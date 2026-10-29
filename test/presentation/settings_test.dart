import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/presentation/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The name field is the only place where the child types, so it is checked on
/// its own: focus, typing without the page fighting back, and committing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsController> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: settings)),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('поле имени получает фокус и не теряет набранный текст', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    final field = find.byKey(const Key('nickname-field'));
    expect(field, findsOneWidget);

    await tester.tap(field);
    await tester.pump();
    final node = tester.widget<TextField>(field).focusNode!;
    expect(node.hasFocus, isTrue);

    await tester.enterText(field, 'Алиса');
    await tester.pump();
    // The page rebuilds on every keystroke; the field must keep both its text
    // and its focus, otherwise the keyboard closes and nothing can be typed.
    expect(tester.widget<TextField>(field).controller!.text, 'Алиса');
    expect(node.hasFocus, isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(settings.nickname, 'Алиса');
  });

  testWidgets('пустое имя заменяется именем по умолчанию', (tester) async {
    final settings = await pumpSettings(tester);
    final field = find.byKey(const Key('nickname-field'));

    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(settings.nickname, 'Диана');
    // Nothing half-typed is left in the field.
    expect(tester.widget<TextField>(field).controller!.text, 'Диана');
  });

  testWidgets('имя обрезается до двадцати символов', (tester) async {
    final settings = await pumpSettings(tester);
    await tester.enterText(
      find.byKey(const Key('nickname-field')),
      'Диана-Василиса-Премудрая',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(settings.nickname.runes.length, 20);
  });
}
