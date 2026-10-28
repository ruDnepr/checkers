import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/settings.dart';
import 'presentation/home.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = SettingsController();
  await settings.load();
  runApp(ProviderScope(child: DianaApp(settings: settings)));
}

class DianaApp extends StatelessWidget {
  const DianaApp({super.key, required this.settings, this.showSplash = true});
  final SettingsController settings;
  final bool showSplash;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Шашки для Дианы',
    debugShowCheckedModeBanner: false,
    theme: dianaTheme(),
    home: showSplash
        ? SplashPage(settings: settings)
        : HomePage(settings: settings),
  );
}
