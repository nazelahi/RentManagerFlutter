import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';

/// Representation of a tab/section in the macOS desktop environment.
class DesktopTab {
  final String label;
  final IconData outlined;
  final IconData filled;
  final String subtitle;
  const DesktopTab(this.label, this.outlined, this.filled, this.subtitle);
}

/// Global desktop notification state
class DesktopNotificationState {
  final bool isMarkedAllRead;
  final bool isAllCleared;
  final Set<String> dismissedIds;

  const DesktopNotificationState({
    this.isMarkedAllRead = false,
    this.isAllCleared = false,
    this.dismissedIds = const {},
  });

  Map<String, dynamic> toJson() => {
        'isMarkedAllRead': isMarkedAllRead,
        'isAllCleared': isAllCleared,
        'dismissedIds': dismissedIds.toList(),
      };

  factory DesktopNotificationState.fromJson(Map<String, dynamic> json) {
    return DesktopNotificationState(
      isMarkedAllRead: json['isMarkedAllRead'] as bool? ?? false,
      isAllCleared: json['isAllCleared'] as bool? ?? false,
      dismissedIds: (json['dismissedIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
    );
  }

  DesktopNotificationState copyWith({
    bool? isMarkedAllRead,
    bool? isAllCleared,
    Set<String>? dismissedIds,
  }) {
    return DesktopNotificationState(
      isMarkedAllRead: isMarkedAllRead ?? this.isMarkedAllRead,
      isAllCleared: isAllCleared ?? this.isAllCleared,
      dismissedIds: dismissedIds ?? this.dismissedIds,
    );
  }
}

/// Global desktop notification notifier managing read, cleared, and dismissed notifications
class DesktopNotificationsNotifier
    extends StateNotifier<DesktopNotificationState> {
  static const _storageKey = 'desktop_notifications_state';

  DesktopNotificationsNotifier() : super(_loadInitialState());

  static DesktopNotificationState _loadInitialState() {
    try {
      final saved = AppStorage.readJson<DesktopNotificationState>(
        _storageKey,
        (json) => DesktopNotificationState.fromJson(json),
      );
      return saved ?? const DesktopNotificationState();
    } catch (_) {
      return const DesktopNotificationState();
    }
  }

  void _persist() {
    try {
      AppStorage.writeJson(_storageKey, state.toJson());
    } catch (_) {}
  }

  void markAllAsRead() {
    state = state.copyWith(isMarkedAllRead: true);
    _persist();
  }

  void markAsUnread() {
    state = state.copyWith(isMarkedAllRead: false);
    _persist();
  }

  void clearAll() {
    state = state.copyWith(isAllCleared: true, isMarkedAllRead: true);
    _persist();
  }

  void restoreAll() {
    state = const DesktopNotificationState(
      isMarkedAllRead: false,
      isAllCleared: false,
      dismissedIds: {},
    );
    _persist();
  }

  void dismiss(String id) {
    final next = Set<String>.from(state.dismissedIds)..add(id);
    state = state.copyWith(dismissedIds: next);
    _persist();
  }

  void restore(String id) {
    final next = Set<String>.from(state.dismissedIds)..remove(id);
    state = state.copyWith(dismissedIds: next);
    _persist();
  }
}

final desktopNotificationsProvider =
    StateNotifierProvider<DesktopNotificationsNotifier, DesktopNotificationState>(
  (ref) => DesktopNotificationsNotifier(),
);

// Backward compatibility alias for read state
final desktopNotificationsReadProvider = Provider<bool>(
  (ref) => ref.watch(desktopNotificationsProvider).isMarkedAllRead,
);

/// Dynamic macOS Unified Title Bar & Section Controller.
///
/// Automatically adjusts title, section switcher, contextual stats badges,
/// and primary action buttons based on the active screen.
class DesktopAppBar extends ConsumerWidget {
  final int currentTabIndex;
  final List<DesktopTab> tabs;
  final ValueChanged<int> onNavigateTab;
  final VoidCallback onOpenSearch;
  final VoidCallback onAddTenant;
  final VoidCallback onLogPayment;
  final VoidCallback onLogExpense;
  final VoidCallback onAddWorkOrder;
  final VoidCallback onAddDocument;
  final VoidCallback onSyncDocuments;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final VoidCallback? onPrintReport;
  final VoidCallback? onAddZakatInflow;
  final VoidCallback? onAddZakatOutflow;
  final VoidCallback? onOpenZakatCalculator;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDeposit;
  final VoidCallback? onSyncRoll;
  final VoidCallback? onBatchRentCollection;
  final VoidCallback? onGenerateReceipt;
  final VoidCallback? onOpenCashFlowForecast;
  final FocusNode? searchFocusNode;
  final Function(Tenant tenant)? onSelectTenant;
  final Function(Tenant tenant)? onLogPaymentForTenant;
  final Function(WorkOrder workOrder)? onSelectWorkOrder;
  final VoidCallback? onAbout;
  final VoidCallback? onEditProfile;
  final VoidCallback? onKeyboardShortcuts;
  final VoidCallback? onToggleUtilityDrawer;
  final bool isUtilityDrawerOpen;

  const DesktopAppBar({
    super.key,
    required this.currentTabIndex,
    required this.tabs,
    required this.onNavigateTab,
    required this.onOpenSearch,
    required this.onAddTenant,
    required this.onLogPayment,
    required this.onLogExpense,
    required this.onAddWorkOrder,
    required this.onAddDocument,
    required this.onSyncDocuments,
    required this.onExportCsv,
    required this.onExportPdf,
    this.onPrintReport,
    this.onAddZakatInflow,
    this.onAddZakatOutflow,
    this.onOpenZakatCalculator,
    this.onOpenSettings,
    this.onDeposit,
    this.onSyncRoll,
    this.onBatchRentCollection,
    this.onGenerateReceipt,
    this.onOpenCashFlowForecast,
    this.searchFocusNode,
    this.onSelectTenant,
    this.onLogPaymentForTenant,
    this.onSelectWorkOrder,
    this.onAbout,
    this.onEditProfile,
    this.onKeyboardShortcuts,
    this.onToggleUtilityDrawer,
    this.isUtilityDrawerOpen = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final bg = isDark
        ? const Color(0xFF040E0F).withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.75);

    // Active alerts for notifications center & badge (scoped to active property)
    final now = DateTime.now();
    final curMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final currentMonthPayments = s.scopedPayments
        .where((p) =>
            p.paidForMonth == curMonth ||
            (p.paidDate != null && p.paidDate!.startsWith(curMonth)) ||
            (p.dueDate != null && p.dueDate!.startsWith(curMonth)))
        .toList();
    final paidTenantIds = currentMonthPayments
        .where((p) => p.status == 'paid')
        .map((p) => p.tenantId)
        .toSet();

    final notifState = ref.watch(desktopNotificationsProvider);

    final activeOverdueCount = notifState.isAllCleared
        ? 0
        : s.scopedTenants
            .where((t) =>
                t.status == 'active' &&
                !paidTenantIds.contains(t.id) &&
                !notifState.dismissedIds.contains('rent_${t.id}'))
            .length;

    final activePendingOrdersCount = notifState.isAllCleared
        ? 0
        : s.scopedWorkOrders
            .where((w) =>
                (w.status == 'pending' ||
                    w.status == 'in-progress' ||
                    w.status == 'open') &&
                !notifState.dismissedIds.contains('wo_${w.id}'))
            .length;

    final totalAlertsCount = activeOverdueCount + activePendingOrdersCount;
    final displayedAlertsCount =
        (notifState.isMarkedAllRead || notifState.isAllCleared)
            ? 0
            : totalAlertsCount;
    final displayedOverdueCount =
        (notifState.isMarkedAllRead || notifState.isAllCleared)
            ? 0
            : activeOverdueCount;

    final validIndex = currentTabIndex.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    final currentTab = tabs.isNotEmpty
        ? tabs[validIndex]
        : const DesktopTab('Overview', Ionicons.homeOutline, Ionicons.home, 'Executive Overview');

    return LayoutBuilder(
      builder: (context, constraints) {
        final showContextBadge = constraints.maxWidth >= 1120;
        final showExtraActions = constraints.maxWidth >= 1200;
        final isCompact = constraints.maxWidth < 1060;
        final isNarrow = constraints.maxWidth < 880;

        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: borderColor, width: 1)),
          ),
          child: Row(
            children: [
              // 1. Screen Title & Slogan
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentTab.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      currentTab.subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        letterSpacing: 0.1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              if (showContextBadge && validIndex != 0) ...[
                const SizedBox(width: 8),
                // 3. Dynamic Contextual Stats Badge
                _buildContextBadge(validIndex, s, isDark),
              ],

              // Middle: Centered Direct Search Bar
              Expanded(
                child: Center(
                  child: DesktopDirectSearchBar(
                    focusNode: searchFocusNode,
                    onNavigateTab: onNavigateTab,
                    onSelectTenant: onSelectTenant,
                    onAddTenant: onAddTenant,
                    onLogPayment: onLogPayment,
                    onLogExpense: onLogExpense,
                    onAddWorkOrder: onAddWorkOrder,
                    onAddDocument: onAddDocument,
                    onSyncDocuments: onSyncDocuments,
                    onExportCsv: onExportCsv,
                    onExportPdf: onExportPdf,
                    onPrintReport: onPrintReport,
                    onAddZakatInflow: onAddZakatInflow,
                    onAddZakatOutflow: onAddZakatOutflow,
                    onOpenZakatCalculator: onOpenZakatCalculator,
                    onDeposit: onDeposit,
                    onSyncRoll: onSyncRoll,
                    onBatchRentCollection: onBatchRentCollection,
                    onGenerateReceipt: onGenerateReceipt,
                    onOpenCashFlowForecast: onOpenCashFlowForecast,
                  ),
                ),
              ),

              // Right side: Universal Quick Action Hub
              _buildQuickActionMenu(context, isDark, isNarrow),
              const SizedBox(width: 6),

              // Active Screen Action Buttons
              _buildScreenActions(validIndex, isDark,
                  isNarrow: isCompact, showExtra: showExtraActions),

              const SizedBox(width: 8),

              // Notifications / Overdue Alert Badge
              _NotificationBellButton(
                alertsCount: displayedAlertsCount,
                overdueCount: displayedOverdueCount,
                isDark: isDark,
                onTap: (buttonContext) =>
                    _showNotificationCenter(context, ref, s, isDark, buttonContext),
              ),

          const SizedBox(width: 6),

          // 7. Theme Toggle
          Tooltip(
            message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: InkWell(
              onTap: () {
                final nextMode = isDark ? 'light' : 'dark';
                ref.read(appDataProvider.notifier).setThemeMode(nextMode);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B2223)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.06)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Icon(
                  isDark ? Ionicons.sunny : Ionicons.moon,
                  size: 14,
                  color: isDark
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF0F766E),
                ),
              ),
            ),
          ),

          if (onToggleUtilityDrawer != null) ...[
            const SizedBox(width: 6),
            // Utility Drawer Toggle (⌘I)
            Tooltip(
              message: isUtilityDrawerOpen
                  ? 'Close Utility Panel (⌘I)'
                  : 'Open Utility Panel (⌘I) • Calculator, Scratchpad & Activity',
              child: InkWell(
                onTap: onToggleUtilityDrawer,
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isUtilityDrawerOpen
                        ? (isDark
                            ? const Color(0xFF10B981).withValues(alpha: 0.22)
                            : const Color(0xFF059669).withValues(alpha: 0.16))
                        : (isDark
                            ? const Color(0xFF0B2223)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isUtilityDrawerOpen
                          ? const Color(0xFF10B981)
                          : (isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.06)
                              : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Icon(
                    Ionicons.browsersOutline,
                    size: 14,
                    color: isUtilityDrawerOpen
                        ? const Color(0xFF10B981)
                        : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(width: 8),

          // 8. Profile with Avatar (User Profile Hub)
          _DesktopProfileButton(
            s: s,
            isDark: isDark,
            isCompact: isNarrow,
            onTap: (buttonContext) =>
                _showProfileMenu(context, ref, s, isDark, buttonContext),
          ),
        ],
      ),
    );
      },
    );
  }

