#!/usr/bin/env python3
"""
Health-check des sources IPTV légales -> publie verified.m3u (chaînes vivantes).

Stratégie alignée avec la règle produit "fiabilité" :
- on teste UNIQUEMENT la connectivité réelle de chaque flux (HEAD/GET range) ;
- un flux qui répond 200/206 et renvoie des octets est "vivant" ;
- on ne garde dans verified.m3u que les paires #EXTINF + URL qui passent.

Sources testées = les mêmes que l'app (services FAST propres + broadcasters
officiels). L'index iptv-org (~8000) est optionnel (INCLUDE_MASTER=1) car volu-
mineux. Aucune source piratée n'est testée ni publiée.

Classification : les FAST groupent leurs playlists par PAYS, le genre n'est
donc pas dans le M3U. tools/enrich.py va le chercher à la source (taxonomie du
provider + index iptv-org) et classify() l'applique par autorité décroissante.

Env :
  INCLUDE_MASTER=1   teste aussi iptv-org/index.m3u (~11000 flux, +10 min)
  MAX_CHANNELS=N     plafond de flux testés (def 6000) ; le surplus est LOGUÉ
  CONCURRENCY=N      requêtes simultanées (def 80)
  TIMEOUT=N          timeout par flux en s (def 8)
  MAX_SHRINK=0.20    perte de chaînes tolérée vs catalogue publié (def 20%)
  ALLOW_SHRINK=1     publie malgré une perte au-delà du seuil
"""
import asyncio
import datetime
import json
import os
import re
import sys
import aiohttp

import enrich

OFFICIAL_BROADCASTERS = """\
#EXTM3U
#EXTINF:-1 tvg-id="Arte.fr" group-title="Officiel",Arte
https://artesimulcast.akamaized.net/hls/live/2031003/artelive_fr/index.m3u8
#EXTINF:-1 tvg-id="France5.fr" group-title="Officiel",France 5
https://s13.tntendirect.com/france5/live/playlist.m3u8
#EXTINF:-1 tvg-id="TV5MondeFBS.fr" group-title="Officiel",TV5 Monde FBS
https://ott.tv5monde.com/Content/HLS/Live/channel(fbs)/index.m3u8
#EXTINF:-1 tvg-id="TV5MondeInfo.fr" group-title="Officiel",TV5 Monde Info
https://ott.tv5monde.com/Content/HLS/Live/channel(info)/index.m3u8
#EXTINF:-1 tvg-id="BFMTV.fr" group-title="Officiel",BFMTV
https://bcovlive-a.akamaihd.net/f3c53617100e4fd7a0fbdf9e784a650e/eu-central-1/876450610001/playlist.m3u8
#EXTINF:-1 tvg-id="NASATV.us" group-title="Officiel",NASA TV
https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8
#EXTINF:-1 tvg-id="EuronewsEnglish.fr" group-title="Officiel",Euronews English
https://cdn-euronews.akamaized.net/live/eds/euronews-en/25002/index.m3u8
#EXTINF:-1 tvg-id="EuronewsFrench.fr" group-title="Officiel",Euronews Français
https://cdn-euronews.akamaized.net/live/eds/euronews-fr/25026/index.m3u8
#EXTINF:-1 tvg-id="DWEnglish.de" group-title="Officiel",DW English
https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/master.m3u8
#EXTINF:-1 tvg-id="France24English.fr" group-title="Officiel",France 24 English
https://live.france24.com/hls/live/2037218/F24_EN_HI_HLS/master_5000.m3u8
#EXTINF:-1 tvg-id="France24French.fr" group-title="Officiel",France 24 Français
https://live.france24.com/hls/live/2037179/F24_FR_HI_HLS/master_5000.m3u8
#EXTINF:-1 tvg-id="AlJazeeraEnglish.qa" group-title="Officiel",Al Jazeera English
https://live-hls-web-aje.getaj.net/AJE/index.m3u8
#EXTINF:-1 tvg-id="AlJazeera.qa" group-title="Officiel",Al Jazeera Arabic
https://live-hls-web-aja.getaj.net/AJA-V3/index.m3u8
#EXTINF:-1 tvg-id="ABCNewsLive.us" group-title="Officiel",ABC News Live
https://abcnews-streams.akamaized.net/hls/live/2023560/abcnewshudson1/master.m3u8
"""

BUDDY = ("https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/"
         "refs/heads/main/playlists")
APSATT = "https://www.apsattv.com"

