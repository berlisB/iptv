import 'package:flutter/foundation.dart';
import 'package:iptv/features/epg/data/epg_service.dart';
import 'package:iptv/features/epg/domain/epg_programme.dart';

/// Charge le guide des programmes en arrière-plan et expose now/next par tvg-id.
class EpgProvider extends ChangeNotifier {
  Map<String, List<EpgProgramme>> _byChannel = {};
  bool _loading = false;
  bool _loaded = false;

  bool get isLoading => _loading;
  bool get hasData => _byChannel.isNotEmpty;

  /// Charge le guide pour les chaînes demandées (non bloquant, à appeler après
  /// le chargement des chaînes). Ne recharge pas si déjà fait.
  Future<void> load(Set<String> wantedIds) async {
    if (_loading || _loaded || wantedIds.isEmpty) return;
    _loading = true;
    notifyListeners();

    _byChannel = await EpgService.fetch(wantedIds: wantedIds);
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  /// Force un rechargement (ex: changement de jour).
  Future<void> refresh(Set<String> wantedIds) async {
    _loaded = false;
    await load(wantedIds);
  }

  /// Programme en cours + suivant pour une chaîne (vide si pas de guide).
  EpgNowNext nowNext(String tvgId, {DateTime? at}) {
    final list = _byChannel[tvgId];
    if (list == null || list.isEmpty) return const EpgNowNext();
    final now = at ?? DateTime.now().toUtc();

    EpgProgramme? current;
    EpgProgramme? next;
    for (final p in list) {
      if (!now.isBefore(p.start) && now.isBefore(p.stop)) {
        current = p;
      } else if (p.start.isAfter(now)) {
        next = p;
        break;
      }
    }
    return EpgNowNext(now: current, next: next);
  }
}
