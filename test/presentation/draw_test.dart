import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two kings that do not see each other on any diagonal: no capture is
/// possible, so they can walk in a circle and repeat the same position — the
/// classic draw by repetition.
GameState twoKings() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(0, 1): const Piece(Side.black, king: true),
  }),
  turn: Side.white,
);

/// A white king and a black simple piece: the limit is 30 quiet plies, because
/// a simple piece is still on the board.
GameState quietPosition({int quietPlies = 29}) => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(2, 1): const Piece(Side.black),
  }),
  turn: Side.white,
  quietPlies: quietPlies,
);

/// Only kings are left, so the quiet series may be twice as long.
GameState kingsOnlyPosition({int quietPlies = 59}) => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(0, 1): const Piece(Side.black, king: true),
  }),
  turn: Side.white,
  quietPlies: quietPlies,
);

Future<GameController> pumpGame(
  WidgetTester tester, {
  required SettingsController settings,
  required GameState state,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: GamePage(
          settings: settings,
          initialState: state,
          animationPerLanding: const Duration(milliseconds: 20),
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

Future<void> play(
  WidgetTester tester,
  GameController game,
  Square from,
  Square to,
) async {
  game.tap(from);
  await tester.pump();
  game.tap(to);
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('третье повторение позиции даёт ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(tester, settings: settings, state: twoKings());

    const circle = [
      [Square(5, 2), Square(4, 1)],
      [Square(0, 1), Square(1, 2)],
      [Square(4, 1), Square(5, 2)],
      [Square(1, 2), Square(0, 1)],
    ];

    // One full circle brings the position back, but only twice: no draw yet.
    for (final step in circle) {
      await play(tester, game, step.first, step.last);
    }
    expect(game.state.ply, 4);
    expect(game.isDraw, isFalse);
    expect(game.winner, isNull);

    for (final step in circle) {
      await play(tester, game, step.first, step.last);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(game.state.ply, 8);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(game.isOver, isTrue);
    expect(find.text('Ничья!'), findsOneWidget);
    expect(find.textContaining('позиция повторилась'), findsOneWidget);
    // No move can be played after the draw.
    expect(game.canInteract, isFalse);
    expect(find.byKey(const Key('hint-button')), findsNothing);
  });

  testWidgets('30 тихих полуходов дают ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: quietPosition(),
    );

    await play(tester, game, const Square(5, 2), const Square(4, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(game.state.quietPlies, 30);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(find.text('Ничья!'), findsOneWidget);
  });

  testWidgets('на 29 тихих полуходах партия продолжается', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: quietPosition(quietPlies: 28),
    );

    await play(tester, game, const Square(5, 2), const Square(4, 1));

    expect(game.state.quietPlies, 29);
    expect(game.quietLimit, 30);
    expect(game.isDraw, isFalse);
    expect(game.isOver, isFalse);
    expect(find.text('Ничья!'), findsNothing);
  });

  testWidgets('когда остались только дамки, 30 тихих полуходов — не ничья', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    // The same 30 quiet plies would already be a draw with a simple piece on
    // the board, but kings get twice as long.
    final game = await pumpGame(
      tester,
      settings: settings,
      state: kingsOnlyPosition(quietPlies: 30),
    );

    expect(game.quietLimit, 60);
    expect(game.state.quietPlies, 30);
    expect(game.isDraw, isFalse);
    expect(find.text('Ничья!'), findsNothing);
  });

  testWidgets('60 тихих полуходов у одних дамок дают ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: kingsOnlyPosition(),
    );

    await play(tester, game, const Square(5, 2), const Square(4, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(game.state.quietPlies, 60);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(find.text('Ничья!'), findsOneWidget);
  });

  testWidgets('ход простой шашкой обнуляет тихую серию', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 2): const Piece(Side.white),
          const Square(2, 1): const Piece(Side.black),
        }),
        turn: Side.white,
        quietPlies: 25,
      ),
    );

    await play(tester, game, const Square(5, 2), const Square(4, 3));

    expect(game.state.quietPlies, 0);
    expect(game.isDraw, isFalse);
  });
}
