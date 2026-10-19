import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../services/auto_backup_service.dart';
import '../../services/biometric_auth.dart';
import '../../services/drive_backup_service.dart';

enum _SettingsCategory {
  profile('Profile & Property', 'Manager details & property assets', Ionicons.personCircleOutline),
  appearance('Appearance & Display', 'Theme, currency & workspace tabs', Ionicons.colorPaletteOutline),
  notifications('Notifications & Alerts', 'Due dates, expenses & summaries', Ionicons.notificationsOutline),
  security('Security & Privacy', 'Biometric lock & macOS system permissions', Ionicons.shieldCheckmarkOutline),
  backup('Cloud & Auto Backup', 'Google Drive sync & backup schedule', Ionicons.cloudUploadOutline),
  data('Data & Storage', 'Export, restore & database management', Ionicons.serverOutline),
  analytics('System Analytics', 'Full project statistics & metrics', Ionicons.analyticsOutline),
  support('Help & About', 'Documentation, privacy & app details', Ionicons.informationCircleOutline);

  final String title;
  final String subtitle;
  final IconData icon;
  const _SettingsCategory(this.title, this.subtitle, this.icon);
}

/// Modern macOS-styled System Preferences & Settings View for desktop.
class DesktopSettingsView extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onEditProfile;
  final VoidCallback? onPropertyDetails;
  final VoidCallback? onExportData;
  final VoidCallback? onImportData;
  final VoidCallback? onGoogleDrive;
  final VoidCallback? onFullStatistics;
  final VoidCallback? onHelpSupport;
  final VoidCallback? onPrivacyPolicy;
  final VoidCallback? onAbout;

  const DesktopSettingsView({
    super.key,
    this.onClose,
    this.onEditProfile,
    this.onPropertyDetails,
    this.onExportData,
    this.onImportData,
    this.onGoogleDrive,
    this.onFullStatistics,
    this.onHelpSupport,
    this.onPrivacyPolicy,
    this.onAbout,
  });

  @override
  ConsumerState<DesktopSettingsView> createState() =>
      _DesktopSettingsViewState();
}

