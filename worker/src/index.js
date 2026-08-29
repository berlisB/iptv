// iptv-edge — étage serveur minimal du projet iptv (berlisB/iptv).
//
// Routes :
//   GET /catalog.json      → catalogue v3 (proxy GitHub raw, cache edge 15 min)
//   GET /epg/:pack.xml.gz  → EPG XMLTV gzippé (whitelist stricte, cache 6 h)
//   GET /healthz           → "ok"
//
// Aucun restream de flux vidéo : uniquement des métadonnées légères, pour
// rester loin des quotas du plan gratuit (100k req/jour, CPU 10 ms).

const GH = "https://raw.githubusercontent.com/berlisB/iptv/main";

// Whitelist stricte des packs EPG — jamais de proxy ouvert.
const EPG_PACKS = {
  "fr1": "https://epgshare01.online/epgshare01/epg_ripper_FR1.xml.gz",
  "pluto-fr": "https://i.mjh.nz/PlutoTV/fr.xml.gz",
  "pluto-us": "https://i.mjh.nz/PlutoTV/us.xml.gz",
  "pluto-all": "https://i.mjh.nz/PlutoTV/all.xml.gz",
  "samsung-fr": "https://i.mjh.nz/SamsungTVPlus/fr.xml.gz",
  "samsung-us": "https://i.mjh.nz/SamsungTVPlus/us.xml.gz",
  "samsung-all": "https://i.mjh.nz/SamsungTVPlus/all.xml.gz",
};

const CATALOG_TTL = 900; // 15 min — la CI régénère toutes les 6 h
const EPG_TTL = 21600; // 6 h

function withHeaders(response, maxAge) {
  const h = new Headers(response.headers);
  h.set("Cache-Control", `public, max-age=${maxAge}`);
  h.set("Access-Control-Allow-Origin", "*");
  return new Response(response.body, { status: response.status, headers: h });
}

async function proxy(request, upstream, ttl) {
  const r = await fetch(upstream, {
    cf: { cacheTtl: ttl, cacheEverything: true },
  });
  if (!r.ok) {
    return new Response(`upstream ${r.status}`, { status: 502 });
  }
  // 304 si le client présente déjà l'ETag courant (économise data + quota).
  const etag = r.headers.get("etag");
  const inm = request.headers.get("if-none-match");
  if (etag && inm && inm === etag) {
    return new Response(null, {
      status: 304,
      headers: { etag, "Access-Control-Allow-Origin": "*" },
    });
  }
  return withHeaders(r, ttl);
}

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);

    if (pathname === "/healthz") {
      return new Response("ok");
    }
    if (pathname === "/catalog.json") {
      return proxy(request, `${GH}/catalog.json`, CATALOG_TTL);
    }
    const epg = pathname.match(/^\/epg\/([a-z0-9-]+)\.xml\.gz$/);
    if (epg && EPG_PACKS[epg[1]]) {
      return proxy(request, EPG_PACKS[epg[1]], EPG_TTL);
    }
    return new Response("not found", { status: 404 });
  },
};
