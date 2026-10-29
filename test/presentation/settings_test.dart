import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/presentation/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The name field is the only place where the child types, so it is checked on
/// its own: focus, typing without the page fighting back, and committing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A tall surface, so the whole settings page (and the name field with it) is
  /// built and can be focused without scrolling.
  Future<SettingsController> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
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

  /// Removes the page before the settings controller is disposed by the
  /// teardown, so nothing touches it after it is gone.
  Future<void> tearDownPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  final field = find.byKey(const Key('nickname-field'));

  testWidgets('поле имени получает фокус и не теряет набранный текст', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    expect(field, findsOneWidget);

    final node = tester.widget<TextField>(field).focusNode!;
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.enterText(field, 'Алиса');
    await tester.pump();
    // The page rebuilds on every change of the settings; the field must keep
    // both its text and its focus, otherwise the keyboard closes and nothing
    // can be typed.
    expect(tester.widget<TextField>(field).controller!.text, 'Алиса');
    expect(node.hasFocus, isTrue);

    node.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings.nickname, 'Алиса');

    await tearDownPage(tester);
  });

  testWidgets('пустое имя заменяется именем по умолчанию', (tester) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;

    await tester.enterText(field, '   ');
    await tester.pump();
    node.unfocus();
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.nickname, 'Диана');
    // Nothing half-typed is left in the field.
    expect(tester.widget<TextField>(field).controller!.text, 'Диана');

    await tearDownPage(tester);
  });

  testWidgets('имя обрезается до двадцати символов', (tester) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;

    await tester.enterText(field, 'Диана-Василиса-Премудрая');
    await tester.pump();
    node.unfocus();
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.nickname.runes.length, 20);
    expect(settings.nickname.startsWith('Диана-Василиса'), isTrue);

    await tearDownPage(tester);
  });

  testWidgets('имя сохраняется, даже если уйти со страницы во время набора', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;
    node.requestFocus();
    await tester.pump();

    await tester.enterText(field, 'Маша');
    await tester.pump();

    // The page goes away while the field is still focused.
    await tearDownPage(tester);
    await tester.pump();

    expect(settings.nickname, 'Маша');
  });
}
