import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_overview_view.dart';
import 'package:rentmanager/features/desktop/desktop_shell.dart';
import 'package:rentmanager/features/overview/overview_view.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'rentmanager_overview_test',
    );
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });
  testWidgets(
    'DesktopOverviewView renders 5 KPI cards including Total Expenses and Expenses Summary Status',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final year = now.year;
      final monthStr = now.month.toString().padLeft(2, '0');
      final monthKey = '$year-$monthStr';

      final testState = AppDataState(
        preferences: AppPreferences(),
        selectedYear: year,
        selectedCurrency: '\$',
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            rentAmount: 1200,
            phone: '1234567890',
            email: 'alice@example.com',
            status: 'active',
            joinDate: '$year-01-01',
          ),
        ],
        payments: [
          Payment(
            id: 'p1',
            tenantId: 't1',
            amount: 1200,
            paidDate: '$monthKey-05',
            paidForMonth: monthKey,
            status: 'paid',
          ),
        ],
        expenses: [
          Expense(
            id: 'e1',
            category: 'Repairs',
            description: 'Plumbing leak',
            amount: 250,
            date: '$monthKey-10',
            status: 'paid',
            expenseForMonth: monthKey,
          ),
          Expense(
            id: 'e2',
            category: 'Utilities',
            description: 'Water bill',
            amount: 100,
            date: '$monthKey-12',
            status: 'pending',
            expenseForMonth: monthKey,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
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

      // Verify 5 KPI cards
      expect(find.text('Collected Rent'), findsOneWidget);
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.text('Net Cash Flow'), findsOneWidget);
      expect(find.text('Pending & Overdue'), findsOneWidget);
      expect(find.text('Occupancy Rate'), findsOneWidget);

      // Verify Rent Collection Status & Expenses Summary Status cards
      expect(find.text('Rent Collection Status'), findsOneWidget);
      expect(find.text('Expenses Summary Status'), findsOneWidget);
      expect(find.text('Quick Management'), findsNothing);

      // Verify Expenses has STATUS column & badges
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Rent Roll'), findsOneWidget);
      expect(
        find.text('STATUS'),
        findsNWidgets(2),
      ); // in Rent Roll and Expense Roll
      expect(find.text('PAID'), findsWidgets);
      expect(find.text('PENDING'), findsWidgets);
    },
  );

  testWidgets('Mobile OverviewView renders _expenseSummary in expense tab', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final now = DateTime.now();
    final year = now.year;
    final monthStr = now.month.toString().padLeft(2, '0');
    final monthKey = '$year-$monthStr';

    final testState = AppDataState(
      preferences: AppPreferences(),
      selectedYear: year,
      selectedCurrency: '\$',
      expenses: [
        Expense(
          id: 'e1',
          category: 'Repairs',
          description: 'Plumbing leak',
          amount: 250,
          date: '$monthKey-10',
          status: 'paid',
          expenseForMonth: monthKey,
        ),
        Expense(
          id: 'e2',
          category: 'Utilities',
          description: 'Electricity',
          amount: 150,
          date: '$monthKey-15',
          status: 'pending',
          expenseForMonth: monthKey,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
        ],
        child: MaterialApp(home: OverviewView(onSettings: () {})),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Expenses tab
    final expensesTabFinder = find.text('Expenses');
    expect(expensesTabFinder, findsWidgets);
    await tester.tap(expensesTabFinder.last);
    await tester.pumpAndSettle();

    // Verify _expenseSummary displays Total, Paid, Pending
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Plumbing leak'), findsOneWidget);
    expect(find.text('Electricity'), findsOneWidget);
  });

  testWidgets(
    'DesktopShell renders bottom status bar with storage, sync, metrics, and version',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testState = AppDataState(
        preferences: AppPreferences(driveAutoSync: true),
        selectedYear: 2026,
        selectedCurrency: '\$',
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            phone: '1234567890',
            email: 'alice@example.com',
            rentAmount: 1200,
            status: 'active',
            joinDate: '2026-01-01',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: const DesktopShell(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Local Storage'), findsOneWidget);
      expect(find.text('Drive Sync'), findsOneWidget);
      expect(find.textContaining('Tenants'), findsWidgets);
      expect(find.text('1 Units'), findsOneWidget);
      expect(find.text('v1.0.6'), findsOneWidget);
      expect(find.text('⌘K'), findsWidgets);

      // Tapping Drive Sync opens Desktop Google Drive dialog
      await tester.tap(find.text('Drive Sync'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Google Drive Cloud Backup'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      await tester.tap(find.byIcon(Ionicons.close));
      await tester.pump(const Duration(milliseconds: 300));

      // Tapping v1.0.6 opens About RentManager Pro dialog with app details
      await tester.tap(find.text('v1.0.6'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('RentManager Pro'), findsOneWidget);
      expect(find.text('Database Engine'), findsOneWidget);
      expect(find.text('Offline-First SQLite'), findsOneWidget);
      expect(find.text('Check Updates'), findsOneWidget);
      await tester.tap(find.text('Check Updates'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Update source not configured'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Property Information card in sidebar bottom
      expect(find.text('My Property'), findsOneWidget);
      expect(find.text('1 Active • 1 Units'), findsOneWidget);

      // Tapping property card opens Property Information dialog
      await tester.tap(find.text('My Property'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Property Information'), findsOneWidget);
      expect(find.text('Edit Details'), findsOneWidget);
    },
  );

  testWidgets(
    'DesktopOverviewView renders Sync buttons and executes preview & sync flow',
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

      final testState = AppDataState(
        preferences: AppPreferences(),
        selectedYear: year,
        selectedCurrency: '\$',
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            rentAmount: 1200,
            phone: '1234567890',
            email: 'alice@example.com',
            status: 'active',
            joinDate: '$prevYear-01-01',
          ),
        ],
        payments: [
          Payment(
            id: 'p_prev',
            tenantId: 't1',
            amount: 1200,
            paidDate: '$prevMonthKey-05',
            paidForMonth: prevMonthKey,
            status: 'paid',
          ),
        ],
        expenses: [
          Expense(
            id: 'e_prev',
            category: 'Utilities',
            description: 'Electric bill',
            amount: 150,
            date: '$prevMonthKey-10',
            status: 'paid',
            expenseForMonth: prevMonthKey,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
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

      // Verify sync buttons rendered
      expect(find.text('Sync'), findsWidgets);
      expect(find.text('Sync Roll'), findsWidgets);
      expect(find.text('Sync Expenses'), findsWidgets);

      // Tap top "Sync" button
      await tester.tap(find.text('Sync').first);
      await tester.pumpAndSettle();

      // Verify dialog opened
      expect(find.text('Sync Previous Month Roll'), findsOneWidget);
      expect(find.text('All Entries'), findsOneWidget);
      expect(find.text('Rent Roll Only'), findsOneWidget);
      expect(find.text('Expenses Only'), findsOneWidget);
      expect(find.text('2 Ready to Sync'), findsOneWidget);
      expect(find.text('Confirm Sync (2)'), findsOneWidget);

      // Click Confirm Sync
      await tester.tap(find.text('Confirm Sync (2)'));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Sync Previous Month Roll'), findsNothing);
    },
  );

  testWidgets(
    'DesktopOverviewView deduplicates source records and prevents duplicate entries during sync',
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
      final currentMonthKey =
          '$year-${currentMonth.toString().padLeft(2, '0')}';

      final testState = AppDataState(
        preferences: AppPreferences(),
        selectedYear: year,
        selectedCurrency: '\$',
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            rentAmount: 1200,
            phone: '1234567890',
            email: 'alice@example.com',
            status: 'active',
            joinDate: '$prevYear-01-01',
          ),
          Tenant(
            id: 't2',
            name: 'Bob Smith',
            unit: '102',
            rentAmount: 1500,
            phone: '9876543210',
            email: 'bob@example.com',
            status: 'active',
            joinDate: '$prevYear-01-01',
          ),
        ],
        payments: [
          // Source month has 2 payments for Alice (installments: 600 + 600)
          Payment(
            id: 'p_prev_1',
            tenantId: 't1',
            amount: 600,
            paidDate: '$prevMonthKey-05',
            paidForMonth: prevMonthKey,
            status: 'paid',
          ),
          Payment(
            id: 'p_prev_2',
            tenantId: 't1',
            amount: 600,
            paidDate: '$prevMonthKey-15',
            paidForMonth: prevMonthKey,
            status: 'paid',
          ),
          // Source month has 1 payment for Bob
          Payment(
            id: 'p_prev_bob',
            tenantId: 't2',
            amount: 1500,
            paidDate: '$prevMonthKey-05',
            paidForMonth: prevMonthKey,
            status: 'paid',
          ),
          // Target month ALREADY has a payment for Bob (e.g. paid early with paidDate)
          Payment(
            id: 'p_target_bob',
            tenantId: 't2',
            amount: 1500,
            paidDate: '$currentMonthKey-01',
            status: 'paid',
          ),
        ],
        expenses: [
          // Source month has 2 identical utility bills
          Expense(
            id: 'e_prev_1',
            category: 'Utilities',
            description: 'Electric bill',
            amount: 150,
            date: '$prevMonthKey-10',
            status: 'paid',
            expenseForMonth: prevMonthKey,
          ),
          Expense(
            id: 'e_prev_2',
            category: 'Utilities',
            description: 'Electric bill',
            amount: 150,
            date: '$prevMonthKey-10',
            status: 'paid',
            expenseForMonth: prevMonthKey,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
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

      // Open sync dialog
      await tester.tap(find.text('Sync').first);
      await tester.pumpAndSettle();

      // Alice has 2 source payments -> deduplicated to 1.
      // Bob is already in target month -> skipped as duplicate.
      // Expenses have 2 identical bills -> deduplicated to 1.
      // Total ready to sync should be exactly 2 (Alice rent + 1 Electric bill).
      expect(find.text('2 Ready to Sync'), findsOneWidget);
      expect(find.text('1 Duplicates (Skipped)'), findsOneWidget);
      expect(find.text('Confirm Sync (2)'), findsOneWidget);
    },
  );

  testWidgets(
    'DesktopShell renders macOS Sequoia translucent sidebar with collapsible rail and dynamic badges',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testState = AppDataState(
        preferences: AppPreferences(),
        selectedYear: 2026,
        selectedCurrency: '\$',
        propertyManager: PropertyManager(
          id: 'pm-1',
          name: 'Alex Johnson',
          propertyName: 'Skyline Heights',
          address: '123 Main St',
          phone: '555-0100',
          email: 'alex@example.com',
        ),
        tenants: [
          Tenant(
            id: 't-1',
            name: 'Jane Doe',
            unit: '101',
            phone: '555-0101',
            email: 'jane@example.com',
            rentAmount: 1200,
            status: 'active',
            joinDate: '2026-01-01',
          ),
          Tenant(
            id: 't-2',
            name: 'John Smith',
            unit: '102',
            phone: '555-0102',
            email: 'john@example.com',
            rentAmount: 1400,
            status: 'active',
            joinDate: '2026-01-01',
          ),
        ],
        workOrders: [
          WorkOrder(
            id: 'wo-1',
            title: 'Leaking Faucet',
            description: 'Sink leaking in bathroom',
            category: 'Plumbing',
            unit: '101',
            priority: 'high',
            status: 'open',
            assignedTo: 'Plumber Bob',
            createdAt: DateTime.now().toIso8601String(),
            dueDate: DateTime.now()
                .add(const Duration(days: 2))
                .toIso8601String(),
          ),
        ],
        documents: [
          RentDoc(
            id: 'doc-1',
            title: 'Lease Agreement 101',
            type: 'Lease',
            fileName: 'Lease Agreement 101.pdf',
            fileSize: '1.2 MB',
            uploadedBy: 'Alex',
            uploadedDate: DateTime.now().toIso8601String(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
          ],
          child: const MaterialApp(home: DesktopShell()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify macOS Sequoia sidebar elements in expanded mode
      expect(find.text('RentManager'), findsWidgets);
      expect(find.text('Property Management'), findsWidgets);
      expect(find.text('MAIN MENU'), findsOneWidget);
      expect(find.text('Skyline Heights'), findsOneWidget);
      expect(find.text('2 Active • 2 Units'), findsOneWidget);

      // Verify dynamic badges
      expect(find.text('2'), findsWidgets); // 2 active tenants badge
      expect(find.text('1'), findsWidgets); // 1 open work order & 1 doc

      // Verify collapse button exists and tap it
      final collapseBtn = find.byTooltip('Collapse Sidebar (⌘B)');
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sidebar collapsed into rail mode (MAIN MENU text hidden)
      expect(find.text('MAIN MENU'), findsNothing);
      expect(find.text('Property Management'), findsNothing);

      // Verify expand button exists and tap it
      final expandBtn = find.byTooltip('Expand Sidebar (⌘B)');
      expect(expandBtn, findsOneWidget);
      await tester.tap(expandBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sidebar expanded back
      expect(find.text('MAIN MENU'), findsOneWidget);
      expect(find.text('Property Management'), findsWidgets);
    },
  );

  testWidgets(
    'DesktopOverviewView triggers onPaymentDetails and onExpenseDetails on item tap',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final now = DateTime.now();
      final year = now.year;
      final monthStr = now.month.toString().padLeft(2, '0');
      final monthKey = '$year-$monthStr';

      final testState = AppDataState(
        preferences: AppPreferences(),
        selectedYear: year,
        selectedCurrency: '\$',
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            rentAmount: 1200,
            phone: '1234567890',
            email: 'alice@example.com',
            status: 'active',
            joinDate: '$year-01-01',
          ),
        ],
        payments: [
          Payment(
            id: 'p1',
            tenantId: 't1',
            amount: 1200,
            paidDate: '$monthKey-05',
            paidForMonth: monthKey,
            status: 'paid',
          ),
        ],
        expenses: [
          Expense(
            id: 'e1',
            description: 'Elevator Maintenance',
            amount: 450,
            date: '$monthKey-08',
            category: 'Maintenance',
            status: 'paid',
          ),
        ],
        bankDeposits: [
          BankDeposit(
            id: 'd1',
            bankId: 'b1',
            bankName: 'Chase Commercial',
            amount: 2500,
            depositDate: '$monthKey-10',
            description: 'October Rental Income Deposit',
            status: 'confirmed',
          ),
        ],
      );

      Payment? tappedPayment;
      Tenant? tappedTenant;
      Expense? tappedExpense;
      BankDeposit? tappedDeposit;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopOverviewView(
                onSelectTenant: (_) {},
                onAddTenant: () {},
                onLogPayment: () {},
                onPaymentDetails: (p, t) {
                  tappedPayment = p;
                  tappedTenant = t;
                },
                onExpenseDetails: (e) {
                  tappedExpense = e;
                },
                onDepositDetails: (d) {
                  tappedDeposit = d;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify row for Alice Johnson exists and tap it
      final rentItem = find.text('Alice Johnson');
      expect(rentItem, findsOneWidget);
      await tester.tap(rentItem);
      await tester.pumpAndSettle();

      expect(tappedPayment?.id, equals('p1'));
      expect(tappedTenant?.id, equals('t1'));

      // Verify row for Elevator Maintenance exists and tap it
      final expenseItem = find.text('Elevator Maintenance');
      expect(expenseItem, findsOneWidget);
      await tester.tap(expenseItem);
      await tester.pumpAndSettle();

      expect(tappedExpense?.id, equals('e1'));

      // Verify row for Chase Commercial bank deposit exists and tap it
      final depositItem = find.text('Chase Commercial');
      expect(depositItem, findsOneWidget);
      await tester.tap(depositItem);
      await tester.pumpAndSettle();

      expect(tappedDeposit?.id, equals('d1'));
    },
  );

  testWidgets(
    'DesktopShell renders top bar profile with avatar and opens profile popover',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testState = AppDataState(
        preferences: AppPreferences(driveAutoSync: true),
        selectedYear: 2026,
        selectedCurrency: '\$',
        propertyManager: PropertyManager(
          id: 'pm1',
          name: 'Sarah Connor',
          address: '100 Cyberdyne Blvd',
          phone: '555-0199',
          email: 'sarah@skynet.com',
          propertyName: 'Skyline Lofts',
        ),
        tenants: [
          Tenant(
            id: 't1',
            name: 'Alice Johnson',
            unit: '101',
            phone: '1234567890',
            email: 'alice@example.com',
            rentAmount: 1200,
            status: 'active',
            joinDate: '2026-01-01',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataProvider.overrideWith((ref) => _MockNotifier(testState)),
          ],
          child: const MaterialApp(home: DesktopShell()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify manager name is rendered in the top bar profile button
      final profileButton = find.text('Sarah Connor');
      expect(profileButton, findsOneWidget);

      // Tap the profile button to open popover
      await tester.tap(profileButton);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify popover contents
      expect(find.text('Property Manager'), findsWidgets);
      expect(find.text('Skyline Lofts'), findsWidgets);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Property Details'), findsOneWidget);
      expect(find.text('About RentManager'), findsOneWidget);
    },
  );
}

class _MockNotifier extends AppDataNotifier {
  _MockNotifier(AppDataState initial) {
    state = initial;
  }
}
