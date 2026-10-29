import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/checkers_ai.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import '../network/network_game_service.dart';
import '../network/protocol.dart';
import 'settings.dart';
import 'sounds.dart';

enum GameMode { computer, local, network }

class GameSetup {
  const GameSetup({
    required this.variant,
    required this.mode,
    required this.playerSide,
    this.difficulty = Difficulty.easy,
    this.network,
  });
  final GameVariant variant;
  final GameMode mode;
  final Side playerSide;
  final Difficulty difficulty;
  final NetworkGameService? network;
}

class MoveRecord {
  const MoveRecord(this.side, this.move);
  final Side side;
  final Move move;
}

class MoveAnimation {
  const MoveAnimation(this.before, this.move, this.duration);
  final GameState before;
  final Move move;
  final Duration duration;
}

class _SearchRequest {
  const _SearchRequest(this.state, this.depth, this.noise, this.materialOnly);
  final GameState state;
  final int depth;
  final bool noise;
  final bool materialOnly;
}

Move? _searchMove(_SearchRequest request) => CheckersAI().findBestMove(
  request.state,
  request.depth,
  easyNoise: request.noise,
  materialOnly: request.materialOnly,
);

class GameController extends ChangeNotifier {
  GameController(
    this.setup,
    this.settings, {
    this.animationPerLanding = const Duration(milliseconds: 350),
    GameState? initialState,
  }) : state = initialState ?? GameState.initial(setup.variant),
       rules = GameRules.forVariant(setup.variant) as StandardRules,
       sounds = GameSounds(settings) {
    if (setup.mode == GameMode.network && setup.network == null) {
      throw ArgumentError('Для сетевой игры необходимо соединение');
    }
    _refresh();
    settings.addListener(_settingsChanged);
    _networkSubscription = setup.network?.events.listen(_onNetworkMessage);
  }

  final GameSetup setup;
  final SettingsController settings;
  final StandardRules rules;
  final GameSounds sounds;
  final Duration animationPerLanding;
  GameState state;
  late List<Move> legalMoves;
  final List<GameState> _history = [];
  final List<MoveRecord> _records = [];
  List<MoveRecord> get history => List.unmodifiable(_records);
  Square? selected;
  final List<Square> _prefix = [];
  List<Square> get selectedPath => List.unmodifiable(_prefix);
  Move? suggestedMove;

  /// Explanation of the highlighted hint. It is filled by [showHint] only, so
  /// nothing hints at the best move before the button is pressed.
  String? hintText;
  MoveAnimation? animation;
  bool computerThinking = false;
  bool hintThinking = false;
  bool waitingForUndo = false;
  int? incomingUndoPly;
  int? _deferredUndoPly;
  String? notice;
  String? fatalMessage;
  Side? _resignedWinner;
  StreamSubscription<NetworkMessage>? _networkSubscription;
  int _generation = 0;
  bool _disposed = false;
  bool _started = false;

  Side? get winner =>
      _resignedWinner ??
      (legalMoves.isEmpty || state.board.count(state.turn) == 0
          ? (state.variant.reverseGoal ? state.turn : state.turn.opponent)
          : null);
  bool get isAnimating => animation != null;
  bool get canInteract =>
      winner == null &&
      fatalMessage == null &&
      !isAnimating &&
      !computerThinking &&
      !waitingForUndo &&
      incomingUndoPly == null &&
      _deferredUndoPly == null &&
      (setup.mode == GameMode.local || state.turn == setup.playerSide);
  bool get hasCapture => legalMoves.isNotEmpty && legalMoves.first.isCapture;
  int get maximumCapture => hasCapture ? legalMoves.first.captures.length : 0;

  bool get canUndo {
    if (_history.isEmpty ||
        _resignedWinner != null ||
        isAnimating ||
        waitingForUndo ||
        incomingUndoPly != null ||
        _deferredUndoPly != null ||
        fatalMessage != null) {
      return false;
    }
    if (setup.mode == GameMode.network) {
      return setup.network?.status == NetworkStatus.connected &&
          _history.last.turn == setup.playerSide &&
          state.turn == setup.playerSide.opponent;
    }
    if (setup.mode == GameMode.computer &&
        _history.last.turn != setup.playerSide) {
      return _history.length >= 2 &&
          _history[_history.length - 2].turn == setup.playerSide;
    }
    return true;
  }

