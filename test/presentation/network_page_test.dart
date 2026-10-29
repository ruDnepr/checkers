import 'dart:io';

import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:checkers_for_diana/presentation/network_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkService extends NetworkGameService {
  @override
  Future<void> discover() async {
    status = NetworkStatus.discovering;
    notifyListeners();
  }

  @override
  List<DiscoveredGame> get games => const [
    DiscoveredGame(
      code: 'ABC234',
      name: 'Игра Друга',
      host: '192.168.1.2',
      port: 12345,
    ),
  ];
  @override
  Future<void> host(
    GameConfig game, {
    bool advertise = true,
    InternetAddress? bindAddress,
  }) async {
    config = game;
    port = 12345;
    localAddress = '192.168.1.2';
    status = NetworkStatus.hosting;
    notifyListeners();
  }
}

void main() {
  testWidgets('сетевая игра показывает найденные игры и поле кода', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkPage(settings: settings, service: FakeNetworkService()),
      ),
    );
    expect(find.text('Создать игру'), findsOneWidget);
    await tester.tap(find.text('Найти игру / ввести код'));
    await tester.pump();
    expect(find.byKey(const Key('network-code')), findsOneWidget);
    expect(find.text('Игра Друга'), findsOneWidget);
    expect(find.text('Код: ABC234'), findsOneWidget);
  });

  testWidgets('создатель после жеребьёвки видит код и ожидание', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final service = FakeNetworkService();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkPage(
          settings: settings,
          initialVariant: GameVariant.russian,
          service: service,
        ),
      ),
    );
    await tester.tap(find.text('Создать игру'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('hand-left')));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(service.config, isNotNull);
    expect(isGameCode(service.config!.code), isTrue);
    expect(find.text('Ждём друга…'), findsOneWidget);
  });
}
