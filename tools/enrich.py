#!/usr/bin/env python3
"""Enrichissement des métadonnées de chaînes (genre, pays, logo, NSFW).

Pourquoi ce module existe
-------------------------
Les services FAST (Pluto, Samsung, Plex, Roku) publient leurs playlists M3U
groupées par **pays** : `group-title="Germany"`, `group-title="South Korea"`…
Le genre n'y figure pas. Résultat, la classification par group-title de
healthcheck.py n'avait rien à mordre sur ~5500 chaînes, qui tombaient toutes
dans « Général ».

Mais ces mêmes providers exposent leur taxonomie de genre dans un JSON séparé,
indexé par l'identifiant qu'on stocke déjà en `tvgId` :

    https://i.mjh.nz/<Provider>/.channels.json

On joint donc sur `tvgId` pour récupérer le genre à la source, plutôt que de
le devenir depuis le nom de la chaîne. L'index iptv-org (identifiants pointés
type `Buzzr.us`) complète pour les broadcasters classiques.

Tout est *fail-soft* : une source injoignable laisse son index vide et le
pipeline continue. La CI ne doit jamais casser pour un enrichissement manquant.
"""
import asyncio
import json

MJH = "https://i.mjh.nz"
# .channels.json par provider. Plex n'expose pas de genre (champs name/logo/
# regions seulement) mais sert pour le pays ; Roku utilise `groups` (pluriel).
PROVIDER_SOURCES = {
    "pluto": f"{MJH}/PlutoTV/.channels.json",
    "samsung": f"{MJH}/SamsungTVPlus/.channels.json",
    "plex": f"{MJH}/Plex/.channels.json",
    "roku": f"{MJH}/Roku/.channels.json",
}
IPTV_ORG_API = "https://iptv-org.github.io/api/channels.json"

