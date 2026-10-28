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
  int get depth => switch (this) {
    Difficulty.easy => 2,
    Difficulty.medium => 3,
    Difficulty.hard => 5,
  };
}

/// Minimax over complete turns, with alpha-beta pruning and a bounded search.
/// The budget keeps difficult 10×10 positions responsive on mobile devices.
class CheckersAI {
  CheckersAI({Random? random, this.nodeBudget = 50000})
    : _random = random ?? Random();
  final Random _random;
  final int nodeBudget;
  int _nodes = 0;

  Move? findBestMove(GameState state, int depth, {bool easyNoise = false}) {
    if (depth < 1) throw ArgumentError.value(depth, 'depth');
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
      var score = _search(next, rules, depth - 1, alpha, double.infinity, root);
      // A little variety only affects the easy opponent, never a requested hint.
      if (easyNoise && score.abs() < 100000)
        score += (_random.nextDouble() - 0.5) * 0.5;
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
  ) {
    _nodes++;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      final winner = state.variant.reverseGoal
          ? state.turn
          : state.turn.opponent;
      return winner == root ? 1000000.0 + depth : -1000000.0 - depth;
    }
    if (depth == 0 || _nodes >= nodeBudget) return _evaluate(state, root);
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

  double _evaluate(GameState state, Side root) {
    var value = 0.0;
    final size = state.board.size;
    for (final entry in state.board.pieces.entries) {
      final piece = entry.value;
      final square = entry.key;
      final progress = piece.side == Side.white
          ? size - 1 - square.row
          : square.row;
      final center = 1 - ((square.col - (size - 1) / 2).abs() / (size / 2));
      final edgeSafety = (square.col == 0 || square.col == size - 1)
          ? 0.12
          : 0.0;
      final weight =
          (piece.king ? 3.1 : 1.0 + progress * 0.07) +
          center * 0.15 +
          edgeSafety;
      value += piece.side == root ? weight : -weight;
    }
    return state.variant.reverseGoal ? -value : value;
  }
}