FREE_SERVICES = [
    "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8",
    "https://raw.githubusercontent.com/freecasthub/public-iptv/main/playlist.m3u",
    f"{BUDDY}/plutotv_all.m3u",
    f"{BUDDY}/samsungtvplus_all.m3u",
    f"{BUDDY}/plex_all.m3u",
    f"{BUDDY}/roku_all.m3u",
    f"{BUDDY}/tubi_all.m3u",
    "https://raw.githubusercontent.com/BuddyChewChew/xumo-playlist-generator/"
    "refs/heads/main/playlists/xumo_playlist.m3u",
    f"{APSATT}/distro.m3u",
    f"{APSATT}/localnow.m3u",
    f"{APSATT}/vidaa.m3u",
    f"{APSATT}/vizio.m3u",
    f"{APSATT}/tclplus.m3u",
    f"{APSATT}/frlg.m3u",
]
# Flux adultes (promos gratuites de réseaux cam). Catégorie forcée
# 'Adulte 🔞' → masqués par défaut dans l'app (toggle Réglages).
ADULT_SOURCES = [
    "http://adultiptv.net/chs.m3u8",
]
MASTER_INDEX = "https://iptv-org.github.io/iptv/index.m3u"

UA = {"User-Agent": "iptv-healthcheck/1.0 (+https://github.com/berlisB/iptv)"}

CURATED_JSON = os.path.join(os.path.dirname(__file__), "..",
                            "assets", "catalog", "channels.json")

# ---------------------------------------------------------------------------
# catalog.json v3 — identité stable, classification, providers
# ---------------------------------------------------------------------------

# Provider déduit de l'URL de la playlist source.
SOURCE_PROVIDERS = [
    ("plutotv_all", "pluto"), ("samsungtvplus_all", "samsung"),
    ("plex_all", "plex"), ("roku_all", "roku"), ("tubi_all", "tubi"),
    ("xumo", "xumo"),
]
# Provider déduit de l'URL du flux lui-même (redirections mjh.nz).
STREAM_PROVIDERS = [
    ("jmp2.uk/plu-", "pluto"), ("jmp2.uk/stvp-", "samsung"),
    ("jmp2.uk/plex-", "plex"), ("jmp2.uk/rok-", "roku"),
    ("i.mjh.nz/PlutoTV", "pluto"), ("i.mjh.nz/SamsungTVPlus", "samsung"),
    ("pluto.tv", "pluto"),
]

# Miroir de _categoryMap (lib/features/home/provider/home_provider.dart) —
# mêmes cibles, sans le bug 'satellite'→'TV Chine'.
CATEGORY_MAP = {
    "news": "Actualités", "information": "Actualités", "noticias": "Actualités",
    "nachrichten": "Actualités", "weather": "Actualités", "météo": "Actualités",
    "sports": "Sport", "sport": "Sport", "deportes": "Sport",
    "football": "Sport",
    "movies": "Films & Séries", "cinema": "Films & Séries",
    "films": "Films & Séries", "series": "Films & Séries",
    "drama": "Films & Séries", "thriller": "Films & Séries",
    "action": "Films & Séries", "horror": "Films & Séries",
    "romance": "Films & Séries", "crime": "Films & Séries",
    "mystery": "Films & Séries", "sci-fi": "Films & Séries",
    "western": "Films & Séries", "war": "Films & Séries",
    "entertainment": "Divertissement",
    "variety": "Divertissement", "comedy": "Divertissement",
    "reality": "Divertissement", "game": "Divertissement",
    "talk": "Divertissement", "classic": "Divertissement",
    "kids": "Enfants", "children": "Enfants", "animation": "Enfants",
    "cartoon": "Enfants", "family": "Enfants", "enfant": "Enfants",
    "jeunesse": "Enfants",
    "music": "Musique", "musique": "Musique",
    "documentary": "Documentaires", "science": "Documentaires",
    "nature": "Documentaires", "history": "Documentaires",
    "education": "Documentaires", "culture": "Documentaires",
    "discovery": "Documentaires",
    "lifestyle": "Lifestyle", "cooking": "Lifestyle", "food": "Lifestyle",
    "travel": "Lifestyle", "fashion": "Lifestyle", "home": "Lifestyle",
    "garden": "Lifestyle", "diy": "Lifestyle", "health": "Lifestyle",
    "wellness": "Lifestyle", "outdoor": "Lifestyle", "adventure": "Lifestyle",
    "relax": "Lifestyle",
    "business": "Business", "finance": "Business",
    "religious": "Religion", "religion": "Religion", "spiritual": "Religion",
    "shop": "Shopping", "shopping": "Shopping",
    "auto": "Auto & Tech", "automotive": "Auto & Tech",
    "technology": "Auto & Tech",
    "legislative": "Politique", "political": "Politique",
    "xxx": "Adulte 🔞", "adult": "Adulte 🔞", "+18": "Adulte 🔞",
    "porn": "Adulte 🔞",
    "tv chine": "TV Chine", "chinese": "TV Chine", "china": "TV Chine",
    "cctv": "TV Chine",
}