  List<Move> get selectedCandidates {
    if (selected == null) return [];
    return legalMoves.where((move) {
      if (move.from != selected || move.landings.length < _prefix.length) {
        return false;
      }
      for (var i = 0; i < _prefix.length; i++) {
        if (move.landings[i] != _prefix[i]) return false;
      }
      return true;
    }).toList();
  }

  Set<Square> get suggestedDestinations => selectedCandidates
      .where((m) => m.landings.length > _prefix.length)
      .map((m) => m.landings[_prefix.length])
      .toSet();

  /// The series played so far can already be finished here, while a longer one
  /// is still available. Only Russian/giveaway allow this for a man.
  Move? get _stopHere => _prefix.isEmpty
      ? null
      : selectedCandidates
            .where((m) => m.landings.length == _prefix.length)
            .firstOrNull;
  bool get canFinishCapture =>
      _stopHere != null && suggestedDestinations.isNotEmpty;

  /// Ends the capture series at the landings already played.
  void finishCapture() {
    if (!canInteract) return;
    final move = _stopHere;
    if (move == null) return;
    _clearSelection();
    notice = null;
    unawaited(_apply(move, remote: false));
  }

  void start() {
    if (_started) return;
    _started = true;
    if (setup.mode == GameMode.computer && state.turn != setup.playerSide) {
      _startComputer();
    }
  }

  void _refresh() => legalMoves = rules.legalMoves(state);
  void _settingsChanged() {
    if (!settings.hints) {
      suggestedMove = null;
      hintText = null;
      // Instructions only make sense while the hints setting is on.
      if (notice != null && !waitingForUndo) notice = null;
    }
    _notify();
  }

  /// Called when «Подсказка» is pressed: highlights the best move and explains
  /// why it is good. Nothing about the best move is shown before this.
  String _describeHint(Move move) {
    final buffer = StringBuffer('Подсказка: подсвечен лучший ход');
    if (move.isCapture) {
      buffer.write(', он бьёт ${_captureCount(move.captures.length)}');
    }
    if (hasCapture) {
      buffer.write(
        setup.variant == GameVariant.international
            ? '. Бить нужно как можно больше шашек: $maximumCapture'
            : '. Сейчас бой обязателен',
      );
    }
    if (setup.variant == GameVariant.giveaway) {
      buffer.write('. В поддавках выгодно отдавать свои шашки');
    }
    return '${buffer.toString()}.';
  }

  /// Dismisses the hint bubble. The highlight disappears with it.
  void clearHint() {
    if (suggestedMove == null && hintText == null) return;
    suggestedMove = null;
    hintText = null;
    _notify();
  }

  /// Dismisses an explanation message shown after a tap.
  void clearNotice() {
    if (notice == null) return;
    notice = null;
    _notify();
  }

  static String _captureCount(int count) => switch (count) {
    1 => '1 шашку',
    2 => '2 шашки',
    3 => '3 шашки',
    4 => '4 шашки',
    _ => '$count шашек',
  };

  String _captureDutyText() => setup.variant == GameVariant.international
      ? 'Сейчас нужно бить как можно больше шашек: $maximumCapture.'
      : 'Сейчас бой обязателен: спокойно походить нельзя, нужно бить шашку.';

  /// Explains why a tap changed nothing, so a child is not left guessing.
  /// Detailed wording belongs to the hints setting; without hints the message
  /// only states that the move is not possible.
  String _explainTap(Square square, {required bool hadSelection}) {
    if (!settings.hints) return 'Так ходить нельзя.';
    final piece = state.board.at(square);
    if (piece == null) {
      if (hasCapture) return _captureDutyText();
      if (hadSelection) {
        return 'Так ходить нельзя: подсвечены только разрешённые клетки.';
      }
      return 'Сначала выбери свою шашку, потом подсвеченную клетку.';
    }
    if (piece.side != state.turn) {
      return 'Это шашка соперника: ходить можно только своей.';
    }
    if (hasCapture) {
      return setup.variant == GameVariant.international
          ? '${_captureDutyText()} Эта шашка не бьёт — выбери ту, которая бьёт.'
          : 'Сейчас бой обязателен: эта шашка не бьёт, выбери ту, которая бьёт.';
    }
    return 'Эта шашка сейчас не может ходить — выбери другую.';
  }

