import 'dart:async';

import 'package:flutter/material.dart';

import '../application/settings.dart';
import 'network_page.dart';
import 'setup_pages.dart';
import 'theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.settings});
  final SettingsController settings;
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(settings: widget.settings),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: Center(
        child: FadeTransition(
          opacity: _animation,
          child: ScaleTransition(
            scale: Tween(begin: .75, end: 1.0).animate(
              CurvedAnimation(parent: _animation, curve: Curves.elasticOut),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Logo(size: 125),
                const SizedBox(height: 28),
                Text(
                  'Шашки для Дианы',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Время играть и улыбаться!',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.settings});
  final SettingsController settings;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Eyebrow('ИГРАЕМ ВМЕСТЕ ✦'),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsPage(settings: settings),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.settings_rounded,
                              color: purple,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _Logo(size: 132),
                    const SizedBox(height: 22),
                    const Text(
                      'Шашки\nдля Дианы',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 37,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 11),
                    const Text(
                      'Думай, играй и улыбайся!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 29),
                    BigButton(
                      title: 'Играть',
                      subtitle: 'Выбери свою игру',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VariantPage(settings: settings),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    BigButton(
                      title: 'Сетевая игра',
                      subtitle: 'С другом по Wi-Fi',
                      icon: Icons.wifi_rounded,
                      color: const Color(0xFFF4CB67),
                      foreground: ink,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NetworkPage(settings: settings),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallMenu(
                            icon: Icons.menu_book_rounded,
                            label: 'Правила',
                            color: const Color(0xFFE9E1FB),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RulesPage(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SmallMenu(
                            icon: Icons.tune_rounded,
                            label: 'Настройки',
                            color: const Color(0xFFFCE4D7),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsPage(settings: settings),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      settings.gamesPlayed == 0
                          ? 'Каждая партия — маленькое приключение ✨'
                          : 'Сыграно партий: ${settings.gamesPlayed}  ·  Побед: ${settings.gamesWon}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SmallMenu extends StatelessWidget {
  const _SmallMenu({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .82),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: ink, size: 21),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, color: ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 45,
    height: size + 25,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 15,
          top: 10,
          child: Transform.rotate(
            angle: -.12,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF8C5831),
                borderRadius: BorderRadius.circular(23),
                boxShadow: const [
                  BoxShadow(color: Color(0xFFA66C3D), offset: Offset(0, 7)),
                  BoxShadow(
                    color: Color(0x33714850),
                    blurRadius: 20,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(painter: _MiniBoardPainter()),
              ),
            ),
          ),
        ),
        Positioned(
          left: -2,
          top: size * .28,
          child: Transform.rotate(
            angle: -.2,
            child: CheckerIcon(size: size * .40),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 5,
          child: Transform.rotate(
            angle: .2,
            child: CheckerIcon(size: size * .42, dark: true, crown: true),
          ),
        ),
        Positioned(
          right: 2,
          top: 0,
          child: Transform.rotate(
            angle: .2,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: const Color(0xFFF0BE48),
              size: size * .24,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MiniBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final rect = Rect.fromLTWH(
          c * size.width / 4,
          r * size.height / 4,
          size.width / 4,
          size.height / 4,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = (r + c).isEven
                ? const Color(0xFFFFD767)
                : const Color(0xFF946138),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings});
  final SettingsController settings;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Настройки',
    child: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          const Intro(
            eyebrow: 'ВСЁ ПОД ТЕБЯ',
            title: 'Как тебе удобнее?',
            subtitle: 'Настрой игру так, чтобы она приносила радость.',
          ),
          const SizedBox(height: 26),
          _SettingsSwitch(
            icon: Icons.lightbulb_rounded,
            title: 'Показывать подсказки',
            subtitle: 'Подсветка ходов и советы',
            value: settings.hints,
            onChanged: settings.setHints,
          ),
          _SettingsSwitch(
            icon: Icons.volume_up_rounded,
            title: 'Звуки игры',
            subtitle: 'Мягкие звуки и мелодии',
            value: settings.sound,
            onChanged: settings.setSound,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Твоё имя',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Так тебя увидит друг в сети',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: settings.nickname,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  onChanged: settings.setNickname,
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: cream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              final reset = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Сбросить прогресс?'),
                  content: const Text(
                    'Счётчик партий и побед станет равен нулю. Настройки останутся.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Не сейчас'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Сбросить'),
                    ),
                  ],
                ),
              );
              if (reset == true) await settings.resetProgress();
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Сбросить прогресс'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 54),
              foregroundColor: purple,
              side: const BorderSide(color: Color(0xFFDAD0ED)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: purple,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      secondary: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFF1EAFB),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: purple),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Правила',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: const [
        Intro(
          eyebrow: 'УЧИМСЯ ИГРАЯ',
          title: 'Это просто!',
          subtitle:
              'Выбери свои шашки, ходи по диагонали и получай удовольствие от игры.',
        ),
        SizedBox(height: 24),
        _RuleCard(
          '1',
          'Ходи по диагонали',
          'Обычная шашка идёт на одну клетку вперёд. Дойдя до края доски, она становится дамкой.',
        ),
        _RuleCard(
          '2',
          'Бей, если можешь',
          'Перепрыгни через шашку соперника на свободную клетку. Если можно бить дальше, продолжай тем же ходом.',
        ),
        _RuleCard(
          '3',
          'У каждого вида свои правила',
          'В русских и международных шашках дамка летает, а простая шашка бьёт назад. В классических дамка ходит на одну клетку, а простая не бьёт назад.',
        ),
        _RuleCard(
          '4',
          'Два особенных варианта',
          'В международных нужно взять как можно больше шашек. В поддавках выигрывает тот, кто первым отдаст свои шашки или не сможет ходить.',
        ),
        SizedBox(height: 14),
        Text(
          'Подсказки можно включить или выключить в настройках. Ошибаться и пробовать снова — это нормально! ✨',
          style: TextStyle(
            color: purple,
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _RuleCard extends StatelessWidget {
  const _RuleCard(this.number, this.title, this.text);
  final String number, title, text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFF4E7C4),
          child: Text(
            number,
            style: const TextStyle(color: ink, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: muted,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