# group-title qui ne portent aucune information : on les traverse sans rien
# décider, pour laisser l'index iptv-org puis les mots-clés du nom trancher.
# Sans ce garde-fou, les 2653 chaînes group-title="General" de l'index
# iptv-org écrasaient un genre connu par un fourre-tout.
UNINFORMATIVE_GROUPS = {
    "general", "undefined", "uncategorized", "autres", "other", "others",
    "misc", "miscellaneous", "n/a", "na", "unknown", "divers", "generale",
    "général", "générale", "tv", "iptv", "live", "channels",
}

# group-title « pays » → ISO-2 (les FAST listent leurs chaînes par pays).
COUNTRY_ISO = {
    "argentina": "AR", "australia": "AU", "austria": "AT", "belgium": "BE",
    "brazil": "BR", "bulgaria": "BG", "canada": "CA", "chile": "CL",
    "china": "CN", "colombia": "CO", "costa rica": "CR", "croatia": "HR",
    "czech republic": "CZ", "czechia": "CZ", "denmark": "DK",
    "dominican republic": "DO", "ecuador": "EC", "egypt": "EG",
    "estonia": "EE", "finland": "FI", "france": "FR", "germany": "DE",
    "greece": "GR", "hong kong": "HK", "hungary": "HU", "iceland": "IS",
    "india": "IN", "indonesia": "ID", "ireland": "IE", "israel": "IL",
    "italy": "IT", "japan": "JP", "kenya": "KE", "south korea": "KR",
    "latvia": "LV", "lithuania": "LT", "luxembourg": "LU",
    "malaysia": "MY", "mexico": "MX", "morocco": "MA", "netherlands": "NL",
    "new zealand": "NZ", "nigeria": "NG", "norway": "NO", "pakistan": "PK",
    "peru": "PE", "philippines": "PH", "poland": "PL", "portugal": "PT",
    "qatar": "QA", "romania": "RO", "russia": "RU", "saudi arabia": "SA",
    "senegal": "SN", "serbia": "RS", "singapore": "SG", "slovakia": "SK",
    "slovenia": "SI", "south africa": "ZA", "spain": "ES",
    "sweden": "SE", "switzerland": "CH", "taiwan": "TW", "thailand": "TH",
    "tunisia": "TN", "turkey": "TR", "ukraine": "UA",
    "united arab emirates": "AE", "united kingdom": "GB",
    "united states": "US", "united states of america": "US",
    "uruguay": "UY", "venezuela": "VE", "vietnam": "VN",
    "usa": "US", "uk": "GB", "uae": "AE",
}

