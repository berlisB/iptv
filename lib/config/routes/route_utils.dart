enum AppPage {
  splash(path: '/splash', name: 'Splash'),
  home(path: '/', name: 'Home'),
  player(path: '/player', name: 'Player'),
  favorites(path: '/favorites', name: 'Favorites');

  final String path;
  final String name;

  const AppPage({required this.path, required this.name});
}
