import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/game_controller.dart';
import '../application/settings.dart';
import '../domain/models.dart';
import '../network/network_game_service.dart';
import '../network/protocol.dart';
import 'game_page.dart';
import 'setup_pages.dart';
import 'theme.dart';

enum _LobbyView { choose, host, find }

class NetworkPage extends StatefulWidget {
  const NetworkPage({
    super.key,
    required this.settings,
    this.initialVariant,
    this.service,
  });
  final SettingsController settings;
  final GameVariant? initialVariant;

  /// Allows discovery/transport to be substituted in widget tests.
  final NetworkGameService? service;
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late final NetworkGameService service =
      widget.service ?? NetworkGameService();
  StreamSubscription<NetworkMessage>? _subscription;
  final codeController = TextEditingController();
  final addressController = TextEditingController();
  _LobbyView view = _LobbyView.choose;
  bool transferred = false;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    _subscription = service.events.listen(_onEvent);
  }

  void _onEvent(NetworkMessage event) {
    if (!mounted || transferred) return;
    if (event.type == 'connected' || event.type == 'gameConfig') {
      final config = service.config;
      if (config == null) return;
      transferred = true;
      final side = service.isHost ? config.hostSide : config.hostSide.opponent;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GamePage(
            settings: widget.settings,
            setup: GameSetup(
              variant: config.variant,
              mode: GameMode.network,
              playerSide: side,
              network: service,
            ),
          ),
        ),
      );
    } else if (event.type == 'disconnected') {
      setState(() {
        busy = false;
        message = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
      });
    }
  }

  Future<void> _create() async {
    var variant = widget.initialVariant;
    variant ??= await Navigator.push<GameVariant>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VariantPage(settings: widget.settings, returnSelection: true),
      ),
    );
    if (!mounted || variant == null) return;
    final side = await Navigator.push<Side>(
      context,
      MaterialPageRoute(builder: (_) => GuessPage(settings: widget.settings)),
    );
    if (!mounted || side == null) return;
    setState(() {
      view = _LobbyView.host;
      busy = true;
      message = null;
    });
    final config = GameConfig(
      variant: variant,
      hostSide: side,
      code: NetworkGameService.newCode(),
      hostName: widget.settings.nickname,
    );
    try {
      await service.host(config);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Не получилось создать игру. Проверь подключение к Wi-Fi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _find() async {
    setState(() {
      view = _LobbyView.find;
      busy = true;
      message = null;
    });
    await service.discover();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _connect(String host, int port, {String? code}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await service.connect(
        host,
        port,
        code: code,
        playerName: widget.settings.nickname,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Не получилось подключиться. Проверь адрес и Wi-Fi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _connectCode() {
    final code = codeController.text.trim().toUpperCase();
    if (!isGameCode(code)) {
      setState(() => message = 'Введи шесть символов кода друга.');
      return;
    }
    final game = service.games.where((game) => game.code == code).firstOrNull;
    if (game == null) {
      setState(
        () => message =
            'Пока не нашли игру с этим кодом. Убедись, что вы в одной сети.',
      );
      return;
    }
    _connect(game.host, game.port, code: game.code);
  }

  void _connectAddress() {
    final text = addressController.text.trim();
    final uri = Uri.tryParse('ws://$text');
    if (uri == null ||
        !uri.hasPort ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      setState(() => message = 'Проверь адрес. Пример: 192.168.1.10:12345');
      return;
    }
    _connect(uri.host, uri.port);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    codeController.dispose();
    addressController.dispose();
    if (!transferred) service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Сетевая игра',
    child: ListenableBuilder(
      listenable: service,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          if (view == _LobbyView.choose) ...[
            const Intro(
              eyebrow: 'ВМЕСТЕ ВЕСЕЛЕЕ',
              title: 'Играй с другом',
              subtitle:
                  'Подключите оба устройства к одной сети Wi-Fi или точке доступа.',
            ),
            const SizedBox(height: 28),
            BigButton(
              title: 'Создать игру',
              subtitle: 'Ты выбираешь правила',
              icon: Icons.add_rounded,
              onPressed: _create,
            ),
            const SizedBox(height: 16),
            BigButton(
              title: 'Найти игру / ввести код',
              subtitle: 'Подключись к другу',
              icon: Icons.search_rounded,
              color: const Color(0xFFF4CB67),
              foreground: ink,
              onPressed: _find,
            ),
            const SizedBox(height: 30),
            const _NetworkInfo(
              text:
                  'Интернет и аккаунты не нужны. Игра работает только в одной локальной сети.',
            ),
          ] else if (view == _LobbyView.host) ...[
            const Intro(
              eyebrow: 'ТЫ СОЗДАЁШЬ ИГРУ',
              title: 'Пригласи друга!',
              subtitle:
                  'Скажи другу этот код. Он найдёт твою игру в той же сети.',
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFFEDE4F0)),
                boxShadow: [
                  BoxShadow(
                    color: purple.withValues(alpha: .07),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'КОД ИГРЫ',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    service.config?.code ?? '······',
                    style: const TextStyle(
                      fontSize: 37,
                      letterSpacing: 7,
                      color: deepPurple,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    service.config?.variant.label ?? '',
                    style: const TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Text(
                  busy ? 'Создаём игру…' : 'Ждём друга…',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (service.localAddress != null && service.port != null) ...[
              const SizedBox(height: 26),
              _NetworkInfo(
                text:
                    'Если поиск не работает, взрослый может ввести адрес: ${service.localAddress}:${service.port}',
              ),
            ],
            if (service.discoveryError != null) ...[
              const SizedBox(height: 12),
              _NetworkInfo(text: service.discoveryError!),
            ],
          ] else ...[
            const Intro(
              eyebrow: 'ПОИСК ДРУГА',
              title: 'Найди игру',
              subtitle:
                  'Выбери игру из списка или введи код, который сказал друг.',
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('network-code'),
                    controller: codeController,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z2-9]')),
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'КОД ИГРЫ',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.tag_rounded, color: purple),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: busy ? null : _connectCode,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(92, 58),
                  ),
                  child: const Text('Найти'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text(
                  'Игры рядом',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (busy || service.status == NetworkStatus.discovering)
                  const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (service.games.isEmpty)
              const _NetworkInfo(
                text: 'Пока никого не видно. Поиск продолжается…',
              ),
            for (final game in service.games)
              ChoiceTile(
                title: game.name,
                subtitle: 'Код: ${game.code}',
                icon: Icons.wifi_rounded,
                color: const Color(0xFFDDF1DF),
                onTap: () {
                  if (!busy) _connect(game.host, game.port, code: game.code);
                },
              ),
            if (service.discoveryError != null) ...[
              const SizedBox(height: 10),
              _NetworkInfo(text: service.discoveryError!),
            ],
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text(
                'Подключение по адресу',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'Если поиск не работает, попроси взрослого помочь',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              children: [
                TextField(
                  key: const Key('network-address'),
                  controller: addressController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: '192.168.1.10:12345',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: busy ? null : _connectAddress,
                  child: const Text('Подключиться'),
                ),
                const SizedBox(height: 10),
              ],
            ),
            if (service.status == NetworkStatus.connecting)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    'Подключаемся…',
                    style: TextStyle(
                      color: purple,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
          if (message != null) ...[
            const SizedBox(height: 18),
            _NetworkInfo(text: message!),
          ],
        ],
      ),
    ),
  );
}

class _NetworkInfo extends StatelessWidget {
  const _NetworkInfo({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0E9FC),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: purple, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: ink,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