# Mots-clés du NOM d'une chaîne → catégorie. Dernier recours, quand ni le
# provider ni iptv-org ne connaissent la chaîne (typiquement Plex, dont le
# .channels.json ne porte aucun genre, et les sources sans tvg-id).
#
# L'ordre compte : la première famille qui matche gagne, donc on va du plus
# spécifique au plus générique. « Adulte 🔞 » passe en tête pour qu'une chaîne
# érotique ne soit jamais classée ailleurs par un mot générique ; Shopping
# avant Lifestyle sinon « Home Shopping Network » tombe dans Lifestyle sur
# « home » ; Sport avant Films & Séries sinon « Action Sports » devient un
# film d'action.
NAME_KEYWORDS = [
    (("xxx", "porn", "adult", "18+", "milf", "erotic", "erotik", "babes",
      "playboy", "hustler", "dorcel", "redlight", "venus", "cam girl",
      "camtv", "naked", "brazzers", "penthouse", "sexy", "seduction",
      "blue movie", "vivid", "private tv"), "Adulte 🔞"),
    (("shop", "shopping", "teleshop", "qvc", "hsn", "auction", "bid ",
      "market"), "Shopping"),
    (("church", "gospel", "islam", "quran", "coran", "bible", "faith",
      "jesus", "christ", "catholic", "vatican", "hindu", "buddh",
      "prayer", "prière", "religio", "spiritual", "mecca", "sunna",
      "ewtn", "daystar"), "Religion"),
    (("sport", "espn", "motor", "racing", "fight", "wrestling", "poker",
      "golf", "tennis", "soccer", "football", "nba", "nfl", "mlb", "nhl",
      "rugby", "cricket", "boxing", "ufc", "mma", "cycling", "athletic",
      "olympic", "basket", "baseball", "hockey", "surf", "skate", "fitness",
      "gym", "darts", "billiard", "snooker", "bein", "dazn", "eurosport",
      "formula", "f1 ", "nascar", "motogp", "rally", "esport", "gaming"),
     "Sport"),
    # ⚠️ Ne JAMAIS remettre "24/7 " ni " 24" ici. Ils visaient France 24, mais
    # iptv-org suffixe ses chaînes d'un marqueur de disponibilité « [Not 24/7] »
    # qui n'a rien à voir avec l'information : ces deux mots-clés envoyaient
    # 465 chaînes quelconques dans Actualités. Les vraies chaînes « 24 » sont
    # nommées explicitement ci-dessous.
    (("news", "info", "noticias", "nachrichten", "notizie", "nieuws",
      "nyheter", "actu", "journal", "press", "report",
      "bulletin", "weather", "meteo", "météo", "politic", "parliament",
      "senate", "congress", "cnn", "bbc news", "sky news", "msnbc",
      "fox news", "newsmax", "bloomberg", "cnbc", "reuters", "afp",
      "france 24", "france24", "i24", "rai news", "tv24", "24 news",
      "news 24", "kanal 24", "canal 24"),
     "Actualités"),
    (("kids", "junior", "cartoon", "toon", "baby", "teen", "nick",
      "disney", "boomerang", "pokemon", "peppa", "barbie", "lego",
      "sesame", "cbeebies", "kika", "gulli", "tiji", "piwi", "enfant",
      "niño", "bambin", "child", "preschool"), "Enfants"),
    (("music", "mtv", "hits", "radio", "vevo", "karaoke", "musique",
      "musica", "musik", "jazz", "blues", "rock", "pop ", "classical",
      "opera", "reggae", "salsa", "hip hop", "hip-hop", "rap ", "country",
      "dance", "electro", "techno", "chill", "lounge", "ambient",
      "concert", "billboard", "trax", "melody"), "Musique"),
    (("doc", "nature", "wild", "history", "histoire", "science", "discovery",
      "planet", "geo", "crime ", "true crime", "animal", "ocean", "space",
      "cosmos", "explorer", "investigat", "forensic", "archeo", "museum",
      "curiosity", "knowledge", "savoir", "wissen", "natgeo",
      "national geographic", "smithsonian", "pbs", "arte"), "Documentaires"),
    (("cine", "movie", "film", "series", "série", "serie", "drama",
      "thriller", "action", "western", "hollywood", "bollywood", "horror",
      "terror", "sci-fi", "scifi", "fantasy", "anime", "manga", "novela",
      "telenovela", "sitcom", "classic tv", "mystery", "suspense",
      "romance", "blockbuster", "premiere", "box office", "amc", "tnt",
      "sundance", "mgm", "paramount", "sony", "warner", "universal"),
     "Films & Séries"),
    (("cook", "food", "travel", "fashion", "home", "lifestyle", "garden",
      "diy", "craft", "health", "wellness", "yoga", "beauty", "style",
      "decor", "house", "real estate", "voyage", "cuisine", "chef",
      "recipe", "gourmet", "wine", "outdoor", "fishing", "hunting",
      "camping", "pet ", "dog ", "cat "), "Lifestyle"),
    (("comedy", "humor", "humour", "fun ", "gameshow", "game show",
      "reality", "talk", "variety", "laugh", "sitcom", "stand up",
      "stand-up", "prank", "fail", "quiz", "celebrity", "gossip",
      "showbiz", "award"), "Divertissement"),
    (("business", "finance", "money", "economy", "stock", "invest",
      "trading", "entrepreneur"), "Business"),
    (("auto", "car ", "cars ", "truck", "moto ", "garage", "gadget",
      "computer"), "Auto & Tech"),
]

# Tokens de qualité retirés du nom pour l'identité (pas de regex \b : son
# comportement diverge entre Python et Dart sur les caractères accentués).
QUALITY_TOKENS = {"4k", "uhd", "fhd", "hd", "sd",
                  "1080", "1080p", "720", "720p", "480", "480p"}
_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")

# Affilié local américain : « Very Alabama by WVTM », « Denver News by KMGH ».
# Les indicatifs FCC commencent tous par W (est du Mississippi) ou K (ouest).
_US_AFFILIATE_RE = re.compile(r"\bby [WK][A-Z]{2,3}\b")

# Marqueurs techniques accolés au nom par iptv-org : « (1080p) », « [Not 24/7] »,
# « [Geo-blocked] ». Ils décrivent le FLUX, pas le contenu, et empoisonnaient la
# recherche par mots-clés — « [Not 24/7] » suffisait à faire d'une chaîne
# quelconque une chaîne d'information.
_NAME_MARKER_RE = re.compile(r"[\[(][^\])]*[\])]")

_EXTINF_ATTRS = {
    "tvg_id": re.compile(r'tvg-id="([^"]*)"'),
    "logo": re.compile(r'tvg-logo="([^"]*)"'),
    "language": re.compile(r'tvg-language="([^"]*)"'),
    "group": re.compile(r'group-title="([^"]*)"'),
}


