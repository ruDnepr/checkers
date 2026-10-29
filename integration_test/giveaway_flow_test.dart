import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'поддавки показывают напоминание и допустимые ходы',
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
      expect(game.legalMoves, isNotEmpty);
      expect(game.legalMoves.every((move) => !move.isCapture), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
