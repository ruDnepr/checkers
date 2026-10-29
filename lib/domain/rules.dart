import 'dart:math' as math;

import 'models.dart';

/// Pure move generation. Captured pieces remain blockers until the whole jump
/// ends; a man in Russian/giveaway crowns immediately, in international only
/// at the end, and in American crowning ends the turn.
///
/// Capture series differ per variant:
/// * Russian/giveaway — a man may stop after any completed series, a king must
///   finish the series it starts (turning inside a series is allowed);
/// * classic/American — every series is played to the end for all pieces;
/// * international — only series with the maximal number of captured pieces.
/// Maximum capture is *not* universal: it applies to international only.
abstract interface class GameRules {
  GameVariant get variant;
  List<Move> legalMoves(GameState state);
  GameState apply(GameState state, Move move);
  Side? winner(GameState state);

  static GameRules forVariant(GameVariant variant) => switch (variant) {
    GameVariant.russian => const RussianRules(),
    GameVariant.american => const AmericanRules(),
    GameVariant.international => const InternationalRules(),
    GameVariant.giveaway => const GiveawayRules(),
  };
}

class StandardRules implements GameRules {
  const StandardRules(this.variant);
  @override
  final GameVariant variant;
  static const _directions = <(int, int)>[(-1, -1), (-1, 1), (1, -1), (1, 1)];

  @override
  List<Move> legalMoves(GameState state) {
    if (state.variant != variant || state.board.size != variant.boardSize) {
      throw ArgumentError('Правила не соответствуют позиции');
    }
    final captures = <Move>[];
    for (final entry in state.board.pieces.entries) {
      if (entry.value.side != state.turn) continue;
      _findCaptures(
        Map.of(state.board.pieces),
        state.board.size,
        entry.key,
        entry.key,
        entry.value,
        <Square>[],
        <Square>[],
        captures,
      );
    }
    if (captures.isNotEmpty) {
      // A man in Russian/giveaway may stop the series early, so the same move
      // can be produced twice; keep the first occurrence of every move.
      final unique = captures.toSet().toList();
      if (!variant.maximumCapture) return unique;
      final maximum = unique.map((m) => m.captures.length).reduce(math.max);
      return unique.where((move) => move.captures.length == maximum).toList();
    }

    final moves = <Move>[];
    for (final entry in state.board.pieces.entries) {
      final piece = entry.value;
      if (piece.side != state.turn) continue;
      for (final (dr, dc) in _directions) {
        if (!piece.king && dr != piece.side.forward) continue;
        var row = entry.key.row + dr;
        var col = entry.key.col + dc;
        while (Square(row, col).inside(state.board.size) &&
            state.board.at(Square(row, col)) == null) {
          moves.add(Move(from: entry.key, landings: [Square(row, col)]));
          if (!piece.king || !variant.flyingKings) break;
          row += dr;
          col += dc;
        }
      }
    }
    return moves;
  }

  void _findCaptures(
    Map<Square, Piece> board,
    int size,
    Square origin,
    Square current,
    Piece piece,
    List<Square> path,
    List<Square> taken,
    List<Move> result,
  ) {
    var found = false;
    for (final (dr, dc) in _directions) {
      if (!piece.king &&
          !variant.backwardsCapture &&
          dr != piece.side.forward) {
        continue;
      }
      var row = current.row + dr;
      var col = current.col + dc;
      if (piece.king && variant.flyingKings) {
        while (Square(row, col).inside(size) &&
            board[Square(row, col)] == null) {
          row += dr;
          col += dc;
        }
      }
      final victim = Square(row, col);
      final target = board[victim];
      if (!victim.inside(size) ||
          target == null ||
          target.side == piece.side ||
          taken.contains(victim)) {
        continue;
      }
      row += dr;
      col += dc;
      while (Square(row, col).inside(size) && board[Square(row, col)] == null) {
        found = true;
        final landing = Square(row, col);
        final promotes = !piece.king && _isCrownRow(landing, piece.side, size);
        final nextPiece =
            promotes &&
                (variant == GameVariant.russian ||
                    variant == GameVariant.giveaway)
            ? piece.crown()
            : piece;
        final nextBoard = Map<Square, Piece>.of(board)
          ..remove(current)
          ..[landing] = nextPiece;
        final nextPath = [...path, landing];
        final nextTaken = [...taken, victim];
        if (promotes && variant == GameVariant.american) {
          result.add(
            Move(from: origin, landings: nextPath, captures: nextTaken),
          );
        } else {
          _findCaptures(
            nextBoard,
            size,
            origin,
            landing,
            nextPiece,
            nextPath,
            nextTaken,
            result,
          );
          // Russian/giveaway: a man may choose any series and stop after it,
          // even when a longer series exists. A piece that was crowned on this
          // landing is a king already, so it must continue and is not added.
          if (_manMayStopMidSeries(nextPiece)) {
            result.add(
              Move(from: origin, landings: nextPath, captures: nextTaken),
            );
          }
        }
        if (!piece.king || !variant.flyingKings) break;
        row += dr;
        col += dc;
      }
    }
    if (!found && taken.isNotEmpty) {
      result.add(Move(from: origin, landings: path, captures: taken));
    }
  }

  /// Whether the pieces may end a capture series in the middle.
  ///
  /// Russian draughts and giveaway: a man chooses any series and may stop after
  /// it, while a king must finish every series it starts. Classic/American and
  /// international: every started series is played to the end, so stopping is
  /// never allowed. International additionally keeps only maximal series.
  bool _manMayStopMidSeries(Piece piece) =>
      (variant == GameVariant.russian || variant == GameVariant.giveaway) &&
      !piece.king;

  bool _isCrownRow(Square square, Side side, int size) =>
      square.row == (side == Side.white ? 0 : size - 1);

  @override
  GameState apply(GameState state, Move move) {
    if (!legalMoves(state).contains(move)) throw StateError('Недопустимый ход');
    return applyKnownLegal(state, move);
  }

  /// For search after obtaining the move from [legalMoves].
  GameState applyKnownLegal(GameState state, Move move) {
    final pieces = Map<Square, Piece>.of(state.board.pieces);
    var piece = pieces.remove(move.from)!;
    for (final captured in move.captures) {
      pieces.remove(captured);
    }
    final wasRussianPromotion =
        variant == GameVariant.russian || variant == GameVariant.giveaway;
    if (_isCrownRow(move.to, piece.side, state.board.size) ||
        (wasRussianPromotion &&
            move.landings.any(
              (p) => _isCrownRow(p, piece.side, state.board.size),
            ))) {
      piece = piece.crown();
    }
    pieces[move.to] = piece;
    return GameState(
      variant: variant,
      board: Board(state.board.size, pieces),
      turn: state.turn.opponent,
      ply: state.ply + 1,
    );
  }

  @override
  Side? winner(GameState state) {
    if (state.board.count(state.turn) == 0 || legalMoves(state).isEmpty) {
      return variant.reverseGoal ? state.turn : state.turn.opponent;
    }
    return null;
  }
}

class RussianRules extends StandardRules {
  const RussianRules() : super(GameVariant.russian);
}

class AmericanRules extends StandardRules {
  const AmericanRules() : super(GameVariant.american);
}

class InternationalRules extends StandardRules {
  const InternationalRules() : super(GameVariant.international);
}

class GiveawayRules extends StandardRules {
  const GiveawayRules() : super(GameVariant.giveaway);
}
