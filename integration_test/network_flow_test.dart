import 'dart:io';

import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WebSocket на устройстве обменивается ходами по loopback',
    (tester) async {
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
      await tester.runAsync(() async {
        await host.host(
          config,
          advertise: false,
          bindAddress: InternetAddress.loopbackIPv4,
        );
        final ready = client.events.firstWhere(
          (event) => event.type == 'gameConfig',
        );
        await client.connect('127.0.0.1', host.port!, code: config.code);
        await ready.timeout(const Duration(seconds: 10));
        final nextMove = client.events.firstWhere(
          (event) => event.type == 'move',
        );
        host.send(const NetworkMessage('move', {'ply': 0, 'before': 'test'}));
        expect(
          (await nextMove.timeout(const Duration(seconds: 10))).data['ply'],
          0,
        );
        expect(client.status, NetworkStatus.connected);
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