def normalize_name(name):
    """Nom → clé d'identité : lowercase, sans qualité/ponctuation.
    DOIT rester identique à normalizeName de lib/core/utils/stable_id.dart."""
    tokens = _NON_ALNUM_RE.sub(" ", name.lower()).split()
    return " ".join(t for t in tokens if t not in QUALITY_TOKENS)


def fnv1a64_hex(text):
    """FNV-1a 64 bits, hex sur 16 caractères.
    DOIT rester identique à fnv1a64Hex de lib/core/utils/stable_id.dart."""
    h = 0xCBF29CE484222325
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return format(h, "016x")


def strip_feed_suffix(tvg_id):
    """Retire le suffixe de flux des tvg-id de l'index iptv-org.

    L'index publie une entrée par variante de qualité : « 00sReplay.us@SD » et
    « 00sReplay.us@HD » désignent la MÊME chaîne. Sans ce nettoyage :
      - l'identité éclate en deux chaînes au lieu d'une à deux URLs ;
      - l'extraction du pays lit « us@sd » et échoue ;
      - la jointure avec l'API iptv-org, qui expose « 00sReplay.us », rate.

    La casse est volontairement préservée : EpgIdMapping (Dart) indexe des clés
    sensibles à la casse comme 'France24English.fr'.
    DOIT rester identique à stripFeedSuffix de lib/core/utils/stable_id.dart.
    """
    return tvg_id.split("@", 1)[0].strip()


def parse_extinf(line):
    """Extrait tvg-id/logo/language/group + nom (après la dernière virgule
    hors attributs)."""
    meta = {k: (rx.search(line).group(1) if rx.search(line) else "")
            for k, rx in _EXTINF_ATTRS.items()}
    meta["tvg_id"] = strip_feed_suffix(meta["tvg_id"])
    # Le nom = tout ce qui suit la virgule terminant les attributs.
    name_match = re.search(r'(?:"|:-?\d+)\s*,\s*(.+)$', line)
    meta["name"] = (name_match.group(1) if name_match else "").strip()
    return meta


def tag_adult(ext):
    """Force group-title="XXX" sur les EXTINF des sources adultes, pour que
    verified.m3u soit lui aussi filtré par le toggle adulte de l'app."""
    if 'group-title="' in ext:
        return re.sub(r'group-title="[^"]*"', 'group-title="XXX"', ext)
    return re.sub(r"^(#EXTINF:[^,]*),", r'\1 group-title="XXX",', ext, count=1)


def provider_for(source_url, stream_url):
    for needle, prov in STREAM_PROVIDERS:
        if needle in stream_url:
            return prov
    for needle, prov in SOURCE_PROVIDERS:
        if needle in source_url:
            return prov
    if source_url == "official":
        return "official"
    return "other"


def classify(meta, index=None):
    """(country ISO-2, category) par cascade d'autorité décroissante.

    1. le genre publié par le provider pour SA chaîne (Pluto, Samsung, Roku) ;
    2. le group-title de la playlist source, quand c'est un genre et non un
       pays (Roku, Tubi, Free-TV, index iptv-org) ;
    3. l'index communautaire iptv-org, sur les tvg-id pointés ;
    4. les décrochages locaux américains, reconnaissables à leur nommage ;
    5. les mots-clés du nom ;
    6. « Général », qui devient un vrai aveu d'ignorance et non un fourre-tout.
    """
    group = meta["group"].strip().lower()
    name = meta["name"].lower()
    tvg_id = meta["tvg_id"]

    country = COUNTRY_ISO.get(group, "")
    if not country and "." in tvg_id:
        suffix = tvg_id.rsplit(".", 1)[-1].lower()
        if len(suffix) == 2 and suffix.isalpha():
            country = "GB" if suffix == "uk" else suffix.upper()
    if not country and index:
        country = index.country_for(tvg_id)

    # 1. taxonomie du provider — il connaît ses chaînes mieux que nous.
    if index:
        category = index.provider_category(tvg_id)
        if category:
            return country, category

    # 2. group-title = genre → mapping direct (exact puis contains).
    if group and group not in COUNTRY_ISO and group not in UNINFORMATIVE_GROUPS:
        if group in CATEGORY_MAP:
            return country, CATEGORY_MAP[group]
        for key, cat in CATEGORY_MAP.items():
            if key in group:
                return country, cat

    # 3. index iptv-org.
    if index:
        category = index.org_category(tvg_id)
        if category:
            return country, category

    # 4. décrochages locaux américains : le service LocalNow préfixe ses ids
    # par « LN_ », et les affiliés se nomment « … by WVTM » / « … by KTLA »
    # (indicatifs FCC, toujours en W ou K). Ce sont des chaînes d'info locale.
    if tvg_id.startswith("LN_") or _US_AFFILIATE_RE.search(meta["name"]):
        return country or "US", "Actualités"

    # 5. mots-clés du nom, marqueurs de flux retirés au préalable.
    padded = f" {_NAME_MARKER_RE.sub(' ', name)} "
    for keywords, cat in NAME_KEYWORDS:
        if any(kw in padded for kw in keywords):
            return country, cat
    return country, "Général"


