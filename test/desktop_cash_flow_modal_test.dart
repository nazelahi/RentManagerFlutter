import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_cash_flow_modal.dart';
import 'package:rentmanager/services/financial_analytics_service.dart';
import 'package:rentmanager/services/forecast_pdf_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_cash_flow_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  final activeTenant1 = Tenant(
    id: 't-1',
    name: 'Sarah Connor',
    email: 'sarah@resistance.org',
    phone: '+1 555-8920',
    unit: 'Unit 101',
    rentAmount: 2000.0,
    deposit: 2000.0,
    status: 'active',
    joinDate: '2026-01-01',
    leaseStartDate: '2026-01-01',
    leaseEndDate: '2026-11-30', // Expiring in Nov 2026
  );

  final activeTenant2 = Tenant(
    id: 't-2',
    name: 'John Matrix',
    email: 'john@commando.mil',
    phone: '+1 555-4321',
    unit: 'Unit 102',
    rentAmount: 3000.0,
    deposit: 3000.0,
    status: 'active',
    joinDate: '2026-02-01',
    leaseStartDate: '2026-02-01',
    leaseEndDate: '2027-01-31', // Expiring in Jan 2027
  );

  final pastTenant = Tenant(
    id: 't-3',
    name: 'Kyle Reese',
    email: 'kyle@future.net',
    phone: '+1 555-1111',
    unit: 'Unit 103',
    rentAmount: 1500.0,
    status: 'left',
    joinDate: '2025-01-01',
  );

  final payment1 = Payment(
    id: 'p-1',
    tenantId: 't-1',
    amount: 2000.0,
    status: 'paid',
    dueDate: '2026-10-01',
    paidDate: '2026-10-03',
    paidForMonth: '2026-10',
    displayMonth: '2026-10',
  );

  final payment2Pending = Payment(
    id: 'p-2',
    tenantId: 't-2',
    amount: 3000.0,
    status: 'pending',
    dueDate: '2026-10-01',
    paidForMonth: '2026-10',
    displayMonth: '2026-10',
  );

  final expense1 = Expense(
    id: 'e-1',
    category: 'Utilities',
    description: 'Water & Electricity bill',
    amount: 600.0,
    status: 'paid',
    date: '2026-10-05',
    expenseForMonth: '2026-10',
  );

  final expense2 = Expense(
    id: 'e-2',
    category: 'Insurance',
    description: 'Property Liability Insurance',
    amount: 400.0,
    status: 'paid',
    date: '2026-10-10',
    expenseForMonth: '2026-10',
  );

  final workOrder1 = WorkOrder(
    id: 'wo-1',
    title: 'HVAC repair',
    description: 'Compressor check and coolant reload',
    category: 'HVAC',
    status: 'completed',
    assignedTo: 'Dave Tech',
    createdAt: '2026-10-15',
    completedAt: '2026-10-16',
    dueDate: '2026-10-20',
    tenantId: 't-1',
    workerCost: 200.0,
    productPrice: 50.0,
  );

  final testAppState = AppDataState(
    tenants: [activeTenant1, activeTenant2, pastTenant],
    payments: [payment1, payment2Pending],
    expenses: [expense1, expense2],
    workOrders: [workOrder1],
    documents: const [],
    zakat: const [],
    preferences: AppPreferences(),
    selectedYear: 2026,
    selectedCurrency: '\$',
  );

  group('FinancialAnalyticsService.computeMetrics', () {
    test('computes accurate NOI, OER, Occupancy and Collection rates', () {
      final metrics = FinancialAnalyticsService.computeMetrics(
        state: testAppState,
        year: 2026,
        month: 10,
      );

      // Revenue: payment1 paid = 2000.0
      expect(metrics.grossRevenue, equals(2000.0));
      // Expenses: 600 + 400 + (200 + 50) = 1250.0
      expect(metrics.totalOperatingExpenses, equals(1250.0));
      // NOI: 2000 - 1250 = 750.0
      expect(metrics.netOperatingIncome, equals(750.0));
      // OER: (1250 / 2000) * 100 = 62.5%
      expect(metrics.operatingExpenseRatio, closeTo(62.5, 0.01));

      // Total units: 3 tenants = 3 units. Active = 2.
      expect(metrics.totalUnits, equals(3));
      expect(metrics.occupiedUnits, equals(2));
      expect(metrics.vacantUnits, equals(1));
      // Occupancy rate: 2/3 * 100 = 66.67%
      expect(metrics.occupancyRate, closeTo(66.67, 0.1));

      // Scheduled rent: active tenants 2000 + 3000 = 5000.0
      expect(metrics.scheduledRent, equals(5000.0));
      // Collection rate: 2000 / 5000 = 40.0%
      expect(metrics.collectionEfficiency, equals(40.0));
      // Pending rent: payment2 pending = 3000.0
      expect(metrics.pendingRent, equals(3000.0));
    });
  });

  group('FinancialAnalyticsService.computeCashFlowForecast', () {
    test('projects 6-month cash flow with lease expirations', () {
      final forecast6 = FinancialAnalyticsService.computeCashFlowForecast(
        state: testAppState,
        monthsAhead: 6,
      );

      expect(forecast6.projections.length, equals(6));
      expect(forecast6.totalProjectedInflow, greaterThan(0));
      expect(forecast6.totalProjectedOutflow, greaterThan(0));

      // Lease expiry check
      expect(forecast6.upcomingExpirations, isNotEmpty);
      final expiringNov = forecast6.upcomingExpirations.any((e) => e.tenant.id == 't-1');
      expect(expiringNov, isTrue);
    });

    test('projects 12-month horizon correctly', () {
      final forecast12 = FinancialAnalyticsService.computeCashFlowForecast(
        state: testAppState,
        monthsAhead: 12,
      );

      expect(forecast12.projections.length, equals(12));
      expect(forecast12.averageMonthlyInflow, equals(
        forecast12.totalProjectedInflow / 12,
      ));
    });
  });

  group('DesktopCashFlowModal Widget', () {
    testWidgets('renders KPI ribbon, 6M/12M toggle, and switches tabs',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) => _MockAppDataNotifier(testAppState)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopCashFlowModal(
                initialYear: 2026,
                initialMonth: 10,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Check Header
      expect(find.text('Executive Financial Health & Cash Flow Forecast'), findsOneWidget);

      // Check Top Metrics Ribbon
      expect(find.text('Net Operating Income (NOI)'), findsOneWidget);
      expect(find.text('Operating Expense Ratio (OER)'), findsOneWidget);
      expect(find.text('Collection Efficiency'), findsOneWidget);
      expect(find.text('Occupancy & Vacancy'), findsOneWidget);

      // Check Tabs
      expect(find.text('Predictive Cash Flow'), findsOneWidget);
      expect(find.textContaining('Lease Renewal Pipeline'), findsOneWidget);
      expect(find.text('NOI & Solvency Breakdown'), findsOneWidget);

      // Check Export to PDF and Print buttons in footer
      expect(find.text('Export to PDF'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Copy Summary'), findsOneWidget);

      // Check Horizon Switcher
      expect(find.text('6 Months'), findsOneWidget);
      expect(find.text('12 Months'), findsOneWidget);

      // Toggle to 12 Months
      await tester.tap(find.text('12 Months'));
      await tester.pump();

      // Switch to "Lease Renewal Pipeline" tab
      await tester.tap(find.textContaining('Lease Renewal Pipeline'));
      await tester.pump();

      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.textContaining('Unit 101'), findsOneWidget);

      // Switch to "NOI & Solvency Breakdown" tab
      await tester.tap(find.text('NOI & Solvency Breakdown'));
      await tester.pump();

      expect(find.text('REVENUE & RENT ROLL WATERFALL'), findsOneWidget);
      expect(find.text('NET OPERATING INCOME (NOI) FORMULA'), findsOneWidget);
      expect(find.textContaining('Industry Benchmark'), findsOneWidget);
    });
  });

  group('ForecastPdfExportService', () {
    test('generateForecastPdf generates non-empty high-fidelity PDF bytes', () async {
      final metrics = FinancialAnalyticsService.computeMetrics(
        state: testAppState,
        year: 2026,
        month: 10,
      );

      final forecast = FinancialAnalyticsService.computeCashFlowForecast(
        state: testAppState,
        monthsAhead: 6,
        startYear: 2026,
        startMonth: 10,
      );

      final pdfBytes = await ForecastPdfExportService.generateForecastPdf(
        state: testAppState,
        metrics: metrics,
        forecast: forecast,
        year: 2026,
        month: 10,
        forecastHorizon: 6,
        propertyName: 'Test Property Heights',
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
      // Standard PDF header signature check: %PDF-
      expect(String.fromCharCodes(pdfBytes.take(5)), equals('%PDF-'));
    });
  });
}

class _MockAppDataNotifier extends AppDataNotifier {
  _MockAppDataNotifier(AppDataState initialState) {
    state = initialState;
  }
}
