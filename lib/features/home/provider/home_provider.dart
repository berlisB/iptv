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
  String _selectedGroup = 'Tout';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showHidden = false;

  List<ChannelEntity> get allChannels => _allChannels;
  List<ChannelEntity> get filteredChannels => _filteredChannels;
  List<ChannelEntity> get recentChannels => _recentChannels;
  List<ChannelEntity> get frequentChannels => _frequentChannels;
  List<ChannelGroup> get groups => _groups;
  String get selectedGroup => _selectedGroup;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get showHidden => _showHidden;

  List<String> get groupNames {
    final names = ['Tout', ..._groups.map((g) => g.name)];
    return names;
  }

  Future<void> loadChannels() async {
    _isLoading = true;
    notifyListeners();

    final m3uContent = await M3uDataSource.loadAllPlaylists();
    final parsed = M3uParser.parse(m3uContent);

    // Filter out non-streamable URLs
    _allChannels = parsed.where((c) {
      final url = c.url.toLowerCase();
      return !url.contains('youtube.com') &&
          !url.contains('youtu.be') &&
          !url.contains('twitch.tv') &&
          !url.contains('dailymotion.com') &&
          url.isNotEmpty;
    }).toList();

    // Deduplicate by name
    final seen = <String>{};
    _allChannels = _allChannels.where((c) {
      final key = c.name.toLowerCase().trim();
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();

    // Build groups
    final Map<String, List<ChannelEntity>> groupMap = {};
    for (final channel in _allChannels) {
      groupMap.putIfAbsent(channel.group, () => []);
      groupMap[channel.group]!.add(channel);
    }

    _groups = groupMap.entries
        .map((e) => ChannelGroup(name: e.key, channels: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    _loadRecentAndFrequent();
    _applyFilters();

    _isLoading = false;
    notifyListeners();
  }

  void _loadRecentAndFrequent() {
    // Recent
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

    // Frequent
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

  void selectGroup(String group) {
    _selectedGroup = group;
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
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    var channels = List<ChannelEntity>.from(_allChannels);

    // Filter hidden channels
    if (!_showHidden) {
      final hidden = AppStorage.getHiddenChannels();
      channels = channels.where((c) => !hidden.contains(c.id)).toList();
    }

    // Filter by group
    if (_selectedGroup != 'Tout') {
      channels = channels.where((c) => c.group == _selectedGroup).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      channels = channels
          .where((c) =>
              c.name.toLowerCase().contains(query) ||
              c.group.toLowerCase().contains(query))
          .toList();
    }

    _filteredChannels = channels;
  }

  bool isFavorite(String channelId) {
    return AppStorage.isFavorite(channelId);
  }

  Future<void> toggleFavorite(String channelId) async {
    if (AppStorage.isFavorite(channelId)) {
      await AppStorage.removeFavorite(channelId);
    } else {
      await AppStorage.addFavorite(channelId);
    }
    notifyListeners();
  }

  bool isHidden(String channelId) {
    return AppStorage.isHidden(channelId);
  }

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
