import 'dart:math';

import 'models.dart';
import 'rules.dart';

enum Difficulty { easy, medium, hard }

extension DifficultyDetails on Difficulty {
  String get label => switch (this) {
    Difficulty.easy => 'Лёгкий',
    Difficulty.medium => 'Средний',
    Difficulty.hard => 'Сложный',
  };
  /// Search depth in plies. The easy level looks only at its own move with a
  /// material-only score, so it blunders like a beginner and stays beatable.
  int get depth => switch (this) {
    Difficulty.easy => 1,
    Difficulty.medium => 3,
    Difficulty.hard => 5,
  };

  /// Minimal heuristics: material alone, no positional terms.
  bool get materialOnly => this == Difficulty.easy;
}

/// Thrown internally when the time budget of a search runs out.
class _SearchAborted implements Exception {
  const _SearchAborted();
}

/// Minimax over complete turns, with alpha-beta pruning and a bounded search.
/// The budget keeps difficult 10×10 positions responsive on mobile devices.
class CheckersAI {
  CheckersAI({Random? random, this.nodeBudget = 50000})
    : _random = random ?? Random();
  final Random _random;
  final int nodeBudget;
  int _nodes = 0;
  DateTime? _deadline;

  /// Depth of the last fully completed search. With a time budget the search
  /// deepens until the budget is spent, and this reports how far it got.
  int lastDepth = 0;

  Move? findBestMove(
    GameState state,
    int depth, {
    bool easyNoise = false,
    bool materialOnly = false,
    Duration? budget,
  }) {
    if (depth < 1) throw ArgumentError.value(depth, 'depth');
    if (budget == null) {
      final move = _searchRoot(state, depth, easyNoise, materialOnly);
      lastDepth = move == null ? 0 : depth;
      return move;
    }
    // Iterative deepening: every completed pass replaces the answer, and a pass
    // cut by the budget is discarded, so the result is the deepest finished one.
    _deadline = DateTime.now().add(budget);
    lastDepth = 0;
    Move? best;
    try {
      for (var pass = depth < 2 ? 1 : 2; pass <= depth; pass++) {
        final move = _searchRoot(state, pass, easyNoise, materialOnly);
        if (move != null) {
          best = move;
          lastDepth = pass;
        }
      }
    } on _SearchAborted {
      // A pass that ran out of time is dropped, so the answer of the last
      // finished pass stays.
    } finally {
      _deadline = null;
    }
    return best;
  }

  Move? _searchRoot(
    GameState state,
    int depth,
    bool easyNoise,
    bool materialOnly,
  ) {
    _nodes = 0;
    final rules = GameRules.forVariant(state.variant) as StandardRules;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty) return null;
    final root = state.turn;
    var bestScore = double.negativeInfinity;
    var best = legal.first;
    var alpha = double.negativeInfinity;
    for (final move in _ordered(legal)) {
      final next = rules.applyKnownLegal(state, move);
      var score = _search(
        next,
        rules,
        depth - 1,
        alpha,
        double.infinity,
        root,
        materialOnly,
      );
      // A little variety only affects the easy opponent, never a request for
      // a hint.
      if (easyNoise && score.abs() < 100000) {
        score += (_random.nextDouble() - 0.5) * 0.5;
      }
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
      if (score > alpha) alpha = score;
    }
    return best;
  }

  double _search(
    GameState state,
    StandardRules rules,
    int depth,
    double alpha,
    double beta,
    Side root,
    bool materialOnly,
  ) {
    _nodes++;
    if (_deadline != null && (_nodes & 0x3F) == 0) {
      if (DateTime.now().isAfter(_deadline!)) throw const _SearchAborted();
    }
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      final winner = state.variant.reverseGoal
          ? state.turn
          : state.turn.opponent;
      return winner == root ? 1000000.0 + depth : -1000000.0 - depth;
    }
    if (depth == 0 || _nodes >= nodeBudget) {
      return _evaluate(state, root, materialOnly);
    }
    final maximizing = state.turn == root;
    var best = maximizing ? double.negativeInfinity : double.infinity;
    for (final move in _ordered(legal)) {
      final value = _search(
        rules.applyKnownLegal(state, move),
        rules,
        depth - 1,
        alpha,
        beta,
        root,
        materialOnly,
      );
      if (maximizing) {
        best = max(best, value);
        alpha = max(alpha, best);
      } else {
        best = min(best, value);
        beta = min(beta, best);
      }
      if (beta <= alpha) break;
    }
    return best;
  }

  List<Move> _ordered(List<Move> moves) =>
      [...moves]
        ..sort((a, b) => b.captures.length.compareTo(a.captures.length));

  double _evaluate(GameState state, Side root, bool materialOnly) {
    var value = 0.0;
    final size = state.board.size;
    for (final entry in state.board.pieces.entries) {
      final piece = entry.value;
      final square = entry.key;
      final progress = piece.side == Side.white
          ? size - 1 - square.row
          : square.row;
      final double weight;
      if (materialOnly) {
        // Material plus a nudge towards promotion, so the easy opponent still
        // moves forward instead of shuffling.
        weight = (piece.king ? 3 : 1) + (piece.king ? 0 : progress * 0.05);
      } else {
        final center = 1 - ((square.col - (size - 1) / 2).abs() / (size / 2));
        final edgeSafety = (square.col == 0 || square.col == size - 1)
            ? 0.12
            : 0.0;
        weight =
            (piece.king ? 3.1 : 1.0 + progress * 0.07) +
            center * 0.15 +
            edgeSafety;
      }
      value += piece.side == root ? weight : -weight;
    }
    return state.variant.reverseGoal ? -value : value;
  }
}
