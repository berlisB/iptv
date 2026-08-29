/// Identité stable d'une chaîne, partagée entre le pipeline Python
/// (tools/healthcheck.py) et l'app. `normalizeName` et `fnv1a64Hex` DOIVENT
/// rester strictement identiques à leurs homologues Python — tout écart casse
/// la correspondance favoris/scores/EPG entre le catalogue et l'app.
library;

import 'dart:convert';

const _qualityTokens = {
  '4k', 'uhd', 'fhd', 'hd', 'sd',
  '1080', '1080p', '720', '720p', '480', '480p',
};

final _nonAlnum = RegExp(r'[^a-z0-9]+');

/// tvg-id lowercase si présent, sinon hash FNV-1a du nom normalisé.
String stableChannelId({required String tvgId, required String name}) =>
    tvgId.isNotEmpty
        ? tvgId.toLowerCase()
        : 'n-${fnv1a64Hex(normalizeName(name))}';

/// Nom → clé d'identité : lowercase, sans ponctuation ni tokens de qualité.
String normalizeName(String name) => name
    .toLowerCase()
    .split(_nonAlnum)
    .where((t) => t.isNotEmpty && !_qualityTokens.contains(t))
    .join(' ');

/// FNV-1a 64 bits, hex sur 16 caractères (UTF-8).
String fnv1a64Hex(String text) {
  var h = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    h ^= byte;
    h *= 0x100000001b3; // wrap 64 bits natif du VM Dart
  }
  return (h >>> 32).toRadixString(16).padLeft(8, '0') +
      (h & 0xffffffff).toRadixString(16).padLeft(8, '0');
}
