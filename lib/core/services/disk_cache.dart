import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cache disque minimal pour les gros artefacts (catalogue ~1,5 Mo, playlists,
/// EPG gzippé). La fraîcheur est portée par `File.lastModified()` — pas de
/// fichier meta. SharedPreferences reste réservé aux petites valeurs.
class DiskCache {
  DiskCache._();

  static Directory? _dir;

  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/cache_v1');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  static Future<File> _file(String key) async =>
      File('${(await _cacheDir()).path}/$key');

  /// Contenu si présent et plus jeune que [maxAge] (null : ignore l'âge).
  static Future<String?> readString(String key, {Duration? maxAge}) async {
    final bytes = await readBytes(key, maxAge: maxAge);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  static Future<Uint8List?> readBytes(String key, {Duration? maxAge}) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      if (maxAge != null) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age > maxAge) return null;
      }
      return await f.readAsBytes();
    } catch (e) {
      debugPrint('[DiskCache] read $key: $e');
      return null;
    }
  }

  static Future<void> writeString(String key, String content) =>
      writeBytes(key, Uint8List.fromList(utf8.encode(content)));

  static Future<void> writeBytes(String key, Uint8List bytes) async {
    try {
      // Écriture atomique : tmp puis rename, pour ne jamais servir un
      // fichier tronqué après un kill en pleine écriture.
      final f = await _file(key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('[DiskCache] write $key: $e');
    }
  }
}
