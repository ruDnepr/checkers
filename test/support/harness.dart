import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/application/sounds.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

export 'async_wait.dart';

/// Pumps the game screen on a fixed virtual device and returns its controller.
///
/// Every widget test of the game screen used to repeat the same twenty lines:
/// the device size, the teardown of that size, the provider scope and the
/// animation duration. They live here once.
Future<GameController> pumpGame(
  WidgetTester tester, {
  required SettingsController settings,
  GameState? state,
  GameVariant variant = GameVariant.russian,
  GameMode mode = GameMode.local,
  Side playerSide = Side.white,
  NetworkGameService? network,
  // Replaces the audio output, so a test can check which sound would play.
  GameSounds? sounds,
  Size size = const Size(400, 1000),
  Duration animationPerLanding = const Duration(milliseconds: 20),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: GamePage(
          settings: settings,
          sounds: sounds,
          initialState: state,
          animationPerLanding: animationPerLanding,
          setup: GameSetup(
            variant: state?.variant ?? variant,
            mode: mode,
            playerSide: playerSide,
            network: network,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return tester.widget<BoardView>(find.byType(BoardView)).controller;
}

/// Plays one complete move by tapping the start square and the landing square.
Future<void> playMove(
  WidgetTester tester,
  GameController game,
  Square from,
  Square to, {
  Duration settle = const Duration(milliseconds: 60),
}) async {
  game.tap(from);
  await tester.pump();
  game.tap(to);
  await tester.pump(settle);
}
