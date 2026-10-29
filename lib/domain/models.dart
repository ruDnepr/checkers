import 'dart:collection';

enum GameVariant { russian, american, international, giveaway }

enum Side { white, black }

extension SideDetails on Side {
  Side get opponent => this == Side.white ? Side.black : Side.white;
  int get forward => this == Side.white ? -1 : 1;
  String get label => this == Side.white ? 'Белые' : 'Чёрные';
}

extension VariantDetails on GameVariant {
  String get label => switch (this) {
    GameVariant.russian => 'Русские шашки',
    GameVariant.american => 'Классические шашки',
    GameVariant.international => 'Международные шашки',
    GameVariant.giveaway => 'Поддавки',
  };

  int get boardSize => this == GameVariant.international ? 10 : 8;
  int get initialRows => this == GameVariant.international ? 4 : 3;
  bool get flyingKings => this != GameVariant.american;
  bool get backwardsCapture => this != GameVariant.american;
  bool get maximumCapture => this == GameVariant.international;
  bool get reverseGoal => this == GameVariant.giveaway;
  Side get firstSide => this == GameVariant.american ? Side.black : Side.white;
}

class Square {
  const Square(this.row, this.col);

  final int row;
  final int col;

  bool inside(int size) => row >= 0 && col >= 0 && row < size && col < size;
  List<int> toJson() => [row, col];

  factory Square.fromJson(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! int ||
        value[1] is! int) {
      throw const FormatException('Некорректная клетка');
    }
    final square = Square(value[0] as int, value[1] as int);
    if (!square.inside(10)) throw const FormatException('Клетка вне доски');
    return square;
  }

  @override
  bool operator ==(Object other) =>
      other is Square && row == other.row && col == other.col;
  @override
  int get hashCode => Object.hash(row, col);
  @override
  String toString() => '${String.fromCharCode(97 + col)}${row + 1}';
}

class Piece {
  const Piece(this.side, {this.king = false});

  final Side side;
  final bool king;
  Piece crown() => king ? this : Piece(side, king: true);

  @override
  bool operator ==(Object other) =>
      other is Piece && side == other.side && king == other.king;
  @override
  int get hashCode => Object.hash(side, king);
}

/// One *complete* turn. Each landing corresponds to a captured piece in a jump.
class Move {
  Move({
    required this.from,
    required List<Square> landings,
    List<Square> captures = const [],
  }) : landings = List.unmodifiable(landings),
       captures = List.unmodifiable(captures) {
    if (landings.isEmpty ||
        landings.length > 20 ||
        (captures.isNotEmpty && captures.length != landings.length)) {
      throw ArgumentError('Некорректная последовательность хода');
    }
  }

  final Square from;
  final List<Square> landings;
  final List<Square> captures;
  Square get to => landings.last;
  bool get isCapture => captures.isNotEmpty;

  Map<String, Object> toJson() => {
    'from': from.toJson(),
    'path': landings.map((p) => p.toJson()).toList(),
    'captures': captures.map((p) => p.toJson()).toList(),
  };

  factory Move.fromJson(Object? value) {
    if (value is! Map || value['path'] is! List || value['captures'] is! List) {
      throw const FormatException('Некорректный ход');
    }
    final path = (value['path'] as List).map(Square.fromJson).toList();
    final captures = (value['captures'] as List).map(Square.fromJson).toList();
    if (path.isEmpty ||
        path.length > 20 ||
        (captures.isNotEmpty && captures.length != path.length)) {
      throw const FormatException('Некорректная последовательность хода');
    }
    return Move(
      from: Square.fromJson(value['from']),
      landings: path,
      captures: captures,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Move &&
      from == other.from &&
      _sameList(landings, other.landings) &&
      _sameList(captures, other.captures);
  @override
  int get hashCode =>
      Object.hash(from, Object.hashAll(landings), Object.hashAll(captures));
  @override
  String toString() =>
      '$from${isCapture ? ' × ' : ' – '}${landings.join(' – ')}';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class Board {
  Board(this.size, Map<Square, Piece> pieces)
    : pieces = UnmodifiableMapView(Map.of(pieces)) {
    if (size != 8 && size != 10) throw ArgumentError.value(size, 'size');
    if (pieces.keys.any((p) => !p.inside(size) || (p.row + p.col).isEven)) {
      throw ArgumentError('Шашки должны стоять на тёмных клетках доски');
    }
  }

  factory Board.initial(GameVariant variant) {
    final size = variant.boardSize;
    final result = <Square, Piece>{};
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if ((row + col).isEven) continue;
        if (row < variant.initialRows) {
          result[Square(row, col)] = const Piece(Side.black);
        }
        if (row >= size - variant.initialRows) {
          result[Square(row, col)] = const Piece(Side.white);
        }
      }
    }
    return Board(size, result);
  }

  final int size;
  final Map<Square, Piece> pieces;
  Piece? at(Square square) => pieces[square];
  int count(Side side) =>
      pieces.values.where((piece) => piece.side == side).length;
}

class GameState {
  const GameState({
    required this.variant,
    required this.board,
    required this.turn,
    this.ply = 0,
  });

  factory GameState.initial(GameVariant variant) => GameState(
    variant: variant,
    board: Board.initial(variant),
    turn: variant.firstSide,
  );

  final GameVariant variant;
  final Board board;
  final Side turn;
  final int ply;

  /// A stable protocol fingerprint, independent of map iteration order.
  String get fingerprint {
    var hash = 0x811c9dc5;
    void mix(int n) {
      hash = ((hash ^ n) * 0x01000193) & 0xffffffff;
    }

    mix(variant.index);
    mix(turn.index);
    mix(ply);
    for (var row = 0; row < board.size; row++) {
      for (var col = 0; col < board.size; col++) {
        final piece = board.at(Square(row, col));
        mix(
          piece == null ? 0 : 1 + piece.side.index * 2 + (piece.king ? 1 : 0),
        );
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
