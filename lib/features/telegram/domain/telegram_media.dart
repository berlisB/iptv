/// Un fichier vidéo publié dans le canal Telegram, et ce qu'on a réussi à
/// comprendre de son nom.
///
/// Les fichiers d'un canal sont nommés en « scene release » :
///
///   The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv
///   Breaking.Bad.S01E05.MULTI.1080p.mkv
///   Inception (2010) TRUEFRENCH 2160p.mp4
///
/// Tout l'intérêt de la fonctionnalité tient à la qualité de ce découpage :
/// sans titre et année propres, aucun match TMDB, donc pas d'affiche, pas de
/// synopsis, et une liste de noms de fichiers bruts. C'est pour ça que le
/// parsing vit dans le domaine, isolé et testé, plutôt que dilué dans l'UI.
library;

import 'package:equatable/equatable.dart';

/// Ce que le canal propose : un film, ou un épisode de série.
enum TelegramMediaKind { movie, episode }

class TelegramMedia extends Equatable {
  /// Identifiant du message dans le canal — c'est la clé de téléchargement.
  final int messageId;

  /// Identifiant TDLib du fichier, requis par `downloadFile`.
  final int fileId;

  /// Nom de fichier d'origine, conservé tel quel : c'est le seul recours
  /// affichable quand le parsing échoue.
  final String fileName;

  /// Titre nettoyé, prêt pour une recherche TMDB.
  final String title;

  /// Année de sortie, 0 si absente du nom.
  final int year;

  final TelegramMediaKind kind;

  /// Saison et épisode, 0 pour un film.
  final int season;
  final int episode;

  /// Taille en octets et durée en secondes, rapportées par Telegram.
  final int sizeBytes;
  final int durationSeconds;

  /// Légende du message, souvent porteuse du synopsis.
  final String caption;

  /// Marqueurs de langue relevés dans le nom (VF, VOSTFR, MULTI…).
  final List<String> languageTags;

  /// Marqueur de qualité le plus élevé trouvé (2160p, 1080p…), vide sinon.
  final String quality;

  const TelegramMedia({
    required this.messageId,
    required this.fileId,
    required this.fileName,
    required this.title,
    this.year = 0,
    this.kind = TelegramMediaKind.movie,
    this.season = 0,
    this.episode = 0,
    this.sizeBytes = 0,
    this.durationSeconds = 0,
    this.caption = '',
    this.languageTags = const [],
    this.quality = '',
  });

  bool get isEpisode => kind == TelegramMediaKind.episode;

  /// Libellé d'affichage, avec repli sur le nom de fichier si le parsing n'a
  /// rien donné d'exploitable.
  String get displayTitle {
    if (title.isEmpty) return fileName;
    if (isEpisode) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      return '$title · S${s}E$e';
    }
    return year > 0 ? '$title ($year)' : title;
  }

  /// Taille lisible, affichée avant téléchargement : sur mobile, savoir qu'un
  /// fichier pèse 4,2 Go avant de le lancer change la décision.
  String get readableSize {
    if (sizeBytes <= 0) return '';
    const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
    var value = sizeBytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final decimals = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  String get readableDuration {
    if (durationSeconds <= 0) return '';
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}min';
  }

  /// Clé de regroupement des épisodes d'une même série.
  String get seriesKey => isEpisode ? title.toLowerCase() : '';

  @override
  List<Object?> get props => [messageId];
}

// ---------------------------------------------------------------------------
// Parsing des noms de release
// ---------------------------------------------------------------------------

/// Marqueurs à retirer du titre : qualité, source, codec, langue, team.
/// Tout ce qui suit le PREMIER de ces marqueurs est du bruit technique, ce qui
/// donne une règle de coupe bien plus fiable qu'un retrait terme à terme.
const _noiseTokens = <String>{
  // résolution
  '2160p', '1080p', '720p', '480p', '360p', '4k', 'uhd', 'fhd', 'hd', 'sd',
  'hdlight', 'hdrip', 'bdrip', 'brrip', 'dvdrip', 'webrip', 'web',
  'webdl', 'bluray', 'bdremux', 'remux', 'hdtv', 'dvdscr', 'cam', 'ts',
  'telesync', 'r5', 'vodrip',
  // codec / audio
  'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'xvid', 'divx', 'av1',
  'aac', 'ac3', 'eac3', 'dts', 'dd5', 'ddp5', 'truehd', 'atmos', 'flac',
  'mp3', '10bit', '8bit', 'hdr', 'hdr10', 'dolby', 'vision', 'sdr',
  // langue
  'vf', 'vff', 'vfq', 'vfi', 'vo', 'vost', 'vostfr', 'vosta', 'multi',
  'truefrench', 'french', 'english', 'subfrench', 'dual', 'dubbed',
  'subbed', 'fansub',
  // divers
  'integrale', 'complete', 'extended', 'unrated', 'directors', 'remastered',
  'proper', 'repack', 'internal', 'limited', 'custom',
};

/// Marqueurs de langue qu'on garde comme métadonnée au lieu de les jeter.
const _languageTokens = <String, String>{
  'vf': 'VF', 'vff': 'VF', 'vfq': 'VFQ', 'vfi': 'VF',
  'truefrench': 'VF', 'french': 'VF',
  'vostfr': 'VOSTFR', 'vost': 'VOSTFR', 'subfrench': 'VOSTFR',
  'vo': 'VO', 'english': 'VO',
  'multi': 'MULTI', 'dual': 'MULTI',
};

