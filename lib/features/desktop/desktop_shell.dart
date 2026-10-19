import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/state/app_data.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../documents/documents_view.dart';
import '../overview/overview_view.dart';
import '../reports/reports_view.dart';
import '../settings/settings_view.dart';
import '../tenants/tenants_view.dart';
import '../work_orders/work_orders_view.dart';
import '../zakat/zakat_view.dart';
import 'desktop_app_bar.dart';
import 'desktop_batch_rent_modal.dart';
import 'desktop_rent_receipt_modal.dart';
import 'desktop_cash_flow_modal.dart';
import 'desktop_property_modal.dart';
import '../../core/widgets/desktop_window_controls.dart';
import '../../core/widgets/media_widgets.dart';
import '../../services/drive_backup_service.dart';
import '../../services/deep_linking.dart';
import '../../services/update_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Modern macOS Desktop Shell with full-size content view, translucent sidebar,
/// global Cmd+K command palette, and 100% full production functionality.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  int _tabIndex = 0;
  bool _showSettings = false;
  bool _userCollapsed = false;
  bool _collapsePrefsLoaded = false;
  int _windowWidth = 1400;

  bool get _effectiveCollapse => _windowWidth < 820 || _userCollapsed;

  void _toggleSidebarCollapse() {
    final newCollapsed = !_effectiveCollapse;
    setState(() => _userCollapsed = newCollapsed);
    final s = ref.read(appDataProvider);
    ref
        .read(appDataProvider.notifier)
        .setPreferences(s.preferences.copyWith(sidebarCollapsed: newCollapsed));
  }

  // Utility Drawer State
  bool _showRightUtilityDrawer = false;
  int _utilityDrawerTabIndex =
      0; // 0: Scratchpad, 1: Rent Calculator, 2: Activity Stream

  // Scratchpad
  final TextEditingController _scratchpadController = TextEditingController();

  // Rent / Deposit Calculator
  int _calcMode = 0; // 0: Prorated Rent, 1: Security Deposit
  int _calcDaysInMonth = 30;
  int _calcStartDay = 15;
  final TextEditingController _calcMonthlyRentController =
      TextEditingController(text: '1200');

  final TextEditingController _depositHeldController = TextEditingController(
    text: '1200',
  );
  final TextEditingController _depositUnpaidRentController =
      TextEditingController(text: '0');
  final TextEditingController _depositRepairsController = TextEditingController(
    text: '0',
  );
  final TextEditingController _depositCleaningController =
      TextEditingController(text: '0');

  // Standard Math Calculator
  String _mathDisplay = '0';
  String _mathExpression = '';
  double? _mathFirstOperand;
  String? _mathOperator;
  bool _mathShouldResetDisplay = false;

  // Activity Stream State
  String _activityFilter =
      'all'; // 'all', 'payment', 'expense', 'work_order', 'tenant', 'document'
  final TextEditingController _activitySearchController =
      TextEditingController();

  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadScratchpad();
    DeepLinkBus.pending.addListener(_onDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && DeepLinkBus.pending.value != null) _onDeepLink();
    });
  }

  void _onDeepLink() {
    final url = DeepLinkBus.pending.value;
    if (url == null || !mounted) return;
    DeepLinkBus.pending.value = null;
    final tab = DeepLinkBus.tabIndexFor(url);
    if (tab == null) return;
    setState(() {
      if (tab == -1) {
        _showSettings = true;
      } else {
        _tabIndex = tab;
        _showSettings = false;
      }
    });
  }

  Future<void> _loadScratchpad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('desktop_scratchpad_notes');
      if (saved != null && mounted) {
        _scratchpadController.text = saved;
      }
    } catch (_) {}
  }

  Future<void> _saveScratchpad(String val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('desktop_scratchpad_notes', val);
    } catch (_) {}
  }

  @override
  void dispose() {
    DeepLinkBus.pending.removeListener(_onDeepLink);
    _keyboardFocusNode.dispose();
    _searchFocusNode.dispose();
    _scratchpadController.dispose();
    _calcMonthlyRentController.dispose();
    _depositHeldController.dispose();
    _depositUnpaidRentController.dispose();
    _depositRepairsController.dispose();
    _depositCleaningController.dispose();
    _activitySearchController.dispose();
    super.dispose();
  }

  void _openCommandPalette() {
    _searchFocusNode.requestFocus();
  }

  void _showAboutAppDialog(BuildContext context) {
    final isDark = AppColors.isDark;
    final bg = isDark ? const Color(0xFF091E1F) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Ionicons.business,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'RentManager',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.6 (macOS Native Release)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'High-performance property management, tenant leasing, financial tracking, document vault, and automated cloud sync for modern landlords.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF061818)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _aboutRow(
                        'Runtime Architecture',
                        'Flutter macOS Desktop Engine',
                        isDark,
                      ),
                      _aboutRow(
                        'Local Database',
                        'Offline-First SQLite & Hive',
                        isDark,
                      ),
                      _aboutRow(
                        'Cloud Integration',
                        'Google Drive Automated Vault',
                        isDark,
                      ),
                      _aboutRow(
                        'Financial Engine',
                        'Multi-Currency & Zakat Nisab',
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  void _showKeyboardShortcutsDialog(BuildContext context) {
    final isDark = AppColors.isDark;
    final showZakat = ref.read(appDataProvider).preferences.showZakat;
    final bg = isDark ? const Color(0xFF091E1F) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    final categories = [
      (
        category: 'Workspace Navigation',
        shortcuts: [
          showZakat
              ? (
                  ['⌘', '1..6'],
                  'Switch to Overview, Tenants, Work Orders, Documents, Reports, Zakat',
                )
              : (
                  ['⌘', '1..5'],
                  'Switch to Overview, Tenants, Work Orders, Documents, Reports',
                ),
          (['⌘', 'B'], 'Toggle navigation sidebar rail'),
          (
            ['⌘', 'I'],
            'Toggle utility drawer (Calculator, Scratchpad, Activity)',
          ),
          (['⌘', 'T'], 'Toggle light / dark appearance mode'),
          (['⌘', ','], 'Open settings & cloud sync preferences'),
        ],
      ),
      (
        category: 'Quick Actions & Creation',
        shortcuts: [
          (['⌘', 'N'], 'Register new tenant & lease agreement'),
          (['⇧', '⌘', 'P'], 'Log tenant rent payment'),
          (['⇧', '⌘', 'B'], 'Batch collect monthly rent for all active units'),
          (['⇧', '⌘', 'E'], 'Record property operating expense'),
          (['⇧', '⌘', 'W'], 'Create maintenance work order ticket'),
          (['⌘', 'U'], 'Upload lease contract or property document'),
        ],
      ),
      (
        category: 'Search & Reporting Tools',
        shortcuts: [
          (['⌘', 'K'], 'Open global command palette & search'),
          (['⌘', '/'], 'Open keyboard shortcuts cheatsheet'),
          (['⇧', '⌘', 'S'], 'Trigger database & Google Drive sync'),
          (['⇧', '⌘', 'R'], 'Export monthly financial report to PDF'),
          (['⇧', '⌘', 'C'], 'Export financial data to CSV'),
          (['⌘', 'P'], 'Open system print preview dialog'),
        ],
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 580,
            constraints: const BoxConstraints(maxHeight: 650),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Ionicons.keypadOutline,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'macOS Keyboard Shortcuts',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Speed up your property management workflow with desktop hotkeys',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Ionicons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: categories.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (_, catIdx) {
                      final cat = categories[catIdx];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF061818)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.05)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat.category,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final s in cat.shortcuts) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.$2,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFFE2E8F0)
                                              : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final key in s.$1) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 3.5,
                                            ),
                                            margin: const EdgeInsets.only(
                                              left: 3.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? const Color(0xFF0D2B2C)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isDark
                                                    ? const Color.fromRGBO(
                                                        255,
                                                        255,
                                                        255,
                                                        0.12,
                                                      )
                                                    : const Color(0xFFCBD5E1),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(
                                                        alpha: isDark
                                                            ? 0.3
                                                            : 0.06,
                                                      ),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              key,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'monospace',
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  Widget _aboutRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  List<PlatformMenuItem> _buildPlatformMenus(
    BuildContext context,
    dynamic s,
    bool isDark,
    bool showZakat,
  ) {
    return [
      PlatformMenu(
        label: 'RentManager',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About RentManager',
                onSelected: () => _showAboutAppDialog(context),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Settings & Preferences...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: () => setState(() => _showSettings = true),
              ),
            ],
          ),
          if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.servicesSubmenu,
          ))
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
          if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.hide,
          ))
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.hideOtherApplications,
                ))
                  PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.hideOtherApplications,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.showAllApplications,
                ))
                  PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.showAllApplications,
                  ),
              ],
            ),
          if (PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.quit,
          ))
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Add Tenant...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                ),
                onSelected: () => TenantsView.showEditModal(context),
              ),
              PlatformMenuItem(
                label: 'Add Rent...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => OverviewView.showPaymentSheet(context),
              ),
              PlatformMenuItem(
                label: 'Batch Rent Collection...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => DesktopBatchRentModal.show(context),
              ),
              PlatformMenuItem(
                label: 'Add Expense...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyE,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => OverviewView.showExpenseSheet(context),
              ),
              PlatformMenuItem(
                label: 'Add Work Order...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => WorkOrdersView.showAddModal(context),
              ),
              PlatformMenuItem(
                label: 'Add Document...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyU,
                  meta: true,
                ),
                onSelected: () => DocumentsView.showAddModal(context),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Export Financial Report (PDF)...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyR,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => ReportsView.showExportPdf(context),
              ),
              PlatformMenuItem(
                label: 'Export Financial Report (CSV)...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => ReportsView.showExportCsv(context),
              ),
              PlatformMenuItem(
                label: 'Generate Rent Receipt & Invoice...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyI,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => DesktopRentReceiptModal.show(context),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: [
          PlatformMenuItem(
            label: 'Search / Command Palette...',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyK,
              meta: true,
            ),
            onSelected: _openCommandPalette,
          ),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Overview',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit1,
                  meta: true,
                ),
                onSelected: () => setState(() {
                  _tabIndex = 0;
                  _showSettings = false;
                }),
              ),
              PlatformMenuItem(
                label: 'Tenants & Leases',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit2,
                  meta: true,
                ),
                onSelected: () => setState(() {
                  _tabIndex = 1;
                  _showSettings = false;
                }),
              ),
              PlatformMenuItem(
                label: 'Work Orders',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit3,
                  meta: true,
                ),
                onSelected: () => setState(() {
                  _tabIndex = 2;
                  _showSettings = false;
                }),
              ),
              PlatformMenuItem(
                label: 'Document Vault',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit4,
                  meta: true,
                ),
                onSelected: () => setState(() {
                  _tabIndex = 3;
                  _showSettings = false;
                }),
              ),
              PlatformMenuItem(
                label: 'Reports & Analytics',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit5,
                  meta: true,
                ),
                onSelected: () => setState(() {
                  _tabIndex = 4;
                  _showSettings = false;
                }),
              ),
              if (showZakat)
                PlatformMenuItem(
                  label: 'Zakat Engine',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit6,
                    meta: true,
                  ),
                  onSelected: () => setState(() {
                    _tabIndex = 5;
                    _showSettings = false;
                  }),
                ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Toggle Utility Panel',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyI,
                  meta: true,
                ),
                onSelected: () => setState(
                  () => _showRightUtilityDrawer = !_showRightUtilityDrawer,
                ),
              ),
              PlatformMenuItem(
                label: 'Toggle Dark / Light Theme',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  meta: true,
                ),
                onSelected: () {
                  final nextMode = isDark ? 'light' : 'dark';
                  ref.read(appDataProvider.notifier).setThemeMode(nextMode);
                },
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Tools',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Backup & Cloud Sync...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => DocumentsView.showSyncModal(context),
              ),
              PlatformMenuItem(
                label: 'Record Owner Deposit...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => OverviewView.showDepositSheet(context),
              ),
              PlatformMenuItem(
                label: 'Generate Rent Receipt & Invoice...',
                onSelected: () => DesktopRentReceiptModal.show(context),
              ),
              PlatformMenuItem(
                label: 'Cash Flow Forecast & Financial Health...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  meta: true,
                  shift: true,
                ),
                onSelected: () {
                  final selectedYear = ref.read(appDataProvider).selectedYear;
                  DesktopCashFlowModal.show(context, year: selectedYear);
                },
              ),
              if (showZakat)
                PlatformMenuItem(
                  label: 'Zakat Calculator...',
                  onSelected: () => ZakatView.showCalculatorModal(context),
                ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Help',
        menus: [
          PlatformMenuItem(
            label: 'Command Palette & Search',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyK,
              meta: true,
            ),
            onSelected: _openCommandPalette,
          ),
          PlatformMenuItem(
            label: 'Keyboard Shortcuts Cheatsheet',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.slash,
              meta: true,
            ),
            onSelected: () => _showKeyboardShortcutsDialog(context),
          ),
          PlatformMenuItem(
            label: 'About RentManager',
            onSelected: () => _showAboutAppDialog(context),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final showZakat = s.preferences.showZakat;
    _windowWidth = MediaQuery.of(context).size.width.round();
    if (!_collapsePrefsLoaded) {
      _collapsePrefsLoaded = true;
      _userCollapsed = s.preferences.sidebarCollapsed;
    }

    final tabs = [
      const DesktopTab(
        'Overview',
        Ionicons.homeOutline,
        Ionicons.home,
        'Executive Overview',
      ),
      const DesktopTab(
        'Tenants',
        Ionicons.peopleOutline,
        Ionicons.people,
        'Tenants & Leases',
      ),
      const DesktopTab(
        'Work Orders',
        Ionicons.constructOutline,
        Ionicons.construct,
        'Maintenance & Repairs',
      ),
      const DesktopTab(
        'Documents',
        Ionicons.documentTextOutline,
        Ionicons.documentText,
        'Lease Files & Vault',
      ),
      const DesktopTab(
        'Reports',
        Ionicons.barChartOutline,
        Ionicons.barChart,
        'Financial Analytics',
      ),
      if (showZakat)
        const DesktopTab(
          'Zakat',
          Ionicons.pricetagOutline,
          Ionicons.pricetag,
          'Zakat Calculator',
        ),
    ];

    if (_tabIndex >= tabs.length) _tabIndex = 0;

    final views = [
      OverviewView(
        key: OverviewView.globalKey,
        onSettings: () => setState(() => _showSettings = true),
      ),
      TenantsView(key: TenantsView.globalKey),
      WorkOrdersView(key: WorkOrdersView.globalKey),
      DocumentsView(key: DocumentsView.globalKey),
      ReportsView(key: ReportsView.globalKey),
      if (showZakat) const ZakatView(),
    ];

    Widget body;
    if (_showSettings) {
      body = SettingsView(
        key: SettingsView.globalKey,
        onClose: () => setState(() => _showSettings = false),
      );
    } else {
      body = IndexedStack(
        index: _tabIndex.clamp(0, views.length - 1),
        children: views,
      );
    }

    return PlatformMenuBar(
      menus: _buildPlatformMenus(context, s, isDark, showZakat),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _openCommandPalette,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _openCommandPalette,
          const SingleActivator(LogicalKeyboardKey.slash, meta: true): () =>
              _showKeyboardShortcutsDialog(context),
          const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
              _showKeyboardShortcutsDialog(context),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              TenantsView.showEditModal(context),
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
            shift: true,
          ): () =>
              OverviewView.showPaymentSheet(context),
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            meta: true,
            shift: true,
          ): () =>
              DesktopBatchRentModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ): () =>
              DesktopBatchRentModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyI,
            meta: true,
            shift: true,
          ): () =>
              DesktopRentReceiptModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyI,
            control: true,
            shift: true,
          ): () =>
              DesktopRentReceiptModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            shift: true,
          ): () =>
              DesktopCashFlowModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): () =>
              DesktopCashFlowModal.show(context),
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          ): () =>
              OverviewView.showExpenseSheet(context),
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            meta: true,
            shift: true,
          ): () =>
              WorkOrdersView.showAddModal(context),
          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
              DocumentsView.showAddModal(context),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ): () =>
              DocumentsView.showSyncModal(context),
          const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            shift: true,
          ): () =>
              ReportsView.showExportPdf(context),
          const SingleActivator(
            LogicalKeyboardKey.keyC,
            meta: true,
            shift: true,
          ): () =>
              ReportsView.showExportCsv(context),
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
              ReportsView.showPrint(context),
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
              setState(() => _showSettings = true),
          const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
              setState(() {
                _tabIndex = 0;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
              setState(() {
                _tabIndex = 1;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
              setState(() {
                _tabIndex = 2;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () =>
              setState(() {
                _tabIndex = 3;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () =>
              setState(() {
                _tabIndex = 4;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.digit6, meta: true): () =>
              setState(() {
                _tabIndex = 5;
                _showSettings = false;
              }),
          const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () {
            final nextMode = isDark ? 'light' : 'dark';
            ref.read(appDataProvider.notifier).setThemeMode(nextMode);
          },
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
              _toggleSidebarCollapse,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true):
              _toggleSidebarCollapse,
          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () {
            setState(() => _showRightUtilityDrawer = !_showRightUtilityDrawer);
          },
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
            setState(() => _showRightUtilityDrawer = !_showRightUtilityDrawer);
          },
        },
        child: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackground(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // 1. Modern macOS Sidebar
                        _buildSidebar(tabs, s, isDark),

                        // 2. Main Workspace (Full functionality view with Toolbar)
                        Expanded(
                          child: SafeArea(
                            bottom: false,
                            child: Column(
                              children: [
                                if (!_showSettings)
                                  DesktopAppBar(
                                    currentTabIndex: _tabIndex,
                                    tabs: tabs,
                                    searchFocusNode: _searchFocusNode,
                                    onSelectTenant: (tenant) {
                                      setState(() {
                                        _tabIndex = 1;
                                        _showSettings = false;
                                      });
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            TenantsView.showDetails(
                                              context,
                                              tenant,
                                            );
                                          });
                                    },
                                    onLogPaymentForTenant: (tenant) {
                                      setState(() {
                                        _tabIndex = 0;
                                        _showSettings = false;
                                      });
                                      OverviewView.showPaymentSheet(
                                        context,
                                        tenant: tenant,
                                      );
                                    },
                                    onSelectWorkOrder: (workOrder) {
                                      setState(() {
                                        _tabIndex = 2;
                                        _showSettings = false;
                                      });
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            WorkOrdersView.showEditModal(
                                              context,
                                              workOrder,
                                            );
                                          });
                                    },
                                    onNavigateTab: (idx) {
                                      setState(() {
                                        _tabIndex = idx;
                                        _showSettings = false;
                                      });
                                    },
                                    onOpenSearch: _openCommandPalette,
                                    onAddTenant: () =>
                                        TenantsView.showEditModal(context),
                                    onLogPayment: () =>
                                        OverviewView.showPaymentSheet(context),
                                    onLogExpense: () =>
                                        OverviewView.showExpenseSheet(context),
                                    onDeposit: () =>
                                        OverviewView.showDepositSheet(context),
                                    onAddWorkOrder: () =>
                                        WorkOrdersView.showAddModal(context),
                                    onAddDocument: () =>
                                        DocumentsView.showAddModal(context),
                                    onSyncDocuments: () =>
                                        DocumentsView.showSyncModal(context),
                                    onSyncRoll: () =>
                                        OverviewView.showSyncSheet(context),
                                    onBatchRentCollection: () =>
                                        DesktopBatchRentModal.show(context),
                                    onGenerateReceipt: () =>
                                        DesktopRentReceiptModal.show(context),
                                    onOpenCashFlowForecast: () =>
                                        DesktopCashFlowModal.show(context),
                                    onExportCsv: () =>
                                        ReportsView.showExportCsv(context),
                                    onExportPdf: () =>
                                        ReportsView.showExportPdf(context),
                                    onPrintReport: () =>
                                        ReportsView.showPrint(context),
                                    onAddZakatInflow: showZakat
                                        ? () => ZakatView.showAddModal(
                                            context,
                                            initialType: 'inflow',
                                          )
                                        : null,
                                    onAddZakatOutflow: showZakat
                                        ? () => ZakatView.showAddModal(
                                            context,
                                            initialType: 'outflow',
                                          )
                                        : null,
                                    onOpenZakatCalculator: showZakat
                                        ? () => ZakatView.showCalculatorModal(
                                            context,
                                          )
                                        : null,
                                    onOpenSettings: () =>
                                        setState(() => _showSettings = true),
                                    onAbout: () => _showAboutAppDialog(context),
                                    onKeyboardShortcuts: () =>
                                        _showKeyboardShortcutsDialog(context),
                                    onToggleUtilityDrawer: () => setState(
                                      () => _showRightUtilityDrawer =
                                          !_showRightUtilityDrawer,
                                    ),
                                    isUtilityDrawerOpen:
                                        _showRightUtilityDrawer,
                                  ),
                                Expanded(child: body),
                              ],
                            ),
                          ),
                        ),

                        // 3. Right Utility Drawer (Collapsible)
                        if (_showRightUtilityDrawer)
                          _buildRightUtilityDrawer(s, isDark),
                      ],
                    ),
                  ),
                  // 3. Modern Desktop Status Bar (Footer)
                  _buildDesktopStatusBar(isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(List<DesktopTab> tabs, AppDataState s, bool isDark) {
    final activeColor = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF059669);
    final inactiveColor = isDark
        ? const Color(0xFFA0D8D8).withValues(alpha: 0.7)
        : const Color(0xFF64748B);
    final sidebarBg = isDark
        ? const Color(0xFF031415).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.76);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    final screenW = MediaQuery.of(context).size.width;
    final sidebarW = _effectiveCollapse
        ? 68.0
        : (screenW < 1100 ? 212.0 : 232.0);

    // Dynamic badge counters (scoped to active property)
    final activeTenantsCount = s.scopedTenants
        .where((t) => t.status == 'active')
        .length;
    final openTicketsCount = s.scopedWorkOrders
        .where((w) => w.status == 'open' || w.status == 'in_progress')
        .length;
    final docsCount = s.scopedDocuments.length;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          width: sidebarW,
          decoration: BoxDecoration(
            color: sidebarBg,
            border: Border(right: BorderSide(color: borderColor, width: 1)),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: _effectiveCollapse
                  ? 68.0
                  : (screenW < 1100 ? 212.0 : 232.0),
              child: SizedBox(
                width: _effectiveCollapse
                    ? 68.0
                    : (screenW < 1100 ? 212.0 : 232.0),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Custom macOS Window Controller Buttons (Traffic Lights)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          _effectiveCollapse ? 8 : 16,
                          14,
                          _effectiveCollapse ? 8 : 16,
                          12,
                        ),
                        child: Row(
                          mainAxisAlignment: _effectiveCollapse
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            DesktopWindowControls(
                              size: _effectiveCollapse ? 11.0 : 12.5,
                              spacing: _effectiveCollapse ? 5.5 : 7.5,
                            ),
                          ],
                        ),
                      ),

                      // Top App Branding & Sidebar Collapse Toggle
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          _effectiveCollapse ? 10 : 16,
                          0,
                          _effectiveCollapse ? 10 : 16,
                          10,
                        ),
                        child: _effectiveCollapse
                            ? Column(
                                children: [
                                  Tooltip(
                                    message:
                                        'RentManager • Property Management',
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(9),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF059669)
                                                .withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.asset(
                                        'assets/icon.png',
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF0F766E),
                                                    Color(0xFF059669),
                                                    Color(0xFF10B981),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Ionicons.business,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Tooltip(
                                    message: 'Expand Sidebar (⌘B)',
                                    waitDuration: const Duration(
                                      milliseconds: 300,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          _toggleSidebarCollapse();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        hoverColor:
                                            (isDark
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFF059669))
                                                .withValues(alpha: 0.12),
                                        child: Container(
                                          width: 30,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            color: isDark
                                                ? const Color(0xFF0A2223)
                                                : const Color(0xFFF1F5F9),
                                            border: Border.all(
                                              color: borderColor,
                                            ),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Ionicons.chevronForward,
                                              size: 13,
                                              color: activeColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(9),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF059669)
                                              .withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.asset(
                                      'assets/icon.png',
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF0F766E),
                                                  Color(0xFF059669),
                                                  Color(0xFF10B981),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Ionicons.business,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'RentManager',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          'Property Management',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.1,
                                            color: activeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Collapse Sidebar (⌘B)',
                                    waitDuration: const Duration(
                                      milliseconds: 300,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          _toggleSidebarCollapse();
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        hoverColor:
                                            (isDark
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFF059669))
                                                .withValues(alpha: 0.12),
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: borderColor,
                                            ),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Ionicons.chevronBack,
                                              size: 13,
                                              color: isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      const SizedBox(height: 4),

                      // Divider
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _effectiveCollapse ? 12 : 16,
                        ),
                        child: Divider(
                          color: borderColor,
                          height: 1,
                          thickness: 1,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Section Header (when expanded)
                      if (!_effectiveCollapse)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 4,
                          ),
                          child: Text(
                            'MAIN MENU',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),

                      // Tab navigation list
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal: _effectiveCollapse ? 8 : 12,
                            vertical: 4,
                          ),
                          children: [
                            for (var i = 0; i < tabs.length; i++) ...[
                              () {
                                String? badge;
                                Color? bColor;
                                Color? bTextColor;

                                if (i == 1 && activeTenantsCount > 0) {
                                  badge = '$activeTenantsCount';
                                } else if (i == 2 && openTicketsCount > 0) {
                                  badge = '$openTicketsCount';
                                  bColor = const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.20);
                                  bTextColor = const Color(0xFFF59E0B);
                                } else if (i == 3 && docsCount > 0) {
                                  badge = '$docsCount';
                                }

                                return _sidebarNavItem(
                                  index: i,
                                  tab: tabs[i],
                                  isSelected: i == _tabIndex && !_showSettings,
                                  isDark: isDark,
                                  activeColor: activeColor,
                                  inactiveColor: inactiveColor,
                                  badgeText: badge,
                                  badgeColor: bColor,
                                  badgeTextColor: bTextColor,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _tabIndex = i;
                                      _showSettings = false;
                                    });
                                  },
                                );
                              }(),
                            ],
                          ],
                        ),
                      ),

                      // Property Information Card (Sidebar Bottom)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _effectiveCollapse ? 8 : 12,
                          vertical: 4,
                        ),
                        child: _buildSidebarPropertyCard(
                          s,
                          isDark,
                          activeColor,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Bottom Section: Settings & Theme Switch
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _effectiveCollapse ? 12 : 16,
                        ),
                        child: Divider(color: borderColor, height: 1),
                      ),

                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          _effectiveCollapse ? 8 : 12,
                          10,
                          _effectiveCollapse ? 8 : 12,
                          14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildSidebarIconButton(
                                icon: _showSettings
                                    ? Ionicons.settings
                                    : Ionicons.settingsOutline,
                                tooltip: 'Settings & Preferences (⌘,)',
                                isSelected: _showSettings,
                                isDark: isDark,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(
                                    () => _showSettings = !_showSettings,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSidebarIconButton(
                                icon: isDark ? Ionicons.moon : Ionicons.sunny,
                                tooltip: isDark
                                    ? 'Switch to Light Mode (⌘T)'
                                    : 'Switch to Dark Mode (⌘T)',
                                iconColor: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFF59E0B),
                                isSelected: false,
                                isDark: isDark,
                                onTap: () {
                                  final nextMode = isDark ? 'light' : 'dark';
                                  ref
                                      .read(appDataProvider.notifier)
                                      .setThemeMode(nextMode);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _occupancyColor(double ratio) {
    if (ratio >= 0.8) return const Color(0xFF10B981);
    if (ratio >= 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  void _showPropertyMenu(BuildContext context) async {
    final s = ref.read(appDataProvider);
    final isDark = AppColors.isDark;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    if (s.properties.isEmpty) {
      final pm = s.propertyManager;
      if (pm != null) {
        _showPropertyInfoDialog(context, s);
      } else {
        DesktopPropertyModal.show(context);
      }
      return;
    }

    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final cardRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final collapsed = _effectiveCollapse;
    final menuRect = collapsed
        ? Rect.fromLTRB(
            cardRect.right + 8,
            cardRect.top - 4,
            cardRect.right + 348,
            cardRect.top + 456,
          )
        : Rect.fromLTRB(
            cardRect.left,
            cardRect.bottom + 6,
            cardRect.left + 340,
            cardRect.bottom + 466,
          );

    final bg = isDark ? const Color(0xFF071F20) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);
    final textPrimary = AppColors.heading;
    final textMuted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    int activeTenantsFor(dynamic p) => s.tenants
        .where(
          (t) =>
              (t.propertyId.isEmpty ? 'prop-default' : t.propertyId) == p.id &&
              t.status == 'active',
        )
        .length;

    int tenantsFor(dynamic p) => s.tenants
        .where(
          (t) => (t.propertyId.isEmpty ? 'prop-default' : t.propertyId) == p.id,
        )
        .length;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(menuRect, Offset.zero & overlayBox.size),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'PROPERTIES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: textMuted,
            ),
          ),
        ),

        ...s.properties.map((p) {
          final isSelected =
              s.selectedPropertyId == p.id ||
              (s.selectedPropertyId != 'all' && s.selectedPropertyId.isEmpty);
          final activeCount = activeTenantsFor(p);
          final total = p.totalUnits > 0 ? p.totalUnits : tenantsFor(p);
          final ratio = total > 0 ? (activeCount / total).clamp(0.0, 1.0) : 0.0;
          final ocColor = _occupancyColor(ratio);

          return PopupMenuItem<String>(
            value: 'prop:${p.id}',
            height: 58,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0F766E).withValues(alpha: 0.18)
                        : (isDark
                              ? const Color(0xFF0F2627)
                              : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    _iconForType(p.propertyType),
                    size: 17,
                    color: isSelected ? const Color(0xFF14B8A6) : textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.address.isNotEmpty
                                  ? p.address
                                  : p.propertyType.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 36,
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0F2627)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: ratio <= 0
                                    ? 0.0
                                    : ratio.clamp(0.08, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: ocColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$activeCount/$total',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Ionicons.checkmark,
                    size: 15,
                    color: Color(0xFF14B8A6),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  icon: Icon(
                    Ionicons.settingsOutline,
                    size: 14,
                    color: textMuted,
                  ),
                  tooltip: 'Property Settings',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    DesktopPropertyModal.show(context, property: p);
                  },
                ),
              ],
            ),
          );
        }),

        if (s.activeProperty != null) ...[
          const PopupMenuDivider(height: 12),
          PopupMenuItem<String>(
            value: 'info',
            height: 40,
            child: Row(
              children: [
                Icon(
                  Ionicons.informationCircleOutline,
                  size: 16,
                  color: textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  'Property Information…',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],

        const PopupMenuDivider(height: 12),

        // Action: Add Property
        PopupMenuItem<String>(
          value: 'add_new',
          height: 44,
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.add,
                  size: 16,
                  color: Color(0xFF14B8A6),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Add New Property...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF14B8A6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    if (selected == 'add_new') {
      if (context.mounted) {
        DesktopPropertyModal.show(context);
      }
    } else if (selected == 'info') {
      if (context.mounted) {
        _showPropertyInfoDialog(context, s);
      }
    } else if (selected.startsWith('prop:')) {
      ref.read(appDataProvider.notifier).selectProperty(selected.substring(5));
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'commercial':
        return Ionicons.briefcaseOutline;
      case 'mixed':
        return Ionicons.businessOutline;
      case 'villa':
        return Ionicons.storefrontOutline;
      case 'residential':
      default:
        return Ionicons.homeOutline;
    }
  }

  Widget _buildSidebarPropertyCard(
    AppDataState s,
    bool isDark,
    Color activeColor,
  ) {
    if (_effectiveCollapse) {
      return Center(
        child: Tooltip(
          message: 'Switch Property',
          child: InkWell(
            onTap: () => _showPropertyMenu(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Ionicons.business, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    final String propName;
    final int activeUnits;
    final int totalUnits;
    if (s.properties.isNotEmpty) {
      final active = s.activeProperty;
      if (active != null) {
        propName = active.name;
        activeUnits = s.scopedTenants.where((t) => t.status == 'active').length;
        totalUnits = active.totalUnits > 0
            ? active.totalUnits
            : s.scopedTenants.length;
      } else {
        final pm = s.propertyManager;
        propName = (pm?.propertyName?.isNotEmpty == true)
            ? pm!.propertyName!
            : (pm?.name.isNotEmpty == true
                  ? '${pm!.name} Property'
                  : 'My Property');
        activeUnits = s.scopedTenants.where((t) => t.status == 'active').length;
        totalUnits = s.scopedTenants.length;
      }
    } else {
      final pm = s.propertyManager;
      propName = (pm?.propertyName?.isNotEmpty == true)
          ? pm!.propertyName!
          : (pm?.name.isNotEmpty == true
                ? '${pm!.name} Property'
                : 'My Property');
      activeUnits = s.scopedTenants.where((t) => t.status == 'active').length;
      totalUnits = s.scopedTenants.where((t) => t.status != 'archived').length;
    }

    final double occupancyRatio = totalUnits > 0
        ? (activeUnits / totalUnits).clamp(0.0, 1.0)
        : 0.0;

    return Tooltip(
      message: 'View & Edit Property Information',
      child: InkWell(
        onTap: () => _showPropertyInfoDialog(context, s),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7.5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF092021) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: Icon(Ionicons.business, size: 14, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      propName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      '$activeUnits Active • $totalUnits Units',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _occupancyColor(occupancyRatio),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 2),
              // Switcher trigger — tappable, overrides card tap
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showPropertyMenu(context),
                child: Container(
                  width: 26,
                  height: 34,
                  alignment: Alignment.center,
                  child: Icon(
                    Ionicons.chevronDown,
                    size: 13,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    );
  }

  void _showPropertyInfoDialog(BuildContext context, AppDataState s) {
    final isDark = AppColors.isDark;
    final bg = isDark ? const Color(0xFF091E1F) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final pm = s.propertyManager;
    final ownerFallback = (pm?.ownerName?.isNotEmpty == true)
        ? pm!.ownerName!
        : (pm?.name.isNotEmpty == true ? pm!.name : 'Landlord Profile');

    final String propName;
    final String propAddress;
    final String ownerName = ownerFallback;
    final int activeTenants;
    final int totalUnits;

    if (s.properties.isNotEmpty) {
      final active = s.activeProperty;
      if (active != null) {
        propName = active.name;
        propAddress = active.address.isNotEmpty
            ? active.address
            : 'No address set';
        activeTenants = s.scopedTenants
            .where((t) => t.status == 'active')
            .length;
        totalUnits = active.totalUnits > 0
            ? active.totalUnits
            : s.scopedTenants.length;
      } else {
        propName = (pm?.propertyName?.isNotEmpty == true)
            ? pm!.propertyName!
            : (pm?.name.isNotEmpty == true
                  ? '${pm!.name} Property'
                  : 'My Property');
        propAddress = pm?.address.isNotEmpty == true
            ? pm!.address
            : 'No address set';
        activeTenants = s.scopedTenants
            .where((t) => t.status == 'active')
            .length;
        totalUnits = s.scopedTenants.length;
      }
    } else {
      propName = (pm?.propertyName?.isNotEmpty == true)
          ? pm!.propertyName!
          : (pm?.name.isNotEmpty == true
                ? '${pm!.name} Property'
                : 'My Property');
      propAddress = pm?.address.isNotEmpty == true
          ? pm!.address
          : 'No address set';
      activeTenants = s.scopedTenants.where((t) => t.status == 'active').length;
      totalUnits = s.scopedTenants.where((t) => t.status != 'archived').length;
    }

    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(
                          Ionicons.business,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Property Information',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            propName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Managed by $ownerName',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Ionicons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Details Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF061818)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      _propInfoRow('Address', propAddress, isDark),
                      _propInfoRow(
                        'Phone',
                        pm?.phone.isNotEmpty == true
                            ? pm!.phone
                            : 'No phone set',
                        isDark,
                      ),
                      _propInfoRow(
                        'Email',
                        pm?.email.isNotEmpty == true
                            ? pm!.email
                            : 'No email set',
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Operational Stats
                Row(
                  children: [
                    Expanded(
                      child: _propStatPill(
                        'Active Units',
                        '$activeTenants / $totalUnits',
                        const Color(0xFF10B981),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _propStatPill(
                        'Work Orders',
                        '${s.scopedWorkOrders.length}',
                        const Color(0xFFF59E0B),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _propStatPill(
                        'Documents',
                        '${s.scopedDocuments.length}',
                        const Color(0xFF8B5CF6),
                        isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          if (s.activeProperty != null) {
                            DesktopPropertyModal.show(
                              context,
                              property: s.activeProperty,
                            );
                          } else {
                            DesktopPropertyModal.show(context);
                          }
                        },
                        icon: const Icon(Ionicons.createOutline, size: 15),
                        label: const Text('Edit Details'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
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

  Widget _propInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.heading,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _propStatPill(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.25 : 0.15),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarNavItem({
    required int index,
    required DesktopTab tab,
    required bool isSelected,
    required bool isDark,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
    String? badgeText,
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    final shortcutKey = '⌘${index + 1}';
    final tooltipText = '${tab.label} ($shortcutKey)';

    if (_effectiveCollapse) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Tooltip(
            message: tooltipText,
            waitDuration: const Duration(milliseconds: 300),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                hoverColor:
                    (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                        .withValues(alpha: 0.10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isSelected
                        ? (isDark
                              ? const Color(0xFF059669).withValues(alpha: 0.22)
                              : const Color(0xFF059669).withValues(alpha: 0.14))
                        : Colors.transparent,
                    border: isSelected
                        ? Border.all(
                            color: isDark
                                ? const Color(0xFF34D399)
                                      .withValues(alpha: 0.35)
                                : const Color(0xFF059669)
                                      .withValues(alpha: 0.30),
                            width: 1,
                          )
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isSelected)
                        Positioned(
                          left: 0,
                          top: 10,
                          bottom: 10,
                          child: Container(
                            width: 3.5,
                            decoration: BoxDecoration(
                              color: activeColor,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(2),
                                bottomRight: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      Icon(
                        isSelected ? tab.filled : tab.outlined,
                        size: 19,
                        color: isSelected ? activeColor : inactiveColor,
                      ),
                      if (badgeText != null && badgeText.isNotEmpty)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: badgeColor ?? activeColor,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF041213)
                                    : Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor:
              (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                  .withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isSelected
                  ? (isDark
                        ? const Color(0xFF059669).withValues(alpha: 0.18)
                        : const Color(0xFF059669).withValues(alpha: 0.12))
                  : Colors.transparent,
              border: isSelected
                  ? Border.all(
                      color: isDark
                          ? const Color(0xFF34D399).withValues(alpha: 0.30)
                          : const Color(0xFF059669).withValues(alpha: 0.25),
                      width: 1,
                    )
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: isSelected ? 3.5 : 0,
                  height: 18,
                  margin: EdgeInsets.only(right: isSelected ? 8 : 0),
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  isSelected ? tab.filled : tab.outlined,
                  size: 18,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? (AppColors.heading)
                          : (isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF334155)),
                    ),
                  ),
                ),
                if (badgeText != null && badgeText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color:
                          badgeColor ??
                          (isDark
                              ? const Color(0xFF0E2F2F)
                              : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color:
                            badgeTextColor ??
                            (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                      ),
                    ),
                  )
                else if (isSelected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarIconButton({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final activeGradient = const LinearGradient(
      colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final defaultGradient = LinearGradient(
      colors: isDark
          ? const [Color(0xFF0C2425), Color(0xFF07191A)]
          : const [Colors.white, Color(0xFFF1F5F9)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final resolvedIconColor = isSelected
        ? Colors.white
        : (iconColor ??
              (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)));

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor:
              (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                  .withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 34,
            decoration: BoxDecoration(
              gradient: isSelected ? activeGradient : defaultGradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? Colors.transparent
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFCBD5E1).withValues(alpha: 0.75)),
                width: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? const Color(0xFF0F766E).withValues(alpha: 0.38)
                      : (isDark
                            ? Colors.black.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.04)),
                  blurRadius: isSelected ? 5 : 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, size: 16, color: resolvedIconColor),
            ),
          ),
        ),
      ),
    );
  }

  void _showDesktopCurrencyPopover(
    BuildContext context,
    String currentCurrency,
    bool isDark,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Currency Popover',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogCtx, anim1, anim2) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = kCurrencyOptions.where((c) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase().trim();
              return c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase().contains(q) ||
                  c.symbol.toLowerCase().contains(q);
            }).toList();

            return Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 70, bottom: 36),
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        width: 330,
                        constraints: const BoxConstraints(maxHeight: 460),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF091E1F).withValues(alpha: 0.92)
                              : Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF34D399)
                                      .withValues(alpha: 0.28)
                                : const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.45 : 0.16,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                            if (isDark)
                              BoxShadow(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.12),
                                blurRadius: 20,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                12,
                                10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isDark
                                            ? const [
                                                Color(0xFF0F766E),
                                                Color(0xFF10B981),
                                              ]
                                            : const [
                                                Color(0xFF059669),
                                                Color(0xFF10B981),
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.3),
                                          blurRadius: 5,
                                          offset: const Offset(0, 1.5),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Ionicons.cashOutline,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Active Currency',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.heading,
                                          ),
                                        ),
                                        Text(
                                          'Instant financial engine switch',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: isDark
                                                ? const Color(0xFF64748B)
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Ionicons.close, size: 16),
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    onPressed: () =>
                                        Navigator.of(dialogCtx).pop(),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    splashRadius: 14,
                                  ),
                                ],
                              ),
                            ),

                            // Search bar
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF051718)
                                            .withValues(alpha: 0.7)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color.fromRGBO(
                                            255,
                                            255,
                                            255,
                                            0.08,
                                          )
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: TextField(
                                  autofocus: false,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.heading,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    hintText:
                                        'Search currency, code, symbol...',
                                    hintStyle: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    prefixIcon: Icon(
                                      Ionicons.searchOutline,
                                      size: 13,
                                      color: isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (val) {
                                    setModalState(() => searchQuery = val);
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            // List of currencies
                            Flexible(
                              child: filtered.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No matching currencies',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? const Color(0xFF64748B)
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 4),
                                      itemBuilder: (ctx, i) {
                                        final opt = filtered[i];
                                        final isSelected =
                                            opt.symbol == currentCurrency;

                                        return Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              ref
                                                  .read(
                                                    appDataProvider.notifier,
                                                  )
                                                  .setCurrency(opt.symbol);
                                              Navigator.of(dialogCtx).pop();
                                              showAppToast(
                                                context,
                                                'Currency changed to ${opt.flag} ${opt.symbol} (${opt.code})',
                                                isError: false,
                                              );
                                            },
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 150,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 7,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? (isDark
                                                          ? const Color(
                                                              0xFF0F766E,
                                                            ).withValues(
                                                              alpha: 0.28,
                                                            )
                                                          : const Color(
                                                              0xFFECFDF5,
                                                            ))
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? (isDark
                                                            ? const Color(
                                                                0xFF34D399,
                                                              )
                                                            : const Color(
                                                                0xFF059669,
                                                              ))
                                                      : Colors.transparent,
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF0C2425,
                                                            )
                                                          : const Color(
                                                              0xFFF1F5F9,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isDark
                                                            ? const Color.fromRGBO(
                                                                255,
                                                                255,
                                                                255,
                                                                0.06,
                                                              )
                                                            : const Color(
                                                                0xFFE2E8F0,
                                                              ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          opt.flag,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 13.5,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          opt.symbol,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: isSelected
                                                                ? (isDark
                                                                      ? const Color(
                                                                          0xFF34D399,
                                                                        )
                                                                      : const Color(
                                                                          0xFF059669,
                                                                        ))
                                                                : (AppColors
                                                                      .heading),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          opt.name,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                isSelected
                                                                ? FontWeight
                                                                      .w700
                                                                : FontWeight
                                                                      .w500,
                                                            color: AppColors
                                                                .heading,
                                                          ),
                                                        ),
                                                        Text(
                                                          opt.code,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF64748B,
                                                                  )
                                                                : const Color(
                                                                    0xFF94A3B8,
                                                                  ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (isSelected)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            3,
                                                          ),
                                                      decoration:
                                                          const BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color: Color(
                                                              0xFF10B981,
                                                            ),
                                                          ),
                                                      child: const Icon(
                                                        Icons.check,
                                                        size: 11,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDesktopAboutDialog(BuildContext context, bool isDark) {
    final s = ref.read(appDataProvider);
    final totalTenants = s.tenants.length;
    final totalUnits = s.tenants
        .map((t) => t.unit)
        .where((u) => u.trim().isNotEmpty)
        .toSet()
        .length;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss About Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogCtx, anim1, anim2) {
        bool checkingUpdate = false;
        UpdateCheckResult? updateResult;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      width: 410,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF07191A).withValues(alpha: 0.94)
                            : Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF34D399).withValues(alpha: 0.3)
                              : const Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.55 : 0.2,
                            ),
                            blurRadius: 36,
                            offset: const Offset(0, 16),
                          ),
                          if (isDark)
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.15),
                              blurRadius: 24,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Row: Close icon
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              InkWell(
                                onTap: () => Navigator.of(dialogCtx).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                  child: Icon(
                                    Ionicons.close,
                                    size: 14,
                                    color: isDark
                                        ? const Color(0xFFA0D8D8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Brand Icon with gradient and glow
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x5510B981),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Ionicons.business,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // App Name
                          Text(
                            'RentManager Pro',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Version Pill Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF10B981)
                                        .withValues(alpha: 0.15)
                                  : const Color(0xFF10B981)
                                        .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'v1.0.6 • Production Release',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          Text(
                            'Modern Property & Rental Management for macOS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFFA0D8D8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // System Details Matrix Card
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.07)
                                    : const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildAboutInfoRow(
                                  icon: Ionicons.serverOutline,
                                  label: 'Database Engine',
                                  value: 'Offline-First SQLite',
                                  isDark: isDark,
                                ),
                                const Divider(height: 14, thickness: 0.6),
                                _buildAboutInfoRow(
                                  icon: Ionicons.cloudDoneOutline,
                                  label: 'Cloud Backup',
                                  value: DriveBackupService.isSignedIn
                                      ? 'Google Drive Active'
                                      : 'Drive Sync Ready',
                                  isDark: isDark,
                                  valueColor: DriveBackupService.isSignedIn
                                      ? const Color(0xFF10B981)
                                      : null,
                                ),
                                const Divider(height: 14, thickness: 0.6),
                                _buildAboutInfoRow(
                                  icon: Ionicons.hardwareChipOutline,
                                  label: 'Active Workspace',
                                  value:
                                      '$totalTenants Tenants • $totalUnits Units',
                                  isDark: isDark,
                                ),
                                const Divider(height: 14, thickness: 0.6),
                                _buildAboutInfoRow(
                                  icon: Ionicons.shieldCheckmarkOutline,
                                  label: 'Security & Privacy',
                                  value: 'Zero Telemetry • Encrypted',
                                  isDark: isDark,
                                  valueColor: const Color(0xFF10B981),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          if (checkingUpdate || updateResult != null) ...[
                            _buildUpdateStatus(
                              result: updateResult,
                              checking: checkingUpdate,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Actions Row: Check for updates & Done button
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: checkingUpdate
                                      ? null
                                      : () async {
                                          setDialogState(() {
                                            checkingUpdate = true;
                                            updateResult = null;
                                          });
                                          final result =
                                              await UpdateService.checkForUpdates();
                                          if (!dialogCtx.mounted) return;
                                          setDialogState(() {
                                            checkingUpdate = false;
                                            updateResult = result;
                                          });
                                        },
                                  icon: checkingUpdate
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.6,
                                            color: Color(0xFF38BDF8),
                                          ),
                                        )
                                      : const Icon(
                                          Ionicons.refreshOutline,
                                          size: 14,
                                        ),
                                  label: Text(
                                    checkingUpdate
                                        ? 'Checking...'
                                        : 'Check Updates',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    side: BorderSide(
                                      color: isDark
                                          ? const Color(0xFF34D399)
                                                .withValues(alpha: 0.4)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                    foregroundColor: isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF0F766E),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'Done',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
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
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAboutInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 13.5,
          color: isDark ? const Color(0xFFA0D8D8) : const Color(0xFF64748B),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? const Color(0xFFA0D8D8).withValues(alpha: 0.8)
                  : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor ?? (AppColors.heading),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateStatus({
    required UpdateCheckResult? result,
    required bool checking,
    required bool isDark,
  }) {
    if (checking) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF38BDF8).withValues(alpha: 0.1)
              : const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          ),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Color(0xFF38BDF8),
              ),
            ),
            SizedBox(width: 9),
            Text(
              'Checking for updates...',
              style: TextStyle(
                fontSize: 11.5,
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
            'A newer version of RentManager is ready to download.';
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: isDark
                  ? const Color(0xFFA0D8D8).withValues(alpha: 0.85)
                  : const Color(0xFF64748B),
            ),
          ),
          if (result.updateAvailable && result.hasDownload) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
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
                icon: const Icon(Ionicons.downloadOutline, size: 13),
                label: const Text(
                  'Download Update',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contextualChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? tooltip,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 4.5),
              Text(
                '$label: ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                  letterSpacing: 0.1,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.heading,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildContextualStatBadge(
    BuildContext context,
    AppDataState s,
    bool isDark,
    bool isCompact, [
    double maxWidth = 1200,
  ]) {
    if (_showSettings) {
      return const SizedBox.shrink();
    }

    final currency = s.selectedCurrency.isEmpty ? '\$' : s.selectedCurrency;
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = s.selectedYear;

    switch (_tabIndex) {
      case 0: // Overview
        final targetMonthKey =
            '$currentYear-${currentMonth.toString().padLeft(2, '0')}';
        final activeTenants = s.scopedTenants
            .where((t) => t.status == 'active')
            .toList();
        final expectedRent = activeTenants.fold<double>(
          0,
          (sum, t) => sum + t.rentAmount,
        );
        final paidPayments = s.scopedPayments.where((p) {
          final d =
              p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? p.dueDate ?? '';
          return p.status == 'paid' && d.startsWith(targetMonthKey);
        }).toList();
        final collectedRent = paidPayments.fold<double>(
          0,
          (sum, p) => sum + p.amount,
        );
        final paidTenantIds = paidPayments.map((p) => p.tenantId).toSet();
        final unpaidCount = activeTenants
            .where((t) => !paidTenantIds.contains(t.id))
            .length;
        final pct = expectedRent > 0
            ? ((collectedRent / expectedRent) * 100).clamp(0, 100).round()
            : 0;
        final monthExpenses = s.scopedExpenses.where((e) {
          final d = e.expenseForMonth ?? e.displayMonth ?? e.paidDate ?? e.date;
          return d.startsWith(targetMonthKey);
        }).toList();
        final totalExpenses = monthExpenses.fold<double>(
          0,
          (sum, e) => sum + e.amount,
        );

        final rollText = unpaidCount > 0 ? '$pct% ($unpaidCount Due)' : '$pct%';
        final expText = '$currency${totalExpenses.toStringAsFixed(0)}';

        return _contextualChip(
          icon: Ionicons.pieChartOutline,
          iconColor: unpaidCount > 0
              ? const Color(0xFFF59E0B)
              : const Color(0xFF10B981),
          label: 'Roll',
          value: '$rollText   •   Exp: $expText',
          tooltip:
              'Rent Roll: $currency${collectedRent.toStringAsFixed(0)} / $currency${expectedRent.toStringAsFixed(0)} ($pct%)\nExpenses: $currency${totalExpenses.toStringAsFixed(0)} for $targetMonthKey (${monthExpenses.length} entries)',
          isDark: isDark,
        );

      case 1: // Tenants & Leases
        final tenantUnitCount = s.scopedTenants
            .map((t) => t.unit)
            .where((u) => u.trim().isNotEmpty)
            .toSet()
            .length;
        final propertyUnitCount = s.activeProperty?.totalUnits ?? 0;
        final totalUnits = propertyUnitCount > 0
            ? propertyUnitCount
            : tenantUnitCount;
        final occupiedUnits = s.scopedTenants
            .where((t) => t.status == 'active')
            .map((t) => t.unit)
            .where((u) => u.trim().isNotEmpty)
            .toSet()
            .length;
        final occupancy = totalUnits > 0
            ? ((occupiedUnits / totalUnits) * 100).clamp(0, 100).round()
            : 0;

        return _contextualChip(
          icon: Ionicons.keyOutline,
          iconColor: const Color(0xFF38BDF8),
          label: 'Occupancy',
          value: '$occupancy% ($occupiedUnits/$totalUnits)',
          tooltip: 'Unit occupancy rate across active leases',
          isDark: isDark,
        );

      case 2: // Work Orders
        final activeRepairs = s.scopedWorkOrders
            .where((w) => w.status == 'open' || w.status == 'in_progress')
            .length;
        final completedRepairs = s.scopedWorkOrders
            .where((w) => w.status == 'completed')
            .length;

        return _contextualChip(
          icon: Ionicons.buildOutline,
          iconColor: activeRepairs > 0
              ? const Color(0xFFF97316)
              : const Color(0xFF10B981),
          label: 'Repairs',
          value: activeRepairs > 0
              ? '$activeRepairs Active'
              : '$completedRepairs Done',
          tooltip: 'Active and completed work orders',
          isDark: isDark,
        );

      case 3: // Documents Vault
        final totalDocs = s.scopedDocuments.length;

        return _contextualChip(
          icon: Ionicons.folderOpenOutline,
          iconColor: const Color(0xFFA855F7),
          label: 'Vault',
          value: '$totalDocs Files',
          tooltip: 'Stored lease agreements, receipts & property files',
          isDark: isDark,
        );

      case 4: // Reports & Analytics
        final yearStr = '$currentYear';
        final yearIncome = s.scopedPayments
            .where((p) {
              final d =
                  p.paidForMonth ??
                  p.displayMonth ??
                  p.paidDate ??
                  p.dueDate ??
                  '';
              return p.status == 'paid' && d.startsWith(yearStr);
            })
            .fold<double>(0, (sum, p) => sum + p.amount);
        final yearExpenses = s.scopedExpenses
            .where((e) {
              final d =
                  e.expenseForMonth ?? e.displayMonth ?? e.paidDate ?? e.date;
              return d.startsWith(yearStr);
            })
            .fold<double>(0, (sum, e) => sum + e.amount);
        final netCash = yearIncome - yearExpenses;

        return _contextualChip(
          icon: Ionicons.trendingUpOutline,
          iconColor: netCash >= 0
              ? const Color(0xFF10B981)
              : const Color(0xFFEF4444),
          label: 'Net',
          value:
              '${netCash >= 0 ? '+' : ''}$currency${netCash.abs().toStringAsFixed(0)}',
          tooltip:
              'Year-to-date net cashflow ($currentYear): Income $currency${yearIncome.toStringAsFixed(0)} - Expenses $currency${yearExpenses.toStringAsFixed(0)}',
          isDark: isDark,
        );

      case 5: // Zakat Engine
        final distributed = s.scopedZakat
            .where((z) => z.type == 'outflow')
            .fold<double>(0, (sum, z) => sum + z.amount);

        return _contextualChip(
          icon: Ionicons.heartOutline,
          iconColor: const Color(0xFFEC4899),
          label: 'Zakat',
          value: '$currency${distributed.toStringAsFixed(0)}',
          tooltip: 'Total Zakat distributed to beneficiaries',
          isDark: isDark,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDesktopStatusBar(bool isDark) {
    final s = ref.watch(appDataProvider);
    final totalTenants = s.scopedTenants.length;
    final activeTenants = s.scopedTenants
        .where((t) => t.status == 'active')
        .length;
    final totalUnits =
        (s.activeProperty != null && s.activeProperty!.totalUnits > 0
        ? s.activeProperty!.totalUnits
        : s.scopedTenants
              .map((t) => t.unit)
              .where((u) => u.trim().isNotEmpty)
              .toSet()
              .length);
    final currency = s.selectedCurrency.isEmpty ? '\$' : s.selectedCurrency;
    final storageReady = AppStorage.isReady;
    final driveAutoSync = s.preferences.driveAutoSync;
    final lastDriveSync = s.preferences.lastDriveSync;

    final barBg = isDark
        ? const Color(0xFF041213).withValues(alpha: 0.70)
        : const Color(0xFFF8FAFC).withValues(alpha: 0.75);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final textMuted = isDark
        ? const Color(0xFFA0D8D8).withValues(alpha: 0.7)
        : const Color(0xFF64748B);
    final textBold = isDark ? Colors.white : const Color(0xFF1E293B);

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 1000;
          final isUltraCompact = constraints.maxWidth < 800;
          final showCenterStat = constraints.maxWidth >= 900 && !_showSettings;
          final isMacPlatform =
              Theme.of(context).platform == TargetPlatform.macOS;
          final shortcutHint = isMacPlatform ? '⌘K' : 'Ctrl+K';
          final showShortcutHint =
              !isUltraCompact &&
              (isMacPlatform || constraints.maxWidth >= 1320);

          return Row(
            children: [
              // ==========================================
              // 1. LEFT SIDE FUNCTIONS (Aligned to Left)
              // ==========================================
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live Database / Storage Status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: storageReady
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (storageReady
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444))
                                      .withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        storageReady
                            ? (isUltraCompact ? 'Local' : 'Local Storage')
                            : (isUltraCompact ? 'Error' : 'Storage Error'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: storageReady
                              ? (isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669))
                              : const Color(0xFFEF4444),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                  _statusDivider(borderColor),

                  // Backup & Sync Status
                  InkWell(
                    onTap: () => showGoogleDriveSheet(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          DriveBackupService.syncStatus,
                          DriveBackupService.signedIn,
                        ]),
                        builder: (context, _) {
                          final status = DriveBackupService.syncStatus.value;
                          final signedIn = DriveBackupService.signedIn.value;
                          final hasSynced =
                              lastDriveSync != null && lastDriveSync.isNotEmpty;
                          Widget iconWidget;
                          Color statusColor;
                          String statusText;

                          if (status == DriveSyncStatus.syncing) {
                            statusColor = const Color(0xFF38BDF8);
                            statusText = 'Syncing...';
                            iconWidget = const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF38BDF8),
                              ),
                            );
                          } else if (status == DriveSyncStatus.error) {
                            statusColor = const Color(0xFFF59E0B);
                            statusText = 'Sync Paused';
                            iconWidget = Icon(
                              Ionicons.alertCircleOutline,
                              size: 13,
                              color: statusColor,
                            );
                          } else if (signedIn && driveAutoSync) {
                            statusColor = hasSynced
                                ? const Color(0xFF10B981)
                                : (isDark
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFF0284C7));
                            statusText = 'Drive Sync';
                            iconWidget = Icon(
                              hasSynced
                                  ? Ionicons.cloudDoneOutline
                                  : Ionicons.cloudUploadOutline,
                              size: 13,
                              color: statusColor,
                            );
                          } else {
                            statusColor = textMuted;
                            statusText = 'Drive Sync';
                            iconWidget = Icon(
                              Ionicons.cloudOfflineOutline,
                              size: 13,
                              color: statusColor,
                            );
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              iconWidget,
                              const SizedBox(width: 5),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  _statusDivider(borderColor),

                  // Active Tenants Metric
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Ionicons.peopleOutline,
                        size: 12.5,
                        color: textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$activeTenants',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: textBold,
                              ),
                            ),
                            TextSpan(
                              text: isCompact
                                  ? ' Tenants'
                                  : ' / $totalTenants Tenants',
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Units Count (hidden on compact screens)
                  if (!isCompact && totalUnits > 0) ...[
                    _statusDivider(borderColor),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.homeOutline, size: 12, color: textMuted),
                        const SizedBox(width: 5),
                        Text(
                          '$totalUnits Units',
                          style: TextStyle(
                            fontSize: 11,
                            color: textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              const Spacer(),

              // ==========================================
              // 2. CENTER FUNCTIONS (Contextual Screen Stats)
              // ==========================================
              if (showCenterStat) ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey('${_showSettings}_$_tabIndex'),
                    child: _buildContextualStatBadge(
                      context,
                      s,
                      isDark,
                      isCompact,
                      constraints.maxWidth,
                    ),
                  ),
                ),
                const Spacer(),
              ],

              // ==========================================
              // 3. RIGHT SIDE FUNCTIONS (Aligned to Right)
              // ==========================================
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Active Currency (Direct Quick Switcher)
                  Material(
                    color: Colors.transparent,
                    child: Tooltip(
                      message: 'Quick switch currency (currently $currency)',
                      waitDuration: const Duration(milliseconds: 350),
                      child: InkWell(
                        onTap: () => _showDesktopCurrencyPopover(
                          context,
                          currency,
                          isDark,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isCompact)
                                Text(
                                  'Currency: ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              Text(() {
                                final hit = kCurrencyOptions.where(
                                  (c) => c.symbol == currency,
                                );
                                return hit.isNotEmpty ? hit.first.flag : '💵';
                              }(), style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                currency,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF0F766E),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Ionicons.chevronUp,
                                size: 10,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF0F766E),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _statusDivider(borderColor),

                  // Command palette shortcut hint (hidden on ultra compact)
                  if (showShortcutHint) ...[
                    InkWell(
                      onTap: _openCommandPalette,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMacPlatform
                                  ? Icons.keyboard_command_key
                                  : Icons.keyboard_control_key,
                              size: 13,
                              color: textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              shortcutHint,
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _statusDivider(borderColor),
                  ],

                  // App Version (Clickable for App Details)
                  Material(
                    color: Colors.transparent,
                    child: Tooltip(
                      message:
                          'About RentManager Pro (v1.0.6) • Click for details',
                      waitDuration: const Duration(milliseconds: 350),
                      child: InkWell(
                        onTap: () => _showDesktopAboutDialog(context, isDark),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            'v1.0.6',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textMuted.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusDivider(Color color) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: color,
    );
  }

  Widget _buildRightUtilityDrawer(AppDataState s, bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final cur = s.selectedCurrency;

    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061516) : const Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: borderColor, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header Bar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Ionicons.browsersOutline,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Utility Panel',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Close Panel (⌘I)',
                    child: InkWell(
                      onTap: () =>
                          setState(() => _showRightUtilityDrawer = false),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Ionicons.close,
                          size: 15,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab Selector Row
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderColor, width: 1),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color:
                      (isDark
                              ? const Color(0xFF0B2223)
                              : const Color(0xFFE2E8F0))
                          .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildUtilityTabButton(
                      0,
                      'Scratchpad',
                      Ionicons.createOutline,
                      isDark,
                    ),
                    _buildUtilityTabButton(
                      1,
                      'Calculator',
                      Ionicons.calculatorOutline,
                      isDark,
                    ),
                    _buildUtilityTabButton(
                      2,
                      'Activity',
                      Ionicons.pulseOutline,
                      isDark,
                    ),
                  ],
                ),
              ),
            ),

            // Tab View Body
            Expanded(
              child: IndexedStack(
                index: _utilityDrawerTabIndex,
                children: [
                  _buildScratchpadView(isDark, borderColor),
                  _buildCalculatorView(cur, isDark, borderColor),
                  _buildActivityStreamView(s, cur, isDark, borderColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilityTabButton(
    int index,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final active = _utilityDrawerTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _utilityDrawerTabIndex = index),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? (isDark ? const Color(0xFF0F766E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.06,
                      ),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: active
                    ? (AppColors.heading)
                    : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? (AppColors.heading)
                        : (isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScratchpadView(bool isDark, Color borderColor) {
    return Column(
      children: [
        // Top Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Text(
                'QUICK NOTES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Insert Current Timestamp',
                child: InkWell(
                  onTap: () {
                    final now = DateTime.now();
                    final ts =
                        '[${fmtDate(now.toIso8601String(), pattern: 'MMM d, h:mm a')}] ';
                    final text = _scratchpadController.text;
                    final selection = _scratchpadController.selection;
                    if (selection.isValid && selection.start >= 0) {
                      final newText = text.replaceRange(
                        selection.start,
                        selection.end,
                        ts,
                      );
                      _scratchpadController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset: selection.start + ts.length,
                        ),
                      );
                    } else {
                      _scratchpadController.text = '$text$ts';
                    }
                    _saveScratchpad(_scratchpadController.text);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Ionicons.timeOutline,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Copy all notes to clipboard',
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _scratchpadController.text),
                    );
                    showAppToast(
                      context,
                      'Scratchpad copied to clipboard',
                      isSuccess: true,
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Ionicons.copyOutline,
                      size: 14,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Clear scratchpad',
                child: InkWell(
                  onTap: () {
                    if (_scratchpadController.text.trim().isEmpty) return;
                    _scratchpadController.clear();
                    _saveScratchpad('');
                    showAppToast(context, 'Scratchpad cleared');
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Ionicons.trashOutline,
                      size: 14,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Scratchpad Editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF091E1F) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _scratchpadController,
                maxLines: null,
                expands: true,
                onChanged: (v) {
                  _saveScratchpad(v);
                  setState(() {});
                },
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: isDark
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Type or paste quick notes, contractor rates, gate pin codes, phone numbers...\n\nNotes are automatically preserved.',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        // Word & Character count status bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '${_scratchpadController.text.trim().isEmpty ? 0 : _scratchpadController.text.trim().split(RegExp(r'\s+')).length} words • ${_scratchpadController.text.length} chars',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Ionicons.shieldCheckmarkOutline,
                size: 11,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 4),
              Text(
                'Auto-saved',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalcModePill(
    int index,
    String label,
    Color color,
    bool isDark,
    Color borderColor,
  ) {
    final active = _calcMode == index;
    return InkWell(
      onTap: () => setState(() => _calcMode = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : borderColor,
            width: active ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? color
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatorView(String cur, bool isDark, Color borderColor) {
    final rent = double.tryParse(_calcMonthlyRentController.text) ?? 1200.0;
    final dailyRate = rent / _calcDaysInMonth;
    final daysToCharge = (_calcDaysInMonth - _calcStartDay + 1).clamp(
      0,
      _calcDaysInMonth,
    );
    final proratedRent = dailyRate * daysToCharge;

    final deposit = double.tryParse(_depositHeldController.text) ?? 1200.0;
    final unpaid = double.tryParse(_depositUnpaidRentController.text) ?? 0.0;
    final repairs = double.tryParse(_depositRepairsController.text) ?? 0.0;
    final cleaning = double.tryParse(_depositCleaningController.text) ?? 0.0;
    final totalDeductions = unpaid + repairs + cleaning;
    final netRefund = deposit - totalDeductions;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 3-Mode Selector (Prorated, Deposit, Math)
        Row(
          children: [
            Expanded(
              child: _buildCalcModePill(
                0,
                'Prorated',
                const Color(0xFF10B981),
                isDark,
                borderColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCalcModePill(
                1,
                'Deposit',
                const Color(0xFF06B6D4),
                isDark,
                borderColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildCalcModePill(
                2,
                'Quick Math',
                const Color(0xFF8B5CF6),
                isDark,
                borderColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_calcMode == 0) ...[
          // Monthly Rent
          Text(
            'Full Monthly Rent ($cur)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _calcMonthlyRentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '$cur ',
              filled: true,
              fillColor: isDark ? const Color(0xFF091E1F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Days in Month
          Text(
            'Month Duration',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [30, 31, 28, 29].map((days) {
              final active = _calcDaysInMonth == days;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => setState(() => _calcDaysInMonth = days),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? (isDark
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFF059669))
                            : (isDark ? const Color(0xFF091E1F) : Colors.white),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: active ? Colors.transparent : borderColor,
                        ),
                      ),
                      child: Text(
                        '$days d',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active
                              ? Colors.white
                              : (isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A)),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Move-in / Start Day Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Move-In / Start Day',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Day $_calcStartDay',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _calcStartDay.toDouble().clamp(
              1.0,
              _calcDaysInMonth.toDouble(),
            ),
            min: 1,
            max: _calcDaysInMonth.toDouble(),
            divisions: _calcDaysInMonth - 1,
            activeColor: const Color(0xFF10B981),
            onChanged: (v) => setState(() => _calcStartDay = v.round()),
          ),

          // Results Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF091E1F) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Daily Rate',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$cur ${dailyRate.toStringAsFixed(2)} / day',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Days Billed',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$daysToCharge days ($_calcStartDay-$_calcDaysInMonth)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 16, color: borderColor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'Prorated Charge',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$cur ${proratedRent.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Ionicons.cashOutline, size: 14),
                  label: const Text(
                    'Collect Rent',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () {
                    setState(() => _showRightUtilityDrawer = false);
                    OverviewView.showPaymentSheet(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.heading,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Ionicons.createOutline, size: 14),
                  label: const Text(
                    'Add to Notes',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () {
                    final text =
                        'Prorated Rent Calculation:\n'
                        'Monthly Rent: $cur ${rent.toStringAsFixed(2)}\n'
                        'Month Basis: $_calcDaysInMonth days\n'
                        'Daily Rate: $cur ${dailyRate.toStringAsFixed(2)}\n'
                        'Days Billed: $daysToCharge days (Day $_calcStartDay - $_calcDaysInMonth)\n'
                        'Total Prorated Amount: $cur ${proratedRent.toStringAsFixed(2)}\n\n';
                    _scratchpadController.text =
                        '${_scratchpadController.text}$text';
                    _saveScratchpad(_scratchpadController.text);
                    setState(() => _utilityDrawerTabIndex = 0);
                    showAppToast(
                      context,
                      'Proration added to Scratchpad',
                      isSuccess: true,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Ionicons.copyOutline, size: 13),
            label: const Text(
              'Copy Proration Breakdown',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              final text =
                  'Prorated Rent Calculation:\n'
                  'Monthly Rent: $cur ${rent.toStringAsFixed(2)}\n'
                  'Month Basis: $_calcDaysInMonth days\n'
                  'Daily Rate: $cur ${dailyRate.toStringAsFixed(2)}\n'
                  'Days Billed (Day $_calcStartDay - $_calcDaysInMonth): $daysToCharge days\n'
                  'Total Prorated Amount: $cur ${proratedRent.toStringAsFixed(2)}';
              Clipboard.setData(ClipboardData(text: text));
              showAppToast(
                context,
                'Proration breakdown copied to clipboard',
                isSuccess: true,
              );
            },
          ),
        ] else if (_calcMode == 1) ...[
          // Security Deposit Mode
          Text(
            'Deposit Held ($cur)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _depositHeldController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '$cur ',
              filled: true,
              fillColor: isDark ? const Color(0xFF091E1F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Unpaid Rent Arrears ($cur)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _depositUnpaidRentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '$cur ',
              filled: true,
              fillColor: isDark ? const Color(0xFF091E1F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Repairs / Damage Deductions ($cur)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _depositRepairsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '$cur ',
              filled: true,
              fillColor: isDark ? const Color(0xFF091E1F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cleaning / Key Replacement ($cur)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: _depositCleaningController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '$cur ',
              filled: true,
              fillColor: isDark ? const Color(0xFF091E1F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Deposit Settlement Result Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF091E1F) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Deductions',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$cur ${totalDeductions.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 16, color: borderColor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        netRefund >= 0
                            ? 'Net Refund Due'
                            : 'Balance Owed by Tenant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$cur ${netRefund.abs().toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: netRefund >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (netRefund > 0) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Ionicons.receiptOutline, size: 14),
                    label: const Text(
                      'Record Refund',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _showRightUtilityDrawer = false);
                      OverviewView.showExpenseSheet(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.heading,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Ionicons.createOutline, size: 14),
                  label: const Text(
                    'Add to Notes',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () {
                    final text =
                        'Security Deposit Settlement Statement:\n'
                        'Initial Deposit: $cur ${deposit.toStringAsFixed(2)}\n'
                        'Unpaid Rent: $cur ${unpaid.toStringAsFixed(2)}\n'
                        'Repair Deductions: $cur ${repairs.toStringAsFixed(2)}\n'
                        'Cleaning / Misc: $cur ${cleaning.toStringAsFixed(2)}\n'
                        'Total Deductions: $cur ${totalDeductions.toStringAsFixed(2)}\n'
                        '${netRefund >= 0 ? 'Net Refund Due' : 'Balance Owed by Tenant'}: $cur ${netRefund.abs().toStringAsFixed(2)}\n\n';
                    _scratchpadController.text =
                        '${_scratchpadController.text}$text';
                    _saveScratchpad(_scratchpadController.text);
                    setState(() => _utilityDrawerTabIndex = 0);
                    showAppToast(
                      context,
                      'Settlement added to Scratchpad',
                      isSuccess: true,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(vertical: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Ionicons.copyOutline, size: 13),
            label: const Text(
              'Copy Settlement Statement',
              style: TextStyle(fontSize: 11),
            ),
            onPressed: () {
              final text =
                  'Security Deposit Settlement Statement:\n'
                  'Initial Deposit: $cur ${deposit.toStringAsFixed(2)}\n'
                  'Unpaid Rent: $cur ${unpaid.toStringAsFixed(2)}\n'
                  'Repair Deductions: $cur ${repairs.toStringAsFixed(2)}\n'
                  'Cleaning / Misc: $cur ${cleaning.toStringAsFixed(2)}\n'
                  'Total Deductions: $cur ${totalDeductions.toStringAsFixed(2)}\n'
                  '-------------------------------\n'
                  '${netRefund >= 0 ? 'Net Refund Payable to Tenant' : 'Balance Due from Tenant'}: $cur ${netRefund.abs().toStringAsFixed(2)}';
              Clipboard.setData(ClipboardData(text: text));
              showAppToast(
                context,
                'Settlement statement copied to clipboard',
                isSuccess: true,
              );
            },
          ),
        ] else ...[
          // Quick Math Calculator Mode
          _buildStandardCalculatorView(isDark, borderColor),
        ],
      ],
    );
  }

  Widget _buildStandardCalculatorView(bool isDark, Color borderColor) {
    return Column(
      children: [
        // Display Screen
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF041011) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _mathExpression.isNotEmpty ? _mathExpression : ' ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _mathDisplay,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.heading,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Quick Math Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Ionicons.copyOutline, size: 12),
                label: const Text(
                  'Copy Result',
                  style: TextStyle(fontSize: 10.5),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _mathDisplay));
                  showAppToast(
                    context,
                    'Result copied: $_mathDisplay',
                    isSuccess: true,
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Ionicons.createOutline, size: 12),
                label: const Text(
                  'Add to Notes',
                  style: TextStyle(fontSize: 10.5),
                ),
                onPressed: () {
                  final entry =
                      'Calc: ${_mathExpression.isNotEmpty ? '$_mathExpression ' : ''}$_mathDisplay\n';
                  _scratchpadController.text =
                      '${_scratchpadController.text}$entry';
                  _saveScratchpad(_scratchpadController.text);
                  setState(() => _utilityDrawerTabIndex = 0);
                  showAppToast(
                    context,
                    'Inserted into Scratchpad',
                    isSuccess: true,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4x5 Keypad
        Column(
          children: [
            _buildCalcRow(['C', '±', '%', '÷'], isDark, borderColor),
            const SizedBox(height: 6),
            _buildCalcRow(['7', '8', '9', '×'], isDark, borderColor),
            const SizedBox(height: 6),
            _buildCalcRow(['4', '5', '6', '−'], isDark, borderColor),
            const SizedBox(height: 6),
            _buildCalcRow(['1', '2', '3', '+'], isDark, borderColor),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(flex: 2, child: _calcKey('0', isDark, borderColor)),
                const SizedBox(width: 6),
                Expanded(child: _calcKey('.', isDark, borderColor)),
                const SizedBox(width: 6),
                Expanded(
                  child: _calcKey('=', isDark, borderColor, isPrimary: true),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalcRow(List<String> keys, bool isDark, Color borderColor) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _calcKey(
              keys[i],
              isDark,
              borderColor,
              isOperator: ['÷', '×', '−', '+'].contains(keys[i]),
              isFunction: ['C', '±', '%'].contains(keys[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _calcKey(
    String key,
    bool isDark,
    Color borderColor, {
    bool isOperator = false,
    bool isPrimary = false,
    bool isFunction = false,
  }) {
    Color bg;
    Color fg;

    if (isPrimary) {
      bg = const Color(0xFF10B981);
      fg = Colors.white;
    } else if (isOperator) {
      bg = isDark ? const Color(0xFF0F766E) : const Color(0xFFCCFBF1);
      fg = isDark ? Colors.white : const Color(0xFF0F766E);
    } else if (isFunction) {
      bg = isDark ? const Color(0xFF132B2B) : const Color(0xFFE2E8F0);
      fg = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    } else {
      bg = isDark ? const Color(0xFF091E1F) : Colors.white;
      fg = AppColors.heading;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          switch (key) {
            case 'C':
              _onMathClear();
              break;
            case '±':
              _onMathToggleSign();
              break;
            case '%':
              _onMathPercent();
              break;
            case '÷':
            case '×':
            case '−':
            case '+':
              _onMathOperator(key);
              break;
            case '=':
              _onMathEquals();
              break;
            case '.':
              _onMathDecimal();
              break;
            default:
              _onMathDigit(key);
              break;
          }
        },
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isPrimary ? Colors.transparent : borderColor,
            ),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  void _onMathDigit(String digit) {
    setState(() {
      if (_mathShouldResetDisplay || _mathDisplay == '0') {
        _mathDisplay = digit;
        _mathShouldResetDisplay = false;
      } else {
        if (_mathDisplay.length < 14) {
          _mathDisplay += digit;
        }
      }
    });
  }

  void _onMathDecimal() {
    setState(() {
      if (_mathShouldResetDisplay) {
        _mathDisplay = '0.';
        _mathShouldResetDisplay = false;
      } else if (!_mathDisplay.contains('.')) {
        _mathDisplay += '.';
      }
    });
  }

  void _onMathOperator(String op) {
    final current = double.tryParse(_mathDisplay) ?? 0.0;
    setState(() {
      if (_mathFirstOperand != null &&
          _mathOperator != null &&
          !_mathShouldResetDisplay) {
        _executeMathCalc();
      } else {
        _mathFirstOperand = current;
      }
      _mathOperator = op;
      _mathExpression = '${_formatMathNumber(_mathFirstOperand!)} $op';
      _mathShouldResetDisplay = true;
    });
  }

  void _executeMathCalc() {
    if (_mathFirstOperand == null || _mathOperator == null) return;
    final second = double.tryParse(_mathDisplay) ?? 0.0;
    double res = 0.0;
    switch (_mathOperator) {
      case '+':
        res = _mathFirstOperand! + second;
        break;
      case '−':
      case '-':
        res = _mathFirstOperand! - second;
        break;
      case '×':
      case '*':
        res = _mathFirstOperand! * second;
        break;
      case '÷':
      case '/':
        res = second != 0 ? _mathFirstOperand! / second : 0.0;
        break;
    }
    _mathExpression =
        '${_formatMathNumber(_mathFirstOperand!)} $_mathOperator ${_formatMathNumber(second)} =';
    _mathDisplay = _formatMathNumber(res);
    _mathFirstOperand = res;
    _mathOperator = null;
    _mathShouldResetDisplay = true;
  }

  void _onMathEquals() {
    setState(() {
      _executeMathCalc();
    });
  }

  void _onMathClear() {
    setState(() {
      _mathDisplay = '0';
      _mathExpression = '';
      _mathFirstOperand = null;
      _mathOperator = null;
      _mathShouldResetDisplay = false;
    });
  }

  void _onMathPercent() {
    final val = double.tryParse(_mathDisplay) ?? 0.0;
    setState(() {
      _mathDisplay = _formatMathNumber(val / 100);
      _mathShouldResetDisplay = true;
    });
  }

  void _onMathToggleSign() {
    final val = double.tryParse(_mathDisplay) ?? 0.0;
    setState(() {
      _mathDisplay = _formatMathNumber(-val);
    });
  }

  String _formatMathNumber(double num) {
    if (num == num.roundToDouble()) {
      return num.toInt().toString();
    }
    final s = num.toStringAsFixed(4);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Widget _buildActivityStreamView(
    AppDataState s,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    // Compile items from payments, expenses, work orders, tenants, documents
    final List<
      ({
        String title,
        String subtitle,
        String date,
        String tag,
        Color color,
        IconData icon,
        VoidCallback? onTap,
      })
    >
    events = [];

    for (final p in s.scopedPayments) {
      final t = s.scopedTenants.where((x) => x.id == p.tenantId).firstOrNull;
      final date = p.paidDate ?? p.dueDate ?? '';
      events.add((
        title: 'Rent: ${t?.name ?? 'Tenant'} (Unit ${t?.unit ?? '?'})',
        subtitle:
            '$cur ${p.amount.toStringAsFixed(0)} • ${p.status.toUpperCase()}',
        date: date,
        tag: 'payment',
        color: const Color(0xFF10B981),
        icon: Ionicons.cashOutline,
        onTap: () {
          setState(() {
            _tabIndex = 0;
            _showSettings = false;
          });
        },
      ));
    }

    for (final e in s.scopedExpenses) {
      events.add((
        title: e.description.isNotEmpty ? e.description : e.category,
        subtitle: '$cur ${e.amount.toStringAsFixed(0)} • ${e.category}',
        date: e.date,
        tag: 'expense',
        color: const Color(0xFFEF4444),
        icon: Ionicons.walletOutline,
        onTap: () {
          setState(() {
            _tabIndex = 0;
            _showSettings = false;
          });
        },
      ));
    }

    for (final w in s.scopedWorkOrders) {
      final totalCost = (w.productPrice ?? 0) + (w.workerCost ?? 0);
      events.add((
        title: w.title,
        subtitle:
            'Unit ${w.unit ?? 'All'} • ${w.status.toUpperCase()}${totalCost > 0 ? ' • $cur ${totalCost.toStringAsFixed(0)}' : ''}',
        date: w.createdAt,
        tag: 'work_order',
        color: const Color(0xFF06B6D4),
        icon: Ionicons.constructOutline,
        onTap: () {
          setState(() {
            _tabIndex = 2;
            _showSettings = false;
          });
        },
      ));
    }

    for (final t in s.scopedTenants) {
      events.add((
        title: 'New Tenant: ${t.name}',
        subtitle:
            'Unit ${t.unit.isNotEmpty ? t.unit : 'N/A'} • Rent: $cur ${t.rentAmount.toStringAsFixed(0)}',
        date: t.joinDate,
        tag: 'tenant',
        color: const Color(0xFF3B82F6),
        icon: Ionicons.personAddOutline,
        onTap: () {
          setState(() {
            _tabIndex = 1;
            _showSettings = false;
          });
        },
      ));
    }

    for (final d in s.scopedDocuments) {
      events.add((
        title: 'Doc: ${d.title.isNotEmpty ? d.title : d.fileName}',
        subtitle:
            '${d.type.toUpperCase()}${d.unit != null && d.unit!.isNotEmpty ? ' • Unit ${d.unit}' : ''}',
        date: d.uploadedDate,
        tag: 'document',
        color: const Color(0xFF8B5CF6),
        icon: Ionicons.cloudUploadOutline,
        onTap: () {
          setState(() {
            _tabIndex = 3;
            _showSettings = false;
          });
        },
      ));
    }

    // Sort by date descending
    events.sort((a, b) => b.date.compareTo(a.date));

    // Filter events
    final q = _activitySearchController.text.trim().toLowerCase();
    final filteredEvents = events
        .where((e) {
          if (_activityFilter != 'all' && e.tag != _activityFilter) {
            return false;
          }
          if (q.isNotEmpty) {
            return e.title.toLowerCase().contains(q) ||
                e.subtitle.toLowerCase().contains(q);
          }
          return true;
        })
        .take(40)
        .toList();

    return Column(
      children: [
        // Activity Search & Category Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Column(
            children: [
              // Search input
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF091E1F) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: TextField(
                  controller: _activitySearchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 12, color: AppColors.heading),
                  decoration: InputDecoration(
                    hintText: 'Filter activity...',
                    hintStyle: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(Ionicons.searchOutline, size: 13),
                    suffixIcon: _activitySearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Ionicons.closeCircle, size: 13),
                            onPressed: () {
                              _activitySearchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Category filter pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _activityFilterPill('all', 'All', isDark, borderColor),
                    const SizedBox(width: 4),
                    _activityFilterPill(
                      'payment',
                      'Payments',
                      isDark,
                      borderColor,
                    ),
                    const SizedBox(width: 4),
                    _activityFilterPill(
                      'expense',
                      'Expenses',
                      isDark,
                      borderColor,
                    ),
                    const SizedBox(width: 4),
                    _activityFilterPill(
                      'work_order',
                      'Orders',
                      isDark,
                      borderColor,
                    ),
                    const SizedBox(width: 4),
                    _activityFilterPill(
                      'tenant',
                      'Tenants',
                      isDark,
                      borderColor,
                    ),
                    const SizedBox(width: 4),
                    _activityFilterPill(
                      'document',
                      'Docs',
                      isDark,
                      borderColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: filteredEvents.isEmpty
              ? Center(
                  child: Text(
                    'No matching activity',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, i) {
                    final ev = filteredEvents[i];
                    return InkWell(
                      onTap: ev.onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF091E1F)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: ev.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(ev.icon, size: 13, color: ev.color),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ev.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ev.subtitle,
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
                            const SizedBox(width: 6),
                            Text(
                              _formatRelativeDate(ev.date),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _activityFilterPill(
    String filterKey,
    String label,
    bool isDark,
    Color borderColor,
  ) {
    final active = _activityFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activityFilter = filterKey),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? const Color(0xFF0F766E) : const Color(0xFF059669))
              : (isDark ? const Color(0xFF091E1F) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.transparent : borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  String _formatRelativeDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return dateStr;
      final now = DateTime.now();
      final diffDays = now.difference(dt).inDays;
      if (diffDays == 0) return 'Today';
      if (diffDays == 1) return 'Yesterday';
      if (diffDays < 7) return '${diffDays}d ago';
      return fmtDate(dateStr, pattern: 'MMM d');
    } catch (_) {
      return dateStr;
    }
  }
}