  /// Universal Quick Actions Split Dropdown Menu
  Widget _buildQuickActionMenu(BuildContext context, bool isDark, bool isNarrow) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    return PopupMenuButton<String>(
      tooltip: 'Universal Actions (⇧⌘P, ⌘N, ⇧⌘W, ...)',
      offset: const Offset(0, 38),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor),
      ),
      color: isDark ? const Color(0xFF0B2425) : Colors.white,
      onSelected: (val) {
        switch (val) {
          case 'payment':
            onLogPayment();
            break;
          case 'expense':
            onLogExpense();
            break;
          case 'tenant':
            onAddTenant();
            break;
          case 'work_order':
            onAddWorkOrder();
            break;
          case 'document':
            onAddDocument();
            break;
          case 'deposit':
            onDeposit?.call();
            break;
          case 'sync_roll':
            onSyncRoll?.call();
            break;
          case 'batch_rent':
            onBatchRentCollection?.call();
            break;
          case 'receipt':
            onGenerateReceipt?.call();
            break;
          case 'forecast':
            onOpenCashFlowForecast?.call();
            break;
          case 'zakat_inflow':
            onAddZakatInflow?.call();
            break;
          case 'zakat_calc':
            onOpenZakatCalculator?.call();
            break;
          case 'utility_panel':
            onToggleUtilityDrawer?.call();
            break;
          case 'report_pdf':
            onExportPdf();
            break;
          case 'report_csv':
            onExportCsv();
            break;
          case 'sync':
            onSyncDocuments();
            break;
          case 'settings':
            onOpenSettings?.call();
            break;
          case 'shortcuts':
            onKeyboardShortcuts?.call();
            break;
        }
      },
      itemBuilder: (ctx) => [
        // Operations Section
        _menuSectionHeader('OPERATIONS', isDark),
        _quickMenuItem(
          value: 'payment',
          icon: Ionicons.cashOutline,
          label: 'Collect Rent',
          shortcut: '⇧⌘P',
          isDark: isDark,
          color: const Color(0xFF10B981),
        ),
        if (onBatchRentCollection != null)
          _quickMenuItem(
            value: 'batch_rent',
            icon: Ionicons.layersOutline,
            label: 'Batch Rent Collection...',
            shortcut: '⇧⌘B',
            isDark: isDark,
            color: const Color(0xFF6366F1),
          ),
        if (onGenerateReceipt != null)
          _quickMenuItem(
            value: 'receipt',
            icon: Ionicons.receiptOutline,
            label: 'Rent Receipt / Invoice...',
            shortcut: '⇧⌘I',
            isDark: isDark,
            color: const Color(0xFF0EA5E9),
          ),
        _quickMenuItem(
          value: 'expense',
          icon: Ionicons.receiptOutline,
          label: 'Record Expense',
          shortcut: '⇧⌘E',
          isDark: isDark,
          color: const Color(0xFFEF4444),
        ),
        _quickMenuItem(
          value: 'tenant',
          icon: Ionicons.personAddOutline,
          label: 'Add Tenant & Lease',
          shortcut: '⌘N',
          isDark: isDark,
          color: const Color(0xFF3B82F6),
        ),
        _quickMenuItem(
          value: 'work_order',
          icon: Ionicons.constructOutline,
          label: 'New Work Order',
          shortcut: '⇧⌘W',
          isDark: isDark,
          color: const Color(0xFFF59E0B),
        ),
        _quickMenuItem(
          value: 'document',
          icon: Ionicons.cloudUploadOutline,
          label: 'Upload Document',
          shortcut: '⌘U',
          isDark: isDark,
          color: const Color(0xFF8B5CF6),
        ),
        if (onDeposit != null)
          _quickMenuItem(
            value: 'deposit',
            icon: Ionicons.cardOutline,
            label: 'Deposit to Owner',
            shortcut: '⇧⌘D',
            isDark: isDark,
            color: const Color(0xFF06B6D4),
          ),

        const PopupMenuDivider(height: 1),
        // Finance & Tools Section
        _menuSectionHeader('FINANCE & TOOLS', isDark),
        if (onSyncRoll != null)
          _quickMenuItem(
            value: 'sync_roll',
            icon: Ionicons.syncOutline,
            label: 'Sync Previous Month Roll',
            shortcut: '⇧⌘S',
            isDark: isDark,
            color: const Color(0xFF10B981),
          ),
        if (onAddZakatInflow != null)
          _quickMenuItem(
            value: 'zakat_inflow',
            icon: Ionicons.heartOutline,
            label: 'Record Zakat Inflow',
            shortcut: 'Zakat',
            isDark: isDark,
            color: const Color(0xFF10B981),
          ),
        if (onOpenZakatCalculator != null)
          _quickMenuItem(
            value: 'zakat_calc',
            icon: Ionicons.calculatorOutline,
            label: 'Zakat & Nisab Engine',
            shortcut: 'Hawl',
            isDark: isDark,
            color: const Color(0xFF059669),
          ),
        if (onToggleUtilityDrawer != null)
          _quickMenuItem(
            value: 'utility_panel',
            icon: Ionicons.browsersOutline,
            label: 'Calculator & Scratchpad',
            shortcut: '⌘I',
            isDark: isDark,
            color: const Color(0xFF38BDF8),
          ),
        if (onOpenCashFlowForecast != null)
          _quickMenuItem(
            value: 'forecast',
            icon: Ionicons.trendingUpOutline,
            label: 'Cash Flow Forecast (NOI)...',
            shortcut: '⇧⌘F',
            isDark: isDark,
            color: const Color(0xFF10B981),
          ),

        const PopupMenuDivider(height: 1),
        // Data & System Section
        _menuSectionHeader('DATA & SYSTEM', isDark),
        _quickMenuItem(
          value: 'report_pdf',
          icon: Ionicons.documentTextOutline,
          label: 'Export Statement (PDF)',
          shortcut: '⇧⌘R',
          isDark: isDark,
          color: const Color(0xFF10B981),
        ),
        _quickMenuItem(
          value: 'report_csv',
          icon: Ionicons.gridOutline,
          label: 'Export Financials (CSV)',
          shortcut: '⇧⌘C',
          isDark: isDark,
          color: const Color(0xFF059669),
        ),
        _quickMenuItem(
          value: 'sync',
          icon: Ionicons.cloudDoneOutline,
          label: 'Backup & Cloud Sync',
          shortcut: '⇧⌘B',
          isDark: isDark,
          color: const Color(0xFF0F766E),
        ),
        if (onKeyboardShortcuts != null)
          _quickMenuItem(
            value: 'shortcuts',
            icon: Ionicons.keypadOutline,
            label: 'Keyboard Shortcuts',
            shortcut: '⌘/',
            isDark: isDark,
            color: const Color(0xFF64748B),
          ),
        if (onOpenSettings != null)
          _quickMenuItem(
            value: 'settings',
            icon: Ionicons.settingsOutline,
            label: 'System Settings',
            shortcut: '⌘,',
            isDark: isDark,
            color: const Color(0xFF94A3B8),
          ),
      ],
      child: isNarrow
          ? Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D2D2E) : const Color(0xFFE6F4F1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                      : const Color(0xFF059669).withValues(alpha: 0.25),
                ),
              ),
              child: const Center(
                child: Icon(
                  Ionicons.flash,
                  size: 14,
                  color: Color(0xFF10B981),
                ),
              ),
            )
          : Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D2D2E) : const Color(0xFFE6F4F1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.40)
                      : const Color(0xFF059669).withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.flash, size: 13, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Ionicons.chevronDown,
                    size: 11,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
                  ),
                ],
              ),
            ),
    );
  }

  PopupMenuEntry<String> _menuSectionHeader(String title, bool isDark) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  PopupMenuItem<String> _quickMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required String shortcut,
    required bool isDark,
    required Color color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.heading,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF133233) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dynamic contextual badge providing instant screen insight
  Widget _buildContextBadge(int tabIndex, dynamic state, bool isDark) {
    String text = '';
    IconData icon = Ionicons.informationCircleOutline;
    Color color = const Color(0xFF0F766E);

    switch (tabIndex) {
      case 0: // Overview
        return const SizedBox.shrink();
      case 1: // Tenants
        final active = state.tenants.where((t) => t.status == 'active').length;
        text = '${state.tenants.length} Tenants ($active Active)';
        icon = Ionicons.peopleOutline;
        color = const Color(0xFF3B82F6);
        break;
      case 2: // Work Orders
        final open = state.workOrders.where((w) => w.status != 'completed').length;
        text = '${state.workOrders.length} Orders ($open Open)';
        icon = Ionicons.constructOutline;
        color = const Color(0xFFF59E0B);
        break;
      case 3: // Documents
        text = '${state.documents.length} Files in Vault';
        icon = Ionicons.folderOpenOutline;
        color = const Color(0xFF8B5CF6);
        break;
      case 4: // Reports
        text = 'Fiscal Year ${DateTime.now().year}';
        icon = Ionicons.trendingUpOutline;
        color = const Color(0xFF06B6D4);
        break;
      case 5: // Zakat
        text = 'Hawl & Nisab Engine';
        icon = Ionicons.calculatorOutline;
        color = const Color(0xFF10B981);
        break;
      default:
        text = 'Workspace Active';
        icon = Ionicons.shieldCheckmarkOutline;
        color = const Color(0xFF059669);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.30 : 0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : color,
            ),
          ),
        ],
      ),
    );
  }

  /// Dynamic screen-specific primary actions
  Widget _buildScreenActions(int tabIndex, bool isDark,
      {bool isNarrow = false, bool showExtra = false}) {
    switch (tabIndex) {
      case 0: // Overview
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionPill(
              icon: Ionicons.cashOutline,
              label: 'Record Rent',
              isPrimary: true,
              isDark: isDark,
              onTap: onLogPayment,
            ),
            if (!isNarrow) ...[
              const SizedBox(width: 6),
              _actionPill(
                icon: Ionicons.receiptOutline,
                label: 'Record Expense',
                isPrimary: false,
                isDark: isDark,
                onTap: onLogExpense,
              ),
            ],
            if (onSyncRoll != null && showExtra) ...[
              const SizedBox(width: 6),
              _actionPill(
                icon: Ionicons.syncOutline,
                label: 'Sync Roll',
                isPrimary: false,
                isDark: isDark,
                onTap: onSyncRoll!,
              ),
            ],
            if (onDeposit != null && showExtra) ...[
              const SizedBox(width: 6),
              _actionPill(
                icon: Ionicons.cardOutline,
                label: 'Deposit Money',
                isPrimary: false,
                isDark: isDark,
                onTap: onDeposit!,
              ),
            ],
          ],
        );
      case 1: // Tenants
        return _actionPill(
          icon: Ionicons.personAddOutline,
          label: 'Add Tenant',
          isPrimary: true,
          isDark: isDark,
          onTap: onAddTenant,
        );
      case 2: // Work Orders
        return _actionPill(
          icon: Ionicons.addCircleOutline,
          label: 'Add Work Order',
          isPrimary: true,
          isDark: isDark,
          onTap: onAddWorkOrder,
        );
      case 3: // Documents
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionPill(
              icon: Ionicons.cloudUploadOutline,
              label: 'Add Document',
              isPrimary: true,
              isDark: isDark,
              onTap: onAddDocument,
            ),
            const SizedBox(width: 6),
            _actionPill(
              icon: Ionicons.syncOutline,
              label: 'Sync Documents',
              isPrimary: false,
              isDark: isDark,
              onTap: onSyncDocuments,
            ),
          ],
        );
      case 4: // Reports
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionPill(
              icon: Ionicons.documentTextOutline,
              label: 'Export CSV',
              isPrimary: false,
              isDark: isDark,
              onTap: onExportCsv,
            ),
            const SizedBox(width: 6),
            _actionPill(
              icon: Ionicons.documentOutline,
              label: 'Export PDF',
              isPrimary: true,
              isDark: isDark,
              onTap: onExportPdf,
            ),
          ],
        );
      case 5: // Zakat
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAddZakatInflow != null)
              _actionPill(
                icon: Ionicons.add,
                label: 'Record Inflow',
                isPrimary: true,
                isDark: isDark,
                onTap: onAddZakatInflow!,
              ),
            if (onAddZakatOutflow != null) ...[
              const SizedBox(width: 6),
              _actionPill(
                icon: Ionicons.arrowUpOutline,
                label: 'Record Outflow',
                isPrimary: false,
                isDark: isDark,
                onTap: onAddZakatOutflow!,
              ),
            ],
            if (onOpenZakatCalculator != null) ...[
              const SizedBox(width: 6),
              _actionPill(
                icon: Ionicons.calculatorOutline,
                label: 'Zakat Calculator',
                isPrimary: false,
                isDark: isDark,
                onTap: onOpenZakatCalculator!,
              ),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    if (isPrimary) {
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, size: 14, color: Colors.white),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B2223) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationCenter(
      BuildContext context,
      WidgetRef ref,
      AppDataState s,
      bool isDark,
      BuildContext? anchorContext) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final RenderBox? box = anchorContext?.findRenderObject() as RenderBox?;
    final Offset buttonPos = box != null
        ? box.localToGlobal(Offset.zero)
        : Offset(size.width - 50, 48);
    final Size buttonSize = box?.size ?? const Size(32, 32);

    const popoverWidth = 430.0;
    const popoverMaxHeight = 560.0;
    final top = (buttonPos.dy + buttonSize.height + 6)
        .clamp(8.0, size.height - popoverMaxHeight - 20);
    final right = (size.width - (buttonPos.dx + buttonSize.width))
        .clamp(12.0, size.width - popoverWidth - 12);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Notifications',
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogCtx, anim1, anim2) {
        void dismissDialog() {
          if (Navigator.of(dialogCtx).canPop()) {
            Navigator.of(dialogCtx).pop();
          }
        }

        return Stack(
          children: [
            Positioned(
              top: top,
              right: right,
              child: _DesktopNotificationPopover(
                s: s,
                isDark: isDark,
                onLogPayment: () {
                  dismissDialog();
                  onLogPayment();
                },
                onLogPaymentForTenant: onLogPaymentForTenant != null
                    ? (t) {
                        dismissDialog();
                        onLogPaymentForTenant!(t);
                      }
                    : null,
                onSelectTenant: onSelectTenant != null
                    ? (t) {
                        dismissDialog();
                        onSelectTenant!(t);
                      }
                    : null,
                onSelectWorkOrder: onSelectWorkOrder != null
                    ? (w) {
                        dismissDialog();
                        onSelectWorkOrder!(w);
                      }
                    : null,
                onNavigateTab: (tabIdx) {
                  dismissDialog();
                  onNavigateTab(tabIdx);
                },
                onOpenSettings: onOpenSettings != null
                    ? () {
                        dismissDialog();
                        onOpenSettings!();
                      }
                    : null,
                onAddWorkOrder: () {
                  dismissDialog();
                  onAddWorkOrder();
                },
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _showProfileMenu(
      BuildContext context,
      WidgetRef ref,
      AppDataState s,
      bool isDark,
      BuildContext? anchorContext) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final RenderBox? box = anchorContext?.findRenderObject() as RenderBox?;
    final Offset buttonPos = box != null
        ? box.localToGlobal(Offset.zero)
        : Offset(size.width - 50, 48);
    final Size buttonSize = box?.size ?? const Size(32, 32);

    const popoverWidth = 350.0;
    const popoverMaxHeight = 540.0;
    final top = (buttonPos.dy + buttonSize.height + 6)
        .clamp(8.0, size.height - popoverMaxHeight - 20);
    final right = (size.width - (buttonPos.dx + buttonSize.width))
        .clamp(12.0, size.width - popoverWidth - 12);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Profile',
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogCtx, anim1, anim2) {
        void dismissDialog() {
          if (Navigator.of(dialogCtx).canPop()) {
            Navigator.of(dialogCtx).pop();
          }
        }

        return Stack(
          children: [
            Positioned(
              top: top,
              right: right,
              child: _DesktopProfilePopover(
                s: s,
                isDark: isDark,
                onEditProfile: () {
                  dismissDialog();
                  if (onEditProfile != null) {
                    onEditProfile!();
                  } else {
                    _showEditProfileModal(context, ref);
                  }
                },
                onPropertyDetails: () {
                  dismissDialog();
                  _showPropertyDetailsModal(context, ref);
                },
                onOpenSettings: onOpenSettings != null
                    ? () {
                        dismissDialog();
                        onOpenSettings!();
                      }
                    : null,
                onToggleTheme: () {
                  final nextMode = isDark ? 'light' : 'dark';
                  ref.read(appDataProvider.notifier).setThemeMode(nextMode);
                },
                onAbout: () {
                  dismissDialog();
                  if (onAbout != null) {
                    onAbout!();
                  } else {
                    _showAboutDialog(context, isDark);
                  }
                },
                onKeyboardShortcuts: onKeyboardShortcuts != null
                    ? () {
                        dismissDialog();
                        onKeyboardShortcuts!();
                      }
                    : null,
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static void _showEditProfileModal(BuildContext context, WidgetRef ref) {
    final pm = ref.read(appDataProvider).propertyManager;
    final nameCtl = TextEditingController(text: pm?.name ?? '');
    final phoneCtl = TextEditingController(text: pm?.phone ?? '');
    final emailCtl = TextEditingController(text: pm?.email ?? '');
    String? avatar = pm?.avatar;
    String? error;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: 'Edit Profile',
            icon: Ionicons.personOutline,
            footer: SheetActions(
              cancelLabel: 'Cancel',
              primaryLabel: 'Save Changes',
              primaryIcon: const Icon(Ionicons.checkmark, size: 16),
              onPrimary: () {
                if (nameCtl.text.trim().isEmpty || phoneCtl.text.trim().isEmpty) {
                  setS(() => error = 'Name and phone number are required');
                  return;
                }
                ref.read(appDataProvider.notifier).setPropertyManager(
                      PropertyManager(
                        id: pm?.id ?? newId(),
                        name: nameCtl.text.trim(),
                        address: pm?.address ?? '',
                        phone: phoneCtl.text.trim(),
                        email: emailCtl.text.trim(),
                        avatar: avatar,
                        propertyName: pm?.propertyName,
                        ownerName: pm?.ownerName,
                        propertyPictures: pm?.propertyPictures ?? const [],
                        city: pm?.city,
                        state: pm?.state,
                        zipCode: pm?.zipCode,
                      ),
                    );
                Navigator.pop(ctx);
              },
            ),
            body: Column(
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
                        name: nameCtl.text.isEmpty ? 'P' : nameCtl.text,
                        uri: avatar,
                        radius: 36,
                        borderColor: AppColors.primary,
                        borderWidth: 2,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Ionicons.camera,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AppField(
                  label: 'Full Name',
                  hint: 'Property Manager or Owner',
                  controller: nameCtl,
                ),
                AppField(
                  label: 'Phone Number',
                  hint: 'Contact phone for tenants',
                  controller: phoneCtl,
                  keyboard: TextInputType.phone,
                ),
                AppField(
                  label: 'Email Address',
                  hint: 'Official email for receipts',
                  controller: emailCtl,
                  keyboard: TextInputType.emailAddress,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _showPropertyDetailsModal(BuildContext context, WidgetRef ref) {
    final pm = ref.read(appDataProvider).propertyManager;
    final nameCtl = TextEditingController(text: pm?.propertyName ?? '');
    final ownerCtl = TextEditingController(text: pm?.ownerName ?? '');
    final addrCtl = TextEditingController(text: pm?.address ?? '');

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: 'Property Details',
            icon: Ionicons.businessOutline,
            footer: SheetActions(
              cancelLabel: 'Cancel',
              primaryLabel: 'Save Property',
              primaryIcon: const Icon(Ionicons.checkmark, size: 16),
              onPrimary: () {
                ref.read(appDataProvider.notifier).setPropertyManager(
                      PropertyManager(
                        id: pm?.id ?? newId(),
                        name: pm?.name ?? '',
                        address: addrCtl.text.trim(),
                        phone: pm?.phone ?? '',
                        email: pm?.email ?? '',
                        avatar: pm?.avatar,
                        propertyName: nameCtl.text.trim(),
                        ownerName: ownerCtl.text.trim(),
                        propertyPictures: pm?.propertyPictures ?? const [],
                        city: pm?.city,
                        state: pm?.state,
                        zipCode: pm?.zipCode,
                      ),
                    );
                Navigator.pop(ctx);
              },
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppField(
                  label: 'Property Name',
                  hint: 'e.g. Sunset Heights Apartments',
                  controller: nameCtl,
                ),
                AppField(
                  label: 'Property Owner Name',
                  hint: 'e.g. Acme Realty LLC',
                  controller: ownerCtl,
                ),
                AppField(
                  label: 'Property Address',
                  hint: 'Full physical address',
                  controller: addrCtl,
                  maxLines: 3,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _showAboutDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF091E1F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Ionicons.business, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 12),
            const Text('RentManager Pro',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.6 (macOS Native Release)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669))),
            const SizedBox(height: 10),
            Text(
              'High-performance property management, tenant leasing, financial tracking, document vault, and automated cloud sync for modern landlords.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// Interactive Desktop Profile avatar button with hover highlight and online indicator.
class _DesktopProfileButton extends StatefulWidget {
  final AppDataState s;
  final bool isDark;
  final bool isCompact;
  final void Function(BuildContext context) onTap;

  const _DesktopProfileButton({
    required this.s,
    required this.isDark,
    required this.isCompact,
    required this.onTap,
  });

  @override
  State<_DesktopProfileButton> createState() => _DesktopProfileButtonState();
}

class _DesktopProfileButtonState extends State<_DesktopProfileButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final isDark = widget.isDark;
    final isCompact = widget.isCompact;
    final pm = s.propertyManager;
    final displayName = pm?.name.isNotEmpty == true ? pm!.name : 'Manager';

    final borderColor = _hovered
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
        : (isDark
            ? const Color.fromRGBO(255, 255, 255, 0.1)
            : const Color(0xFFE2E8F0));

    final bgColor = _hovered
        ? (isDark ? const Color(0xFF0D2B2C) : const Color(0xFFE6F4F1))
        : (isDark ? const Color(0xFF0B2223) : const Color(0xFFF1F5F9));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: 'Profile: $displayName • Click for details & preferences',
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap(context);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 32,
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 3 : 8,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(isCompact ? 16 : 8),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarView(
                      name: displayName,
                      uri: pm?.avatar,
                      radius: 13,
                      borderColor: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF0F766E),
                      borderWidth: 1.2,
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF040E0F)
                                : Colors.white,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 105),
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Ionicons.chevronDown,
                    size: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// macOS style Profile Popover displaying account information, portfolio stats, and shortcuts.
class _DesktopProfilePopover extends StatelessWidget {
  final AppDataState s;
  final bool isDark;
  final VoidCallback onEditProfile;
  final VoidCallback onPropertyDetails;
  final VoidCallback? onOpenSettings;
  final VoidCallback onToggleTheme;
  final VoidCallback onAbout;
  final VoidCallback? onKeyboardShortcuts;

  const _DesktopProfilePopover({
    required this.s,
    required this.isDark,
    required this.onEditProfile,
    required this.onPropertyDetails,
    required this.onOpenSettings,
    required this.onToggleTheme,
    required this.onAbout,
    this.onKeyboardShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    final pm = s.propertyManager;
    final displayName = pm?.name.isNotEmpty == true ? pm!.name : 'Property Manager';

    final bg = isDark ? const Color(0xFF07191A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF092224) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);
    final textPrimary = AppColors.heading;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeGreen = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final activeTenantsCount = s.scopedTenants.where((t) => t.status == 'active').length;
    final totalUnitsCount = (s.activeProperty != null && s.activeProperty!.totalUnits > 0
        ? s.activeProperty!.totalUnits
        : s.scopedTenants.map((t) => t.unit).where((u) => u.trim().isNotEmpty).toSet().length);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 350,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.16),
              blurRadius: 36,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: (isDark ? const Color(0xFF10B981) : Colors.black)
                  .withValues(alpha: isDark ? 0.06 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Profile Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0A2224) : const Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AvatarView(
                          name: displayName,
                          uri: pm?.avatar,
                          radius: 26,
                          borderColor: activeGreen,
                          borderWidth: 2,
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? const Color(0xFF0A2224) : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: activeGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Property Manager',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: activeGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pm?.email.isNotEmpty == true || pm?.phone.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              pm?.email.isNotEmpty == true ? pm!.email : pm!.phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Managed Property Overview Card
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Ionicons.businessOutline,
                            size: 14,
                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pm?.propertyName?.isNotEmpty == true
                                  ? pm!.propertyName!
                                  : 'Primary Managed Portfolio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (pm?.address.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          pm!.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '$activeTenantsCount Active Leases • ${totalUnitsCount > 0 ? totalUnitsCount : s.scopedTenants.length} Units',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Menu Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    _buildActionItem(
                      icon: Ionicons.createOutline,
                      title: 'Edit Profile',
                      subtitle: 'Update name, contact info, and avatar photo',
                      isDark: isDark,
                      onTap: onEditProfile,
                    ),
                    _buildActionItem(
                      icon: Ionicons.businessOutline,
                      title: 'Property Details',
                      subtitle: 'Edit property name, address, and units',
                      isDark: isDark,
                      onTap: onPropertyDetails,
                    ),
                    if (onOpenSettings != null)
                      _buildActionItem(
                        icon: Ionicons.settingsOutline,
                        title: 'Settings & Preferences',
                        subtitle: 'Cloud sync, security, and backup schedule',
                        isDark: isDark,
                        onTap: onOpenSettings!,
                      ),
                    _buildActionItem(
                      icon: isDark ? Ionicons.sunnyOutline : Ionicons.moonOutline,
                      title: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                      subtitle: isDark ? 'Currently in Dark Mode' : 'Currently in Light Mode',
                      isDark: isDark,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFFF59E0B) : const Color(0xFF0F766E))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isDark ? 'Dark' : 'Light',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF0F766E),
                          ),
                        ),
                      ),
                      onTap: onToggleTheme,
                    ),
                    if (onKeyboardShortcuts != null)
                      _buildActionItem(
                        icon: Ionicons.keypadOutline,
                        title: 'Keyboard Shortcuts',
                        subtitle: 'Quick cheatsheet and navigation hotkeys (⌘/)',
                        isDark: isDark,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '⌘ /',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                        ),
                        onTap: onKeyboardShortcuts!,
                      ),
                    _buildActionItem(
                      icon: Ionicons.informationCircleOutline,
                      title: 'About RentManager',
                      subtitle: 'Version 1.0.6 • Native Desktop',
                      isDark: isDark,
                      onTap: onAbout,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return _PopoverActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      isDark: isDark,
      onTap: onTap,
      trailing: trailing,
    );
  }
}

class _PopoverActionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? trailing;

  const _PopoverActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
    this.trailing,
  });

  @override
  State<_PopoverActionTile> createState() => _PopoverActionTileState();
}

