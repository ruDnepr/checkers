import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/application/sounds.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_sounds.dart';
import '../support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('звук хода звучит один раз на ход', (tester) async {
    final settings = SettingsController()..sound = true;
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    final game = await pumpGame(
      tester,
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 3));
    await tester.pump(const Duration(milliseconds: 200));

    expect(backend.played, [GameSound.move]);
  });

  testWidgets('звук не играет, когда звуки выключены', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    final game = await pumpGame(
      tester,
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 3));
    await tester.pump(const Duration(milliseconds: 200));

    expect(backend.played, isEmpty);
  });

  testWidgets('проигрыш звучит мягким звуком, победы нет', (tester) async {
    final settings = SettingsController()..sound = true;
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    await pumpGame(
      tester,
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      mode: GameMode.computer,
      size: const Size(400, 900),
    );

    // Against the computer resigning means losing.
    await tester.tap(find.text('Сдаться'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сдаться'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Отличная партия!'), findsOneWidget);
    expect(backend.played, [GameSound.lose]);
  });

  testWidgets('в игре на одном устройстве слышна победа', (tester) async {
    final settings = SettingsController()..sound = true;
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    await pumpGame(
      tester,
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      size: const Size(400, 900),
    );

    await tester.tap(find.text('Сдаться'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сдаться'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Чёрные победили!'), findsOneWidget);
    expect(backend.played, [GameSound.win]);
  });

  testWidgets('ничья звучит спокойным звуком', (tester) async {
    final settings = SettingsController()..sound = true;
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    // Only kings are left and the quiet series is one ply short of its limit:
    // the next move makes it 60 plies without a capture, and that is a draw.
    final state = GameState(
      variant: GameVariant.russian,
      board: Board(GameVariant.russian.boardSize, {
        const Square(5, 2): const Piece(Side.white, king: true),
        const Square(0, 1): const Piece(Side.black, king: true),
      }),
      turn: Side.white,
      quietPlies: 59,
    );
    final game = await pumpGame(
      tester,
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      state: state,
      size: const Size(400, 900),
    );

    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ничья!'), findsOneWidget);
    expect(backend.played, [GameSound.move, GameSound.draw]);
  });
}
