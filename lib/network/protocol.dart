import 'dart:convert';

import '../domain/models.dart';

const protocolVersion = 1;
const serviceType = '_diana-checkers._tcp';
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _codePattern = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');

bool isGameCode(String value) => _codePattern.hasMatch(value);

class GameConfig {
  const GameConfig({required this.variant, required this.hostSide, required this.code, this.hostName = 'Друг'});
  final GameVariant variant;
  final Side hostSide;
  final String code;
  final String hostName;
  Side get firstSide => variant.firstSide;

  Map<String, Object> toJson() => {
    'version': protocolVersion, 'variant': variant.name, 'hostSide': hostSide.name,
    'firstSide': firstSide.name, 'code': code, 'hostName': hostName,
  };

  factory GameConfig.fromJson(Object? data) {
    if (data is! Map || data['version'] != protocolVersion || data['code'] is! String ||
        !isGameCode(data['code'] as String) || data['hostName'] is! String ||
        (data['hostName'] as String).length > 40) {
      throw const FormatException('Настройки сетевой игры не распознаны');
    }
    final variant = GameVariant.values.where((v) => v.name == data['variant']).firstOrNull;
    final side = Side.values.where((v) => v.name == data['hostSide']).firstOrNull;
    if (variant == null || side == null || data['firstSide'] != variant.firstSide.name) {
      throw const FormatException('Настройки сетевой игры не распознаны');
    }
    return GameConfig(variant: variant, hostSide: side, code: data['code'] as String,
        hostName: data['hostName'] as String);
  }
}

class NetworkMessage {
  const NetworkMessage(this.type, [this.data = const {}]);
  final String type;
  final Map<String, Object?> data;
  static const types = {
    'hello', 'gameConfig', 'move', 'undoRequest', 'undoResponse',
    'resign', 'ping', 'pong', 'desync', 'error', 'connected', 'disconnected',
  };

  String encode() => jsonEncode({'type': type, 'data': data});

  factory NetworkMessage.decode(Object? text) {
    if (text is! String || text.length > 16384) throw const FormatException('Некорректное сообщение');
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['type'] is! String || !types.contains(decoded['type']) ||
        decoded['data'] is! Map) throw const FormatException('Неизвестное сообщение');
    return NetworkMessage(decoded['type'] as String, Map<String, Object?>.from(decoded['data'] as Map));
  }
}
