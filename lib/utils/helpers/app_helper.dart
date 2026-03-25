class AppHelper {
  AppHelper._();

  static String getGroupIcon(String group) {
    switch (group.toLowerCase()) {
      case 'info':
        return '📰';
      case 'sport':
        return '⚽';
      case 'france':
        return '🇫🇷';
      case 'international':
        return '🌍';
      case 'jeunesse':
        return '🧒';
      case 'musique':
        return '🎵';
      default:
        return '📺';
    }
  }
}
