import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/game_controller.dart';
import '../application/settings.dart';
import '../domain/models.dart';
import 'board_game.dart';
import 'network_page.dart';
import 'setup_pages.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.settings, required this.setup});
  final SettingsController settings;
  final GameSetup setup;
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final GameController controller = GameController(
    widget.setup,
    widget.settings,
  );
  bool resultShown = false;
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
    } else if (controller.winner != null &&
        !controller.isAnimating &&
        !resultShown &&
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
    controller.respondToUndo(accepted == true);
  }

  Future<void> _showResult() async {
    final winner = controller.winner;
    if (winner == null) {
      resultShown = false;
      return;
    }
    final mine = winner == widget.setup.playerSide;
    unawaited(widget.settings.recordGame(won: mine));
    controller.sounds.play('win');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 25, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Celebration(),
            const SizedBox(height: 12),
            Text(
              widget.setup.mode == GameMode.local
                  ? '${winner.label} победили!'
                  : (mine ? 'Ты молодец!' : 'Отличная партия!'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mine || widget.setup.mode == GameMode.local
                  ? 'Здорово сыграно! Каждый ход был важен.'
                  : 'В следующий раз обязательно получится!',
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
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _goHome();
            },
            child: const Text('В меню'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _playAgain();
            },
            child: const Text('Играть снова'),
          ),
        ],
      ),
    );
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
    if (widget.setup.mode == GameMode.network && controller.winner == null) {
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
                    return Column(
                      children: [
                        _header(),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                            child: Column(
                              children: [
                                _playerPanel(topSide, top: true),
                                const SizedBox(height: 12),
                                Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, .001)
                                    ..rotateX(.025),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B552E),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: const Color(0xFFB77A3D),
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0xFF613D23),
                                          offset: Offset(0, 7),
                                        ),
                                        BoxShadow(
                                          color: Color(0x446B492D),
                                          blurRadius: 20,
                                          offset: Offset(0, 15),
                                        ),
                                      ],
                                    ),
                                    child: BoardView(
                                      controller: controller,
                                      flipped: flipped,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _playerPanel(bottomSide, top: false),
                                const SizedBox(height: 16),
                                _message(),
                                const SizedBox(height: 16),
                                _actions(),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _showHistory,
                                      icon: const Icon(
                                        Icons.history_rounded,
                                        size: 19,
                                      ),
                                      label: const Text('История'),
                                    ),
                                    TextButton.icon(
                                      onPressed: controller.winner == null
                                          ? _confirmResign
                                          : null,
                                      icon: const Icon(
                                        Icons.flag_outlined,
                                        size: 19,
                                      ),
                                      label: const Text('Сдаться'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: _confirmExit,
          tooltip: 'Назад в меню',
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                widget.setup.variant.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
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
                  fontSize: 11,
                  color: muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => IconButton(
            tooltip: widget.settings.sound ? 'Выключить звук' : 'Включить звук',
            onPressed: () => widget.settings.setSound(!widget.settings.sound),
            icon: Icon(
              widget.settings.sound
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              color: purple,
            ),
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
    return network.isHost ? 'Друг' : (network.config?.hostName ?? 'Друг');
  }

  Widget _playerPanel(Side side, {required bool top}) {
    final active = controller.state.turn == side && controller.winner == null;
    Widget panel = Container(
      key: Key(top ? 'top-player-panel' : 'bottom-player-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEDE5FD)
            : Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: active ? const Color(0xFFB9A3EF) : const Color(0xFFF1EAE5),
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CheckerIcon(size: 36, dark: side == Side.black),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameFor(side),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${side.label} · ${controller.state.board.count(side)} шашек',
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
            const Eyebrow(
              'ХОД',
              color: deepPurple,
              background: Color(0xFFDCCDF8),
            ),
        ],
      ),
    );
    if (top && widget.setup.mode == GameMode.local)
      panel = RotatedBox(quarterTurns: 2, child: panel);
    return panel;
  }

  Widget _message() {
    var text = controller.notice;
    if (text == null && controller.waitingForUndo) text = 'Ждём ответа друга…';
    if (text == null && controller.computerThinking) text = 'Компьютер думает…';
    if (text == null && widget.settings.hints && controller.hasCapture) {
      text = widget.setup.variant == GameVariant.international
          ? 'Нужно побить как можно больше шашек: ${controller.maximumCapture}.'
          : 'Сейчас нужно бить шашку соперника!';
    }
    if (text == null &&
        widget.settings.hints &&
        widget.setup.variant == GameVariant.giveaway) {
      text = 'В поддавках нужно стараться отдать свои шашки!';
    }
    text ??=
        'Ходят ${controller.state.turn == Side.white ? 'белые' : 'чёрные'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0CA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFFBA8940),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF795D38),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() => Row(
    children: [
      Expanded(
        child: _ActionButton(
          key: const Key('undo-button'),
          icon: Icons.undo_rounded,
          label: 'Отменить ход',
          enabled: controller.canUndo,
          onTap: controller.undo,
        ),
      ),
      if (widget.settings.hints) ...[
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            key: const Key('hint-button'),
            icon: Icons.lightbulb_outline_rounded,
            label: controller.hintThinking ? 'Думаю…' : 'Подсказка',
            enabled: controller.canInteract && !controller.hintThinking,
            onTap: controller.showHint,
            highlighted: true,
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
  });
  final IconData icon;
  final String label;
  final bool enabled, highlighted;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
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

class _Celebration extends StatefulWidget {
  const _Celebration();
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
            scale: .95 + animation.value * .1,
            child: const CheckerIcon(size: 76, crown: true),
          ),
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
          Positioned(
            bottom: 0,
            left: 22,
            child: const Icon(
              Icons.star_rounded,
              color: Color(0xFFFFB39D),
              size: 20,
            ),
          ),
          Positioned(
            bottom: 6,
            right: 18,
            child: const Icon(
              Icons.star_rounded,
              color: Color(0xFFB7DDAF),
              size: 19,
            ),
          ),
        ],
      ),
    ),
  );
}
