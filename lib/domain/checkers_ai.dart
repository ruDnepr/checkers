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

/// Thrown when a search pass runs out of its node budget.
///
/// The pass is thrown away and the answer of the previous, cheaper pass is kept.
/// Without that a tree cut in the middle would be mistaken for a finished
/// search: the leaves would be evaluated right after our own move, the reply of
/// the opponent would be ignored and the engine would calmly give a piece away.
class _SearchAborted implements Exception {
  const _SearchAborted();
}

/// Minimax over complete turns with alpha-beta pruning.
///
/// The search deepens one ply at a time and keeps the result of the last
/// **finished** pass. A pass that hits [nodeBudget] is discarded, so the answer
/// is always the deepest honest one. Leaves are extended by capture moves
/// ([quiescencePlies]), therefore the evaluation never stops in the middle of an
/// exchange where a piece is already under attack.
class CheckersAI {
  CheckersAI({
    Random? random,
    this.nodeBudget = 50000,
    this.quiescencePlies = 3,
  }) : _random = random ?? Random();
  final Random _random;
  final int nodeBudget;

  /// Extra capture-only plies played out at a leaf.
  final int quiescencePlies;
  int _nodes = 0;

  /// Depth of the last fully finished pass. A pass cut by [nodeBudget] never
  /// counts, so the value also documents how deep the answer really looked.
  int lastDepth = 0;

  Move? findBestMove(
    GameState state,
    int depth, {
    bool easyNoise = false,
    bool materialOnly = false,
  }) {
    if (depth < 1) throw ArgumentError.value(depth, 'depth');
    lastDepth = 0;
    Move? best;
    for (var pass = 1; pass <= depth; pass++) {
      try {
        final move = _searchRoot(state, pass, easyNoise, materialOnly);
        if (move == null) return null;
        best = move;
        lastDepth = pass;
      } on _SearchAborted {
        // Keep the answer of the last finished pass and stop deepening: the
        // next pass is only bigger and would be cut as well.
        break;
      }
    }
    // Even the first pass did not fit into the budget (a huge board, or a tiny
    // budget in a test). A last resort is still safe: it looks at every legal
    // move and at every answer of the opponent, so it can never recommend a move
    // that simply gives a piece away.
    return best ?? _safeMove(state, materialOnly);
  }

  /// Two half-moves without any budget: the worst answer of the opponent for
  /// each own move. Cheap, bounded and never blind to an immediate capture.
  Move? _safeMove(GameState state, bool materialOnly) {
    final rules = GameRules.forVariant(state.variant) as StandardRules;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty) return null;
    final root = state.turn;
    var best = legal.first;
    var bestScore = double.negativeInfinity;
    for (final move in _ordered(legal)) {
      final after = rules.applyKnownLegal(state, move);
      final replies = rules.legalMoves(after);
      if (replies.isEmpty || after.board.count(after.turn) == 0) {
        final score = _endScore(after, root, 0);
        if (score > bestScore) {
          bestScore = score;
          best = move;
        }
        continue;
      }
      var score = double.infinity;
      for (final reply in replies) {
        score = min(
          score,
          _evaluate(rules.applyKnownLegal(after, reply), root, materialOnly),
        );
      }
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
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
    _visit();
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      return _endScore(state, root, depth);
    }
    if (depth == 0) {
      return _quiesce(
        state,
        rules,
        alpha,
        beta,
        root,
        materialOnly,
        quiescencePlies,
      );
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

  /// Plays out the captures that are still available at a leaf. A capture is
  /// obligatory in every variant, so a quiet evaluation of such a position would
  /// simply be wrong: the piece is already as good as taken.
  double _quiesce(
    GameState state,
    StandardRules rules,
    double alpha,
    double beta,
    Side root,
    bool materialOnly,
    int plies,
  ) {
    _visit();
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      return _endScore(state, root, 0);
    }
    final captures = [
      for (final move in legal)
        if (move.isCapture) move,
    ];
    if (plies <= 0 || captures.isEmpty) {
      return _evaluate(state, root, materialOnly);
    }
    final maximizing = state.turn == root;
    var best = maximizing ? double.negativeInfinity : double.infinity;
    for (final move in captures) {
      final value = _quiesce(
        rules.applyKnownLegal(state, move),
        rules,
        alpha,
        beta,
        root,
        materialOnly,
        plies - 1,
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

  void _visit() {
    _nodes++;
    if (_nodes >= nodeBudget) throw const _SearchAborted();
  }

  double _endScore(GameState state, Side root, int depth) {
    final winner = state.variant.reverseGoal ? state.turn : state.turn.opponent;
    return winner == root ? 1000000.0 + depth : -1000000.0 - depth;
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
