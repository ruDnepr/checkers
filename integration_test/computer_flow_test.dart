import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/checkers_ai.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'wait_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

      final initial = game.state.fingerprint;
      await tester.ensureVisible(find.byType(BoardView));
      await tester.pump();
      final rect = tester.getRect(find.byType(BoardView));
      final cell = rect.width / game.state.board.size;
      await tester.tapAt(Offset(rect.left + cell * .5, rect.top + cell * 5.5));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(Offset(rect.left + cell * 1.5, rect.top + cell * 4.5));
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
}
