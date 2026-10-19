import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/drive_backup_service.dart';
import '../../core/app_info.dart';
import '../../core/storage/app_storage.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import 'bank_setup_modal.dart';
import 'data_restore_modal.dart';
import 'profile_setup_form.dart';
import 'restore_summary_modal.dart';

/// Desktop-tailored & responsive 8-step Setup Assistant for RentManager.
/// On desktop (width >= 840px), provides a dual-panel master stepper and
/// interactive staging canvas. On mobile, provides a smooth paged flow.
class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});
  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  static const _appName = kAppName;
  static const _appVersion = kAppVersion;

  final _page = PageController();
  final _managerFormKey = GlobalKey<ProfileSetupFormState>();
  final _propertyFormKey = GlobalKey<ProfileSetupFormState>();
  int _step = 0;
  final Set<int> _completed = {};
  PropertyManager? _userProfile;
  List<BankInfo> _userBanks = const [];
  String _currency = '\$';
  String _themeMode = 'dark';
  PermissionStatus? _notifStatus;
  bool _didRestore = false;

  static const _green = Color(0xFF10B981);
  static const _purple = Color(0xFF8B5CF6);
  static const _blue = Color(0xFF3B82F6);
  static const _orange = Color(0xFFF59E0B);

  List<_Step> get _steps => [
    const _Step(
      1,
      'Welcome to $_appName',
      "Your complete property management suite. Let's get you set up with your workspace in just a couple of minutes.",
      Ionicons.home,
      _green,
      false,
      'Welcome',
    ),
    const _Step(
      2,
      'Restore Data (Optional)',
      'Restore your properties and records from Google Drive or local backups if you have existing data.',
      Ionicons.cloudDownload,
      _purple,
      false,
      'Data Backup',
    ),
    const _Step(
      3,
      'Set Up Your Profile',
      'Add your property manager details to personalize your tenant invoices and receipts.',
      Ionicons.person,
      _blue,
      false,
      'Manager Profile',
    ),
    const _Step(
      4,
      'Set Up Your Property',
      'Add your property name, owner, and address so listings and receipts are complete.',
      Ionicons.business,
      _green,
      false,
      'Property Info',
    ),
    const _Step(
      5,
      'Enable Notifications',
      'Stay informed with rent due dates, lease expiration alerts, and critical property updates.',
      Ionicons.notifications,
      _orange,
      false,
      'Alerts & Reminders',
    ),
    const _Step(
      6,
      'Set Up Your Banks',
      'Connect your bank accounts to assign rent collection deposits and monitor monthly payouts.',
      Ionicons.business,
      _purple,
      false,
      'Bank Accounts',
    ),
    const _Step(
      7,
      'Choose Your Currency',
      'Select your primary currency symbol for rent tracking, invoices, and accounting totals.',
      Ionicons.cash,
      _green,
      false,
      'Currency',
    ),
    const _Step(
      8,
      'Choose Your Appearance',
      'Pick a light or dark interface — or let the app follow your system theme automatically.',
      Ionicons.contrastOutline,
      _blue,
      false,
      'Appearance',
    ),
    const _Step(
      9,
      "You're All Set!",
      'Your $_appName workspace is primed and ready. Start managing your units, leases, and cashflow.',
      Ionicons.checkmarkCircle,
      _green,
      false,
      'Complete',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final cur = ref.read(appDataProvider).selectedCurrency;
    if (cur.isNotEmpty) {
      _currency = cur;
    }
    final theme = ref.read(appDataProvider).preferences.themeMode;
    if (theme == 'light' || theme == 'system' || theme == 'dark') {
      _themeMode = theme;
    }
    final pm = ref.read(appDataProvider).propertyManager;
    if (pm != null) {
      _userProfile = pm;
      if (pm.name.isNotEmpty) _completed.add(3);
      if ((pm.propertyName ?? '').isNotEmpty && pm.address.isNotEmpty) {
        _completed.add(4);
      }
    }
    final banks = ref.read(appDataProvider).banks;
    if (banks.isNotEmpty) {
      _userBanks = banks;
      _completed.add(6);
    }
    _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus() async {
    try {
      final st = await Permission.notification.status;
      if (mounted) setState(() => _notifStatus = st);
    } catch (_) {}
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (!mounted) return;
    final clamped = index.clamp(0, _steps.length - 1);
    setState(() => _step = clamped);
    if (_page.hasClients) {
      _page.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _next() async {
    if (_step >= _steps.length - 1) {
      _complete();
      return;
    }
    final step = _steps[_step];

    switch (step.id) {
      case 2:
        // On Step 2 (Restore), next simply advances unless user explicitly triggers restore.
        _completed.add(2);
        _goTo(_step + 1);
        return;
      case 3:
        final managerForm = _managerFormKey.currentState;
        if (managerForm == null || !managerForm.submit()) return;
        _saveProfile(managerForm.value, stepId: 3);
        _goTo(_step + 1);
        return;
      case 4:
        final propertyForm = _propertyFormKey.currentState;
        if (propertyForm == null || !propertyForm.submit()) return;
        _saveProfile(propertyForm.value, stepId: 4);
        _goTo(_step + 1);
        return;
      case 5:
        await _requestNotifications();
        if (!mounted) return;
        if (!_completed.contains(5)) _completed.add(5);
        _goTo(_step + 1);
        return;
      case 6:
        if (!_completed.contains(6)) _completed.add(6);
        _goTo(_step + 1);
        return;
      default:
        if (!_completed.contains(step.id)) _completed.add(step.id);
        _goTo(_step + 1);
    }
  }

  Future<void> _openRestoreSheet() async {
    final res = await showDataRestoreSheet(context);
    if (!mounted) return;
    if (res != null) {
      await _handleRestoreResult(res);
    } else {
      _handleRestoreClose();
    }
  }

  Future<void> _openBankSheet() async {
    final banks = await showBankSetupSheet(context, initial: _userBanks);
    if (banks != null) {
      _saveBanks(banks);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      final account = await DriveBackupService.signIn();
      if (!mounted || account == null) return;
      showAppToast(context, 'Signed in as ${account.email}', isSuccess: true);

      // Connecting Drive on the restore step should actually offer the latest
      // cloud backup, not just authenticate and skip the step.
      List<DriveBackupFile> backups = const [];
      try {
        backups = await DriveBackupService.listBackups();
      } catch (_) {}
      if (!mounted) return;
      if (backups.isNotEmpty) {
        final restore = await confirmDialog(
          context,
          'Restore From Google Drive?',
          'Found ${backups.length} backup(s). Restore the latest '
              '(${backups.first.name}) now? This replaces the current setup data.',
        );
        if (!mounted) return;
        if (restore) {
          final data = await DriveBackupService.download(backups.first.id);
          if (data != null) {
            await AppStorage.importAll(data);
            if (!mounted) return;
            await _handleRestoreResult(data);
            return;
          }
        }
      }
      setState(() => _completed.add(2));
      _goTo(_step + 1);
    } catch (e) {
      if (!mounted) return;
      final s = '$e';
      if (!s.contains('cancel')) {
        showAppToast(context, 'Sign in note: $e');
      }
    }
  }

  void _skip() {
    if (_step >= _steps.length - 1) {
      _complete();
      return;
    }
    final id = _steps[_step].id;
    // Manager Profile (3) and Property Info (4) are required — validate instead.
    if (id == 3 || id == 4) {
      _next();
      return;
    }
    _completed.add(id);
    _goTo(_step + 1);
  }

  void _complete() {
    ref.read(appDataProvider.notifier).completeOnboarding();
  }

  void _saveProfile(PropertyManager p, {int stepId = 3}) {
    final notifier = ref.read(appDataProvider.notifier);
    notifier.setPropertyManager(p);
    if (!mounted) return;
    setState(() {
      _userProfile = p;
      _completed.add(stepId);
    });
  }

  void _saveBanks(List<BankInfo> banks) {
    ref.read(appDataProvider.notifier).setBanks(banks);
    if (!mounted) return;
    setState(() {
      _userBanks = banks;
      _completed.add(6);
    });
  }

  Future<void> _requestNotifications() async {
    try {
      final st = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notifStatus = st);
      if (st.isGranted) {
        showAppToast(
          context,
          'Notifications enabled successfully',
          isSuccess: true,
        );
      } else if (st.isPermanentlyDenied) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Notifications Blocked'),
            content: const Text(
              'Notifications are blocked for this app. Open system settings to enable rent due and lease alerts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (open == true) {
          await openAppSettings();
          await _refreshNotificationStatus();
        }
      } else {
        showAppToast(context, 'Notification permission skipped or denied');
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Notification setup skipped');
      }
    }
  }

  Future<void> _handleRestoreResult(Map<String, dynamic> res) async {
    final notifier = ref.read(appDataProvider.notifier);
    await notifier.loadAll();
    if (!mounted) return;
    // A backup from a completed install carries onboardingCompleted=true.
    // Keep the wizard mounted so the restore summary and completion step run.
    if (!ref.read(appDataProvider).showOnboarding) {
      notifier.setShowOnboarding(true);
    }
    final state = ref.read(appDataProvider);
    setState(() {
      _didRestore = true;
      _completed.addAll([1, 2, 3, 4, 5, 6, 7, 8]);
      _userProfile = state.propertyManager;
      _userBanks = state.banks;
      if (state.selectedCurrency.isNotEmpty) {
        _currency = state.selectedCurrency;
      }
      if (_step < _steps.length - 1) _step += 1;
    });
    if (_page.hasClients) _page.jumpToPage(_step);

    await showRestoreSummarySheet(context, res);
    if (!mounted) return;
    _goTo(_steps.length - 1);
  }

  void _handleRestoreClose() {
    _completed.add(2);
    _goTo(_step + 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF071216)
          : const Color(0xFFF0F5F5),
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 840) {
                return _buildDesktopLayout(context, isDark, constraints);
              }
              return _buildMobileLayout(context, isDark, constraints);
            },
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DESKTOP TWO-PANEL SETUP ASSISTANT LAYOUT
  // ===========================================================================

  Widget _buildDesktopLayout(
    BuildContext context,
    bool isDark,
    BoxConstraints constraints,
  ) {
    final steps = _steps;
    final currentStep = steps[_step];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
          if (_step > 0) _goTo(_step - 1);
        },
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1140, maxHeight: 760),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1B20) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? const Color(0x3334D399)
                    : const Color(0x33059669),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  // Left Master Stepper Sidebar
                  _buildDesktopSidebar(context, isDark, steps),

                  // Divider
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: isDark
                        ? const Color(0x1FFFFFFF)
                        : const Color(0x1F000000),
                  ),

                  // Right Stage Canvas
                  Expanded(
                    child: _buildDesktopStage(
                      context,
                      isDark,
                      currentStep,
                      steps,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(
    BuildContext context,
    bool isDark,
    List<_Step> steps,
  ) {
    final progress = (_step + 1) / steps.length;

    return Container(
      width: 310,
      color: isDark ? const Color(0xFF0A1519) : const Color(0xFFF7FAFA),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.business,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _appName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'SETUP ASSISTANT',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // Progress Overview Pill
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132228) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x14000000),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${_step + 1} of ${steps.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFA0D8D8)
                            : const Color(0xFF059669),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 6,
                    color: isDark
                        ? const Color(0xFF1E323A)
                        : const Color(0xFFE2E8F0),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, val, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: val.clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF059669), Color(0xFF10B981)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Stepper Items List
          Expanded(
            child: ListView.separated(
              itemCount: steps.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final s = steps[i];
                final isCurrent = i == _step;
                final isDone = _completed.contains(s.id) || i < _step;
                // Lock future steps so the sidebar can't bypass required setup.
                final unlocked = isDone || i <= _step;

                return InkWell(
                  onTap: unlocked ? () => _goTo(i) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? (isDark
                                ? const Color(0xFF162A32)
                                : const Color(0xFFE6F4EA))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isCurrent
                          ? Border.all(
                              color: isDark
                                  ? const Color(0xFF34D399)
                                        .withValues(alpha: 0.4)
                                  : const Color(0xFF059669)
                                        .withValues(alpha: 0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Circle Indicator
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? const Color(0xFF10B981)
                                : isCurrent
                                ? const Color(0xFF059669)
                                : (isDark
                                      ? const Color(0xFF1A2A30)
                                      : const Color(0xFFE2E8F0)),
                            border: isCurrent
                                ? Border.all(color: Colors.white, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: isDone
                              ? const Icon(
                                  Ionicons.checkmark,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : !unlocked
                              ? Icon(
                                  Ionicons.lockClosed,
                                  size: 12,
                                  color: isDark
                                      ? const Color(0xFF718096)
                                      : const Color(0xFF94A3B8),
                                )
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: (isDone || isCurrent)
                                        ? Colors.white
                                        : (isDark
                                              ? const Color(0xFF718096)
                                              : const Color(0xFF64748B)),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isCurrent
                                      ? (isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A))
                                      : isDone
                                      ? (isDark
                                            ? const Color(0xFFE2E8F0)
                                            : const Color(0xFF334155))
                                      : (isDark
                                            ? const Color(0xFF718096)
                                            : const Color(0xFF94A3B8)),
                                ),
                              ),
                              Text(
                                s.category,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isCurrent
                                      ? (isDark
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFF059669))
                                      : (isDark
                                            ? const Color(0xFF4A5568)
                                            : const Color(0xFFA0AEC0)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Bottom Reassurance / Encrypted Local Storage
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1B20) : const Color(0xFFEDF2F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Ionicons.shieldCheckmarkOutline,
                  size: 16,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Local-First Encrypted DB',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFA0D8D8)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '$_appName v$_appVersion · Desktop Edition',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark
                    ? const Color(0xFF4A5568)
                    : const Color(0xFFA0AEC0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopStage(
    BuildContext context,
    bool isDark,
    _Step step,
    List<_Step> steps,
  ) {
    final isLast = step.id == steps.length;
    final showSkip = _step < steps.length - 1 &&
        _step > 0 &&
        step.id != 3 &&
        step.id != 4 &&
        _step != 6;

    return Column(
      children: [
        // Main Scrollable Canvas
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 32, 10, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (step.id != 3 && step.id != 4) ...[
                      // Breadcrumb Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: step.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'STEP ${step.id} OF ${steps.length} • ${step.category.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: step.color,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Hero Header Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: step.color.withValues(
                                alpha: isDark ? 0.22 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: step.color.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(step.icon, size: 30, color: step.color),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _description(step),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.45,
                                    color: isDark
                                        ? const Color(0xFFA0AEC0)
                                        : const Color(0xFF4A5568),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],

                    // Custom Stage Body Content
                    _buildStepContent(context, isDark, step),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B1418) : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? const Color(0x1FFFFFFF)
                    : const Color(0x1F000000),
              ),
            ),
          ),
          child: Row(
            children: [
              // Back Button
              if (_step > 0)
                OutlinedButton.icon(
                  onPressed: () => _goTo(_step - 1),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    foregroundColor: isDark
                        ? const Color(0xFFA0D8D8)
                        : const Color(0xFF334155),
                  ),
                )
              else
                const SizedBox.shrink(),

              const Spacer(),

              // Skip Button
              if (showSkip)
                TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF718096)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Primary Action Button
              _buildDesktopPrimaryButton(context, isDark, isLast),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent(BuildContext context, bool isDark, _Step step) {
    switch (step.id) {
      case 1:
        return _buildWelcomeFeatures(isDark);
      case 2:
        return _buildRestoreCards(isDark);
      case 3:
        return _buildProfileCard(isDark);
      case 4:
        return _buildPropertyCard(isDark);
      case 5:
        return _buildNotificationCards(isDark);
      case 6:
        return _buildBankCards(isDark);
      case 7:
        return _buildCurrencyCards(isDark);
      case 8:
        return _buildThemeCards(isDark);
      case 9:
        return _buildCompletionSummary(isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 1: Welcome Features ---
  Widget _buildWelcomeFeatures(bool isDark) {
    final features = [
      (
        Ionicons.businessOutline,
        const Color(0xFF10B981),
        'Property & Unit Portfolio',
        'Manage multi-family complexes or single units, tenant lease terms, and emergency records with unified simplicity.',
      ),
      (
        Ionicons.cashOutline,
        const Color(0xFF3B82F6),
        'Rent Invoicing & Expenses',
        'Instant monthly payment tracking, due-date balance calculations, and vendor upkeep expense records.',
      ),
      (
        Ionicons.shieldCheckmarkOutline,
        const Color(0xFF8B5CF6),
        '100% Offline-First Privacy',
        'Your financial records stay secure on this computer. Zero mandatory cloud accounts or external database dependencies.',
      ),
    ];

    return Column(
      children: [
        for (final f in features)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x14000000),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: f.$2.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(f.$1, size: 22, color: f.$2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$3,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.$4,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Step 2: Restore Cards ---
  Widget _buildRestoreCards(bool isDark) {
    return Column(
      children: [
        // Option 1: File Restore
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.folderOpenOutline,
                  size: 24,
                  color: _purple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restore From Backup File',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select a JSON backup file exported previously from another RentManager installation.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _openRestoreSheet,
                icon: const Icon(Ionicons.cloudDownloadOutline, size: 16),
                label: const Text('Choose Backup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Option 2: Google Drive
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.logoGoogle,
                  size: 24,
                  color: Color(0xFF4285F4),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restore From Google Drive',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in to your Google Account to access automated cloud backups and sync records.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _handleGoogleSignIn,
                icon: const Icon(Icons.login, size: 16),
                label: const Text('Connect Drive'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA0D8D8)
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Starting Fresh Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Ionicons.sparklesOutline,
                color: Color(0xFF10B981),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Starting fresh? Simply click "Continue" below to start your new database!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 3: Manager Profile ---
  Widget _buildProfileCard(bool isDark) {
    return ProfileSetupForm(
      key: _managerFormKey,
      section: ProfileSection.manager,
      initial: _userProfile,
      isDark: isDark,
      onChanged: (p) => _userProfile = p,
    );
  }

  // --- Step 4: Property Info ---
  Widget _buildPropertyCard(bool isDark) {
    return ProfileSetupForm(
      key: _propertyFormKey,
      section: ProfileSection.property,
      initial: _userProfile,
      isDark: isDark,
      onChanged: (p) => _userProfile = p,
    );
  }

  // --- Step 5: Notifications ---
  Widget _buildNotificationCards(bool isDark) {
    final benefits = [
      (
        Ionicons.calendarOutline,
        'Rent Due Reminders',
        'Receive proactive alerts before payment deadlines so you can follow up with pending tenant collections.',
      ),
      (
        Ionicons.timeOutline,
        'Lease Expiration Notices',
        'Get notified 30 & 60 days before tenant agreements expire to plan renewals or unit turns.',
      ),
      (
        Ionicons.hammerOutline,
        'Maintenance & Work Orders',
        'Keep tabs on ongoing unit repairs, contractor estimates, and completed tenant maintenance tickets.',
      ),
    ];

    return Column(
      children: [
        for (final b in benefits)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x14000000),
              ),
            ),
            child: Row(
              children: [
                Icon(b.$1, size: 20, color: _orange),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.$3,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _requestNotifications,
              icon: const Icon(Ionicons.notifications, size: 16),
              label: const Text('Request Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Notification settings can be adjusted anytime in macOS Settings',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF718096)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Step 5: Bank Accounts ---
  Widget _buildBankCards(bool isDark) {
    if (_userBanks.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Ionicons.checkmarkCircle,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_userBanks.length} Bank Account${_userBanks.length == 1 ? '' : 's'} Configured',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _openBankSheet,
                  icon: const Icon(Ionicons.createOutline, size: 16),
                  label: const Text('Manage Banks'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final b in _userBanks)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F1B20) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Ionicons.cardOutline, size: 16, color: _purple),
                    const SizedBox(width: 10),
                    Text(
                      b.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${b.accountNumber ?? ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.businessOutline,
                  size: 26,
                  color: _purple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure Bank Accounts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add your checking or savings accounts to log where tenant rent checks are deposited.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _openBankSheet,
                icon: const Icon(Ionicons.addCircleOutline, size: 16),
                label: const Text('Add Bank Account...'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Optional — banks can be added anytime in Settings',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? const Color(0xFF718096)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Step 6: Currency Grid ---
  Widget _buildCurrencyCards(bool isDark) {
    // 8 popular currencies
    final popular = kCurrencyOptions.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Grid of Currencies
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.1,
          ),
          itemCount: popular.length,
          itemBuilder: (context, i) {
            final c = popular[i];
            final selected = _currency == c.symbol;

            return InkWell(
              onTap: () {
                setState(() => _currency = c.symbol);
                ref.read(appDataProvider.notifier).setCurrency(c.symbol);
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? (isDark
                            ? const Color(0xFF153328)
                            : const Color(0xFFDCFCE7))
                      : (isDark
                            ? const Color(0xFF132228)
                            : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF10B981)
                        : (isDark
                              ? const Color(0x1AFFFFFF)
                              : const Color(0x14000000)),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(c.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${c.symbol} ${c.code}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selected
                                  ? (isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF059669))
                                  : (isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A)),
                            ),
                          ),
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Ionicons.checkmarkCircle,
                        size: 16,
                        color: Color(0xFF10B981),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 14),

        // Live Preview Banner & More Currencies Button
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Ionicons.eyeOutline,
                    size: 15,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Preview: ${_currency}2,450 / mo',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => showCurrencySheet(
                context,
                current: _currency,
                onSelect: (c) {
                  setState(() => _currency = c);
                  ref.read(appDataProvider.notifier).setCurrency(c);
                },
              ),
              icon: const Icon(Ionicons.globeOutline, size: 16),
              label: const Text('More Currencies...'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                foregroundColor: isDark
                    ? const Color(0xFFA0D8D8)
                    : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Step 7: Appearance ---
  Widget _buildThemeCards(bool isDark) {
    final modes = [
      ('system', 'System', Ionicons.contrastOutline, 'Follows OS'),
      ('light', 'Light', Ionicons.sunnyOutline, 'Bright & clean'),
      ('dark', 'Dark', Ionicons.moonOutline, 'Easy on the eyes'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (mode, title, icon, hint) in modes) ...[
              if (mode != 'system') const SizedBox(width: 12),
              Expanded(child: _themeCard(isDark, mode, title, icon, hint)),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 15,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Applied instantly — you can change this anytime in Settings',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _themeCard(
    bool isDark,
    String mode,
    String title,
    IconData icon,
    String hint,
  ) {
    final selected = _themeMode == mode;
    const accent = Color(0xFF10B981);

    return InkWell(
      onTap: () {
        ref.read(appDataProvider.notifier).setThemeMode(mode);
        setState(() => _themeMode = mode);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.16 : 0.10)
              : (isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent
                : (isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000)),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _themePreview(mode),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? accent
                      : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? (isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669))
                              : (isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A)),
                        ),
                      ),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Ionicons.checkmarkCircle, size: 16, color: accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _themePreview(String mode) {
    const lightBg = Color(0xFFF8FAFC);
    const lightBar = Color(0xFFE2E8F0);
    const darkBg = Color(0xFF0F172A);
    const darkBar = Color(0x22FFFFFF);
    final accent = const Color(0xFF10B981);

    Widget mock(Color bg, Color bar, Color chip) => Container(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 3,
            decoration: BoxDecoration(
              color: chip,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 7),
          for (var i = 0; i < 3; i++) ...[
            FractionallySizedBox(
              widthFactor: i == 0 ? 0.9 : (i == 1 ? 0.7 : 0.5),
              alignment: Alignment.centerLeft,
              child: Container(
                height: 5,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: bar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          const SizedBox(height: 2),
          FractionallySizedBox(
            widthFactor: 0.4,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                color: chip,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );

    final lightHalf = mock(lightBg, lightBar, accent.withValues(alpha: 0.9));
    final darkHalf = mock(darkBg, darkBar, accent.withValues(alpha: 0.75));

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: mode == 'system'
            ? Row(
                children: [
                  Expanded(child: darkHalf),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: const Color(0x33000000),
                  ),
                  Expanded(child: lightHalf),
                ],
              )
            : mode == 'light'
            ? lightHalf
            : darkHalf,
      ),
    );
  }

  // --- Step 8: Completion Summary ---
  Widget _buildCompletionSummary(bool isDark) {
    final checklist = [
      'Encrypted local database initialized and ready for properties',
      'Primary currency symbol set to $_currency',
      _userProfile != null && _userProfile!.name.isNotEmpty
          ? 'Property manager profile registered (${_userProfile!.name})'
          : 'Profile ready to customize anytime in Settings',
      (_userProfile?.propertyName ?? '').isNotEmpty
          ? 'Property information added (${_userProfile!.propertyName})'
          : 'Property info ready to add anytime in Settings',
      _userBanks.isNotEmpty
          ? '${_userBanks.length} deposit bank accounts connected'
          : 'Bank accounts can be added anytime for payout routing',
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132228) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.checkmarkDone,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to Launch!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your RentManager desktop workstation is completely prepared.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          for (final item in checklist)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Ionicons.checkmarkCircle,
                    size: 18,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopPrimaryButton(
    BuildContext context,
    bool isDark,
    bool isLast,
  ) {
    return ElevatedButton.icon(
      onPressed: _next,
      icon: Icon(
        isLast ? Ionicons.checkmarkCircle : Ionicons.arrowForward,
        size: 18,
        color: AppColors.buttonPrimaryText,
      ),
      label: Text(
        isLast ? 'Launch RentManager' : 'Continue',
        style: const TextStyle(
          color: AppColors.buttonPrimaryText,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      ),
    );
  }

  // ===========================================================================
  // MOBILE FLOW LAYOUT (WIDTH < 840px)
  // ===========================================================================

  Widget _buildMobileLayout(
    BuildContext context,
    bool isDark,
    BoxConstraints constraints,
  ) {
    final steps = _steps;

    return Column(
      children: [
        _mobileHeader(isDark, steps),
        Expanded(
          child: PageView.builder(
            controller: _page,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: steps.length,
            itemBuilder: (_, i) => _stepMobileView(context, isDark, steps[i]),
          ),
        ),
        _mobileActionBar(context, isDark, steps),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE: header
  // ---------------------------------------------------------------------------
  Widget _mobileHeader(bool isDark, List<_Step> steps) {
    final progress = (_step + 1) / steps.length;
    final step = steps[_step];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1519) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x14FFFFFF) : const Color(0x14000000),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Ionicons.home, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _appName,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.heading,
                        letterSpacing: 0.1,
                      ),
                    ),
                    Text(
                      'Setup Assistant',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF34D399)
                            : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_step + 1} / ${steps.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    margin: EdgeInsets.only(
                      right: i == steps.length - 1 ? 0 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? _green
                          : (isDark
                                ? const Color(0x26FFFFFF)
                                : const Color(0x1A000000)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(step.icon, size: 13, color: step.color),
              const SizedBox(width: 6),
              Text(
                step.category,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}% complete',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFA0D8D8)
                      : const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE: sticky action bar
  // ---------------------------------------------------------------------------
  Widget _mobileActionBar(
    BuildContext context,
    bool isDark,
    List<_Step> steps,
  ) {
    final isLast = _step == steps.length - 1;
    final currentId = steps[_step].id;
    final showSkip =
        _step > 0 && !isLast && currentId != 3 && currentId != 4 && _step != 6;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        10,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1519) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_step > 0)
            SizedBox(
              height: 46,
              child: OutlinedButton(
                onPressed: () => _goTo(_step - 1),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0x33FFFFFF)
                        : const Color(0x22000000),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: isDark
                      ? const Color(0xFFA0D8D8)
                      : const Color(0xFF334155),
                ),
                child: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
            ),
          if (_step > 0) const SizedBox(width: 8),
          if (showSkip)
            TextButton(
              onPressed: _skip,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: isDark
                    ? const Color(0xFF718096)
                    : const Color(0xFF64748B),
              ),
              child: const Text(
                'Skip',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          const Spacer(),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _next,
                icon: Icon(
                  isLast ? Ionicons.checkmarkCircle : Ionicons.arrowForward,
                  size: 17,
                ),
                label: Text(
                  isLast ? 'Get Started' : 'Continue',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.buttonPrimaryText,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE: step canvas
  // ---------------------------------------------------------------------------
  Widget _stepMobileView(BuildContext context, bool isDark, _Step step) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 24),
      child: Column(
        children: [
          if (step.id != 3 && step.id != 4) ...[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [step.color, step.color.withValues(alpha: 0.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: step.color.withValues(alpha: 0.32),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(step.icon, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.heading,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _description(step),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: isDark
                    ? const Color(0xFFA0D8D8)
                    : const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 22),
          ],
          _mobileStepContent(context, isDark, step),
        ],
      ),
    );
  }

  Widget _mobileStepContent(BuildContext context, bool isDark, _Step step) {
    switch (step.id) {
      case 1:
        return _mobileWelcome(isDark);
      case 2:
        return _mobileRestore(isDark);
      case 3:
        return _mobileProfile(isDark);
      case 4:
        return _mobileProperty(isDark);
      case 5:
        return _mobileNotifications(isDark);
      case 6:
        return _mobileBanks(isDark);
      case 7:
        return _mobileCard(isDark, _currencyPicker(isDark));
      case 8:
        return _mobileThemeList(isDark);
      case 9:
        return _mobileCompletion(isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _mobileCard(bool isDark, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132228) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
        ),
      ),
      child: child,
    );
  }

  Widget _mobileStatusTile({
    required bool isDark,
    required bool done,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done
            ? _green.withValues(alpha: isDark ? 0.14 : 0.08)
            : (isDark ? const Color(0xFF132228) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? _green.withValues(alpha: 0.45)
              : (isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (done ? _green : color).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              done ? Ionicons.checkmarkCircle : icon,
              size: 21,
              color: done ? _green : color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: done
                        ? (isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669))
                        : AppColors.heading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _mobileWelcome(bool isDark) {
    final features = [
      (
        Ionicons.businessOutline,
        const Color(0xFF10B981),
        'Property & Unit Portfolio',
        'Manage properties, units, leases and tenant records in one place.',
      ),
      (
        Ionicons.receiptOutline,
        const Color(0xFF3B82F6),
        'Rent Invoicing & Expenses',
        'Track rent, invoices, payments and expenses automatically.',
      ),
      (
        Ionicons.shieldCheckmarkOutline,
        const Color(0xFF8B5CF6),
        '100% Offline Privacy',
        'Your data stays encrypted on this device — no account required.',
      ),
    ];

    return Column(
      children: [
        for (final (icon, color, title, desc) in features)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF132228) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x14000000),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mobileRestore(bool isDark) {
    return Column(
      children: [
        _mobileOptionTile(
          isDark: isDark,
          icon: Ionicons.documentOutline,
          color: _purple,
          title: 'Restore from backup file',
          subtitle: 'Import a RentManager JSON backup from this device',
          onTap: _openRestoreSheet,
        ),
        const SizedBox(height: 10),
        _mobileOptionTile(
          isDark: isDark,
          icon: Ionicons.logoGoogle,
          color: _blue,
          title: 'Sign in with Google Drive',
          subtitle: 'Pull the latest cloud backup linked to your account',
          onTap: _handleGoogleSignIn,
        ),
        const SizedBox(height: 14),
        Text(
          'This step is optional — you can restore your data anytime from Settings.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isDark ? const Color(0xFF718096) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _mobileOptionTile({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132228) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? const Color(0xFF718096) : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileProfile(bool isDark) {
    return ProfileSetupForm(
      key: _managerFormKey,
      section: ProfileSection.manager,
      initial: _userProfile,
      isDark: isDark,
      onChanged: (p) => _userProfile = p,
    );
  }

  Widget _mobileProperty(bool isDark) {
    return ProfileSetupForm(
      key: _propertyFormKey,
      section: ProfileSection.property,
      initial: _userProfile,
      isDark: isDark,
      onChanged: (p) => _userProfile = p,
    );
  }

  Widget _mobileNotifications(bool isDark) {
    final status = _notifStatus;
    final granted = status?.isGranted ?? false;
    final permanentlyDenied = status?.isPermanentlyDenied ?? false;

    return Column(
      children: [
        _mobileStatusTile(
          isDark: isDark,
          done: granted,
          icon: Ionicons.notificationsOutline,
          color: _orange,
          title: granted
              ? 'Notifications enabled'
              : 'Notifications not enabled',
          subtitle: granted
              ? 'You will receive rent due dates and lease alerts'
              : permanentlyDenied
              ? 'Permission blocked — enable it in system settings'
              : 'Allow alerts for rent due dates and lease expiry',
        ),
        const SizedBox(height: 14),
        if (!granted)
          _mobileActionButton(
            label: permanentlyDenied
                ? 'Open System Settings'
                : 'Allow Notifications',
            icon: permanentlyDenied
                ? Ionicons.settingsOutline
                : Ionicons.notificationsOutline,
            color: _orange,
            onTap: () async {
              if (permanentlyDenied) {
                await openAppSettings();
                await _refreshNotificationStatus();
                return;
              }
              await _requestNotifications();
            },
          ),
        const SizedBox(height: 10),
        Text(
          'You can change notification preferences later in Settings.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isDark ? const Color(0xFF718096) : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _mobileBanks(bool isDark) {
    final configured = _userBanks.isNotEmpty;
    return Column(
      children: [
        _mobileStatusTile(
          isDark: isDark,
          done: configured,
          icon: Ionicons.businessOutline,
          color: _purple,
          title: configured
              ? '${_userBanks.length} bank account${_userBanks.length == 1 ? '' : 's'} configured'
              : 'No bank accounts yet',
          subtitle: configured
              ? _userBanks.map((b) => b.name).take(3).join(' • ')
              : 'Optional — assign rent deposits to your bank accounts',
        ),
        const SizedBox(height: 14),
        _mobileActionButton(
          label: configured ? 'Manage Banks' : 'Set Up Banks',
          icon: Ionicons.businessOutline,
          color: _purple,
          onTap: _openBankSheet,
        ),
      ],
    );
  }

  Widget _mobileThemeList(bool isDark) {
    final modes = [
      ('system', 'System', 'Matches your device', Ionicons.contrastOutline),
      ('light', 'Light', 'Bright & clean', Ionicons.sunnyOutline),
      ('dark', 'Dark', 'Easy on the eyes', Ionicons.moonOutline),
    ];
    const accent = Color(0xFF10B981);

    return Column(
      children: [
        for (final (mode, title, hint, icon) in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                ref.read(appDataProvider.notifier).setThemeMode(mode);
                setState(() => _themeMode = mode);
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _themeMode == mode
                      ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
                      : (isDark
                            ? const Color(0xFF132228)
                            : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _themeMode == mode
                        ? accent
                        : (isDark
                              ? const Color(0x1AFFFFFF)
                              : const Color(0x14000000)),
                    width: _themeMode == mode ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: icon == Ionicons.moonOutline
                            ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                            : (icon == Ionicons.sunnyOutline
                                  ? const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15)
                                  : const Color(0xFF3B82F6)
                                        .withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 20,
                        color: _themeMode == mode
                            ? accent
                            : (isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: _themeMode == mode
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: _themeMode == mode
                                  ? (isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF059669))
                                  : AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hint,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _themeMode == mode
                          ? Ionicons.checkmarkCircle
                          : Ionicons.ellipseOutline,
                      size: 20,
                      color: _themeMode == mode
                          ? accent
                          : (isDark
                                ? const Color(0xFF4A5568)
                                : const Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Icon(Icons.bolt_rounded, size: 15, color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Applied instantly — you can change this anytime in Settings',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mobileCompletion(bool isDark) {
    final items = [
      (
        _userProfile != null && _userProfile!.name.trim().isNotEmpty,
        'Manager profile',
      ),
      (
        (_userProfile?.propertyName ?? '').trim().isNotEmpty,
        'Property information',
      ),
      (_notifStatus?.isGranted ?? false, 'Notifications permission'),
      (_userBanks.isNotEmpty, 'Bank accounts'),
      (true, 'Primary currency set to $_currency'),
      (true, 'Appearance preference saved'),
    ];

    return Column(
      children: [
        _mobileCard(
          isDark,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (done, label) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Ionicons.checkmarkCircle
                            : Ionicons.ellipseOutline,
                        size: 19,
                        color: done
                            ? _green
                            : (isDark
                                  ? const Color(0xFF718096)
                                  : const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: done
                                ? AppColors.heading
                                : (isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _green.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Ionicons.sparklesOutline, size: 20, color: _green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Everything is ready. Tap Get Started to open your workspace.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _description(_Step step) {
    if (step.title == 'Set Up Your Profile' &&
        _completed.contains(3) &&
        _userProfile != null) {
      return 'Your manager profile is configured for receipts and tenant records.';
    }
    if (step.title == 'Set Up Your Property' &&
        _completed.contains(4) &&
        _userProfile != null) {
      return 'Your property information is ready for listings and receipts.';
    }
    if (step.title == "You're All Set!" && _didRestore) {
      return 'Your data has been successfully restored. You can now start managing your properties with all your existing records.';
    }
    return step.desc;
  }

  Widget _currencyPicker(bool isDark) {
    const symbols = ['\$', '€', '£', '₹', '৳', '¥'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in symbols)
                GestureDetector(
                  onTap: () {
                    setState(() => _currency = s);
                    ref.read(appDataProvider.notifier).setCurrency(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _currency == s
                          ? const Color(0xFF10B981)
                          : (isDark
                                ? const Color(0x1AFFFFFF)
                                : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _currency == s
                            ? const Color(0xFF10B981)
                            : (isDark
                                  ? const Color(0x33FFFFFF)
                                  : const Color(0x24000000)),
                      ),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 16,
                        color: _currency == s
                            ? Colors.white
                            : (AppColors.heading),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Selected: $_currency',
            style: TextStyle(
              color: isDark ? const Color(0xFFA0D8D8) : const Color(0xFF059669),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  final int id;
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  final bool blockNext;
  final String category;
  const _Step(
    this.id,
    this.title,
    this.desc,
    this.icon,
    this.color,
    this.blockNext,
    this.category,
  );
}
