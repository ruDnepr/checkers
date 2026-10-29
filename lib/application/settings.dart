import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  SharedPreferences? _preferences;
  bool hints = true;

  /// Shows the «Подсказка» button under the board. It is a separate switch, so
  /// the button can be hidden while the move highlighting stays on.
  bool hintButton = true;
  bool sound = true;
  String nickname = 'Диана';
  int gamesPlayed = 0;
  int gamesWon = 0;

  Future<void> load() async {
    _preferences = await SharedPreferences.getInstance();
    hints = _preferences!.getBool('hints') ?? true;
    hintButton = _preferences!.getBool('hintButton') ?? true;
    sound = _preferences!.getBool('sound') ?? true;
    nickname = _preferences!.getString('nickname') ?? 'Диана';
    gamesPlayed = _preferences!.getInt('gamesPlayed') ?? 0;
    gamesWon = _preferences!.getInt('gamesWon') ?? 0;
    notifyListeners();
  }

  Future<void> setHints(bool value) async {
    hints = value;
    notifyListeners();
    await _preferences?.setBool('hints', value);
  }

  Future<void> setHintButton(bool value) async {
    hintButton = value;
    notifyListeners();
    await _preferences?.setBool('hintButton', value);
  }

  Future<void> setSound(bool value) async {
    sound = value;
    notifyListeners();
    await _preferences?.setBool('sound', value);
  }

  /// Stores the name. The trimmed text is kept to 20 characters; an empty name
  /// falls back to «Диана». Nothing is announced when the name did not change,
  /// so the field that is being typed into is never rebuilt for nothing.
  Future<void> setNickname(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty
        ? 'Диана'
        : String.fromCharCodes(trimmed.runes.take(20));
    if (next == nickname) return;
    nickname = next;
    notifyListeners();
    await _preferences?.setString('nickname', next);
  }

  Future<void> recordGame({required bool won}) async {
    gamesPlayed++;
    if (won) gamesWon++;
    notifyListeners();
    await _preferences?.setInt('gamesPlayed', gamesPlayed);
    await _preferences?.setInt('gamesWon', gamesWon);
  }

  Future<void> resetProgress() async {
    gamesPlayed = 0;
    gamesWon = 0;
    notifyListeners();
    await _preferences?.setInt('gamesPlayed', 0);
    await _preferences?.setInt('gamesWon', 0);
  }
}