class _PopoverActionTileState extends State<_PopoverActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = AppColors.heading;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeGreen = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final hoverBg = isDark ? const Color(0xFF0C2425) : const Color(0xFFF1F5F9);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _hovered ? activeGreen : textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null)
                widget.trailing!
              else
                Icon(
                  Ionicons.chevronForward,
                  size: 13,
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive Notification Bell with hover elevation and pulsing alert badge.
class _NotificationBellButton extends StatefulWidget {
  final int alertsCount;
  final int overdueCount;
  final bool isDark;
  final void Function(BuildContext context) onTap;

  const _NotificationBellButton({
    required this.alertsCount,
    required this.overdueCount,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<_NotificationBellButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.alertsCount > 0) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alertsCount > 0 && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.alertsCount == 0 && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final hasAlerts = widget.alertsCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: hasAlerts
            ? '${widget.alertsCount} active alerts (${widget.overdueCount} rent overdue) — click to open notification center'
            : 'All payments and work orders up to date — notification center',
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap(context);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? (isDark
                      ? const Color(0xFF143B3D)
                      : const Color(0xFFE2E8F0))
                  : (isDark
                      ? const Color(0xFF0B2223)
                      : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? (isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669))
                    : (isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.08)
                        : const Color(0xFFE2E8F0)),
                width: 1,
              ),
              boxShadow: _hovered && hasAlerts
                  ? [
                      BoxShadow(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: isDark ? 0.35 : 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  hasAlerts
                      ? Ionicons.notifications
                      : Ionicons.notificationsOutline,
                  size: 15.5,
                  color: isDark
                      ? (hasAlerts
                          ? const Color(0xFF34D399)
                          : const Color(0xFF94A3B8))
                      : (hasAlerts
                          ? const Color(0xFF059669)
                          : const Color(0xFF64748B)),
                ),
                if (hasAlerts)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _hovered ? 1.0 : _pulseAnimation.value,
                          child: child,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isDark ? const Color(0xFF040E0F) : Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.alertsCount > 9
                                ? '9+'
                                : '${widget.alertsCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
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
}

enum _NotifCategory { all, rent, workOrders, system }

/// Anchored Floating Notification Center Popover.
class _DesktopNotificationPopover extends ConsumerStatefulWidget {
  final AppDataState s;
  final bool isDark;
  final VoidCallback onLogPayment;
  final Function(Tenant tenant)? onLogPaymentForTenant;
  final Function(Tenant tenant)? onSelectTenant;
  final Function(WorkOrder workOrder)? onSelectWorkOrder;
  final ValueChanged<int> onNavigateTab;
  final VoidCallback? onOpenSettings;
  final VoidCallback onAddWorkOrder;

  const _DesktopNotificationPopover({
    required this.s,
    required this.isDark,
    required this.onLogPayment,
    this.onLogPaymentForTenant,
    required this.onSelectTenant,
    this.onSelectWorkOrder,
    required this.onNavigateTab,
    required this.onOpenSettings,
    required this.onAddWorkOrder,
  });

  @override
  ConsumerState<_DesktopNotificationPopover> createState() =>
      _DesktopNotificationPopoverState();
}

class _DesktopNotificationPopoverState
    extends ConsumerState<_DesktopNotificationPopover> {
  _NotifCategory _selectedCategory = _NotifCategory.all;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final isDark = widget.isDark;
    final notifState = ref.watch(desktopNotificationsProvider);
    final isMarkedAllRead = notifState.isMarkedAllRead;
    final isAllCleared = notifState.isAllCleared;
    final cur = s.selectedCurrency;
    final now = DateTime.now();
    final mk = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthName = DateFormat.MMMM().format(now);

    final currentMonthPayments = s.scopedPayments
        .where((p) =>
            p.paidForMonth == mk ||
            (p.paidDate != null && p.paidDate!.startsWith(mk)) ||
            (p.dueDate != null && p.dueDate!.startsWith(mk)))
        .toList();
    final paidTenantIds = currentMonthPayments
        .where((p) => p.status == 'paid')
        .map((p) => p.tenantId)
        .toSet();

    final overdueTenants = isAllCleared
        ? <Tenant>[]
        : s.scopedTenants
            .where((t) =>
                t.status == 'active' &&
                !paidTenantIds.contains(t.id) &&
                !notifState.dismissedIds.contains('rent_${t.id}'))
            .toList();

    final pendingOrders = isAllCleared
        ? <WorkOrder>[]
        : s.scopedWorkOrders
            .where((w) =>
                (w.status == 'pending' ||
                    w.status == 'in-progress' ||
                    w.status == 'open') &&
                !notifState.dismissedIds.contains('wo_${w.id}'))
            .toList();

    final totalAlerts = overdueTenants.length + pendingOrders.length;

    final bg = isDark ? const Color(0xFF07191A) : Colors.white;
    final cardBg =
        isDark ? const Color(0xFF092224) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);
    final textPrimary = AppColors.heading;
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeGreen =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 430,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.16),
              blurRadius: 36,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: (isDark ? const Color(0xFF10B981) : Colors.black)
                  .withValues(alpha: isDark ? 0.06 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Popover Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: activeGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Ionicons.notifications,
                        size: 16,
                        color: activeGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isAllCleared || isMarkedAllRead || totalAlerts == 0)
                                  ? activeGreen.withValues(alpha: 0.12)
                                  : const Color(0xFFEF4444)
                                      .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAllCleared
                                  ? 'Cleared'
                                  : (isMarkedAllRead
                                      ? 'All Read'
                                      : (totalAlerts > 0
                                          ? '$totalAlerts new'
                                          : 'Up to date')),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: (isAllCleared || isMarkedAllRead || totalAlerts == 0)
                                    ? activeGreen
                                    : const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isAllCleared && totalAlerts > 0) ...[
                      if (!isMarkedAllRead)
                        Tooltip(
                          message: 'Mark all as read',
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(desktopNotificationsProvider.notifier)
                                  .markAllAsRead();
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Ionicons.checkmarkDoneOutline,
                                    size: 14,
                                    color: activeGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Mark read',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: activeGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Tooltip(
                          message: 'Mark as unread',
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(desktopNotificationsProvider.notifier)
                                  .markAsUnread();
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Ionicons.mailUnreadOutline,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Mark unread',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 2),
                      Tooltip(
                        message: 'Clear all notifications',
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(desktopNotificationsProvider.notifier)
                                .clearAll();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Ionicons.trashOutline,
                                  size: 13,
                                  color: Color(0xFFEF4444),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Clear all',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else if (isAllCleared || notifState.dismissedIds.isNotEmpty) ...[
                      Tooltip(
                        message: 'Restore cleared notifications',
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(desktopNotificationsProvider.notifier)
                                .restoreAll();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Ionicons.arrowUndoOutline,
                                  size: 13,
                                  color: activeGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Restore',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: activeGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.06)
                              : const Color.fromRGBO(0, 0, 0, 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Ionicons.close,
                          size: 15,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Category Filter Tabs
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF041213)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      _buildTabItem(
                        label: 'All',
                        badge: (isMarkedAllRead || isAllCleared) ? null : totalAlerts,
                        category: _NotifCategory.all,
                        isDark: isDark,
                        activeColor: activeGreen,
                      ),
                      _buildTabItem(
                        label: 'Rent',
                        badge: (isMarkedAllRead || isAllCleared) ? null : overdueTenants.length,
                        badgeColor: const Color(0xFFEF4444),
                        category: _NotifCategory.rent,
                        isDark: isDark,
                        activeColor: activeGreen,
                      ),
                      _buildTabItem(
                        label: 'Work',
                        badge: (isMarkedAllRead || isAllCleared) ? null : pendingOrders.length,
                        badgeColor: const Color(0xFFF59E0B),
                        category: _NotifCategory.workOrders,
                        isDark: isDark,
                        activeColor: activeGreen,
                      ),
                      _buildTabItem(
                        label: 'System',
                        category: _NotifCategory.system,
                        isDark: isDark,
                        activeColor: activeGreen,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),
              Divider(height: 1, color: borderColor),

              // 3. Alerts Content List
              Flexible(
                child: _buildTabContent(
                  s: s,
                  isDark: isDark,
                  cur: cur,
                  monthName: monthName,
                  overdueTenants: overdueTenants,
                  pendingOrders: pendingOrders,
                  cardBg: cardBg,
                  borderColor: borderColor,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  activeGreen: activeGreen,
                ),
              ),

              Divider(height: 1, color: borderColor),

              // 4. Footer: Preferences Shortcut & Sync Status
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        widget.onOpenSettings?.call();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.settingsOutline,
                                size: 13, color: textSecondary),
                            const SizedBox(width: 5),
                            Text(
                              'Notification Preferences',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          s.preferences.driveAutoSync
                              ? 'Cloud Sync Active'
                              : 'Auto Backup Active',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required String label,
    int? badge,
    Color? badgeColor,
    required _NotifCategory category,
    required bool isDark,
    required Color activeColor,
  }) {
    final selected = _selectedCategory == category;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = category),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 5.5),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF0A2B2D) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(
                    color: isDark
                        ? const Color(0xFF34D399).withValues(alpha: 0.35)
                        : const Color(0xFFCBD5E1),
                    width: 1,
                  )
                : null,
            boxShadow: selected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? (AppColors.heading)
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? activeColor)
                        .withValues(alpha: selected ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: badgeColor ?? activeColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent({
    required AppDataState s,
    required bool isDark,
    required String cur,
    required String monthName,
    required List<Tenant> overdueTenants,
    required List<WorkOrder> pendingOrders,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color activeGreen,
  }) {
    final notifState = ref.watch(desktopNotificationsProvider);
    final isAllCleared = notifState.isAllCleared;

    switch (_selectedCategory) {
      case _NotifCategory.rent:
        if (overdueTenants.isEmpty) {
          final hasDismissedRent =
              notifState.dismissedIds.any((id) => id.startsWith('rent_')) ||
                  isAllCleared;
          return _buildEmptyState(
            icon: Ionicons.checkmarkDoneCircle,
            title: isAllCleared
                ? 'Rent Alerts Cleared'
                : 'All Rent Payments Up to Date!',
            subtitle: isAllCleared
                ? 'You have cleared rent alerts.'
                : 'Every active tenant has completed their rent payment for $monthName.',
            isDark: isDark,
            color: activeGreen,
            actionButton: hasDismissedRent
                ? InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(desktopNotificationsProvider.notifier).restoreAll();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: activeGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: activeGreen.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.arrowUndoOutline,
                              size: 13, color: activeGreen),
                          const SizedBox(width: 5),
                          Text(
                            'Restore Rent Alerts',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: activeGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: overdueTenants
              .map((t) => _buildRentCard(
                    t: t,
                    isDark: isDark,
                    cur: cur,
                    monthName: monthName,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    activeGreen: activeGreen,
                  ))
              .toList(),
        );

      case _NotifCategory.workOrders:
        if (pendingOrders.isEmpty) {
          final hasDismissedWo =
              notifState.dismissedIds.any((id) => id.startsWith('wo_')) ||
                  isAllCleared;
          return _buildEmptyState(
            icon: Ionicons.constructOutline,
            title: isAllCleared
                ? 'Work Order Alerts Cleared'
                : 'No Active Work Orders',
            subtitle: isAllCleared
                ? 'You have cleared work order notifications.'
                : 'All maintenance orders have been completed and verified.',
            isDark: isDark,
            color: activeGreen,
            actionButton: hasDismissedWo
                ? InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(desktopNotificationsProvider.notifier).restoreAll();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: activeGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: activeGreen.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.arrowUndoOutline,
                              size: 13, color: activeGreen),
                          const SizedBox(width: 5),
                          Text(
                            'Restore Work Orders',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: activeGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: pendingOrders
              .map((w) => _buildWorkOrderCard(
                    w: w,
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ))
              .toList(),
        );

      case _NotifCategory.system:
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildSystemCard(
              title: 'Google Drive Cloud Backup',
              subtitle: s.preferences.driveAutoSync
                  ? 'Auto cloud backup is operational • Keeping records synchronized'
                  : 'Auto cloud backup is currently paused in settings',
              icon: Ionicons.cloudDoneOutline,
              accentColor: const Color(0xFF3B82F6),
              isDark: isDark,
              cardBg: cardBg,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              primaryActionLabel: 'Settings',
              onPrimary: () {
                widget.onOpenSettings?.call();
              },
            ),
            _buildSystemCard(
              title: 'Workstation Storage & Cache',
              subtitle:
                  '${s.tenants.length} tenants • ${s.payments.length} transactions stored locally',
              icon: Ionicons.serverOutline,
              accentColor: const Color(0xFF8B5CF6),
              isDark: isDark,
              cardBg: cardBg,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              primaryActionLabel: 'Settings',
              onPrimary: () {
                widget.onOpenSettings?.call();
              },
            ),
          ],
        );

      case _NotifCategory.all:
        if (isAllCleared || (overdueTenants.isEmpty && pendingOrders.isEmpty)) {
          return _buildEmptyState(
            icon: isAllCleared
                ? Ionicons.checkmarkCircleOutline
                : Ionicons.shieldCheckmarkOutline,
            title: isAllCleared
                ? 'All Notifications Cleared'
                : 'All Caught Up!',
            subtitle: isAllCleared
                ? 'You have cleared all active alerts and notifications.'
                : 'No overdue rent payments or urgent maintenance tickets require attention.',
            isDark: isDark,
            color: activeGreen,
            actionButton: (isAllCleared || notifState.dismissedIds.isNotEmpty)
                ? InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(desktopNotificationsProvider.notifier).restoreAll();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: activeGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: activeGreen.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.arrowUndoOutline,
                              size: 13, color: activeGreen),
                          const SizedBox(width: 5),
                          Text(
                            'Restore Notifications',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: activeGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (overdueTenants.isNotEmpty) ...[
              _buildSectionHeader(
                title: 'Overdue Rent Payments',
                count: overdueTenants.length,
                color: const Color(0xFFEF4444),
                icon: Ionicons.alertCircleOutline,
              ),
              const SizedBox(height: 6),
              ...overdueTenants.map((t) => _buildRentCard(
                    t: t,
                    isDark: isDark,
                    cur: cur,
                    monthName: monthName,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    activeGreen: activeGreen,
                  )),
              const SizedBox(height: 8),
            ],
            if (pendingOrders.isNotEmpty) ...[
              _buildSectionHeader(
                title: 'Active Work Orders',
                count: pendingOrders.length,
                color: const Color(0xFFF59E0B),
                icon: Ionicons.constructOutline,
              ),
              const SizedBox(height: 6),
              ...pendingOrders.take(4).map((w) => _buildWorkOrderCard(
                    w: w,
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  )),
              const SizedBox(height: 8),
            ],
            _buildSectionHeader(
              title: 'System Health',
              count: null,
              color: const Color(0xFF3B82F6),
              icon: Ionicons.pulseOutline,
            ),
            const SizedBox(height: 6),
            _buildSystemCard(
              title: 'Cloud Sync & Storage',
              subtitle: s.preferences.driveAutoSync
                  ? 'Auto cloud backup active • Data synchronized'
                  : 'Auto cloud backup paused in settings',
              icon: Ionicons.cloudDoneOutline,
              accentColor: const Color(0xFF3B82F6),
              isDark: isDark,
              cardBg: cardBg,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              primaryActionLabel: 'Settings',
              onPrimary: () {
                widget.onOpenSettings?.call();
              },
            ),
          ],
        );
    }
  }

  Widget _buildSectionHeader({
    required String title,
    int? count,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRentCard({
    required Tenant t,
    required bool isDark,
    required String cur,
    required String monthName,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color activeGreen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3.5, color: const Color(0xFFEF4444)),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor:
                          const Color(0xFFEF4444).withValues(alpha: 0.15),
                      child: Text(
                        t.name.isNotEmpty ? t.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              if (t.unit.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4.5, vertical: 0.5),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromRGBO(
                                            255, 255, 255, 0.08)
                                        : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Unit ${t.unit}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1.5),
                          Text(
                            'Rent: $cur${t.rentAmount.toStringAsFixed(0)} • Overdue for $monthName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (widget.onSelectTenant != null)
                      Tooltip(
                        message: 'View Tenant Profile',
                        child: InkWell(
                          onTap: () {
                            widget.onSelectTenant!(t);
                          },
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color.fromRGBO(255, 255, 255, 0.05)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: borderColor),
                            ),
                            child: Icon(
                              Ionicons.personOutline,
                              size: 13,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Record Payment for ${t.name}',
                      child: InkWell(
                        onTap: () {
                          if (widget.onLogPaymentForTenant != null) {
                            widget.onLogPaymentForTenant!(t);
                          } else {
                            widget.onLogPayment();
                          }
                        },
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: activeGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: activeGreen.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.cashOutline,
                                  size: 11, color: activeGreen),
                              const SizedBox(width: 3.5),
                              Text(
                                'Pay',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: activeGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Dismiss notification',
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(desktopNotificationsProvider.notifier)
                              .dismiss('rent_${t.id}');
                        },
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.all(4.5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.04)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: borderColor),
                          ),
                          child: Icon(
                            Ionicons.close,
                            size: 11,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkOrderCard({
    required WorkOrder w,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final priority = (w.priority ?? 'normal').toLowerCase();
    final isUrgent = priority == 'urgent' || priority == 'high';
    final priorityColor =
        isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3.5, color: priorityColor),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Ionicons.constructOutline,
                          size: 13, color: priorityColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  w.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4.5, vertical: 0.5),
                                decoration: BoxDecoration(
                                  color:
                                      priorityColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  priority.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: priorityColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1.5),
                          Text(
                            '${w.category} • ${w.assignedTo.isEmpty ? "Unassigned" : w.assignedTo}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Open Work Order Details',
                      child: InkWell(
                        onTap: () {
                          if (widget.onSelectWorkOrder != null) {
                            widget.onSelectWorkOrder!(w);
                          } else {
                            widget.onNavigateTab(2);
                          }
                        },
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(Ionicons.arrowForward,
                                  size: 10, color: Color(0xFFF59E0B)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Dismiss notification',
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ref
                              .read(desktopNotificationsProvider.notifier)
                              .dismiss('wo_${w.id}');
                        },
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.all(4.5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.04)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: borderColor),
                          ),
                          child: Icon(
                            Ionicons.close,
                            size: 11,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    String? primaryActionLabel,
    VoidCallback? onPrimary,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3.5, color: accentColor),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(icon, size: 13, color: accentColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1.5),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (primaryActionLabel != null && onPrimary != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: onPrimary,
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            primaryActionLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color color,
    Widget? actionButton,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            if (actionButton != null) ...[
              const SizedBox(height: 14),
              actionButton,
            ],
          ],
        ),
      ),
    );
  }
}

