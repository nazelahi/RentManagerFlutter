import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/theme/app_theme.dart';
import 'package:rentmanager/features/splash/splash_view.dart';

void main() {
  testWidgets('SplashView renders desktop dual-panel layout on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: const SplashView(loadingText: 'Starting desktop workstation...'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Verify desktop hero elements
    expect(find.text('RentManager'), findsOneWidget);
    expect(find.text('PROPERTY SUITE'), findsOneWidget);
    expect(find.text('Property Management Made Simple'), findsOneWidget);

    // Verify desktop diagnostics module
    expect(find.text('DESKTOP WORKSPACE INITIALIZATION'), findsOneWidget);
    expect(find.text('Local-First Encrypted Database'), findsOneWidget);
    expect(find.text('Property & Lease Engine'), findsOneWidget);
    expect(find.text('Metal Graphics Pipeline'), findsOneWidget);
    expect(find.text('Starting desktop workstation...'), findsOneWidget);

    // Verify desktop system chips
    expect(find.text('Native Desktop'), findsOneWidget);
    expect(find.text('Hardware Accelerated'), findsOneWidget);
    expect(find.text('Offline Privacy'), findsOneWidget);

    // Verify progress indicator is rendered
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