# ---------------------------------------------------------------------------
# Taxonomies providers → vocabulaire canonique de l'app
# ---------------------------------------------------------------------------
# Les `group` des FAST sont localisés (Filme, Cinéma, 예능, Dokus & Wissen…),
# d'où une table plate plutôt qu'un mapping par mots-clés : elle est finie
# (~200 valeurs observées sur les 4 providers) et sans ambiguïté.
#
# Les valeurs qui ne sont PAS un genre — buckets marketing (« Nytt på Pluto
# TV »), buckets de langue (« Latino », « En Español ») — sont volontairement
# absentes : elles retombent sur les mots-clés du nom, qui feront mieux.
PROVIDER_GROUP_MAP = {
    # --- Enfants ---
    "kids": "Enfants", "infantil": "Enfants", "niños": "Enfants",
    "bambini": "Enfants", "barn": "Enfants", "for barn": "Enfants",
    "for børn": "Enfants", "jeunesse": "Enfants",
    "kids en français": "Enfants", "nickelodeon": "Enfants",
    "teen": "Enfants", "animation": "Enfants", "animated": "Enfants",
    "animazione": "Enfants", "어린이": "Enfants",
    "faith & family": "Religion",

    # --- Films & Séries ---
    "movies": "Films & Séries", "movie channels": "Films & Séries",
    "filme": "Films & Séries", "film": "Films & Séries",
    "filmes": "Films & Séries", "filmer": "Films & Séries",
    "films": "Films & Séries", "cine": "Films & Séries",
    "cinéma": "Films & Séries", "películas": "Films & Séries",
    "series": "Films & Séries", "serien": "Films & Séries",
    "serie": "Films & Séries", "serie tv": "Films & Séries",
    "séries": "Films & Séries", "séries tv": "Films & Séries",
    "tv series": "Films & Séries", "serien-marathon": "Films & Séries",
    "serie classiche": "Films & Séries",
    "klassiske tv-serier": "Films & Séries",
    "classic tv": "Films & Séries",
    "classic tv comedy": "Films & Séries",
    "western & classic tv": "Films & Séries",
    "drama": "Films & Séries", "tv dramas": "Films & Séries",
    "action & drama": "Films & Séries",
    "bingeable drama": "Films & Séries", "action": "Films & Séries",
    "sitcoms": "Films & Séries", "sitcoms + comedy": "Films & Séries",
    "sci-fi": "Films & Séries", "sci-fi & horror": "Films & Séries",
    "sci-fi & fantasy": "Films & Séries",
    "sci-fi + fantasy": "Films & Séries",
    "sci-fi & supernatural": "Films & Séries",
    "horror": "Films & Séries", "horror e paranormale": "Films & Séries",
    "paranormal": "Films & Séries", "zona paranormal": "Films & Séries",
    "overnaturlig": "Films & Séries", "övernaturligt": "Films & Séries",
    "mistérios e sobrenatural": "Films & Séries",
    "mystery": "Films & Séries", "romance": "Films & Séries",
    "westerns": "Films & Séries", "western": "Films & Séries",
    "novelas": "Films & Séries", "telenovela": "Films & Séries",
    "crime": "Films & Séries", "crime drama": "Films & Séries",
    "serie crime": "Films & Séries", "crimen": "Films & Séries",
    "policiacas": "Films & Séries",
    "séries policières": "Films & Séries",
    "crime & mystère": "Films & Séries",
    "crimen y misterio": "Films & Séries",
    # Anime → Films & Séries et non Enfants : le catalogue va de Doraemon aux
    # seinen, et l'app a déjà une section animés dédiée côté VOD.
    "anime": "Films & Séries",
    "드라마": "Films & Séries", "영화": "Films & Séries",
    "gamla godingar": "Films & Séries", "gamle godbiter": "Films & Séries",
    "retro": "Films & Séries", "retrô": "Films & Séries",
    "emissions cultes": "Films & Séries",
    "south park": "Films & Séries",
    "star trek 60-årsjubileum": "Films & Séries",
    "star trek 60-års jubilæum": "Films & Séries",
    "60 jahre star trek": "Films & Séries",
    "jornada nas estrelas": "Films & Séries",

    # --- Divertissement ---
    "entertainment": "Divertissement",
    "tv & entertainment": "Divertissement",
    "entretenimiento": "Divertissement",
    "intrattenimento": "Divertissement",
    "divertissement": "Divertissement",
    "black entertainment": "Divertissement",
    "comedy": "Divertissement", "comedia": "Divertissement",
    "comédia": "Divertissement", "comédie": "Divertissement",
    "komedi": "Divertissement", "komedie": "Divertissement",
    "humor": "Divertissement", "reality": "Divertissement",
    "reality tv": "Divertissement", "reality show": "Divertissement",
    "realityserier": "Divertissement",
    "competition reality": "Divertissement",
    "reality competition": "Divertissement",
    "competencia": "Divertissement",
    "dansk reality & underholdning": "Divertissement",
    "svensk reality och underhållning": "Divertissement",
    "norsk reality og underholdning": "Divertissement",
    "télé réalité": "Divertissement", "tv réalité": "Divertissement",
    "paradise hotel": "Divertissement",
    "big brother live": "Divertissement",
    "game shows": "Divertissement", "game show": "Divertissement",
    "games & competition": "Divertissement",
    "daytime + game shows": "Divertissement",
    "daytime & talk shows": "Divertissement",
    "talkshow": "Divertissement", "infotainment": "Divertissement",
    "pop culture": "Divertissement",
    "anime & gaming": "Divertissement",
    "mtv": "Divertissement", "mtv en pluto tv": "Divertissement",
    "det bedste fra mtv": "Divertissement",
    "det beste fra mtv": "Divertissement",
    "det bästa från mtv": "Divertissement",
    "예능": "Divertissement",

    # --- Actualités ---
    "news": "Actualités", "news & opinion": "Actualités",
    "news + opinion": "Actualités", "local news": "Actualités",
    "regional news": "Actualités", "hindi news": "Actualités",
    "english news": "Actualités", "global news": "Actualités",
    "national news": "Actualités", "news e mondo": "Actualités",
    "noticias": "Actualités", "notícias": "Actualités",
    "nachrichten": "Actualités", "nyheter": "Actualités",
    "actualités": "Actualités", "weather": "Actualités",
    "뉴스": "Actualités", "시사/교양": "Actualités",

    # --- Documentaires ---
    "documentary": "Documentaires", "documentaries": "Documentaires",
    "documentari": "Documentaires", "documentaires": "Documentaires",
    "documentaire": "Documentaires", "dokumentarer": "Documentaires",
    "dokumentärer": "Documentaires", "documentales": "Documentaires",
    "dokus & wissen": "Documentaires", "dokus + wissen": "Documentaires",
    "documentary + science": "Documentaires",
    "history + science": "Documentaires",
    "nature, history & science": "Documentaires",
    "science & nature": "Documentaires", "nature": "Documentaires",
    "natureza": "Documentaires", "animals": "Documentaires",
    "animals + nature": "Documentaires", "environment": "Documentaires",
    "educational": "Documentaires", "cultura": "Documentaires",
    "curiosidad": "Documentaires", "curiosidades": "Documentaires",
    "real life adventure": "Documentaires",
    # True crime = documentaire d'investigation, pas fiction.
    "true crime": "Documentaires", "investigación": "Documentaires",
    "investigação": "Documentaires",

    # --- Sport ---
    "sport": "Sport", "sports": "Sport",
    "sports & outdoors": "Sport", "sports on now": "Sport",
    "live sports": "Sport", "deportes": "Sport", "deporte": "Sport",
    "esportes": "Sport", "motor sports": "Sport",
    "motori e sport": "Sport", "sports & auto": "Sport",
    "auto & motorsports": "Sport", "fußball": "Sport", "calcio": "Sport",
    "3x3 basketball": "Sport", "스포츠": "Sport",

    # --- Musique ---
    "music": "Musique", "musica": "Musique", "música": "Musique",
    "music videos": "Musique", "musik & ambient": "Musique",
    "music & ambient": "Musique", "musica e ambient": "Musique",
    "música & ambiente": "Musique", "musique et ambiance": "Musique",
    "ambiance": "Musique", "음악": "Musique",

    # --- Lifestyle ---
    "lifestyle": "Lifestyle", "living": "Lifestyle",
    "estilo de vida": "Lifestyle", "home & food": "Lifestyle",
    "home + food": "Lifestyle", "food & travel": "Lifestyle",
    "good eats": "Lifestyle", "cooking": "Lifestyle",
    "cucina & viaggi": "Lifestyle",
    "voyages et gastronomie": "Lifestyle",
    "viajes y cocina": "Lifestyle", "mat & livsstil": "Lifestyle",
    "mad & livsstil": "Lifestyle", "health": "Lifestyle",
    "lifestyle & pop culture": "Lifestyle", "라이프스타일": "Lifestyle",

    # --- Divers ---
    # « À Binge-Watch » est bien un bucket de séries, contrairement aux autres
    # buckets éditoriaux de Pluto qu'on laisse volontairement retomber.
    "à binge-watch": "Films & Séries",
    "art": "Documentaires", "biography": "Documentaires",
    "law": "Documentaires",
    "gaming": "Divertissement", "pro wrestling": "Sport",
    "auto & motor": "Auto & Tech",
    "business news": "Business",
    "devotional": "Religion", "religious": "Religion",
    "auction": "Shopping", "쇼핑": "Shopping",
    "sinnliche fantasien": "Adulte 🔞",
}

