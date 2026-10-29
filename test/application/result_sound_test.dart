import 'package:checkers_for_diana/application/sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('победитель слышит звук победы, проигравший — другой звук', () {
    expect(resultSoundName(draw: false, local: false, iWon: true), 'win');
    expect(resultSoundName(draw: false, local: false, iWon: false), 'lose');
  });

  test('ничья звучит одинаково для обоих игроков', () {
    expect(resultSoundName(draw: true, local: false, iWon: true), 'draw');
    expect(resultSoundName(draw: true, local: false, iWon: false), 'draw');
  });

  test('в игре на одном устройстве всегда звучит победа', () {
    expect(resultSoundName(draw: false, local: true, iWon: true), 'win');
    expect(resultSoundName(draw: false, local: true, iWon: false), 'win');
  });
}
