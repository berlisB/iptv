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

Env :
  INCLUDE_MASTER=1   teste aussi iptv-org/index.m3u (lent)
  MAX_CHANNELS=N     plafond de flux testés (def 6000) ; le surplus est LOGUÉ
  CONCURRENCY=N      requêtes simultanées (def 80)
  TIMEOUT=N          timeout par flux en s (def 8)
"""
import asyncio
import datetime
import json
import os
import re
import sys
import aiohttp

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
    "entertainment": "Divertissement", "general": "Divertissement",
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

# Mots-clés du NOM d'une chaîne → catégorie (quand le group-title est un pays).
NAME_KEYWORDS = [
    (("news", "info", "noticias", "nachrichten", "24/7 ", " 24",), "Actualités"),
    (("sport", "espn", "motor", "racing", "fight", "wrestling", "poker",
      "golf", "tennis", "soccer", "football", "nba", "nfl", "mlb"), "Sport"),
    (("kids", "junior", "cartoon", "toon", "anime", "baby", "teen"), "Enfants"),
    (("music", "mtv", "hits", "radio", "vevo", "karaoke"), "Musique"),
    (("doc", "nature", "wild", "history", "science", "discovery", "planet",
      "geo", "crime "), "Documentaires"),
    (("cine", "movie", "film", "series", "drama", "thriller", "action",
      "western", "hollywood"), "Films & Séries"),
    (("cook", "food", "travel", "fashion", "home", "lifestyle"), "Lifestyle"),
    (("comedy", "humor", "fun ", "gameshow", "reality"), "Divertissement"),
    (("xxx", "porn", "adult", "18+", "milf", "erotic", "erotik", "babes",
      "playboy", "hustler", "dorcel", "redlight", "venus", "cam girl",
      "camtv", "naked"), "Adulte 🔞"),
]

# Tokens de qualité retirés du nom pour l'identité (pas de regex \b : son
# comportement diverge entre Python et Dart sur les caractères accentués).
QUALITY_TOKENS = {"4k", "uhd", "fhd", "hd", "sd",
                  "1080", "1080p", "720", "720p", "480", "480p"}
_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")

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


def parse_extinf(line):
    """Extrait tvg-id/logo/language/group + nom (après la dernière virgule
    hors attributs)."""
    meta = {k: (rx.search(line).group(1) if rx.search(line) else "")
            for k, rx in _EXTINF_ATTRS.items()}
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


def classify(meta):
    """(country ISO-2, category) depuis group-title + nom + tvg-id."""
    group = meta["group"].strip().lower()
    name = meta["name"].lower()
    tvg_id = meta["tvg_id"]

    country = COUNTRY_ISO.get(group, "")
    if not country and "." in tvg_id:
        suffix = tvg_id.rsplit(".", 1)[-1].lower()
        if len(suffix) == 2 and suffix.isalpha():
            country = "GB" if suffix == "uk" else suffix.upper()

    # group-title = genre → mapping direct (exact puis contains).
    if group and group not in COUNTRY_ISO:
        if group in CATEGORY_MAP:
            return country, CATEGORY_MAP[group]
        for key, cat in CATEGORY_MAP.items():
            if key in group:
                return country, cat

    # group pays (ou inconnu) → mots-clés du nom.
    padded = f" {name} "
    for keywords, cat in NAME_KEYWORDS:
        if any(kw in padded for kw in keywords):
            return country, cat
    return country, "Général"


def channel_id(tvg_id, name):
    return tvg_id.lower() if tvg_id else f"n-{fnv1a64_hex(normalize_name(name))}"


def build_catalog(alive):
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
            country, category = classify(meta)
            if src in ADULT_SOURCES:
                category = "Adulte 🔞"
            lang = meta["language"].split(";")[0].strip().lower()
            by_id[cid] = {
                "id": cid,
                "name": meta["name"],
                "logo": meta["logo"],
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


def curated_category(c):
    cat = c.get("category", "")
    if cat in CURATED_CAT_MAP:
        return CURATED_CAT_MAP[cat]
    if cat == "TV Chine" and (c.get("country") == "CN"
                              or c.get("language") == "zh"):
        return "TV Chine"
    meta = {"group": "", "name": c["name"], "tvg_id": c.get("tvgId", ""),
            "language": c.get("language", ""), "logo": ""}
    return classify(meta)[1]


def merge_curated(channels, by_id):
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
                "category": curated_category(c),
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
            entry["category"] = curated_category(c)
        entry["curated"] = True
        entry["priority"] = c.get("priority", 99)


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
    print(f"Écrit catalog.json — {len(channels)} chaînes ({top})")


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


async def fetch_text(session, url):
    try:
        async with session.get(url, headers=UA) as r:
            if r.status == 200:
                return await r.text(errors="ignore")
    except Exception as e:  # noqa: BLE001
        print(f"  [skip source] {url} ({e})", file=sys.stderr)
    return ""


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
        # 1) récupérer toutes les playlists sources
        sources = list(FREE_SERVICES) + list(ADULT_SOURCES)
        if include_master:
            sources.append(MASTER_INDEX)
        texts = await asyncio.gather(*(fetch_text(session, u) for u in sources))

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

    with open("verified.m3u", "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n")
        f.write(f"# Généré par tools/healthcheck.py — {len(alive)} flux vérifiés "
                f"vivants. Sources 100% légales (FAST + broadcasters officiels).\n")
        for ext, url, _src in alive:
            f.write(f"{ext}\n{url}\n")

    print("Écrit verified.m3u")

    # 4) catalog.json v3 : dédup par identité, classification, fusion curée
    channels, by_id = build_catalog(alive)
    merge_curated(channels, by_id)
    channels.sort(key=lambda c: (0 if c.get("curated") else 1,
                                 c.get("priority", 99), c["name"].lower()))
    write_catalog(channels)


if __name__ == "__main__":
    asyncio.run(main())
