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

/// Device runs are slow: wait for a condition by pumping real frames instead of
/// blocking inside `runAsync`, so a stuck game fails with a readable message.
Future<void> waitForGame(
  WidgetTester tester,
  GameController game,
  bool Function() condition, {
  String reason = 'состояние партии',
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Не дождались: $reason (за ${timeout.inSeconds} с). '
        'Ход: ${game.state.turn.label}, полуходов: ${game.state.ply}, '
        'ошибка: ${game.fatalMessage ?? 'нет'}',
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'на устройстве открываются меню и жеребьёвка',
    (tester) async {
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GuessPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('hand-left')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ТЫ ИГРАЕШЬ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(GamePage), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'подсказка, ответ компьютера и отмена на устройстве',
    (tester) async {
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
              animationPerLanding: const Duration(milliseconds: 40),
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
      expect(game.canInteract, isTrue, reason: 'ход должен быть у игрока');

      await tester.ensureVisible(find.byKey(const Key('hint-button')));
      await tester.tap(find.byKey(const Key('hint-button')));
      await waitForGame(
        tester,
        game,
        () => game.suggestedMove != null,
        reason: 'подсказка с подсветкой хода',
      );
      expect(game.suggestedMove, isNotNull);

      final initial = game.state.fingerprint;
      await tester.ensureVisible(find.byType(BoardView));
      await tester.pump();
      final rect = tester.getRect(find.byType(BoardView));
      final cell = rect.width / game.state.board.size;
      await tester.tapAt(
        Offset(rect.left + cell * .5, rect.top + cell * 5.5),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(
        Offset(rect.left + cell * 1.5, rect.top + cell * 4.5),
      );
      await waitForGame(
        tester,
        game,
        () => game.state.ply == 2 && !game.isAnimating,
        reason: 'ответ компьютера на полуходе 2',
      );

      await tester.ensureVisible(find.byKey(const Key('undo-button')));
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pump();
      expect(game.state.fingerprint, initial);

      await settings.setHints(false);
      await tester.pump();
      expect(find.byKey(const Key('hint-button')), findsNothing);
      expect(game.legalMoves, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'поддавки: обязательный бой блокирует тихие ходы',
    (tester) async {
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
              animationPerLanding: const Duration(milliseconds: 40),
              setup: const GameSetup(
                variant: GameVariant.giveaway,
                mode: GameMode.local,
                playerSide: Side.white,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final game = tester.widget<BoardView>(find.byType(BoardView)).controller;
      expect(find.textContaining('В поддавках'), findsOneWidget);
      expect(game.legalMoves.every((move) => !move.isCapture), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'WebSocket на устройстве обменивается настройками по loopback',
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
