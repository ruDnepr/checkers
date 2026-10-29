import 'dart:async';
import 'package:flame_audio/flame_audio.dart';
import 'settings.dart';

/// The sound that matches the end of a game for this player. A draw has its own
/// calm tone; otherwise the winner hears the win sound and the loser a softer
/// falling one. In a two-player game on one device somebody always won, so
/// there the win sound is played.
String resultSoundName({
  required bool draw,
  required bool local,
  required bool iWon,
}) => draw ? 'draw' : (local || iWon ? 'win' : 'lose');

class GameSounds {
  const GameSounds(this.settings);
  final SettingsController settings;

  void play(String name) {
    if (!settings.sound) return;
    // Audio is optional: a missing device or an interrupted player must never
    // break a move or prevent the game from starting.
    unawaited(
      FlameAudio.play(
        '$name.wav',
        volume: 0.45,
      ).then<void>((_) {}).catchError((_) {}),
    );
  }
}
