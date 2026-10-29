import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A position where white must capture, so a refused tap produces a notice.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('доска не двигается, когда появляется подсказка', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(tester, settings: settings);

    final board = tester.getRect(find.byType(BoardView));
    final bubble = tester.getRect(find.byKey(const Key('message-bubble')));

    await tester.runAsync(game.showHint);
    await tester.pump();

    expect(game.hintText, isNotNull);
    // The board keeps its place and its size: a longer message used to squeeze
    // it, and that is what looked like the board shuddering.
    expect(tester.getRect(find.byType(BoardView)), board);
    expect(tester.getRect(find.byKey(const Key('message-bubble'))), bubble);
  });

  testWidgets('доска не двигается при выборе шашки и отказе в ходе', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpGame(
      tester,
      settings: settings,
      state: forcedCapture(),
    );

    final before = tester.getRect(find.byType(BoardView));

    // A tap on a piece that cannot move: the bubble explains the capture duty.
    game.tap(const Square(5, 6));
    await tester.pump();
    expect(game.notice, isNotNull);
    expect(tester.getRect(find.byType(BoardView)), before);

    // Dismissing the notice must not move it either.
    await tester.tap(find.byKey(const Key('message-dismiss')));
    await tester.pump();
    expect(game.notice, isNull);
    expect(tester.getRect(find.byType(BoardView)), before);

    // A tap on the piece that must capture: the legal landings are shown.
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.selected, const Square(5, 0));
    expect(game.suggestedDestinations, isNotEmpty);
    expect(tester.getRect(find.byType(BoardView)), before);
  });

  testWidgets('ряд кнопок не ломает доску и кнопки остаются крупными', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    // Russian rules: the man may stop after the first capture, so the row gains
    // «Закончить бой» while the series is half played.
    final game = await pumpGame(
      tester,
      settings: settings,
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 0): const Piece(Side.white),
          const Square(4, 1): const Piece(Side.black),
          const Square(2, 3): const Piece(Side.black),
        }),
        turn: Side.white,
      ),
      size: const Size(400, 900),
    );
    final before = tester.getRect(find.byType(BoardView));

    game.tap(const Square(5, 0));
    await tester.pump();
    game.tap(const Square(3, 2));
    await tester.pump();

    expect(game.canFinishCapture, isTrue);
    expect(tester.getRect(find.byType(BoardView)), before);

    final finish = tester.getRect(
      find.byKey(const Key('finish-capture-button')),
    );
    final hint = tester.getRect(find.byKey(const Key('hint-button')));
    // A child must be able to hit them: never a squeezed row of three.
    expect(finish.height, greaterThanOrEqualTo(46));
    expect(hint.height, greaterThanOrEqualTo(46));
    expect(finish.width, greaterThanOrEqualTo(140));
    expect(hint.width, greaterThanOrEqualTo(140));
    // Undo is gone during the series: rewinding it would replay the opponent.
    expect(find.byKey(const Key('undo-button')), findsNothing);
  });

  testWidgets('кнопки диалога крупные и в столбик', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await pumpGame(tester, settings: settings, size: const Size(360, 640));

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in ['Продолжить', 'В меню']) {
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    final buttons = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(buttons, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      final rect = tester.getRect(buttons.at(index));
      expect(rect.height, greaterThanOrEqualTo(56), reason: 'кнопка $index');
      expect(rect.width, greaterThanOrEqualTo(200), reason: 'кнопка $index');
    }
  });
}
