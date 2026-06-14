enum AppPage {
  splash(path: '/splash', name: 'Splash'),
  home(path: '/', name: 'Home'),
  player(path: '/player', name: 'Player'),
  favorites(path: '/favorites', name: 'Favorites'),
  reliable(path: '/reliable', name: 'Reliable'),
  settings(path: '/settings', name: 'Settings');

  final String path;
  final String name;

  const AppPage({required this.path, required this.name});
}
