import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/async_wait.dart';

void main() {
  test(
    'отмена возвращает точную позицию, очередь, счётчики и допустимые ходы',
    () async {
      final settings = SettingsController()..sound = false;
      final game = GameController(
        const GameSetup(
          variant: GameVariant.russian,
          mode: GameMode.local,
          playerSide: Side.white,
        ),
        settings,
        animationPerLanding: Duration.zero,
      );
      addTearDown(() {
        game.dispose();
        settings.dispose();
      });
      final before = game.state;
      final legalBefore = game.legalMoves.toSet();
      await game.playLegalMoveForTest(game.legalMoves.first);
      expect(game.state.turn, Side.black);
      expect(game.history, hasLength(1));
      game.undo();
      expect(game.state.fingerprint, before.fingerprint);
      expect(game.state.turn, before.turn);
      expect(
        game.state.board.count(Side.white),
        before.board.count(Side.white),
      );
      expect(game.legalMoves.toSet(), legalBefore);
      expect(game.history, isEmpty);
    },
  );

  test('после ответа компьютера откатываются два полухода', () async {
    final settings = SettingsController()..sound = false;
    final game = GameController(
      const GameSetup(
        variant: GameVariant.russian,
        mode: GameMode.computer,
        playerSide: Side.white,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    addTearDown(() {
      game.dispose();
      settings.dispose();
    });
    final before = game.state.fingerprint;
    await game.playLegalMoveForTest(game.legalMoves.first);
    await waitUntil(game, () => game.state.ply == 2 && !game.isAnimating);
    game.undo();
    expect(game.state.fingerprint, before);
    expect(game.history, isEmpty);
    expect(game.state.turn, Side.white);
  });

  test('отключение подсказок не меняет допустимые ходы', () async {
    final settings = SettingsController()..sound = false;
    final game = GameController(
      const GameSetup(
        variant: GameVariant.russian,
        mode: GameMode.local,
        playerSide: Side.white,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    addTearDown(() {
      game.dispose();
      settings.dispose();
    });
    final before = game.legalMoves.toSet();
    await settings.setHints(false);
    await game.showHint();
    expect(game.suggestedMove, isNull);
    expect(game.legalMoves.toSet(), before);
  });
  test('сдача во время хода компьютера отдаёт победу компьютеру', () async {
    final settings = SettingsController()..sound = false;
    final game = GameController(
      const GameSetup(
        variant: GameVariant.russian,
        mode: GameMode.computer,
        playerSide: Side.white,
      ),
      settings,
      animationPerLanding: Duration.zero,
    );
    addTearDown(() {
      game.dispose();
      settings.dispose();
    });
    await game.playLegalMoveForTest(game.legalMoves.first);
    expect(game.state.turn, Side.black);
    game.resign();
    expect(game.winner, Side.black);
    expect(game.canUndo, isFalse);
  });
}