class DesktopDirectSearchBar extends ConsumerStatefulWidget {
  final FocusNode? focusNode;
  final ValueChanged<int> onNavigateTab;
  final Function(Tenant tenant)? onSelectTenant;
  final VoidCallback onAddTenant;
  final VoidCallback onLogPayment;
  final VoidCallback onLogExpense;
  final VoidCallback onAddWorkOrder;
  final VoidCallback onAddDocument;
  final VoidCallback onSyncDocuments;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final VoidCallback? onPrintReport;
  final VoidCallback? onAddZakatInflow;
  final VoidCallback? onAddZakatOutflow;
  final VoidCallback? onOpenZakatCalculator;
  final VoidCallback? onDeposit;
  final VoidCallback? onSyncRoll;
  final VoidCallback? onBatchRentCollection;
  final VoidCallback? onGenerateReceipt;
  final VoidCallback? onOpenCashFlowForecast;

  const DesktopDirectSearchBar({
    super.key,
    this.focusNode,
    required this.onNavigateTab,
    this.onSelectTenant,
    required this.onAddTenant,
    required this.onLogPayment,
    required this.onLogExpense,
    required this.onAddWorkOrder,
    required this.onAddDocument,
    required this.onSyncDocuments,
    required this.onExportCsv,
    required this.onExportPdf,
    this.onPrintReport,
    this.onAddZakatInflow,
    this.onAddZakatOutflow,
    this.onOpenZakatCalculator,
    this.onDeposit,
    this.onSyncRoll,
    this.onBatchRentCollection,
    this.onGenerateReceipt,
    this.onOpenCashFlowForecast,
  });

