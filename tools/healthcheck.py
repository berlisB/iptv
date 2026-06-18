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
import os
import re
import sys
import aiohttp

OFFICIAL_BROADCASTERS = """\
#EXTM3U
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
MASTER_INDEX = "https://iptv-org.github.io/iptv/index.m3u"

UA = {"User-Agent": "iptv-healthcheck/1.0 (+https://github.com/berlisB/iptv)"}


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
        sources = list(FREE_SERVICES)
        if include_master:
            sources.append(MASTER_INDEX)
        texts = await asyncio.gather(*(fetch_text(session, u) for u in sources))

        pairs = parse_m3u(OFFICIAL_BROADCASTERS)
        for t in texts:
            pairs += parse_m3u(t)

        # 2) dédup par URL en gardant l'ordre
        seen = set()
        unique = []
        for ext, url in pairs:
            if url not in seen:
                seen.add(url)
                unique.append((ext, url))

        total = len(unique)
        dropped = 0
        if total > max_channels:
            dropped = total - max_channels
            unique = unique[:max_channels]
        print(f"Sources parsées : {total} flux uniques "
              f"(test de {len(unique)}, {dropped} ignorés par MAX_CHANNELS)")

        # 3) probe concurrent
        sem = asyncio.Semaphore(concurrency)

        async def check(ext, url):
            async with sem:
                return (ext, url) if await is_alive(session, url, timeout) else None

        results = await asyncio.gather(*(check(e, u) for e, u in unique))

    alive = [r for r in results if r]
    print(f"Vivants : {len(alive)}/{len(unique)} "
          f"({100 * len(alive) // max(1, len(unique))}%)")

    with open("verified.m3u", "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n")
        f.write(f"# Généré par tools/healthcheck.py — {len(alive)} flux vérifiés "
                f"vivants. Sources 100% légales (FAST + broadcasters officiels).\n")
        for ext, url in alive:
            f.write(f"{ext}\n{url}\n")

    print("Écrit verified.m3u")


if __name__ == "__main__":
    asyncio.run(main())
