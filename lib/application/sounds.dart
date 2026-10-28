import 'dart:async';
import 'package:flame_audio/flame_audio.dart';
import 'settings.dart';

class GameSounds {
  const GameSounds(this.settings);
  final SettingsController settings;

  void play(String name) {
    if (!settings.sound) return;
    // Audio is optional: a missing device or an interrupted player must never
    // break a move or prevent the game from starting.
    unawaited(FlameAudio.play('$name.wav', volume: 0.45).then<void>((_) {}).catchError((_) {}));
  }
}
