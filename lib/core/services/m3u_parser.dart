import 'package:iptv/features/home/domain/entities/channel_entity.dart';

class M3uParser {
  M3uParser._();

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

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.startsWith('#EXTINF:')) {
        tvgId = _extractAttribute(line, 'tvg-id');
        name = _extractDisplayName(line);
        logoUrl = _extractAttribute(line, 'tvg-logo');
        group = _extractAttribute(line, 'group-title');
        language = _extractAttribute(line, 'tvg-language');
        country = _extractAttribute(line, 'tvg-country');

        if (group.isEmpty) group = 'Autres';
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        // Generate a unique ID
        var id = tvgId.isNotEmpty ? tvgId : '${name}_${channels.length}';
        while (usedIds.contains(id)) {
          id = '${id}_${channels.length}';
        }
        usedIds.add(id);

        channels.add(ChannelEntity(
          id: id,
          name: name,
          url: line,
          logoUrl: logoUrl,
          group: group,
          language: language,
          country: country,
        ));

        name = '';
        logoUrl = '';
        group = 'Autres';
        tvgId = '';
        language = '';
        country = '';
      }
    }

    return channels;
  }

  static String _extractAttribute(String line, String attribute) {
    final regex = RegExp('$attribute="([^"]*)"');
    final match = regex.firstMatch(line);
    return match?.group(1) ?? '';
  }

  static String _extractDisplayName(String line) {
    final commaIndex = line.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < line.length - 1) {
      return line.substring(commaIndex + 1).trim();
    }
    return '';
  }
}