  @override
  ConsumerState<DesktopDirectSearchBar> createState() =>
      _DesktopDirectSearchBarState();
}

class _SearchDirectResult {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color iconColor;
  final String? badge;
  final VoidCallback onSelect;

  const _SearchDirectResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.iconColor,
    this.badge,
    required this.onSelect,
  });
}

class _DesktopDirectSearchBarState
    extends ConsumerState<DesktopDirectSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _ownsFocusNode = false;
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  final ScrollController _scrollController = ScrollController();
  bool _isFocused = false;
  int _highlightedIndex = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _isFocused = true;
        _highlightedIndex = 0;
      });
      _overlayController.show();
    } else {
      setState(() {
        _isFocused = false;
      });
      _overlayController.hide();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 48.0;
    final target = _highlightedIndex * itemHeight;
    if (target < _scrollController.offset) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
      );
    } else if (target + itemHeight > _scrollController.offset + 250) {
      _scrollController.animateTo(
        target + itemHeight - 250,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectItem(_SearchDirectResult item) {
    _focusNode.unfocus();
    _overlayController.hide();
    _controller.clear();
    setState(() {
      _query = '';
      _isFocused = false;
    });
    item.onSelect();
  }

  List<_SearchDirectResult> _computeResults(AppDataState s) {
    final q = _query.trim().toLowerCase();
    final results = <_SearchDirectResult>[];

    if (q.isEmpty) {
      // 1. Quick Common Actions
      results.add(
        _SearchDirectResult(
          id: 'action_rent',
          title: 'Record Rent Payment',
          subtitle: 'Collect tenant rent or log payment',
          category: 'ACTION',
          icon: Ionicons.cashOutline,
          iconColor: const Color(0xFF10B981),
          badge: '⇧⌘P',
          onSelect: widget.onLogPayment,
        ),
      );
      if (widget.onBatchRentCollection != null) {
        results.add(
          _SearchDirectResult(
            id: 'action_batch_rent',
            title: 'Batch Rent Collection Sheet',
            subtitle: '1-click monthly roll to collect all active tenants',
            category: 'ACTION',
            icon: Ionicons.layersOutline,
            iconColor: const Color(0xFF6366F1),
            badge: '⇧⌘B',
            onSelect: widget.onBatchRentCollection!,
          ),
        );
      }
      if (widget.onGenerateReceipt != null) {
        results.add(
          _SearchDirectResult(
            id: 'action_receipt',
            title: 'Generate Rent Receipt & Invoice',
            subtitle: 'Branded PDF payment receipt with manager signature block',
            category: 'ACTION',
            icon: Ionicons.receiptOutline,
            iconColor: const Color(0xFF0EA5E9),
            badge: '⇧⌘I',
            onSelect: widget.onGenerateReceipt!,
          ),
        );
      }
      if (widget.onOpenCashFlowForecast != null) {
        results.add(
          _SearchDirectResult(
            id: 'action_forecast',
            title: 'Cash Flow Forecast & Financial Health',
            subtitle: '6-12 month predictive cash flow, NOI, and lease renewal pipeline',
            category: 'ACTION',
            icon: Ionicons.trendingUpOutline,
            iconColor: const Color(0xFF10B981),
            badge: '⇧⌘F',
            onSelect: widget.onOpenCashFlowForecast!,
          ),
        );
      }
      results.add(
        _SearchDirectResult(
          id: 'action_expense',
          title: 'Record Operational Expense',
          subtitle: 'Maintenance, utility, or property operational bill',
          category: 'ACTION',
          icon: Ionicons.receiptOutline,
          iconColor: const Color(0xFFEF4444),
          badge: '⇧⌘E',
          onSelect: widget.onLogExpense,
        ),
      );
      results.add(
        _SearchDirectResult(
          id: 'action_tenant',
          title: 'Add New Tenant & Lease',
          subtitle: 'Register new occupant, lease agreement, and unit',
          category: 'ACTION',
          icon: Ionicons.personAddOutline,
          iconColor: const Color(0xFF3B82F6),
          badge: '⌘N',
          onSelect: widget.onAddTenant,
        ),
      );
      results.add(
        _SearchDirectResult(
          id: 'action_work',
          title: 'New Maintenance Work Order',
          subtitle: 'File maintenance or contractor repair ticket',
          category: 'ACTION',
          icon: Ionicons.constructOutline,
          iconColor: const Color(0xFFF59E0B),
          badge: '⇧⌘W',
          onSelect: widget.onAddWorkOrder,
        ),
      );

      // 2. Active Scoped Tenants (top 4)
      for (final t in s.scopedTenants.take(4)) {
        results.add(
          _SearchDirectResult(
            id: 'tenant_${t.id}',
            title: t.name,
            subtitle:
                'Unit ${t.unit.isEmpty ? 'N/A' : t.unit} • ${s.selectedCurrency}${t.rentAmount.toStringAsFixed(0)}/mo • ${t.phone.isNotEmpty ? t.phone : 'No phone'}',
            category: 'TENANT',
            icon: Ionicons.personOutline,
            iconColor: const Color(0xFF0F766E),
            badge: t.status.toUpperCase(),
            onSelect: () {
              widget.onNavigateTab(1);
              widget.onSelectTenant?.call(t);
            },
          ),
        );
      }
      return results;
    }

    // Dynamic Search matching query:

    // A. Tenants (Scoped)
    for (final t in s.scopedTenants) {
      final nameMatch = t.name.toLowerCase().contains(q);
      final unitMatch = t.unit.toLowerCase().contains(q);
      final phoneMatch = t.phone.toLowerCase().contains(q);
      final addressMatch = (t.address ?? '').toLowerCase().contains(q);

      if (nameMatch || unitMatch || phoneMatch || addressMatch) {
        results.add(
          _SearchDirectResult(
            id: 'tenant_${t.id}',
            title: t.name,
            subtitle:
                'Unit ${t.unit.isEmpty ? 'N/A' : t.unit} • ${t.address?.isNotEmpty == true ? t.address! : 'Main'} • ${s.selectedCurrency}${t.rentAmount.toStringAsFixed(0)}/mo',
            category: 'TENANT',
            icon: Ionicons.personOutline,
            iconColor: const Color(0xFF10B981),
            badge: t.status.toUpperCase(),
            onSelect: () {
              widget.onNavigateTab(1);
              widget.onSelectTenant?.call(t);
            },
          ),
        );
      }
    }

    // B. Work Orders (Scoped)
    for (final w in s.scopedWorkOrders) {
      final titleMatch = w.title.toLowerCase().contains(q);
      final unitMatch = (w.unit ?? '').toLowerCase().contains(q);
      final catMatch = w.category.toLowerCase().contains(q);
      final descMatch = w.description.toLowerCase().contains(q);

      if (titleMatch || unitMatch || catMatch || descMatch) {
        results.add(
          _SearchDirectResult(
            id: 'wo_${w.id}',
            title: w.title,
            subtitle: 'Unit ${w.unit ?? 'General'} • ${w.category} • ${w.status}',
            category: 'MAINTENANCE',
            icon: Ionicons.constructOutline,
            iconColor: const Color(0xFFF59E0B),
            badge: w.status.toUpperCase(),
            onSelect: () => widget.onNavigateTab(2),
          ),
        );
      }
    }

    // C. Documents (Scoped)
    for (final d in s.scopedDocuments) {
      final titleMatch = d.title.toLowerCase().contains(q);
      final typeMatch = d.type.toLowerCase().contains(q);
      final fileNameMatch = d.fileName.toLowerCase().contains(q);

      if (titleMatch || typeMatch || fileNameMatch) {
        results.add(
          _SearchDirectResult(
            id: 'doc_${d.id}',
            title: d.title,
            subtitle: '${d.type} • ${d.fileName}',
            category: 'DOCUMENT',
            icon: Ionicons.documentTextOutline,
            iconColor: const Color(0xFF8B5CF6),
            badge: 'DOC',
            onSelect: () => widget.onNavigateTab(3),
          ),
        );
      }
    }

    // D. Actions
    final actionKeywords = [
      (
        'Record Rent Payment',
        'Collect rent from tenant',
        ['rent', 'collect', 'payment', 'record rent', 'cash', 'money'],
        Ionicons.cashOutline,
        const Color(0xFF10B981),
        '⇧⌘P',
        widget.onLogPayment,
      ),
      if (widget.onBatchRentCollection != null)
        (
          'Batch Rent Collection Sheet',
          'Collect monthly rent from all active tenants in 1 click',
          ['batch', 'bulk', 'roll', 'collect all', 'rent roll', 'batch collect'],
          Ionicons.layersOutline,
          const Color(0xFF6366F1),
          '⇧⌘B',
          widget.onBatchRentCollection!,
        ),
      if (widget.onGenerateReceipt != null)
        (
          'Generate Rent Receipt & Invoice',
          'Print or export branded PDF rent receipt or invoice',
          ['receipt', 'invoice', 'rent receipt', 'pdf receipt', 'voucher', 'slip', 'print receipt'],
          Ionicons.receiptOutline,
          const Color(0xFF0EA5E9),
          '⇧⌘I',
          widget.onGenerateReceipt!,
        ),
      if (widget.onOpenCashFlowForecast != null)
        (
          'Cash Flow Forecast & Financial Health',
          'Predictive cash flow, NOI, OER, and occupancy solvency model',
          ['forecast', 'cash flow', 'projection', 'noi', 'oer', 'solvency', 'predictive', 'financial health'],
          Ionicons.trendingUpOutline,
          const Color(0xFF10B981),
          '⇧⌘F',
          widget.onOpenCashFlowForecast!,
        ),
      (
        'Record Operational Expense',
        'Record expense or utility bill',
        ['expense', 'bill', 'utility', 'cost', 'spend', 'maintenance'],
        Ionicons.receiptOutline,
        const Color(0xFFEF4444),
        '⇧⌘E',
        widget.onLogExpense,
      ),
      (
        'Add New Tenant',
        'Register new tenant and unit lease',
        ['tenant', 'lease', 'add tenant', 'person', 'occupant'],
        Ionicons.personAddOutline,
        const Color(0xFF3B82F6),
        '⌘N',
        widget.onAddTenant,
      ),
      (
        'New Work Order',
        'Create repair or maintenance ticket',
        [
          'work order',
          'repair',
          'fix',
          'contractor',
          'maintenance',
          'plumb',
          'electric'
        ],
        Ionicons.constructOutline,
        const Color(0xFFF59E0B),
        '⇧⌘W',
        widget.onAddWorkOrder,
      ),
      (
        'Upload Document',
        'Attach lease, agreement, or deed file',
        ['upload', 'document', 'pdf', 'contract', 'agreement', 'file'],
        Ionicons.cloudUploadOutline,
        const Color(0xFF8B5CF6),
        '⇧⌘U',
        widget.onAddDocument,
      ),
      (
        'Sync Cloud Documents',
        'Backup and sync document files',
        ['sync', 'cloud', 'backup', 'drive', 'save'],
        Ionicons.syncOutline,
        const Color(0xFF0F766E),
        '⇧⌘S',
        widget.onSyncDocuments,
      ),
      (
        'Export Financial CSV',
        'Download financial spreadsheet',
        ['csv', 'export', 'excel', 'sheet', 'spreadsheet'],
        Ionicons.documentTextOutline,
        const Color(0xFF10B981),
        'CSV',
        widget.onExportCsv,
      ),
      (
        'Export Financial PDF Summary',
        'Generate printable PDF statement',
        ['pdf', 'export pdf', 'report', 'summary', 'statement'],
        Ionicons.documentOutline,
        const Color(0xFF0284C7),
        '⇧⌘R',
        widget.onExportPdf,
      ),
    ];

    for (final act in actionKeywords) {
      if (act.$3.any((keyword) => keyword.contains(q) || q.contains(keyword))) {
        results.add(
          _SearchDirectResult(
            id: 'act_${act.$1}',
            title: act.$1,
            subtitle: act.$2,
            category: 'ACTION',
            icon: act.$4,
            iconColor: act.$5,
            badge: act.$6,
            onSelect: act.$7,
          ),
        );
      }
    }

    // E. Navigation
    final navKeywords = [
      (
        'Overview Dashboard',
        'Monthly overview & KPI analytics',
        ['overview', 'dashboard', 'home', 'kpi'],
        0,
        Ionicons.homeOutline
      ),
      (
        'Tenants Directory',
        'All tenants, rent roll & contracts',
        ['tenants', 'directory', 'people'],
        1,
        Ionicons.peopleOutline
      ),
      (
        'Work Orders',
        'Property maintenance & repairs',
        ['work orders', 'repairs', 'maintenance'],
        2,
        Ionicons.constructOutline
      ),
      (
        'Documents & Leases',
        'Property deeds & legal files',
        ['documents', 'files', 'leases'],
        3,
        Ionicons.folderOutline
      ),
      (
        'Financial Reports',
        'Cash flow & statements',
        ['reports', 'finance', 'statements'],
        4,
        Ionicons.barChartOutline
      ),
      if (s.preferences.showZakat)
        (
          'Zakat Portfolio',
          'Annual rental wealth zakat calculation',
          ['zakat', 'charity', 'wealth'],
          5,
          Ionicons.calculatorOutline
        ),
    ];

    for (final nav in navKeywords) {
      if (nav.$3.any((kw) => kw.contains(q) || q.contains(kw))) {
        results.add(
          _SearchDirectResult(
            id: 'nav_${nav.$4}',
            title: nav.$1,
            subtitle: nav.$2,
            category: 'NAVIGATION',
            icon: nav.$5,
            iconColor: const Color(0xFF38BDF8),
            badge: '⌘${nav.$4 + 1}',
            onSelect: () => widget.onNavigateTab(nav.$4),
          ),
        );
      }
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final results = _computeResults(s);

    if (_highlightedIndex >= results.length) {
      _highlightedIndex = results.isEmpty ? 0 : results.length - 1;
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (ctx) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _focusNode.unfocus();
                    _overlayController.hide();
                  },
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomCenter,
                followerAnchor: Alignment.topCenter,
                offset: const Offset(0, 8),
                child: FocusScope(
                  canRequestFocus: false,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 420,
                      constraints: const BoxConstraints(maxHeight: 380),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF091E1F) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color.fromRGBO(255, 255, 255, 0.12)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.5 : 0.14),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0B2425)
                                    : const Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark
                                        ? const Color.fromRGBO(
                                            255, 255, 255, 0.06)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _query.isEmpty
                                        ? 'QUICK SEARCH & SHORTCUTS'
                                        : '${results.length} MATCHES FOUND',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Direct Search',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: results.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Ionicons.searchOutline,
                                            size: 28,
                                            color: isDark
                                                ? const Color(0xFF64748B)
                                                : const Color(0xFF94A3B8),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'No results matching "$_query"',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Try searching by tenant name, unit number, or action keyword',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      itemCount: results.length,
                                      itemBuilder: (ctx, idx) {
                                        final item = results[idx];
                                        final isHighlighted =
                                            idx == _highlightedIndex;
                                        return MouseRegion(
                                          onEnter: (_) {
                                            setState(
                                                () => _highlightedIndex = idx);
                                          },
                                          child: InkWell(
                                            onTap: () => _selectItem(item),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7),
                                              color: isHighlighted
                                                  ? (isDark
                                                      ? const Color(0xFF133233)
                                                      : const Color(0xFFE6F4F1))
                                                  : Colors.transparent,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: item.iconColor
                                                          .withValues(
                                                              alpha: isDark
                                                                  ? 0.2
                                                                  : 0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: Icon(item.icon,
                                                        size: 14,
                                                        color: item.iconColor),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          item.title,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isDark
                                                                ? Colors.white
                                                                : const Color(
                                                                    0xFF0F172A),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 1.5),
                                                        Text(
                                                          item.subtitle,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF94A3B8)
                                                                : const Color(
                                                                    0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (item.badge != null) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 5,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDark
                                                            ? const Color(
                                                                0xFF1A3839)
                                                            : const Color(
                                                                0xFFE2E8F0),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        item.badge!,
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: isDark
                                                              ? const Color(
                                                                  0xFF34D399)
                                                              : const Color(
                                                                  0xFF059669),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF07191A)
                                    : const Color(0xFFF1F5F9),
                                border: Border(
                                  top: BorderSide(
                                    color: isDark
                                        ? const Color.fromRGBO(
                                            255, 255, 255, 0.06)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '↑↓ navigate',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '↵ select',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8)),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'esc dismiss',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8)),
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
            ],
          );
        },
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (results.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex + 1) % results.length;
                });
                _scrollToHighlighted();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (results.isNotEmpty) {
                setState(() {
                  _highlightedIndex =
                      (_highlightedIndex - 1 + results.length) % results.length;
                });
                _scrollToHighlighted();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              _controller.clear();
              setState(() {
                _query = '';
                _highlightedIndex = 0;
              });
              _focusNode.unfocus();
              _overlayController.hide();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (results.isNotEmpty &&
                  _highlightedIndex >= 0 &&
                  _highlightedIndex < results.length) {
                _selectItem(results[_highlightedIndex]);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: _isFocused ? 280 : 220,
            height: 30,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0B2223)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFF10B981)
                    : (isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.08)
                        : const Color(0xFFE2E8F0)),
                width: _isFocused ? 1.2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(
                  Ionicons.searchOutline,
                  size: 13,
                  color: _isFocused
                      ? const Color(0xFF10B981)
                      : (isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.heading,
                    ),
                    cursorColor: const Color(0xFF10B981),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: 'Search portfolio, tenants, actions...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _query = val;
                        _highlightedIndex = 0;
                      });
                      if (!_overlayController.isShowing) {
                        _overlayController.show();
                      }
                    },
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  InkWell(
                    onTap: () {
                      _controller.clear();
                      setState(() {
                        _query = '';
                        _highlightedIndex = 0;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Ionicons.closeCircle,
                        size: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF133233)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '⌘ K',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
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
}
