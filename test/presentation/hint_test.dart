import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Position where white must capture: the man on (5, 0) can take the black man
/// on (4, 1), and the man on (5, 6) cannot do anything.
GameState forcedCapture() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 0): const Piece(Side.white),
    const Square(5, 6): const Piece(Side.white),
    const Square(4, 1): const Piece(Side.black),
    const Square(1, 0): const Piece(Side.black),
  }),
  turn: Side.white,
);

Future<GameController> pumpGame(
  WidgetTester tester, {
  required SettingsController settings,
  GameState? state,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: GamePage(
          settings: settings,
          initialState: state,
          animationPerLanding: const Duration(milliseconds: 30),
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
  return tester.widget<BoardView>(find.byType(BoardView)).controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('подсказка появляется только после нажатия кнопки', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);

    final game = await pumpGame(tester, settings: settings);
    expect(game.suggestedMove, isNull);
    expect(game.hintText, isNull);
    expect(find.textContaining('подсвечен лучший ход'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('hint-button')));
    await tester.tap(find.byKey(const Key('hint-button')));
    await tester.pump();
    expect(find.text('Думаю…'), findsOneWidget);
    await tester.runAsync(() async {
      while (game.hintThinking) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(game.suggestedMove, isNotNull);
    expect(game.hintText, contains('подсвечен лучший ход'));
    expect(find.textContaining('подсвечен лучший ход'), findsOneWidget);

    // The bubble can be dismissed together with the highlight.
    await tester.tap(find.byKey(const Key('message-dismiss')));
    await tester.pump();
    expect(game.suggestedMove, isNull);
    expect(find.textContaining('подсвечен лучший ход'), findsNothing);
  });

  testWidgets('попытка походить без обязательного боя объясняется', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);

    final game = await pumpGame(
      tester,
      settings: settings,
      state: forcedCapture(),
    );
    expect(game.hasCapture, isTrue);
    // Nothing is said about the capture duty before the player tries to move.
    expect(find.text('Ходят белые'), findsOneWidget);

    game.tap(const Square(5, 6));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.selected, isNull);
    expect(game.notice, contains('бой обязателен'));
    expect(find.textContaining('Сейчас бой обязателен'), findsOneWidget);

    // Tapping an empty square is refused with the same explanation.
    game.tap(const Square(6, 1));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.notice, contains('обязателен'));
    expect(find.textContaining('спокойно походить нельзя'), findsOneWidget);

    await tester.tap(find.byKey(const Key('message-dismiss')));
    await tester.pump();
    expect(find.text('Ходят белые'), findsOneWidget);
    expect(game.notice, isNull);

    // The capturing piece can still be chosen and the series played.
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.selected, const Square(5, 0));
    game.tap(const Square(3, 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 1);
  });

  testWidgets('без подсказок запрещённый ход тоже объясняется, но коротко', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()
      ..sound = false
      ..hints = false;
    addTearDown(settings.dispose);

    final game = await pumpGame(
      tester,
      settings: settings,
      state: forcedCapture(),
    );
    expect(find.byKey(const Key('hint-button')), findsNothing);

    game.tap(const Square(5, 6));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.notice, 'Так ходить нельзя.');
    expect(find.text('Так ходить нельзя.'), findsOneWidget);

    // Rules are still enforced: the capture is the only accepted move.
    expect(game.legalMoves, hasLength(1));
    expect(game.legalMoves.single.isCapture, isTrue);
  });
}
