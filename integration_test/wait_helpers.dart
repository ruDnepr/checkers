import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Device runs are slow: wait for a condition by pumping real frames instead of
/// blocking inside `runAsync`, so a stuck game fails with a readable message.
Future<void> waitForGame(
  WidgetTester tester,
  GameController game,
  bool Function() condition, {
  String reason = 'состояние партии',
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Не дождались: $reason (за ${timeout.inSeconds} с). '
        'Ход: ${game.state.turn.label}, полуходов: ${game.state.ply}, '
        'думает компьютер: ${game.computerThinking}, '
        'думает подсказка: ${game.hintThinking}, '
        'анимация: ${game.isAnimating}, '
        'ошибка: ${game.fatalMessage ?? 'нет'}',
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}