  void tap(Square square) {
    if (!canInteract) return;
    notice = null;
    suggestedMove = null;
    hintText = null;
    final candidates = selectedCandidates;
    final next = candidates
        .where(
          (m) =>
              m.landings.length > _prefix.length &&
              m.landings[_prefix.length] == square,
        )
        .toList();
    if (next.isNotEmpty) {
      _prefix.add(square);
      final completed = next
          .where((m) => m.landings.length == _prefix.length)
          .firstOrNull;
      // When the series could also be continued, the player decides: tapping
      // the next landing plays on, «Закончить бой» stops here.
      if (completed != null && !canFinishCapture) {
        _clearSelection();
        unawaited(_apply(completed, remote: false));
      } else {
        _notify();
      }
      return;
    }
    // A started series must be finished by the same piece; in Russian/giveaway
    // a man may also end it where it is with the «Закончить бой» button.
    if (_prefix.isNotEmpty) {
      notice = canFinishCapture
          ? 'Можно закончить бой здесь — нажми «Закончить бой», '
                'или продолжай бить этой шашкой.'
          : 'Серия взятий уже начата — закончи её этой же шашкой.';
      _notify();
      return;
    }
    if (legalMoves.any((m) => m.from == square)) {
      selected = square;
      _notify();
      return;
    }
    final hadSelection = selected != null;
    selected = null;
    notice = _explainTap(square, hadSelection: hadSelection);
    _notify();
  }

  Future<void> showHint() async {
    if (!settings.hints || !canInteract || hintThinking) return;
    final snapshot = state;
    final generation = _generation;
    hintThinking = true;
    notice = null;
    _notify();
    try {
      // The hint always searches two plies with the full heuristic, which is
      // stronger than the easy opponent and is what a child should copy.
      final move = await compute(
        _searchMove,
        _SearchRequest(snapshot, 2, false, false),
      );
      if (!_disposed &&
          move != null &&
          generation == _generation &&
          snapshot.fingerprint == state.fingerprint &&
          settings.hints) {
        _clearSelection();
        suggestedMove = move;
        hintText = _describeHint(move);
      }
    } finally {
      if (!_disposed) {
        hintThinking = false;
        _notify();
      }
    }
  }

  Future<void> _apply(Move move, {required bool remote}) async {
    if (_disposed || fatalMessage != null || !legalMoves.contains(move)) return;
    final before = state;
    _history.add(before);
    _records.add(MoveRecord(before.turn, move));
    state = rules.applyKnownLegal(before, move);
    _refresh();
    _clearSelection();
    suggestedMove = null;
    hintText = null;
    notice = null;
    computerThinking = false;
    final duration = animationPerLanding * move.landings.length;
    animation = MoveAnimation(before, move, duration);
    final generation = ++_generation;
    final becameKing =
        !(before.board.at(move.from)?.king ?? false) &&
        (state.board.at(move.to)?.king ?? false);
    sounds.play(becameKing ? 'crown' : (move.isCapture ? 'capture' : 'move'));
    _notify();
    if (duration > Duration.zero) await Future<void>.delayed(duration);
    if (_disposed || generation != _generation) return;
    animation = null;
    if (_deferredUndoPly != null) {
      incomingUndoPly = _deferredUndoPly;
      _deferredUndoPly = null;
    }
    if (!remote && setup.mode == GameMode.network) {
      try {
        setup.network!.send(
          NetworkMessage('move', {
            'ply': before.ply,
            'before': before.fingerprint,
            'move': move.toJson(),
          }),
        );
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
      }
    }
    _notify();
    if (winner != null || fatalMessage != null) return;
    if (setup.mode == GameMode.computer && state.turn != setup.playerSide) {
      _startComputer();
    }
  }

