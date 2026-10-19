import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_rent_receipt_modal.dart';
import 'package:rentmanager/services/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_receipt_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  final testTenant = Tenant(
    id: 't-101',
    name: 'Sarah Connor',
    phone: '+1 555-8920',
    email: 'sarah@skynet-resistance.org',
    unit: 'Apt 4B',
    rentAmount: 1850.0,
    deposit: 1850.0,
    status: 'active',
    joinDate: '2026-01-01',
    leaseStartDate: '2026-01-01',
    leaseEndDate: '2026-12-31',
  );

  final testPayment = Payment(
    id: 'p-101',
    tenantId: 't-101',
    amount: 1850.0,
    status: 'paid',
    dueDate: '2026-10-01',
    paidDate: '2026-10-02',
    paidForMonth: '2026-10',
    displayMonth: '2026-10',
    notes: 'Paid via direct ACH',
  );

  final testPropertyManager = PropertyManager(
    id: 'pm-101',
    name: 'Alexander Hamilton',
    propertyName: 'Skyline Luxury Residences',
    address: '742 Evergreen Terrace, Springfield, IL',
    email: 'management@skylineresidences.com',
    phone: '+1 (555) 019-2834',
  );

  final testAppState = AppDataState(
    tenants: [testTenant],
    payments: [testPayment],
    expenses: const [],
    workOrders: const [],
    documents: const [],
    zakat: const [],
    preferences: AppPreferences(),
    selectedYear: 2026,
    selectedCurrency: '\$',
    propertyManager: testPropertyManager,
  );

  group('ReportExportService.generateRentReceiptPdf', () {
    test('generates valid non-empty PDF bytes for receipt type', () async {
      final bytes = await ReportExportService.generateRentReceiptPdf(
        payment: testPayment,
        tenant: testTenant,
        propertyManager: testPropertyManager,
        currency: '\$',
        receiptNumber: 'RCP-202610-101',
        documentType: 'RECEIPT',
        customNotes: 'Thank you for your prompt monthly payment.',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      // PDF documents start with %PDF
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('generates valid non-empty PDF bytes for invoice type', () async {
      final bytes = await ReportExportService.generateRentReceiptPdf(
        payment: testPayment,
        tenant: testTenant,
        propertyManager: testPropertyManager,
        currency: '\$',
        receiptNumber: 'INV-202610-101',
        documentType: 'INVOICE',
        customNotes: 'Invoice due upon receipt.',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });
  });

  group('DesktopRentReceiptModal Widget', () {
    testWidgets('renders controls sidebar, receipt number, and tenant metadata',
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
          child: MaterialApp(
            home: Scaffold(
              body: DesktopRentReceiptModal(
                initialPayment: testPayment,
                initialTenant: testTenant,
              ),
            ),
          ),
        ),
      );

      // Allow async initializations
      await tester.pump();

      // Check header and top bar
      expect(find.text('Branded Rent Receipt & Invoice Generator'), findsOneWidget);
      expect(
        find.text('Official verification document with property branding, breakdown, and signature seals'),
        findsOneWidget,
      );

      // Verify controls
      expect(find.text('DOCUMENT FORMAT'), findsOneWidget);
      expect(find.text('Payment Receipt'), findsOneWidget);
      expect(find.text('Rent Invoice'), findsOneWidget);
      expect(find.text('RECEIPT / INVOICE NUMBER'), findsOneWidget);
      expect(find.text('REMARKS & THANK YOU MESSAGE'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Print Receipt (⌘P)'), findsOneWidget);
      expect(find.text('Save PDF Receipt...'), findsOneWidget);
      expect(find.text('Copy WhatsApp / SMS Text'), findsOneWidget);

      // Toggle to Invoice mode
      await tester.tap(find.text('Rent Invoice'));
      await tester.pump();

      // Check button text updated for invoice
      expect(find.text('Print Invoice (⌘P)'), findsOneWidget);
      expect(find.text('Save PDF Invoice...'), findsOneWidget);
    });
  });
}

class _MockAppDataNotifier extends AppDataNotifier {
  _MockAppDataNotifier(AppDataState initialState) {
    state = initialState;
  }
}
