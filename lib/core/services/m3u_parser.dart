import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class M3uParser {
  M3uParser._();

  // Precompiled regexes for performance (like Open TV's LazyLock pattern)
  static final _tvgNameRegex = RegExp(r'tvg-name="([^"]*)"');
  static final _tvgIdRegex = RegExp(r'tvg-id="([^"]*)"');
  static final _tvgLogoRegex = RegExp(r'tvg-logo="([^"]*)"');
  static final _groupTitleRegex = RegExp(r'group-title="([^"]*)"');
  static final _tvgLanguageRegex = RegExp(r'tvg-language="([^"]*)"');
  static final _tvgCountryRegex = RegExp(r'tvg-country="([^"]*)"');

  // EXTVLCOPT header regexes
  static final _httpReferrerRegex = RegExp(r'http-referrer=(.+)');
  static final _httpOriginRegex = RegExp(r'http-origin=(.+)');
  static final _httpUserAgentRegex = RegExp(r'http-user-agent=(.+)');

  // Movie file extensions
  static final _movieExtensions = {
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v',
  };

  static List<ChannelEntity> parse(String m3uContent) {
    final List<ChannelEntity> channels = [];
    final lines = m3uContent.split('\n');
    final Set<String> usedIds = {};

    String name = '';
    String logoUrl = '';
    String group = 'Autres';
    String tvgId = '';
    String language = '';
    String country = '';
    String? referrer;
    String? userAgent;
    String? httpOrigin;
    bool ignoreSSL = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.startsWith('#EXTINF:')) {
        // Parse EXTINF attributes
        tvgId = _extract(_tvgIdRegex, line);
        name = _extractDisplayName(line);

        // Fallback: use tvg-name if display name is empty
        if (name.isEmpty) {
          name = _extract(_tvgNameRegex, line);
        }

        logoUrl = _extract(_tvgLogoRegex, line);
        group = _extract(_groupTitleRegex, line);
        language = _extract(_tvgLanguageRegex, line);
        country = _extract(_tvgCountryRegex, line);

        if (group.isEmpty) group = 'Autres';

        // Reset headers for this channel
        referrer = null;
        userAgent = null;
        httpOrigin = null;
        ignoreSSL = false;
      } else if (line.toUpperCase().startsWith('#EXTVLCOPT:')) {
        // Parse VLC-specific options (HTTP headers)
        final value = line.substring(11).trim();

        final refMatch = _httpReferrerRegex.firstMatch(value);
        if (refMatch != null) referrer = refMatch.group(1)?.trim();

        final originMatch = _httpOriginRegex.firstMatch(value);
        if (originMatch != null) httpOrigin = originMatch.group(1)?.trim();

        final uaMatch = _httpUserAgentRegex.firstMatch(value);
        if (uaMatch != null) userAgent = uaMatch.group(1)?.trim();

        if (value.contains('no-check-certificates') ||
            value.contains('ssl-verify=false')) {
          ignoreSSL = true;
        }
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        // URL line - create the channel
        var id = tvgId.isNotEmpty ? tvgId : '${name}_${channels.length}';
        while (usedIds.contains(id)) {
          id = '${id}_${channels.length}';
        }
        usedIds.add(id);

        // Detect media type from URL extension
        final urlLower = line.toLowerCase();
        final mediaType = _movieExtensions.any((ext) => urlLower.endsWith(ext))
            ? MediaType.movie
            : MediaType.livestream;

        // Detect geo-blocked from name markers
        final nameLower = name.toLowerCase();
        final isGeoBlocked = nameLower.contains('[geo-blocked]') ||
            nameLower.contains('geo-blocked') ||
            name.contains('Ⓖ');

        channels.add(ChannelEntity(
          id: id,
          name: name,
          url: line,
          tvgId: tvgId,
          quality: _detectQuality(name),
          logoUrl: logoUrl,
          group: group,
          language: language,
          country: country,
          mediaType: mediaType,
          isGeoBlocked: isGeoBlocked,
          httpHeaders: ChannelHttpHeaders(
            referrer: referrer,
            userAgent: userAgent,
            httpOrigin: httpOrigin,
            ignoreSSL: ignoreSSL,
          ),
        ));

        // Reset all
        name = '';
        logoUrl = '';
        group = 'Autres';
        tvgId = '';
        language = '';
        country = '';
        referrer = null;
        userAgent = null;
        httpOrigin = null;
        ignoreSSL = false;
      }
    }

    return channels;
  }

  static String _extract(RegExp regex, String line) {
    return regex.firstMatch(line)?.group(1) ?? '';
  }

  // Détecte la qualité depuis les marqueurs courants dans le nom de la chaîne.
  static String _detectQuality(String name) {
    final n = name.toUpperCase();
    if (n.contains('4K') || n.contains('UHD') || n.contains('2160')) return '4K';
    if (n.contains('FHD') || n.contains('1080')) return 'FHD';
    if (n.contains('HD') || n.contains('720')) return 'HD';
    if (n.contains('SD') || n.contains('480')) return 'SD';
    return '';
  }

  static String _extractDisplayName(String line) {
    final commaIndex = line.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < line.length - 1) {
      return line.substring(commaIndex + 1).trim();
    }
    return '';
  }
}
