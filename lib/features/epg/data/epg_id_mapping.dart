/// Mapping entre les tvgId du catalogue et les channel id du guide XMLTV.
///
/// Le catalogue utilise des IDs comme "France24English.fr" tandis que le
/// guide XMLTV utilise "France.24.Anglais.fr". Ce mapping fait la jonction.
class EpgIdMapping {
  EpgIdMapping._();

  /// Catalog tvgId → EPG XMLTV channel id.
  static const Map<String, String> catalogToEpg = {
    // France 24
    'France24English.fr': 'France.24.Anglais.fr',
    'France24French.fr': 'France.24.fr',
    'France24Arabic.fr': 'France.24.Arabe.fr',
    'France24Spanish.fr': 'France.24.Espagnol.fr',

    // Euronews
    'EuronewsFrench.fr': 'Euronews.fr',
    'EuronewsEnglish.fr': 'Euronews.English.fr',
    'EuronewsArabic.fr': 'Euronews.Arabic.fr',
    'EuronewsGerman.fr': 'Euronews.Allemand.fr',
    'EuronewsItalian.fr': 'Euronews.Italien.fr',
    'EuronewsSpanish.fr': 'Euronews.Espagnol.fr',
    'EuronewsRussian.fr': 'Euronews.Russe.fr',
    'EuronewsPortuguese.fr': 'Euronews.Portugais.fr',
    'EuronewsTurkish.fr': 'Euronews.Turc.fr',
    'EuronewsGreek.fr': 'Euronews.Grec.fr',
    'EuronewsHungarian.fr': 'Euronews.Hongrois.fr',
    'EuronewsPersian.fr': 'Euronews.Persan.fr',
    'EuronewsPolish.fr': 'Euronews.Polonais.fr',
    'EuronewsUkrainian.fr': 'Euronews.Ukrainien.fr',
    'EuronewsJapanese.fr': 'Euronews.Japonais.fr',
    'EuronewsKorean.fr': 'Euronews.Coreen.fr',
    'EuronewsIndonesian.fr': 'Euronews.Indonesien.fr',
    'EuronewsBulgarian.fr': 'Euronews.Bulgare.fr',
    'EuronewsRomanian.fr': 'Euronews.Roumain.fr',

    // DW
    'DWEnglish.de': 'DW-TV.fr',
    'DWDeutsch.de': 'DW-TV.de',
    'DWArabic.de': 'DW-TV.Arabic.fr',

    // CGTN
    'CGTNEnglish.cn': 'CGTN.English.fr',
    'CGTNFrench.cn': 'CGTN.Français.fr',
    'CGTNArabic.cn': 'CGTN.Arabic.fr',
    'CGTNSpanish.cn': 'CGTN.Espagnol.fr',
    'CGTNRussian.cn': 'CGTN.Russe.fr',

    // CCTV
    'CCTV1.cn': 'CCTV-1.fr',
    'CCTV4.cn': 'CCTV-4.fr',
    'CCTV9.cn': 'CCTV-9.fr',
    'CCTV13.cn': 'CCTV-NEWS.fr',

    // NHK
    'NHKWorldJapan.jp': 'NHK.World.Premium.fr',

    // TV5 Monde
    'TV5MONDEInfo.fr': 'TV5.Monde.fr',

    // Al Jazeera
    'AlJazeeraEnglish': 'Al.Jazeera.English.fr',
    'AlJazeeraArabic': 'Al.Jazeera.fr',

    // France TV
    'France5': 'France.5.fr',
    'Arte': 'Arte.fr',
    'FranceInfo': 'Franceinfo.fr',
  };

  /// Convertit un tvgId du catalogue en channel id XMLTV.
  /// Retourne l'ID original si pas de mapping trouvé.
  static String toEpgId(String catalogId) {
    return catalogToEpg[catalogId] ?? catalogId;
  }

  /// Convertit un set de tvgId catalogue en set de channel id XMLTV.
  static Set<String> toEpgIds(Set<String> catalogIds) {
    return catalogIds.map(toEpgId).toSet();
  }
}
