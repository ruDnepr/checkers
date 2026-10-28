import 'dart:math';

import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/main.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:checkers_for_diana/presentation/setup_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('главное меню, выбор правил, режима и сложности', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(child: DianaApp(settings: settings, showSplash: false)),
    );
    expect(find.text('Играть'), findsOneWidget);
    expect(find.text('Сетевая игра'), findsOneWidget);
    await tester.tap(find.text('Играть'));
    await tester.pumpAndSettle();
    expect(find.text('Русские шашки'), findsOneWidget);
    expect(find.text('Международные шашки'), findsOneWidget);
    await tester.tap(find.text('Русские шашки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Против компьютера'));
    await tester.pumpAndSettle();
    expect(find.text('Лёгкий'), findsOneWidget);
    expect(find.text('Средний'), findsOneWidget);
    expect(find.text('Сложный'), findsOneWidget);
  });

  testWidgets('мини-игра показывает руку и возвращает согласованный цвет', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    Side? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Side>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GuessPage(
                        settings: settings,
                        random: Random(7),
                        revealDelay: const Duration(milliseconds: 500),
                      ),
                    ),
                  );
                },
                child: const Text('Начать'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Начать'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('hand-left')), findsOneWidget);
    expect(find.byKey(const Key('hand-right')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hand-left')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('ТЫ ИГРАЕШЬ'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, Random(7).nextInt(2) == 0 ? Side.white : Side.black);
  });

  testWidgets('доска, активная сторона, подсказка и отмена работают', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: GamePage(
            settings: settings,
            setup: const GameSetup(
              variant: GameVariant.russian,
              mode: GameMode.local,
              playerSide: Side.white,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('top-player-panel')),
        matching: find.byType(RotatedBox),
      ),
      findsOneWidget,
    );
    final game = tester.widget<BoardView>(find.byType(BoardView)).controller;
    await tester.runAsync(game.showHint);
    await tester.pump();
    expect(game.suggestedMove, isNotNull);
    final before = game.state.fingerprint;
    game.tap(const Square(5, 0));
    game.tap(const Square(4, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.state.turn, Side.black);
    expect(find.text('Ходят чёрные'), findsOneWidget);
    await tester.tap(find.byKey(const Key('undo-button')));
    await tester.pump();
    expect(game.state.fingerprint, before);
    await settings.setHints(false);
    await tester.pump();
    expect(find.byKey(const Key('hint-button')), findsNothing);
    expect(game.legalMoves, isNotEmpty);
  });
}
