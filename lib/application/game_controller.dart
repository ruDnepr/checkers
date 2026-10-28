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
  const _SearchRequest(this.state, this.depth, this.noise);
  final GameState state;
  final int depth;
  final bool noise;
}

Move? _searchMove(_SearchRequest request) => CheckersAI().findBestMove(
  request.state,
  request.depth,
  easyNoise: request.noise,
);

class GameController extends ChangeNotifier {
  GameController(
    this.setup,
    this.settings, {
    this.animationPerLanding = const Duration(milliseconds: 350),
  }) : state = GameState.initial(setup.variant),
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
  MoveAnimation? animation;
  bool computerThinking = false;
  bool hintThinking = false;
  bool waitingForUndo = false;
  int? incomingUndoPly;
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
      (setup.mode == GameMode.local || state.turn == setup.playerSide);
  bool get hasCapture => legalMoves.isNotEmpty && legalMoves.first.isCapture;
  int get maximumCapture => hasCapture ? legalMoves.first.captures.length : 0;

  bool get canUndo {
    if (_history.isEmpty ||
        isAnimating ||
        waitingForUndo ||
        incomingUndoPly != null ||
        fatalMessage != null)
      return false;
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
      if (move.from != selected || move.landings.length < _prefix.length)
        return false;
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

  void start() {
    if (_started) return;
    _started = true;
    if (setup.mode == GameMode.computer && state.turn != setup.playerSide)
      _startComputer();
  }

  void _refresh() => legalMoves = rules.legalMoves(state);
  void _settingsChanged() {
    if (!settings.hints) suggestedMove = null;
    _notify();
  }

  void tap(Square square) {
    if (!canInteract) return;
    notice = null;
    suggestedMove = null;
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
      if (completed != null) {
        _clearSelection();
        unawaited(_apply(completed, remote: false));
      } else {
        _notify();
      }
      return;
    }
    // Once a chain has begun it cannot be abandoned or switched to another piece.
    if (_prefix.isNotEmpty) return;
    if (legalMoves.any((m) => m.from == square)) {
      selected = square;
      _notify();
    } else if (selected != null) {
      selected = null;
      _notify();
    }
  }

  Future<void> showHint() async {
    if (!settings.hints || !canInteract || hintThinking) return;
    final snapshot = state;
    final generation = _generation;
    hintThinking = true;
    _notify();
    try {
      final move = await compute(
        _searchMove,
        _SearchRequest(snapshot, 2, false),
      );
      if (!_disposed &&
          generation == _generation &&
          snapshot.fingerprint == state.fingerprint &&
          settings.hints) {
        _clearSelection();
        suggestedMove = move;
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
    if (setup.mode == GameMode.computer && state.turn != setup.playerSide)
      _startComputer();
  }

  void _startComputer() {
    if (_disposed || computerThinking || winner != null || fatalMessage != null)
      return;
    computerThinking = true;
    final generation = _generation;
    final snapshot = state;
    _notify();
    Future<void>(() async {
      try {
        final move = await compute(
          _searchMove,
          _SearchRequest(
            snapshot,
            setup.difficulty.depth,
            setup.difficulty == Difficulty.easy,
          ),
        );
        if (_disposed ||
            generation != _generation ||
            snapshot.fingerprint != state.fingerprint)
          return;
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
        _history.last.turn != setup.playerSide)
      count = 2;
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
    suggestedMove = null;
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
      _resignedWinner = state.turn.opponent;
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
          if (!legalMoves.contains(move))
            throw const FormatException('Недопустимый ход');
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
            !isAnimating &&
            incomingUndoPly == null;
        if (valid) {
          incomingUndoPly = state.ply;
          _notify();
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