# Catégories iptv-org → vocabulaire canonique. 'general', 'public' et
# 'interactive' sont omis volontairement : ils ne portent aucun signal, on
# préfère laisser les mots-clés du nom tenter leur chance.
IPTV_ORG_CAT_MAP = {
    "sports": "Sport", "entertainment": "Divertissement",
    "news": "Actualités", "weather": "Actualités",
    "religious": "Religion", "music": "Musique", "relax": "Musique",
    "movies": "Films & Séries", "series": "Films & Séries",
    "classic": "Films & Séries",
    "kids": "Enfants", "animation": "Enfants", "family": "Enfants",
    "education": "Documentaires", "culture": "Documentaires",
    "documentary": "Documentaires", "science": "Documentaires",
    "lifestyle": "Lifestyle", "travel": "Lifestyle",
    "cooking": "Lifestyle", "outdoor": "Lifestyle",
    "comedy": "Divertissement",
    "business": "Business", "shop": "Shopping",
    "auto": "Auto & Tech", "legislative": "Politique",
    "xxx": "Adulte 🔞",
}


class EnrichIndex:
    """Index tvg-id → (catégorie, pays, logo, NSFW), fusionné de deux sources.

    Les deux dictionnaires restent séparés parce qu'ils n'ont pas la même
    autorité : la taxonomie d'un provider sur ses propres chaînes est plus
    fiable que l'index communautaire iptv-org, et `category_for` applique cet
    ordre.
    """

    def __init__(self):
        self.provider = {}  # id minuscule → {category, country, logo}
        self.iptv_org = {}  # id minuscule → {category, country, logo, nsfw}

    def __len__(self):
        return len(self.provider) + len(self.iptv_org)

    def _both(self, tvg_id):
        key = (tvg_id or "").lower()
        if not key:
            return None, None
        return self.provider.get(key), self.iptv_org.get(key)

    def provider_category(self, tvg_id):
        """Genre déclaré par le provider lui-même — l'autorité la plus haute."""
        prov, _org = self._both(tvg_id)
        return (prov or {}).get("category", "")

    def org_category(self, tvg_id):
        """Genre selon l'index communautaire iptv-org."""
        _prov, org = self._both(tvg_id)
        return (org or {}).get("category", "")

    def category_for(self, tvg_id):
        """Catégorie canonique, ou "" si aucune source ne sait."""
        return (self.provider_category(tvg_id)
                or self.org_category(tvg_id))

    def country_for(self, tvg_id):
        prov, org = self._both(tvg_id)
        for src in (prov, org):
            if src and src.get("country"):
                return src["country"]
        return ""

    def logo_for(self, tvg_id):
        prov, org = self._both(tvg_id)
        for src in (prov, org):
            if src and src.get("logo"):
                return src["logo"]
        return ""

    def is_nsfw(self, tvg_id):
        _prov, org = self._both(tvg_id)
        return bool(org and org.get("nsfw"))


