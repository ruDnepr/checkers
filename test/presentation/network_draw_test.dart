import 'dart:async';

import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/network_game_service.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pair of connected services that hand every message straight to the other
/// side, so the real controller code runs without sockets or mDNS.
class LoopbackService extends NetworkGameService {
  final _incoming = StreamController<NetworkMessage>.broadcast();
  LoopbackService? peer;

  @override
  Stream<NetworkMessage> get events => _incoming.stream;

  @override
  void send(NetworkMessage message) {
    peer?._incoming.add(message);
  }

  @override
  Future<void> close() => _incoming.close();
}

Future<void> waitFor(GameController game, bool Function() condition) async {
  if (condition()) return;
  final completer = Completer<void>();
  void listener() {
    if (condition() && !completer.isCompleted) completer.complete();
  }

  game.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 10));
  } finally {
    game.removeListener(listener);
  }
}

/// Two kings that do not see each other on any diagonal: no capture is
/// possible, so they repeat the same position over and over.
GameState twoKings() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(0, 1): const Piece(Side.black, king: true),
  }),
  turn: Side.white,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ничья по повторению позиции совпадает у обоих игроков', () async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    const config = GameConfig(
      variant: GameVariant.russian,
      hostSide: Side.white,
      code: 'ABC234',
      hostName: 'Диана',
    );
    final hostService = LoopbackService()
      ..status = NetworkStatus.connected
      ..isHost = true
      ..config = config
      ..peerName = 'Друг';
    final guestService = LoopbackService()
      ..status = NetworkStatus.connected
      ..isHost = false
      ..config = config
      ..peerName = 'Диана';
    hostService.peer = guestService;
    guestService.peer = hostService;

    final host = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: config.hostSide,
        network: hostService,
      ),
      settings,
      animationPerLanding: Duration.zero,
      initialState: twoKings(),
    );
    final guest = GameController(
      GameSetup(
        variant: config.variant,
        mode: GameMode.network,
        playerSide: config.hostSide.opponent,
        network: guestService,
      ),
      settings,
      animationPerLanding: Duration.zero,
      initialState: twoKings(),
    );
    addTearDown(host.dispose);
    addTearDown(guest.dispose);
    addTearDown(hostService.close);
    addTearDown(guestService.close);

    const circle = [
      [Square(5, 2), Square(4, 1)],
      [Square(0, 1), Square(1, 2)],
      [Square(4, 1), Square(5, 2)],
      [Square(1, 2), Square(0, 1)],
    ];

    Future<void> move(GameController game, GameController other) async {
      final from = circle[game.state.ply % circle.length][0];
      final to = circle[game.state.ply % circle.length][1];
      game.tap(from);
      game.tap(to);
      await waitFor(other, () => other.state.ply == game.state.ply);
      expect(other.state.fingerprint, game.state.fingerprint);
      expect(other.isDraw, game.isDraw);
    }

    // Two circles bring the position back for the third time.
    for (var i = 0; i < 8; i++) {
      final mover = host.state.turn == config.hostSide ? host : guest;
      final other = mover == host ? guest : host;
      await move(mover, other);
    }

    expect(host.state.ply, 8);
    expect(guest.state.ply, 8);
    expect(host.isDraw, isTrue);
    expect(guest.isDraw, isTrue);
    expect(host.winner, isNull);
    expect(guest.winner, isNull);
    expect(host.isOver, isTrue);
    expect(guest.isOver, isTrue);
    expect(host.canInteract, isFalse);
    expect(guest.canInteract, isFalse);
  });
}
