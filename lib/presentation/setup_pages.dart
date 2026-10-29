import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../application/settings.dart';
import '../application/sounds.dart';
import '../domain/checkers_ai.dart';
import '../domain/models.dart';
import 'game_page.dart';
import 'network_page.dart';
import 'theme.dart';

class VariantPage extends StatelessWidget {
  const VariantPage({
    super.key,
    required this.settings,
    this.returnSelection = false,
  });
  final SettingsController settings;
  final bool returnSelection;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Вариант игры',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 1',
          title: 'Во что сыграем?',
          subtitle: 'У каждой игры свой характер. Выбирай любую!',
        ),
        const SizedBox(height: 25),
        for (final variant in GameVariant.values)
          ChoiceTile(
            title: variant.label,
            subtitle: switch (variant) {
              GameVariant.russian => 'Знакомые правила и летающие дамки',
              GameVariant.american => 'Короткие ходы и классический бой',
              GameVariant.international =>
                'Большая доска и максимальное взятие',
              GameVariant.giveaway => 'Побеждает тот, кто отдаст свои шашки',
            },
            icon: switch (variant) {
              GameVariant.russian => Icons.auto_awesome_rounded,
              GameVariant.american => Icons.extension_rounded,
              GameVariant.international => Icons.public_rounded,
              GameVariant.giveaway => Icons.favorite_rounded,
            },
            color: switch (variant) {
              GameVariant.russian => const Color(0xFFFFE5A3),
              GameVariant.american => const Color(0xFFE6DEF9),
              GameVariant.international => const Color(0xFFD9EFE4),
              GameVariant.giveaway => const Color(0xFFFFDDD3),
            },
            tag: '${variant.boardSize}×${variant.boardSize}',
            onTap: () {
              if (returnSelection) {
                Navigator.pop(context, variant);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ModePage(settings: settings, variant: variant),
                  ),
                );
              }
            },
          ),
      ],
    ),
  );
}

class ModePage extends StatelessWidget {
  const ModePage({super.key, required this.settings, required this.variant});
  final SettingsController settings;
  final GameVariant variant;

  Future<void> _startLocal(BuildContext context) async {
    final side = await Navigator.push<Side>(
      context,
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!context.mounted || side == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GamePage(
          settings: settings,
          setup: GameSetup(
            variant: variant,
            mode: GameMode.local,
            playerSide: side,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Режим игры',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 2',
          title: 'С кем играем?',
          subtitle: 'Можно тренироваться одному или пригласить друга.',
        ),
        const SizedBox(height: 25),
        ChoiceTile(
          title: 'Против компьютера',
          subtitle: 'Выбери уровень и начни приключение',
          icon: Icons.smart_toy_rounded,
          color: const Color(0xFFE8E0FA),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DifficultyPage(settings: settings, variant: variant),
            ),
          ),
        ),
        ChoiceTile(
          title: 'Два игрока',
          subtitle: 'Играйте вместе на одном устройстве',
          icon: Icons.people_alt_rounded,
          color: const Color(0xFFFFE5A3),
          onTap: () => _startLocal(context),
        ),
        ChoiceTile(
          title: 'По сети',
          subtitle: 'Два устройства в одной Wi-Fi-сети',
          icon: Icons.wifi_rounded,
          color: const Color(0xFFD9EFE4),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  NetworkPage(settings: settings, initialVariant: variant),
            ),
          ),
        ),
      ],
    ),
  );
}

class DifficultyPage extends StatelessWidget {
  const DifficultyPage({
    super.key,
    required this.settings,
    required this.variant,
  });
  final SettingsController settings;
  final GameVariant variant;

  Future<void> _start(BuildContext context, Difficulty difficulty) async {
    final side = await Navigator.push<Side>(
      context,
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!context.mounted || side == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GamePage(
          settings: settings,
          setup: GameSetup(
            variant: variant,
            mode: GameMode.computer,
            playerSide: side,
            difficulty: difficulty,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Сложность',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 3',
          title: 'Выбери уровень',
          subtitle: 'Начни с лёгкого — и расти с каждой партией!',
        ),
        const SizedBox(height: 25),
        for (final difficulty in Difficulty.values)
          ChoiceTile(
            title: difficulty.label,
            subtitle: switch (difficulty) {
              Difficulty.easy => 'Учимся и пробуем без спешки',
              Difficulty.medium => 'Немного больше размышлений',
              Difficulty.hard => 'Для настоящих искателей задач',
            },
            icon: Icons.star_rounded,
            color: switch (difficulty) {
              Difficulty.easy => const Color(0xFFDDF1DF),
              Difficulty.medium => const Color(0xFFFFE5A3),
              Difficulty.hard => const Color(0xFFE8DDFB),
            },
            tag: '★' * (difficulty.index + 1),
            onTap: () => _start(context, difficulty),
          ),
      ],
    ),
  );
}

