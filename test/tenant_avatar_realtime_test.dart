import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/widgets/common.dart';
import 'package:rentmanager/features/desktop/desktop_tenants_view.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_avatar_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  group('Tenant Avatar Realtime System-Wide Tests', () {
    testWidgets('AvatarView displays initial fallback and updates when uri changes',
        (tester) async {
      String? testUri;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    AvatarView(
                      name: 'John Doe',
                      uri: testUri,
                      radius: 30,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          testUri = 'https://example.com/avatar.jpg';
                        });
                      },
                      child: const Text('Change Avatar'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Initially fallback initials 'J' is shown
      expect(find.text('J'), findsOneWidget);

      // Tap change avatar button
      await tester.tap(find.text('Change Avatar'));
      await tester.pump();

      // AvatarView received new uri, rebuilds without throwing
      expect(find.byType(AvatarView), findsOneWidget);
    });

    testWidgets('DesktopTenantsView displays tenant avatar in list and dossier header, updating in realtime',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialTenant = Tenant(
        id: 'tenant-101',
        name: 'Sarah Connor',
        unit: '4B',
        phone: '1234567890',
        email: 'sarah@example.com',
        rentAmount: 1500,
        joinDate: '2026-01-01',
        status: 'active',
        avatar: null,
      );

      final fakeNotifier = _FakeAppDataNotifier(initialTenant);
      final container = ProviderContainer(
        overrides: [
          appDataProvider.overrideWith((ref) => fakeNotifier),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: DesktopTenantsView(
              initialSelectedTenant: initialTenant,
              onAddTenant: () {},
              onLogPayment: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Master list shows Sarah Connor and unit 4B
      expect(find.text('Sarah Connor'), findsWidgets);
      expect(find.text('4B'), findsWidgets);

      // Now update tenant avatar in state
      final updatedTenant = initialTenant.copyWith(avatar: 'https://example.com/sarah.jpg');
      container.read(appDataProvider.notifier).upsertTenant(updatedTenant);

      await tester.pumpAndSettle();

      // Re-rendered in realtime: master list and dossier have AvatarView with the new URI
      final avatars = tester.widgetList<AvatarView>(find.byType(AvatarView)).toList();
      expect(avatars.isNotEmpty, isTrue);
      expect(avatars.any((a) => a.uri == 'https://example.com/sarah.jpg'), isTrue);
    });
  });
}

class _FakeAppDataNotifier extends AppDataNotifier {
  _FakeAppDataNotifier(Tenant initialTenant) : super() {
    state = AppDataState(
      preferences: AppPreferences(),
      selectedYear: 2026,
      selectedCurrency: '\$',
      tenants: [initialTenant],
    );
  }

  @override
  void upsertTenant(Tenant t) {
    final list = [...state.tenants];
    final idx = list.indexWhere((e) => e.id == t.id);
    if (idx >= 0) {
      list[idx] = t;
    } else {
      list.add(t);
    }
    state = state.copyWith(tenants: list);
  }
}
