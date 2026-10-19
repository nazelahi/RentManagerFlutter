import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_batch_rent_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_batch_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('DesktopBatchRentModal displays active tenants and records batch payments',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Seed mock state with 2 active tenants and 1 inactive tenant
    final t1 = Tenant(
      id: 't-1',
      name: 'John Doe',
      phone: '+1 555-0101',
      email: 'john@example.com',
      unit: 'Unit 101',
      rentAmount: 1200.0,
      status: 'active',
      joinDate: '2026-01-01',
    );
    final t2 = Tenant(
      id: 't-2',
      name: 'Jane Smith',
      phone: '+1 555-0102',
      email: 'jane@example.com',
      unit: 'Unit 102',
      rentAmount: 1500.0,
      status: 'active',
      joinDate: '2026-01-01',
    );
    final t3 = Tenant(
      id: 't-3',
      name: 'Past Resident',
      phone: '+1 555-0103',
      email: 'past@example.com',
      unit: 'Unit 103',
      rentAmount: 900.0,
      status: 'past',
      joinDate: '2025-01-01',
    );

    container.read(appDataProvider.notifier).upsertTenant(t1);
    container.read(appDataProvider.notifier).upsertTenant(t2);
    container.read(appDataProvider.notifier).upsertTenant(t3);

    // Pump DesktopBatchRentModal
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: DesktopBatchRentModal(
              initialYear: 2026,
              initialMonth: 10,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify modal header & active tenants rendered
    expect(find.text('Batch Rent Collection Sheet'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);
    // Inactive/past tenant should not appear in monthly roll
    expect(find.text('Past Resident'), findsNothing);

    // Verify initial expected subtotal ($1200 + $1500 = $2700)
    expect(find.textContaining('2700'), findsWidgets);

    // Test deselect all
    final deselectBtn = find.text('Deselect All');
    expect(deselectBtn, findsOneWidget);
    await tester.tap(deselectBtn);
    await tester.pumpAndSettle();

    // Confirm commit button shows disabled/0 selected
    expect(find.textContaining('Select tenants to record payment'), findsOneWidget);

    // Test select all unpaid
    final selectAllBtn = find.textContaining('Select All Unpaid');
    expect(selectAllBtn, findsOneWidget);
    await tester.tap(selectAllBtn);
    await tester.pumpAndSettle();

    // Verify commit button is enabled for 2 tenants
    expect(find.textContaining('Collect 2 Payments'), findsOneWidget);

    // Click commit batch collection
    await tester.tap(find.textContaining('Collect 2 Payments'));
    await tester.pumpAndSettle();
    // Allow AppDataNotifier debounced disk save timer (1s) to fire
    await tester.pump(const Duration(seconds: 2));

    // Verify payments in container state
    final updatedState = container.read(appDataProvider);
    final octPayments = updatedState.payments
        .where((p) => p.paidForMonth == '2026-10' && p.status == 'paid')
        .toList();
    expect(octPayments.length, 2);
    expect(octPayments.any((p) => p.tenantId == 't-1' && p.amount == 1200), isTrue);
    expect(octPayments.any((p) => p.tenantId == 't-2' && p.amount == 1500), isTrue);
  });
}
