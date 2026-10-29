import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/game_controller.dart';
import '../application/settings.dart';
import '../application/sounds.dart';
import '../domain/models.dart';
import 'board_game.dart';
import 'network_page.dart';
import 'setup_pages.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    required this.settings,
    required this.setup,
    this.animationPerLanding = const Duration(milliseconds: 350),
    this.initialState,
  });
  final SettingsController settings;
  final GameSetup setup;

  /// Shorter values keep device tests fast; the game itself uses 350 ms.
  final Duration animationPerLanding;

  /// Optional starting position; the game always starts from the initial one.
  final GameState? initialState;
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final GameController controller = GameController(
    widget.setup,
    widget.settings,
    animationPerLanding: widget.animationPerLanding,
    initialState: widget.initialState,
  );
  bool resultShown = false;
  bool resultDialogOpen = false;
  bool resultRecorded = false;
  bool errorShown = false;
  bool undoDialogShown = false;
  bool exiting = false;
  bool get flipped =>
      widget.setup.mode != GameMode.local &&
      widget.setup.playerSide == Side.black;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onGameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.start();
    });
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (controller.fatalMessage != null && !errorShown) {
      errorShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showError();
      });
    } else if (controller.incomingUndoPly != null && !undoDialogShown) {
      undoDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showUndoRequest();
      });
    } else if (controller.isOver &&
        !controller.isAnimating &&
        !resultShown &&
        !controller.waitingForUndo &&
        controller.incomingUndoPly == null &&
        controller.fatalMessage == null) {
      resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResult();
      });
    }
  }

  Future<void> _showError() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ой, что-то случилось'),
        content: Text(controller.fatalMessage ?? 'Связь потеряна.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _goHome();
            },
            child: const Text('В меню'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUndoRequest() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Друг просит отменить ход'),
        content: const Text('Разрешить вернуться на один ход назад?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Не сейчас'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Разрешить'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    undoDialogShown = false;
    if (accepted == true && resultDialogOpen) {
      Navigator.of(context).pop();
      resultDialogOpen = false;
      resultShown = false;
    }
    controller.respondToUndo(accepted == true);
  }

  Future<void> _showResult() async {
    final winner = controller.winner;
    final draw = winner == null && controller.isDraw;
    if (winner == null && !draw) {
      resultShown = false;
      return;
    }
    final mine = winner != null && winner == widget.setup.playerSide;
    // Each ending has its own sound: a win, a soft loss and a calm draw. In a
    // two-player game on one device somebody always won, so it is a win sound.
    controller.sounds.play(
      resultSoundName(
        draw: draw,
        local: widget.setup.mode == GameMode.local,
        iWon: mine,
      ),
    );
    resultDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 25, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Celebration(calm: !mine),
            const SizedBox(height: 12),
            Text(
              draw
                  ? 'Ничья!'
                  : (widget.setup.mode == GameMode.local
                        ? '${winner!.label} победили!'
                        : (mine ? 'Ты молодец!' : 'Отличная партия!')),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              draw
                  ? 'Никто не уступил: позиция повторилась или давно не было '
                        'взятий. Сыграем ещё?'
                  : (mine || widget.setup.mode == GameMode.local
                        ? 'Здорово сыграно! Каждый ход был важен.'
                        : 'В следующий раз обязательно получится!'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: muted,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (controller.canUndo)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                resultDialogOpen = false;
                resultShown = false;
                controller.undo();
              },
              child: const Text('Отменить ход'),
            ),
          TextButton(
            onPressed: () {
              _recordResult(mine);
              Navigator.pop(dialogContext);
              _goHome();
            },
            child: const Text('В меню'),
          ),
          FilledButton(
            onPressed: () {
              _recordResult(mine);
              Navigator.pop(dialogContext);
              _playAgain();
            },
            child: const Text('Играть снова'),
          ),
        ],
      ),
    );
    resultDialogOpen = false;
  }

  void _recordResult(bool won) {
    if (resultRecorded) return;
    resultRecorded = true;
    unawaited(widget.settings.recordGame(won: won));
  }

  void _goHome() {
    if (exiting || !mounted) return;
    exiting = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _playAgain() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final setup = widget.setup;
    final settings = widget.settings;
    exiting = true;
    navigator.popUntil((route) => route.isFirst);
    if (setup.mode == GameMode.network) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              NetworkPage(settings: settings, initialVariant: setup.variant),
        ),
      );
      return;
    }
    final side = await navigator.push<Side>(
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!navigator.mounted || side == null) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => GamePage(
          settings: settings,
          setup: GameSetup(
            variant: setup.variant,
            mode: setup.mode,
            playerSide: side,
            difficulty: setup.difficulty,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (exiting) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти из партии?'),
        content: const Text(
          'Текущая партия закончится. Можно будет начать новую!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Продолжить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('В меню'),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    if (widget.setup.mode == GameMode.network && !controller.isOver) {
      controller.resign();
    }
    _goHome();
  }

  Future<void> _confirmResign() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Закончить партию?'),
        content: const Text('Если сдашься, победа достанется сопернику.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Продолжить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сдаться'),
          ),
        ],
      ),
    );
    if (mounted && yes == true) controller.resign();
  }

  void _showHistory() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFCF7),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'История ходов',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            if (controller.history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Пока ходов нет. Начинаем!',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: controller.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final record = controller.history[index];
                    return ListTile(
                      leading: CheckerIcon(
                        size: 32,
                        dark: record.side == Side.black,
                      ),
                      title: Text(
                        '${index + 1}. ${record.move}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(record.side.label),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    controller.removeListener(_onGameChanged);
    controller.dispose();
    widget.setup.network?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmExit();
    },
    child: ProviderScope(
      overrides: [activeGameProvider.overrideWith((ref) => controller)],
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 510),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final topSide = flipped ? Side.white : Side.black;
                    final bottomSide = topSide.opponent;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // Everything except the board has a measured height, so
                        // the board takes the rest and stays square: the page
                        // does not scroll and no control is cut off. Only an
                        // extremely short window scrolls instead.
                        final compact = constraints.maxHeight < 700;
                        final tiny = constraints.maxHeight < 430;
                        final board = _board();
                        final panels = <Widget>[
                          _playerPanel(topSide, top: true, compact: compact),
                          SizedBox(height: compact ? 8 : 12),
                          if (tiny)
                            AspectRatio(aspectRatio: 1, child: board)
                          else
                            Expanded(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: board,
                                ),
                              ),
                            ),
                          SizedBox(height: compact ? 8 : 12),
                          _playerPanel(bottomSide, top: false, compact: compact),
                          SizedBox(height: compact ? 8 : 12),
                          _message(compact: compact),
                          SizedBox(height: compact ? 8 : 12),
                          _actions(compact: compact),
                          if (!compact) ...[
                            const SizedBox(height: 2),
                            _secondaryActions(),
                          ],
                        ];
                        return Column(
                          children: [
                            _header(compact: compact),
                            Expanded(
                              child: tiny
                                  ? SingleChildScrollView(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        10,
                                      ),
                                      child: Column(children: panels),
                                    )
                                  : Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        compact ? 8 : 14,
                                      ),
                                      child: Column(children: panels),
                                    ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _board() => Transform(
    alignment: Alignment.center,
    transform: Matrix4.identity()
      ..setEntry(3, 2, .001)
      ..rotateX(.025),
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF8B552E),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFB77A3D), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xFF613D23), offset: Offset(0, 6)),
          BoxShadow(
            color: Color(0x446B492D),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: BoardView(controller: controller, flipped: flipped),
    ),
  );

  Widget _secondaryActions() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      TextButton.icon(
        onPressed: _showHistory,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text('История'),
      ),
      TextButton.icon(
        onPressed: controller.isOver ? null : _confirmResign,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: const Text('Сдаться'),
      ),
    ],
  );

  Widget _header({bool compact = false}) => Padding(
    padding: EdgeInsets.fromLTRB(6, compact ? 0 : 4, 6, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: _confirmExit,
          tooltip: 'Назад в меню',
          visualDensity: compact ? VisualDensity.compact : null,
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                widget.setup.variant.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                widget.setup.mode == GameMode.network
                    ? 'Сетевая игра'
                    : (widget.setup.mode == GameMode.local
                          ? 'Два игрока'
                          : 'Против компьютера'),
                style: const TextStyle(
                  fontSize: 10,
                  color: muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shows or hides only the «Подсказка» button under the board.
              // With the hints setting off there is nothing to show, so the
              // switch itself is hidden as well.
              if (widget.settings.hints)
                IconButton(
                  key: const Key('hint-toggle'),
                  tooltip: widget.settings.hintButton
                      ? 'Скрыть кнопку «Подсказка»'
                      : 'Показать кнопку «Подсказка»',
                  visualDensity: compact ? VisualDensity.compact : null,
                  onPressed: () => widget.settings.setHintButton(
                    !widget.settings.hintButton,
                  ),
                  icon: Icon(
                    widget.settings.hintButton
                        ? Icons.lightbulb_rounded
                        : Icons.lightbulb_outline_rounded,
                    color: widget.settings.hintButton
                        ? purple
                        : const Color(0xFFB4ACAF),
                  ),
                ),
              IconButton(
                tooltip: widget.settings.sound
                    ? 'Выключить звук'
                    : 'Включить звук',
                visualDensity: compact ? VisualDensity.compact : null,
                onPressed: () =>
                    widget.settings.setSound(!widget.settings.sound),
                icon: Icon(
                  widget.settings.sound
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: purple,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _nameFor(Side side) {
    if (widget.setup.mode == GameMode.local) {
      return side == widget.setup.playerSide ? 'Игрок 1' : 'Игрок 2';
    }
    if (side == widget.setup.playerSide) return widget.settings.nickname;
    if (widget.setup.mode == GameMode.computer) return 'Компьютер';
    final network = widget.setup.network!;
    return network.isHost
        ? network.peerName
        : (network.config?.hostName ?? 'Друг');
  }

  Widget _playerPanel(Side side, {required bool top, bool compact = false}) {
    final active = controller.state.turn == side && !controller.isOver;
    // On a short screen the panel is one line: name and piece count together.
    final title = compact
        ? '${_nameFor(side)} · ${controller.state.board.count(side)}'
        : _nameFor(side);
    Widget panel = Container(
      key: Key(top ? 'top-player-panel' : 'bottom-player-panel'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEDE5FD)
            : Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(compact ? 15 : 19),
        border: Border.all(
          color: active ? const Color(0xFFB9A3EF) : const Color(0xFFF1EAE5),
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CheckerIcon(size: compact ? 26 : 36, dark: side == Side.black),
          SizedBox(width: compact ? 9 : 12),
          Expanded(
            child: compact
                ? Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${side.label} · '
                        '${controller.state.board.count(side)} шашек',
                        style: const TextStyle(
                          fontSize: 11,
                          color: muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
          if (active)
            Eyebrow(
              'ХОД',
              color: deepPurple,
              background: const Color(0xFFDCCDF8),
              fontSize: compact ? 9 : 10,
            ),
        ],
      ),
    );
    if (top && widget.setup.mode == GameMode.local) {
      panel = RotatedBox(quarterTurns: 2, child: panel);
    }
    return panel;
  }

  /// The bubble under the board. The best move is described here only after
  /// «Подсказка» is pressed; the capture duty is told when a tap is refused.
  Widget _message({bool compact = false}) {
    var text = controller.notice;
    var hint = false;
    if (text == null) {
      text = controller.hintText;
      hint = text != null;
    }
    if (text == null && controller.waitingForUndo) text = 'Ждём ответа друга…';
    if (text == null && controller.computerThinking) text = 'Компьютер думает…';
    if (text == null && controller.isDraw) text = 'Ничья — отличная партия!';
    if (text == null &&
        widget.settings.hints &&
        widget.setup.variant == GameVariant.giveaway) {
      text = 'В поддавках выгодно отдавать шашки!';
    }
    if (text == null && widget.setup.mode == GameMode.network) {
      text = controller.isMyTurn ? 'Твой ход' : 'Ходит друг…';
    }
    text ??=
        'Ходят ${controller.state.turn == Side.white ? 'белые' : 'чёрные'}';
    final canDismiss =
        controller.notice != null || controller.hintText != null;
    return Container(
      key: const Key('message-bubble'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, compact ? 7 : 10, 6, compact ? 7 : 10),
      decoration: BoxDecoration(
        color: hint ? const Color(0xFFFFE8A8) : const Color(0xFFFFF0CA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            hint ? Icons.lightbulb_rounded : Icons.auto_awesome_rounded,
            color: const Color(0xFFBA8940),
            size: compact ? 17 : 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12,
                height: 1.25,
                color: const Color(0xFF795D38),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (canDismiss)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                key: const Key('message-dismiss'),
                padding: EdgeInsets.zero,
                iconSize: 18,
                onPressed: controller.hintText != null
                    ? controller.clearHint
                    : controller.clearNotice,
                tooltip: 'Скрыть',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF9A8060),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The hint button appears only when it can be used right now: a greyed out
  /// button is never shown. While the game is over, an animation runs, an undo
  /// is awaited or the other player is to move there is nothing to hint, so the
  /// row simply shrinks to the undo button. When the button is on the screen it
  /// is always pressable — repeated presses during a running search are ignored
  /// by [GameController.showHint].
  bool get _showHintButton =>
      widget.settings.hints &&
      widget.settings.hintButton &&
      (controller.hintThinking || controller.canInteract);

  Widget _actions({bool compact = false}) => Row(
    children: [
      Expanded(
        child: _ActionButton(
          key: const Key('undo-button'),
          icon: Icons.undo_rounded,
          label: 'Отменить ход',
          enabled: controller.canUndo,
          onTap: controller.undo,
          height: compact ? 46 : 54,
        ),
      ),
      if (_showHintButton) ...[
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            key: const Key('hint-button'),
            icon: Icons.lightbulb_outline_rounded,
            label: controller.hintThinking ? 'Думаю…' : 'Подсказка',
            enabled: true,
            onTap: controller.showHint,
            highlighted: true,
            height: compact ? 46 : 54,
          ),
        ),
      ],
      // Only Russian/giveaway let a man stop a series early, so this button
      // appears exactly when the played series may be finished here.
      if (controller.canFinishCapture) ...[
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            key: const Key('finish-capture-button'),
            icon: Icons.done_all_rounded,
            label: 'Закончить бой',
            enabled: controller.canInteract,
            onTap: controller.finishCapture,
            highlighted: true,
            height: compact ? 46 : 54,
          ),
        ),
      ],
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.highlighted = false,
    this.height = 54,
  });
  final IconData icon;
  final String label;
  final bool enabled, highlighted;
  final double height;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: FilledButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 21),
      label: FittedBox(child: Text(label)),
      style: FilledButton.styleFrom(
        backgroundColor: highlighted ? purple : Colors.white,
        foregroundColor: highlighted ? Colors.white : ink,
        disabledBackgroundColor: const Color(0xFFEFE9E5),
        disabledForegroundColor: const Color(0xFFB4ACAF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
    ),
  );
}

/// The picture above the result text. A win shows a crowned piece with stars,
/// a draw or a loss shows a calm piece without them.
class _Celebration extends StatefulWidget {
  const _Celebration({this.calm = false});
  final bool calm;
  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  Widget _star({
    required double? top,
    required double? bottom,
    required double? left,
    required double? right,
    required Color color,
    required double size,
  }) => Positioned(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    child: Icon(Icons.star_rounded, color: color, size: size),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, _) => SizedBox(
      width: 150,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: .95 + animation.value * (widget.calm ? .04 : .1),
            child: CheckerIcon(size: 76, crown: !widget.calm),
          ),
          if (!widget.calm) ...[
            Positioned(
              top: 5 + animation.value * 5,
              left: 10,
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFF5C254),
                size: 27,
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: purple.withValues(alpha: .7),
                size: 25,
              ),
            ),
            _star(
              top: null,
              bottom: 0,
              left: 22,
              right: null,
              color: const Color(0xFFFFB39D),
              size: 20,
            ),
            _star(
              top: null,
              bottom: 6,
              left: null,
              right: 18,
              color: const Color(0xFFB7DDAF),
              size: 19,
            ),
          ],
        ],
      ),
    ),
  );
}
