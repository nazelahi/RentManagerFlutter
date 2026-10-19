import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/desktop/desktop_command_palette.dart';

class _FakePaletteDataNotifier extends AppDataNotifier {
  _FakePaletteDataNotifier(List<Tenant> tenants) : super() {
    state = AppDataState(
      preferences: AppPreferences(),
      selectedYear: 2026,
      selectedCurrency: '\$',
      tenants: tenants,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_palette_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  Widget buildTestWidget({
    required Function(int) onNavigate,
    required Function(Tenant) onSelectTenant,
    required VoidCallback onAddTenant,
    required VoidCallback onLogPayment,
    List<Tenant>? tenants,
  }) {
    final list = tenants ??
        [
          Tenant(
            id: 't1',
            name: 'John Doe',
            unit: '101',
            email: 'john@example.com',
            phone: '555-0101',
            rentAmount: 1200,
            joinDate: '2026-01-01',
            status: 'active',
          ),
          Tenant(
            id: 't2',
            name: 'Jane Smith',
            unit: '102',
            email: 'jane@example.com',
            phone: '555-0102',
            rentAmount: 1450,
            joinDate: '2026-01-01',
            status: 'late',
          ),
        ];

    final fakeNotifier = _FakePaletteDataNotifier(list);

    return ProviderScope(
      overrides: [
        appDataProvider.overrideWith((ref) => fakeNotifier),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                DesktopCommandPalette.show(
                  context: context,
                  onNavigate: onNavigate,
                  onSelectTenant: onSelectTenant,
                  onAddTenant: onAddTenant,
                  onLogPayment: onLogPayment,
                );
              },
              child: const Text('Open Palette'),
            ),
          ),
        ),
      ),
    );
  }

  group('DesktopCommandPalette Improvements', () {
    testWidgets('Renders search input, category chips, and close button',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          onNavigate: (_) {},
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        ),
      );

      await tester.tap(find.text('Open Palette'));
      await tester.pumpAndSettle();

      // Verify search input is present
      expect(find.byType(TextField), findsOneWidget);

      // Verify category filter chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Tenants'), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);

      // Verify explicit close button in header (with ESC)
      expect(find.text('ESC'), findsOneWidget);

      // Verify footer close action
      expect(find.text('Close (Esc)'), findsOneWidget);

      // Verify rich tenant display with Unit & Status badge
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('Late'), findsOneWidget);
    });

    testWidgets('Header close button dismisses command palette',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          onNavigate: (_) {},
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        ),
      );

      await tester.tap(find.text('Open Palette'));
      await tester.pumpAndSettle();

      expect(find.text('Close (Esc)'), findsOneWidget);

      // Tap header close button
      await tester.tap(find.text('ESC'));
      await tester.pumpAndSettle();

      // Verify palette is dismissed
      expect(find.text('Close (Esc)'), findsNothing);
      expect(find.text('Open Palette'), findsOneWidget);
    });

    testWidgets('Footer close button dismisses command palette',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          onNavigate: (_) {},
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        ),
      );

      await tester.tap(find.text('Open Palette'));
      await tester.pumpAndSettle();

      // Tap footer close button
      await tester.tap(find.text('Close (Esc)'));
      await tester.pumpAndSettle();

      // Verify palette is dismissed
      expect(find.text('Close (Esc)'), findsNothing);
      expect(find.text('Open Palette'), findsOneWidget);
    });

    testWidgets('Category chips filter results immediately',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          onNavigate: (_) {},
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        ),
      );

      await tester.tap(find.text('Open Palette'));
      await tester.pumpAndSettle();

      // Filter to Navigation only
      await tester.tap(find.text('Navigation'));
      await tester.pumpAndSettle();

      // Navigation item should be visible, tenant items should not
      expect(find.text('Overview Dashboard'), findsOneWidget);
      expect(find.text('John Doe'), findsNothing);

      // Filter to Tenants only
      await tester.tap(find.text('Tenants'));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Overview Dashboard'), findsNothing);
    });

    testWidgets('Typing query displays clear button and filters items',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestWidget(
          onNavigate: (_) {},
          onSelectTenant: (_) {},
          onAddTenant: () {},
          onLogPayment: () {},
        ),
      );

      await tester.tap(find.text('Open Palette'));
      await tester.pumpAndSettle();

      // Type "Jane"
      await tester.enterText(find.byType(TextField), 'Jane');
      await tester.pumpAndSettle();

      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('John Doe'), findsNothing);

      // Tap clear button
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      // Both tenants back
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
    });
  });
}
