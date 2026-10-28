import 'dart:math';

import 'package:checkers_for_diana/domain/checkers_ai.dart';
import 'package:checkers_for_diana/domain/models.dart';
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
}
