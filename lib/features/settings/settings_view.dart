import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_info.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../services/auto_backup_service.dart';
import '../../services/biometric_auth.dart';
import '../../services/drive_backup_service.dart';
import '../../services/update_service.dart';
import '../permissions/permissions_view.dart';
import '../desktop/desktop_settings_view.dart';
import '../desktop/desktop_property_modal.dart';

/// Exact port of `src/screens/SettingsScreen.tsx` — presented as a
/// full-height bottom sheet (dim backdrop + handle + header) matching the
/// Expo `Modal` layout. Six sections: Profile Management, Preferences,
/// Notification Settings, Data Management, Project Statistics, Support.
class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  const SettingsView({super.key, this.onClose});

  static final GlobalKey<SettingsViewState> globalKey =
      GlobalKey<SettingsViewState>();

  static void showEditProfile(BuildContext context) {
    globalKey.currentState?._editProfileSheet(context);
  }

  static void showPropertyDetails(BuildContext context) {
    globalKey.currentState?._propertyDetailsSheet(context);
  }

  static void showExport(BuildContext context) {
    globalKey.currentState?._exportSheet(context);
  }

  static void showImport(BuildContext context) {
    globalKey.currentState?._importSheet(context);
  }

  static void showDrive(BuildContext context) {
    globalKey.currentState?._driveSheet(context);
  }

  static void showStatistics(BuildContext context) {
    final s = globalKey.currentState?.ref.read(appDataProvider);
    if (s != null) {
      globalKey.currentState?._statisticsSheet(context, s);
    }
  }

  static void showHelp(BuildContext context) {
    globalKey.currentState?._helpSheet(context);
  }

  static void showPrivacy(BuildContext context) {
    globalKey.currentState?._privacySheet(context);
  }

  static void showAbout(BuildContext context) {
    globalKey.currentState?._aboutSheet(context);
  }

  @override
  ConsumerState<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends ConsumerState<SettingsView> {
  bool _fingerprintAvailable = false;
  bool _fingerprintLoading = true;
  bool _faceIdAvailable = false;
  bool _backupInProgress = false;

  Future<void> _ensureNotificationPermission(BuildContext context) async {
    final status = await Permission.notification.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (context.mounted) {
        showAppToast(
          context,
          'Notification permission is disabled. Please enable it in Settings.',
          isError: true,
          actionLabel: 'Settings',
          onAction: () => openAppSettings(),
        );
      }
    }
  }

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

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Widget _header(BuildContext context, bool isDark, double topPadding) {
    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 6,
        bottom: 12,
        left: 14,
        right: 14,
      ),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF071C1C),
                  Color(0xFF0D2B2B),
                  Color(0xFF133B3B),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F766E), // Rich teal
                  Color(0xFF059669), // Vibrant emerald
                  Color(0xFF10B981), // Fresh lively jade
                ],
              ),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.08)
                : const Color(0xFF047857),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF059669).withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Glassmorphic back button
          GestureDetector(
            onTap: _handleClose,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.08)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.12)
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              child: const Center(
                child: Icon(Ionicons.arrowBack, size: 20, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Settings Icon Badge
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : Colors.white.withValues(alpha: 0.22),
              border: Border.all(
                color: isDark ? AppColors.primary : Colors.white,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Ionicons.settings,
                size: 20,
                color: isDark ? AppColors.primary : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Center: Title + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Preferences & system configurations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textSecondary
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopSettingsView(
        onClose: widget.onClose ?? _handleClose,
        onEditProfile: () => _editProfileSheet(context),
        onPropertyDetails: () => _propertyDetailsSheet(context),
        onExportData: () => _exportSheet(context),
        onImportData: () => _importSheet(context),
        onGoogleDrive: () => _driveSheet(context),
        onFullStatistics: () => _statisticsSheet(context, s),
        onHelpSupport: () => _helpSheet(context),
        onPrivacyPolicy: () => _privacySheet(context),
        onAbout: () => _aboutSheet(context),
      );
    }

    final isDark = AppColors.isDark;
    final topPadding = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: Column(
            children: [
              _header(context, isDark, topPadding),
              // Settings sections list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    12,
                    10,
                    MediaQuery.of(context).padding.bottom + 32,
                  ),
                  children: [
                    _profileManagementSection(context, s),
                    _preferencesSection(context, s),
                    _notificationSection(s),
                    _dataManagementSection(context),
                    _projectStatisticsSection(context, s),
                    _supportSection(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ Section builders ============

  Widget _profileManagementSection(BuildContext context, AppDataState s) {
    return _section('Profile Management', [
      _item(
        icon: Ionicons.person,
        label: 'Edit Profile',
        desc: 'Update property manager details',
        onTap: () => _editProfileSheet(context),
      ),
      _item(
        icon: Ionicons.location,
        label: 'Property Details',
        desc: 'Update property information',
        onTap: () => _propertyDetailsSheet(context),
      ),
      _item(
        icon: Ionicons.business,
        label: 'Manage Properties',
        desc: 'Add, edit, or switch portfolio properties',
        onTap: () => _managePropertiesSheet(context, s),
      ),
    ]);
  }

  Widget _preferencesSection(BuildContext context, AppDataState s) {
    final p = s.preferences;
    final autoDesc = p.autoBackup
        ? (p.lastBackup != null
              ? 'Last: ${fmtDate(p.lastBackup!)} | Next: ${AutoBackupService.nextLabel(s)}'
              : 'Automatically backing up data')
        : 'Automatically backup data';
    return _section('Preferences', [
      _item(
        icon: p.themeMode == 'light'
            ? Ionicons.sunny
            : p.themeMode == 'system'
            ? Ionicons.contrast
            : Ionicons.moon,
        iconColor: AppColors.primary,
        label: 'Theme Mode',
        desc: p.themeMode == 'light'
            ? 'Light theme active'
            : p.themeMode == 'system'
            ? 'Follow device system theme'
            : 'Dark theme active',
        trailing: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.isDark
                ? const Color.fromRGBO(255, 255, 255, 0.05)
                : const Color(0xFFF0F4F4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _themeButton('dark', Ionicons.moon, 'Dark', p.themeMode),
              _themeButton('light', Ionicons.sunny, 'Light', p.themeMode),
              _themeButton('system', Ionicons.contrast, 'System', p.themeMode),
            ],
          ),
        ),
      ),
      _switchItem(
        icon: Ionicons.pricetag,
        label: 'Show Zakat Screen',
        desc: 'Toggle Zakat tab visibility',
        value: p.showZakat,
        onChanged: (v) => ref
            .read(appDataProvider.notifier)
            .setPreferences(p.copyWith(showZakat: v)),
      ),
      _switchItem(
        icon: Ionicons.notifications,
        label: 'Push Notifications',
        desc: 'Receive alerts for rent due dates and property updates',
        value:
            p.notifRentDue ||
            p.notifWorkOrder ||
            p.notifExpense ||
            p.notifMaintenance,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          ref
              .read(appDataProvider.notifier)
              .setPreferences(
                p.copyWith(
                  notifRentDue: v,
                  notifWorkOrder: v,
                  notifExpense: v,
                  notifMaintenance: v,
                ),
              );
        },
      ),
      _switchItem(
        icon: Ionicons.cloudUpload,
        label: 'Auto Backup',
        desc: autoDesc,
        value: p.autoBackup,
        onChanged: (v) => ref
            .read(appDataProvider.notifier)
            .setPreferences(p.copyWith(autoBackup: v)),
      ),
      if (p.autoBackup)
        _item(
          icon: Ionicons.calendar,
          label: 'Backup Schedule',
          desc: 'Choose how often to backup your data',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scheduleButton(
                'Weekly',
                p.backupSchedule == 'weekly',
                () => ref
                    .read(appDataProvider.notifier)
                    .setPreferences(p.copyWith(backupSchedule: 'weekly')),
              ),
              const SizedBox(width: 8),
              _scheduleButton(
                'Monthly',
                p.backupSchedule == 'monthly',
                () => ref
                    .read(appDataProvider.notifier)
                    .setPreferences(p.copyWith(backupSchedule: 'monthly')),
              ),
            ],
          ),
        ),
      _switchItem(
        icon: Ionicons.logoGoogle,
        iconColor: const Color(0xFF4285F4),
        label: 'Google Drive Auto-Sync',
        desc: !DriveBackupService.isSignedIn
            ? 'Sign in to automatically sync data to Google Drive'
            : (p.driveAutoSync
                  ? 'Auto-syncing (${p.driveSyncFrequency == 'on_change' ? 'On Change' : p.driveSyncFrequency}) • Last: ${DriveBackupService.formatTimeAgo(p.lastDriveSync)}'
                  : 'Automatically sync backups to Google Drive'),
        value: p.driveAutoSync,
        onChanged: (v) async {
          if (v && !DriveBackupService.isSignedIn) {
            _driveSheet(context);
            return;
          }
          ref
              .read(appDataProvider.notifier)
              .setPreferences(p.copyWith(driveAutoSync: v));
          if (v) {
            unawaited(DriveBackupService.syncNow(ref));
          }
        },
      ),
      if (p.driveAutoSync && DriveBackupService.isSignedIn)
        _item(
          icon: Ionicons.timerOutline,
          label: 'Drive Sync Frequency',
          desc: 'Choose when data syncs to Google Drive',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scheduleButton(
                'On Change',
                p.driveSyncFrequency == 'on_change',
                () => ref
                    .read(appDataProvider.notifier)
                    .setPreferences(
                      p.copyWith(driveSyncFrequency: 'on_change'),
                    ),
              ),
              const SizedBox(width: 6),
              _scheduleButton(
                'Daily',
                p.driveSyncFrequency == 'daily',
                () => ref
                    .read(appDataProvider.notifier)
                    .setPreferences(p.copyWith(driveSyncFrequency: 'daily')),
              ),
              const SizedBox(width: 6),
              _scheduleButton(
                'Weekly',
                p.driveSyncFrequency == 'weekly',
                () => ref
                    .read(appDataProvider.notifier)
                    .setPreferences(p.copyWith(driveSyncFrequency: 'weekly')),
              ),
            ],
          ),
        ),
      if (p.autoBackup)
        _item(
          icon: Ionicons.refresh,
          iconColor: _backupInProgress
              ? AppColors.iconMuted
              : AppColors.primary,
          label: _backupInProgress ? 'Backing up...' : 'Manual Backup',
          labelColor: _backupInProgress ? AppColors.iconMuted : null,
          desc: _backupInProgress
              ? 'Please wait while backup is in progress'
              : 'Trigger backup now and get notification',
          onTap: _backupInProgress
              ? null
              : () async {
                  setState(() => _backupInProgress = true);
                  final name = await AutoBackupService.runNow(ref);
                  if (mounted) {
                    setState(() => _backupInProgress = false);
                  }
                  if (context.mounted) {
                    showAppToast(
                      context,
                      name == null ? 'Backup failed' : 'Backup complete: $name',
                      isError: name == null,
                      isSuccess: name != null,
                    );
                  }
                },
        ),
      _item(
        icon: Ionicons.shield,
        label: 'App Permissions',
        desc: 'Manage camera, location, and other permissions',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsView()),
        ),
      ),
      _switchItem(
        icon: Ionicons.fingerPrint,
        iconColor: _fingerprintAvailable
            ? AppColors.primary
            : AppColors.iconMuted,
        label: 'Fingerprint Lock',
        desc: _fingerprintAvailable
            ? 'Use fingerprint to unlock the app'
            : 'Not available on this device',
        value: p.biometricLock && _fingerprintAvailable,
        enabled: _fingerprintAvailable && !_fingerprintLoading,
        trailing: _fingerprintLoading
            ? const Icon(Ionicons.hourglass, size: 16, color: AppColors.primary)
            : null,
        onChanged: (v) async {
          if (v) {
            final ok = await BiometricAuth.authenticate(
              localizedReason: 'Scan fingerprint to enable app lock',
            );
            if (!ok) {
              if (context.mounted) {
                showAppToast(
                  context,
                  'Fingerprint authentication cancelled or not recognized',
                  isError: true,
                );
              }
              return;
            }
          }
          ref
              .read(appDataProvider.notifier)
              .setPreferences(p.copyWith(biometricLock: v));
          if (context.mounted) {
            showAppToast(
              context,
              v ? 'Fingerprint lock enabled' : 'Biometric lock disabled',
              isSuccess: v,
            );
          }
        },
      ),
      _switchItem(
        icon: Ionicons.eye,
        iconColor: _faceIdAvailable ? AppColors.primary : AppColors.iconMuted,
        label: 'Face ID Lock',
        desc: _faceIdAvailable
            ? 'Use Face ID to unlock the app'
            : 'Not available on this device',
        value: p.biometricLock && _faceIdAvailable,
        enabled: _faceIdAvailable && !_fingerprintLoading,
        trailing: _fingerprintLoading
            ? const Icon(Ionicons.hourglass, size: 16, color: AppColors.primary)
            : null,
        onChanged: (v) async {
          if (v) {
            final ok = await BiometricAuth.authenticate(
              localizedReason: 'Scan face or biometrics to enable app lock',
            );
            if (!ok) {
              if (context.mounted) {
                showAppToast(
                  context,
                  'Face authentication cancelled or not recognized',
                  isError: true,
                );
              }
              return;
            }
          }
          ref
              .read(appDataProvider.notifier)
              .setPreferences(p.copyWith(biometricLock: v));
          if (context.mounted) {
            showAppToast(
              context,
              v ? 'Face ID lock enabled' : 'Biometric lock disabled',
              isSuccess: v,
            );
          }
        },
      ),
      _item(
        icon: Ionicons.cash,
        label: 'Currency Symbol',
        desc: 'Select your preferred currency',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currencyFlag(s.selectedCurrency),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 4),
            Text(
              s.selectedCurrency,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Ionicons.chevronDown,
              size: 16,
              color: AppColors.primary,
            ),
          ],
        ),
        onTap: () => showCurrencySheet(
          context,
          current: s.selectedCurrency,
          onSelect: ref.read(appDataProvider.notifier).setCurrency,
        ),
      ),
    ]);
  }

  Widget _notificationSection(AppDataState s) {
    final p = s.preferences;
    final n = ref.read(appDataProvider.notifier);
    return _section('Notification Settings', [
      _switchItem(
        icon: Ionicons.calendar,
        label: 'Rent Due Reminders',
        desc: 'Get notified before rent is due',
        value: p.notifRentDue,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          n.setPreferences(p.copyWith(notifRentDue: v));
        },
      ),
      _switchItem(
        icon: Ionicons.construct,
        label: 'Work Order Updates',
        desc: 'Get notified about work order changes',
        value: p.notifWorkOrder,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          n.setPreferences(p.copyWith(notifWorkOrder: v));
        },
      ),
      _switchItem(
        icon: Ionicons.card,
        label: 'Expense Alerts',
        desc: 'Get notified when expenses are added',
        value: p.notifExpense,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          n.setPreferences(p.copyWith(notifExpense: v));
        },
      ),
      _switchItem(
        icon: Ionicons.hammer,
        label: 'Maintenance Reminders',
        desc: 'Get notified about maintenance schedules',
        value: p.notifMaintenance,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          n.setPreferences(p.copyWith(notifMaintenance: v));
        },
      ),
      _switchItem(
        icon: Ionicons.notifications,
        label: 'Daily Summaries',
        desc: 'Get daily property management summaries',
        value: p.notifDaily,
        onChanged: (v) async {
          if (v) await _ensureNotificationPermission(context);
          n.setPreferences(p.copyWith(notifDaily: v));
        },
      ),
    ]);
  }

  Widget _dataManagementSection(BuildContext context) {
    return _section('Data Management', [
      _item(
        icon: Ionicons.download,
        label: 'Export Data',
        desc: 'Backup your data to a file',
        onTap: () => _exportSheet(context),
      ),
      _item(
        icon: Ionicons.cloudUpload,
        label: 'Import Data',
        desc: 'Restore data from a backup file',
        onTap: () => _importSheet(context),
      ),
      _item(
        icon: Ionicons.logoGoogle,
        label: 'Google Drive Backup',
        desc: 'Backup and restore data to Google Drive',
        onTap: () => _driveSheet(context),
      ),
      _item(
        icon: Ionicons.refresh,
        iconColor: AppColors.error,
        label: 'Reset App',
        labelColor: AppColors.error,
        desc: 'Clear all data and reset to defaults',
        danger: true,
        onTap: () async {
          final ok = await confirmDialog(
            context,
            'Reset App',
            'Clear all data and reset to defaults? This cannot be undone.',
          );
          if (ok) {
            await ref.read(appDataProvider.notifier).resetApp();
            _handleClose();
          }
        },
      ),
    ]);
  }

  Widget _projectStatisticsSection(BuildContext context, AppDataState s) {
    return _section('Project Statistics', [
      _item(
        icon: Ionicons.analytics,
        label: 'Full Project Statistics',
        desc: 'View comprehensive project data and analytics',
        onTap: () => _statisticsSheet(context, s),
      ),
    ]);
  }

  Widget _supportSection(BuildContext context) => _section('Support', [
    _item(
      icon: Ionicons.helpCircle,
      label: 'Help & Support',
      desc: 'Get help and contact support',
      onTap: () => _helpSheet(context),
    ),
    _item(
      icon: Ionicons.documentText,
      label: 'Privacy Policy',
      desc: 'Read our privacy policy',
      onTap: () => _privacySheet(context),
    ),
    _item(
      icon: Ionicons.informationCircle,
      label: 'About',
      desc: 'App version and information',
      onTap: () => _aboutSheet(context),
    ),
  ]);

  // ============ Shared item widgets ============

  Widget _section(String title, List<Widget> items) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 10));
      children.add(items[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    String? desc,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
    Color? iconColor,
    Color? labelColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            if (danger)
              Container(
                width: 3,
                height: 28,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Icon(
              icon,
              size: 20,
              color:
                  iconColor ?? (danger ? AppColors.error : AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: labelColor ?? AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (desc != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 8,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(
                Ionicons.chevronForward,
                size: 16,
                color: AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _switchItem({
    required IconData icon,
    required String label,
    String? desc,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    Color? iconColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color:
                iconColor ??
                (enabled ? AppColors.primary : AppColors.iconMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 8,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              SizedBox(
                height: 24,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Switch(
                    value: value,
                    onChanged: enabled ? onChanged : null,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFF666666),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _themeButton(
    String mode,
    IconData icon,
    String label,
    String currentMode,
  ) {
    final active = currentMode == mode;
    return GestureDetector(
      onTap: () => ref.read(appDataProvider.notifier).setThemeMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: active ? AppColors.primary : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? Colors.white : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleButton(String text, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: active ? Colors.white : AppColors.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );

  String _currencyFlag(String symbol) {
    final hit = kCurrencyOptions.where((c) => c.symbol == symbol);
    return hit.isEmpty ? '🇺🇸' : hit.first.flag;
  }

  // ============ Shared bottom-sheet frame ============

  void _showSheet(
    BuildContext context, {
    required String title,
    IconData? icon,
    required Widget body,
    List<Widget>? actions,
  }) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AppModalSheet(
          title: title,
          icon: icon,
          scrollable: true,
          body: body,
          footer: actions != null && actions.isNotEmpty
              ? Row(children: actions)
              : null,
        );
      },
    );
  }

  // ============ Edit Profile ============

  void _editProfileSheet(BuildContext context) {
    final pm = ref.read(appDataProvider).propertyManager;
    final name = TextEditingController(text: pm?.name ?? '');
    final phone = TextEditingController(text: pm?.phone ?? '');
    final email = TextEditingController(text: pm?.email ?? '');
    String? avatar = pm?.avatar;
    String? error;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => _rawSheet(
            ctx,
            title: 'Edit Profile',
            canPop: () => Navigator.pop(ctx),
            actions: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.border.withValues(
                          alpha: AppColors.isDark ? 0.7 : 1.0,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColors.textSecondary,
                      backgroundColor: AppColors.surface,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: GradientButton.icon(
                    height: 46,
                    onPressed: () {
                      if (name.text.trim().isEmpty ||
                          phone.text.trim().isEmpty) {
                        setS(
                          () => error = 'Name and phone number are required',
                        );
                        return;
                      }
                      ref
                          .read(appDataProvider.notifier)
                          .setPropertyManager(
                            PropertyManager(
                              id: pm?.id ?? newId(),
                              name: name.text.trim(),
                              address: pm?.address ?? '',
                              phone: phone.text.trim(),
                              email: email.text.trim(),
                              avatar: avatar,
                              propertyName: pm?.propertyName,
                              ownerName: pm?.ownerName,
                              propertyPictures:
                                  pm?.propertyPictures ?? const [],
                              city: pm?.city,
                              state: pm?.state,
                              zipCode: pm?.zipCode,
                            ),
                          );
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Ionicons.checkmark, size: 16),
                    label: const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () async {
                    final p = await MediaPicker.pickImage(ctx);
                    if (p != null) setS(() => avatar = p);
                  },
                  child: Stack(
                    children: [
                      AvatarView(
                        name: name.text.isEmpty ? '' : name.text,
                        uri: avatar,
                        radius: 30,
                        borderColor: AppColors.primary,
                        borderWidth: 2,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Ionicons.camera,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to upload photo',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Owner Profile',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                AppField(
                  label: 'Property Manager Name',
                  hint: 'Enter property manager name',
                  controller: name,
                ),
                AppField(
                  label: 'Phone Number',
                  hint: 'Enter phone number',
                  controller: phone,
                  keyboard: TextInputType.phone,
                ),
                AppField(
                  label: 'Email Address',
                  hint: 'Enter email address',
                  controller: email,
                  keyboard: TextInputType.emailAddress,
                ),
                if (error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ Manage Properties & Portfolio ============

  void _managePropertiesSheet(BuildContext context, AppDataState s) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Properties & Portfolio',
        icon: Ionicons.businessOutline,
        iconColor: AppColors.primary,
        footer: SheetActions(
          cancelLabel: 'Close',
          primaryLabel: 'Add Property',
          primaryIcon: const Icon(Ionicons.add, size: 18, color: Colors.white),
          onPrimary: () {
            Navigator.pop(ctx);
            showDialog(
              context: context,
              builder: (_) => const DesktopPropertyModal(),
            );
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.properties.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No custom properties added yet.\nTap "Add Property" below to create one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              for (final p in s.properties)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Ionicons.businessOutline,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${p.address.isNotEmpty ? '${p.address} • ' : ''}${p.totalUnits} units • ${p.propertyType}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Ionicons.createOutline,
                          size: 18,
                          color: AppColors.iconSecondary,
                        ),
                        tooltip: 'Edit Property',
                        onPressed: () {
                          Navigator.pop(ctx);
                          showDialog(
                            context: context,
                            builder: (_) => DesktopPropertyModal(property: p),
                          );
                        },
                      ),
                      if (s.selectedPropertyId == p.id)
                        const Icon(
                          Ionicons.checkmarkCircle,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                  onTap: () {
                    ref.read(appDataProvider.notifier).selectProperty(p.id);
                    Navigator.pop(ctx);
                  },
                ),
          ],
        ),
      ),
    );
  }

  // ============ Property Details ============

  void _propertyDetailsSheet(BuildContext context) {
    final pm = ref.read(appDataProvider).propertyManager;
    final nameCtl = TextEditingController(text: pm?.propertyName ?? '');
    final ownerCtl = TextEditingController(text: pm?.ownerName ?? '');
    final addrCtl = TextEditingController(text: pm?.address ?? '');
    List<String> pics = [...(pm?.propertyPictures ?? [])];

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => _rawSheet(
            ctx,
            title: 'Property Details',
            canPop: () => Navigator.pop(ctx),
            actions: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.border.withValues(
                          alpha: AppColors.isDark ? 0.7 : 1.0,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColors.textSecondary,
                      backgroundColor: AppColors.surface,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: GradientButton.icon(
                    height: 46,
                    onPressed: () {
                      ref
                          .read(appDataProvider.notifier)
                          .setPropertyManager(
                            PropertyManager(
                              id: pm?.id ?? newId(),
                              name: pm?.name ?? '',
                              address: addrCtl.text.trim(),
                              phone: pm?.phone ?? '',
                              email: pm?.email ?? '',
                              avatar: pm?.avatar,
                              propertyName: nameCtl.text.trim(),
                              ownerName: ownerCtl.text.trim(),
                              propertyPictures: pics,
                              city: pm?.city,
                              state: pm?.state,
                              zipCode: pm?.zipCode,
                            ),
                          );
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Ionicons.checkmark, size: 16),
                    label: const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Property Information',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                AppField(
                  label: 'Property Name',
                  hint: 'Enter property name',
                  controller: nameCtl,
                ),
                AppField(
                  label: 'Property Owner Name',
                  hint: 'Enter property owner name',
                  controller: ownerCtl,
                ),
                AppField(
                  label: 'Property Address',
                  hint: 'Enter property address',
                  controller: addrCtl,
                  maxLines: 3,
                ),
                const SizedBox(height: 4),
                Text(
                  'Property Pictures',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final pic in pics)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AvatarView(name: '', uri: pic, radius: 26),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => setS(() => pics.remove(pic)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color.fromRGBO(255, 0, 0, 0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Ionicons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    GestureDetector(
                      onTap: () async {
                        final p = await MediaPicker.pickImage(ctx);
                        if (p != null) setS(() => pics.add(p));
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                          color: AppColors.primaryLight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Ionicons.camera,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Add Photo',
                              style: TextStyle(
                                fontSize: 9.5,
                                height: 1.1,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ Export Data ============

  void _exportSheet(BuildContext context) {
    final s = ref.read(appDataProvider);
    final selected = <String, bool>{
      'propertyManager': true,
      'tenants': true,
      'payments': true,
      'expenses': true,
      'workOrders': true,
      'banks': true,
      'zakat': true,
      'documents': true,
      'bankDeposits': true,
      'monthlyNotes': true,
      'preferences': true,
    };
    bool exporting = false;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: StatefulBuilder(
          builder: (ctx, setS) => _rawSheet(
            ctx,
            title: 'Export Data',
            icon: Ionicons.download,
            canPop: () => Navigator.pop(ctx),
            actions: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.border.withValues(
                          alpha: AppColors.isDark ? 0.7 : 1.0,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColors.textSecondary,
                      backgroundColor: AppColors.surface,
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: GradientButton.icon(
                    height: 46,
                    onPressed: exporting
                        ? null
                        : () async {
                            setS(() => exporting = true);
                            final data = await AppStorage.exportAll();
                            if (!ctx.mounted) return;
                            final allSelected = selected.values.every((v) => v);
                            final filtered = <String, dynamic>{};
                            if (allSelected) {
                              filtered.addAll(data);
                            } else {
                              if (selected['propertyManager'] == true) {
                                filtered['propertyManager'] =
                                    data['propertyManager'];
                              }
                              if (selected['tenants'] == true) {
                                filtered['tenants'] = data['tenants'];
                              }
                              if (selected['payments'] == true) {
                                filtered['payments'] = data['payments'];
                              }
                              if (selected['expenses'] == true) {
                                filtered['expenses'] = data['expenses'];
                                if (data['expenseCategories'] != null) {
                                  filtered['expenseCategories'] =
                                      data['expenseCategories'];
                                }
                              }
                              if (selected['workOrders'] == true) {
                                filtered['workOrders'] = data['workOrders'];
                              }
                              if (selected['banks'] == true) {
                                filtered['banks'] = data['banks'];
                              }
                              if (selected['zakat'] == true) {
                                filtered['zakat'] = data['zakat'];
                                if (data['zakatCategories'] != null) {
                                  filtered['zakatCategories'] =
                                      data['zakatCategories'];
                                }
                              }
                              if (selected['documents'] == true) {
                                filtered['documents'] = data['documents'];
                                if (data['documentGroups'] != null) {
                                  filtered['documentGroups'] =
                                      data['documentGroups'];
                                }
                                if (data['documentCategories'] != null) {
                                  filtered['documentCategories'] =
                                      data['documentCategories'];
                                }
                              }
                              if (selected['bankDeposits'] == true) {
                                filtered['bankDeposits'] = data['bankDeposits'];
                              }
                              if (selected['monthlyNotes'] == true) {
                                filtered['monthlyNotes'] = data['monthlyNotes'];
                              }
                              if (selected['preferences'] == true) {
                                filtered['preferences'] = data['preferences'];
                                filtered['__prefs__'] = data['__prefs__'];
                                filtered['selectedCurrency'] =
                                    data['selectedCurrency'];
                                filtered['predefinedDescriptions'] =
                                    data['predefinedDescriptions'];
                                filtered['onboardingCompleted'] =
                                    data['onboardingCompleted'];
                              }
                              if (data['__media__'] != null) {
                                filtered['__media__'] = data['__media__'];
                                filtered['__media_count__'] =
                                    data['__media_count__'];
                                filtered['__backup_format__'] =
                                    data['__backup_format__'];
                              }
                            }
                            final json = const JsonEncoder.withIndent('  ')
                                .convert(filtered);
                            final tmpDir = await getTemporaryDirectory();
                            final stamp = DateTime.now()
                                .toIso8601String()
                                .replaceAll(':', '-')
                                .split('.')
                                .first;
                            final backupFile = File(
                              '${tmpDir.path}/RentManager_Backup_$stamp.json',
                            );
                            await backupFile.writeAsString(json);
                            if (!ctx.mounted) return;
                            final box = ctx.findRenderObject() as RenderBox?;
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [XFile(backupFile.path)],
                                subject: 'RentManager backup',
                                sharePositionOrigin: box != null
                                    ? box.localToGlobal(Offset.zero) & box.size
                                    : null,
                              ),
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          },
                    icon: Icon(
                      exporting ? Ionicons.hourglass : Ionicons.download,
                      size: 16,
                    ),
                    label: Text(
                      exporting ? 'Exporting...' : 'Export Data',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            child: Builder(
              builder: (ctx) {
                final isDark = AppColors.isDark;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Choose what to include in your backup',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondary
                                  : const Color(0xFF5A7A7A),
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                          onPressed: () {
                            final all = selected.values.every((v) => v);
                            setS(() {
                              for (final k in selected.keys) {
                                selected[k] = !all;
                              }
                            });
                          },
                          child: Text(
                            selected.values.every((v) => v)
                                ? 'Deselect All'
                                : 'Select All',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _dataGrid([
                      _dataCard(
                        icon: Ionicons.personOutline,
                        color: AppColors.primary,
                        title: 'Property Manager',
                        count: s.propertyManager != null
                            ? '1 profile'
                            : 'No data',
                        selected: selected['propertyManager']!,
                        onTap: () => setS(
                          () => selected['propertyManager'] =
                              !selected['propertyManager']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.peopleOutline,
                        color: AppColors.info,
                        title: 'Tenants',
                        count:
                            '${s.tenants.length} ${s.tenants.length == 1 ? 'tenant' : 'tenants'}',
                        selected: selected['tenants']!,
                        onTap: () => setS(
                          () => selected['tenants'] = !selected['tenants']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.cashOutline,
                        color: AppColors.accentDark,
                        title: 'Payments',
                        count:
                            '${s.payments.length} ${s.payments.length == 1 ? 'payment' : 'payments'}',
                        selected: selected['payments']!,
                        onTap: () => setS(
                          () => selected['payments'] = !selected['payments']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.walletOutline,
                        color: const Color(0xFF9C27B0),
                        title: 'Expenses',
                        count:
                            '${s.expenses.length} ${s.expenses.length == 1 ? 'expense' : 'expenses'}',
                        selected: selected['expenses']!,
                        onTap: () => setS(
                          () => selected['expenses'] = !selected['expenses']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.hammerOutline,
                        color: const Color(0xFFF44336),
                        title: 'Work Orders',
                        count:
                            '${s.workOrders.length} ${s.workOrders.length == 1 ? 'order' : 'orders'}',
                        selected: selected['workOrders']!,
                        onTap: () => setS(
                          () =>
                              selected['workOrders'] = !selected['workOrders']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.businessOutline,
                        color: const Color(0xFF009688),
                        title: 'Bank Accounts',
                        count:
                            '${s.banks.length} ${s.banks.length == 1 ? 'account' : 'accounts'}',
                        selected: selected['banks']!,
                        onTap: () =>
                            setS(() => selected['banks'] = !selected['banks']!),
                      ),
                      _dataCard(
                        icon: Ionicons.heartOutline,
                        color: const Color(0xFFE91E63),
                        title: 'Zakat',
                        count:
                            '${s.zakat.length} ${s.zakat.length == 1 ? 'record' : 'records'}',
                        selected: selected['zakat']!,
                        onTap: () =>
                            setS(() => selected['zakat'] = !selected['zakat']!),
                      ),
                      _dataCard(
                        icon: Ionicons.documentTextOutline,
                        color: const Color(0xFF3F51B5),
                        title: 'Documents',
                        count:
                            '${s.documents.length} ${s.documents.length == 1 ? 'document' : 'documents'}',
                        selected: selected['documents']!,
                        onTap: () => setS(
                          () => selected['documents'] = !selected['documents']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.cardOutline,
                        color: const Color(0xFFFF9800),
                        title: 'Bank Deposits',
                        count:
                            '${s.bankDeposits.length} ${s.bankDeposits.length == 1 ? 'deposit' : 'deposits'}',
                        selected: selected['bankDeposits']!,
                        onTap: () => setS(
                          () => selected['bankDeposits'] =
                              !selected['bankDeposits']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.newspaperOutline,
                        color: const Color(0xFF795548),
                        title: 'Monthly Notes',
                        count:
                            '${s.monthlyNotes.length} ${s.monthlyNotes.length == 1 ? 'note' : 'notes'}',
                        selected: selected['monthlyNotes']!,
                        onTap: () => setS(
                          () => selected['monthlyNotes'] =
                              !selected['monthlyNotes']!,
                        ),
                      ),
                      _dataCard(
                        icon: Ionicons.settingsOutline,
                        color: const Color(0xFF607D8B),
                        title: 'Preferences',
                        count: 'Settings',
                        selected: selected['preferences']!,
                        onTap: () => setS(
                          () => selected['preferences'] =
                              !selected['preferences']!,
                        ),
                      ),
                    ]),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ============ Import Data ============

  void _importSheet(BuildContext context) {
    final s = ref.read(appDataProvider);
    final selected = <String, bool>{
      'propertyManager': true,
      'tenants': true,
      'payments': true,
      'expenses': true,
      'workOrders': true,
      'banks': true,
      'zakat': true,
      'documents': true,
      'bankDeposits': true,
      'monthlyNotes': true,
      'preferences': true,
    };

    Future<void> pickFile() async {
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (f?.path == null) return;
      try {
        final raw = await File(f!.path!).readAsString();
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (context.mounted) {
          Navigator.pop(context);
          _importPreview(context, map, selected: selected);
        }
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, 'Could not read file: $e', isError: true);
        }
      }
    }

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder(
        future: AutoBackupService.listLocal(),
        builder: (_, snap) {
          final backups = snap.data ?? [];
          return StatefulBuilder(
            builder: (ctx, setS) => _rawSheet(
              ctx,
              title: 'Import Data',
              icon: Ionicons.cloudUpload,
              canPop: () => Navigator.pop(ctx),
              actions: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.border.withValues(
                            alpha: AppColors.isDark ? 0.7 : 1.0,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: AppColors.textSecondary,
                        backgroundColor: AppColors.surface,
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: GradientButton.icon(
                      height: 46,
                      onPressed: pickFile,
                      icon: const Icon(Ionicons.cloudUpload, size: 16),
                      label: const Text(
                        'Browse File',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              child: Builder(
                builder: (ctx) {
                  final isDark = AppColors.isDark;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select the data types you want to import',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textSecondary
                                    : const Color(0xFF5A7A7A),
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                            ),
                            onPressed: () {
                              final all = selected.values.every((v) => v);
                              setS(() {
                                for (final k in selected.keys) {
                                  selected[k] = !all;
                                }
                              });
                            },
                            child: Text(
                              selected.values.every((v) => v)
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _dataGrid([
                        _dataCard(
                          icon: Ionicons.personOutline,
                          color: AppColors.primary,
                          title: 'Property Manager',
                          count: s.propertyManager != null
                              ? '1 profile'
                              : 'No data',
                          selected: selected['propertyManager']!,
                          onTap: () => setS(
                            () => selected['propertyManager'] =
                                !selected['propertyManager']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.peopleOutline,
                          color: AppColors.info,
                          title: 'Tenants',
                          count:
                              '${s.tenants.length} ${s.tenants.length == 1 ? 'tenant' : 'tenants'}',
                          selected: selected['tenants']!,
                          onTap: () => setS(
                            () => selected['tenants'] = !selected['tenants']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.cashOutline,
                          color: AppColors.accentDark,
                          title: 'Payments',
                          count:
                              '${s.payments.length} ${s.payments.length == 1 ? 'payment' : 'payments'}',
                          selected: selected['payments']!,
                          onTap: () => setS(
                            () => selected['payments'] = !selected['payments']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.walletOutline,
                          color: const Color(0xFF9C27B0),
                          title: 'Expenses',
                          count:
                              '${s.expenses.length} ${s.expenses.length == 1 ? 'expense' : 'expenses'}',
                          selected: selected['expenses']!,
                          onTap: () => setS(
                            () => selected['expenses'] = !selected['expenses']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.hammerOutline,
                          color: const Color(0xFFF44336),
                          title: 'Work Orders',
                          count:
                              '${s.workOrders.length} ${s.workOrders.length == 1 ? 'order' : 'orders'}',
                          selected: selected['workOrders']!,
                          onTap: () => setS(
                            () => selected['workOrders'] =
                                !selected['workOrders']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.businessOutline,
                          color: const Color(0xFF009688),
                          title: 'Bank Accounts',
                          count:
                              '${s.banks.length} ${s.banks.length == 1 ? 'account' : 'accounts'}',
                          selected: selected['banks']!,
                          onTap: () => setS(
                            () => selected['banks'] = !selected['banks']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.heartOutline,
                          color: const Color(0xFFE91E63),
                          title: 'Zakat',
                          count:
                              '${s.zakat.length} ${s.zakat.length == 1 ? 'record' : 'records'}',
                          selected: selected['zakat']!,
                          onTap: () => setS(
                            () => selected['zakat'] = !selected['zakat']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.documentTextOutline,
                          color: const Color(0xFF3F51B5),
                          title: 'Documents',
                          count:
                              '${s.documents.length} ${s.documents.length == 1 ? 'document' : 'documents'}',
                          selected: selected['documents']!,
                          onTap: () => setS(
                            () =>
                                selected['documents'] = !selected['documents']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.cardOutline,
                          color: const Color(0xFFFF9800),
                          title: 'Bank Deposits',
                          count:
                              '${s.bankDeposits.length} ${s.bankDeposits.length == 1 ? 'deposit' : 'deposits'}',
                          selected: selected['bankDeposits']!,
                          onTap: () => setS(
                            () => selected['bankDeposits'] =
                                !selected['bankDeposits']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.newspaperOutline,
                          color: const Color(0xFF795548),
                          title: 'Monthly Notes',
                          count:
                              '${s.monthlyNotes.length} ${s.monthlyNotes.length == 1 ? 'note' : 'notes'}',
                          selected: selected['monthlyNotes']!,
                          onTap: () => setS(
                            () => selected['monthlyNotes'] =
                                !selected['monthlyNotes']!,
                          ),
                        ),
                        _dataCard(
                          icon: Ionicons.settingsOutline,
                          color: const Color(0xFF607D8B),
                          title: 'Preferences',
                          count: 'Settings',
                          selected: selected['preferences']!,
                          onTap: () => setS(
                            () => selected['preferences'] =
                                !selected['preferences']!,
                          ),
                        ),
                      ]),
                      if (backups.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Ionicons.cloudDone,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Auto Backup Available',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Restore from your automatic backup data\nLast backup: ${backups.first.path.split('/').last.replaceFirst('RentManager_AutoBackup_', '').replaceAll('.json', '')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.textSecondary
                                      : const Color(0xFF4D6E6E),
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 36,
                                child: GradientButton.icon(
                                  onPressed: () async {
                                    final map =
                                        await AutoBackupService.readLocal(
                                          backups.first,
                                        );
                                    if (map == null) {
                                      if (ctx.mounted) {
                                        showAppToast(
                                          ctx,
                                          'Could not read backup file',
                                          isError: true,
                                        );
                                      }
                                      return;
                                    }
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      _importPreview(
                                        context,
                                        map,
                                        selected: selected,
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Ionicons.cloudDownload,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Restore from Auto Backup',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.04)
                              : const Color(0xFFF7FAFA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.08)
                                : const Color(0xFFDFE6E6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.2 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Ionicons.documentTextOutline,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Import from File',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF142424),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Select a .json backup file from device storage',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? const Color(0xFFA0D8D8)
                                          : const Color(0xFF5A7A7A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 32,
                              child: OutlinedButton(
                                onPressed: pickFile,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  foregroundColor: AppColors.primary,
                                ),
                                child: const Text(
                                  'Browse',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  static int _countOf(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v == null) return 0;
    try {
      if (v is String) {
        final d = jsonDecode(v);
        if (d is List) return d.length;
        return 1;
      }
      if (v is List) return v.length;
      return 1;
    } catch (_) {
      return 0;
    }
  }

  /// Preview with replace|merge + per-type strategies displayed as a bottom modal sheet.
  void _importPreview(
    BuildContext context,
    Map<String, dynamic> rawMap, {
    Map<String, bool>? selected,
  }) {
    String mode = 'replace';
    bool importing = false;
    final strategies = {
      'tenants': 'skip',
      'payments': 'skip',
      'expenses': 'skip',
      'workOrders': 'skip',
      'banks': 'skip',
      'zakat': 'skip',
      'documents': 'skip',
      'bankDeposits': 'skip',
      'monthlyNotes': 'skip',
    };

    final map = <String, dynamic>{};
    if (selected != null && !selected.values.every((v) => v)) {
      if (selected['propertyManager'] == true &&
          rawMap['propertyManager'] != null) {
        map['propertyManager'] = rawMap['propertyManager'];
      }
      if (selected['tenants'] == true && rawMap['tenants'] != null) {
        map['tenants'] = rawMap['tenants'];
      }
      if (selected['payments'] == true && rawMap['payments'] != null) {
        map['payments'] = rawMap['payments'];
      }
      if (selected['expenses'] == true) {
        if (rawMap['expenses'] != null) map['expenses'] = rawMap['expenses'];
        if (rawMap['expenseCategories'] != null) {
          map['expenseCategories'] = rawMap['expenseCategories'];
        }
      }
      if (selected['workOrders'] == true && rawMap['workOrders'] != null) {
        map['workOrders'] = rawMap['workOrders'];
      }
      if (selected['banks'] == true && rawMap['banks'] != null) {
        map['banks'] = rawMap['banks'];
      }
      if (selected['zakat'] == true) {
        if (rawMap['zakat'] != null) map['zakat'] = rawMap['zakat'];
        if (rawMap['zakatCategories'] != null) {
          map['zakatCategories'] = rawMap['zakatCategories'];
        }
      }
      if (selected['documents'] == true) {
        if (rawMap['documents'] != null) map['documents'] = rawMap['documents'];
        if (rawMap['documentGroups'] != null) {
          map['documentGroups'] = rawMap['documentGroups'];
        }
        if (rawMap['documentCategories'] != null) {
          map['documentCategories'] = rawMap['documentCategories'];
        }
      }
      if (selected['bankDeposits'] == true && rawMap['bankDeposits'] != null) {
        map['bankDeposits'] = rawMap['bankDeposits'];
      }
      if (selected['monthlyNotes'] == true && rawMap['monthlyNotes'] != null) {
        map['monthlyNotes'] = rawMap['monthlyNotes'];
      }
      if (selected['preferences'] == true) {
        if (rawMap['preferences'] != null) {
          map['preferences'] = rawMap['preferences'];
        }
        if (rawMap['__prefs__'] != null) map['__prefs__'] = rawMap['__prefs__'];
      }
    } else {
      map.addAll(rawMap);
    }

    final rows = <String, (int, IconData)>{
      'Tenants': (_countOf(map, 'tenants'), Ionicons.peopleOutline),
      'Payments': (_countOf(map, 'payments'), Ionicons.cardOutline),
      'Expenses': (_countOf(map, 'expenses'), Ionicons.receiptOutline),
      'Work Orders': (_countOf(map, 'workOrders'), Ionicons.constructOutline),
      'Banks': (_countOf(map, 'banks'), Ionicons.businessOutline),
      'Zakat': (_countOf(map, 'zakat'), Ionicons.heartOutline),
      'Documents': (_countOf(map, 'documents'), Ionicons.documentTextOutline),
      'Bank Deposits': (_countOf(map, 'bankDeposits'), Ionicons.cashOutline),
      'Monthly Notes': (
        _countOf(map, 'monthlyNotes'),
        Ionicons.clipboardOutline,
      ),
    };
    final total = rows.values.fold<int>(0, (a, b) => a + b.$1);

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => _rawSheet(
          ctx,
          title: 'Import Preview',
          icon: Ionicons.cloudUpload,
          canPop: () => Navigator.pop(ctx),
          actions: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: importing ? null : () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.border.withValues(
                        alpha: AppColors.isDark ? 0.7 : 1.0,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: AppColors.textSecondary,
                    backgroundColor: AppColors.surface,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 46,
                child: GradientButton(
                  height: 46,
                  onPressed: importing
                      ? null
                      : () async {
                          setS(() => importing = true);
                          try {
                            final summary = await ref
                                .read(appDataProvider.notifier)
                                .applyImport(
                                  map,
                                  mode: mode,
                                  strategies: strategies,
                                );
                            final added = summary.values.fold<int>(
                              0,
                              (a, m) => a + (m['added'] ?? 0),
                            );
                            final updated = summary.values.fold<int>(
                              0,
                              (a, m) => a + (m['updated'] ?? 0),
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (context.mounted) {
                              showAppToast(
                                context,
                                mode == 'replace'
                                    ? 'Successfully restored $total records'
                                    : 'Merged successfully: $added added, $updated updated',
                                isSuccess: true,
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setS(() => importing = false);
                              showAppToast(
                                ctx,
                                'Failed to restore data: $e',
                                isError: true,
                              );
                            }
                          }
                        },
                  child: importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          mode == 'replace'
                              ? 'Restore & Replace'
                              : 'Restore & Merge',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
          child: Builder(
            builder: (ctx) {
              final isDark = AppColors.isDark;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode selection cards
                  Text(
                    'Restoration Mode',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: isDark ? Colors.white : const Color(0xFF142424),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => mode = 'replace'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mode == 'replace'
                                  ? (isDark
                                        ? AppColors.primary.withValues(
                                            alpha: 0.16,
                                          )
                                        : const Color(0xFFE8F5E9))
                                  : (isDark
                                        ? const Color.fromRGBO(
                                            255,
                                            255,
                                            255,
                                            0.04,
                                          )
                                        : const Color(0xFFF7FAFA)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: mode == 'replace'
                                    ? AppColors.primary
                                    : (isDark
                                          ? const Color.fromRGBO(
                                              255,
                                              255,
                                              255,
                                              0.08,
                                            )
                                          : const Color(0xFFDFE6E6)),
                                width: mode == 'replace' ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Ionicons.refreshCircleOutline,
                                      size: 16,
                                      color: mode == 'replace'
                                          ? AppColors.primary
                                          : (isDark
                                                ? AppColors.textSecondary
                                                : const Color(0xFF5A7A7A)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Replace All',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: mode == 'replace'
                                            ? AppColors.primary
                                            : (isDark
                                                  ? Colors.white
                                                  : const Color(0xFF142424)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Overwrites current data with backup',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? const Color(0xFFA0D8D8)
                                        : const Color(0xFF5A7A7A),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => mode = 'merge'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mode == 'merge'
                                  ? (isDark
                                        ? AppColors.primary.withValues(
                                            alpha: 0.16,
                                          )
                                        : const Color(0xFFE8F5E9))
                                  : (isDark
                                        ? const Color.fromRGBO(
                                            255,
                                            255,
                                            255,
                                            0.04,
                                          )
                                        : const Color(0xFFF7FAFA)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: mode == 'merge'
                                    ? AppColors.primary
                                    : (isDark
                                          ? const Color.fromRGBO(
                                              255,
                                              255,
                                              255,
                                              0.08,
                                            )
                                          : const Color(0xFFDFE6E6)),
                                width: mode == 'merge' ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Ionicons.gitMergeOutline,
                                      size: 16,
                                      color: mode == 'merge'
                                          ? AppColors.primary
                                          : (isDark
                                                ? AppColors.textSecondary
                                                : const Color(0xFF5A7A7A)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Merge Data',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: mode == 'merge'
                                            ? AppColors.primary
                                            : (isDark
                                                  ? Colors.white
                                                  : const Color(0xFF142424)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Keeps existing, adds new records',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? const Color(0xFFA0D8D8)
                                        : const Color(0xFF5A7A7A),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (mode == 'merge') ...[
                    const SizedBox(height: 10),
                    Text(
                      'Duplicate Conflict Resolution',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: isDark ? Colors.white : const Color(0xFF142424),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final k in strategies.keys.where(
                      (k) => _countOf(map, k) > 0,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.04)
                                : const Color(0xFFF7FAFA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                                  : const Color(0xFFDFE6E6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  k[0].toUpperCase() + k.substring(1),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF142424),
                                  ),
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value:
                                      const [
                                        'skip',
                                        'update',
                                        'create',
                                      ].contains(strategies[k])
                                      ? strategies[k]
                                      : 'skip',
                                  dropdownColor: isDark
                                      ? const Color(0xFF0D2424)
                                      : Colors.white,
                                  iconEnabledColor: AppColors.primary,
                                  isDense: true,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF142424),
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'skip',
                                      child: Text(
                                        'Skip duplicate',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF142424),
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'update',
                                      child: Text(
                                        'Update duplicate',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF142424),
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'create',
                                      child: Text(
                                        'Create copy',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF142424),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setS(() => strategies[k] = v ?? 'skip'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  // Compact 2-column Records Breakdown Card
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.04)
                          : const Color(0xFFF7FAFA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color.fromRGBO(255, 255, 255, 0.08)
                            : const Color(0xFFDFE6E6),
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Records in Backup',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF142424),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.2 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$total total',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          color: isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.06)
                              : const Color(0xFFDFE6E6),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (ctx, cons) {
                            final colW = (cons.maxWidth - 10) / 2;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                for (final entry in rows.entries)
                                  SizedBox(
                                    width: colW,
                                    child: Row(
                                      children: [
                                        Icon(
                                          entry.value.$2,
                                          size: 15,
                                          color: entry.value.$1 > 0
                                              ? AppColors.primary
                                              : (isDark
                                                    ? Colors.white38
                                                    : const Color(0xFF889B9B)),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            entry.key,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: entry.value.$1 > 0
                                                  ? (isDark
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF142424,
                                                          ))
                                                  : (isDark
                                                        ? Colors.white38
                                                        : const Color(
                                                            0xFF889B9B,
                                                          )),
                                              fontWeight: entry.value.$1 > 0
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: entry.value.$1 > 0
                                                ? (isDark
                                                      ? AppColors.primary
                                                            .withValues(
                                                              alpha: 0.16,
                                                            )
                                                      : const Color(0xFFE8F5E9))
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            '${entry.value.$1}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10,
                                              color: entry.value.$1 > 0
                                                  ? AppColors.primary
                                                  : (isDark
                                                        ? Colors.white38
                                                        : const Color(
                                                            0xFF889B9B,
                                                          )),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ============ Statistics ============

  void _statisticsSheet(BuildContext context, AppDataState s) {
    final paid = s.payments
        .where((p) => p.status == 'paid')
        .fold<double>(0, (a, p) => a + p.amount);
    final spent = s.expenses.fold<double>(0, (a, e) => a + e.amount);
    final deposits = s.bankDeposits.fold<double>(0, (a, d) => a + d.amount);
    final byStatus = <String, int>{};
    for (final w in s.workOrders) {
      byStatus[w.status] = (byStatus[w.status] ?? 0) + 1;
    }
    final zakIn = s.zakat
        .where((z) => z.type == 'inflow')
        .fold<double>(0, (a, z) => a + z.amount);
    final zakOut = s.zakat
        .where((z) => z.type == 'outflow')
        .fold<double>(0, (a, z) => a + z.amount);
    final pm = s.propertyManager;

    _showSheet(
      context,
      title: 'Full Project Statistics',
      icon: Ionicons.analytics,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statSection('Project Overview', [
            _statRow('Tenants', '${s.tenants.length}'),
            _statRow(
              'Active tenants',
              '${s.tenants.where((t) => t.status == 'active').length}',
            ),
            _statRow('Payments', '${s.payments.length} records'),
            _statRow('Expenses', '${s.expenses.length} records'),
            _statRow('Work orders', '${s.workOrders.length}'),
            _statRow('Banks', '${s.banks.length}'),
            _statRow('Documents', '${s.documents.length}'),
            _statRow('Document groups', '${s.documentGroups.length}'),
          ]),
          _statSection('Financial Overview', [
            _statRow('Rent collected', fmtMoney(s.selectedCurrency, paid)),
            _statRow('Total expenses', fmtMoney(s.selectedCurrency, spent)),
            _statRow('Net profit', fmtMoney(s.selectedCurrency, paid - spent)),
            _statRow('Bank deposits', fmtMoney(s.selectedCurrency, deposits)),
          ]),
          _statSection('Payment Status', [
            _statRow(
              'Paid',
              '${s.payments.where((p) => p.status == 'paid').length}',
            ),
            _statRow(
              'Pending',
              '${s.payments.where((p) => p.status != 'paid').length}',
            ),
          ]),
          _statSection('Work Order Status', [
            _statRow('Pending', '${byStatus['pending'] ?? 0}'),
            _statRow('In progress', '${byStatus['in-progress'] ?? 0}'),
            _statRow('Completed', '${byStatus['completed'] ?? 0}'),
          ]),
          _statSection('Additional Data', [
            _statRow(
              'Zakat balance',
              fmtMoney(s.selectedCurrency, zakIn - zakOut),
            ),
            _statRow('Monthly notes', '${s.monthlyNotes.length}'),
            _statRow(
              'Predefined descriptions',
              '${s.predefinedDescriptions.length}',
            ),
            _statRow(
              'Recently deleted docs',
              '${s.recentlyDeletedDocs.length}',
            ),
            _statRow('Expense categories', '${s.expenseCategories.length}'),
            _statRow('Document categories', '${s.documentCategories.length}'),
          ]),
          _statSection('Property Manager', [
            _statRow('Name', pm?.name ?? '—'),
            _statRow('Property', pm?.propertyName ?? '—'),
            _statRow('Phone', pm?.phone ?? '—'),
            _statRow('Email', pm?.email ?? '—'),
          ]),
        ],
      ),
    );
  }

  Widget _statSection(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Column(children: rows),
        ),
      ],
    ),
  );

  Widget _statRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  // ============ Data grid helpers ============

  Widget _dataGrid(List<Widget> cards) => LayoutBuilder(
    builder: (ctx, cons) {
      final w = (cons.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final c in cards) SizedBox(width: w, child: c)],
      );
    },
  );

  Widget _dataCard({
    required IconData icon,
    required Color color,
    required String title,
    required String count,
    required bool selected,
    required VoidCallback onTap,
  }) => Builder(
    builder: (ctx) {
      final isDark = AppColors.isDark;
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                      ? AppColors.primary.withValues(alpha: 0.16)
                      : const Color(0xFFE8F5E9))
                : (isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.04)
                      : const Color(0xFFF7FAFA)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.08)
                        : const Color(0xFFDFE6E6)),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF142424),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFFA0D8D8)
                            : const Color(0xFF5A7A7A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : (isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.25)
                              : const Color(0xFFB0BEBE)),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Icon(
                        Ionicons.checkmark,
                        size: 13,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    },
  );

  // ============ Help / Privacy / About ============

  void _helpSheet(BuildContext context) {
    _showSheet(
      context,
      title: 'Help & Support',
      icon: Ionicons.helpCircle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HelpQ(
            'How do I record rent?',
            'Open Overview, tap + → Record rent payment, pick the tenant and save. Use “Multiple” mode to batch-record multiple payments.',
          ),
          _HelpQ(
            'How do monthly totals work?',
            'Overview filters by the selected month and year. Payments count by their “Paid for” month; expenses by “Expense for” month.',
          ),
          _HelpQ(
            'How do I back up my data?',
            'Settings → Data Management → Export Data, Google Drive Backup, or enable Auto Backup.',
          ),
          _HelpQ(
            'How do I restore a backup?',
            'Settings → Data Management → Import Data → choose the .json file, review the preview, then Replace or Merge.',
          ),
          _HelpQ(
            'Where are my files stored?',
            'Everything stays on this device (plus your own Drive backups). Uninstalling without a backup loses data.',
          ),
          _HelpQ(
            'Contact',
            'For support, contact the developer from the About screen details.',
          ),
        ],
      ),
    );
  }

  void _privacySheet(BuildContext context) {
    _showSheet(
      context,
      title: 'Privacy Policy',
      icon: Ionicons.documentText,
      body: Text(
        'RentManager is local-first. Your tenants, payments, expenses, documents and photos are stored only on this device.\n\n• No account is required and no analytics are collected by the app itself.\n• Google Drive backup uploads a JSON snapshot to your own Drive folder (RentManager_Backups) only when you tap Back Up.\n• Notifications are scheduled on-device; nothing leaves the phone.\n• Deleting the app without a backup permanently removes local data.',
        style: TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
    );
  }

  Widget _buildMobileUpdateStatus(
    UpdateCheckResult? result, {
    required bool checking,
  }) {
    if (checking) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          ),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF38BDF8),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Checking for updates...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF38BDF8),
              ),
            ),
          ],
        ),
      );
    }

    if (result == null) return const SizedBox.shrink();

    Color color;
    IconData icon;
    String title;
    String message;
    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        color = const Color(0xFF10B981);
        icon = Ionicons.cloudDownloadOutline;
        title = 'Update available: v${result.latestVersion}';
        message =
            result.releaseNotes ??
            'A newer version of RentManager is ready to install.';
        break;
      case UpdateCheckStatus.upToDate:
        color = const Color(0xFF10B981);
        icon = Ionicons.checkmarkCircleOutline;
        title = 'You are up to date';
        message =
            'v${result.currentVersion} (build ${result.currentBuild}) is the latest version.';
        break;
      case UpdateCheckStatus.notConfigured:
        color = const Color(0xFFF59E0B);
        icon = Ionicons.settingsOutline;
        title = 'Update source not configured';
        message = 'Set UPDATE_MANIFEST_URL when building to enable live update checks.';
        break;
      case UpdateCheckStatus.error:
        color = const Color(0xFFEF4444);
        icon = Ionicons.alertCircleOutline;
        title = 'Update check failed';
        message = result.error ?? 'Could not check for updates.';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (result.updateAvailable && result.hasDownload) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final opened = await UpdateService.openDownload(result);
                  if (!opened && mounted) {
                    showAppToast(
                      context,
                      'Could not open the download page.',
                      isError: true,
                    );
                  }
                },
                icon: const Icon(Ionicons.downloadOutline, size: 16),
                label: const Text('Update Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _aboutSheet(BuildContext context) {
    const features = [
      [
        Ionicons.peopleOutline,
        'Tenant Management',
        'Manage tenants, leases, and contact details',
      ],
      [
        Ionicons.homeOutline,
        'Property Management',
        'Track properties, units, and ownership',
      ],
      [
        Ionicons.cashOutline,
        'Financial Tracking',
        'Monitor rent, expenses, and cash flow',
      ],
      [
        Ionicons.constructOutline,
        'Work Orders',
        'Create and track maintenance requests',
      ],
      [
        Ionicons.documentOutline,
        'Document Management',
        'Store leases, receipts, and important files',
      ],
      [
        Ionicons.analyticsOutline,
        'Reports & Analytics',
        'Generate insights and financial reports',
      ],
      [
        Ionicons.shieldCheckmarkOutline,
        'Security & Privacy',
        'Biometric lock keeps your data safe',
      ],
      [
        Ionicons.notificationsOutline,
        'Smart Notifications',
        'Stay on top of rent due dates',
      ],
    ];
    bool checkingUpdate = false;
    UpdateCheckResult? updateResult;
    _showSheet(
      context,
      title: 'About Rent Manager',
      icon: Ionicons.informationCircle,
      body: StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Ionicons.home,
                  size: 56,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Rent Manager',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Version $kAppVersion',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: checkingUpdate
                      ? null
                      : () async {
                          setSheetState(() {
                            checkingUpdate = true;
                            updateResult = null;
                          });
                          final result = await UpdateService.checkForUpdates();
                          if (!mounted) return;
                          setSheetState(() {
                            checkingUpdate = false;
                            updateResult = result;
                          });
                        },
                  icon: checkingUpdate
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF38BDF8),
                          ),
                        )
                      : const Icon(Ionicons.refreshOutline, size: 16),
                  label: Text(
                    checkingUpdate ? 'Checking...' : 'Check for Updates',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (checkingUpdate || updateResult != null) ...[
                const SizedBox(height: 10),
                _buildMobileUpdateStatus(
                  updateResult,
                  checking: checkingUpdate,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'A comprehensive property management app for landlords and property managers. Streamline your rental business with powerful tools and intuitive design.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Key Features',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          f[0] as IconData,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f[1] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f[2] as String,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Developer Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Ionicons.personCircleOutline,
                    size: 40,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'nazelahi',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Developer & Designer',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () =>
                            launchUrl(Uri.parse('mailto:imnazelahi@gmail.com')),
                        child: Row(
                          children: const [
                            Icon(
                              Ionicons.mailOutline,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Contact Developer',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Built with love for property managers and landlords',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Thank you for using Rent Manager!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============ Drive ============

  void _driveSheet(BuildContext context) {
    showGoogleDriveSheet(context, onImportPreview: _importPreview);
  }

  /// Raw sheet frame used by the stateful child sheets (delegating to AppModalSheet).
  Widget _rawSheet(
    BuildContext ctx, {
    required String title,
    IconData? icon,
    required Widget child,
    List<Widget>? actions,
    required VoidCallback canPop,
  }) {
    return AppModalSheet(
      title: title,
      icon: icon,
      scrollable: true,
      onClose: canPop,
      body: child,
      footer: actions != null && actions.isNotEmpty
          ? Row(children: actions)
          : null,
    );
  }
}

class _HelpQ extends StatelessWidget {
  final String q;
  final String a;
  const _HelpQ(this.q, this.a);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(a, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
      ],
    ),
  );
}

/// Drive backup sheet body with live upload / list / restore / delete.
class _DriveSheetBody extends ConsumerStatefulWidget {
  final void Function(String? msg) onDone;
  final void Function(Map<String, dynamic> data)? onImportPreview;
  final bool isDialog;
  const _DriveSheetBody({
    required this.onDone,
    this.onImportPreview,
    this.isDialog = false,
  });
  @override
  ConsumerState<_DriveSheetBody> createState() => _DriveSheetBodyState();
}

class _DriveSheetBodyState extends ConsumerState<_DriveSheetBody> {
  bool _busy = false;
  String? _error;
  List<DriveBackupFile> _files = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    if (DriveBackupService.isSignedIn) {
      _refresh();
    }
  }

  Future<void> _run(
    Future<String?> Function() fn, {
    bool closeOnDone = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await fn();
      if (closeOnDone) {
        widget.onDone(msg);
      } else if (msg != null && mounted) {
        showAppToast(context, msg, isSuccess: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _friendlyError(Object e) {
    final s = '$e';
    if (s.contains('ApiException: 10') || s.contains('DEVELOPER_ERROR')) {
      return 'Google Sign-In configuration note: Ensure your app SHA-1 fingerprint '
          'is registered in Google Cloud Console / Firebase.';
    }
    if (s.contains('canceled') || s.contains('cancelled')) {
      return 'Sign-in was cancelled.';
    }
    return 'Operation failed: $e';
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await DriveBackupService.listBackups();
      if (mounted) {
        setState(() {
          _files = files;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await DriveBackupService.signIn();
      if (account != null) {
        final p = ref.read(appDataProvider).preferences;
        if (!p.driveAutoSync) {
          ref
              .read(appDataProvider.notifier)
              .setPreferences(p.copyWith(driveAutoSync: true));
          unawaited(
            DriveBackupService.syncNow(ref).then((_) {
              if (mounted) _refresh();
            }),
          );
        }
        await _refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Disconnect Google Drive',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Do you want to sign out from your Google account?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DriveBackupService.signOut();
      final p = ref.read(appDataProvider).preferences;
      ref
          .read(appDataProvider.notifier)
          .setPreferences(p.copyWith(driveAutoSync: false));
      if (mounted) {
        setState(() {
          _files = [];
          _loaded = false;
        });
      }
    }
  }

  Future<void> _confirmRestore(DriveBackupFile f) async {
    await _run(() async {
      final map = await DriveBackupService.download(f.id);
      if (map == null) {
        throw const FormatException('Empty or corrupt backup file');
      }
      if (widget.onImportPreview != null) {
        widget.onImportPreview!(map);
        return null;
      }
      await AppStorage.importAll(map);
      await ref.read(appDataProvider.notifier).loadAll();
      return 'Successfully restored ${f.name}';
    });
  }

  Future<void> _confirmDelete(DriveBackupFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Delete Cloud Backup?',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${f.name}" from Google Drive? This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _run(() async {
        await DriveBackupService.deleteBackup(f.id);
        await _refresh();
        return 'Deleted ${f.name}';
      });
    }
  }

  Widget _syncFreqTab(String label, String value, String current) {
    final active = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          final p = ref.read(appDataProvider).preferences;
          ref
              .read(appDataProvider.notifier)
              .setPreferences(p.copyWith(driveSyncFrequency: value));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = DriveBackupService.currentUser;
    final isSignedIn = user != null;
    final isDark = AppColors.isDark;
    final p = ref.watch(appDataProvider).preferences;

    if (widget.isDialog) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF091E1F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.08)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF4285F4).withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Ionicons.logoGoogle,
                      size: 20,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Drive Cloud Backup',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Encrypted cloud snapshots on your personal Google Drive',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Ionicons.close,
                          size: 16,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.06)
                  : const Color(0xFFE2E8F0),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: _buildContent(user, isSignedIn, isDark, p),
              ),
            ),
          ],
        ),
      );
    }

    return AppModalSheet(
      title: 'Google Drive Cloud Backup',
      icon: Ionicons.logoGoogle,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildContent(user, isSignedIn, isDark, p),
      ),
    );
  }

  List<Widget> _buildContent(
    GoogleAccountInfo? user,
    bool isSignedIn,
    bool isDark,
    AppPreferences p,
  ) {
    final u = user;
    return [
      // 1. Google Account Card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: (isSignedIn && u != null)
            ? Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF4285F4)
                        .withValues(alpha: 0.2),
                    child: Text(
                      (u.displayName ?? u.email).isNotEmpty
                          ? (u.displayName ?? u.email)[0].toUpperCase()
                          : 'G',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.displayName ?? 'Google Account',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          u.email,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _handleSignOut,
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Ionicons.cloudOutline,
                        size: 22,
                        color: Color(0xFF4285F4),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Connect your Google Account to back up all tenants, payments, documents, and settings to Google Drive.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Ionicons.logoGoogle, size: 18),
                    label: const Text(
                      'Sign in with Google',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: _busy ? null : _handleSignIn,
                  ),
                ],
              ),
      ),

      // 2. Google Drive Auto-Sync Card (shown when signed in)
      if (isSignedIn) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: p.driveAutoSync
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: p.driveAutoSync
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Ionicons.syncCircle,
                          size: 22,
                          color: p.driveAutoSync
                              ? AppColors.primary
                              : AppColors.iconMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Google Drive Auto-Sync',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<DriveSyncStatus>(
                            valueListenable: DriveBackupService.syncStatus,
                            builder: (_, status, _) {
                              if (status == DriveSyncStatus.syncing) {
                                return const Text(
                                  'Syncing in progress...',
                                  style: TextStyle(
                                    color: Color(0xFF4285F4),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }
                              if (p.driveAutoSync) {
                                return Text(
                                  'Active • Last: ${DriveBackupService.formatTimeAgo(p.lastDriveSync)}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                  ),
                                );
                              }
                              return Text(
                                'Disabled • Turn on to sync automatically',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  Switch(
                    value: p.driveAutoSync,
                    activeThumbColor: AppColors.primary,
                    onChanged: _busy
                        ? null
                        : (v) {
                            ref
                                .read(appDataProvider.notifier)
                                .setPreferences(p.copyWith(driveAutoSync: v));
                            if (v) {
                              unawaited(
                                DriveBackupService.syncNow(ref).then((_) {
                                  if (mounted) _refresh();
                                }),
                              );
                            }
                          },
                  ),
                ],
              ),
              if (p.driveAutoSync) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: AppColors.surfaceBorder),
                const SizedBox(height: 10),
                Text(
                  'Sync Frequency',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _syncFreqTab(
                      'On Change',
                      'on_change',
                      p.driveSyncFrequency,
                    ),
                    const SizedBox(width: 8),
                    _syncFreqTab('Daily', 'daily', p.driveSyncFrequency),
                    const SizedBox(width: 8),
                    _syncFreqTab('Weekly', 'weekly', p.driveSyncFrequency),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p.driveSyncFrequency == 'on_change'
                      ? 'Changes sync automatically in the background, keeping your cloud backup up to date.'
                      : 'Backs up automatically on a ${p.driveSyncFrequency} schedule, keeping your cloud backup up to date.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],

      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Text(
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
        ),
      ],

      const SizedBox(height: 16),

      // 3. Action Buttons
      Row(
        children: [
          Expanded(
            child: GradientButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Ionicons.cloudUpload, size: 18),
              label: Text(p.driveAutoSync ? 'Sync Now' : 'Back Up Now'),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final name = await DriveBackupService.syncNow(ref);
                      await _refresh();
                      return name != null
                          ? 'Synced to Google Drive: $name'
                          : 'Synced successfully';
                    }),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
            icon: const Icon(Ionicons.refresh, size: 18),
            label: Text(_loaded ? 'Refresh' : 'List Backups'),
            onPressed: _busy ? null : _refresh,
          ),
        ],
      ),

      const SizedBox(height: 20),

      // 4. Backups List Header
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Drive Backups (RentManager_Backups)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          if (_files.isNotEmpty)
            Text(
              '${_files.length} found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),

      const SizedBox(height: 10),

      if (_loaded && _files.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No backups found in Google Drive yet.\nTap "Sync Now" to create your first backup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ),

      ..._files.map(
        (f) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Ionicons.cloudDone,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    f.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (f.name.contains('AutoSync')) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Auto-Sync',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '${f.created.isEmpty ? '' : fmtDate(f.created)} • ${f.size}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: _busy
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _confirmRestore(f),
                        child: const Text(
                          'Restore',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Ionicons.trashOutline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        onPressed: () => _confirmDelete(f),
                        tooltip: 'Delete Backup',
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ];
  }
}

/// Global helper to show the Google Drive Backup & Sync modal or dialog.
void showGoogleDriveSheet(
  BuildContext context, {
  void Function(BuildContext, Map<String, dynamic>)? onImportPreview,
}) {
  final isDesktop = Responsive.isDesktop(context);
  if (isDesktop) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: _DriveSheetBody(
            isDialog: true,
            onDone: (msg) {
              Navigator.pop(ctx);
              if (context.mounted && msg != null) {
                showAppToast(context, msg, isSuccess: true);
              }
            },
            onImportPreview: (map) {
              Navigator.pop(ctx);
              if (onImportPreview != null) {
                onImportPreview(context, map);
              }
            },
          ),
        ),
      ),
    );
    return;
  }

  showAdaptiveModalSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DriveSheetBody(
      onDone: (msg) {
        Navigator.pop(ctx);
        if (context.mounted && msg != null) {
          showAppToast(context, msg, isSuccess: true);
        }
      },
      onImportPreview: (map) {
        Navigator.pop(ctx);
        if (onImportPreview != null) {
          onImportPreview(context, map);
        }
      },
    ),
  );
}
