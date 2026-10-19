import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rentmanager/core/widgets/common.dart';

void main() {
  testWidgets('showAppToast renders Top-Right macOS Notification HUD on desktop screens', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late BuildContext targetContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              targetContext = ctx;
              return const Center(child: Text('Desktop App Body'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger success toast
    showAppToast(targetContext, 'Rent payment recorded successfully', isSuccess: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify desktop HUD elements
    expect(find.text('SUCCESS'), findsOneWidget);
    expect(find.text('Rent payment recorded successfully'), findsOneWidget);
    expect(find.text('now'), findsOneWidget);
    expect(find.byIcon(Ionicons.close), findsOneWidget);

    // Verify it is positioned in the top-right
    final toastFinder = find.text('Rent payment recorded successfully');
    final topLeft = tester.getTopLeft(toastFinder);
    expect(topLeft.dy, lessThan(100.0)); // Top area of screen
    expect(topLeft.dx, greaterThan(800.0)); // Right side of 1280 screen

    // Tap dismiss close button
    await tester.tap(find.byIcon(Ionicons.close));
    await tester.pumpAndSettle();

    expect(find.text('Rent payment recorded successfully'), findsNothing);
  });

  testWidgets('showAppToast renders mobile SnackBar on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late BuildContext targetContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              targetContext = ctx;
              return const Center(child: Text('Mobile App Body'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    showAppToast(targetContext, 'Mobile alert message', isError: true);
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Mobile alert message'), findsOneWidget);
  });
}
