import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A white man may take one black man and then a second one, so the series can
/// be finished after the first capture — Russian rules allow that.
GameState twoCaptures() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 0): const Piece(Side.white),
    const Square(4, 1): const Piece(Side.black),
    const Square(2, 3): const Piece(Side.black),
  }),
  turn: Side.white,
);

/// The king takes (6, 1) and then must take (4, 1); stopping on (5, 2) is not
/// allowed even though the landing square is free.
GameState kingMustContinue() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(7, 0): const Piece(Side.white, king: true),
    const Square(6, 1): const Piece(Side.black),
    const Square(4, 1): const Piece(Side.black),
  }),
  turn: Side.white,
);

Future<GameController> pumpGame(
  WidgetTester tester, {
  required SettingsController settings,
  required GameState state,
}) async {
  tester.view.physicalSize = const Size(400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: GamePage(
          settings: settings,
          initialState: state,
          animationPerLanding: const Duration(milliseconds: 30),
          setup: GameSetup(
            variant: state.variant,
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

  testWidgets('простая шашка может закончить бой после первой серии', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(tester, settings: settings, state: twoCaptures());

    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.selected, const Square(5, 0));
    game.tap(const Square(3, 2));
    await tester.pump();

    // The series is not applied yet: the player may continue with a second one.
    expect(game.state.ply, 0);
    expect(game.canFinishCapture, isTrue);
    expect(find.byKey(const Key('finish-capture-button')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('finish-capture-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-capture-button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 1);
    expect(game.state.board.at(const Square(3, 2)), isNotNull);
    expect(find.byKey(const Key('finish-capture-button')), findsNothing);
  });

  testWidgets('второе взятие доигрывает серию как раньше', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(tester, settings: settings, state: twoCaptures());

    game.tap(const Square(5, 0));
    await tester.pump();
    game.tap(const Square(3, 2));
    await tester.pump();
    game.tap(const Square(1, 4));
    await tester.pump(const Duration(milliseconds: 200));

    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 0);
    expect(game.state.board.at(const Square(1, 4)), isNotNull);
  });

  testWidgets('дамка не предлагает закончить бой досрочно', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: kingMustContinue(),
    );

    game.tap(const Square(7, 0));
    await tester.pump();
    game.tap(const Square(5, 2));
    await tester.pump();

    expect(game.state.ply, 0);
    expect(game.canFinishCapture, isFalse);
    expect(find.byKey(const Key('finish-capture-button')), findsNothing);

    game.tap(const Square(3, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 0);
  });

  testWidgets('лампочка в шапке скрывает только кнопку подсказки', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(tester, settings: settings, state: twoCaptures());

    expect(find.byKey(const Key('hint-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hint-toggle')));
    await tester.pump();
    expect(settings.hintButton, isFalse);
    expect(find.byKey(const Key('hint-button')), findsNothing);
    // The hints themselves stay on: legal moves are still highlighted.
    expect(settings.hints, isTrue);
    expect(game.legalMoves, isNotEmpty);
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.suggestedDestinations, isNotEmpty);

    await tester.tap(find.byKey(const Key('hint-toggle')));
    await tester.pump();
    expect(settings.hintButton, isTrue);
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
  });
}
