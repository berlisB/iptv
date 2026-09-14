import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv/config/routes/app_router.dart';
import 'package:iptv/config/theme/app_theme.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/provider_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await AppStorage.init();
  _installCrashHandlers();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
}

/// Capture les erreurs qui, jusqu'ici, disparaissaient sans laisser de trace.
///
/// Deux canaux distincts, et il faut les DEUX : `FlutterError.onError` ne voit
/// que les erreurs levées pendant le build/layout/paint, tandis que celles des
/// Future non attendus — un `unawaited(...)`, un `.listen()` sans `onError` —
/// ne passent que par `PlatformDispatcher.onError`. C'est précisément cette
/// seconde catégorie qui domine dans une app de lecture réseau.
///
/// On les journalise au lieu de les avaler : sans ça, un crash rapporté par un
/// utilisateur ne laisse rien à analyser.
void _installCrashHandlers() {
  final flutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppStorage.logCrash('flutter', details.exception, details.stack);
    // On délègue ensuite au comportement par défaut, qui affiche l'erreur en
    // rouge dans la console et dans l'arbre de widgets en debug.
    flutterOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppStorage.logCrash('async', error, stack);
    debugPrint('[CRASH] $error\n$stack');
    // true = erreur traitée : l'app continue au lieu de terminer le processus.
    return true;
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: MaterialApp.router(
          title: 'IPTV Player',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
