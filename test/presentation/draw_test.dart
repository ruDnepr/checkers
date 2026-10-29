import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('третье повторение позиции даёт ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: twoKings(),
      size: const Size(400, 900),
    );

    const circle = [
      [Square(5, 2), Square(4, 1)],
      [Square(0, 1), Square(1, 2)],
      [Square(4, 1), Square(5, 2)],
      [Square(1, 2), Square(0, 1)],
    ];

    // One full circle brings the position back, but only twice: no draw yet.
    for (final step in circle) {
      await playMove(tester, game, step.first, step.last);
    }
    expect(game.state.ply, 4);
    expect(game.isDraw, isFalse);
    expect(game.winner, isNull);

    for (final step in circle) {
      await playMove(tester, game, step.first, step.last);
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
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
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
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 1));

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
      size: const Size(400, 900),
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
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
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
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 3));

    expect(game.state.quietPlies, 0);
    expect(game.isDraw, isFalse);
  });
}