def channel_id(tvg_id, name):
    return tvg_id.lower() if tvg_id else f"n-{fnv1a64_hex(normalize_name(name))}"


def build_catalog(alive, index=None):
    """alive = [(extinf, url, source_url)] → liste de chaînes v3 dédupliquées
    par identité, URLs mergées (cap 6, ordre de découverte = officiel d'abord)."""
    by_id = {}
    order = []
    for ext, url, src in alive:
        meta = parse_extinf(ext)
        if not meta["name"]:
            continue
        cid = channel_id(meta["tvg_id"], meta["name"])
        entry = by_id.get(cid)
        if entry is None:
            country, category = classify(meta, index)
            if src in ADULT_SOURCES:
                category = "Adulte 🔞"
            # iptv-org marque le NSFW indépendamment du genre : une chaîne
            # signalée reste derrière le toggle adulte de l'app même si sa
            # catégorie annoncée est anodine.
            elif index and index.is_nsfw(meta["tvg_id"]):
                category = "Adulte 🔞"
            lang = meta["language"].split(";")[0].strip().lower()
            by_id[cid] = {
                "id": cid,
                "name": meta["name"],
                # Le provider a souvent un logo là où la playlist n'en a pas.
                "logo": (meta["logo"]
                         or (index.logo_for(meta["tvg_id"]) if index else "")),
                "tvgId": meta["tvg_id"],
                "country": country,
                "category": category,
                "language": lang,
                "provider": provider_for(src, url),
                "urls": [url],
            }
            order.append(cid)
        else:
            if len(entry["urls"]) < 6 and url not in entry["urls"]:
                entry["urls"].append(url)
            if not entry["logo"] and meta["logo"]:
                entry["logo"] = meta["logo"]
            if not entry["tvgId"] and meta["tvg_id"]:
                entry["tvgId"] = meta["tvg_id"]
    return [by_id[cid] for cid in order], by_id


# Libellés éditoriaux de channels.json → vocabulaire canonique. Les libellés
# d'audience ('Anglais utile', 'Francophone'…) et les erreurs de saisie
# ('TV Chine' sur des chaînes non chinoises) sont reclassés par classify().
CURATED_CAT_MAP = {
    "Infos": "Actualités", "Actualités": "Actualités",
    "Sport gratuit": "Sport", "Films & Séries": "Films & Séries",
    "Documentaires": "Documentaires", "Enfants": "Enfants",
    "Musique": "Musique",
}


def curated_category(c, index=None):
    cat = c.get("category", "")
    if cat in CURATED_CAT_MAP:
        return CURATED_CAT_MAP[cat]
    if cat == "TV Chine" and (c.get("country") == "CN"
                              or c.get("language") == "zh"):
        return "TV Chine"
    meta = {"group": "", "name": c["name"], "tvg_id": c.get("tvgId", ""),
            "language": c.get("language", ""), "logo": ""}
    return classify(meta, index)[1]


def merge_curated(channels, by_id, index=None):
    """Fusionne assets/catalog/channels.json : les chaînes éditoriales gagnent
    curated/priority, leur URL passe en tête, et héritent des backups FAST."""
    try:
        with open(CURATED_JSON, encoding="utf-8") as f:
            curated = json.load(f).get("channels", [])
    except OSError as e:
        print(f"  [curated] introuvable ({e}) — ignoré", file=sys.stderr)
        return
    for c in curated:
        cid = channel_id(c.get("tvgId", ""), c["name"])
        entry = by_id.get(cid)
        if entry is None:
            entry = {
                "id": cid,
                "name": c["name"],
                "logo": c.get("logo", ""),
                "tvgId": c.get("tvgId", ""),
                "country": c.get("country", ""),
                "category": curated_category(c, index),
                "language": c.get("language", ""),
                "provider": "curated",
                "urls": [c["streamUrl"]],
            }
            by_id[cid] = entry
            channels.append(entry)
        else:
            urls = [c["streamUrl"]] + [u for u in entry["urls"]
                                       if u != c["streamUrl"]]
            entry["urls"] = urls[:6]
            entry["provider"] = "curated"
            entry["category"] = curated_category(c, index)
        entry["curated"] = True
        entry["priority"] = c.get("priority", 99)


