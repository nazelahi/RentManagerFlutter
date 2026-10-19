import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_batch_rent_modal.dart';
import 'package:rentmanager/features/desktop/desktop_cash_flow_modal.dart';
import 'package:rentmanager/features/desktop/desktop_documents_view.dart';
import 'package:rentmanager/features/desktop/desktop_overview_view.dart';
import 'package:rentmanager/features/desktop/desktop_rent_receipt_modal.dart';
import 'package:rentmanager/features/desktop/desktop_reports_view.dart';
import 'package:rentmanager/features/desktop/desktop_settings_view.dart';
import 'package:rentmanager/features/desktop/desktop_shell.dart';
import 'package:rentmanager/features/desktop/desktop_tenants_view.dart';
import 'package:rentmanager/features/desktop/desktop_work_orders_view.dart';
import 'package:rentmanager/features/desktop/desktop_zakat_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_overflow_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  final now = DateTime.now();
  final year = now.year;
  final monthStr = now.month.toString().padLeft(2, '0');
  final monthKey = '$year-$monthStr';

  final sampleTenants = [
    Tenant(
      id: 't-1',
      name: 'Alice Johnson',
      unit: 'Apt 101',
      phone: '+1 555-0101',
      email: 'alice@example.com',
      rentAmount: 1800.0,
      deposit: 1800.0,
      status: 'active',
      joinDate: '$year-01-01',
      leaseStartDate: '$year-01-01',
      leaseEndDate: '$year-12-31',
    ),
    Tenant(
      id: 't-2',
      name: 'Bob Martinez',
      unit: 'Unit 204B',
      phone: '+1 555-0202',
      email: 'bob@example.com',
      rentAmount: 2200.0,
      deposit: 2200.0,
      status: 'active',
      joinDate: '$year-02-01',
      leaseStartDate: '$year-02-01',
      leaseEndDate: '$year-11-30',
    ),
    Tenant(
      id: 't-3',
      name: 'Charlie Davis',
      unit: 'Suite 305',
      phone: '+1 555-0303',
      email: 'charlie@example.com',
      rentAmount: 1500.0,
      deposit: 1500.0,
      status: 'left',
      joinDate: '${year - 1}-01-01',
    ),
  ];

  final samplePayments = [
    Payment(
      id: 'p-1',
      tenantId: 't-1',
      amount: 1800.0,
      status: 'paid',
      dueDate: '$monthKey-01',
      paidDate: '$monthKey-03',
      paidForMonth: monthKey,
      displayMonth: monthKey,
    ),
    Payment(
      id: 'p-2',
      tenantId: 't-2',
      amount: 2200.0,
      status: 'pending',
      dueDate: '$monthKey-01',
      paidForMonth: monthKey,
      displayMonth: monthKey,
    ),
  ];

  final sampleExpenses = [
    Expense(
      id: 'e-1',
      category: 'Utilities',
      description: 'Electricity & Water',
      amount: 550.0,
      date: '$monthKey-05',
      expenseForMonth: monthKey,
      status: 'paid',
    ),
    Expense(
      id: 'e-2',
      category: 'Repairs',
      description: 'Plumbing Service',
      amount: 320.0,
      date: '$monthKey-10',
      expenseForMonth: monthKey,
      status: 'paid',
    ),
  ];

  final sampleWorkOrders = [
    WorkOrder(
      id: 'wo-1',
      title: 'Fix kitchen sink leak',
      description: 'Replace seal and trap',
      category: 'Plumbing',
      assignedTo: 'Mario Tech',
      createdAt: '$monthKey-02',
      dueDate: '$monthKey-05',
      status: 'completed',
      tenantId: 't-1',
      workerCost: 150.0,
      productPrice: 40.0,
    ),
  ];

  final sampleZakat = [
    ZakatTransaction(
      id: 'z-1',
      type: 'inflow',
      amount: 500.0,
      date: '$monthKey-01',
      description: 'Monthly Zakat savings',
    ),
  ];

  final samplePropertyManager = PropertyManager(
    id: 'pm-1',
    name: 'Alexander Hamilton',
    propertyName: 'Skyline Luxury Residences',
    address: '742 Evergreen Terrace, Springfield, IL',
    email: 'management@skylineresidences.com',
    phone: '+1 (555) 019-2834',
  );

  final testState = AppDataState(
    tenants: sampleTenants,
    payments: samplePayments,
    expenses: sampleExpenses,
    workOrders: sampleWorkOrders,
    documents: const [],
    zakat: sampleZakat,
    preferences: AppPreferences(),
    selectedYear: year,
    selectedCurrency: '\$',
    propertyManager: samplePropertyManager,
  );

  Widget createTestHost(Widget child, [AppDataState? state]) {
    final container = ProviderContainer(
      overrides: [
        appDataProvider.overrideWith((ref) => _MockAppDataNotifier(state ?? testState)),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: child),
      ),
    );
  }

  final testResolutions = [
    const Size(1440, 900), // Standard MacBook / iMac
    const Size(1280, 800), // Compact MacBook
    const Size(1024, 768), // Half screen / iPad
  ];

  group('Desktop Screen Overflow & Render Stress Tests', () {
    for (final size in testResolutions) {
      testWidgets('DesktopOverviewView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(DesktopOverviewView(
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        )));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('DesktopTenantsView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(DesktopTenantsView(
          onAddTenant: () {},
          onLogPayment: (_) {},
        )));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('DesktopReportsView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(const DesktopReportsView()));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Switch to Annual / YTD period
        final annualBtn = find.text('Annual / YTD');
        if (annualBtn.evaluate().isNotEmpty) {
          await tester.tap(annualBtn);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        // Switch back to Monthly period
        final monthlyBtn = find.text('Monthly');
        if (monthlyBtn.evaluate().isNotEmpty) {
          await tester.tap(monthlyBtn);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('DesktopWorkOrdersView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(DesktopWorkOrdersView(
          onAddOrder: () {},
        )));
        await tester.pump();
      });

      testWidgets('DesktopDocumentsView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(DesktopDocumentsView(
          onAddDocument: () {},
        )));
        await tester.pump();
      });

      testWidgets('DesktopZakatView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(DesktopZakatView(
          onAddInflow: () {},
          onAddOutflow: () {},
        )));
        await tester.pump();
      });

      testWidgets('DesktopSettingsView does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(const DesktopSettingsView()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('DesktopShell does not overflow at ${size.width}x${size.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestHost(const DesktopShell()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('DesktopCashFlowModal does not overflow across all tabs',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestHost(
        DesktopCashFlowModal(initialYear: year, initialMonth: now.month),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tab 1: 12 months horizon
      await tester.tap(find.text('12 Months'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tab 2: Lease Renewal Pipeline
      await tester.tap(find.textContaining('Lease Renewal Pipeline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tab 3: NOI & Solvency Breakdown
      await tester.tap(find.text('NOI & Solvency Breakdown'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DesktopBatchRentModal does not overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestHost(
        DesktopBatchRentModal(initialYear: year, initialMonth: now.month),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DesktopRentReceiptModal does not overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestHost(
        DesktopRentReceiptModal(
          initialPayment: samplePayments.first,
          initialTenant: sampleTenants.first,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}

class _MockAppDataNotifier extends AppDataNotifier {
  _MockAppDataNotifier(AppDataState initialState) {
    state = initialState;
  }
}
