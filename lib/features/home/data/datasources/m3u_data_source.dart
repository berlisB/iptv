import 'package:flutter/services.dart';

class M3uDataSource {
  M3uDataSource._();

  static const String _frPlaylist = 'assets/playlists/fr.m3u';
  static const String _internationalPlaylist = 'assets/playlists/international.m3u8';

  static Future<String> loadFrenchPlaylist() async {
    return await rootBundle.loadString(_frPlaylist);
  }

  static Future<String> loadInternationalPlaylist() async {
    return await rootBundle.loadString(_internationalPlaylist);
  }

  static Future<String> loadAllPlaylists() async {
    final fr = await loadFrenchPlaylist();
    final intl = await loadInternationalPlaylist();
    return '$fr\n$intl';
  }
}
