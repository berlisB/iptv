# iptv-edge — Cloudflare Worker

Étage serveur du projet : sert `catalog.json` (catalogue v3 généré par la CI)
et les EPG gzippés avec cache edge, pour que l'app ait des endpoints stables
et rapides sans dépendre directement de GitHub raw / epgshare / mjh.nz.

## Routes

| Route | Description | Cache edge |
|---|---|---|
| `GET /catalog.json` | Catalogue v3 (proxy GitHub raw) | 15 min |
| `GET /epg/<pack>.xml.gz` | EPG XMLTV gzippé (whitelist) | 6 h |
| `GET /healthz` | Sonde de vie | — |

Packs EPG : `fr1`, `pluto-fr`, `pluto-us`, `pluto-all`, `samsung-fr`,
`samsung-us`, `samsung-all`.

## Développement / déploiement

```bash
cd worker
npx wrangler dev              # test local sur http://localhost:8787
npx wrangler deploy           # déploiement (nécessite un compte Cloudflare)
```

Premier déploiement : `npx wrangler login` ouvre le navigateur pour lier le
compte Cloudflare (plan gratuit suffisant : 100k req/jour). L'URL de prod est
`https://iptv-edge.<sous-domaine>.workers.dev` — à reporter dans l'app via
`--dart-define=WORKER_BASE_URL=...` (une valeur par défaut est compilée dans
`lib/features/home/data/datasources/catalog_v3_source.dart`).

## Garde-fous

- Aucun restream vidéo (métadonnées uniquement) : quotas gratuits intouchés.
- Whitelist stricte des upstreams EPG : pas de proxy ouvert.
- L'app fonctionne sans le Worker (fallback GitHub raw → cache disque → asset).
