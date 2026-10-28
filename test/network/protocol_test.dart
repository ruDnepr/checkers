import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('параметры партии и запрос отмены сериализуются', () {
    const config = GameConfig(
      variant: GameVariant.international,
      hostSide: Side.black,
      code: 'ABC234',
      hostName: 'Диана',
    );
    final received = GameConfig.fromJson(
      NetworkMessage.decode(
        NetworkMessage('gameConfig', config.toJson()).encode(),
      ).data,
    );
    expect(received.variant, config.variant);
    expect(received.hostSide, Side.black);
    expect(received.firstSide, Side.white);
    expect(received.code, 'ABC234');
    final undo = NetworkMessage.decode(
      const NetworkMessage('undoRequest', {
        'ply': 2,
        'before': '12345678',
      }).encode(),
    );
    expect(undo.data['ply'], 2);
    expect(undo.type, 'undoRequest');
  });

  test('ошибочная версия и неизвестные сообщения отклоняются', () {
    expect(
      () => GameConfig.fromJson({'version': 999, 'code': 'ABC234'}),
      throwsFormatException,
    );
    expect(
      () => NetworkMessage.decode('{"type":"bad","data":{}}'),
      throwsFormatException,
    );
    expect(isGameCode('O01I23'), isFalse);
  });
}
