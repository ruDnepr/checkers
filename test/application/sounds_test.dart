import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/application/sounds.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_sounds.dart';

void main() {
  late SettingsController settings;
  late RecordingBackend backend;
  var now = DateTime(2026, 1, 1);

  setUp(() {
    settings = SettingsController();
    backend = RecordingBackend();
    now = DateTime(2026, 1, 1);
  });

  tearDown(() => settings.dispose());

  GameSounds sounds() =>
      GameSounds(settings, backend: backend, clock: () => now);

  test('победитель слышит звук победы, проигравший — другой звук', () {
    expect(
      resultSoundName(draw: false, local: false, iWon: true),
      GameSound.win,
    );
    expect(
      resultSoundName(draw: false, local: false, iWon: false),
      GameSound.lose,
    );
  });

  test('ничья звучит одинаково для обоих игроков', () {
    expect(
      resultSoundName(draw: true, local: false, iWon: true),
      GameSound.draw,
    );
    expect(
      resultSoundName(draw: true, local: false, iWon: false),
      GameSound.draw,
    );
  });

  test('в игре на одном устройстве всегда звучит победа', () {
    expect(
      resultSoundName(draw: false, local: true, iWon: true),
      GameSound.win,
    );
    expect(
      resultSoundName(draw: false, local: true, iWon: false),
      GameSound.win,
    );
  });

  test('при выключенном звуке не играет ничего', () {
    settings.sound = false;
    sounds().play(GameSound.move);
    expect(backend.played, isEmpty);
  });

  test('один и тот же звук не накладывается сам на себя', () {
    final s = sounds();
    s.play(GameSound.move);
    s.play(GameSound.move);
    s.play(GameSound.move);
    expect(backend.played, [GameSound.move]);

    expect(s.lastSound, GameSound.move);

    now = now.add(GameSounds.repeatGap);
    s.play(GameSound.move);
    expect(backend.played, [GameSound.move, GameSound.move]);
  });

  test('звуки ходов не сваливаются в кучу', () {
    final s = sounds();
    s.play(GameSound.move);
    // A capture and a promotion of the same move would be a second event in
    // the same instant; only the first one is heard.
    s.play(GameSound.capture);
    s.play(GameSound.crown);
    expect(backend.played, [GameSound.move]);

    now = now.add(GameSounds.repeatGap);
    s.play(GameSound.capture);
    expect(backend.played, [GameSound.move, GameSound.capture]);
  });

  test('звук окончания партии слышен сразу после хода', () {
    final s = sounds();
    s.play(GameSound.capture);
    // The last move takes the final piece, so the result follows at once and
    // must not be swallowed by the guard above.
    s.play(GameSound.win);
    expect(backend.played, [GameSound.capture, GameSound.win]);
  });

  test('у каждого звука свой файл в assets/audio', () {
    for (final sound in GameSound.values) {
      expect(sound.path, 'assets/audio/${sound.name}.wav');
      expect(sound.fileName, '${sound.name}.wav');
    }
  });
}
