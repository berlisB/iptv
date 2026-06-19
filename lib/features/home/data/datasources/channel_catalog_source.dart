import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:iptv/features/home/data/models/catalog_channel_model.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';

/// Charge le catalogue curé.
///
/// Backend-ready : si [remoteUrl] est fourni, on tente d'abord le JSON distant
/// (même schéma que l'asset). En cas d'échec, repli automatique sur l'asset
/// local — l'app fonctionne donc 100% hors-ligne dès l'installation.
class ChannelCatalogSource {
  ChannelCatalogSource({this.remoteUrl, http.Client? client})
      : _client = client ?? http.Client();

  static const String assetPath = 'assets/catalog/channels.json';

  /// URL d'un catalogue distant (futur backend). Null = asset local uniquement.
  final String? remoteUrl;
  final http.Client _client;

  Future<List<ChannelEntity>> load() async {
    if (remoteUrl != null) {
      final remote = await _loadRemote(remoteUrl!);
      if (remote != null && remote.isNotEmpty) return remote;
      debugPrint('[Catalog] Distant indisponible → repli asset local');
    }
    return _loadAsset();
  }

  Future<List<ChannelEntity>?> _loadRemote(String url) async {
    try {
      final res = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.body.length > 2) {
        return _parse(res.body);
      }
    } catch (e) {
      debugPrint('[Catalog] Erreur distant: $e');
    }
    return null;
  }

  Future<List<ChannelEntity>> _loadAsset() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return _parse(raw);
    } catch (e) {
      debugPrint('[Catalog] Erreur asset: $e');
      return const [];
    }
  }

  List<ChannelEntity> _parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['channels'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(CatalogChannelModel.fromJson)
        .where((c) => c.id.isNotEmpty && c.url.isNotEmpty)
        .toList();
  }
}
