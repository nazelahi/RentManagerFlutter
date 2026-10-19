import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_settings_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_settings_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('DesktopSettingsView renders with compact style and category navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    bool closed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DesktopSettingsView(
              onClose: () => closed = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Top Bar
    expect(find.text('System Preferences'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // 2. Default category is Profile & Property
    expect(find.text('Property Manager Profile'), findsOneWidget);
    expect(find.text('Property Asset Information'), findsOneWidget);

    // 3. Switch to Appearance & Display
    await tester.tap(find.text('Appearance & Display'));
    await tester.pumpAndSettle();
    expect(find.text('Visual Theme'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(find.text('Regional Currency & Format'), findsOneWidget);

    // 4. Switch to Notifications & Alerts
    await tester.tap(find.text('Notifications & Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Master Notification Switch'), findsOneWidget);
    expect(find.text('Granular Notification Triggers'), findsOneWidget);

    // 5. Switch to System Analytics
    await tester.tap(find.text('System Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Executive Statistics Summary'), findsOneWidget);
    expect(find.text('Total Tenants'), findsOneWidget);

    // 6. Test Done button triggers onClose
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
