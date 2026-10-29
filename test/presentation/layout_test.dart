import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:checkers_for_diana/presentation/board_game.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A board with one piece of each colour, so every layout test starts from a
/// position where both players may move.
GameState calmPosition({Side turn = Side.white}) => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white),
    const Square(2, 1): const Piece(Side.black),
  }),
  turn: turn,
);

/// A connected service that never sends anything: enough to render a network
/// game without sockets.
class SilentService extends NetworkGameService {
  @override
  Stream<NetworkMessage> get events => const Stream.empty();

  @override
  void send(NetworkMessage message) {}
}

Future<void> pumpAt(
  WidgetTester tester,
  Size size, {
  required SettingsController settings,
  GameMode mode = GameMode.local,
  Side turn = Side.white,
  NetworkGameService? network,
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
          initialState: calmPosition(turn: turn),
          animationPerLanding: const Duration(milliseconds: 20),
          setup: GameSetup(
            variant: GameVariant.russian,
            mode: mode,
            playerSide: Side.white,
            network: network,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('на маленьком телефоне все элементы помещаются без прокрутки', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    const size = Size(360, 640);
    await pumpAt(tester, size, settings: settings);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(BoardView), findsOneWidget);

    // The board is a square that fits the width of the screen.
    final board = tester.getRect(find.byType(BoardView));
    expect(board.width, closeTo(board.height, 1));
    expect(board.width, lessThanOrEqualTo(size.width));

    // Every control is fully inside the screen: nothing is cut off at the
    // bottom, which was the complaint about the old scrolling layout.
    for (final key in const [
      'top-player-panel',
      'bottom-player-panel',
      'message-bubble',
      'undo-button',
      'hint-button',
    ]) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(rect.top, greaterThanOrEqualTo(0), reason: key);
      expect(rect.bottom, lessThanOrEqualTo(size.height), reason: key);
    }

    // The secondary links are hidden on a short screen but can be reached from
    // the result dialog and the board itself, so the game stays playable.
    expect(find.text('История'), findsNothing);
  });

  testWidgets('на большом экране видны история и сдача', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await pumpAt(tester, const Size(420, 1000), settings: settings);

    expect(tester.takeException(), isNull);
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Сдаться'), findsOneWidget);
    final undo = tester.getRect(find.byKey(const Key('undo-button')));
    expect(undo.bottom, lessThanOrEqualTo(1000));
  });

  testWidgets('на очень низком экране включается прокрутка без переполнения', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await pumpAt(tester, const Size(360, 400), settings: settings);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
  });

  testWidgets('кнопки подсказки нет, когда ход не твой', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);

    // In a network game the player is white, so while the friend is to move
    // there is nothing to hint and the button must not be on the screen at all.
    final service = SilentService()
      ..status = NetworkStatus.connected
      ..isHost = true
      ..config = const GameConfig(
        variant: GameVariant.russian,
        hostSide: Side.white,
        code: 'ABC234',
      )
      ..peerName = 'Друг';
    await pumpAt(
      tester,
      const Size(400, 900),
      settings: settings,
      mode: GameMode.network,
      turn: Side.black,
      network: service,
    );

    expect(find.byKey(const Key('hint-button')), findsNothing);
    // The undo button stays on the screen.
    expect(find.byKey(const Key('undo-button')), findsOneWidget);
    expect(find.text('Ходит друг…'), findsOneWidget);
  });
}
