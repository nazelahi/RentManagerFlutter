import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/widgets/common.dart';
import 'package:rentmanager/features/desktop/desktop_documents_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_docs_redesign_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  group('DesktopDocumentsView Modal Preview & No File Inspector', () {
    testWidgets('Clicking a document opens preview modal and File Inspector is removed',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc1 = RentDoc(
        id: 'doc-1',
        title: 'Lease Agreement Apt 3B',
        type: 'lease',
        fileName: 'lease_apt3b.pdf',
        fileSize: '1.4 MB',
        uploadedBy: 'Landlord',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      final doc2 = RentDoc(
        id: 'doc-2',
        title: 'Move-in Inspection Photos',
        type: 'receipt',
        fileName: 'kitchen_inspection.jpg',
        fileUri: '/path/to/kitchen_inspection.jpg',
        fileSize: '3.2 MB',
        uploadedBy: 'Property Manager',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      RentDoc? viewedDoc;

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [doc1, doc2],
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
                onViewDocument: (doc) {
                  viewedDoc = doc;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify files are listed on canvas
      expect(find.text('Lease Agreement Apt 3B'), findsWidgets);
      expect(find.text('Move-in Inspection Photos'), findsWidgets);

      // 2. CRITICAL: File Inspector panel and Inspector toolbar button must NOT exist
      expect(find.text('File Inspector'), findsNothing);
      expect(find.text('Inspector'), findsNothing);

      // 3. Single-clicking the document card directly triggers onViewDocument preview callback!
      final docCard = find.text('Lease Agreement Apt 3B').first;
      await tester.tap(docCard);
      await tester.pumpAndSettle();

      expect(viewedDoc, isNotNull);
      expect(viewedDoc?.id, equals('doc-1'));
      expect(viewedDoc?.title, equals('Lease Agreement Apt 3B'));
    });

    testWidgets('Tapping document opens preview modal sheet when onViewDocument is null',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc1 = RentDoc(
        id: 'doc-1',
        title: 'Lease Agreement Apt 3B',
        type: 'lease',
        fileName: 'lease_apt3b.pdf',
        fileSize: '1.4 MB',
        uploadedBy: 'Landlord',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [doc1],
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

      // Tap document
      final docFinder = find.text('Lease Agreement Apt 3B').first;
      await tester.tap(docFinder);
      await tester.pumpAndSettle();

      // Should open the preview AppModalSheet
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Tap Done to close modal
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(AppModalSheet), findsNothing);
    });

    testWidgets('Quick file type filter pills filter PDFs and Images',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc1 = RentDoc(
        id: 'doc-1',
        title: 'Master Lease PDF',
        type: 'lease',
        fileName: 'lease.pdf',
        fileSize: '1.2 MB',
        uploadedBy: 'Manager',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      final doc2 = RentDoc(
        id: 'doc-2',
        title: 'Bathroom Wall Image',
        type: 'maintenance',
        fileName: 'bathroom.png',
        fileUri: '/path/to/bathroom.png',
        fileSize: '800 KB',
        uploadedBy: 'Contractor',
        uploadedDate: DateTime.now().toIso8601String(),
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [doc1, doc2],
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

      // Both should be visible initially
      expect(find.text('Master Lease PDF'), findsWidgets);
      expect(find.text('Bathroom Wall Image'), findsWidgets);

      // Tap "PDFs" filter pill
      final pdfPill = find.text('PDFs');
      expect(pdfPill, findsOneWidget);
      await tester.tap(pdfPill);
      await tester.pumpAndSettle();

      // Only Master Lease PDF should be visible
      expect(find.text('Master Lease PDF'), findsWidgets);
      expect(find.text('Bathroom Wall Image'), findsNothing);

      // Tap "Images" filter pill
      final imagePill = find.text('Images');
      expect(imagePill, findsOneWidget);
      await tester.tap(imagePill);
      await tester.pumpAndSettle();

      // Only Bathroom Wall Image should be visible
      expect(find.text('Master Lease PDF'), findsNothing);
      expect(find.text('Bathroom Wall Image'), findsWidgets);
    });

    testWidgets('Redesigned Sort Selector sorts documents by Newest, Oldest, Name, and Expiry',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final docAlpha = RentDoc(
        id: 'doc-alpha',
        title: 'Alpha Document',
        type: 'other',
        fileName: 'alpha.pdf',
        fileSize: '500 KB',
        uploadedBy: 'Admin',
        uploadedDate: '2026-01-01',
        expiryDate: '2026-12-31',
        status: 'active',
      );

      final docZeta = RentDoc(
        id: 'doc-zeta',
        title: 'Zeta Document',
        type: 'other',
        fileName: 'zeta.pdf',
        fileSize: '600 KB',
        uploadedBy: 'Admin',
        uploadedDate: '2026-10-01',
        expiryDate: '2026-05-01',
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [docAlpha, docZeta],
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

      // Initially sorted Newest First -> Zeta (uploaded 2026-10-01) should appear before Alpha (2026-01-01)
      final zetaFinder = find.text('Zeta Document');
      final alphaFinder = find.text('Alpha Document');
      expect(zetaFinder, findsWidgets);
      expect(alphaFinder, findsWidgets);

      final zetaYInit = tester.getTopLeft(zetaFinder.first).dy;
      final alphaYInit = tester.getTopLeft(alphaFinder.first).dy;
      // In grid view, Zeta (newest) appears first (top or left)
      final zetaXInit = tester.getTopLeft(zetaFinder.first).dx;
      final alphaXInit = tester.getTopLeft(alphaFinder.first).dx;
      expect(zetaYInit < alphaYInit || (zetaYInit == alphaYInit && zetaXInit < alphaXInit), isTrue);

      // Open sort dropdown and select Oldest First
      await tester.tap(find.textContaining('Newest').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Oldest First').last);
      await tester.pumpAndSettle();

      // Now Alpha (2026-01-01) should appear before Zeta (2026-10-01)
      final zetaYOld = tester.getTopLeft(zetaFinder.first).dy;
      final alphaYOld = tester.getTopLeft(alphaFinder.first).dy;
      final zetaXOld = tester.getTopLeft(zetaFinder.first).dx;
      final alphaXOld = tester.getTopLeft(alphaFinder.first).dx;
      expect(alphaYOld < zetaYOld || (alphaYOld == zetaYOld && alphaXOld < zetaXOld), isTrue);

      // Switch to Name (A-Z) -> Alpha should remain before Zeta
      await tester.tap(find.textContaining('Oldest').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Name (A-Z)').last);
      await tester.pumpAndSettle();

      final zetaYName = tester.getTopLeft(zetaFinder.first).dy;
      final alphaYName = tester.getTopLeft(alphaFinder.first).dy;
      final zetaXName = tester.getTopLeft(zetaFinder.first).dx;
      final alphaXName = tester.getTopLeft(alphaFinder.first).dx;
      expect(alphaYName < zetaYName || (alphaYName == zetaYName && alphaXName < zetaXName), isTrue);

      // Switch to Expiry Date -> Zeta expires 2026-05-01 (earlier) so Zeta comes before Alpha (2026-12-31)
      await tester.tap(find.textContaining('Name').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Expiry Date').last);
      await tester.pumpAndSettle();

      final zetaYExp = tester.getTopLeft(zetaFinder.first).dy;
      final alphaYExp = tester.getTopLeft(alphaFinder.first).dy;
      final zetaXExp = tester.getTopLeft(zetaFinder.first).dx;
      final alphaXExp = tester.getTopLeft(alphaFinder.first).dx;
      expect(zetaYExp < alphaYExp || (zetaYExp == alphaYExp && zetaXExp < alphaXExp), isTrue);
    });

    testWidgets('Toggling to List View renders aligned Table Header and document table rows',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc = RentDoc(
        id: 'doc-1',
        title: 'Single Apartment Lease',
        type: 'lease',
        fileName: 'lease.pdf',
        fileSize: '1.2 MB',
        uploadedBy: 'Manager',
        uploadedDate: '2026-04-10',
        unit: 'Apt 4A',
        tenant: 'John Doe',
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [doc],
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

      // Switch to List View
      final listViewButton = find.byTooltip('List View');
      expect(listViewButton, findsOneWidget);
      await tester.tap(listViewButton);
      await tester.pumpAndSettle();

      // Verify Table Header is rendered with all columns
      expect(find.text('DOCUMENT / NAME'), findsOneWidget);
      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('UNIT / TENANT'), findsOneWidget);
      expect(find.text('DATE / EXPIRY'), findsOneWidget);
      expect(find.text('SIZE'), findsOneWidget);
      expect(find.text('ACTIONS'), findsOneWidget);

      // Verify row is rendered as table row (NOT as single doc card)
      expect(find.text('Single Apartment Lease'), findsOneWidget);
      expect(find.text('lease.pdf'), findsOneWidget);
      expect(find.text('Apt 4A (John Doe)'), findsOneWidget);
      expect(find.byTooltip('Preview Document'), findsOneWidget);
    });

    testWidgets('List View rows render thumbnails for PDF, Image, and Group documents',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final pdfDoc = RentDoc(
        id: 'doc-pdf',
        title: 'Signed Agreement',
        type: 'contract',
        fileName: 'agreement.pdf',
        fileSize: '500 KB',
        uploadedBy: 'Admin',
        uploadedDate: '2026-04-01',
        status: 'active',
      );

      final imgDoc = RentDoc(
        id: 'doc-img',
        title: 'Balcony Photo',
        type: 'inspection',
        fileName: 'balcony.jpg',
        fileUri: '/path/to/balcony.jpg',
        fileSize: '2.1 MB',
        uploadedBy: 'Admin',
        uploadedDate: '2026-04-02',
        status: 'active',
      );

      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) {
            final notifier = AppDataNotifier();
            notifier.state = notifier.state.copyWith(
              documents: [pdfDoc, imgDoc],
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

      // Switch to List View
      await tester.tap(find.byTooltip('List View'));
      await tester.pumpAndSettle();

      // PDF row renders PDF badge thumbnail
      expect(find.text('PDF'), findsOneWidget);

      // Both document rows exist in list view
      expect(find.text('Signed Agreement'), findsOneWidget);
      expect(find.text('Balcony Photo'), findsOneWidget);

      // Verify thumbnail containers with 32x32 size exist
      final containers = tester.widgetList<Container>(find.byType(Container));
      final has32x32Thumbnails = containers.any(
        (c) =>
            c.constraints?.maxWidth == 32 &&
            c.constraints?.maxHeight == 32,
      );
      expect(has32x32Thumbnails, isTrue);
    });
  });
}

