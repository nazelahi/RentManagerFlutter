import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/widgets/media_widgets.dart';
import 'package:rentmanager/features/zakat/zakat_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_picker_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  group('Desktop File Picker Improvements', () {
    test('MediaPicker class exposes desktop-optimized methods', () {
      expect(MediaPicker.pickImage, isNotNull);
      expect(MediaPicker.pickMultipleImages, isNotNull);
      expect(MediaPicker.pickDocument, isNotNull);
      expect(MediaPicker.fileSizeOf, isNotNull);
    });

    testWidgets('Zakat transaction add modal renders desktop receipt picker on desktop',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ZakatView.showAddModal(context),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final receiptBtn = find.text('Browse Receipt Image');
        await tester.scrollUntilVisible(
          receiptBtn,
          100.0,
          scrollable: find.byType(Scrollable).last,
        );
        expect(receiptBtn, findsOneWidget);
        expect(find.text('Choose from Gallery'), findsNothing);
        expect(find.text('Capture Photo'), findsNothing);
      }
    });
  });
}