  void _startComputer() {
    if (_disposed ||
        computerThinking ||
        winner != null ||
        fatalMessage != null) {
      return;
    }
    computerThinking = true;
    final generation = _generation;
    final snapshot = state;
    _notify();
    Future<void>(() async {
      if (_disposed || generation != _generation) return;
      try {
        final move = await compute(
          _searchMove,
          _SearchRequest(
            snapshot,
            setup.difficulty.depth,
            setup.difficulty == Difficulty.easy,
            setup.difficulty.materialOnly,
          ),
        );
        if (_disposed ||
            generation != _generation ||
            snapshot.fingerprint != state.fingerprint) {
          return;
        }
        if (move != null) await _apply(move, remote: false);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          computerThinking = false;
          fatalMessage =
              'Не получилось сделать ход. Попробуй начать новую партию.';
          _notify();
        }
      }
    });
  }

  void undo() {
    if (!canUndo) return;
    if (setup.mode == GameMode.network) {
      waitingForUndo = true;
      try {
        setup.network!.send(
          NetworkMessage('undoRequest', {
            'ply': state.ply,
            'before': state.fingerprint,
          }),
        );
      } catch (_) {
        waitingForUndo = false;
        fatalMessage = 'Связь потеряна.';
      }
      _notify();
      return;
    }
    var count = 1;
    if (setup.mode == GameMode.computer &&
        _history.last.turn != setup.playerSide) {
      count = 2;
    }
    _restore(count);
  }

  void _restore(int count) {
    _generation++;
    computerThinking = false;
    hintThinking = false;
    animation = null;
    for (var i = 0; i < count; i++) {
      state = _history.removeLast();
      _records.removeLast();
    }
    _resignedWinner = null;
    waitingForUndo = false;
    incomingUndoPly = null;
    _deferredUndoPly = null;
    suggestedMove = null;
    hintText = null;
    _clearSelection();
    _refresh();
    _notify();
  }

  void respondToUndo(bool accepted) {
    final ply = incomingUndoPly;
    if (ply == null) return;
    try {
      setup.network!.send(
        NetworkMessage('undoResponse', {'ply': ply, 'accepted': accepted}),
      );
      incomingUndoPly = null;
      if (accepted && state.ply == ply && _history.isNotEmpty) {
        _restore(1);
      } else {
        _notify();
      }
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      _notify();
    }
  }

  void resign() {
    if (winner != null || fatalMessage != null) return;
    if (setup.mode == GameMode.network) {
      try {
        setup.network!.send(const NetworkMessage('resign'));
      } catch (_) {}
      _resignedWinner = setup.playerSide.opponent;
    } else {
      _resignedWinner = setup.mode == GameMode.local
          ? state.turn.opponent
          : setup.playerSide.opponent;
    }
    _generation++;
    computerThinking = false;
    animation = null;
    _notify();
  }

  void _onNetworkMessage(NetworkMessage message) {
    if (_disposed || fatalMessage != null) return;
    switch (message.type) {
      case 'move':
        try {
          if (message.data['ply'] != state.ply ||
              message.data['before'] != state.fingerprint ||
              state.turn != setup.playerSide.opponent ||
              isAnimating ||
              incomingUndoPly != null) {
            throw const FormatException('Разные позиции');
          }
          final move = Move.fromJson(message.data['move']);
          if (!legalMoves.contains(move)) {
            throw const FormatException('Недопустимый ход');
          }
          waitingForUndo =
              false; // A simultaneous answer takes precedence over an undo request.
          unawaited(_apply(move, remote: true));
        } catch (_) {
          _desync();
        }
      case 'undoRequest':
        final valid =
            message.data['ply'] == state.ply &&
            message.data['before'] == state.fingerprint &&
            _history.isNotEmpty &&
            _history.last.turn == setup.playerSide.opponent &&
            state.turn == setup.playerSide &&
            incomingUndoPly == null &&
            _deferredUndoPly == null;
        if (valid) {
          // The request may arrive while the opponent is still watching the
          // move animation. Keep the turn locked and ask as soon as it ends.
          if (isAnimating) {
            _deferredUndoPly = state.ply;
          } else {
            incomingUndoPly = state.ply;
            _notify();
          }
        } else {
          try {
            setup.network!.send(
              NetworkMessage('undoResponse', {
                'ply': message.data['ply'],
                'accepted': false,
              }),
            );
          } catch (_) {}
        }
      case 'undoResponse':
        if (waitingForUndo &&
            message.data['ply'] == state.ply &&
            message.data['accepted'] is bool) {
          waitingForUndo = false;
          if (message.data['accepted'] == true && _history.isNotEmpty) {
            _restore(1);
          } else {
            notice = 'Друг решил продолжить без отмены хода.';
            _notify();
          }
        }
      case 'resign':
        _resignedWinner = setup.playerSide;
        _generation++;
        animation = null;
        _notify();
      case 'desync':
        fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
        _notify();
      case 'disconnected':
        if (_resignedWinner == null && winner == null) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
          _notify();
        }
      default:
        break;
    }
  }

  void _desync() {
    try {
      setup.network!.send(const NetworkMessage('desync'));
    } catch (_) {}
    fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
    _generation++;
    animation = null;
    _notify();
  }

  void _clearSelection() {
    selected = null;
    _prefix.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @visibleForTesting
  Future<void> playLegalMoveForTest(Move move) => _apply(move, remote: true);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    settings.removeListener(_settingsChanged);
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }
}
