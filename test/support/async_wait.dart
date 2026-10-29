import 'dart:async';

import 'package:checkers_for_diana/application/game_controller.dart';

/// Waits until [condition] becomes true, driven by controller notifications.
///
/// Used by the plain (non-widget) tests that wait for a move of the computer or
/// for a message from the other side of a network game.
Future<void> waitUntil(
  GameController game,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (condition()) return;
  final completer = Completer<void>();
  void listener() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  game.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    game.removeListener(listener);
  }
}