class _DesktopSettingsViewState extends ConsumerState<DesktopSettingsView> {
  _SettingsCategory _selectedCategory = _SettingsCategory.profile;
  bool _fingerprintAvailable = false;
  bool _fingerprintLoading = true;
  bool _faceIdAvailable = false;
  bool _backupInProgress = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final isAvail = await BiometricAuth.isAvailable;
    final hasFp = await BiometricAuth.hasFingerprint;
    final hasFc = await BiometricAuth.hasFace;
    if (mounted) {
      setState(() {
        _fingerprintAvailable = isAvail || hasFp;
        _faceIdAvailable = isAvail || hasFc;
        _fingerprintLoading = false;
      });
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['x-apple.systempreferences:com.apple.preference.security?Privacy']);
        return;
      }
    } catch (_) {}
    try {
      await openAppSettings();
    } catch (_) {}
  }

  Future<void> _ensureNotificationPermission(BuildContext context) async {
    final status = await Permission.notification.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (context.mounted) {
        showAppToast(
          context,
          'Notification permission is disabled. Please enable it in macOS System Settings.',
          isError: true,
          actionLabel: 'Settings',
          onAction: () => _openSystemSettings(),
        );
      }
    }
  }

  String _currencyFlag(String symbol) {
    final hit = kCurrencyOptions.where((c) => c.symbol == symbol);
    return hit.isEmpty ? '🇺🇸' : hit.first.flag;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;

    return Container(
      color: isDark ? const Color(0xFF030D0E) : const Color(0xFFEDF4F3),
      child: Column(
        children: [
          // 1. Top Header Bar
          _buildTopBar(isDark),

          // 2. Main 2-Pane Preferences Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Category Selector Sidebar (macOS System Settings style)
                _buildCategorySidebar(isDark),

                // Active Setting Detail Panel
                Expanded(
                  child: Container(
                    color: isDark
                        ? const Color(0xFF061415).withValues(alpha: 0.6)
                        : const Color(0xFFF8FAFC),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: _buildSelectedCategoryContent(s, isDark),
                        ),
                      ),
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

  Widget _buildTopBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071E1F) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.08)
                : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Icon(Ionicons.settings, color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Preferences',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              Text(
                _selectedCategory.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (widget.onClose != null)
            _buildPrimaryButton(
              onPressed: widget.onClose,
              icon: Ionicons.checkmark,
              label: 'Done',
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySidebar(bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF051718).withValues(alpha: 0.95)
            : Colors.white,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        itemCount: _SettingsCategory.values.length,
        separatorBuilder: (context, index) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final cat = _SettingsCategory.values[index];
          final isSelected = cat == _selectedCategory;

          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = cat);
            },
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? const Color(0xFF0D9488).withValues(alpha: 0.20)
                        : const Color(0xFF059669).withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                              ? const Color(0xFF14B8A6)
                              : const Color(0xFF059669))
                          : (isDark
                              ? const Color(0xFF0C2425)
                              : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Center(
                      child: Icon(
                        cat.icon,
                        size: 13,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? (isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669))
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : const Color(0xFF1E293B)),
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
    );
  }

  Widget _buildSelectedCategoryContent(AppDataState s, bool isDark) {
    switch (_selectedCategory) {
      case _SettingsCategory.profile:
        return _buildProfileCategory(s, isDark);
      case _SettingsCategory.appearance:
        return _buildAppearanceCategory(s, isDark);
      case _SettingsCategory.notifications:
        return _buildNotificationsCategory(s, isDark);
      case _SettingsCategory.security:
        return _buildSecurityCategory(s, isDark);
      case _SettingsCategory.backup:
        return _buildBackupCategory(s, isDark);
      case _SettingsCategory.data:
        return _buildDataCategory(s, isDark);
      case _SettingsCategory.analytics:
        return _buildAnalyticsCategory(s, isDark);
      case _SettingsCategory.support:
        return _buildSupportCategory(s, isDark);
    }
  }

  // =================== 1. Profile & Property ===================

  Widget _buildProfileCategory(AppDataState s, bool isDark) {
    final pm = s.propertyManager;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Property Manager Profile',
            'Primary contact and credentials for notices, receipts, and leases', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        (pm?.name.isNotEmpty == true)
                            ? pm!.name.substring(0, 1).toUpperCase()
                            : 'M',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pm?.name.isNotEmpty == true
                              ? pm!.name
                              : 'Property Manager',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Ionicons.mailOutline,
                                size: 12.5,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B)),
                            const SizedBox(width: 5),
                            Text(
                              pm?.email.isNotEmpty == true
                                  ? pm!.email
                                  : 'No email specified',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Ionicons.callOutline,
                                size: 12.5,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B)),
                            const SizedBox(width: 5),
                            Text(
                              pm?.phone.isNotEmpty == true
                                  ? pm!.phone
                                  : 'No phone specified',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildPrimaryButton(
                    onPressed: widget.onEditProfile,
                    icon: Ionicons.createOutline,
                    label: 'Edit Profile',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Property Asset Information',
            'Building configuration, physical location, and unit count', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Property Name',
                subtitle: s.activeProperty?.name ?? pm?.propertyName ?? 'My Property',
                icon: Ionicons.businessOutline,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Address & Location',
                subtitle: s.activeProperty?.address.isNotEmpty == true
                    ? s.activeProperty!.address
                    : (pm?.address.isNotEmpty == true
                        ? pm!.address
                        : 'No address set'),
                icon: Ionicons.locationOutline,
                isDark: isDark,
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Total Units Registered',
                subtitle: () {
                  final activeUnits = s.scopedTenants.where((t) => t.status == 'active').length;
                  final totalUnits = (s.activeProperty != null && s.activeProperty!.totalUnits > 0
                      ? s.activeProperty!.totalUnits
                      : s.scopedTenants.map((t) => t.unit).where((u) => u.trim().isNotEmpty).toSet().length);
                  return '$totalUnits Units registered • $activeUnits Active leases';
                }(),
                icon: Ionicons.homeOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: widget.onPropertyDetails,
                  icon: Ionicons.businessOutline,
                  label: 'Update Details',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 2. Appearance & Display ===================

  Widget _buildAppearanceCategory(AppDataState s, bool isDark) {
    final p = s.preferences;
    final notifier = ref.read(appDataProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Visual Theme',
            'Choose between dark, light, or follow your macOS system preference', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Theme Mode',
                subtitle: p.themeMode == 'light'
                    ? 'Light theme active'
                    : p.themeMode == 'system'
                        ? 'Follow macOS system appearance'
                        : 'Dark theme active',
                icon: p.themeMode == 'light'
                    ? Ionicons.sunny
                    : p.themeMode == 'system'
                        ? Ionicons.contrast
                        : Ionicons.moon,
                isDark: isDark,
                trailing: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0C2425)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.08)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _themePill('dark', Ionicons.moon, 'Dark', p.themeMode,
                          () => notifier.setPreferences(p.copyWith(themeMode: 'dark'))),
                      _themePill('light', Ionicons.sunny, 'Light', p.themeMode,
                          () => notifier.setPreferences(p.copyWith(themeMode: 'light'))),
                      _themePill('system', Ionicons.contrast, 'System', p.themeMode,
                          () => notifier.setPreferences(p.copyWith(themeMode: 'system'))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Regional Currency & Format',
            'Set the primary currency symbol for financial reports and rent rolls', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Currency Symbol',
                subtitle: 'Active: ${_currencyFlag(s.selectedCurrency)} ${s.selectedCurrency}',
                icon: Ionicons.cashOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: () => showCurrencySheet(
                    context,
                    current: s.selectedCurrency,
                    onSelect: notifier.setCurrency,
                  ),
                  leadingWidget: Text(_currencyFlag(s.selectedCurrency),
                      style: const TextStyle(fontSize: 14)),
                  label: '${s.selectedCurrency}  ▾',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Workspace Modules',
            'Toggle optional modules in the desktop navigation sidebar', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Zakat Financial Module',
                subtitle: 'Show Islamic wealth calculation & distribution tab',
                icon: Ionicons.pricetagOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.showZakat,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) =>
                      notifier.setPreferences(p.copyWith(showZakat: v)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 3. Notifications & Alerts ===================

  Widget _buildNotificationsCategory(AppDataState s, bool isDark) {
    final p = s.preferences;
    final notifier = ref.read(appDataProvider.notifier);
    final masterNotif = p.notifRentDue ||
        p.notifWorkOrder ||
        p.notifExpense ||
        p.notifMaintenance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Master Notification Switch',
            'Global control for all rent collection and maintenance notifications', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Push Notifications',
                subtitle: 'Receive alerts for upcoming rent due dates and work orders',
                icon: Ionicons.notificationsOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: masterNotif,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(
                      p.copyWith(
                        notifRentDue: v,
                        notifWorkOrder: v,
                        notifExpense: v,
                        notifMaintenance: v,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Granular Notification Triggers',
            'Configure individual alerts for each domain', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Rent Due Reminders',
                subtitle: 'Alert 3 days and 1 day prior to lease billing date',
                icon: Ionicons.calendarOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.notifRentDue,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(p.copyWith(notifRentDue: v));
                  },
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Work Order Status Changes',
                subtitle: 'Alert when a repair is started or resolved',
                icon: Ionicons.constructOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.notifWorkOrder,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(p.copyWith(notifWorkOrder: v));
                  },
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Expense Logging Alerts',
                subtitle: 'Alert whenever property expenses exceed normal limits',
                icon: Ionicons.cardOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.notifExpense,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(p.copyWith(notifExpense: v));
                  },
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Maintenance Schedules',
                subtitle: 'Remind on routine inspection schedules',
                icon: Ionicons.hammerOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.notifMaintenance,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(p.copyWith(notifMaintenance: v));
                  },
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Daily Digest & Summaries',
                subtitle: 'Receive a daily 9:00 AM summary of pending items',
                icon: Ionicons.documentTextOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.notifDaily,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) async {
                    if (v) await _ensureNotificationPermission(context);
                    notifier.setPreferences(p.copyWith(notifDaily: v));
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 4. Security & Biometrics ===================

  Widget _buildSecurityCategory(AppDataState s, bool isDark) {
    final p = s.preferences;
    final notifier = ref.read(appDataProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Biometric Authentication',
            'Protect financial data and tenant documents with Touch ID / Face ID', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Touch ID / Fingerprint Lock',
                subtitle: _fingerprintAvailable
                    ? 'Require fingerprint verification on application startup'
                    : 'Hardware not available or not configured on this Mac',
                icon: Ionicons.fingerPrintOutline,
                isDark: isDark,
                trailing: _fingerprintLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch.adaptive(
                        value: p.biometricLock && _fingerprintAvailable,
                        activeTrackColor: const Color(0xFF059669),
                        onChanged: _fingerprintAvailable
                            ? (v) async {
                                if (v) {
                                  final ok = await BiometricAuth.authenticate(
                                    localizedReason:
                                        'Scan fingerprint to enable app lock',
                                  );
                                  if (!ok) {
                                    if (mounted) {
                                      showAppToast(context,
                                          'Authentication cancelled or not recognized',
                                          isError: true);
                                    }
                                    return;
                                  }
                                }
                                notifier.setPreferences(
                                    p.copyWith(biometricLock: v));
                                if (mounted) {
                                  showAppToast(
                                    context,
                                    v
                                        ? 'Touch ID lock enabled'
                                        : 'Biometric lock disabled',
                                    isSuccess: v,
                                  );
                                }
                              }
                            : null,
                      ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Face ID / Camera Biometrics',
                subtitle: _faceIdAvailable
                    ? 'Unlock via facial recognition'
                    : 'Face ID not supported on this device',
                icon: Ionicons.scanOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.biometricLock && _faceIdAvailable,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: _faceIdAvailable
                      ? (v) async {
                          if (v) {
                            final ok = await BiometricAuth.authenticate(
                              localizedReason: 'Scan face to enable app lock',
                            );
                            if (!ok) {
                              if (mounted) {
                                showAppToast(context,
                                    'Face authentication cancelled',
                                    isError: true);
                              }
                              return;
                            }
                          }
                          notifier.setPreferences(
                              p.copyWith(biometricLock: v));
                          if (mounted) {
                            showAppToast(
                              context,
                              v
                                  ? 'Face ID lock enabled'
                                  : 'Biometric lock disabled',
                              isSuccess: v,
                            );
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Privacy & System Access',
            'Configure app permissions, sandbox entitlements, and macOS system privacy', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'System Privacy & Permissions',
                subtitle: 'Open macOS System Settings to manage notifications and security access',
                icon: Ionicons.shieldCheckmarkOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: _openSystemSettings,
                  icon: Ionicons.openOutline,
                  label: 'Open Settings',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 5. Cloud & Auto Backup ===================

  Widget _buildBackupCategory(AppDataState s, bool isDark) {
    final p = s.preferences;
    final notifier = ref.read(appDataProvider.notifier);
    final autoDesc = p.autoBackup
        ? (p.lastBackup != null
            ? 'Last: ${fmtDate(p.lastBackup!)} | Next: ${AutoBackupService.nextLabel(s)}'
            : 'Automatic backups scheduled')
        : 'Keep your database safe with automated snapshots';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Automated Local Backups',
            'Schedule periodic background snapshots of all properties, tenants, and receipts', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Auto Backup System',
                subtitle: autoDesc,
                icon: Ionicons.cloudUploadOutline,
                isDark: isDark,
                trailing: Switch.adaptive(
                  value: p.autoBackup,
                  activeTrackColor: const Color(0xFF059669),
                  onChanged: (v) =>
                      notifier.setPreferences(p.copyWith(autoBackup: v)),
                ),
              ),
              if (p.autoBackup) ...[
                _buildDivider(isDark),
                _buildSettingRow(
                  title: 'Backup Frequency',
                  subtitle: 'Choose frequency interval',
                  icon: Ionicons.calendarOutline,
                  isDark: isDark,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _frequencyPill(
                        'Weekly',
                        p.backupSchedule == 'weekly',
                        isDark,
                        () => notifier.setPreferences(
                            p.copyWith(backupSchedule: 'weekly')),
                      ),
                      const SizedBox(width: 8),
                      _frequencyPill(
                        'Monthly',
                        p.backupSchedule == 'monthly',
                        isDark,
                        () => notifier.setPreferences(
                            p.copyWith(backupSchedule: 'monthly')),
                      ),
                    ],
                  ),
                ),
                _buildDivider(isDark),
                _buildSettingRow(
                  title: 'Manual Snapshot',
                  subtitle: _backupInProgress
                      ? 'Compiling backup archive...'
                      : 'Take a complete snapshot immediately',
                  icon: Ionicons.refreshOutline,
                  isDark: isDark,
                  trailing: _buildPrimaryButton(
                    onPressed: _backupInProgress
                        ? null
                        : () async {
                            setState(() => _backupInProgress = true);
                            final name =
                                await AutoBackupService.runNow(ref);
                            if (mounted) {
                              setState(() => _backupInProgress = false);
                              showAppToast(
                                context,
                                name == null
                                    ? 'Backup failed'
                                    : 'Backup completed: $name',
                                isError: name == null,
                                isSuccess: name != null,
                              );
                            }
                          },
                    iconWidget: _backupInProgress
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : null,
                    icon: _backupInProgress ? null : Ionicons.flashOutline,
                    label: _backupInProgress ? 'Backing Up...' : 'Run Now',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Google Drive Cloud Backup',
            'Synchronize encrypted database snapshots directly with your Google Drive account', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Google Drive Sync',
                subtitle: !DriveBackupService.isSignedIn
                    ? 'Connect Google account to enable cloud synchronization'
                    : (p.driveAutoSync
                        ? 'Connected • Frequency: ${p.driveSyncFrequency} • Last: ${DriveBackupService.formatTimeAgo(p.lastDriveSync)}'
                        : 'Google account connected (sync paused)'),
                icon: Ionicons.logoGoogle,
                iconColor: const Color(0xFF4285F4),
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: widget.onGoogleDrive,
                  icon: Ionicons.logoGoogle,
                  accentColor: const Color(0xFF4285F4),
                  label: DriveBackupService.isSignedIn
                      ? 'Drive Settings'
                      : 'Connect Drive',
                ),
              ),
              if (DriveBackupService.isSignedIn) ...[
                _buildDivider(isDark),
                _buildSettingRow(
                  title: 'Cloud Auto-Sync',
                  subtitle: 'Automatically upload snapshots when changes occur',
                  icon: Ionicons.syncOutline,
                  isDark: isDark,
                  trailing: Switch.adaptive(
                    value: p.driveAutoSync,
                    activeTrackColor: const Color(0xFF059669),
                    onChanged: (v) {
                      notifier
                          .setPreferences(p.copyWith(driveAutoSync: v));
                      if (v) {
                        unawaited(DriveBackupService.syncNow(ref));
                      }
                    },
                  ),
                ),
                if (p.driveAutoSync) ...[
                  _buildDivider(isDark),
                  _buildSettingRow(
                    title: 'Drive Sync Frequency',
                    subtitle: 'Choose when data syncs to Google Drive',
                    icon: Ionicons.timerOutline,
                    isDark: isDark,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _frequencyPill(
                          'On Change',
                          p.driveSyncFrequency == 'on_change',
                          isDark,
                          () => notifier.setPreferences(
                              p.copyWith(driveSyncFrequency: 'on_change')),
                        ),
                        const SizedBox(width: 8),
                        _frequencyPill(
                          'Daily',
                          p.driveSyncFrequency == 'daily',
                          isDark,
                          () => notifier.setPreferences(
                              p.copyWith(driveSyncFrequency: 'daily')),
                        ),
                        const SizedBox(width: 8),
                        _frequencyPill(
                          'Weekly',
                          p.driveSyncFrequency == 'weekly',
                          isDark,
                          () => notifier.setPreferences(
                              p.copyWith(driveSyncFrequency: 'weekly')),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =================== 6. Data & Storage ===================

  Widget _buildDataCategory(AppDataState s, bool isDark) {
    final notifier = ref.read(appDataProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Export & Import Tools',
            'Export database to portable JSON or restore data from an existing backup', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Export Database JSON',
                subtitle: 'Generate a complete JSON archive of all records, images, and logs',
                icon: Ionicons.downloadOutline,
                isDark: isDark,
                trailing: _buildPrimaryButton(
                  onPressed: widget.onExportData,
                  icon: Ionicons.downloadOutline,
                  label: 'Export JSON',
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Import & Restore Data',
                subtitle: 'Restore database state from a verified .json backup file',
                icon: Ionicons.cloudUploadOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: widget.onImportData,
                  icon: Ionicons.cloudUploadOutline,
                  label: 'Import File',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Danger Zone',
            'Irreversible administrative actions that affect the entire database', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          borderColor: isDark
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.25),
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Reset Application Data',
                subtitle: 'Permanently wipe all tenants, payments, receipts, and reset to defaults',
                icon: Ionicons.trashOutline,
                iconColor: const Color(0xFFEF4444),
                isDark: isDark,
                trailing: _buildPrimaryButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      'Reset All Data',
                      'Are you sure you want to completely reset the application? All tenants, payment history, and documents will be permanently cleared. This cannot be undone.',
                    );
                    if (ok) {
                      await notifier.resetApp();
                      if (mounted) {
                        showAppToast(context, 'Application reset to factory defaults', isSuccess: true);
                        widget.onClose?.call();
                      }
                    }
                  },
                  icon: Ionicons.alertCircleOutline,
                  label: 'Reset App',
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 7. System Analytics ===================

  Widget _buildAnalyticsCategory(AppDataState s, bool isDark) {
    final paid = s.scopedPayments
        .where((p) => p.status == 'paid')
        .fold<double>(0, (a, p) => a + p.amount);
    final expenses =
        s.scopedExpenses.fold<double>(0, (a, e) => a + e.amount);
    final activeTenants =
        s.scopedTenants.where((t) => t.status == 'active').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Executive Statistics Summary',
            'High-level operational overview across all portfolio modules', isDark),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Total Tenants',
                '${s.scopedTenants.length}',
                '$activeTenants Active Leases',
                Ionicons.peopleOutline,
                const Color(0xFF0D9488),
                isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'Rent Collected',
                fmtMoney(s.selectedCurrency, paid),
                '${s.scopedPayments.length} Payments logged',
                Ionicons.cashOutline,
                const Color(0xFF059669),
                isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'Expenses Logged',
                fmtMoney(s.selectedCurrency, expenses),
                '${s.scopedExpenses.length} Expense entries',
                Ionicons.receiptOutline,
                const Color(0xFFDC2626),
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Work Orders',
                '${s.scopedWorkOrders.length}',
                '${s.scopedWorkOrders.where((w) => w.status != 'completed').length} Open maintenance',
                Ionicons.constructOutline,
                const Color(0xFFD97706),
                isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'Vault Documents',
                '${s.scopedDocuments.length}',
                '${s.documentGroups.length} Categories',
                Ionicons.folderOpenOutline,
                const Color(0xFF2563EB),
                isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                'Banking Accounts',
                '${s.banks.length}',
                '${s.bankDeposits.length} Bank records',
                Ionicons.cardOutline,
                const Color(0xFF7C3AED),
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Comprehensive Project Analytics Sheet',
            'Inspect deep historical financial performance, occupancy ratios, and metrics', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Full Analytics Breakdown',
                subtitle: 'Open the detailed statistical modal with complete breakdowns',
                icon: Ionicons.analyticsOutline,
                isDark: isDark,
                trailing: _buildPrimaryButton(
                  onPressed: widget.onFullStatistics,
                  icon: Ionicons.barChartOutline,
                  label: 'View Full Analytics',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== 8. Help & About ===================

  Widget _buildSupportCategory(AppDataState s, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('About Rent Manager',
            'Application version, architecture, and system build information', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Ionicons.business, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rent Manager Pro',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Version 1.0.6 • macOS Desktop Edition',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildSecondaryButton(
                    onPressed: widget.onAbout,
                    icon: Ionicons.informationCircleOutline,
                    label: 'App Details',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Help & Documentation',
            'Guides on recording rent, importing data, and property configuration', isDark),
        const SizedBox(height: 8),
        _buildCard(
          isDark: isDark,
          child: Column(
            children: [
              _buildSettingRow(
                title: 'Help & Support Guide',
                subtitle: 'Read common questions, tutorials, and operational guides',
                icon: Ionicons.helpCircleOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: widget.onHelpSupport,
                  icon: Ionicons.bookOutline,
                  label: 'Read Guide',
                ),
              ),
              _buildDivider(isDark),
              _buildSettingRow(
                title: 'Privacy Policy',
                subtitle: 'Local-first architecture guarantee and data confidentiality',
                icon: Ionicons.documentTextOutline,
                isDark: isDark,
                trailing: _buildSecondaryButton(
                  onPressed: widget.onPrivacyPolicy,
                  icon: Ionicons.documentTextOutline,
                  label: 'View Policy',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================== Common Widgets ===================

  Widget _buildPrimaryButton({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    Widget? iconWidget,
    List<Color>? gradientColors,
    bool isDestructive = false,
  }) {
    final isDark = AppColors.isDark;
    final colors = isDestructive
        ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
        : gradientColors ??
            (isDark
                ? const [Color(0xFF0F766E), Color(0xFF0D9488)]
                : const [Color(0xFF0F766E), Color(0xFF059669)]);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onPressed == null
                  ? [Colors.grey.shade600, Colors.grey.shade700]
                  : colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: isDark ? 0.35 : 0.22),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (iconWidget != null) ...[
                iconWidget,
                const SizedBox(width: 5),
              ] else if (icon != null) ...[
                Icon(icon, size: 13, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    Widget? leadingWidget,
    Color? accentColor,
  }) {
    final isDark = AppColors.isDark;
    final baseColor = accentColor ??
        (isDark ? const Color(0xFF34D399) : const Color(0xFF059669));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: isDark
            ? baseColor.withValues(alpha: 0.15)
            : baseColor.withValues(alpha: 0.08),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? (accentColor != null
                      ? [accentColor.withValues(alpha: 0.22), accentColor.withValues(alpha: 0.12)]
                      : const [Color(0xFF143B3C), Color(0xFF0D292A)])
                  : (accentColor != null
                      ? [accentColor.withValues(alpha: 0.14), accentColor.withValues(alpha: 0.06)]
                      : const [Color(0xFFF6FBF8), Color(0xFFE5F3ED)]),
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark
                  ? (accentColor != null
                      ? accentColor.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.08))
                  : (accentColor != null
                      ? accentColor.withValues(alpha: 0.28)
                      : const Color(0xFFCBD5E1).withValues(alpha: 0.75)),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: 5),
              ] else if (icon != null) ...[
                Icon(icon, size: 13, color: baseColor),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: baseColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppColors.heading,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required Widget child,
    required bool isDark,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071C1D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor ??
              (isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0)),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required bool isDark,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0C2425)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 14,
                color: iconColor ??
                    (isDark
                        ? const Color(0xFF14B8A6)
                        : const Color(0xFF059669)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.heading,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing is Switch
                ? Transform.scale(
                    scale: 0.82,
                    alignment: Alignment.centerRight,
                    child: trailing,
                  )
                : trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.06)
            : const Color(0xFFF1F5F9),
        height: 1,
      ),
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071C1D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.08)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _themePill(
    String mode,
    IconData icon,
    String label,
    String current,
    VoidCallback onTap,
  ) {
    final active = current == mode;
    final isDark = AppColors.isDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.30),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: active
                  ? Colors.white
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? Colors.white
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frequencyPill(
    String label,
    bool active,
    bool isDark,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active
              ? null
              : (isDark ? const Color(0xFF0A2021) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(5),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.30),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? Colors.white
                : (isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }
}
