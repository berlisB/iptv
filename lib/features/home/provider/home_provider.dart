import 'package:flutter/foundation.dart';
import 'package:iptv/core/services/m3u_parser.dart';
import 'package:iptv/core/utils/stable_id.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/daddylive_service.dart';
import 'package:iptv/features/home/data/datasources/m3u_data_source.dart';
import 'package:iptv/features/home/data/datasources/xtream_service.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/entities/channel_group.dart';
import 'package:iptv/features/home/domain/services/channel_filter.dart';
import 'package:iptv/features/home/domain/services/channel_service.dart';

/// Deux modes d'affichage des chaînes.
///  - [reliable] : catalogue curé (peu de chaînes, fiables, francophone-first).
///  - [explore]  : sources brutes filtrées par audience (plus large, badges).
enum CatalogMode { reliable, explore }

class HomeProvider extends ChangeNotifier {
  HomeProvider({ChannelService? channelService})
      : _channelService = channelService ?? ChannelService();

  final ChannelService _channelService;
  final ChannelFilter _filter = const ChannelFilter();

  /// Catégories orientées utilisateur (ordre = priorité d'affichage des chips).
  static const List<String> userCategories = [
    'Francophone',
    'Afrique francophone',
    'TV Chine',
    'Infos',
    'Films & séries gratuits',
    'Documentaires',
    'Sport gratuit',
    'Musique',
    'Enfants',
    'Anglais utile',
    'Sans barrière de langue',
  ];

  // --- Category normalization: merge fragmented groups into broad categories ---
  static const Map<String, String> _categoryMap = {
    // Actualités
    'news': 'Actualités', 'information': 'Actualités', 'noticias': 'Actualités',
    'nachrichten': 'Actualités', 'weather': 'Actualités', 'météo': 'Actualités',
    // Sport
    'sports': 'Sport', 'sport': 'Sport', 'deportes': 'Sport', 'football': 'Sport',
    // Films & Séries
    'movies': 'Films & Séries', 'cinema': 'Films & Séries',
    'films': 'Films & Séries', 'series': 'Films & Séries',
    'drama': 'Films & Séries', 'thriller': 'Films & Séries',
    'action': 'Films & Séries', 'horror': 'Films & Séries',
    'romance': 'Films & Séries', 'crime': 'Films & Séries',
    'mystery': 'Films & Séries', 'sci-fi': 'Films & Séries',
    'western': 'Films & Séries', 'war': 'Films & Séries',
    // Divertissement
    'entertainment': 'Divertissement', 'general': 'Divertissement',
    'variety': 'Divertissement', 'comedy': 'Divertissement',
    'reality': 'Divertissement', 'game': 'Divertissement',
    'talk': 'Divertissement', 'classic': 'Divertissement',
    // Enfants
    'kids': 'Enfants', 'children': 'Enfants', 'animation': 'Enfants',
    'cartoon': 'Enfants', 'family': 'Enfants', 'enfant': 'Enfants',
    'jeunesse': 'Enfants',
    // Musique
    'music': 'Musique', 'musique': 'Musique',
    // Documentaires
    'documentary': 'Documentaires', 'science': 'Documentaires',
    'nature': 'Documentaires', 'history': 'Documentaires',
    'education': 'Documentaires', 'culture': 'Documentaires',
    'discovery': 'Documentaires',
    // Lifestyle
    'lifestyle': 'Lifestyle', 'cooking': 'Lifestyle', 'food': 'Lifestyle',
    'travel': 'Lifestyle', 'fashion': 'Lifestyle', 'home': 'Lifestyle',
    'garden': 'Lifestyle', 'diy': 'Lifestyle', 'health': 'Lifestyle',
    'wellness': 'Lifestyle', 'outdoor': 'Lifestyle', 'adventure': 'Lifestyle',
    'relax': 'Lifestyle',
    // Business
    'business': 'Business', 'finance': 'Business',
    // Religion
    'religious': 'Religion', 'religion': 'Religion', 'spiritual': 'Religion',
    // Shopping
    'shop': 'Shopping', 'shopping': 'Shopping',
    // Auto & Tech
    'auto': 'Auto & Tech', 'automotive': 'Auto & Tech', 'technology': 'Auto & Tech',
    // Politique
    'legislative': 'Politique', 'political': 'Politique',
    // Adulte
    'xxx': 'Adulte 🔞', 'adult': 'Adulte 🔞', '+18': 'Adulte 🔞',
    'porn': 'Adulte 🔞',
    // TV Chine
    'tv chine': 'TV Chine', 'chinese': 'TV Chine', 'china': 'TV Chine',
    'cctv': 'TV Chine',
  };