const _qualityRanking = <String>['2160p', '1080p', '720p', '480p', '360p'];

/// S01E05, S1E5, 1x05, S01.E05
/// Le numéro d'épisode va jusqu'à 4 chiffres : les animes au long cours
/// (One Piece S01E1089) dépassent largement les 999 épisodes.
final _seasonEpisodeRe = RegExp(
  r's(\d{1,2})[\s._-]*e(\d{1,4})|(?<![a-z0-9])(\d{1,2})x(\d{1,4})(?![a-z0-9])',
  caseSensitive: false,
);

/// « Saison 2 Episode 5 » / « Season 2 Episode 5 »
final _verboseSeasonRe = RegExp(
  r'sai?son[\s._-]*(\d{1,2})[\s._-]*(?:episode|ep)[\s._-]*(\d{1,4})',
  caseSensitive: false,
);

/// Année plausible entre 1900 et 2099, éventuellement entre parenthèses.
final _yearRe = RegExp(r'(?<![0-9])(19\d{2}|20\d{2})(?![0-9])');

final _extensionRe = RegExp(r'\.(mkv|mp4|avi|mov|m4v|ts|webm)$', caseSensitive: false);
final _separatorRe = RegExp(r'[._\-\s]+');
final _bracketRe = RegExp(r'[\[\](){}]');

/// Découpe un nom de fichier de release en [TelegramMedia] exploitable.
///
/// La stratégie, dans l'ordre, parce que chaque étape réduit le bruit pour la
/// suivante :
///   1. retirer l'extension et normaliser les séparateurs ;
///   2. repérer saison/épisode — c'est ce qui décide film vs série, et ça
///      borne le titre à gauche du marqueur ;
///   3. repérer l'année — elle borne aussi le titre, et sert au match TMDB ;
///   4. couper au premier marqueur technique rencontré ;
///   5. garder la borne la plus à GAUCHE des trois, car tout ce qui suit le
///      premier marqueur appartient déjà aux métadonnées.
TelegramMedia parseTelegramFileName(
  String fileName, {
  required int messageId,
  required int fileId,
  int sizeBytes = 0,
  int durationSeconds = 0,
  String caption = '',
}) {
  final withoutExt = fileName.replaceAll(_extensionRe, '');
  final normalized = withoutExt.replaceAll(_bracketRe, ' ');

  var season = 0;
  var episode = 0;
  var cutIndex = normalized.length;

  // 2. saison / épisode
  final verbose = _verboseSeasonRe.firstMatch(normalized);
  final compact = _seasonEpisodeRe.firstMatch(normalized);
  final seMatch = verbose ?? compact;
  if (seMatch != null) {
    if (seMatch == verbose) {
      season = int.tryParse(seMatch.group(1) ?? '') ?? 0;
      episode = int.tryParse(seMatch.group(2) ?? '') ?? 0;
    } else {
      // Le motif compact a deux alternatives : SxxExx, ou NxNN.
      season = int.tryParse(seMatch.group(1) ?? seMatch.group(3) ?? '') ?? 0;
      episode = int.tryParse(seMatch.group(2) ?? seMatch.group(4) ?? '') ?? 0;
    }
    cutIndex = seMatch.start;
  }

  // 3. année
  var year = 0;
  for (final m in _yearRe.allMatches(normalized)) {
    final candidate = int.parse(m.group(1)!);
    // Une année ne peut pas ouvrir le nom : « 1917.2019.1080p » — le titre
    // EST 1917, et l'année est la seconde occurrence.
    if (m.start == 0) continue;
    year = candidate;
    if (m.start < cutIndex) cutIndex = m.start;
    break;
  }

  // 4. premier marqueur technique
  final tokens = normalized.split(_separatorRe);
  final languages = <String>[];
  var quality = '';
  var offset = 0;
  var noiseCut = normalized.length;
  for (final token in tokens) {
    final lower = token.toLowerCase();
    final start = normalized.indexOf(token, offset);
    offset = start >= 0 ? start + token.length : offset;
    if (lower.isEmpty) continue;

    final lang = _languageTokens[lower];
    if (lang != null && !languages.contains(lang)) languages.add(lang);
    if (_qualityRanking.contains(lower)) {
      if (quality.isEmpty ||
          _qualityRanking.indexOf(lower) < _qualityRanking.indexOf(quality)) {
        quality = lower;
      }
    }
    if (_noiseTokens.contains(lower) && start > 0 && start < noiseCut) {
      noiseCut = start;
    }
  }
  if (noiseCut < cutIndex) cutIndex = noiseCut;

  // 5. titre = ce qui reste à gauche de la borne la plus précoce.
  var title = normalized
      .substring(0, cutIndex.clamp(0, normalized.length))
      .replaceAll(_separatorRe, ' ')
      .trim();
  // Un titre vide signifie que le nom n'était QUE des métadonnées : on préfère
  // alors afficher le nom de fichier brut plutôt qu'une ligne vide.
  if (title.isEmpty) {
    title = withoutExt.replaceAll(_separatorRe, ' ').trim();
  }

  final isEpisode = season > 0 || episode > 0;
  return TelegramMedia(
    messageId: messageId,
    fileId: fileId,
    fileName: fileName,
    title: title,
    year: year,
    kind: isEpisode ? TelegramMediaKind.episode : TelegramMediaKind.movie,
    season: season,
    episode: episode,
    sizeBytes: sizeBytes,
    durationSeconds: durationSeconds,
    caption: caption,
    languageTags: languages,
    quality: quality,
  );
}
