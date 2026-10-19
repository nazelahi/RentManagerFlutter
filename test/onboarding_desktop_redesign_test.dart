import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/theme/app_theme.dart';
import 'package:rentmanager/features/onboarding/onboarding_view.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_onboarding_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('OnboardingView renders desktop dual-panel layout on wide screen', (tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildDarkAppTheme(),
          home: const OnboardingView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify desktop stepper sidebar branding and step list
    expect(find.text('SETUP ASSISTANT'), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);
    expect(find.text('Local-First Encrypted DB'), findsOneWidget);
    expect(find.text('Welcome to RentManager'), findsWidgets);

    // Verify desktop welcome feature cards
    expect(find.text('Property & Unit Portfolio'), findsOneWidget);
    expect(find.text('Rent Invoicing & Expenses'), findsOneWidget);
    expect(find.text('100% Offline-First Privacy'), findsOneWidget);

    // Tap "Continue" button to move to Step 2 (Restore)
    final continueBtn = find.widgetWithText(ElevatedButton, 'Continue');
    expect(continueBtn, findsOneWidget);
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();

    // Verify Step 2 Restore cards
    expect(find.text('Restore From Backup File'), findsOneWidget);
    expect(find.text('Restore From Google Drive'), findsOneWidget);

    // Future steps stay locked until the required setup is completed, so
    // tapping a later sidebar entry must not navigate away from Step 2.
    final currencyStepTile = find.text('Choose Your Currency');
    expect(currencyStepTile, findsOneWidget);
    await tester.tap(currencyStepTile);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 9'), findsOneWidget);
    expect(find.text('Restore From Google Drive'), findsOneWidget);
  });

  testWidgets('OnboardingView renders mobile layout on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightAppTheme(),
          home: const OnboardingView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sidebar should NOT be rendered on mobile
    expect(find.text('SETUP ASSISTANT'), findsNothing);
    expect(find.text('Local-First Encrypted DB'), findsNothing);

    // Mobile paged view should be rendered
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Welcome to RentManager'), findsOneWidget);
  });
}
