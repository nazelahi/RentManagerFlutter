import 'dart:async';
import 'dart:ui';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/state/app_data.dart';
import 'core/storage/app_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/app_shell.dart';
import 'core/widgets/common.dart';
import 'features/onboarding/onboarding_view.dart';
import 'features/splash/splash_view.dart';
import 'services/auto_backup_service.dart';
import 'services/biometric_auth.dart';
import 'services/deep_linking.dart';
import 'services/drive_backup_service.dart';
import 'services/notification_service.dart';

/// Port of `App.tsx` — boot sequence: splash (min display) → biometric gate
/// (existing users with lock enabled) → onboarding → tabs.
/// Mirrors showSplash / isAuthenticated / showOnboarding gating.
Future<void> main() async {
  // Port of ErrorBoundary at the root.
  ErrorWidget.builder = (details) => Container(
        color: AppColors.backgroundDark,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'Something went wrong. Please restart the app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppStorage.init();
    try {
      await NotificationService.init();
    } catch (_) {
      // Notifications optional on first boot — matches Expo Go fallback.
    }
    runApp(const ProviderScope(child: RentManagerApp()));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class RentManagerApp extends ConsumerStatefulWidget {
  const RentManagerApp({super.key});
  @override
  ConsumerState<RentManagerApp> createState() => _RentManagerAppState();
}

class _RentManagerAppState extends ConsumerState<RentManagerApp>
    with WidgetsBindingObserver {
  bool _authChecked = false;
  bool _authenticated = false;
  bool _authFailed = false;
  late final AppLinks _links;
  StreamSubscription? _linkSub;
  bool _periodicSyncRestarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await ref.read(appDataProvider.notifier).loadAll();
      // Minimum splash display (mirrors minDisplayTime 2000/3000ms).
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) ref.read(appDataProvider.notifier).dismissSplash();
      await _checkBiometricGate();
      // Local auto-backup and Google Drive auto-sync if enabled and due (fire-and-forget).
      if (mounted) {
        unawaited(AutoBackupService.runIfDue(ref));
        unawaited(DriveBackupService.syncIfDue(ref));
        DriveBackupService.startPeriodicSync(ref);
      }
    });
    _links = AppLinks();
    _linkSub = _links.uriLinkStream.listen((uri) {
      DeepLinkBus.request(uri.toString());
    }, onError: (_) {});
  }

  /// Mirrors the biometric check in useOptimizedAppData for existing users.
  Future<void> _checkBiometricGate() async {
    final s = ref.read(appDataProvider);
    final needsGate = s.preferences.biometricLock && !s.showOnboarding;
    if (!needsGate) {
      if (mounted) {
        setState(() {
          _authChecked = true;
          _authenticated = true;
        });
      }
      return;
    }
    final ok = await BiometricAuth.authenticate(
      localizedReason: 'Please authenticate to unlock RentManager',
    );
    if (mounted) {
      setState(() {
        _authChecked = true;
        _authenticated = ok;
        _authFailed = !ok;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = ref.read(appDataProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Flush the debounced save so the last edit survives backgrounding.
      unawaited(ref.read(appDataProvider.notifier).flush());
    }
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(DriveBackupService.onAppResumed(ref));
      if (s.preferences.biometricLock && !s.showOnboarding) {
        setState(() {
          _authChecked = false;
          _authenticated = false;
          _authFailed = false;
        });
        unawaited(_checkBiometricGate());
      }
    }
  }

  @override
  void dispose() {
    DriveBackupService.stopPeriodicSync();
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applySystemChrome();
  }

  void _applySystemChrome() {
    final isDark = AppColors.isDark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? const Color(0xFF061818)
          : const Color(0xFFF1F5F9),
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final themeMode = s.preferences.themeMode;
    final isDark = themeMode == 'light'
        ? false
        : themeMode == 'system'
            ? (WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark)
            : true;
    AppColors.isDark = isDark;

    // The periodic Drive sync timer is stopped while the setup wizard runs
    // (resetApp stops it); restart it once, after onboarding completes.
    ref.listen<bool>(appDataProvider.select((s) => s.showOnboarding),
        (previous, next) {
      if (next) {
        _periodicSyncRestarted = false;
        DriveBackupService.stopPeriodicSync();
      } else if (previous == true) {
        // Restore/complete can import biometricLock while onboarding was
        // visible; re-evaluate the gate now that the shell will be shown.
        unawaited(_checkBiometricGate());
      }
    });
    if (!s.showOnboarding && !s.showSplash && !s.isLoading && !_periodicSyncRestarted) {
      _periodicSyncRestarted = true;
      DriveBackupService.startPeriodicSync(ref);
    }

    return MaterialApp(
      title: 'RentManager',
      debugShowCheckedModeBanner: false,
      theme: buildLightAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode == 'light'
          ? ThemeMode.light
          : themeMode == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system,
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: Builder(builder: (_) {
        if (s.showSplash || s.isLoading) {
          return SplashView(
            loadingText: s.showOnboarding
                ? 'Setting up RentManager...'
                : s.isLoading
                    ? 'Loading critical data...'
                    : 'Almost ready...',
          );
        }
        if (s.showOnboarding) return const OnboardingView();
        // Port of the App.tsx authentication gate.
        if (!_authChecked || !_authenticated) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fingerprint,
                          size: 64, color: AppColors.primary),
                      const SizedBox(height: 16),
                      const Text('Authentication Required',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(
                        'Please authenticate using your biometric credentials to access RentManager',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14),
                      ),
                      if (_authFailed) ...[
                        const SizedBox(height: 20),
                        GradientButton.icon(
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Try Again'),
                          onPressed: () {
                            setState(() => _authFailed = false);
                            _checkBiometricGate();
                          },
                        ),
                      ],
                    ]),
              ),
            ),
          );
        }
        return const AppShell();
      }),
    );
  }
}