def _iter_provider_channels(payload):
    """Aplatit les deux formes de .channels.json en (id, channel, region).

    Pluto et Samsung imbriquent par région (`regions.<iso>.channels`), Plex et
    Roku exposent un dict plat `channels` où la région est dans le champ
    `regions` de chaque chaîne.
    """
    for region, bucket in (payload.get("regions") or {}).items():
        for cid, chan in (bucket.get("channels") or {}).items():
            yield cid, chan, region
    for cid, chan in (payload.get("channels") or {}).items():
        regions = chan.get("regions") or []
        yield cid, chan, (regions[0] if regions else "")


def _group_of(chan):
    """`group` (Pluto/Samsung/Plex) ou premier `groups` (Roku)."""
    group = chan.get("group")
    if not group:
        groups = chan.get("groups") or []
        group = groups[0] if groups else None
    return (group or "").strip()


def parse_provider_payload(payload, index):
    """Remplit index.provider depuis un .channels.json déjà décodé."""
    for cid, chan, region in _iter_provider_channels(payload):
        key = cid.lower()
        if key in index.provider:
            continue
        index.provider[key] = {
            "category": PROVIDER_GROUP_MAP.get(_group_of(chan).lower(), ""),
            "country": region.upper() if len(region) == 2 else "",
            "logo": chan.get("logo") or "",
        }


def parse_iptv_org_payload(payload, index):
    """Remplit index.iptv_org depuis l'API iptv-org déjà décodée."""
    for chan in payload:
        cid = (chan.get("id") or "").lower()
        if not cid:
            continue
        category = ""
        for raw in chan.get("categories") or []:
            mapped = IPTV_ORG_CAT_MAP.get(raw)
            if mapped:
                category = mapped
                break
        index.iptv_org[cid] = {
            "category": category,
            "country": (chan.get("country") or "").upper(),
            "logo": chan.get("logo") or "",
            "nsfw": bool(chan.get("is_nsfw")),
        }


async def build_index(fetch_json):
    """Construit l'EnrichIndex. `fetch_json(url)` → objet décodé ou None.

    Chaque source est indépendante : celle qui échoue est simplement absente
    de l'index, jamais une exception qui casserait la CI.
    """
    index = EnrichIndex()
    urls = list(PROVIDER_SOURCES.values()) + [IPTV_ORG_API]
    payloads = await asyncio.gather(*(fetch_json(u) for u in urls))
    for url, payload in zip(urls, payloads):
        if payload is None:
            continue
        if url == IPTV_ORG_API:
            parse_iptv_org_payload(payload, index)
        else:
            parse_provider_payload(payload, index)
    return index


def load_index_from_files(provider_files, iptv_org_file=None):
    """Variante hors-ligne, pour les tests et la mise au point locale."""
    index = EnrichIndex()
    for path in provider_files:
        with open(path, encoding="utf-8") as f:
            parse_provider_payload(json.load(f), index)
    if iptv_org_file:
        with open(iptv_org_file, encoding="utf-8") as f:
            parse_iptv_org_payload(json.load(f), index)
    return index
