// Diagnostic capture for checking the mobile layout in CI. No golden files are
// checked in; ordinary test runs skip this optional diagnostic.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:checkers_for_diana/application/game_controller.dart';
import 'package:checkers_for_diana/application/settings.dart';
import 'package:checkers_for_diana/domain/models.dart';
import 'package:checkers_for_diana/main.dart';
import 'package:checkers_for_diana/presentation/game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final capture = Platform.environment['DIANA_CAPTURE'] == '1';
  testWidgets('capture mobile screens for layout review', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.runAsync(() async {
      final font = FontLoader('Nunito')
        ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final key = GlobalKey();
    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: .65);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/diana-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          child: DianaApp(settings: settings, showSplash: false),
        ),
      ),
    );
    await tester.pump();
    await save('home');
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          child: MaterialApp(
            home: GamePage(
              settings: settings,
              setup: const GameSetup(
                variant: GameVariant.russian,
                mode: GameMode.local,
                playerSide: Side.white,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await save('game');
  }, skip: !capture);
}