class GuessPage extends StatefulWidget {
  const GuessPage({
    super.key,
    required this.settings,
    this.random,
    this.revealDelay = const Duration(milliseconds: 1600),
  });
  final SettingsController settings;
  final Random? random;
  final Duration revealDelay;
  @override
  State<GuessPage> createState() => _GuessPageState();
}

class _GuessPageState extends State<GuessPage>
    with SingleTickerProviderStateMixin {
  late final int hiddenHand = (widget.random ?? Random.secure()).nextInt(2);
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);
  int? chosen;
  Timer? _timer;

  /// One instance for the page, so the repeated-draw guard works.
  late final GameSounds _sounds = GameSounds(widget.settings);

  void _choose(int hand) {
    if (chosen != null) return;
    setState(() => chosen = hand);
    final guessed = hand == hiddenHand;
    _sounds.play(guessed ? GameSound.guess : GameSound.miss);
    _timer = Timer(widget.revealDelay, () {
      if (mounted) Navigator.pop(context, guessed ? Side.white : Side.black);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Выбираем цвет',
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Intro(
            eyebrow: 'НЕБОЛЬШАЯ ЖЕРЕБЬЁВКА',
            title: 'В какой руке\nшашка?',
            subtitle: 'Угадай, где спряталась белая шашка. Нажми на ладошку!',
          ),
          const SizedBox(height: 30),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: chosen == null
                  ? const Eyebrow(
                      'ВЫБЕРИ ОДНУ РУКУ',
                      background: Color(0xFFFFE8B2),
                      color: Color(0xFF9E7130),
                    )
                  : Eyebrow(
                      chosen == hiddenHand
                          ? 'УГАДАЛА! ТЫ ИГРАЕШЬ БЕЛЫМИ'
                          : 'ПОЧТИ! ТЫ ИГРАЕШЬ ЧЁРНЫМИ',
                      key: ValueKey(chosen == hiddenHand),
                      background: const Color(0xFFE3F2DE),
                      color: const Color(0xFF5C8559),
                    ),
            ),
          ),
          const SizedBox(height: 25),
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: _HandCard(
                    key: const Key('hand-left'),
                    label: 'Левая',
                    index: 0,
                    hiddenHand: hiddenHand,
                    chosen: chosen,
                    angle: -.05 + _bounce.value * .05,
                    onTap: () => _choose(0),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _HandCard(
                    key: const Key('hand-right'),
                    label: 'Правая',
                    index: 1,
                    hiddenHand: hiddenHand,
                    chosen: chosen,
                    angle: .05 - _bounce.value * .05,
                    onTap: () => _choose(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: chosen == null
                  ? const Text(
                      'Готова? Доверься интуиции ✨',
                      key: ValueKey('waiting'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : Text(
                      chosen == hiddenHand
                          ? 'Отличное начало!'
                          : 'Любым цветом можно победить!',
                      key: const ValueKey('revealed'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: purple,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    super.key,
    required this.label,
    required this.index,
    required this.hiddenHand,
    required this.chosen,
    required this.angle,
    required this.onTap,
  });
  final String label;
  final int index, hiddenHand;
  final int? chosen;
  final double angle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: chosen == null ? angle : 0,
    child: Material(
      color: index == 0 ? const Color(0xFFFFE2C9) : const Color(0xFFE8DDFB),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 210,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedScale(
                      scale: chosen == null ? 1 : .85,
                      duration: const Duration(milliseconds: 350),
                      child: Text(
                        chosen == null ? '✊' : '🖐️',
                        style: const TextStyle(fontSize: 72),
                      ),
                    ),
                    if (chosen != null && index == hiddenHand)
                      const Positioned(bottom: 0, child: CheckerIcon(size: 42)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