def previous_channel_count():
    """Nombre de chaînes du catalogue actuellement publié, 0 s'il n'y en a pas."""
    try:
        with open("catalog.json", encoding="utf-8") as f:
            return len(json.load(f).get("channels", []))
    except (OSError, ValueError):
        return 0


def shrink_refused(channels):
    """Vrai s'il faut REFUSER de publier ce catalogue car il a trop rétréci.

    Une source injoignable emporte toutes ses chaînes d'un coup : le run du
    2026-09-12 aurait publié un catalogue amputé de 3043 chaînes parce que
    apsattv ne répondait pas. Sans ce garde-fou, une panne passagère chez un
    fournisseur dégrade l'app pour tout le monde jusqu'au run suivant.

    Mieux vaut garder le catalogue précédent, encore valide, que publier un
    catalogue appauvri. `ALLOW_SHRINK=1` force la publication quand la perte
    est réelle et définitive (un service qui ferme).
    """
    if os.getenv("ALLOW_SHRINK") == "1":
        return False
    previous = previous_channel_count()
    if previous == 0:
        return False
    max_shrink = float(os.getenv("MAX_SHRINK", "0.20"))
    drop = (previous - len(channels)) / previous
    if drop <= max_shrink:
        return False
    print(f"⚠ PUBLICATION REFUSÉE : {len(channels)} chaînes contre {previous} "
          f"précédemment ({drop:.0%} de perte, seuil {max_shrink:.0%}).",
          file=sys.stderr)
    if FAILED_SOURCES:
        print(f"  Cause probable : {len(FAILED_SOURCES)} source(s) "
              f"injoignable(s) ci-dessus.", file=sys.stderr)
    print("  Le catalogue précédent est conservé. Pour publier malgré tout : "
          "ALLOW_SHRINK=1", file=sys.stderr)
    return True


