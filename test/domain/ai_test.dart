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
    final state = position(GameVariant.russian, {
      const Square(5, 2): const Piece(Side.white),
      const Square(3, 0): const Piece(Side.black),
    });
    expect(
      CheckersAI(random: Random(1)).findBestMove(state, 2)!.to,
      const Square(4, 3),
    );
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
