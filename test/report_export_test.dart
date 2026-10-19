import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/services/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tenant = Tenant(
    id: 't-1',
    name: 'Alice Johnson',
    unit: '101',
    phone: '555-1234',
    email: 'alice@example.com',
    rentAmount: 1200,
    deposit: 1200,
    joinDate: '2026-01-01',
    leaseStartDate: '2026-01-01',
    leaseEndDate: '2026-12-31',
    status: 'active',
  );

  final payment = Payment(
    id: 'p-1',
    tenantId: 't-1',
    amount: 1200,
    paidDate: '2026-10-02',
    paidForMonth: '2026-10',
    displayMonth: '2026-10',
    status: 'paid',
  );

  final expense = Expense(
    id: 'e-1',
    amount: 150,
    category: 'Repairs',
    description: 'Plumbing leak',
    date: '2026-10-05',
    status: 'paid',
    expenseForMonth: '2026-10',
  );

  final workOrder = WorkOrder(
    id: 'w-1',
    title: 'AC Filter Replacement',
    description: 'Replace filters',
    category: 'HVAC',
    priority: 'medium',
    status: 'completed',
    unit: '101',
    assignedTo: 'Bob Worker',
    dueDate: '2026-10-10',
    workerCost: 50,
    productPrice: 30,
    createdAt: '2026-10-01T08:00:00.000Z',
  );

  final appState = AppDataState(
    tenants: [tenant],
    payments: [payment],
    expenses: [expense],
    workOrders: [workOrder],
    documents: const [],
    zakat: const [],
    preferences: AppPreferences(),
    selectedYear: 2026,
    selectedCurrency: '\$',
  );

  group('ReportExportService', () {
    test('prepareData accurately calculates financial summary and filters', () {
      final data = ReportExportService.prepareData(
        state: appState,
        monthKey: '2026-10',
        tenantId: 'all',
      );

      expect(data.monthKey, '2026-10');
      expect(data.monthName, 'October 2026');
      expect(data.rentRows.length, 1);
      expect(data.expenses.length, 1);
      expect(data.workOrders.length, 1);
      expect(data.totalRent, 1200);
      expect(data.totalExpenses, 150);
      expect(data.totalWork, 80);
      expect(data.net, 1200 - 150 - 80); // 970
    });

    test('generateReportCsv generates structured CSV content', () {
      final data = ReportExportService.prepareData(
        state: appState,
        monthKey: '2026-10',
        tenantId: 'all',
      );

      final csv = ReportExportService.generateReportCsv(data);
      expect(csv, contains('Property Management Report'));
      expect(csv, contains('October 2026'));
      expect(csv, contains('Alice Johnson'));
      expect(csv, contains('Plumbing leak'));
      expect(csv, contains('AC Filter Replacement'));
      expect(csv, contains('970.00'));
    });

    test('generateReportPdf generates valid PDF bytes', () async {
      final data = ReportExportService.prepareData(
        state: appState,
        monthKey: '2026-10',
        tenantId: 'all',
      );

      final pdfBytes = await ReportExportService.generateReportPdf(data);
      expect(pdfBytes, isNotEmpty);
      // Valid PDF magic header bytes: %PDF-
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), '%PDF');
    });

    test('generateTenantStatementPdf and Csv generate valid outputs', () async {
      final propManager = PropertyManager(
        id: 'pm-1',
        name: 'Towfike elahi',
        address: 'UPOSHOR BLOCK-D',
        phone: '01737235248',
        email: 'imnazelahi@gmail.com',
        propertyName: 'AMIN MANZIL',
        ownerName: 'Hazi Shunahor Ali',
      );

      final csv = ReportExportService.generateTenantStatementCsv(
        tenant: tenant,
        history: [payment],
        currency: '৳',
        propertyManager: propManager,
      );
      expect(csv, contains('Tenant Rent History Statement'));
      expect(csv, contains('AMIN MANZIL'));
      expect(csv, contains('UPOSHOR BLOCK-D'));
      expect(csv, contains('Hazi Shunahor Ali'));
      expect(csv, contains('Towfike elahi'));
      expect(csv, contains('Alice Johnson'));
      expect(csv, contains('1200.00'));

      final pdfBytes = await ReportExportService.generateTenantStatementPdf(
        tenant: tenant,
        history: [payment],
        currency: '৳',
        propertyManager: propManager,
      );
      expect(pdfBytes, isNotEmpty);
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), '%PDF');
    });

    test('prepareData forwards propertyManager to ReportExportData', () {
      final propManager = PropertyManager(
        id: 'pm-1',
        name: 'Towfike elahi',
        address: 'UPOSHOR BLOCK-D',
        phone: '01737235248',
        email: 'imnazelahi@gmail.com',
        propertyName: 'AMIN MANZIL',
        ownerName: 'Hazi Shunahor Ali',
      );

      final stateWithProp = appState.copyWith(propertyManager: propManager);
      final data = ReportExportService.prepareData(
        state: stateWithProp,
        monthKey: '2026-10',
        tenantId: 'all',
      );

      expect(data.propertyManager?.propertyName, 'AMIN MANZIL');
      expect(data.propertyManager?.address, 'UPOSHOR BLOCK-D');
      expect(data.propertyManager?.ownerName, 'Hazi Shunahor Ali');

      final csv = ReportExportService.generateReportCsv(data);
      expect(csv, contains('Property: AMIN MANZIL'));
      expect(csv, contains('Address: UPOSHOR BLOCK-D'));
      expect(csv, contains('Owner: Hazi Shunahor Ali'));
    });
  });
}
