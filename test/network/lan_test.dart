import 'dart:async';
import 'dart:io';

import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(
  GameController controller,
  bool Function() condition,
) async {
  if (condition()) return;
  final completer = Completer<void>();
  void listener() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  controller.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}

void main() {
  test('хост и клиент обмениваются ходом и отменяют его по согласию', () async {
    final host = NetworkGameService();
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });
    const config = GameConfig(
      variant: GameVariant.russian,
      hostSide: Side.white,
      code: 'ABC234',
    );
    await host.host(
      config,
      advertise: false,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect(
      '127.0.0.1',
      host.port!,
      code: config.code,
      playerName: 'Маша',
    );
    await configured.timeout(const Duration(seconds: 5));
    expect(host.status, NetworkStatus.connected);
    expect(host.peerName, 'Маша');
    expect(client.config!.hostSide, Side.white);

    final settings = SettingsController()..sound = false;
    final a = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: Side.white,
        network: host,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    final b = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: Side.black,
        network: client,
      ),
      settings,
      animationPerLanding: const Duration(milliseconds: 300),
    );
    addTearDown(() {
      a.dispose();
      b.dispose();
      settings.dispose();
    });
    final initial = a.state.fingerprint;
    a.tap(const Square(5, 0));
    a.tap(const Square(4, 1));
    await waitFor(b, () => b.state.ply == 1);
    expect(a.state.fingerprint, b.state.fingerprint);
    expect(b.isAnimating, isTrue);
    expect(a.canUndo, isTrue);
    a.undo();
    await waitFor(b, () => b.incomingUndoPly != null);
    expect(a.waitingForUndo, isTrue);
    b.respondToUndo(true);
    await waitFor(a, () => a.state.ply == 0);
    expect(a.state.fingerprint, initial);
    expect(b.state.fingerprint, initial);
  });

  test('соперник может отклонить отмену хода по сети', () async {
    final host = NetworkGameService();
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });
    const config = GameConfig(
      variant: GameVariant.russian,
      hostSide: Side.white,
      code: 'ABC234',
    );
    await host.host(
      config,
      advertise: false,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect('127.0.0.1', host.port!, code: config.code);
    await configured.timeout(const Duration(seconds: 5));
    final settings = SettingsController()..sound = false;
    final a = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: Side.white,
        network: host,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    final b = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: Side.black,
        network: client,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    addTearDown(() {
      a.dispose();
      b.dispose();
      settings.dispose();
    });
    a.tap(const Square(5, 0));
    a.tap(const Square(4, 1));
    await waitFor(b, () => b.state.ply == 1);
    a.undo();
    await waitFor(b, () => b.incomingUndoPly != null);
    b.respondToUndo(false);
    await waitFor(a, () => !a.waitingForUndo && a.notice != null);
    expect(a.state.ply, 1);
    expect(b.state.ply, 1);
    expect(a.notice, contains('без отмены'));
    expect(a.canUndo, isTrue);
  });

  test('рассинхронизация и разрыв связи обнаруживаются', () async {
    final host = NetworkGameService();
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });
    const config = GameConfig(
      variant: GameVariant.russian,
      hostSide: Side.white,
      code: 'ABC234',
    );
    await host.host(
      config,
      advertise: false,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect('127.0.0.1', host.port!, code: config.code);
    await configured.timeout(const Duration(seconds: 5));
    final settings = SettingsController()..sound = false;
    final game = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: Side.black,
        network: client,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    addTearDown(() {
      game.dispose();
      settings.dispose();
    });
    host.send(
      const NetworkMessage('move', {'ply': 0, 'before': 'wrong', 'move': {}}),
    );
    await waitFor(game, () => game.fatalMessage != null);
    expect(game.fatalMessage, contains('перестали совпадать'));
    final disconnected = client.events.firstWhere(
      (event) => event.type == 'disconnected',
    );
    await host.close();
    await disconnected.timeout(const Duration(seconds: 5));
    expect(client.status, NetworkStatus.disconnected);
  });
}
