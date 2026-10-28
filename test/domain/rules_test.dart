import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/domain/rules.dart';
import 'package:flutter_test/flutter_test.dart';

GameState position(GameVariant variant, Map<Square, Piece> pieces, {Side turn = Side.white}) =>
    GameState(variant: variant, board: Board(variant.boardSize, pieces), turn: turn);

void main() {
  const white = Piece(Side.white);
  const black = Piece(Side.black);

  test('начальная позиция и первый ход зависят от варианта', () {
    for (final variant in GameVariant.values) {
      final state = GameState.initial(variant);
      expect(state.board.count(Side.white), variant == GameVariant.international ? 20 : 12);
      expect(state.board.count(Side.black), variant == GameVariant.international ? 20 : 12);
      expect(state.turn, variant == GameVariant.american ? Side.black : Side.white);
      expect(GameRules.forVariant(variant).legalMoves(state), isNotEmpty);
    }
  });

  test('бой обязателен и цепочка является одним ходом', () {
    final state = position(GameVariant.russian, {
      const Square(5, 0): white, const Square(4, 1): black,
      const Square(2, 3): black, const Square(5, 6): white,
    });
    const rules = RussianRules();
    final moves = rules.legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.landings, [const Square(3, 2), const Square(1, 4)]);
    expect(moves.single.captures, [const Square(4, 1), const Square(2, 3)]);
    final next = rules.apply(state, moves.single);
    expect(next.board.count(Side.black), 0);
    expect(next.turn, Side.black);
    expect(rules.winner(next), Side.white);
    expect(() => rules.apply(state, Move(from: const Square(5, 6), landings: [const Square(4, 7)])), throwsStateError);
  });

  test('русская простая бьёт назад, американская — нет', () {
    final pieces = {const Square(3, 2): white, const Square(4, 3): black};
    final russian = RussianRules().legalMoves(position(GameVariant.russian, pieces));
    final american = AmericanRules().legalMoves(position(GameVariant.american, pieces));
    expect(russian.any((m) => m.to == const Square(5, 4) && m.isCapture), isTrue);
    expect(american.every((m) => !m.isCapture && m.to.row == 2), isTrue);
  });

  test('летающая дамка ходит и бьёт на расстояние; классическая — нет', () {
    const king = Piece(Side.white, king: true);
    final free = {const Square(5, 2): king};
    expect(RussianRules().legalMoves(position(GameVariant.russian, free))
        .any((m) => m.to == const Square(1, 6)), isTrue);
    expect(AmericanRules().legalMoves(position(GameVariant.american, free))
        .every((m) => (m.to.row - 5).abs() == 1), isTrue);
    final withOpponent = {const Square(5, 2): king, const Square(3, 4): black};
    final captures = RussianRules().legalMoves(position(GameVariant.russian, withOpponent));
    expect(captures.map((m) => m.to), containsAll([const Square(2, 5), const Square(1, 6), const Square(0, 7)]));
    expect(captures.every((m) => m.isCapture), isTrue);
  });

  test('сбитые шашки остаются преградой до окончания серии', () {
    final state = position(GameVariant.russian, {
      const Square(5, 2): const Piece(Side.white, king: true),
      const Square(4, 3): black, const Square(6, 1): black,
    });
    final moves = RussianRules().legalMoves(state);
    expect(moves, isNotEmpty);
    expect(moves.every((m) => m.captures.length == 1), isTrue);
  });

  test('в русских шашках превращение происходит во время боя', () {
    final state = position(GameVariant.russian, {
      const Square(2, 1): white, const Square(1, 2): black, const Square(1, 4): black,
    });
    final moves = RussianRules().legalMoves(state);
    final move = moves.firstWhere((m) => m.to == const Square(4, 7));
    expect(move.landings, [const Square(0, 3), const Square(4, 7)]);
    expect(RussianRules().apply(state, move).board.at(const Square(4, 7))!.king, isTrue);
  });

  test('в американских шашках превращение завершает цепочку', () {
    final state = position(GameVariant.american, {
      const Square(2, 1): white, const Square(1, 2): black, const Square(1, 4): black,
    });
    final move = AmericanRules().legalMoves(state).single;
    expect(move.landings, [const Square(0, 3)]);
    final next = AmericanRules().apply(state, move);
    expect(next.board.at(const Square(0, 3))!.king, isTrue);
    expect(next.board.count(Side.black), 1);
  });

  test('международные шашки требуют максимальное взятие', () {
    final state = position(GameVariant.international, {
      const Square(7, 2): white, const Square(6, 3): black, const Square(4, 5): black,
      const Square(7, 6): white, const Square(6, 7): black,
    });
    final moves = InternationalRules().legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.captures, [const Square(6, 3), const Square(4, 5)]);
    expect(moves.single.to, const Square(3, 6));
  });

  test('в международных шашках проход через последнюю линию не даёт дамку', () {
    final state = position(GameVariant.international, {
      const Square(2, 1): white, const Square(1, 2): black, const Square(1, 4): black,
    });
    final move = InternationalRules().legalMoves(state).single;
    expect(move.landings, [const Square(0, 3), const Square(2, 5)]);
    expect(InternationalRules().apply(state, move).board.at(const Square(2, 5))!.king, isFalse);
  });

  test('в поддавках игрок без хода или шашек выигрывает', () {
    final withoutPieces = position(GameVariant.giveaway, {const Square(1, 0): black});
    expect(GiveawayRules().winner(withoutPieces), Side.white);
    final blocked = position(GameVariant.giveaway, {const Square(0, 1): white, const Square(7, 0): black});
    expect(GiveawayRules().winner(blocked), Side.white);
    expect(RussianRules().winner(position(GameVariant.russian, blocked.board.pieces)), Side.black);
  });

  test('ход проходит JSON round-trip и защищён от некорректных данных', () {
    final move = Move(from: const Square(5, 0), landings: [const Square(3, 2), const Square(1, 4)],
        captures: [const Square(4, 1), const Square(2, 3)]);
    expect(Move.fromJson(move.toJson()), move);
    expect(() => Move.fromJson({'from': [0, 1], 'path': [], 'captures': []}), throwsFormatException);
    expect(() => Square.fromJson([100, 1]), throwsFormatException);
  });
}
