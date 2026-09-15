# iptv

Lecteur IPTV Flutter : chaînes live vérifiées, EPG, et films/séries.

La TV en direct fonctionne sans aucune configuration. Les deux sections
ci-dessous couvrent le reste.

## Prérequis de build

Le projet compile et se lance tel quel. Deux fonctionnalités restent inertes
tant qu'on ne les active pas — aucune des deux n'étant devinable, d'où cette
section.

### 1. Clé TMDB — affiches et synopsis

Un jeton de lecture est committé par défaut (déjà public dans l'historique git,
donc sans valeur de secret). Pour le vôtre, créez-en un sur
[themoviedb.org](https://www.themoviedb.org/settings/api) :

```bash
flutter run --dart-define=TMDB_API_KEY=<votre jeton v4>
```

### 2. Section Telegram — désactivée par défaut

La lecture des films depuis un canal Telegram est **livrée mais inactive**.

La raison est un choix de priorité : elle repose sur TDLib, dont la
bibliothèque native est servie par GitHub Packages Maven, lequel exige une
authentification **même pour un paquet public**. Tant que la dépendance est
active, *tout* build Android échoue sur `401 Unauthorized` — y compris pour
qui ne se sert pas du canal. Une fonctionnalité optionnelle ne doit pas
bloquer la livraison des autres.

Le code reste entièrement dans le dépôt et compilé : indexation du canal,
correspondance TMDB, lecteur progressif et interface. Seul l'accès réseau
passe par une frontière, `lib/features/telegram/data/tdlib_client.dart`, dont
l'implémentation active est un bouchon. L'onglet « Mon canal » s'affiche et
annonce que la fonctionnalité n'est pas incluse dans cette version.

**Pour l'activer**, trois gestes :

```bash
# 1. décommenter « libtdjson: ^0.3.0 » dans pubspec.yaml

# 2. échanger les deux implémentations
cd lib/features/telegram/data
mv tdlib_client.dart tdlib_client_stub.dart.disabled
mv tdlib_client_real.dart.disabled tdlib_client.dart

# 3. récupérer la dépendance
flutter pub get
```

Il faut alors un token GitHub (scope `read:packages`) dans
`~/.gradle/gradle.properties` :

```properties
gpr.user=<votre login github>
gpr.key=<token github avec le scope read:packages>
```

En CI GitHub Actions, le `GITHUB_TOKEN` fourni automatiquement suffit — il
suffit de l'exposer au job :

```yaml
env:
  GITHUB_ACTOR: ${{ github.actor }}
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Enfin, créez une application sur [my.telegram.org](https://my.telegram.org),
onglet *API development tools*, et passez ses identifiants au build :

```bash
flutter run \
  --dart-define=TELEGRAM_API_ID=123456 \
  --dart-define=TELEGRAM_API_HASH=0123456789abcdef0123456789abcdef
```

## Pipeline de chaînes

`tools/healthcheck.py` sonde les sources légales (services FAST + diffuseurs
officiels + index iptv-org), ne retient que les flux qui répondent réellement,
et publie deux fichiers à la racine :

- `verified.m3u` — les flux vivants, au format M3U ;
- `catalog.json` — le catalogue v3 : identité stable, catégorie, pays, URLs de
  secours fusionnées.

`tools/enrich.py` fournit les métadonnées de genre que les playlists FAST ne
contiennent pas : celles-ci groupent leurs chaînes par **pays**, pas par genre.
L'enrichissement joint sur le `tvg-id` la taxonomie publiée par chaque provider
et l'index communautaire iptv-org.

`.github/workflows/healthcheck.yml` rejoue le tout toutes les 6 h et commite le
résultat.

Exécution locale :

```bash
pip install aiohttp
INCLUDE_MASTER=1 MAX_CHANNELS=24000 python tools/healthcheck.py
```

⚠️ Le script écrit dans le répertoire courant : lancez-le depuis la racine du
dépôt, ou depuis un dossier jetable si vous ne voulez pas écraser le catalogue.

## Tests

```bash
flutter test
```

Les tests couvrent notamment deux invariants qui cassent silencieusement :

- `test/stable_id_test.dart` — l'identité d'une chaîne est calculée à la fois
  par `tools/healthcheck.py` et `lib/core/utils/stable_id.dart`. Tout écart
  désynchronise favoris, scores et EPG. Les valeurs attendues sont les sorties
  réelles du Python.
- `test/telegram_media_test.dart` — découpage des noms de release. Sans titre
  et année propres, aucune correspondance TMDB, donc aucune affiche.
