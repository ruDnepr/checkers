import 'dart:math';

import 'package:checkers_for_diana/domain/checkers_ai.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/domain/rules.dart';
import 'package:flutter_test/flutter_test.dart';

GameState position(GameVariant variant, Map<Square, Piece> pieces) => GameState(
  variant: variant,
  board: Board(variant.boardSize, pieces),
  turn: Side.white,
);

/// A white man may step to (4, 1) and be taken by the black man at (3, 0), or
/// to (4, 3) and stay safe. Any sensible search has to choose (4, 3).
GameState hangingMan() => position(GameVariant.russian, {
  const Square(5, 2): const Piece(Side.white),
  const Square(3, 0): const Piece(Side.black),
});

/// True when the side that is to move in [state] can capture something.
bool hasCapture(GameState state) =>
    (GameRules.forVariant(state.variant) as StandardRules).legalMoves(
      state,
    ).any((move) => move.isCapture);

void main() {
  test('находит победу за один полный ход', () {
    final state = position(GameVariant.russian, {
      const Square(2, 1): const Piece(Side.white),
      const Square(1, 2): const Piece(Side.black),
    });
    expect(
      CheckersAI(random: Random(1)).findBestMove(state, 2)!.to,
      const Square(0, 3),
    );
  });

  test('в обычной игре избегает подставы в два полухода', () {
    expect(
      CheckersAI(random: Random(1)).findBestMove(hangingMan(), 2)!.to,
      const Square(4, 3),
    );
  });

  test('ответное взятие видно даже на глубине в один полуход', () {
    // The quiescence extension plays out the captures at a leaf, so the shallow
    // search does not walk into a piece being taken.
    expect(
      CheckersAI(random: Random(1)).findBestMove(
        hangingMan(),
        1,
        materialOnly: true,
      )!.to,
      const Square(4, 3),
    );
  });

  test('подсказка глубины 3 не ставит шашки под бой в начале партии', () {
    // The situation reported from the phone: right after the first moves the
    // hint suggested pieces that were captured at once. With a finished
    // three-ply search the answer of the opponent is always evaluated. In the
    // quiet opening no pieces touch each other, so any capture available to the
    // opponent right after the suggested move is a piece given away for free.
    for (final variant in [GameVariant.russian, GameVariant.american]) {
      var state = GameState.initial(variant);
      final rules = GameRules.forVariant(variant) as StandardRules;
      for (var ply = 0; ply < 4; ply++) {
        final move = CheckersAI().findBestMove(state, 3);
        expect(move, isNotNull, reason: '${variant.name}/$ply');
        state = rules.applyKnownLegal(state, move!);
        expect(
          hasCapture(state),
          isFalse,
          reason: '${variant.name}: ход $move на полуходе $ply отдаёт шашку',
        );
      }
    }
  });

  test('в поддавках стремится отдать последнюю шашку', () {
    final state = position(GameVariant.giveaway, {
      const Square(5, 2): const Piece(Side.white),
      const Square(3, 0): const Piece(Side.black),
    });
    expect(
      CheckersAI(random: Random(1)).findBestMove(state, 2)!.to,
      const Square(4, 1),
    );
  });

  test('уровни различаются глубиной и эвристикой', () {
    expect(Difficulty.values.map((d) => d.depth).toList(), [1, 3, 5]);
    expect(Difficulty.easy.materialOnly, isTrue);
    expect(Difficulty.medium.materialOnly, isFalse);
    expect(Difficulty.hard.materialOnly, isFalse);
  });

  test('обычный бюджет позволяет доиграть заявленную глубину', () {
    final ai = CheckersAI(random: Random(1));
    expect(ai.findBestMove(GameState.initial(GameVariant.russian), 3), isNotNull);
    expect(ai.lastDepth, 3);
  });

  test('обрезанный проход не считается ответом поиска', () {
    // A budget this small cannot even finish one pass, so nothing may be
    // reported as searched and the safe fallback answers instead.
    final ai = CheckersAI(nodeBudget: 2);
    final move = ai.findBestMove(hangingMan(), 5);
    expect(move, isNotNull);
    expect(ai.lastDepth, 0);
    expect(move!.to, const Square(4, 3));
  });

  test(
    'каждый уровень возвращает допустимый ход во всех вариантах',
    () {
      for (final variant in GameVariant.values) {
        final state = GameState.initial(variant);
        final legal = GameRules.forVariant(variant).legalMoves(state);
        for (final difficulty in Difficulty.values) {
          final move = CheckersAI(random: Random(5)).findBestMove(
            state,
            difficulty.depth,
            easyNoise: difficulty == Difficulty.easy,
            materialOnly: difficulty.materialOnly,
          );
          expect(move, isNotNull, reason: '${variant.name}/${difficulty.name}');
          expect(
            legal,
            contains(move),
            reason: '${variant.name}/${difficulty.name}',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
