import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_topbar_util_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  group('Universal Actions & Utility Panel Enhancements', () {
    testWidgets('Top bar renders prominent Actions button with categorized menu',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) => AppDataNotifier()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify the enhanced "Actions" button is visible in top bar
      final actionsBtn = find.text('Actions');
      expect(actionsBtn, findsOneWidget);

      // 2. Tap the Actions button to open the categorized universal action menu
      await tester.tap(actionsBtn);
      await tester.pumpAndSettle();

      // 3. Verify section headers exist
      expect(find.text('OPERATIONS'), findsOneWidget);
      expect(find.text('FINANCE & TOOLS'), findsOneWidget);
      expect(find.text('DATA & SYSTEM'), findsOneWidget);

      // 4. Verify key universal operations are present
      expect(find.text('Collect Rent'), findsOneWidget);
      expect(find.text('Record Expense'), findsOneWidget);
      expect(find.text('New Work Order'), findsOneWidget);
      expect(find.text('Upload Document'), findsOneWidget);
      expect(find.text('Calculator & Scratchpad'), findsOneWidget);

      // Close menu
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('Utility panel features 3-mode calculator, scratchpad stats, and activity filters',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testTenant = Tenant(
        id: 't-1',
        name: 'John Doe',
        unit: 'Apt 4B',
        phone: '123456',
        email: 'john@example.com',
        rentAmount: 1500,
        joinDate: '2026-01-01',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final n = AppDataNotifier();
            n.state = n.state.copyWith(tenants: [testTenant]);
            return n;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // Open utility drawer using the toggle button in top bar (Ionicons.browsersOutline)
      final toggleBtn = find.byTooltip('Open Utility Panel (⌘I) • Calculator, Scratchpad & Activity');
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Utility Panel header is visible
      expect(find.text('Utility Panel'), findsOneWidget);

      // 1. Scratchpad Tab
      expect(find.text('QUICK NOTES'), findsOneWidget);
      expect(find.textContaining('words •'), findsOneWidget);
      expect(find.text('Auto-saved'), findsOneWidget);

      // 2. Switch to Calculator Tab
      final calcTab = find.text('Calculator');
      await tester.tap(calcTab);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify 3 mode pills: Prorated, Deposit, Quick Math
      expect(find.text('Prorated'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('Quick Math'), findsOneWidget);

      // In Prorated mode, verify interoperability buttons exist
      expect(find.text('Collect Rent'), findsOneWidget);
      expect(find.text('Add to Notes'), findsOneWidget);
      expect(find.text('Copy Proration Breakdown'), findsOneWidget);

      // Switch to Quick Math mode
      await tester.tap(find.text('Quick Math'));
      await tester.pump(const Duration(milliseconds: 200));

      // Check math keypad keys exist
      expect(find.text('C'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('Copy Result'), findsOneWidget);

      // Perform a calculation: 7 + 5 = 12
      await tester.tap(find.text('7'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('+'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('5'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('='));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('12'), findsOneWidget);

      // 3. Switch to Activity Tab
      final activityTab = find.text('Activity');
      await tester.tap(activityTab);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify filter pills and search bar are present
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Tenants'), findsWidgets);
      expect(find.text('Filter activity...'), findsOneWidget);
    });
  });
}