  // Known country names (used as group-title by many sources)
  static final _countryNames = <String>{
    // English
    'afghanistan', 'albania', 'algeria', 'andorra', 'angola', 'argentina',
    'armenia', 'australia', 'austria', 'azerbaijan', 'bahrain', 'bangladesh',
    'belarus', 'belgium', 'benin', 'bolivia', 'bosnia and herzegovina',
    'brazil', 'brunei', 'bulgaria', 'burkina faso', 'burundi', 'cambodia',
    'cameroon', 'canada', 'chad', 'chile', 'china', 'colombia', 'congo',
    'costa rica', 'croatia', 'cuba', 'cyprus', 'czech republic', 'czechia',
    'denmark', 'dominican republic', 'ecuador', 'egypt', 'el salvador',
    'estonia', 'ethiopia', 'finland', 'france', 'gabon', 'georgia',
    'germany', 'ghana', 'greece', 'guatemala', 'guinea', 'haiti',
    'honduras', 'hong kong', 'hungary', 'iceland', 'india', 'indonesia',
    'iran', 'iraq', 'ireland', 'israel', 'italy', 'ivory coast', 'jamaica',
    'japan', 'jordan', 'kazakhstan', 'kenya', 'kosovo', 'kuwait',
    'kyrgyzstan', 'laos', 'latvia', 'lebanon', 'libya', 'liechtenstein',
    'lithuania', 'luxembourg', 'macedonia', 'madagascar', 'malaysia',
    'mali', 'malta', 'mexico', 'moldova', 'monaco', 'mongolia',
    'montenegro', 'morocco', 'mozambique', 'myanmar', 'nepal',
    'netherlands', 'new zealand', 'nicaragua', 'niger', 'nigeria', 'norway',
    'oman', 'pakistan', 'palestine', 'panama', 'paraguay', 'peru',
    'philippines', 'poland', 'portugal', 'qatar', 'romania', 'russia',
    'rwanda', 'saudi arabia', 'senegal', 'serbia', 'singapore', 'slovakia',
    'slovenia', 'somalia', 'south africa', 'south korea', 'spain',
    'sri lanka', 'sudan', 'sweden', 'switzerland', 'syria', 'taiwan',
    'tajikistan', 'tanzania', 'thailand', 'togo', 'trinidad and tobago',
    'tunisia', 'turkey', 'turkmenistan', 'uganda', 'ukraine',
    'united arab emirates', 'united kingdom', 'united states',
    'united states of america', 'uruguay', 'uzbekistan', 'venezuela',
    'vietnam', 'yemen', 'zambia', 'zimbabwe',
    // French
    'algérie', 'allemagne', 'arabie saoudite', 'belgique', 'brésil',
    'cameroun', 'côte d\'ivoire', 'danemark', 'espagne', 'états-unis',
    'grèce', 'hongrie', 'inde', 'irlande', 'islande', 'italie', 'japon',
    'liban', 'libye', 'maroc', 'mexique', 'norvège', 'nouvelle-zélande',
    'pays-bas', 'pologne', 'république dominicaine', 'république tchèque',
    'roumanie', 'royaume-uni', 'russie', 'sénégal', 'suède', 'suisse',
    'thaïlande', 'tunisie', 'turquie',
    // Common abbreviations used as groups
    'usa', 'uk', 'uae', 'drc',
  };

