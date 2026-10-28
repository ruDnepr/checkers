import 'dart:async';
import 'dart:io';

import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/checkers_ai.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/main.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:checkers_for_diana/presentation/setup_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> waitForGame(GameController game, bool Function() condition) async {
  if (condition()) return;
  final done = Completer<void>();
  void listener() {
    if (condition() && !done.isCompleted) done.complete();
  }

  game.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 25));
  } finally {
    game.removeListener(listener);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('на устройстве открываются меню и жеребьёвка', (tester) async {
    final settings = SettingsController();
    await settings.load();
    await settings.setSound(false);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(child: DianaApp(settings: settings, showSplash: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Играть'), findsOneWidget);
    await tester.tap(find.text('Играть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русские шашки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Два игрока'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GuessPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('hand-left')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('ТЫ ИГРАЕШЬ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GamePage), findsOneWidget);
  });

  testWidgets('компьютер, подсказка, два полухода и отмена на устройстве', (
    tester,
  ) async {
    final settings = SettingsController();
    await settings.load();
    await settings.setSound(false);
    await settings.setHints(true);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: GamePage(
            settings: settings,
            setup: const GameSetup(
              variant: GameVariant.russian,
              mode: GameMode.computer,
              playerSide: Side.white,
              difficulty: Difficulty.easy,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final game = tester.widget<BoardView>(find.byType(BoardView)).controller;
    await tester.runAsync(game.showHint);
    await tester.pump();
    expect(game.suggestedMove, isNotNull);
    final initial = game.state.fingerprint;
    final rect = tester.getRect(find.byType(BoardView));
    await tester.tapAt(
      Offset(rect.left + rect.width * .5 / 8, rect.top + rect.height * 5.5 / 8),
    );
    await tester.tapAt(
      Offset(
        rect.left + rect.width * 1.5 / 8,
        rect.top + rect.height * 4.5 / 8,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => waitForGame(game, () => game.state.ply == 2 && !game.isAnimating),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('undo-button')));
    await tester.tap(find.byKey(const Key('undo-button')));
    await tester.pump();
    expect(game.state.fingerprint, initial);
    await settings.setHints(false);
    await tester.pump();
    expect(find.byKey(const Key('hint-button')), findsNothing);
  });

  testWidgets('WebSocket на устройстве обменивается настройками по loopback', (
    tester,
  ) async {
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
    });
  });
}
