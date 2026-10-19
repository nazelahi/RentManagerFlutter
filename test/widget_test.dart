import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/theme/app_colors.dart';
import 'package:rentmanager/core/theme/app_theme.dart';
import 'package:rentmanager/core/widgets/app_shell.dart';
import 'package:rentmanager/features/splash/splash_view.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_widget_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });
  test('status colors mirror COLORS.getStatusColor', () {
    expect(AppColors.statusColor('paid'), AppColors.success);
    expect(AppColors.statusColor('pending'), AppColors.warning);
    expect(AppColors.statusColor('failed'), AppColors.error);
    expect(AppColors.statusColor('draft'), AppColors.info);
  });

  test('theme builds dark teal scheme', () {
    final theme = buildAppTheme();
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.scaffoldBackgroundColor, AppColors.backgroundDark);
  });

  testWidgets('SplashView renders branding + progress in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildDarkAppTheme(), home: const SplashView()),
    );
    expect(find.text('RentManager'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Property Management Made Simple'), findsOneWidget);
    expect(find.text('PROPERTY SUITE'), findsOneWidget);
  });

  testWidgets('SplashView renders branding + progress in light mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightAppTheme(), home: const SplashView(loadingText: 'Syncing assets...')),
    );
    expect(find.text('RentManager'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Syncing assets...'), findsOneWidget);
  });

  testWidgets('AppShell renders desktop sidebar on wide screen', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    expect(find.text('MAIN MENU'), findsOneWidget);
  });

  testWidgets('AppShell renders bottom navigation on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    expect(find.text('MAIN MENU'), findsNothing);
    expect(find.text('Overview'), findsOneWidget);
  });
}