  static String _normalizeGroup(String rawGroup, {bool isAdult = false}) {
    if (rawGroup.isEmpty) return 'Autres';
    if (isAdult) return 'Adulte 🔞';

    final lower = rawGroup.toLowerCase().trim();
    if (lower == 'undefined' || lower == 'autres' || lower == 'uncategorized'
        || lower == 'other' || lower == 'misc') {
      return 'Autres';
    }
    // Check if it's a country name → put in Général
    if (_countryNames.contains(lower)) return 'Général';
    // Exact match
    if (_categoryMap.containsKey(lower)) return _categoryMap[lower]!;
    // Contains match
    for (final entry in _categoryMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return rawGroup;
  }

  // --- State ---
  List<ChannelEntity> _allChannels = []; // sources brutes (mode Explorer)
  List<ChannelEntity> _catalogChannels = []; // catalogue curé (mode Fiable)
  List<ChannelEntity> _lookupPool = []; // union par id (favoris/récents/EPG)
  List<ChannelEntity> _modeBase = []; // base affichée selon le mode courant
  List<ChannelEntity> _filteredChannels = [];
  List<ChannelEntity> _recentChannels = [];
  List<ChannelEntity> _frequentChannels = [];
  List<ChannelGroup> _groups = [];
  Set<String> _blocklist = {};

  CatalogMode _mode = CatalogMode.reliable;

  /// Maps original group name → normalized category for each channel
  final Map<String, String> _normalizedGroups = {};

  String _selectedGroup = 'Tout';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showHidden = false;
  bool _showGeoBlocked = false;
  bool _showUndefined = true;
  int _geoBlockedCount = 0;
  bool _daddyliveEnabled = false;

  /// Union catalogue + brut (résolution par id : favoris, récents, EPG, fiables).
  List<ChannelEntity> get allChannels => _lookupPool;

  /// Packs EPG utiles selon les chaînes chargées (cf. EpgService.packUrls).
  /// Les flux Pluto/Samsung passent par les redirections jmp2.uk, dont les
  /// tvg-id correspondent aux ids des guides i.mjh.nz.
  List<String> get epgPacks {
    var hasPluto = false;
    var hasSamsung = false;
    for (final c in _lookupPool) {
      if (c.url.contains('jmp2.uk/plu-')) hasPluto = true;
      if (c.url.contains('jmp2.uk/stvp-')) hasSamsung = true;
      if (hasPluto && hasSamsung) break;
    }
    return [
      'fr1',
      if (hasPluto) 'pluto-fr',
      if (hasSamsung) 'samsung-fr',
    ];
  }

  /// Sources brutes uniquement (mode Explorer).
  List<ChannelEntity> get rawChannels => _allChannels;

  /// Catalogue curé uniquement (mode Fiable).
  List<ChannelEntity> get catalogChannels => _catalogChannels;

  CatalogMode get mode => _mode;
  bool get isReliableMode => _mode == CatalogMode.reliable;

  List<ChannelEntity> get filteredChannels => _filteredChannels;
  List<ChannelEntity> get recentChannels => _recentChannels;
  List<ChannelEntity> get frequentChannels => _frequentChannels;
  List<ChannelGroup> get groups => _groups;
  String get selectedGroup => _selectedGroup;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get showHidden => _showHidden;
  bool get showGeoBlocked => _showGeoBlocked;
  bool get showUndefined => _showUndefined;
  int get geoBlockedCount => _geoBlockedCount;

  bool get hasActiveFilters => _selectedGroup != 'Tout';
  int get activeFilterCount => _selectedGroup != 'Tout' ? 1 : 0;

  /// Catégorie principale d'une chaîne pour le badge sur sa carte.
  /// Les chaînes du catalogue portent déjà une catégorie orientée usage.
  String categoryOf(ChannelEntity c) {
    if (c.category.isNotEmpty) return c.category;
    final key = '${c.group}|${c.isAdult}';
    return _normalizedGroups[key] ?? _normalizeGroup(c.group, isAdult: c.isAdult);
  }

  /// Appartenance (multi) d'une chaîne à une catégorie orientée usage.
  bool matchesCategory(ChannelEntity c, String cat) {
    if (categoryOf(c) == cat) return true;
    final aud = _filter.audienceOf(c);
    final content = () {
      final key = '${c.group}|${c.isAdult}';
      return _normalizedGroups[key] ??
          _normalizeGroup(c.group, isAdult: c.isAdult);
    }();
    switch (cat) {
      case 'Francophone':
        return aud == AudienceFit.francophone ||
            aud == AudienceFit.africaFrancophone;
      case 'Afrique francophone':
        return aud == AudienceFit.africaFrancophone;
      case 'TV Chine':
        return c.country.toLowerCase() == 'cn' ||
            c.group.toLowerCase().contains('cctv') ||
            c.group.toLowerCase().contains('china') ||
            c.group.toLowerCase().contains('tv chine') ||
            c.category.toLowerCase() == 'tv chine';
      case 'Anglais utile':
        return aud == AudienceFit.englishUseful;
      case 'Sans barrière de langue':
        return aud == AudienceFit.visualNoLanguage;
      case 'Infos':
        return content == 'Actualités';
      case 'Films & séries gratuits':
        return content == 'Films & Séries';
      case 'Documentaires':
        return content == 'Documentaires';
      case 'Sport gratuit':
        return content == 'Sport';
      case 'Musique':
        return content == 'Musique';
      case 'Enfants':
        return content == 'Enfants';
    }
    return false;
  }

  /// Badge à afficher sur une carte (null = aucun). Visible surtout en Explorer.
  String? badgeFor(ChannelEntity c) {
    if (c.isOfficial && c.status == ChannelStatus.online) return null;
    if (c.status == ChannelStatus.online) return null;
    if (_filter.audienceOf(c) == AudienceFit.other && c.language.isEmpty) {
      return 'Langue variable';
    }
    if (c.isUnverified) return 'Non vérifiée';
    return null;
  }

  List<String> get groupNames {
    return ['Tout', ..._groups.map((g) => g.name)];
  }

  /// Bascule entre "Sélection fiable" et "Explorer".
  void setMode(CatalogMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _selectedGroup = 'Tout';
    _recomputeBase();
    _applyFilters();
    notifyListeners();
  }

  Future<void> loadChannels() async {
    _isLoading = true;
    _showHidden = AppStorage.getShowHidden();
    _showGeoBlocked = AppStorage.getShowGeoBlocked();
    notifyListeners();

    // Load blocklist
    _blocklist = await M3uDataSource.loadBlocklist();
    _blocklist.addAll(AppStorage.getLocalBlocklist());

    // Load playlists
    final m3uContent = await M3uDataSource.loadAllPlaylists();
    final parsed = M3uParser.parse(m3uContent);

    // Abonnement Xtream Codes : chaînes prioritaires (placées en tête → source
    // principale lors de la fusion). L'utilisateur les paie, elles sont fiables.
    final xtream = AppStorage.getXtreamConfig();
    if (xtream != null) {
      final xchannels = await XtreamService.fetchLiveChannels(
        host: xtream['host']!,
        username: xtream['username']!,
        password: xtream['password']!,
      );
      parsed.insertAll(0, xchannels);
    }

    // Source Daddylive (étude éducative) : activée dans les paramètres.
    _daddyliveEnabled = AppStorage.getDaddyliveEnabled();
    if (_daddyliveEnabled) {
      final daddyliveChannels = await DaddyliveService.fetchAllChannels();
      if (daddyliveChannels.isNotEmpty) {
        parsed.insertAll(0, daddyliveChannels);
        debugPrint('[IPTV] Daddylive: ${daddyliveChannels.length} chaînes');
      }
    }

    // Filter pipeline
    _allChannels = parsed.where((c) {
      final url = c.url.toLowerCase();
      if (url.contains('youtube.com') ||
          url.contains('youtu.be') ||
          url.contains('twitch.tv') ||
          url.contains('dailymotion.com')) {
        return false;
      }
      if (url.isEmpty) return false;
      if (_blocklist.contains(c.url)) return false;
      return true;
    }).toList();

    _geoBlockedCount = _allChannels.where((c) => c.isGeoBlocked).length;

    debugPrint('[IPTV] Parsed: ${parsed.length}, '
        'after filters: ${_allChannels.length}, '
        'geo-blocked: $_geoBlockedCount');

    // Fusion des doublons : au lieu de jeter une chaîne en double, on garde
    // ses URLs comme sources de secours (failover) → plus de chaînes fonctionnelles.
    _allChannels = _mergeDuplicates(_allChannels);

    debugPrint('[IPTV] After merge: ${_allChannels.length} channels '
        '(${_allChannels.fold<int>(0, (s, c) => s + c.backupUrls.length)} backup sources)');

    // Catalogue curé (mode "Sélection fiable") : rapide (asset local).
    _catalogChannels = await _channelService.loadCatalog();
    debugPrint('[IPTV] Catalogue curé: ${_catalogChannels.length} chaînes');

    // Pool union par id (favoris/récents/EPG/fiables) — catalogue prioritaire.
    final seenIds = <String>{};
    _lookupPool = [
      for (final c in [..._catalogChannels, ..._allChannels])
        if (seenIds.add(c.id)) c,
    ];

    // Build normalized group mapping (per-channel because isAdult depends on name)
    _normalizedGroups.clear();
    for (final c in _lookupPool) {
      final key = '${c.group}|${c.isAdult}';
      if (!_normalizedGroups.containsKey(key)) {
        _normalizedGroups[key] = _normalizeGroup(c.group, isAdult: c.isAdult);
      }
    }

    _recomputeBase();
    _loadRecentAndFrequent();
    _applyFilters();

    _isLoading = false;
    notifyListeners();

    // Validation des flux du catalogue en arrière-plan (non bloquant) : met à
    // jour les scores, puis on rafraîchit la base si le mode Fiable est actif.
    _validateCatalogInBackground();
  }

  /// (Re)calcule la base affichée selon le mode et reconstruit les catégories.
  void _recomputeBase() {
    _modeBase = isReliableMode
        ? _channelService.reliableSelection(_catalogChannels)
        : _channelService.exploreSelection(_allChannels);
    _rebuildGroups();
  }

  /// Catégories canoniques déjà représentées par un chip de [userCategories]
  /// (ex. 'Actualités' est servi par le chip 'Infos') — pas de doublon.
  static const Set<String> _coveredByUserCategories = {
    'Actualités', 'Films & Séries', 'Documentaires', 'Sport', 'Musique',
    'Enfants', 'TV Chine',
  };

  /// Construit les groupes par catégorie orientée usage à partir de la base.
  void _rebuildGroups() {
    final groups = <ChannelGroup>[];
    for (final cat in userCategories) {
      final channels =
          _modeBase.where((c) => matchesCategory(c, cat)).toList();
      if (channels.isNotEmpty) {
        groups.add(ChannelGroup(name: cat, channels: channels));
      }
    }

    // Chips dynamiques : catégories du catalogue v3 non couvertes par les
    // chips éditoriaux (Divertissement, Général, Lifestyle…), par volume ↓.
    final showAdult = AppStorage.getShowAdult();
    final extraCounts = <String, int>{};
    for (final c in _modeBase) {
      final cat = categoryOf(c);
      if (cat == 'Autres' ||
          _coveredByUserCategories.contains(cat) ||
          userCategories.contains(cat)) {
        continue;
      }
      if (cat == 'Adulte 🔞' && !showAdult) continue;
      extraCounts[cat] = (extraCounts[cat] ?? 0) + 1;
    }
    final extras = extraCounts.keys.toList()
      ..sort((a, b) => extraCounts[b]!.compareTo(extraCounts[a]!));
    for (final cat in extras) {
      groups.add(ChannelGroup(
        name: cat,
        channels: _modeBase.where((c) => categoryOf(c) == cat).toList(),
      ));
    }

    _groups = groups;
    debugPrint('[IPTV] Mode=$_mode base=${_modeBase.length} '
        'catégories=${_groups.length}');
  }

  Future<void> _validateCatalogInBackground() async {
    if (_catalogChannels.isEmpty) return;

    // Le catalogue v3 est déjà vérifié par la CI (< 6 h). On ne re-sonde côté
    // client qu'un échantillon utile : les chaînes éditoriales/officielles,
    // les favoris et la tête de liste — jamais les ~6000 chaînes.
    final favorites = AppStorage.getFavorites().toSet();
    final sample = <ChannelEntity>[
      for (final c in _catalogChannels)
        if (c.isOfficial || favorites.contains(c.id)) c,
      ..._catalogChannels.take(100),
    ];
    // Cooldown : pas de re-probe d'une chaîne vérifiée il y a moins de 6 h —
    // le probe ne doit pas marteler les CDN (ni les scores) à chaque lancement.
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    final seen = <String>{};
    final toValidate = [
      for (final c in sample)
        if (seen.add(c.id) &&
            (AppStorage.getCheckedAt(c.id)?.isBefore(cutoff) ?? true))
          c,
    ];

    const batchSize = 10;
    for (var i = 0; i < toValidate.length; i += batchSize) {
      final batch = toValidate.skip(i).take(batchSize).toList();
      final statuses =
          await _channelService.validateBatch(batch, concurrency: 3);

      _catalogChannels = _catalogChannels
          .map((c) => statuses.containsKey(c.id)
              ? c.copyWith(
                  status: statuses[c.id],
                  reliabilityScore: AppStorage.getScore(c.id),
                )
              : c)
          .toList();
    }

    if (isReliableMode) {
      _recomputeBase();
      _applyFilters();
      notifyListeners();
    }
  }

  /// Fusionne les chaînes de même identité : la meilleure source devient
  /// principale, les autres URLs deviennent des secours (failover). Cap à 6.
  static List<ChannelEntity> _mergeDuplicates(List<ChannelEntity> channels) {
    final Map<String, ChannelEntity> merged = {};

    for (final c in channels) {
      // Identité stable partagée avec le pipeline (tvg-id sinon nom normalisé).
      final key = stableChannelId(tvgId: c.tvgId, name: c.name);
      final existing = merged[key];

      // Les ids préfixés (xtream_/daddylive_) restent tels quels ; le reste est
      // aligné sur l'identité stable → mêmes scores/favoris qu'en mode Fiable.
      String idFor(ChannelEntity primary) =>
          primary.id.startsWith('xtream_') || primary.id.startsWith('daddylive_')
              ? primary.id
              : key;

      if (existing == null) {
        merged[key] = c.id == idFor(c) ? c : c.copyWith(id: idFor(c));
        continue;
      }

      // Évite d'ajouter une URL déjà connue.
      if (existing.url == c.url || existing.backupUrls.contains(c.url)) continue;

      // On choisit la meilleure source comme principale (non géo-bloquée + qualité).
      final keepNewAsPrimary = _isBetterSource(c, existing);
      final primary = keepNewAsPrimary ? c : existing;
      final extraUrl = keepNewAsPrimary ? existing.url : c.url;

      final backups = <String>{
        ...primary.backupUrls,
        extraUrl,
        ...(keepNewAsPrimary ? existing.backupUrls : c.backupUrls),
      }.take(6).toList();

      merged[key] = primary.copyWith(id: idFor(primary), backupUrls: backups);
    }

    return merged.values.toList();
  }

  /// Une source est "meilleure" si elle n'est pas géo-bloquée et porte une qualité.
  static bool _isBetterSource(ChannelEntity candidate, ChannelEntity current) {
    if (current.isGeoBlocked && !candidate.isGeoBlocked) return true;
    if (!current.isGeoBlocked && candidate.isGeoBlocked) return false;
    final score = {'4K': 4, 'FHD': 3, 'HD': 2, 'SD': 1, '': 0};
    return (score[candidate.quality] ?? 0) > (score[current.quality] ?? 0);
  }

  void _loadRecentAndFrequent() {
    final recentIds = AppStorage.getRecentChannels();
    _recentChannels = recentIds
        .map((id) {
          try {
            return _lookupPool.firstWhere((c) => c.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<ChannelEntity>()
        .take(10)
        .toList();

    final frequentIds = AppStorage.getFrequentChannels(limit: 10);
    _frequentChannels = frequentIds
        .map((id) {
          try {
            return _lookupPool.firstWhere((c) => c.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<ChannelEntity>()
        .toList();
  }

  Future<void> onChannelWatched(String channelId) async {
    await AppStorage.addRecentChannel(channelId);
    await AppStorage.incrementWatchCount(channelId);
    _loadRecentAndFrequent();
    notifyListeners();
  }

  // --- Filter methods ---

  void selectGroup(String group) {
    _selectedGroup = group;
    _applyFilters();
    notifyListeners();
  }

  void clearAllFilters() {
    _selectedGroup = 'Tout';
    _searchQuery = '';
    _applyFilters();
    notifyListeners();
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void toggleShowHidden() {
    _showHidden = !_showHidden;
    AppStorage.setShowHidden(_showHidden);
    _applyFilters();
    notifyListeners();
  }

  void toggleShowGeoBlocked() {
    _showGeoBlocked = !_showGeoBlocked;
    AppStorage.setShowGeoBlocked(_showGeoBlocked);
    _applyFilters();
    notifyListeners();
  }

  bool get daddyliveEnabled => _daddyliveEnabled;
  bool get showAdult => AppStorage.getShowAdult();

  void toggleShowAdult() {
    AppStorage.setShowAdult(!showAdult);
    _rebuildGroups(); // le chip 'Adulte 🔞' apparaît/disparaît avec le toggle
    _applyFilters();
    notifyListeners();
  }

  void toggleShowUndefined() {
    _showUndefined = !_showUndefined;
    _applyFilters();
    notifyListeners();
  }

  void refreshFilters() {
    _showHidden = AppStorage.getShowHidden();
    _showGeoBlocked = AppStorage.getShowGeoBlocked();
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    // Base = catalogue curé (Fiable) ou sources brutes filtrées (Explorer),
    // déjà triée/exclue par le ChannelService.
    var channels = List<ChannelEntity>.from(_modeBase);

    // Chaînes "mortes" (3+ échecs DURS) masquées sauf si l'utilisateur l'autorise.
    if (!_showHidden) {
      channels = channels.where((c) => !AppStorage.isDead(c.id)).toList();
    }

    // Hidden
    if (!_showHidden) {
      final hidden = AppStorage.getHiddenChannels();
      channels = channels.where((c) => !hidden.contains(c.id)).toList();
    }

    // Geo-blocked
    if (!_showGeoBlocked) {
      channels = channels.where((c) => !c.isGeoBlocked).toList();
    }

    // Adult (XXX) - hidden by default
    if (!AppStorage.getShowAdult()) {
      channels = channels.where((c) => !c.isAdult).toList();
    }

    // Undefined/unclassified channels
    if (!_showUndefined) {
      channels = channels.where((c) {
        final cat = categoryOf(c);
        return cat != 'Autres';
      }).toList();
    }

    // Catégorie orientée usage (appartenance multi).
    if (_selectedGroup != 'Tout') {
      channels =
          channels.where((c) => matchesCategory(c, _selectedGroup)).toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      channels = channels
          .where((c) =>
              c.name.toLowerCase().contains(query) ||
              categoryOf(c).toLowerCase().contains(query) ||
              c.country.toLowerCase().contains(query))
          .toList();
    }

    _filteredChannels = channels;
  }

  bool isFavorite(String channelId) => AppStorage.isFavorite(channelId);

  Future<void> toggleFavorite(String channelId) async {
    if (AppStorage.isFavorite(channelId)) {
      await AppStorage.removeFavorite(channelId);
    } else {
      await AppStorage.addFavorite(channelId);
    }
    notifyListeners();
  }

  bool isHidden(String channelId) => AppStorage.isHidden(channelId);

  Future<void> hideChannel(String channelId) async {
    await AppStorage.hideChannel(channelId);
    _applyFilters();
    notifyListeners();
  }

  Future<void> unhideChannel(String channelId) async {
    await AppStorage.unhideChannel(channelId);
    _applyFilters();
    notifyListeners();
  }

  Future<void> clearHiddenChannels() async {
    await AppStorage.clearHiddenChannels();
    _applyFilters();
    notifyListeners();
  }

  int get hiddenCount => AppStorage.getHiddenChannels().length;
}
