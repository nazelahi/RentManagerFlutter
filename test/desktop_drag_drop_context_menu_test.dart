import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_documents_view.dart';
import 'package:rentmanager/features/desktop/desktop_tenants_view.dart';
import 'package:rentmanager/features/desktop/desktop_work_orders_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_dragdrop_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  group('Desktop Drag & Drop and Context Menus', () {
    testWidgets('DesktopDocumentsView renders DropTarget and secondary-click context menu',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testDoc = RentDoc(
        id: 'doc-1',
        title: 'Lease Agreement Apt 3B',
        type: 'contract',
        fileName: 'lease_agreement.pdf',
        fileSize: '1.2 MB',
        uploadedBy: 'Desktop User',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [testDoc],
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DesktopDocumentsView(
                onAddDocument: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify DropTarget is present in DesktopDocumentsView
      expect(find.byType(DropTarget), findsOneWidget);

      // Verify document card is rendered
      final docFinder = find.text('Lease Agreement Apt 3B');
      expect(docFinder, findsWidgets);

      // Secondary click (right-click) on document to trigger context menu
      await tester.tap(docFinder.first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Verify context menu items appear
      expect(find.text('View / Preview'), findsOneWidget);
      expect(find.text('Delete Document'), findsOneWidget);
    });

    testWidgets('DesktopTenantsView renders DropTarget and secondary-click context menu',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testTenant = Tenant(
        id: 'tenant-1',
        name: 'Sarah Connor',
        unit: 'Apt 101',
        phone: '555-0199',
        email: 'sarah@example.com',
        rentAmount: 1450.0,
        joinDate: '2025-01-01',
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              tenants: [testTenant],
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DesktopTenantsView(
                initialSelectedTenant: testTenant,
                onAddTenant: () {},
                onLogPayment: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify DropTarget is present in DesktopTenantsView dossier
      expect(find.byType(DropTarget), findsOneWidget);

      // Verify tenant card is rendered
      final tenantFinder = find.text('Sarah Connor');
      expect(tenantFinder, findsWidgets);

      // Secondary click on tenant in list
      await tester.tap(tenantFinder.first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Verify context menu options appear
      expect(find.text('Log Rent Payment'), findsOneWidget);
      expect(find.text('Call (555-0199)'), findsOneWidget);
    });

    testWidgets('DesktopWorkOrdersView renders secondary-click context menu with status options',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testOrder = WorkOrder(
        id: 'wo-1',
        title: 'Fix kitchen faucet leak',
        description: 'Dripping water in kitchen sink',
        status: 'pending',
        category: 'Plumbing',
        assignedTo: 'Mike Plumber',
        createdAt: DateTime.now().toIso8601String(),
        dueDate: DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        unit: '101',
        productPrice: 35.0,
        workerCost: 50.0,
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              workOrders: [testOrder],
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DesktopWorkOrdersView(
                onAddOrder: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify order title is rendered
      final orderFinder = find.text('Fix kitchen faucet leak');
      expect(orderFinder, findsWidgets);

      // Secondary click on work order row
      await tester.tap(orderFinder.first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Verify context menu options appear
      expect(find.text('Mark In Progress'), findsOneWidget);
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Delete Work Order'), findsOneWidget);
    });
  });
}
