import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class PlayerProvider extends ChangeNotifier {
  late Player _player;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _showControls = true;
  bool _isFullScreen = false;
  double _volume = 100.0;
  ChannelEntity? _currentChannel;

  Player get player => _player;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get showControls => _showControls;
  bool get isFullScreen => _isFullScreen;
  double get volume => _volume;
  ChannelEntity? get currentChannel => _currentChannel;

  void init() {
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32MB buffer for smooth streaming
      ),
    );

    _volume = AppStorage.getVolume();
    _player.setVolume(_volume);

    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    _player.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      notifyListeners();
    });
  }

  Future<void> playChannel(ChannelEntity channel) async {
    _currentChannel = channel;
    _isBuffering = true;
    notifyListeners();

    await _player.open(Media(channel.url));
    await AppStorage.addRecentChannel(channel.id);
    await AppStorage.incrementWatchCount(channel.id);
  }

  Future<void> togglePlayPause() async {
    await _player.playOrPause();
  }

  void toggleControls() {
    _showControls = !_showControls;
    notifyListeners();
  }

  void setShowControls(bool show) {
    _showControls = show;
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  Future<void> setVolume(double vol) async {
    _volume = vol;
    await _player.setVolume(vol);
    await AppStorage.setVolume(vol);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
