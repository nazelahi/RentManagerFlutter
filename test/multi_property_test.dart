import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/services/data_merge_service.dart';
import 'package:rentmanager/features/desktop/desktop_property_modal.dart';
import 'package:rentmanager/features/desktop/desktop_property_switcher.dart';
import 'package:rentmanager/features/desktop/desktop_overview_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rent_manager_test_');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    if (tempDir != null && await tempDir!.exists()) {
      await tempDir!.delete(recursive: true);
    }
  });

  final baseState = AppDataState(
    selectedYear: 2024,
    preferences: AppPreferences(),
    tenants: const [],
    payments: const [],
    expenses: const [],
    workOrders: const [],
    documents: const [],
  );

  group('Multi-Property Management Core Tests', () {
    test('Property entity JSON serialization & deserialization round-trip', () {
      final now = DateTime.now();
      final prop = Property(
        id: 'prop-123',
        name: 'Ocean Breeze Residencies',
        address: '101 Ocean Ave, Santa Monica, CA',
        propertyType: 'residential',
        totalUnits: 16,
        notes: 'Gated parking, rooftop pool',
        createdAt: now,
      );

      final json = prop.toJson();
      expect(json['id'], 'prop-123');
      expect(json['name'], 'Ocean Breeze Residencies');
      expect(json['totalUnits'], 16);

      final restored = Property.fromJson(json);
      expect(restored.id, prop.id);
      expect(restored.name, prop.name);
      expect(restored.address, prop.address);
      expect(restored.propertyType, prop.propertyType);
      expect(restored.totalUnits, prop.totalUnits);
      expect(restored.notes, prop.notes);
    });

    test('Models default to prop-default for backward compatibility', () {
      final tenant = Tenant(
        id: 't-1',
        name: 'Alice Smith',
        unit: '101',
        phone: '555-0101',
        email: 'alice@example.com',
        rentAmount: 1200,
        status: 'active',
        joinDate: '2024-01-01',
      );
      expect(tenant.propertyId, 'prop-default');

      final payment = Payment(
        id: 'p-1',
        tenantId: 't-1',
        amount: 1200,
        status: 'paid',
      );
      expect(payment.propertyId, 'prop-default');

      final expense = Expense(
        id: 'e-1',
        category: 'Maintenance',
        description: 'Repaired lock',
        amount: 250,
        date: '2024-01-15',
        status: 'paid',
      );
      expect(expense.propertyId, 'prop-default');

      final workOrder = WorkOrder(
        id: 'wo-1',
        title: 'Fix leak',
        description: 'Faucet leaking',
        category: 'Plumbing',
        priority: 'high',
        status: 'pending',
        assignedTo: 'Bob Plumber',
        createdAt: '2024-01-15',
        dueDate: '2024-01-20',
      );
      expect(workOrder.propertyId, 'prop-default');

      final doc = RentDoc(
        id: 'd-1',
        title: 'Insurance Policy',
        type: 'Insurance',
        fileName: 'insurance.pdf',
        fileSize: '1.2 MB',
        uploadedBy: 'Manager',
        uploadedDate: '2024-01-15',
      );
      expect(doc.propertyId, 'prop-default');
    });

    test('AppDataState correctly scopes tenants, payments, expenses, etc.', () {
      final propA = Property(
        id: 'prop-A',
        name: 'Building Alpha',
        address: '100 Alpha St',
        totalUnits: 10,
        createdAt: DateTime.now(),
      );
      final propB = Property(
        id: 'prop-B',
        name: 'Building Beta',
        address: '200 Beta Ave',
        totalUnits: 8,
        createdAt: DateTime.now(),
      );

      final tenantA = Tenant(
        id: 't-A',
        name: 'Tenant Alpha',
        unit: 'A1',
        phone: '111',
        email: 'a@test.com',
        rentAmount: 1000,
        status: 'active',
        joinDate: '2024-01-01',
        propertyId: 'prop-A',
      );
      final tenantB = Tenant(
        id: 't-B',
        name: 'Tenant Beta',
        unit: 'B1',
        phone: '222',
        email: 'b@test.com',
        rentAmount: 1500,
        status: 'active',
        joinDate: '2024-01-01',
        propertyId: 'prop-B',
      );

      final paymentA = Payment(
        id: 'pay-A',
        tenantId: 't-A',
        amount: 1000,
        status: 'paid',
        propertyId: 'prop-A',
      );
      final paymentB = Payment(
        id: 'pay-B',
        tenantId: 't-B',
        amount: 1500,
        status: 'paid',
        propertyId: 'prop-B',
      );

      // 1. Scoped to Building Alpha
      final stateA = baseState.copyWith(
        properties: [propA, propB],
        selectedPropertyId: 'prop-A',
        tenants: [tenantA, tenantB],
        payments: [paymentA, paymentB],
      );
      expect(stateA.isAllProperties, isFalse);
      expect(stateA.activeProperty?.name, 'Building Alpha');
      expect(stateA.scopedTenants.map((t) => t.id), ['t-A']);
      expect(stateA.scopedPayments.map((p) => p.id), ['pay-A']);

      // 2. Scoped to Building Beta
      final stateB = stateA.copyWith(selectedPropertyId: 'prop-B');
      expect(stateB.isAllProperties, isFalse);
      expect(stateB.activeProperty?.name, 'Building Beta');
      expect(stateB.scopedTenants.map((t) => t.id), ['t-B']);
      expect(stateB.scopedPayments.map((p) => p.id), ['pay-B']);
    });

    test('DataMergeService.merge reconciles multi-property data with Google Drive', () {
      final localProp = Property(
        id: 'prop-local-1',
        name: 'Local Sunset Villa',
        address: '12 Sunset Blvd',
        totalUnits: 4,
        createdAt: DateTime(2026, 1, 1),
      );
      final remoteProp = Property(
        id: 'prop-remote-1',
        name: 'Remote Mountain Lodge',
        address: '99 Alpine Way',
        totalUnits: 6,
        createdAt: DateTime(2026, 2, 1),
      );

      final localData = {
        StorageKeys.properties: [localProp.toJson()],
        StorageKeys.selectedPropertyId: 'prop-local-1',
      };
      final remoteData = {
        StorageKeys.properties: [remoteProp.toJson()],
        StorageKeys.selectedPropertyId: 'all',
      };

      final result = DataMergeService.merge(
        local: localData,
        remote: remoteData,
      );

      final mergedProperties = (result.mergedData[StorageKeys.properties] as List)
          .map((m) => Property.fromJson(m as Map<String, dynamic>))
          .toList();

      expect(mergedProperties.length, 2);
      expect(mergedProperties.map((p) => p.id), containsAll(['prop-local-1', 'prop-remote-1']));
      expect(result.mergedData[StorageKeys.selectedPropertyId], 'prop-local-1');
    });
  });

  group('Multi-Property Desktop Widgets Tests', () {
    testWidgets('DesktopPropertySwitcher renders and displays active property',
        (tester) async {
      final prop = Property(
        id: 'prop-1',
        name: 'Grand Horizon Towers',
        address: '500 Skyline Blvd',
        propertyType: 'commercial',
        totalUnits: 24,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockAppDataNotifier(
                  baseState.copyWith(
                    properties: [prop],
                    selectedPropertyId: 'prop-1',
                    tenants: [
                      Tenant(
                        id: 't-1',
                        name: 'Tech Corp',
                        unit: 'Suite 400',
                        phone: '123',
                        email: 'info@techcorp.com',
                        rentAmount: 5000,
                        status: 'active',
                        joinDate: '2024-01-01',
                        propertyId: 'prop-1',
                      ),
                    ],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: DesktopPropertySwitcher(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check displayed text
      expect(find.text('Grand Horizon Towers'), findsOneWidget);
      expect(find.text('24 units'), findsOneWidget);

      // Tap switcher to open popup menu
      await tester.tap(find.byType(DesktopPropertySwitcher));
      await tester.pumpAndSettle();

      // Menu should show "PROPERTIES", the property item, and "Add New Property..."
      expect(find.text('PROPERTIES'), findsOneWidget);
      expect(find.text('Grand Horizon Towers'), findsWidgets);
      expect(find.text('Add New Property...'), findsOneWidget);
    });

    testWidgets('DesktopPropertyModal opens and allows creating a new property',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockAppDataNotifier(baseState)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => DesktopPropertyModal.show(ctx),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify modal elements
      expect(find.text('Add New Property'), findsOneWidget);
      expect(find.text('Property Name'), findsOneWidget);
      expect(find.text('Property Classification'), findsOneWidget);
      expect(find.text('Residential'), findsOneWidget);
      expect(find.text('Commercial'), findsOneWidget);
      expect(find.text('Street Address'), findsOneWidget);
      expect(find.text('Total Units'), findsOneWidget);
      expect(find.text('Create Property'), findsOneWidget);
    });

    testWidgets(
        'DesktopOverviewView sync from previous month isolates properties and shows property selector',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final year = now.year;
      final currentMonth = now.month;
      final prevMonth = currentMonth == 1 ? 12 : currentMonth - 1;
      final prevYear = currentMonth == 1 ? year - 1 : year;
      final prevMonthKey = '$prevYear-${prevMonth.toString().padLeft(2, '0')}';

      final propA = Property(
          id: 'prop-A',
          name: 'Alpha Tower',
          address: '123 Alpha St',
          totalUnits: 10,
          createdAt: DateTime.now());
      final propB = Property(
          id: 'prop-B',
          name: 'Beta Plaza',
          address: '456 Beta Ave',
          totalUnits: 12,
          createdAt: DateTime.now());

      final multiState = baseState.copyWith(
        properties: [propA, propB],
        selectedPropertyId: 'prop-B',
        selectedYear: year,
        tenants: [
          Tenant(
              id: 't-A',
              name: 'Alpha Tenant',
              unit: 'A-101',
              phone: '555-0001',
              email: 'alpha@example.com',
              joinDate: '2024-01-01',
              rentAmount: 1000,
              status: 'active',
              propertyId: 'prop-A'),
          Tenant(
              id: 't-B',
              name: 'Beta Tenant',
              unit: 'B-201',
              phone: '555-0002',
              email: 'beta@example.com',
              joinDate: '2024-01-01',
              rentAmount: 1500,
              status: 'active',
              propertyId: 'prop-B'),
        ],
        payments: [
          Payment(
              id: 'p-A',
              tenantId: 't-A',
              amount: 1000,
              status: 'paid',
              paidDate: '$prevMonthKey-01',
              paidForMonth: prevMonthKey,
              propertyId: 'prop-A'),
          Payment(
              id: 'p-B',
              tenantId: 't-B',
              amount: 1500,
              status: 'paid',
              paidDate: '$prevMonthKey-01',
              paidForMonth: prevMonthKey,
              propertyId: 'prop-B'),
        ],
        expenses: [
          Expense(
              id: 'e-A',
              category: 'Maintenance',
              description: 'Alpha elevator repair',
              amount: 500,
              date: '$prevMonthKey-05',
              expenseForMonth: prevMonthKey,
              propertyId: 'prop-A'),
          Expense(
              id: 'e-B',
              category: 'Utilities',
              description: 'Beta water bill',
              amount: 200,
              date: '$prevMonthKey-05',
              expenseForMonth: prevMonthKey,
              propertyId: 'prop-B'),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockAppDataNotifier(multiState)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopOverviewView(
                onSelectTenant: (_) {},
                onAddTenant: () {},
                onLogPayment: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap sync
      await tester.tap(find.text('Sync').first);
      await tester.pumpAndSettle();

      // Verify dialog opened with property selectors
      expect(find.text('Sync Previous Month Roll'), findsOneWidget);
      expect(find.text('SOURCE PROPERTY'), findsOneWidget);
      expect(find.text('TARGET PROPERTY'), findsOneWidget);

      // Verify that Beta Plaza is target property and only Beta items are in preview
      expect(find.text('Beta Tenant'), findsOneWidget);
      expect(find.text('Beta water bill'), findsOneWidget);
      expect(find.text('Alpha Tenant'), findsNothing);
      expect(find.text('Alpha elevator repair'), findsNothing);
    });
  });
}

class _MockAppDataNotifier extends AppDataNotifier {
  _MockAppDataNotifier(AppDataState initialState) {
    state = initialState;
  }

  @override
  void addProperty(Property property) {
    state = state.copyWith(
      properties: [...state.properties, property],
      selectedPropertyId: property.id,
    );
  }

  @override
  void selectProperty(String propertyId) {
    state = state.copyWith(selectedPropertyId: propertyId);
  }
}
