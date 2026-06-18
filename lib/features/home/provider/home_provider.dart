import 'package:flutter/foundation.dart';
import 'package:iptv/core/services/m3u_parser.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/m3u_data_source.dart';
import 'package:iptv/features/home/data/datasources/xtream_service.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/entities/channel_group.dart';

class HomeProvider extends ChangeNotifier {
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
  List<ChannelEntity> _allChannels = [];
  List<ChannelEntity> _filteredChannels = [];
  List<ChannelEntity> _recentChannels = [];
  List<ChannelEntity> _frequentChannels = [];
  List<ChannelGroup> _groups = [];
  Set<String> _blocklist = {};

  /// Maps original group name → normalized category for each channel
  final Map<String, String> _normalizedGroups = {};

  String _selectedGroup = 'Tout';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showHidden = false;
  bool _showGeoBlocked = false;
  bool _showUndefined = true;
  int _geoBlockedCount = 0;

  List<ChannelEntity> get allChannels => _allChannels;
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

  /// Get normalized category for a channel
  String categoryOf(ChannelEntity c) {
    final key = '${c.group}|${c.isAdult}';
    return _normalizedGroups[key] ?? _normalizeGroup(c.group, isAdult: c.isAdult);
  }

  List<String> get groupNames {
    return ['Tout', ..._groups.map((g) => g.name)];
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

    // Build normalized group mapping (per-channel because isAdult depends on name)
    _normalizedGroups.clear();
    for (final c in _allChannels) {
      final key = '${c.group}|${c.isAdult}';
      if (!_normalizedGroups.containsKey(key)) {
        _normalizedGroups[key] = _normalizeGroup(c.group, isAdult: c.isAdult);
      }
    }

    // Build groups using normalized categories
    final Map<String, List<ChannelEntity>> groupMap = {};
    for (final channel in _allChannels) {
      final cat = categoryOf(channel);
      groupMap.putIfAbsent(cat, () => []).add(channel);
    }
    _groups = groupMap.entries
        .map((e) => ChannelGroup(name: e.key, channels: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    debugPrint('[IPTV] Categories: ${_groups.length} '
        '(${_groups.take(5).map((g) => '${g.name}:${g.count}').join(', ')}, ...)');

    _loadRecentAndFrequent();
    _applyFilters();

    _isLoading = false;
    notifyListeners();
  }

  /// Fusionne les chaînes de même identité : la meilleure source devient
  /// principale, les autres URLs deviennent des secours (failover). Cap à 6.
  static List<ChannelEntity> _mergeDuplicates(List<ChannelEntity> channels) {
    final Map<String, ChannelEntity> merged = {};

    for (final c in channels) {
      final key = c.name.toLowerCase().trim();
      final existing = merged[key];

      if (existing == null) {
        merged[key] = c;
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

      merged[key] = primary.copyWith(backupUrls: backups);
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
            return _allChannels.firstWhere((c) => c.id == id);
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
            return _allChannels.firstWhere((c) => c.id == id);
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

  bool get showAdult => AppStorage.getShowAdult();

  void toggleShowAdult() {
    AppStorage.setShowAdult(!showAdult);
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
    var channels = List<ChannelEntity>.from(_allChannels);

    // Chaînes fiables FRAÎCHES : retirées de la liste principale (elles ont
    // leur onglet). Les confirmations périmées (>7j) reviennent pour re-test.
    final confirmed = AppStorage.getConfirmedChannels();
    if (confirmed.isNotEmpty) {
      channels = channels
          .where((c) =>
              !(confirmed.contains(c.id) && AppStorage.isReliableFresh(c.id)))
          .toList();
    }

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

    // Group/category (using normalized categories)
    if (_selectedGroup != 'Tout') {
      channels = channels.where((c) => categoryOf(c) == _selectedGroup).toList();
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
