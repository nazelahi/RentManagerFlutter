import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/onboarding/profile_setup_modal.dart';
import 'package:rentmanager/features/onboarding/setup_sheet.dart';

void main() {
  Directory? tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_profile_test');
    await AppStorage.initWithPath(tempDir!.path);
  });
  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('profile setup sheet accepts text input on mobile viewport',
      (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final original = PropertyManager(
      id: '1',
      name: '',
      email: '',
      phone: '',
      address: '',
      propertyName: '',
      ownerName: '',
      propertyPictures: const [],
    );

    PropertyManager? captured;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured =
                        await showProfileSetupSheet(ctx, initial: original);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet starts on the Manager Picture section - tap Continue.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Full Name *'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields.evaluate().length, 3);

    await tester.enterText(fields.first, 'John Doe');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'john@test.com');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(2), '555-0100');
    await tester.pumpAndSettle();

    // Errors should be gone for valid values.
    expect(find.text('Property manager name is required'), findsNothing);

    // Continue to property section.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final propFields = find.byType(TextField);
    expect(propFields.evaluate().length, 3);
    await tester.enterText(propFields.first, 'Sunset Villa');
    await tester.pumpAndSettle();
    await tester.enterText(propFields.at(2), '123 Main Street, Springfield');
    await tester.pumpAndSettle();

    final sheetRect = tester.getRect(find.byType(SetupSheet));
    debugPrint('setupSheet rect=$sheetRect');
    debugPrint('viewport=${tester.view.physicalSize}');
    debugPrint(
        'scrollable visible=${tester.getRect(find.byType(SingleChildScrollView))}');

    // Reach the Save button by scrolling (like a real user).
    await tester.dragUntilVisible(
        find.text('Save Profile'), find.byType(SingleChildScrollView),
        const Offset(0, -150));
    await tester.pumpAndSettle();

    final saveRect = tester.getRect(find.text('Save Profile'));
    debugPrint('saveLabel rect after scroll=$saveRect');
    expect(
        saveRect.topLeft.dy < sheetRect.bottom &&
            saveRect.bottomRight.dy <= sheetRect.bottom,
        isTrue,
        reason: 'Save button must stay inside the visible sheet area');

    // Save.
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.name, 'John Doe');
    expect(captured!.email, 'john@test.com');
    expect(captured!.phone, '555-0100');
    expect(captured!.propertyName, 'Sunset Villa');
  });
}
