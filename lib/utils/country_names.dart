class CountryNames {
  CountryNames._();

  static String getFullName(String code) {
    return _map[code.toUpperCase()] ?? code;
  }

  static const Map<String, String> _map = {
    'AF': 'Afghanistan', 'AL': 'Albanie', 'DZ': 'Algérie', 'AD': 'Andorre',
    'AO': 'Angola', 'AR': 'Argentine', 'AM': 'Arménie', 'AU': 'Australie',
    'AT': 'Autriche', 'AZ': 'Azerbaïdjan', 'BS': 'Bahamas', 'BH': 'Bahreïn',
    'BD': 'Bangladesh', 'BB': 'Barbade', 'BY': 'Biélorussie', 'BE': 'Belgique',
    'BJ': 'Bénin', 'BO': 'Bolivie', 'BA': 'Bosnie-Herzégovine', 'BR': 'Brésil',
    'BN': 'Brunei', 'BG': 'Bulgarie', 'BF': 'Burkina Faso', 'BI': 'Burundi',
    'KH': 'Cambodge', 'CM': 'Cameroun', 'CA': 'Canada', 'CV': 'Cap-Vert',
    'CF': 'Centrafrique', 'TD': 'Tchad', 'CL': 'Chili', 'CN': 'Chine',
    'CO': 'Colombie', 'KM': 'Comores', 'CG': 'Congo', 'CD': 'RD Congo',
    'CR': 'Costa Rica', 'CI': "Côte d'Ivoire", 'HR': 'Croatie', 'CU': 'Cuba',
    'CY': 'Chypre', 'CZ': 'Tchéquie', 'DK': 'Danemark', 'DJ': 'Djibouti',
    'DO': 'Rép. Dominicaine', 'EC': 'Équateur', 'EG': 'Égypte',
    'SV': 'El Salvador', 'GQ': 'Guinée Équatoriale', 'EE': 'Estonie',
    'ET': 'Éthiopie', 'FI': 'Finlande', 'FR': 'France', 'GA': 'Gabon',
    'GM': 'Gambie', 'GE': 'Géorgie', 'DE': 'Allemagne', 'GH': 'Ghana',
    'GR': 'Grèce', 'GT': 'Guatemala', 'GN': 'Guinée', 'HT': 'Haïti',
    'HN': 'Honduras', 'HK': 'Hong Kong', 'HU': 'Hongrie', 'IS': 'Islande',
    'IN': 'Inde', 'ID': 'Indonésie', 'IR': 'Iran', 'IQ': 'Irak',
    'IE': 'Irlande', 'IL': 'Israël', 'IT': 'Italie', 'JM': 'Jamaïque',
    'JP': 'Japon', 'JO': 'Jordanie', 'KZ': 'Kazakhstan', 'KE': 'Kenya',
    'KP': 'Corée du Nord', 'KR': 'Corée du Sud', 'KW': 'Koweït',
    'KG': 'Kirghizistan', 'LA': 'Laos', 'LV': 'Lettonie', 'LB': 'Liban',
    'LY': 'Libye', 'LI': 'Liechtenstein', 'LT': 'Lituanie',
    'LU': 'Luxembourg', 'MK': 'Macédoine du Nord', 'MG': 'Madagascar',
    'MW': 'Malawi', 'MY': 'Malaisie', 'MV': 'Maldives', 'ML': 'Mali',
    'MT': 'Malte', 'MR': 'Mauritanie', 'MU': 'Maurice', 'MX': 'Mexique',
    'MD': 'Moldavie', 'MC': 'Monaco', 'MN': 'Mongolie', 'ME': 'Monténégro',
    'MA': 'Maroc', 'MZ': 'Mozambique', 'MM': 'Myanmar', 'NA': 'Namibie',
    'NP': 'Népal', 'NL': 'Pays-Bas', 'NZ': 'Nouvelle-Zélande',
    'NI': 'Nicaragua', 'NE': 'Niger', 'NG': 'Nigeria', 'NO': 'Norvège',
    'OM': 'Oman', 'PK': 'Pakistan', 'PS': 'Palestine', 'PA': 'Panama',
    'PY': 'Paraguay', 'PE': 'Pérou', 'PH': 'Philippines', 'PL': 'Pologne',
    'PT': 'Portugal', 'PR': 'Porto Rico', 'QA': 'Qatar', 'RO': 'Roumanie',
    'RU': 'Russie', 'RW': 'Rwanda', 'SA': 'Arabie Saoudite', 'SN': 'Sénégal',
    'RS': 'Serbie', 'SG': 'Singapour', 'SK': 'Slovaquie', 'SI': 'Slovénie',
    'SO': 'Somalie', 'ZA': 'Afrique du Sud', 'ES': 'Espagne',
    'LK': 'Sri Lanka', 'SD': 'Soudan', 'SE': 'Suède', 'CH': 'Suisse',
    'SY': 'Syrie', 'TW': 'Taïwan', 'TZ': 'Tanzanie', 'TH': 'Thaïlande',
    'TG': 'Togo', 'TN': 'Tunisie', 'TR': 'Turquie', 'TM': 'Turkménistan',
    'UG': 'Ouganda', 'UA': 'Ukraine', 'AE': 'Émirats Arabes Unis',
    'GB': 'Royaume-Uni', 'UK': 'Royaume-Uni', 'US': 'États-Unis',
    'UY': 'Uruguay', 'UZ': 'Ouzbékistan', 'VE': 'Venezuela',
    'VN': 'Vietnam', 'YE': 'Yémen', 'ZM': 'Zambie', 'ZW': 'Zimbabwe',
    'INT': 'International', 'UNDEFINED': 'Non défini',
  };
}
