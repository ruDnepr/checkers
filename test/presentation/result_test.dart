import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('после сдачи показывается результат и возврат в меню', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GamePage(
                        settings: settings,
                        animationPerLanding: const Duration(milliseconds: 20),
                        setup: const GameSetup(
                          variant: GameVariant.russian,
                          mode: GameMode.local,
                          playerSide: Side.white,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Старт'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Старт'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GamePage), findsOneWidget);

    await tester.ensureVisible(find.text('Сдаться'));
    await tester.tap(find.text('Сдаться'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сдаться'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Чёрные победили!'), findsOneWidget);
    expect(find.text('Играть снова'), findsOneWidget);

    await tester.tap(find.text('В меню'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(GamePage), findsNothing);
    expect(find.text('Старт'), findsOneWidget);
    expect(settings.gamesPlayed, 1);
    expect(settings.gamesWon, 0);
  });

  testWidgets('международная доска 10×10 без подсказок сохраняет ходы', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()
      ..sound = false
      ..hints = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: GamePage(
            settings: settings,
            animationPerLanding: const Duration(milliseconds: 20),
            setup: const GameSetup(
              variant: GameVariant.international,
              mode: GameMode.local,
              playerSide: Side.white,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('hint-button')), findsNothing);
    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(board.controller.legalMoves, isNotEmpty);
    expect(board.controller.state.board.size, 10);
    expect(board.controller.state.board.count(Side.white), 20);
  });
}
