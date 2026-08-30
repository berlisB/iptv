import 'package:flutter/foundation.dart';
import 'package:iptv/core/services/stream_validator.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/repositories/channel_repository_impl.dart';
import 'package:iptv/features/home/domain/entities/channel_entity.dart';
import 'package:iptv/features/home/domain/repositories/channel_repository.dart';
import 'package:iptv/features/home/domain/services/channel_filter.dart';

/// Orchestrateur métier du module live : combine [ChannelRepository] (catalogue
/// curé), [StreamValidator] (liveness) et [ChannelFilter] (audience/score).
///
/// C'est le point d'entrée que les providers/l'UI consommeront en Phase 2.
/// Aucune dépendance Flutter UI ici.
class ChannelService {
  ChannelService({
    ChannelRepository? repository,
    StreamValidator? validator,
    ChannelFilter filter = const ChannelFilter(),
  })  : _repo = repository ?? ChannelRepositoryImpl(),
        _validator = validator ?? StreamValidator(),
        _filter = filter;

  final ChannelRepository _repo;
  final StreamValidator _validator;
  final ChannelFilter _filter;

  /// Charge le catalogue curé (score persistant déjà appliqué par le repo).
  Future<List<ChannelEntity>> loadCatalog() => _repo.getCuratedChannels();

  /// Mode "Sélection fiable".
  List<ChannelEntity> reliableSelection(List<ChannelEntity> channels) =>
      _filter.reliable(channels);

  /// Mode "Explorer".
  List<ChannelEntity> exploreSelection(List<ChannelEntity> channels) =>
      _filter.explore(channels);

  /// Valide un flux et met à jour son score selon le résultat.
  /// Ne supprime jamais une chaîne : seul le score bouge (decay/récompense).
  Future<ChannelStatus> validateAndScore(ChannelEntity channel) async {
    final headers = channel.httpHeaders.toHttpMap();
    // offline seulement sur échec dur AVÉRÉ (404/410). Un 403 sur un GET
    // Range est massivement un faux positif (CDN exigeant headers/token que
    // mpv envoie mais pas forcément le probe) → pénalité douce seulement.
    var status = ChannelStatus.unknown;

    for (final url in channel.allUrls) {
      final outcome = await _validator.probe(url, headers: headers);
      switch (outcome) {
        case ProbeOutcome.ok:
          await AppStorage.recordSuccess(channel.id);
          return ChannelStatus.online;
        case ProbeOutcome.notFound:
          await AppStorage.recordHardFail(channel.id);
          status = ChannelStatus.offline;
        case ProbeOutcome.forbidden:
        case ProbeOutcome.error:
          await AppStorage.recordSoftFail(channel.id);
        case ProbeOutcome.timeout:
          await AppStorage.recordTimeout(channel.id);
      }
    }
    return status;
  }

  /// Valide en arrière-plan un lot de chaînes (concurrence limitée pour ne pas
  /// saturer le réseau). Renvoie la map id → statut.
  Future<Map<String, ChannelStatus>> validateBatch(
    List<ChannelEntity> channels, {
    int concurrency = 6,
  }) async {
    final results = <String, ChannelStatus>{};
    for (var i = 0; i < channels.length; i += concurrency) {
      final slice = channels.skip(i).take(concurrency);
      final statuses = await Future.wait(
        slice.map((c) async => MapEntry(c.id, await validateAndScore(c))),
      );
      results.addEntries(statuses);
    }
    debugPrint('[ChannelService] Validé ${results.length} chaînes');
    return results;
  }

}