def write_catalog(channels):
    payload = {
        "version": 3,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "channels": channels,
    }
    with open("catalog.json", "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    cats = {}
    for c in channels:
        cats[c["category"]] = cats.get(c["category"], 0) + 1
    top = ", ".join(f"{k}:{v}" for k, v in
                    sorted(cats.items(), key=lambda kv: -kv[1])[:8])
    total = max(1, len(channels))
    # Le taux de « Général » est l'indicateur de santé de la classification :
    # s'il remonte, c'est qu'une source d'enrichissement a lâché.
    unclassified = 100 * cats.get("Général", 0) // total
    no_logo = 100 * sum(1 for c in channels if not c["logo"]) // total
    print(f"Écrit catalog.json — {len(channels)} chaînes ({top})")
    print(f"  Général : {unclassified}% — sans logo : {no_logo}%")


def parse_m3u(text):
    """Retourne une liste de (extinf_line, url). Ignore les en-têtes/commentaires."""
    pairs = []
    pending = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTINF"):
            pending = line
        elif line.startswith("#"):
            continue
        else:
            # ligne d'URL ; on garde l'EXTINF si présent, sinon on en fabrique un
            pairs.append((pending or f"#EXTINF:-1,{line[:40]}", line))
            pending = None
    return pairs


# Récupération des playlists sources. Une source perdue coûte TOUTES ses
# chaînes d'un coup — l'incident du 2026-09-12 sur apsattv en a fait perdre
# 3043 — donc on réessaie avant d'abandonner, et l'échec est rendu visible
# dans le résumé plutôt que noyé dans stderr.
SOURCE_ATTEMPTS = 3
SOURCE_TIMEOUT = 45

# Sources qui n'ont pas pu être lues sur ce run.
FAILED_SOURCES = []


async def fetch_text(session, url):
    last_error = "statut inattendu"
    for attempt in range(1, SOURCE_ATTEMPTS + 1):
        try:
            async with session.get(
                url,
                headers=UA,
                allow_redirects=True,
                timeout=aiohttp.ClientTimeout(total=SOURCE_TIMEOUT),
            ) as r:
                if r.status == 200:
                    return await r.text(errors="ignore")
                last_error = f"HTTP {r.status}"
        except Exception as e:  # noqa: BLE001
            last_error = str(e) or e.__class__.__name__
        if attempt < SOURCE_ATTEMPTS:
            # Backoff court : on vise le hoquet réseau passager, pas un hôte
            # durablement mort qui ne ferait qu'allonger le job.
            await asyncio.sleep(2 * attempt)
    print(f"  [source perdue] {url} ({last_error})", file=sys.stderr)
    FAILED_SOURCES.append(url)
    return ""


async def fetch_json(session, url):
    """JSON d'enrichissement, ou None. Jamais d'exception : une source de
    métadonnées absente dégrade la classification, elle ne casse pas la CI."""
    try:
        async with session.get(url, headers=UA, allow_redirects=True,
                               timeout=aiohttp.ClientTimeout(total=120)) as r:
            if r.status != 200:
                print(f"  [enrich] {url} → HTTP {r.status}", file=sys.stderr)
                return None
            return json.loads(await r.text(errors="ignore"))
    except Exception as e:  # noqa: BLE001
        print(f"  [enrich] {url} ({e})", file=sys.stderr)
        return None


async def is_alive(session, url, timeout):
    """Vivant si 200/206 + octets reçus ; pour HLS, exige du contenu #EXT."""
    headers = dict(UA)
    headers["Range"] = "bytes=0-2047"
    try:
        async with session.get(url, headers=headers,
                               timeout=aiohttp.ClientTimeout(total=timeout)) as r:
            if r.status not in (200, 206):
                return False
            chunk = await r.content.read(2048)
            if not chunk:
                return False
            if ".m3u8" in url.lower() or "mpegurl" in (
                    r.headers.get("content-type", "").lower()):
                return b"#EXT" in chunk
            return True
    except Exception:  # noqa: BLE001
        return False


async def main():
    include_master = os.getenv("INCLUDE_MASTER") == "1"
    max_channels = int(os.getenv("MAX_CHANNELS", "6000"))
    concurrency = int(os.getenv("CONCURRENCY", "80"))
    timeout = int(os.getenv("TIMEOUT", "8"))

    connector = aiohttp.TCPConnector(limit=concurrency, ssl=False)
    async with aiohttp.ClientSession(connector=connector) as session:
        # 1) playlists sources + index d'enrichissement, en parallèle
        sources = list(FREE_SERVICES) + list(ADULT_SOURCES)
        if include_master:
            sources.append(MASTER_INDEX)
        texts, index = await asyncio.gather(
            asyncio.gather(*(fetch_text(session, u) for u in sources)),
            enrich.build_index(lambda u: fetch_json(session, u)),
        )
        print(f"Index d'enrichissement : {len(index.provider)} chaînes "
              f"providers + {len(index.iptv_org)} iptv-org")
        if FAILED_SOURCES:
            print(f"⚠ {len(FAILED_SOURCES)}/{len(sources)} sources "
                  f"injoignables — le catalogue sera incomplet :")
            for url in FAILED_SOURCES:
                print(f"    {url}")

        # triplets (extinf, url, source) — la source sert à déduire le provider
        pairs = [(e, u, "official") for e, u in parse_m3u(OFFICIAL_BROADCASTERS)]
        for src, t in zip(sources, texts):
            if src in ADULT_SOURCES:
                pairs += [(tag_adult(e), u, src) for e, u in parse_m3u(t)]
            else:
                pairs += [(e, u, src) for e, u in parse_m3u(t)]

        # 2) dédup par URL en gardant l'ordre (officiels d'abord)
        seen = set()
        unique = []
        for ext, url, src in pairs:
            if url not in seen:
                seen.add(url)
                unique.append((ext, url, src))

        total = len(unique)
        dropped = 0
        if total > max_channels:
            dropped = total - max_channels
            unique = unique[:max_channels]
        print(f"Sources parsées : {total} flux uniques "
              f"(test de {len(unique)}, {dropped} ignorés par MAX_CHANNELS)")

        # 3) probe concurrent
        sem = asyncio.Semaphore(concurrency)

        async def check(ext, url, src):
            async with sem:
                alive = await is_alive(session, url, timeout)
                return (ext, url, src) if alive else None

        results = await asyncio.gather(*(check(e, u, s) for e, u, s in unique))

    alive = [r for r in results if r]
    print(f"Vivants : {len(alive)}/{len(unique)} "
          f"({100 * len(alive) // max(1, len(unique))}%)")

    # 4) catalog.json v3 : dédup par identité, classification, fusion curée.
    # Construit AVANT toute écriture : le garde-fou anti-rétrécissement doit
    # pouvoir tout annuler, y compris verified.m3u, sans laisser les deux
    # fichiers désynchronisés.
    channels, by_id = build_catalog(alive, index)
    merge_curated(channels, by_id, index)
    channels.sort(key=lambda c: (0 if c.get("curated") else 1,
                                 c.get("priority", 99), c["name"].lower()))

    if shrink_refused(channels):
        # Sortie en succès : ce n'est pas une panne du script, c'est son
        # garde-fou qui joue son rôle. La CI ne commitera rien puisque les
        # fichiers sont inchangés.
        return

    with open("verified.m3u", "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n")
        f.write(f"# Généré par tools/healthcheck.py — {len(alive)} flux vérifiés "
                f"vivants. Sources 100% légales (FAST + broadcasters officiels).\n")
        for ext, url, _src in alive:
            f.write(f"{ext}\n{url}\n")

    print("Écrit verified.m3u")
    write_catalog(channels)


if __name__ == "__main__":
    asyncio.run(main())
