import 'package:checkers_for_diana/application/sounds.dart';

/// Remembers every effect that was asked for, so a test can check the audio
/// without a device and without the real players.
class RecordingBackend implements SfxBackend {
  final List<GameSound> played = [];

  @override
  Future<void> play(GameSound sound) async => played.add(sound);
}
