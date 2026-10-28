import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/main.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:checkers_for_diana/presentation/setup_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'на устройстве открываются меню, жеребьёвка и партия вдвоём',
    (tester) async {
      final settings = SettingsController();
      await settings.load();
      await settings.setSound(false);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        ProviderScope(child: DianaApp(settings: settings, showSplash: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Играть'), findsOneWidget);
      await tester.tap(find.text('Играть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русские шашки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Два игрока'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GuessPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('hand-left')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ТЫ ИГРАЕШЬ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(GamePage), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
