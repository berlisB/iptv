import 'package:flutter/foundation.dart';
import 'package:iptv/core/services/m3u_parser.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/m3u_data_source.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/entities/channel_group.dart';

class HomeProvider extends ChangeNotifier {
  List<ChannelEntity> _allChannels = [];
  List<ChannelEntity> _filteredChannels = [];
  List<ChannelEntity> _recentChannels = [];
  List<ChannelEntity> _frequentChannels = [];
  List<ChannelGroup> _groups = [];
  Set<String> _blocklist = {};

  // Filter state
  String _selectedGroup = 'Tout';
  final Set<String> _selectedCountries = {};
  final Set<String> _selectedLanguages = {};
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showHidden = false;
  bool _showGeoBlocked = false;
  bool _showUndefined = true;
  int _geoBlockedCount = 0;

  // Available filter options (built from data)
  Map<String, int> _countryCounts = {};
  Map<String, int> _languageCounts = {};

  List<ChannelEntity> get allChannels => _allChannels;
  List<ChannelEntity> get filteredChannels => _filteredChannels;
  List<ChannelEntity> get recentChannels => _recentChannels;
  List<ChannelEntity> get frequentChannels => _frequentChannels;
  List<ChannelGroup> get groups => _groups;
  String get selectedGroup => _selectedGroup;
  Set<String> get selectedCountries => _selectedCountries;
  Set<String> get selectedLanguages => _selectedLanguages;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get showHidden => _showHidden;
  bool get showGeoBlocked => _showGeoBlocked;
  bool get showUndefined => _showUndefined;
  int get geoBlockedCount => _geoBlockedCount;
  Map<String, int> get countryCounts => _countryCounts;
  Map<String, int> get languageCounts => _languageCounts;

  bool get hasActiveFilters =>
      _selectedGroup != 'Tout' ||
      _selectedCountries.isNotEmpty ||
      _selectedLanguages.isNotEmpty;

  int get activeFilterCount =>
      (_selectedGroup != 'Tout' ? 1 : 0) +
      _selectedCountries.length +
      _selectedLanguages.length;

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

    // Filter pipeline
    _allChannels = parsed.where((c) {
      final url = c.url.toLowerCase();
      if (url.contains('youtube.com') ||
          url.contains('youtu.be') ||
          url.contains('twitch.tv') ||
          url.contains('dailymotion.com')) {
        return false;
      }
      if (url.isEmpty) {
        return false;
      }
      if (_blocklist.contains(c.url)) {
        return false;
      }
      return true;
    }).toList();

    _geoBlockedCount = _allChannels.where((c) => c.isGeoBlocked).length;

    debugPrint('[IPTV] Parsed: ${parsed.length}, '
        'after filters: ${_allChannels.length}, '
        'geo-blocked: $_geoBlockedCount');

    // Deduplicate by name
    final seen = <String>{};
    _allChannels = _allChannels.where((c) {
      final key = c.name.toLowerCase().trim();
      if (seen.contains(key)) {
        return false;
      }
      seen.add(key);
      return true;
    }).toList();

    debugPrint('[IPTV] After dedup: ${_allChannels.length} channels');

    // Build groups
    final Map<String, List<ChannelEntity>> groupMap = {};
    for (final channel in _allChannels) {
      groupMap.putIfAbsent(channel.group, () => []);
      groupMap[channel.group]!.add(channel);
    }
    _groups = groupMap.entries
        .map((e) => ChannelGroup(name: e.key, channels: e.value))
        .where((g) {
          // Hide adult groups from the list unless enabled
          final n = g.name.toLowerCase();
          if (n.contains('xxx') || n.contains('adult') || n.contains('+18')) {
            return false;
          }
          return true;
        })
        .toList()
      // Sort by channel count (most popular first)
      ..sort((a, b) => b.count.compareTo(a.count));

    // Build country and language counts
    _countryCounts = {};
    _languageCounts = {};
    for (final c in _allChannels) {
      if (c.country.isNotEmpty) {
        _countryCounts[c.country] = (_countryCounts[c.country] ?? 0) + 1;
      }
      if (c.language.isNotEmpty) {
        _languageCounts[c.language] = (_languageCounts[c.language] ?? 0) + 1;
      }
    }

    _loadRecentAndFrequent();
    _applyFilters();

    _isLoading = false;
    notifyListeners();
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

  void toggleCountry(String country) {
    if (_selectedCountries.contains(country)) {
      _selectedCountries.remove(country);
    } else {
      _selectedCountries.add(country);
    }
    _applyFilters();
    notifyListeners();
  }

  void toggleLanguage(String language) {
    if (_selectedLanguages.contains(language)) {
      _selectedLanguages.remove(language);
    } else {
      _selectedLanguages.add(language);
    }
    _applyFilters();
    notifyListeners();
  }

  void clearAllFilters() {
    _selectedGroup = 'Tout';
    _selectedCountries.clear();
    _selectedLanguages.clear();
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

  /// Called from settings to refresh filters
  void refreshFilters() {
    _showHidden = AppStorage.getShowHidden();
    _showGeoBlocked = AppStorage.getShowGeoBlocked();
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    var channels = List<ChannelEntity>.from(_allChannels);

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
        final g = c.group.toLowerCase();
        return g != 'undefined' && g != 'autres' && g.isNotEmpty;
      }).toList();
    }

    // Group/category
    if (_selectedGroup != 'Tout') {
      channels = channels.where((c) => c.group == _selectedGroup).toList();
    }

    // Countries (multi-select OR)
    if (_selectedCountries.isNotEmpty) {
      channels = channels
          .where((c) => _selectedCountries.contains(c.country))
          .toList();
    }

    // Languages (multi-select OR)
    if (_selectedLanguages.isNotEmpty) {
      channels = channels
          .where((c) => _selectedLanguages.contains(c.language))
          .toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      channels = channels
          .where((c) =>
              c.name.toLowerCase().contains(query) ||
              c.group.toLowerCase().contains(query) ||
              c.country.toLowerCase().contains(query) ||
              c.language.toLowerCase().contains(query))
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
