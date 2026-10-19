import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';

import '../../services/drive_backup_service.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/wave_animation.dart';
import '../desktop/desktop_overview_view.dart';
import '../desktop/desktop_rent_receipt_modal.dart';
import '../desktop/desktop_property_modal.dart';
import '../onboarding/bank_setup_modal.dart';
import '../tenants/tenants_view.dart';

/// Port of `src/screens/OverviewScreen.tsx` — dashboard with rent-roll/expenses
/// tabs, month/year pill selector, monthly summary, selection-mode bulk
/// actions, monthly-notes checklist, bank deposits and preview/sync.
class OverviewView extends ConsumerStatefulWidget {
  final VoidCallback onSettings;
  const OverviewView({super.key, required this.onSettings});

  // ignore: library_private_types_in_public_api
  static final GlobalKey<_OverviewViewState> globalKey =
      GlobalKey<_OverviewViewState>();

  static void showPaymentSheet(
    BuildContext context, {
    Payment? payment,
    Tenant? tenant,
  }) {
    globalKey.currentState?._paymentSheet(context, payment, tenant);
  }

  static void showRentDetails(
    BuildContext context, {
    required Payment payment,
    Tenant? tenant,
  }) {
    globalKey.currentState?._rentDetails(context, payment, tenant);
  }

  static void showExpenseSheet(BuildContext context, {Expense? expense}) {
    globalKey.currentState?._expenseSheet(context, expense);
  }

  static void showExpenseDetails(
    BuildContext context, {
    required Expense expense,
  }) {
    final state = globalKey.currentState;
    if (state != null) {
      state._expenseDetails(context, state.ref.read(appDataProvider), expense);
    }
  }

  static void showDepositSheet(
    BuildContext context, {
    BankDeposit? deposit,
    double net = 0.0,
  }) {
    globalKey.currentState?._depositSheet(context, deposit, net);
  }

  static void showDepositDetails(
    BuildContext context, {
    required BankDeposit deposit,
  }) {
    globalKey.currentState?._depositDetails(context, deposit);
  }

  static void showChecklistModal(BuildContext context, {String? monthKey}) {
    final state = globalKey.currentState;
    if (state != null) {
      final y = state.ref.read(appDataProvider).selectedYear;
      final mk = monthKey ?? state._key(y, state._month);
      state._noteEditSheet(
        context,
        mk,
        state.ref.read(appDataProvider.notifier),
        null,
      );
    }
  }

  static void showSyncSheet(
    BuildContext context, [
    String initialType = 'all',
  ]) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop && DesktopOverviewView.globalKey.currentState != null) {
      DesktopOverviewView.showSyncDialog(context, initialType);
    } else {
      globalKey.currentState?._syncSheet(context, initialType);
    }
  }

  @override
  ConsumerState<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends ConsumerState<OverviewView> {
  String _tab = 'rentRoll';
  int _month = DateTime.now().month;
  // Selection mode (ports RentRollTable/ExpensesTable isSelectionMode).
  bool _selecting = false;
  final Set<String> _selected = {};
  // Loading/sync wave (ports GenericWaveAnimation via isLoadingOverview /
  // isSwitchingTab / isSwitchingMonthYear).
  bool _wave = false;
  Timer? _waveTimer;
  bool _fabOpen = false;
  final GlobalKey<_FanFabState> _fabKey = GlobalKey<_FanFabState>();

  @override
  void initState() {
    super.initState();
    _wave = true;
    _waveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _wave = false);
    });
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    super.dispose();
  }

  /// Briefly show the skeleton wave, mirroring Expo's 800ms switch delay.
  void _flashWave() {
    _waveTimer?.cancel();
    setState(() => _wave = true);
    _waveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _wave = false);
    });
  }

  String _key(int y, int m) => '$y-${m.toString().padLeft(2, '0')}';

  String _prevKey() {
    final y = ref.read(appDataProvider).selectedYear;
    var m = _month - 1;
    var yy = y;
    if (m < 1) {
      m = 12;
      yy--;
    }
    return _key(yy, m);
  }

  /// Unit-aware sort (numeric parts first) — ports RentRollTable sort.
  static int _unitSort(String a, String b) {
    final ra = RegExp(r'(\d+)').firstMatch(a);
    final rb = RegExp(r'(\d+)').firstMatch(b);
    if (ra != null && rb != null) {
      final c = int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
      if (c != 0) return c;
    }
    return a.compareTo(b);
  }

  void _clearSelection() {
    _selecting = false;
    _selected.clear();
  }

  void _stepMonth(int dir) {
    setState(() {
      var m = _month + dir;
      var y = ref.read(appDataProvider).selectedYear;
      if (m < 1) {
        m = 12;
        y--;
        ref.read(appDataProvider.notifier).setYear(y);
      } else if (m > 12) {
        m = 1;
        y++;
        ref.read(appDataProvider.notifier).setYear(y);
      }
      _month = m;
      _clearSelection();
    });
    _flashWave();
  }

  void _stepYear(int dir) {
    final y = ref.read(appDataProvider).selectedYear + dir;
    if (y < 1900 || y > 2100) return;
    setState(() {
      ref.read(appDataProvider.notifier).setYear(y);
      _clearSelection();
    });
    _flashWave();
  }

  // ---------- Visual helpers ----------

  static const _monthShort = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthLong = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _short(String? ym) {
    if (ym == null || ym.length < 7) return '';
    final m = int.tryParse(ym.substring(5, 7)) ?? 0;
    if (m < 1 || m > 12) return ym;
    return _monthShort[m];
  }

  static Color _hex(String? c) {
    var v = (c ?? '').replaceFirst('#', '').trim();
    if (v.length == 6) v = 'FF$v';
    final n = int.tryParse(v, radix: 16);
    return n == null ? AppColors.primary : Color(n);
  }

  Color _catColor(AppDataState s, String name) {
    final hit = s.expenseCategories.where((c) => c.name == name).toList();
    return _hex(hit.isEmpty ? '#4CAF50' : hit.first.color);
  }

  static Color _contrast(Color c) =>
      c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  IconData _rentStatusIcon(String status) {
    switch (status) {
      case 'paid':
        return Icons.check_circle;
      case 'pending':
        return Icons.schedule;
      case 'overdue':
        return Icons.warning;
      case 'partial':
        return Icons.circle;
      default:
        return Icons.help_outline;
    }
  }

  Color _rentStatusColor(String status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF4CAF50);
      case 'pending':
        return const Color(0xFFFF9800);
      case 'overdue':
        return const Color(0xFFFF6B6B);
      case 'partial':
        return const Color(0xFFFFB74D);
      default:
        return const Color(0xFFA0D8D8);
    }
  }

  Color _rentStatusBg(String status) {
    switch (status) {
      case 'pending':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 152, 0, 0.08)
            : const Color(0xFFFFF8E7);
      case 'overdue':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 107, 107, 0.08)
            : const Color(0xFFFFF0F0);
      case 'partial':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 183, 77, 0.08)
            : const Color(0xFFFFF7ED);
      default:
        return AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.03)
            : AppColors.cardBackground;
    }
  }

  Color _rentStatusBorder(String status) {
    switch (status) {
      case 'pending':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 152, 0, 0.15)
            : const Color(0xFFFFE0B2);
      case 'overdue':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 107, 107, 0.15)
            : const Color(0xFFFFCDD2);
      case 'partial':
        return AppColors.isDark
            ? const Color.fromRGBO(255, 183, 77, 0.15)
            : const Color(0xFFFFE0B2);
      default:
        return AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.08)
            : AppColors.border;
    }
  }

  Color _expStatusBg(String status) => status == 'pending'
      ? (AppColors.isDark
            ? const Color.fromRGBO(255, 152, 0, 0.08)
            : const Color(0xFFFFF8E7))
      : (AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.03)
            : AppColors.cardBackground);

  Color _expStatusBorder(String status) => status == 'pending'
      ? (AppColors.isDark
            ? const Color.fromRGBO(255, 152, 0, 0.15)
            : const Color(0xFFFFE0B2))
      : (AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.08)
            : AppColors.border);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final n = ref.read(appDataProvider.notifier);
    final mk = _key(s.selectedYear, _month);
    final cur = s.selectedCurrency;

    final monthPayments = s.scopedPayments
        .where(
          (p) => (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
              .startsWith(mk),
        )
        .toList();
    final monthExpenses = s.scopedExpenses
        .where(
          (e) => (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(mk),
        )
        .toList();

    // monthlySummary — ports OverviewScreen monthlySummary.
    double sumWhere(Iterable<Payment> ps, bool Function(Payment) f) =>
        ps.where(f).fold(0.0, (a, p) => a + p.amount);
    final income = sumWhere(monthPayments, (p) => p.status == 'paid');
    final spent = monthExpenses
        .where((e) => e.status == 'paid' || e.status.isEmpty)
        .fold<double>(0, (a, e) => a + e.amount);
    final net = income - spent;

    // Sort rent rows by tenant unit.
    final tenantById = {for (final t in s.scopedTenants) t.id: t};
    monthPayments.sort(
      (a, b) => _unitSort(
        tenantById[a.tenantId]?.unit ?? '',
        tenantById[b.tenantId]?.unit ?? '',
      ),
    );

    final notes = s.scopedMonthlyNotes.where((x) => x.month == mk).toList();
    final deposits = s.scopedBankDeposits
        .where((d) => d.depositDate.startsWith(mk))
        .toList();

    final isDark = AppColors.isDark;

    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopOverviewView(
        key: DesktopOverviewView.globalKey,
        onSelectTenant: (tenant) {
          TenantsView.showDetails(context, tenant);
        },
        onAddTenant: () {
          TenantsView.showEditModal(context);
        },
        onLogPayment: () {
          _paymentSheet(context, null, null);
        },
        onLogExpense: () {
          _expenseSheet(context, null);
        },
        onDeposit: () {
          _depositSheet(context, null, net);
        },
        onAddNote: (mk, existing) {
          _noteEditSheet(
            context,
            mk,
            ref.read(appDataProvider.notifier),
            existing,
          );
        },
        onDepositDetails: (deposit) {
          _depositDetails(context, deposit);
        },
        onEditDeposit: (deposit) {
          _depositSheet(context, deposit, net);
        },
        onPaymentDetails: (p, t) {
          _rentDetails(context, p, t);
        },
        onExpenseDetails: (e) {
          _expenseDetails(context, ref.read(appDataProvider), e);
        },
        onEditPayment: (p, t) {
          _paymentSheet(context, p, t);
        },
        onEditExpense: (e) {
          _expenseSheet(context, e);
        },
      );
    }

    return PopScope(
      canPop: !_fabOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fabOpen) {
          _fabKey.currentState?.collapse();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AppBackground(
            child: Stack(
              children: [
                Column(
                  children: [
                    _header(context, s),
                    Expanded(
                      child: GestureDetector(
                        // Horizontal swipe changes month — ports PanResponder swipe.
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v < -300) _stepMonth(1);
                          if (v > 300) _stepMonth(-1);
                        },
                        child: RefreshIndicator(
                          onRefresh: () async {
                            try {
                              await DriveBackupService.checkAndPullLatest(ref);
                            } catch (_) {}
                            await n.loadAll();
                          },
                          color: AppColors.primary,
                          backgroundColor: AppColors.isDark
                              ? const Color(0xFF0C2425)
                              : Colors.white,
                          strokeWidth: 2.4,
                          displacement: 46,
                          edgeOffset: 4,
                          semanticsLabel: 'Refresh data',
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 6),
                            children: [
                              _monthYearSelector(s),
                              _summaryRow(cur, income, spent, net),
                              RentExpenseTabs(
                                value: _tab,
                                onChanged: (t) {
                                  if (t == _tab) return;
                                  setState(() {
                                    _tab = t;
                                    _clearSelection();
                                  });
                                  _flashWave();
                                },
                              ),
                              if (_selecting) _selectionBar(),
                              if (_wave)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: WaveAnimation(
                                    count: 6,
                                    icon: Ionicons.barChart,
                                  ),
                                )
                              else if (_tab == 'rentRoll')
                                ..._rentTab(
                                  context,
                                  s,
                                  monthPayments,
                                  tenantById,
                                  cur,
                                )
                              else
                                ..._expenseTab(context, s, monthExpenses, cur),
                              _notesSection(context, mk, notes, n, s),
                              _bankSection(
                                context,
                                s,
                                deposits,
                                income,
                                spent,
                                net,
                                cur,
                                mk,
                              ),
                              const SizedBox(height: 90),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_fabOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _fabKey.currentState?.collapse(),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 200),
                        builder: (context, opacity, child) => Container(
                          color: Colors.black.withValues(
                            alpha: (isDark ? 0.6 : 0.35) * opacity,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: _FanFab(
            key: _fabKey,
            onOpenChanged: (isOpen) {
              if (_fabOpen != isOpen) {
                setState(() => _fabOpen = isOpen);
              }
            },
            onRent: () => _paymentSheet(context, null, null),
            onExpense: () => _expenseSheet(context, null),
            onNote: () => _noteEditSheet(context, mk, n, null),
            onDeposit: () => _depositSheet(context, null, net),
          ),
        ),
      ),
    );
  }

  // ---------- Header (settings only) ----------

  Widget _header(BuildContext context, AppDataState s) {
    final pm = s.propertyManager;
    final title =
        s.activeProperty?.name ??
        ((pm?.propertyName?.isNotEmpty ?? false)
            ? pm!.propertyName!
            : (pm?.name ?? 'Loading...'));
    final addr = s.activeProperty?.address.isNotEmpty ?? false
        ? s.activeProperty!.address
        : (pm?.address ?? '');
    final isDark = AppColors.isDark;
    final topPadding = MediaQuery.of(context).padding.top;

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
          // Left: Profile Avatar with subtle status dot
          SizedBox(
            width: 44,
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _profileDetails(context, s),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
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
                      child: AvatarView(
                        name: pm?.name ?? 'R',
                        uri: pm?.avatar,
                        radius: 19,
                        borderColor: isDark ? AppColors.primary : Colors.white,
                        borderWidth: 1.5,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.primary
                              : const Color(0xFF34D399),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0D2B2B)
                                : const Color(0xFF0F766E),
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

          // Center: Title + Info pill + Location (geometrically balanced)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _propertyInfo(context, s),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: isDark ? AppColors.primary : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (addr.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 12,
                          color: isDark
                              ? AppColors.primary
                              : const Color(0xFFA7F3D0),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            addr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.textSecondary
                                  : Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Right: Settings Action Button (balances Left 44px)
          SizedBox(
            width: 44,
            height: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.06)
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.1)
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onSettings,
                    child: Center(
                      child: Icon(
                        Icons.settings_outlined,
                        size: 20,
                        color: isDark ? AppColors.icon : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Month / Year selector ----------

  Widget _monthYearSelector(AppDataState s) {
    Widget arrow(IconData icon, VoidCallback onTap) => InkWell(
      onTap: _wave ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 15,
          color: _wave ? AppColors.iconMuted : AppColors.primary,
        ),
      ),
    );
    Widget display(String text, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 12,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.isDark ? null : AppColors.surface,
          gradient: AppColors.isDark
              ? const LinearGradient(
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.1),
                    Color.fromRGBO(255, 255, 255, 0.05),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  arrow(Icons.chevron_left, () => _stepMonth(-1)),
                  display(_monthLong[_month], () async {
                    final r = await _pickMonthYear(s.selectedYear, _month);
                    if (r != null) {
                      setState(() {
                        _month = r.$2;
                        ref.read(appDataProvider.notifier).setYear(r.$1);
                        _clearSelection();
                      });
                      _flashWave();
                    }
                  }),
                  arrow(Icons.chevron_right, () => _stepMonth(1)),
                ],
              ),
            ),
            Container(width: 1, height: 24, color: AppColors.border),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  arrow(Icons.chevron_left, () => _stepYear(-1)),
                  display('${s.selectedYear}', () async {
                    final r = await _pickMonthYear(s.selectedYear, _month);
                    if (r != null) {
                      setState(() {
                        _month = r.$2;
                        ref.read(appDataProvider.notifier).setYear(r.$1);
                        _clearSelection();
                      });
                      _flashWave();
                    }
                  }),
                  arrow(Icons.chevron_right, () => _stepYear(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Month + year picker dialog → (year, month).
  Future<(int, int)?> _pickMonthYear(int year, int month) {
    var tempYear = year;
    var tempMonth = month;
    var view = 'month';
    var navYear = year;
    return showAdaptiveModalSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final sw = MediaQuery.of(ctx).size.width;
          final monthW = (sw - 32 - 16) / 3;
          final yearW = (sw - 32 - 24) / 4;

          Widget cell(
            String label,
            bool selected,
            VoidCallback onTap,
            double width,
          ) => InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.text,
                ),
              ),
            ),
          );

          Widget toggle(String label, bool active, VoidCallback onTap) =>
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );

          return AppModalSheet(
            title: 'Select Month and Year',
            footer: SheetActions(
              primaryLabel: 'Confirm',
              onPrimary: () => Navigator.pop(ctx, (tempYear, tempMonth)),
            ),
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      toggle(
                        'Month',
                        view == 'month',
                        () => setS(() => view = 'month'),
                      ),
                      toggle(
                        'Year',
                        view == 'year',
                        () => setS(() => view = 'year'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (view == 'month')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var m = 1; m <= 12; m++)
                        cell(
                          _monthLong[m],
                          tempMonth == m,
                          () => setS(() => tempMonth = m),
                          monthW,
                        ),
                    ],
                  ),
                if (view == 'year') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setS(() => navYear--),
                        icon: Icon(Icons.chevron_left, color: AppColors.text),
                      ),
                      Text(
                        '$navYear',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setS(() => navYear++),
                        icon: Icon(Icons.chevron_right, color: AppColors.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = navYear - 10; i <= navYear + 10; i++)
                        cell('$i', tempYear == i, () {
                          setS(() {
                            tempYear = i;
                            navYear = i;
                          });
                        }, yearW),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Summary ----------

  Widget _summaryRow(String cur, double income, double spent, double net) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            SummaryCard(
              label: 'Income',
              value: fmtMoney(cur, income),
              color: AppColors.success,
              icon: Icons.trending_up,
            ),
            const SizedBox(width: 8),
            SummaryCard(
              label: 'Expenses',
              value: fmtMoney(cur, spent),
              color: AppColors.error,
              icon: Icons.trending_down,
            ),
            const SizedBox(width: 8),
            SummaryCard(
              label: 'Net',
              value: fmtMoney(cur, net),
              color: net >= 0 ? AppColors.success : AppColors.error,
              icon: Icons.account_balance_wallet,
            ),
          ],
        ),
      );

  // ---------- Selection bar ----------

  Widget _selectionBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.primary),
    ),
    child: Row(
      children: [
        Text(
          '${_selected.length} selected',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        const Spacer(),
        _selAction(
          Icons.done_all,
          'All',
          AppColors.success,
          () => setState(() {
            _selected.addAll(_visibleIds());
            _selecting = true;
          }),
        ),
        _selAction(
          Icons.close,
          'None',
          AppColors.error,
          () => setState(() => _selected.clear()),
        ),
        if (_selected.isNotEmpty)
          _selAction(Icons.delete, 'Delete', AppColors.error, _bulkDelete),
        _selAction(
          Icons.close,
          'Cancel',
          AppColors.textSecondary,
          () => setState(_clearSelection),
        ),
      ],
    ),
  );

  Widget _selAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Set<String> _visibleIds() {
    final s = ref.read(appDataProvider);
    final mk = _key(s.selectedYear, _month);
    if (_tab == 'rentRoll') {
      return s.scopedPayments
          .where(
            (p) => (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
                .startsWith(mk),
          )
          .map((p) => p.id)
          .toSet();
    }
    return s.scopedExpenses
        .where(
          (e) => (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(mk),
        )
        .map((e) => e.id)
        .toSet();
  }

  void _bulkDelete() async {
    final ok = await confirmDialog(
      context,
      'Delete ${_selected.length} items?',
      'This cannot be undone.',
    );
    if (!ok) return;
    final n = ref.read(appDataProvider.notifier);
    if (_tab == 'rentRoll') {
      n.deletePayments(_selected.toList());
    } else {
      n.deleteExpenses(_selected.toList());
    }
    setState(_clearSelection);
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  // ---------- Rent tab ----------

  List<Widget> _rentTab(
    BuildContext context,
    AppDataState s,
    List<Payment> rows,
    Map<String, Tenant> tenantById,
    String cur,
  ) {
    if (rows.isEmpty) {
      return [
        _emptyState(
          icon: Icons.description,
          title: 'No Rent Roll Data',
          subtext: 'Start by adding your first rent roll entry using the + button below',
          onSync: () => _syncSheet(context, 'rentRoll'),
        ),
      ];
    }
    final total = rows.fold<double>(0, (a, p) => a + p.amount);
    final paid = rows
        .where((p) => p.status == 'paid')
        .fold<double>(0, (a, p) => a + p.amount);

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          children: [
            ...rows.map(
              (p) => _rentRow(context, p, tenantById[p.tenantId], cur),
            ),
            _rentSummary(cur, total, paid),
          ],
        ),
      ),
    ];
  }

  Widget _rentRow(BuildContext context, Payment p, Tenant? t, String cur) {
    final sel = _selected.contains(p.id);
    final statusColor = _rentStatusColor(p.status);
    final unit = t?.unit ?? '';
    final isDark = AppColors.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            _selecting ? _toggleSelect(p.id) : _rentDetails(context, p, t),
        onLongPress: () {
          AppHaptics.medium();
          _rentLongPress(context, p, t);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? const Color.fromRGBO(76, 175, 80, 0.08)
                : _rentStatusBg(p.status),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel
                  ? const Color.fromRGBO(76, 175, 80, 0.2)
                  : _rentStatusBorder(p.status),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarView(
                      name: t?.name ?? '?',
                      uri: t?.avatar,
                      radius: 16,
                      borderColor: AppColors.primary,
                      borderWidth: 1,
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Icon(
                        _rentStatusIcon(p.status),
                        size: 12,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            t?.name ?? 'Unknown tenant',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(76, 175, 80, 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color.fromRGBO(76, 175, 80, 0.3),
                              ),
                            ),
                            child: Text(
                              unit,
                              style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((p.displayMonth ?? p.paidForMonth)?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 152, 0, 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color.fromRGBO(255, 152, 0, 0.3),
                            ),
                          ),
                          child: Text(
                            _short(p.displayMonth ?? p.paidForMonth),
                            style: const TextStyle(
                              color: Color(0xFFFF9800),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtMoney(cur, p.amount),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (p.paidDate?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 10,
                            color: Color(0xFF4CAF50),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fmtDate(p.paidDate!),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rentSummary(String cur, double total, double paid) {
    final isDark = AppColors.isDark;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(0, 0, 0, 0.15)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calculate_outlined,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Total Rent',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  fmtMoney(cur, total),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 20, color: AppColors.border),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Collected',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  fmtMoney(cur, paid),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expenseSummary(
    String cur,
    double total,
    double paid,
    double pending,
  ) {
    final isDark = AppColors.isDark;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(0, 0, 0, 0.15)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Total',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    fmtMoney(cur, total),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 20, color: AppColors.border),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Paid',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    fmtMoney(cur, paid),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (pending > 0) ...[
            Container(width: 1, height: 20, color: AppColors.border),
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 12,
                        color: Color(0xFFFF9800),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Pending',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      fmtMoney(cur, pending),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF9800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- Expense tab ----------

  List<Widget> _expenseTab(
    BuildContext context,
    AppDataState s,
    List<Expense> rows,
    String cur,
  ) {
    if (rows.isEmpty) {
      return [
        _emptyState(
          icon: Ionicons.card,
          title: 'No Expenses Data',
          subtext:
              'Start by adding your first expense using the + button below',
          onSync: () => _syncSheet(context, 'expenses'),
        ),
      ];
    }
    final total = rows.fold<double>(0, (a, e) => a + e.amount);
    final paid = rows
        .where((e) => e.status == 'paid' || e.status.isEmpty)
        .fold<double>(0, (a, e) => a + e.amount);
    final pending = rows
        .where((e) => e.status == 'pending')
        .fold<double>(0, (a, e) => a + e.amount);

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          children: [
            ...rows.map((e) => _expenseRow(context, s, e, cur)),
            _expenseSummary(cur, total, paid, pending),
          ],
        ),
      ),
    ];
  }

  Widget _expenseRow(
    BuildContext context,
    AppDataState s,
    Expense e,
    String cur,
  ) {
    final sel = _selected.contains(e.id);
    final catColor = _catColor(s, e.category);
    final hasReceipt =
        e.receipt?.isNotEmpty == true || e.receiptFiles.isNotEmpty;
    final paid = e.status == 'paid';
    final isDark = AppColors.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Dismissible(
        key: ValueKey('expense-${e.id}'),
        direction: _selecting
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Ionicons.trashOutline, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          AppHaptics.medium();
          return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: AppColors.isDark
                      ? const Color(0xFF061818)
                      : Colors.white,
                  title: const Text('Delete Expense?'),
                  content: Text(
                    'Delete "${e.description}" (${fmtMoney(cur, e.amount)}) permanently?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ) ??
              false;
        },
        onDismissed: (_) {
          AppHaptics.success();
          ref.read(appDataProvider.notifier).deleteExpense(e.id);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              _selecting ? _toggleSelect(e.id) : _expenseDetails(context, s, e),
          onLongPress: () {
            AppHaptics.medium();
            _expenseLongPress(context, e);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: sel
                  ? const Color.fromRGBO(76, 175, 80, 0.08)
                  : _expStatusBg(e.status),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel
                    ? const Color.fromRGBO(76, 175, 80, 0.2)
                    : _expStatusBorder(e.status),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.025),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            paid ? Icons.check_circle : Icons.schedule,
                            size: 12,
                            color: paid
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              e.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: catColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            e.category,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _contrast(catColor),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtMoney(cur, e.amount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 10,
                          color: Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fmtDate(e.date),
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (hasReceipt)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.receipt,
                              size: 12,
                              color: Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Receipt available',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF4CAF50),
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
          ),
        ),
      ),
    );
  }

  // ---------- Empty state ----------

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtext,
    required VoidCallback onSync,
  }) {
    final isDark = AppColors.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.03)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 107, 107, 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync, size: 16, color: Color(0xFF4CAF50)),
              label: const Text(
                'Preview & Sync',
                style: TextStyle(color: Color(0xFF4CAF50)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color.fromRGBO(76, 175, 80, 0.4)),
                backgroundColor: const Color.fromRGBO(76, 175, 80, 0.1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small coverage chip row: how many of the month's paid rent payments are
  /// linked to a bank deposit (confirmed only).
  Widget _depositPaymentLinkRow(
    AppDataState s,
    List<BankDeposit> deposits,
    String mk,
  ) {
    final linkedIds = deposits
        .where((d) => d.status.toLowerCase().trim() == 'confirmed')
        .expand((d) => d.linkedPaymentIds)
        .toSet();
    if (linkedIds.isEmpty) return const SizedBox.shrink();
    final monthPaidPayments = s.scopedPayments.where((p) {
      final pm = (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '');
      return pm.startsWith(mk) && p.status == 'paid';
    }).length;
    final linked = monthPaidPayments == 0
        ? 0
        : s.scopedPayments.where((p) {
            final pm = (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '');
            return pm.startsWith(mk) &&
                p.status == 'paid' &&
                linkedIds.contains(p.id);
          }).length;
    if (linked == 0) return const SizedBox.shrink();
    final done = linked >= monthPaidPayments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Tooltip(
        message: done
            ? 'Every paid rent payment this month is linked to a bank deposit'
            : 'Link rent payments to deposits from the deposit sheet for per-payment reconciliation',
        child: Row(
          children: [
            const Icon(
              Ionicons.linkOutline,
              size: 11,
              color: Color(0xFF3B82F6),
            ),
            const SizedBox(width: 4),
            Text(
              '$linked/$monthPaidPayments rent payments linked to deposits',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: done ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Notes checklist ----------

  Widget _notesSection(
    BuildContext context,
    String mk,
    List<MonthlyNote> notes,
    AppDataNotifier n,
    AppDataState s,
  ) {
    final isDark = AppColors.isDark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Ionicons.documentTextOutline,
                        size: 16,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Monthly Notes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          notes.isEmpty ? '0 notes' : '${notes.length} notes',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text(
                    'Add',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _noteEditSheet(context, mk, n, null),
                ),
              ],
            ),
          ),
          if (notes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? null : AppColors.cardBackground,
                gradient: isDark
                    ? const LinearGradient(
                        colors: [
                          Color.fromRGBO(255, 255, 255, 0.03),
                          Color.fromRGBO(255, 255, 255, 0.01),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Ionicons.documentTextOutline,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'No notes for this month',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                    onPressed: () => _noteEditSheet(context, mk, n, null),
                  ),
                ],
              ),
            )
          else
            ...notes.map((x) => _noteItem(x, n, s)),
        ],
      ),
    );
  }

  Widget _noteItem(MonthlyNote x, AppDataNotifier n, AppDataState s) {
    final isDark = AppColors.isDark;
    String? propName;
    if (s.isAllProperties && s.properties.isNotEmpty && x.propertyId != null) {
      final hit = s.properties.where((p) => p.id == x.propertyId).toList();
      if (hit.isNotEmpty) propName = hit.first.name;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => _noteEditSheet(context, x.month, n, x),
        onLongPress: () {
          AppHaptics.medium();
          _noteLongPress(context, x, n);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.03)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      x.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.text,
                      ),
                    ),
                    if (propName != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          propName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Ionicons.trashOutline, size: 14),
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Delete note',
                onPressed: () => _noteLongPress(context, x, n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _noteLongPress(
    BuildContext context,
    MonthlyNote x,
    AppDataNotifier n,
  ) async {
    final ok = await confirmDialog(
      context,
      'Delete Note',
      'Are you sure you want to delete this note?',
    );
    if (ok) n.deleteNote(x.id);
  }

  // ---------- Bank deposits ----------

  Widget _bankSection(
    BuildContext context,
    AppDataState s,
    List<BankDeposit> deposits,
    double rentCollected,
    double paidExpenses,
    double net,
    String cur,
    String mk,
  ) {
    final isDark = AppColors.isDark;
    final confirmedDeposits = deposits
        .where((d) => d.status.toLowerCase().trim() == 'confirmed')
        .toList();
    final pendingDeposits = deposits
        .where((d) => d.status.toLowerCase().trim() != 'confirmed')
        .toList();

    final confirmedTotal = confirmedDeposits.fold<double>(
      0.0,
      (a, d) => a + d.amount,
    );
    final pendingTotal = pendingDeposits.fold<double>(
      0.0,
      (a, d) => a + d.amount,
    );

    // Determine reconciliation state:
    final bool matchesGross =
        rentCollected > 0 && confirmedTotal >= rentCollected;
    final bool matchesNet =
        paidExpenses > 0 && confirmedTotal >= net && net > 0;
    final bool isReconciled = matchesGross || matchesNet;
    final double benchmark = (paidExpenses > 0 && net > 0)
        ? net
        : rentCollected;
    final String benchmarkLabel = (paidExpenses > 0 && net > 0)
        ? 'Net Cash'
        : 'Rent';
    final double diff = (benchmark - confirmedTotal).clamp(0, double.infinity);

    final Color badgeColor = isReconciled
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF9800);

    final String badgeText;
    final String tooltipMessage;
    if (rentCollected <= 0 && confirmedTotal <= 0 && pendingTotal <= 0) {
      badgeText = 'No rent';
      tooltipMessage = 'No rent collected yet for this month.';
    } else if (matchesGross) {
      badgeText = 'Reconciled (Gross)';
      tooltipMessage =
          'Bank deposits ($cur ${confirmedTotal.toStringAsFixed(0)}) match total rent collected ($cur ${rentCollected.toStringAsFixed(0)}).';
    } else if (matchesNet) {
      badgeText = 'Reconciled (Net Cash)';
      tooltipMessage =
          'Bank deposits ($cur ${confirmedTotal.toStringAsFixed(0)}) match Net Income ($cur ${net.toStringAsFixed(0)} = Rent $cur ${rentCollected.toStringAsFixed(0)} - Exp $cur ${paidExpenses.toStringAsFixed(0)}).';
    } else if ((confirmedTotal + pendingTotal) >= benchmark) {
      badgeText = 'Pending Conf.';
      tooltipMessage =
          'Pending deposits ($cur ${pendingTotal.toStringAsFixed(0)}) will reconcile $benchmarkLabel once marked as confirmed.';
    } else {
      badgeText = 'Unmatched: $cur ${diff.toStringAsFixed(0)}';
      tooltipMessage =
          '$cur ${diff.toStringAsFixed(0)} un-deposited $benchmarkLabel ($benchmarkLabel: $cur ${benchmark.toStringAsFixed(0)} - Confirmed: $cur ${confirmedTotal.toStringAsFixed(0)}).';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Ionicons.businessOutline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Bank Deposits',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Tooltip(
                          message: tooltipMessage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              badgeText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text(
                    'Add',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _depositSheet(context, null, net),
                ),
              ],
            ),
          ),
          if (paidExpenses > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                'Rent: $cur ${rentCollected.toStringAsFixed(0)}  •  Exp: $cur ${paidExpenses.toStringAsFixed(0)}  •  Net to Deposit: $cur ${net.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          _depositPaymentLinkRow(s, deposits, mk),
          if (deposits.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              decoration: BoxDecoration(
                color: isDark ? null : AppColors.cardBackground,
                gradient: isDark
                    ? const LinearGradient(
                        colors: [
                          Color.fromRGBO(255, 255, 255, 0.03),
                          Color.fromRGBO(255, 255, 255, 0.01),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Ionicons.businessOutline,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'No bank deposits recorded this month',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      'Add Deposit',
                      style: TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _depositSheet(context, null, net),
                  ),
                ],
              ),
            )
          else
            ...deposits.map((d) => _bankCard(context, s, d, net, cur)),
        ],
      ),
    );
  }

  IconData _depositStatusIcon(String status) {
    switch (status.toLowerCase().trim()) {
      case 'confirmed':
        return Icons.check_circle;
      case 'pending':
        return Icons.schedule;
      case 'failed':
        return Icons.cancel;
      default:
        return Icons.schedule;
    }
  }

  Color _depositStatusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'confirmed':
        return const Color(0xFF4CAF50);
      case 'pending':
        return const Color(0xFFFFC107);
      case 'failed':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFFFFC107);
    }
  }

  Widget _bankCard(
    BuildContext context,
    AppDataState s,
    BankDeposit d,
    double net,
    String cur,
  ) {
    final bank = s.banks.where((b) => b.id == d.bankId).toList();
    final acct = bank.isNotEmpty
        ? (bank.first.accountNumber ?? '****1234')
        : '****1234';
    final isDark = AppColors.isDark;
    String? propName;
    if (s.isAllProperties && s.properties.isNotEmpty && d.propertyId != null) {
      final hit = s.properties.where((p) => p.id == d.propertyId).toList();
      if (hit.isNotEmpty) propName = hit.first.name;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _depositDetails(context, d),
        onLongPress: () {
          AppHaptics.medium();
          _depositLongPress(context, d, net);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? null : AppColors.cardBackground,
            gradient: isDark
                ? const LinearGradient(
                    colors: [
                      Color.fromRGBO(255, 255, 255, 0.05),
                      Color.fromRGBO(255, 255, 255, 0.02),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (d.bankLogo?.isNotEmpty == true)
                    Image.network(
                      d.bankLogo!,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, _, _) => _bankLogoPlaceholder(),
                    )
                  else
                    _bankLogoPlaceholder(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                d.bankName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            if (propName != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  propName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                final isConf =
                                    d.status.toLowerCase().trim() ==
                                    'confirmed';
                                final newStatus = isConf
                                    ? 'pending'
                                    : 'confirmed';
                                final now = DateTime.now().toIso8601String();
                                final updated = d.copyWith(
                                  status: newStatus,
                                  updatedAt: now,
                                );
                                ref
                                    .read(appDataProvider.notifier)
                                    .upsertDeposit(updated);
                                showAppToast(
                                  context,
                                  newStatus == 'confirmed'
                                      ? 'Deposit marked as Confirmed'
                                      : 'Deposit marked as Pending',
                                  isSuccess: true,
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _depositStatusColor(d.status)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _depositStatusColor(d.status)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _depositStatusIcon(d.status),
                                      size: 11,
                                      color: _depositStatusColor(d.status),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      d.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: _depositStatusColor(d.status),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          acct,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtMoney(cur, d.amount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtDate(d.depositDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (d.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    d.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (d.receiptImage?.isNotEmpty == true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.receipt,
                    size: 16,
                    color: Color(0xFF4CAF50),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankLogoPlaceholder() => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: const Color.fromRGBO(76, 175, 80, 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Ionicons.business, size: 16, color: Color(0xFF4CAF50)),
  );

  // ---------- Profile / property dialogs ----------

  void _profileDetails(BuildContext context, AppDataState s) {
    final pm = s.propertyManager;
    if (pm == null) return;
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Profile Details',
        icon: Ionicons.personCircleOutline,
        iconColor: AppColors.primary,
        footer: SheetActions(
          cancelLabel: 'Close',
          primaryLabel: 'Edit Profile',
          primaryIcon: const Icon(
            Ionicons.createOutline,
            size: 18,
            color: Colors.white,
          ),
          onPrimary: () {
            Navigator.pop(ctx);
            _editProfileSheet(context);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: AvatarView(
                name: pm.name,
                uri: pm.avatar,
                radius: 36,
                borderColor: AppColors.primary,
                borderWidth: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _kv('Name', pm.name),
            if (pm.propertyName?.isNotEmpty == true)
              _kv('Property', pm.propertyName!),
            if (pm.ownerName?.isNotEmpty == true) _kv('Owner', pm.ownerName!),
            _kv('Phone', pm.phone),
            _kv('Email', pm.email),
            _kv('Address', pm.address),
          ],
        ),
      ),
    );
  }

  void _propertyInfo(BuildContext context, AppDataState s) {
    final pm = s.propertyManager;
    final active = s.scopedTenants.where((t) => t.status == 'active').length;
    final activeProp = s.activeProperty;
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: activeProp?.name ?? 'Property Information',
        icon: Ionicons.businessOutline,
        iconColor: AppColors.primary,
        footer: SheetActions(
          cancelLabel: 'Close',
          primaryLabel: 'Property Settings',
          primaryIcon: const Icon(
            Ionicons.businessOutline,
            size: 18,
            color: Colors.white,
          ),
          onPrimary: () {
            Navigator.pop(ctx);
            _propertyDetailsSheet(context);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: AvatarView(
                name: activeProp?.name ?? pm?.propertyName ?? pm?.name ?? '?',
                uri: pm?.avatar,
                radius: 36,
              ),
            ),
            const SizedBox(height: 16),
            _kv('Selected', activeProp?.name ?? '—'),
            if (activeProp != null) ...[
              _kv('Type', activeProp.propertyType.toUpperCase()),
              _kv(
                'Address',
                activeProp.address.isNotEmpty
                    ? activeProp.address
                    : (pm?.address ?? '—'),
              ),
              _kv('Total Units', '${activeProp.totalUnits}'),
            ] else ...[
              _kv('Owner', pm?.ownerName ?? pm?.name ?? '—'),
              _kv('Address', pm?.address ?? '—'),
            ],
            const Divider(height: 24),
            _kv(
              'Tenants (Active Scope)',
              '${s.scopedTenants.length} ($active active)',
            ),
            _kv('Work orders', '${s.scopedWorkOrders.length}'),
            _kv('Documents', '${s.scopedDocuments.length}'),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Switch Property',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Ionicons.addCircleOutline, size: 16),
                  label: const Text(
                    'Add Property',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (_) => const DesktopPropertyModal(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  '${p.address.isNotEmpty ? '${p.address} • ' : ''}${p.totalUnits} units',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Ionicons.createOutline,
                        size: 16,
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: 'Edit Profile',
            icon: Ionicons.personOutline,
            footer: SheetActions(
              primaryLabel: 'Save Changes',
              primaryIcon: const Icon(Ionicons.checkmark, size: 16),
              onPrimary: () {
                if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                  setS(() => error = 'Name and phone number are required');
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
                        name: name.text.isEmpty ? '' : name.text,
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
                    'Manager Profile',
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
          );
        },
      ),
    );
  }

  void _propertyDetailsSheet(BuildContext context) {
    final pm = ref.read(appDataProvider).propertyManager;
    final nameCtl = TextEditingController(text: pm?.propertyName ?? '');
    final ownerCtl = TextEditingController(text: pm?.ownerName ?? '');
    final addrCtl = TextEditingController(text: pm?.address ?? '');
    List<String> pics = [...(pm?.propertyPictures ?? [])];

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: 'Property Details',
            icon: Ionicons.businessOutline,
            size: SheetSize.standard,
            body: Column(
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
            footer: SheetActions(
              primaryLabel: 'Save Changes',
              primaryIcon: const Icon(Ionicons.checkmark, size: 16),
              onPrimary: () {
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
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            k,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(v, style: TextStyle(color: AppColors.text)),
        ),
      ],
    ),
  );

  // ---------- Long-press action sheets ----------

  void _rentLongPress(BuildContext context, Payment p, Tenant? t) {
    if (_selecting) {
      _toggleSelect(p.id);
      return;
    }
    final name = t?.name ?? 'Unknown tenant';
    showAdaptiveModalSheet(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Rent Options',
        subtitle: name,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Ionicons.checkmarkDoneOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Select Multiple',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selecting = true;
                  _selected.add(p.id);
                });
              },
            ),
            if (p.status != 'paid')
              ListTile(
                leading: const Icon(
                  Ionicons.checkmarkCircleOutline,
                  color: AppColors.success,
                ),
                title: const Text(
                  'Mark as Paid',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  AppHaptics.success();
                  ref.read(appDataProvider.notifier).markPayments([
                    p.id,
                  ], 'paid');
                },
              ),
            ListTile(
              leading: Icon(
                Ionicons.createOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _paymentSheet(context, p, t);
              },
            ),
            ListTile(
              leading: const Icon(
                Ionicons.trashOutline,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  'Delete Rent Record',
                  'Are you sure you want to delete the rent record for $name? This action cannot be undone.',
                );
                if (ok) {
                  ref.read(appDataProvider.notifier).deletePayment(p.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _expenseLongPress(BuildContext context, Expense e) {
    if (_selecting) {
      _toggleSelect(e.id);
      return;
    }
    final others = ['paid', 'pending'].where((x) => x != e.status);
    showAdaptiveModalSheet(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Expense Options',
        subtitle: e.description,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Ionicons.checkmarkDoneOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Select Multiple',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selecting = true;
                  _selected.add(e.id);
                });
              },
            ),
            for (final st in others)
              ListTile(
                leading: Icon(
                  st == 'paid'
                      ? Ionicons.checkmarkCircleOutline
                      : Ionicons.timeOutline,
                  color: st == 'paid' ? AppColors.success : AppColors.warning,
                ),
                title: Text(
                  'Mark as ${st[0].toUpperCase()}${st.substring(1)}',
                  style: TextStyle(
                    color: st == 'paid' ? AppColors.success : AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _markExpense(e, st);
                },
              ),
            ListTile(
              leading: Icon(
                Ionicons.createOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _expenseSheet(context, e);
              },
            ),
            ListTile(
              leading: const Icon(
                Ionicons.trashOutline,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  'Delete Expense',
                  'Are you sure you want to delete the expense "${e.description}"? This action cannot be undone.',
                );
                if (ok) {
                  ref.read(appDataProvider.notifier).deleteExpense(e.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _markExpense(Expense e, String status) {
    ref
        .read(appDataProvider.notifier)
        .upsertExpense(
          Expense(
            id: e.id,
            category: e.category,
            description: e.description,
            amount: e.amount,
            date: e.date,
            status: status,
            paidDate: status == 'paid'
                ? (e.paidDate ?? DateTime.now().toIso8601String())
                : e.paidDate,
            expenseForMonth: e.expenseForMonth,
            displayMonth: e.displayMonth,
            receipt: e.receipt,
            receiptFiles: e.receiptFiles,
          ),
        );
  }

  // ---------- Read-only detail sheets ----------

  String _formatMonthDisplay(String ym) {
    if (ym.length < 7) return ym;
    final y = int.tryParse(ym.substring(0, 4)) ?? 0;
    final m = int.tryParse(ym.substring(5, 7)) ?? 0;
    if (m < 1 || m > 12) return ym;
    return '${_monthLong[m]} $y';
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _detailCard(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
      boxShadow: AppColors.isDark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _detailSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4CAF50),
        letterSpacing: 0.2,
      ),
    ),
  );

  void _rentDetails(BuildContext context, Payment p, Tenant? t) {
    final s = ref.read(appDataProvider);
    final cur = s.selectedCurrency;
    final statusColor = _rentStatusColor(p.status);
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Rent Details',
        icon: Icons.credit_card,
        iconColor: AppColors.primary,
        size: SheetSize.expanded,
        footer: SheetActions(
          cancelLabel: '',
          leadingAction: Row(
            children: [
              SizedBox(
                height: 46,
                child: DangerButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      'Delete Rent Record',
                      'Are you sure you want to delete the rent record for ${t?.name ?? 'this tenant'}? This action cannot be undone.',
                    );
                    if (!ok) return;
                    ref.read(appDataProvider.notifier).deletePayment(p.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    DesktopRentReceiptModal.show(
                      context,
                      payment: p,
                      tenant: t,
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('Receipt'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          primaryLabel: 'Edit',
          primaryIcon: const Icon(Icons.edit, size: 16),
          primaryFlex: 1,
          onPrimary: () {
            Navigator.pop(ctx);
            _paymentSheet(context, p, t);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSectionTitle('Tenant Information'),
            _detailCard([
              Row(
                children: [
                  AvatarView(
                    name: t?.name ?? '?',
                    uri: t?.avatar,
                    radius: 28,
                    borderColor: AppColors.primary,
                    borderWidth: 1,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t?.name ?? 'Unknown tenant',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (t?.unit.isNotEmpty == true)
                          Text(
                            'Unit ${t!.unit}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (t?.phone.isNotEmpty == true)
                          Text(
                            t!.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (t?.email.isNotEmpty == true)
                          Text(
                            t!.email,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _detailCard([
                Row(
                  children: [
                    Text(
                      'Status:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      t?.status == 'active' ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: t?.status == 'active'
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF6B6B),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (t != null && t.joinDate.isNotEmpty)
                  _detailRow('Join Date:', fmtDate(t.joinDate)),
                if (t != null)
                  _detailRow('Rent Amount:', fmtMoney(cur, t.rentAmount)),
                if (t?.fathersName?.isNotEmpty == true)
                  _detailRow("Father's Name:", t!.fathersName!),
                if (t?.address?.isNotEmpty == true)
                  _detailRow('Address:', t!.address!),
                if (t?.idNumber?.isNotEmpty == true)
                  _detailRow('ID Number:', t!.idNumber!),
                if (t?.dateOfBirth?.isNotEmpty == true)
                  _detailRow('Date of Birth:', fmtDate(t!.dateOfBirth!)),
              ]),
              if (t?.gasMeterNumber?.isNotEmpty == true ||
                  t?.electricMeterNumber?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _detailCard([
                  const Text(
                    'Meter Information',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (t?.gasMeterNumber?.isNotEmpty == true)
                    _detailRow('Gas Meter:', t!.gasMeterNumber!),
                  if (t?.electricMeterNumber?.isNotEmpty == true)
                    _detailRow('Electric Meter:', t!.electricMeterNumber!),
                ]),
              ],
            ]),
            const SizedBox(height: 16),
            _detailSectionTitle('Payment Information'),
            _detailCard([
              _detailRow('Amount:', fmtMoney(cur, p.amount)),
              if (p.paidDate?.isNotEmpty == true)
                _detailRow('Payment Date:', fmtDate(p.paidDate!)),
              if (p.displayMonth?.isNotEmpty == true)
                _detailRow(
                  'Paid For Month:',
                  _formatMonthDisplay(p.displayMonth!),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Status:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _rentStatusIcon(p.status),
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      p.status.isEmpty
                          ? ''
                          : p.status[0].toUpperCase() + p.status.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (p.notes?.isNotEmpty == true)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notes:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.notes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  void _openImageFullscreen(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (c) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(c),
              child: Container(
                color: Colors.transparent,
                alignment: Alignment.center,
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(c),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in Gallery / External App'),
                onPressed: () => MediaFiles.open(path),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _expenseDetails(BuildContext context, AppDataState s, Expense e) {
    final cur = s.selectedCurrency;
    final catColor = _catColor(s, e.category);
    final statusColor = e.status == 'paid'
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF9800);
    // Separate actual file attachments from text reference codes
    final allReceiptFiles = <String>[];
    String? textReference;
    if (e.receipt != null && e.receipt!.trim().isNotEmpty) {
      final r = e.receipt!.trim();
      final isPath =
          r.startsWith('/') ||
          r.startsWith('file:') ||
          r.startsWith('http:') ||
          r.startsWith('https:') ||
          r.startsWith('content:') ||
          r.startsWith('@media:') ||
          RegExp(
            r'\.(jpe?g|png|webp|gif|bmp|heic|pdf|docx?)$',
            caseSensitive: false,
          ).hasMatch(r);
      if (isPath) {
        allReceiptFiles.add(r);
      } else {
        textReference = r;
      }
    }
    for (final f in e.receiptFiles) {
      final fTrim = f.trim();
      if (fTrim.isNotEmpty && !allReceiptFiles.contains(fTrim)) {
        allReceiptFiles.add(fTrim);
      }
    }
    final hasReceipt = textReference != null || allReceiptFiles.isNotEmpty;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Expense Details',
        icon: Icons.receipt_long,
        iconColor: AppColors.primary,
        size: SheetSize.expanded,
        footer: SheetActions(
          cancelLabel: '',
          leadingAction: Expanded(
            child: SizedBox(
              height: 46,
              child: DangerButton(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    'Delete Expense',
                    'Are you sure you want to delete the expense "${e.description}"? This action cannot be undone.',
                  );
                  if (!ok) return;
                  ref.read(appDataProvider.notifier).deleteExpense(e.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Delete'),
              ),
            ),
          ),
          primaryLabel: 'Edit',
          primaryIcon: const Icon(Icons.edit, size: 16),
          primaryFlex: 1,
          onPrimary: () {
            Navigator.pop(ctx);
            _expenseSheet(context, e);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSectionTitle('Basic Information'),
            _detailCard([
              _detailRow('Description:', e.description),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Category:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: catColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: _contrast(catColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Amount:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      fmtMoney(cur, e.amount),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _detailRow('Date:', fmtDate(e.date)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Status:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      e.status == 'paid' ? Icons.check_circle : Icons.schedule,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      e.status.isEmpty
                          ? ''
                          : e.status[0].toUpperCase() + e.status.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            if (hasReceipt) ...[
              const SizedBox(height: 16),
              _detailSectionTitle('Receipt & Attachments'),
              _detailCard([
                if (textReference != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.confirmation_number_outlined,
                          size: 18,
                          color: Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reference: $textReference',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (allReceiptFiles.isNotEmpty) ...[
                  if (textReference != null) const SizedBox(height: 4),
                  Text(
                    'Attached Receipts (${allReceiptFiles.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...allReceiptFiles.map((f) {
                    final isImage = RegExp(
                      r'\.(jpe?g|png|webp|gif|bmp|heic)$',
                      caseSensitive: false,
                    ).hasMatch(f);
                    final fileName = f.split('/').last;
                    if (isImage) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openImageFullscreen(context, f),
                              child: Container(
                                width: double.infinity,
                                height: 220,
                                decoration: BoxDecoration(
                                  color: AppColors.isDark
                                      ? const Color(0xFF031415)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.border,
                                    width: 1.2,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      File(f),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.broken_image,
                                                  size: 36,
                                                  color: AppColors.textMuted,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Unable to load receipt image',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                    ),
                                    Positioned(
                                      bottom: 10,
                                      right: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.72,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.zoom_in,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Tap to Zoom',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => MediaFiles.open(f),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.open_in_new,
                                          size: 13,
                                          color: AppColors.primary,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'External',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
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
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => MediaFiles.open(f),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.05)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(76, 175, 80, 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color.fromRGBO(
                                      76,
                                      175,
                                      80,
                                      0.3,
                                    ),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.insert_drive_file,
                                  size: 24,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap to open document',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: Color(0xFF4CAF50),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ]),
            ],
            const SizedBox(height: 16),
            _detailSectionTitle('Additional Details'),
            _detailCard([
              _detailBullet(
                Icons.calendar_today,
                'Expense Date: ${fmtDate(e.date)}',
              ),
              _detailBullet(
                Icons.credit_card,
                'Amount: ${fmtMoney(cur, e.amount)}',
              ),
              _detailBullet(Icons.local_offer, 'Category: ${e.category}'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _detailBullet(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF4CAF50)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  // ---------- Rent add/edit ----------

  void _paymentSheet(BuildContext context, Payment? p, Tenant? t) {
    final s = ref.read(appDataProvider);
    final activeTenants = s.scopedTenants
        .where((e) => e.status == 'active')
        .toList();
    final rawPool = activeTenants.isEmpty ? s.scopedTenants : activeTenants;
    final tenantPool = <Tenant>[];
    final seenTenantIds = <String>{};
    if (p != null) {
      final existingTenant = s.scopedTenants
          .where((e) => e.id == p.tenantId)
          .cast<Tenant?>()
          .firstOrNull;
      if (existingTenant != null && seenTenantIds.add(existingTenant.id)) {
        tenantPool.add(existingTenant);
      }
    }
    for (final e in rawPool) {
      if (e.id.isNotEmpty && seenTenantIds.add(e.id)) {
        tenantPool.add(e);
      }
    }
    String? tenantId =
        p?.tenantId ??
        (t?.id ?? (tenantPool.isEmpty ? null : tenantPool.first.id));
    final amount = TextEditingController(text: p != null ? '${p.amount}' : '');
    final notesCtl = TextEditingController(text: p?.notes ?? '');
    String status = p?.status ?? 'paid';
    DateTime paidDate = _parseDate(p?.paidDate);
    String? paidForMonth = p?.paidForMonth ?? _key(s.selectedYear, _month);
    String? displayMonth = p?.displayMonth ?? _key(s.selectedYear, _month);
    final errorN = ValueNotifier<String?>(null);
    // Multiple-add mode (ports RentRollAddModal "Multiple" mode).
    bool multi = false;
    final List<Payment> drafts = [];
    String draftLabel(Payment d) {
      final tn = tenantPool.where((x) => x.id == d.tenantId);
      final nm = tn.isEmpty ? 'Tenant' : tn.first.name;
      return '$nm • ${fmtMoney(s.selectedCurrency, d.amount)}';
    }

    Future<void> save() async {
      final amt = double.tryParse(amount.text) ?? -1;
      if (tenantId == null) {
        errorN.value = 'Please select a tenant.';
        return;
      }
      if (amt < 0.01 || amt > 999999.99) {
        errorN.value = 'Amount must be between 0.01 and 999,999.99.';
        return;
      }
      if (notesCtl.text.trim().length > 500) {
        errorN.value = 'Notes must be under 500 characters.';
        return;
      }
      ref
          .read(appDataProvider.notifier)
          .upsertPayment(
            Payment(
              id: p?.id ?? newId(),
              tenantId: tenantId!,
              amount: amt,
              status: status,
              paidDate: paidDate.toIso8601String(),
              paidForMonth: paidForMonth,
              displayMonth: displayMonth,
              notes: notesCtl.text.trim().isEmpty ? null : notesCtl.text.trim(),
            ),
          );
      if (context.mounted) Navigator.pop(context);
    }

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDark = AppColors.isDark;
          return AppModalSheet(
            title: p == null
                ? (multi ? 'Add Multiple Rent' : 'Add Rent')
                : 'Edit Rent',
            icon: Icons.payments_outlined,
            iconColor: AppColors.primary,
            headerTrailing: p == null
                ? _modeIconToggle(
                    multi: multi,
                    isDark: isDark,
                    onChanged: (m) => setS(() => multi = m),
                  )
                : null,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tenantPool.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppColors.accentDark,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No tenants available. Please add a tenant first.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tenant (active) *',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: tenantPool.any((e) => e.id == tenantId)
                              ? tenantId
                              : (tenantPool.isNotEmpty
                                    ? tenantPool.first.id
                                    : null),
                          dropdownColor: AppColors.dropdownBackground,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            hintText: 'Select tenant',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          items: tenantPool
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(
                                    '${e.name} • ${e.unit} • ${fmtMoney(s.selectedCurrency, e.rentAmount)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setS(() {
                              tenantId = v;
                              final picked = tenantPool.where((e) => e.id == v);
                              if (picked.isNotEmpty && amount.text.isEmpty) {
                                amount.text = '${picked.first.rentAmount}';
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                AppField(
                  label: 'Amount (${s.selectedCurrency}) *',
                  controller: amount,
                  keyboard: TextInputType.number,
                ),
                DateFieldRow(
                  label: 'Paid date',
                  value: paidDate,
                  onChanged: (d) => setS(() => paidDate = d),
                ),
                _ymRow(
                  'Paid for month',
                  paidForMonth,
                  (v) => setS(() => paidForMonth = v),
                ),
                _ymRow(
                  'Display month',
                  displayMonth,
                  (v) => setS(() => displayMonth = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            const [
                              'paid',
                              'pending',
                              'overdue',
                              'partial',
                            ].contains(status.toLowerCase())
                            ? status.toLowerCase()
                            : 'paid',
                        dropdownColor: AppColors.dropdownBackground,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: const ['paid', 'pending', 'overdue', 'partial']
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _rentStatusColor(e),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      e[0].toUpperCase() + e.substring(1),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setS(() => status = v ?? 'paid'),
                      ),
                    ],
                  ),
                ),
                AppField(
                  label: 'Notes (optional, max 500)',
                  controller: notesCtl,
                  maxLines: 2,
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: errorN,
                  builder: (_, err, _) => err == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            err,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                if (p?.notes?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Saved note: ${p!.notes}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (multi) ...[
                  if (drafts.isNotEmpty) ...[
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Entries to add (${drafts.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...drafts.map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _rentStatusColor(d.status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  draftLabel(d),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => setS(() => drafts.remove(d)),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add to List'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.2,
                        ),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: tenantId == null
                          ? null
                          : () {
                              final amt = double.tryParse(amount.text) ?? -1;
                              if (amt < 0.01 || amt > 999999.99) {
                                errorN.value = 'Amount must be between 0.01 and 999,999.99.';
                                return;
                              }
                              if (notesCtl.text.trim().length > 500) {
                                errorN.value =
                                    'Notes must be under 500 characters.';
                                return;
                              }
                              setS(() {
                                drafts.add(
                                  Payment(
                                    id: newId(),
                                    tenantId: tenantId!,
                                    amount: amt,
                                    status: status,
                                    paidDate: paidDate.toIso8601String(),
                                    paidForMonth: paidForMonth,
                                    displayMonth: displayMonth,
                                    notes: notesCtl.text.trim().isEmpty
                                        ? null
                                        : notesCtl.text.trim(),
                                  ),
                                );
                                amount.clear();
                                notesCtl.clear();
                                status = 'paid';
                                errorN.value = null;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
            footer: (!multi && p != null)
                ? SheetActions(
                    cancelLabel: '',
                    leadingAction: Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              'Delete payment?',
                              'This cannot be undone.',
                            );
                            if (!ok) return;
                            ref
                                .read(appDataProvider.notifier)
                                .deletePayment(p.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.error,
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.error,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: AppColors.error.withValues(
                              alpha: 0.06,
                            ),
                          ),
                        ),
                      ),
                    ),
                    primaryLabel: 'Update',
                    primaryIcon: const Icon(
                      Icons.check_circle_outline,
                      size: 19,
                    ),
                    primaryFlex: 2,
                    onPrimary: tenantId == null ? null : save,
                  )
                : multi
                ? SheetActions(
                    cancelLabel: 'Cancel',
                    primaryLabel: drafts.isEmpty
                        ? 'Save Entries (0)'
                        : 'Save ${drafts.length} ${drafts.length == 1 ? 'Entry' : 'Entries'}',
                    primaryIcon: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 19,
                    ),
                    onPrimary: drafts.isEmpty
                        ? null
                        : () {
                            final n = ref.read(appDataProvider.notifier);
                            for (final d in drafts) {
                              n.upsertPayment(d);
                            }
                            Navigator.pop(ctx);
                          },
                  )
                : SheetActions(
                    cancelLabel: 'Cancel',
                    primaryLabel: 'Save Payment',
                    primaryIcon: const Icon(
                      Icons.check_circle_outline,
                      size: 19,
                    ),
                    onPrimary: tenantId == null ? null : save,
                  ),
          );
        },
      ),
    );
  }

  Widget _modeIconToggle({
    required bool multi,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.06)
            : const Color(0xFFF0F5F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.1)
              : const Color(0xFFDFE6E6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeIconButton(
            icon: Icons.person_rounded,
            tooltip: 'Single rent',
            isSelected: !multi,
            isDark: isDark,
            onTap: () {
              if (multi) {
                HapticFeedback.selectionClick();
                onChanged(false);
              }
            },
          ),
          const SizedBox(width: 2),
          _modeIconButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'Multiple rent',
            isSelected: multi,
            isDark: isDark,
            onTap: () {
              if (!multi) {
                HapticFeedback.selectionClick();
                onChanged(true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _modeIconButton({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F766E), // Rich teal
                      Color(0xFF059669), // Vibrant emerald
                      Color(0xFF10B981), // Fresh lively jade
                    ],
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF059669)
                          .withValues(alpha: isDark ? 0.4 : 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? const Color(0xFFA0D8D8).withValues(alpha: 0.7)
                        : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ymRow(String label, String? value, ValueChanged<String> onPick) {
    final parts = (value ?? '').split('-');
    final y =
        int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? DateTime.now().year;
    final m =
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: m.clamp(1, 12),
                  dropdownColor: AppColors.dropdownBackground,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (var i = 1; i <= 12; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          _monthShort[i],
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      onPick('$y-${(v ?? m).toString().padLeft(2, '0')}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: y,
                  dropdownColor: AppColors.dropdownBackground,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (var yy = y - 3; yy <= y + 1; yy++)
                      DropdownMenuItem(
                        value: yy,
                        child: Text(
                          '$yy',
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      onPick('${v ?? y}-${m.toString().padLeft(2, '0')}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Expense add/edit ----------

  static const _catColors = [
    '#4CAF50',
    '#2196F3',
    '#FF6B6B',
    '#FFB74D',
    '#9C27B0',
    '#00BCD4',
    '#FF9800',
    '#795548',
  ];
  static const _catIcons = [
    'pricetag',
    'home',
    'build',
    'car',
    'cart',
    'medkit',
    'school',
    'gift',
  ];

  Color _parseColor(String hex) {
    try {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  /// Port of `CombinedManagementModal` — expense categories + quick
  /// descriptions, opened from the expense sheet header gear.
  void _manageSheet(BuildContext context) {
    final newCat = TextEditingController();
    final newDesc = TextEditingController();
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final s = ref.read(appDataProvider);
          final nn = ref.read(appDataProvider.notifier);
          return AppModalSheet(
            title: 'Manage Expense Data',
            icon: Icons.settings_outlined,
            iconColor: AppColors.primary,
            size: SheetSize.expanded,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expense Categories',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                ...s.expenseCategories.map(
                  (c) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.label, color: _parseColor(c.color)),
                    title: Text(c.name),
                    subtitle: Text(
                      '${c.suggestedDescriptions.length} suggestions',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _editCategory(context, c),
                        ),
                        if (!c.isDefault)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () => _deleteCategory(context, c),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newCat,
                        decoration: const InputDecoration(
                          hintText: 'New category name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GradientButton(
                      onPressed: () {
                        final name = newCat.text.trim();
                        if (name.isEmpty) return;
                        if (s.expenseCategories.any(
                          (c) =>
                              c.name.trim().toLowerCase() == name.toLowerCase(),
                        )) {
                          newCat.clear();
                          return;
                        }
                        final now = DateTime.now().toIso8601String();
                        nn.setExpenseCategories([
                          ...s.expenseCategories,
                          ExpenseCategory(
                            id: newId(),
                            name: name,
                            description: name,
                            color: '#4CAF50',
                            icon: 'pricetag',
                            createdAt: now,
                            updatedAt: now,
                          ),
                        ]);
                        newCat.clear();
                        setS(() {});
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  'Quick Descriptions',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                ...s.predefinedDescriptions.map(
                  (d) => Row(
                    children: [
                      Expanded(
                        child: Text(d, style: const TextStyle(fontSize: 13)),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.error,
                        ),
                        onPressed: () {
                          nn.setDescriptions(
                            s.predefinedDescriptions
                                .where((x) => x != d)
                                .toList(),
                          );
                          setS(() {});
                        },
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newDesc,
                        decoration: const InputDecoration(
                          hintText: 'Add quick description',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GradientButton(
                      onPressed: () {
                        final t = newDesc.text.trim();
                        if (t.isEmpty || s.predefinedDescriptions.contains(t)) {
                          return;
                        }
                        nn.setDescriptions([...s.predefinedDescriptions, t]);
                        newDesc.clear();
                        setS(() {});
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editCategory(BuildContext context, ExpenseCategory e) {
    final nameCtl = TextEditingController(text: e.name);
    final descCtl = TextEditingController(text: e.description);
    final sugCtl = TextEditingController();
    String color = e.color;
    String icon = e.icon;
    List<String> sugs = [...e.suggestedDescriptions];
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (dctx, setS) {
          return AppModalSheet(
            title: 'Edit Category',
            icon: Ionicons.pricetagOutline,
            iconColor: AppColors.primary,
            footer: SheetActions(
              primaryLabel: 'Save Changes',
              onPrimary: () {
                if (nameCtl.text.trim().isEmpty) return;
                final cur = ref.read(appDataProvider).expenseCategories;
                ref
                    .read(appDataProvider.notifier)
                    .setExpenseCategories(
                      cur
                          .map(
                            (x) => x.id == e.id
                                ? ExpenseCategory(
                                    id: x.id,
                                    name: nameCtl.text.trim(),
                                    description: descCtl.text.trim(),
                                    color: color,
                                    icon: icon,
                                    isDefault: x.isDefault,
                                    createdAt: x.createdAt,
                                    updatedAt: DateTime.now().toIso8601String(),
                                    suggestedDescriptions: sugs,
                                  )
                                : x,
                          )
                          .toList(),
                    );
                Navigator.pop(dctx);
              },
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: descCtl,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Color',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final cc in _catColors)
                      GestureDetector(
                        onTap: () => setS(() => color = cc),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _parseColor(cc),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == cc
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Icon (name)',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final ic in _catIcons)
                      ChoiceChip(
                        label: Text(ic, style: const TextStyle(fontSize: 11)),
                        selected: icon == ic,
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setS(() => icon = ic),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Suggested descriptions',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ...sugs.map(
                  (sg) => Row(
                    children: [
                      Expanded(
                        child: Text(sg, style: const TextStyle(fontSize: 13)),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.error,
                        ),
                        onPressed: () => setS(() => sugs.remove(sg)),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sugCtl,
                        decoration: const InputDecoration(
                          hintText: 'Add suggestion',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      onPressed: () {
                        if (sugCtl.text.trim().isEmpty) {
                          return;
                        }
                        setS(() => sugs.add(sugCtl.text.trim()));
                        sugCtl.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _deleteCategory(BuildContext context, ExpenseCategory e) {
    final used = ref
        .read(appDataProvider)
        .expenses
        .any((x) => x.category == e.name);
    if (used) {
      showAppToast(
        context,
        '“${e.name}” is used by expenses and cannot be deleted.',
        isError: true,
      );
      return;
    }
    final cur = ref.read(appDataProvider).expenseCategories;
    ref
        .read(appDataProvider.notifier)
        .setExpenseCategories(cur.where((x) => x.id != e.id).toList());
  }

  void _expenseSheet(BuildContext context, Expense? e) {
    final s = ref.read(appDataProvider);
    final desc = TextEditingController(text: e?.description ?? '');
    final amount = TextEditingController(text: e != null ? '${e.amount}' : '');
    String cat =
        e?.category ??
        (s.expenseCategories.isEmpty
            ? 'Other'
            : s.expenseCategories.first.name);
    DateTime expDate = _parseDate(e?.date);
    String? expenseForMonth =
        e?.expenseForMonth ?? _key(s.selectedYear, _month);
    String? displayMonth = e?.displayMonth ?? _key(s.selectedYear, _month);
    String status = (e?.status != null && e!.status.trim().isNotEmpty)
        ? e.status.trim().toLowerCase()
        : 'paid';
    if (status != 'pending') status = 'paid';
    List<String> files = [...(e?.receiptFiles ?? [])];
    if (e?.receipt?.isNotEmpty == true && !files.contains(e!.receipt)) {
      files.add(e.receipt!);
    }
    String? error;
    bool multi = false;
    final List<Expense> drafts = [];
    String draftLabel(Expense d) =>
        '${d.category} • ${d.description} • ${fmtMoney(s.selectedCurrency, d.amount)}${d.status == 'pending' ? ' • Pending' : ''}';
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheetBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final distinctCategories = <ExpenseCategory>[];
          final seenCatNames = <String>{};
          for (final c in s.expenseCategories) {
            final nameTrimmed = c.name.trim();
            if (nameTrimmed.isNotEmpty &&
                seenCatNames.add(nameTrimmed.toLowerCase())) {
              distinctCategories.add(c);
            }
          }
          if (distinctCategories.isEmpty) {
            distinctCategories.add(
              ExpenseCategory(
                id: 'x',
                name: 'Other',
                description: '',
                color: '#4CAF50',
                icon: 'pricetag',
                createdAt: '',
                updatedAt: '',
              ),
            );
          }
          final catTrimmed = cat.trim();
          final matchingCat = distinctCategories.firstWhere(
            (c) => c.name.trim().toLowerCase() == catTrimmed.toLowerCase(),
            orElse: () {
              if (catTrimmed.isNotEmpty) {
                final extra = ExpenseCategory(
                  id: 'extra_${catTrimmed.toLowerCase()}',
                  name: catTrimmed,
                  description: '',
                  color: '#4CAF50',
                  icon: 'pricetag',
                  createdAt: '',
                  updatedAt: '',
                );
                distinctCategories.insert(0, extra);
                return extra;
              }
              return distinctCategories.first;
            },
          );
          if (cat != matchingCat.name) {
            cat = matchingCat.name;
          }

          final catHit = distinctCategories.where((c) => c.name == cat);
          final scoped = <String>{
            ...catHit.expand((c) => c.suggestedDescriptions),
            ...s.predefinedDescriptions,
          }.take(8).toList();
          Future<void> save() async {
            final amt = double.tryParse(amount.text) ?? -1;
            if (desc.text.trim().length < 3) {
              setS(() => error = 'Description needs at least 3 characters.');
              return;
            }
            if (amt < 0.01 || amt > 999999.99) {
              setS(() => error = 'Amount must be between 0.01 and 999,999.99.');
              return;
            }
            final mk = _key(ref.read(appDataProvider).selectedYear, _month);
            ref
                .read(appDataProvider.notifier)
                .upsertExpense(
                  Expense(
                    id: e?.id ?? newId(),
                    category: cat,
                    description: desc.text.trim(),
                    amount: amt,
                    date: expDate.toIso8601String(),
                    status: status,
                    paidDate: status == 'paid'
                        ? (e?.paidDate ?? expDate.toIso8601String())
                        : null,
                    expenseForMonth: expenseForMonth ?? mk,
                    displayMonth: displayMonth ?? mk,
                    receipt: files.isEmpty ? null : files.first,
                    receiptFiles: files,
                  ),
                );
            if (context.mounted) Navigator.pop(context);
          }

          return AppModalSheet(
            icon: Icons.receipt_long_outlined,
            iconColor: AppColors.primary,
            title: e == null
                ? (multi ? 'Add Multiple Expenses' : 'Add Expense')
                : 'Edit Expense',
            headerTrailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (e == null) ...[
                  _modeIconToggle(
                    multi: multi,
                    isDark:
                        Theme.of(ctx).brightness == Brightness.dark ||
                        AppColors.isDark,
                    onChanged: (m) => setS(() => multi = m),
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: () => _manageSheet(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color:
                          (Theme.of(ctx).brightness == Brightness.dark ||
                              AppColors.isDark)
                          ? const Color.fromRGBO(255, 255, 255, 0.06)
                          : const Color(0xFFF0F5F3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            (Theme.of(ctx).brightness == Brightness.dark ||
                                AppColors.isDark)
                            ? const Color.fromRGBO(255, 255, 255, 0.1)
                            : const Color(0xFFDFE6E6),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Ionicons.settings,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            size: SheetSize.standard,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category *',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: cat,
                        dropdownColor: AppColors.dropdownBackground,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: 'Select category',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: distinctCategories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.name,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _parseColor(c.color),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      c.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setS(() => cat = v ?? cat),
                      ),
                    ],
                  ),
                ),
                AppField(
                  label: 'Description *',
                  controller: desc,
                  hint: scoped.isEmpty ? 'Description' : scoped.first,
                ),
                if (scoped.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final sug in scoped)
                        ActionChip(
                          label: Text(
                            sug,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: AppColors.border),
                          onPressed: () => setS(() => desc.text = sug),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                AppField(
                  label: 'Amount (${s.selectedCurrency}) *',
                  controller: amount,
                  keyboard: TextInputType.number,
                ),
                DateFieldRow(
                  label: 'Date',
                  value: expDate,
                  onChanged: (d) => setS(() => expDate = d),
                ),
                _ymRow(
                  'Expense for month',
                  expenseForMonth,
                  (v) => setS(() => expenseForMonth = v),
                ),
                _ymRow(
                  'Display month',
                  displayMonth,
                  (v) => setS(() => displayMonth = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        dropdownColor: AppColors.dropdownBackground,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: const ['paid', 'pending']
                            .map(
                              (st) => DropdownMenuItem(
                                value: st,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: st == 'paid'
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFFFF9800),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      st[0].toUpperCase() + st.substring(1),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setS(() => status = v ?? status),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receipts',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (files.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'No receipts attached.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ...files.map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.attach_file,
                                  size: 16,
                                  color: AppColors.iconSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    f.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 16),
                                  onPressed: () => MediaFiles.open(f),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppColors.error,
                                  ),
                                  onPressed: () => setS(() => files.remove(f)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add receipt'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () async {
                            final doc = await MediaPicker.pickDocument(ctx);
                            if (doc != null) {
                              setS(() => files.add(doc.path));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (multi) ...[
                  if (drafts.isNotEmpty) ...[
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Entries to add (${drafts.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...drafts.map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  draftLabel(d),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => setS(() => drafts.remove(d)),
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add to List'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.2,
                        ),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        final amt = double.tryParse(amount.text) ?? -1;
                        if (desc.text.trim().length < 3) {
                          setS(
                            () => error =
                                'Description needs at least 3 characters.',
                          );
                          return;
                        }
                        if (amt < 0.01 || amt > 999999.99) {
                          setS(
                            () => error =
                                'Amount must be between 0.01 and 999,999.99.',
                          );
                          return;
                        }
                        final mk = _key(s.selectedYear, _month);
                        setS(() {
                          drafts.add(
                            Expense(
                              id: newId(),
                              category: cat,
                              description: desc.text.trim(),
                              amount: amt,
                              date: expDate.toIso8601String(),
                              status: status,
                              paidDate: status == 'paid'
                                  ? expDate.toIso8601String()
                                  : null,
                              expenseForMonth: expenseForMonth ?? mk,
                              displayMonth: displayMonth ?? mk,
                              receipt: files.isEmpty ? null : files.first,
                              receiptFiles: [...files],
                            ),
                          );
                          desc.clear();
                          amount.clear();
                          files = [];
                          error = null;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
            footer: multi
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: GradientButton(
                          onPressed: drafts.isEmpty
                              ? null
                              : () {
                                  final n = ref.read(appDataProvider.notifier);
                                  for (final d in drafts) {
                                    n.upsertExpense(d);
                                  }
                                  Navigator.pop(ctx);
                                },
                          child: Text(
                            drafts.isEmpty
                                ? 'No entries added'
                                : 'Save ${drafts.length} ${drafts.length == 1 ? "Entry" : "Entries"}',
                          ),
                        ),
                      ),
                    ],
                  )
                : SheetActions(
                    primaryLabel: e == null ? 'Save Expense' : 'Update',
                    primaryIcon: const Icon(
                      Icons.check_circle_outline,
                      size: 19,
                    ),
                    onPrimary: save,
                    leadingAction: (e != null)
                        ? SizedBox(
                            height: 46,
                            child: DangerButton(
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  'Delete expense?',
                                  'This cannot be undone.',
                                );
                                if (!ok) return;
                                ref
                                    .read(appDataProvider.notifier)
                                    .deleteExpense(e.id);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
          );
        },
      ),
    );
  }

  // ---------- Quick notes (one free-text note card per entry) ----------

  void _noteEditSheet(
    BuildContext context,
    String mk,
    AppDataNotifier n,
    MonthlyNote? x,
  ) {
    final s = ref.read(appDataProvider);
    final targetPropId = s.selectedPropertyId == 'all'
        ? (s.activeProperty?.id ?? 'prop-default')
        : s.selectedPropertyId;
    final parts = mk.split('-');
    final monthLabel =
        '${_monthLong[int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0]} ${parts.isNotEmpty ? parts[0] : ''}';
    final propName = s.activeProperty?.name ?? 'Default Property';
    final c = TextEditingController(text: x?.text ?? '');
    final isNew = x == null;
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final valid = c.text.trim().isNotEmpty;
          return AppModalSheet(
            title: isNew ? 'Add Note' : 'Edit Note',
            subtitle: 'Property: $propName • $monthLabel',
            icon: Ionicons.documentText,
            iconColor: AppColors.success,
            footer: SheetActions(
              primaryLabel: isNew ? 'Save Note' : 'Update',
              primaryIcon: const Icon(
                Icons.save_outlined,
                size: 19,
                color: Colors.white,
              ),
              onPrimary: valid == false
                  ? null
                  : () {
                      if (isNew) {
                        n.addNote(
                          MonthlyNote(
                            id: newId(),
                            text: c.text.trim(),
                            month: mk,
                            propertyId: targetPropId,
                          ),
                        );
                      } else {
                        n.updateNoteText(x.id, c.text.trim());
                      }
                      Navigator.pop(ctx);
                    },
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  autofocus: true,
                  maxLines: 8,
                  minLines: 4,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Write anything — tenant issues, reminders, income ideas...',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Free-form note for ${monthLabel.trim()}. Tap a note card to edit, long-press to delete.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Bank deposit add/edit/details ----------

  void _depositSheet(BuildContext context, BankDeposit? d, double netHint) {
    final s = ref.read(appDataProvider);
    final amount = TextEditingController(
      text: d == null || d.amount == 0 ? '' : d.amount.toString(),
    );
    final refNo = TextEditingController(text: d?.referenceNumber ?? '');
    final notesCtl = TextEditingController(text: d?.notes ?? '');
    String? bankId =
        d?.bankId ??
        (s.banks.any((b) => b.isDefault)
            ? s.banks.firstWhere((b) => b.isDefault).id
            : (s.banks.isEmpty ? null : s.banks.first.id));
    var banks = s.banks;
    String bankName =
        d?.bankName ??
        (bankId == null
            ? ''
            : s.banks
                  .firstWhere(
                    (b) => b.id == bankId,
                    orElse: () => s.banks.first,
                  )
                  .name);
    String status = d?.status ?? 'pending';
    String? propId =
        d?.propertyId ??
        (s.selectedPropertyId == 'all'
            ? (s.activeProperty?.id ??
                  (s.properties.isNotEmpty
                      ? s.properties.first.id
                      : 'prop-default'))
            : s.selectedPropertyId);
    DateTime depDate = _parseDate(d?.depositDate);
    String? receipt = d?.receiptImage;
    String? error;
    final depMk = '${depDate.year}-${depDate.month.toString().padLeft(2, '0')}';
    final tenantById = {for (final t in s.scopedTenants) t.id: t};
    final monthPayments = s.scopedPayments.where((p) {
      final pm = (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '');
      return pm.startsWith(depMk) && p.status != 'archived';
    }).toList()..sort((a, b) => (b.paidDate ?? '').compareTo(a.paidDate ?? ''));
    final selectedPayments = <String>{...(d?.linkedPaymentIds ?? const [])};
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: d == null ? 'Add Monthly Deposit' : 'Edit Bank Deposit',
            subtitle: 'Month net: ${fmtMoney(s.selectedCurrency, netHint)}',
            icon: Icons.account_balance_outlined,
            iconColor: AppColors.primary,
            size: SheetSize.expanded,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.properties.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Property *',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue:
                              (propId != null &&
                                  s.properties.any((p) => p.id == propId))
                              ? propId
                              : s.properties.first.id,
                          dropdownColor: AppColors.dropdownBackground,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          items: s.properties
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setS(() => propId = v),
                        ),
                      ],
                    ),
                  ),
                if (banks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bank *',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final distinctBanks = <BankInfo>[];
                            final seenBankIds = <String>{};
                            for (final b in banks) {
                              if (b.id.isNotEmpty && seenBankIds.add(b.id)) {
                                distinctBanks.add(b);
                              }
                            }
                            final safeBankId =
                                (bankId != null && seenBankIds.contains(bankId))
                                ? bankId
                                : (distinctBanks.isNotEmpty
                                      ? distinctBanks.first.id
                                      : null);

                            return DropdownButtonFormField<String>(
                              initialValue: safeBankId,
                              dropdownColor: AppColors.dropdownBackground,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                hintText: 'Select bank',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                              ),
                              items: distinctBanks
                                  .map(
                                    (b) => DropdownMenuItem(
                                      value: b.id,
                                      child: Text(
                                        '${b.name}${b.accountNumber?.isNotEmpty == true ? ' • ${b.accountNumber!}' : ''}${b.isDefault ? ' (default)' : ''}',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setS(() {
                                bankId = v;
                                final hit = distinctBanks.where(
                                  (b) => b.id == v,
                                );
                                if (hit.isNotEmpty) bankName = hit.first.name;
                              }),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                else
                  AppField(
                    label: 'Bank name *',
                    controller: TextEditingController(text: bankName),
                    hint: 'Add banks in Settings',
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.account_balance, size: 16),
                    label: const Text('Manage banks'),
                    onPressed: () async {
                      final r = await showBankSetupSheet(ctx, initial: banks);
                      if (r == null) return;
                      ref.read(appDataProvider.notifier).setBanks(r);
                      banks = r;
                      if (bankId == null || !banks.any((b) => b.id == bankId)) {
                        bankId = banks.any((b) => b.isDefault)
                            ? banks.firstWhere((b) => b.isDefault).id
                            : (banks.isEmpty ? null : banks.first.id);
                      }
                      if (bankId != null) {
                        final hit = banks.where((b) => b.id == bankId);
                        if (hit.isNotEmpty) bankName = hit.first.name;
                      }
                      setS(() {});
                    },
                  ),
                ),
                AppField(
                  label: 'Amount (${s.selectedCurrency}) *',
                  controller: amount,
                  keyboard: TextInputType.number,
                ),
                AppField(label: 'Reference number', controller: refNo),
                AppField(
                  label: 'Notes (optional)',
                  controller: notesCtl,
                  maxLines: 2,
                ),
                DateFieldRow(
                  label: 'Deposit date',
                  value: depDate,
                  onChanged: (v) => setS(() => depDate = v),
                ),
                AttachmentRow(
                  label: 'Receipt image (optional)',
                  path: receipt,
                  onPick: () async {
                    final p = await MediaPicker.pickImage(ctx);
                    if (p != null) setS(() => receipt = p);
                  },
                  onClear: () => setS(() => receipt = null),
                ),
                if (monthPayments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Ionicons.linkOutline,
                                size: 13,
                                color: Color(0xFF3B82F6),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Link rent payments (${selectedPayments.length} selected)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                              const Spacer(),
                              if (selectedPayments.isNotEmpty)
                                InkWell(
                                  onTap: () =>
                                      setS(() => selectedPayments.clear()),
                                  child: Text(
                                    'Clear',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select paid rent payments this deposit covers — enables per-payment reconciliation.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final p in monthPayments)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(7),
                                      onTap: () => setS(() {
                                        selectedPayments.contains(p.id)
                                            ? selectedPayments.remove(p.id)
                                            : selectedPayments.add(p.id);
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 5,
                                          horizontal: 2,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              selectedPayments.contains(p.id)
                                                  ? Icons.check_box
                                                  : Icons
                                                        .check_box_outline_blank,
                                              size: 17,
                                              color:
                                                  selectedPayments.contains(
                                                    p.id,
                                                  )
                                                  ? const Color(0xFF059669)
                                                  : AppColors.textSecondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${tenantById[p.tenantId]?.name ?? 'Tenant'}'
                                                '${(tenantById[p.tenantId]?.unit ?? '').trim().isNotEmpty ? ' • ${tenantById[p.tenantId]?.unit.trim()}' : ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${s.selectedCurrency} ${p.amount.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF10B981),
                                              ),
                                            ),
                                          ],
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
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            const [
                              'pending',
                              'confirmed',
                              'failed',
                            ].contains(status.toLowerCase())
                            ? status.toLowerCase()
                            : 'pending',
                        dropdownColor: AppColors.dropdownBackground,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                        items: const ['pending', 'confirmed', 'failed'].map((
                          e,
                        ) {
                          final color = e == 'confirmed'
                              ? const Color(0xFF4CAF50)
                              : (e == 'pending'
                                    ? const Color(0xFFFF9800)
                                    : const Color(0xFFFF6B6B));
                          return DropdownMenuItem(
                            value: e,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  e[0].toUpperCase() + e.substring(1),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setS(() => status = v ?? 'pending'),
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
            footer: SheetActions(
              primaryLabel: d == null ? 'Save Deposit' : 'Update',
              primaryIcon: const Icon(
                Icons.check_circle_outline,
                size: 19,
                color: Colors.white,
              ),
              onPrimary: () {
                if (depDate.isAfter(
                  DateTime.now().add(const Duration(days: 1)),
                )) {
                  setS(() => error = 'Deposit date cannot be in the future.');
                  return;
                }
                final resolvedBank = bankId == null
                    ? null
                    : banks.where((b) => b.id == bankId);
                final depositId = d?.id ?? newId();
                final normalizedStatus = status.toLowerCase().trim();
                ref
                    .read(appDataProvider.notifier)
                    .upsertDeposit(
                      BankDeposit(
                        id: depositId,
                        bankId: bankId ?? newId(),
                        bankName: resolvedBank?.isNotEmpty == true
                            ? resolvedBank!.first.name
                            : bankName,
                        bankLogo: resolvedBank?.isNotEmpty == true
                            ? resolvedBank!.first.logo
                            : d?.bankLogo,
                        amount: double.tryParse(amount.text.trim()) ?? 0.0,
                        depositDate: depDate.toIso8601String(),
                        description:
                            'Deposit to ${resolvedBank?.isNotEmpty == true ? resolvedBank!.first.name : bankName}',
                        status: normalizedStatus,
                        referenceNumber: refNo.text.trim(),
                        receiptImage: receipt,
                        notes: notesCtl.text.trim().isEmpty
                            ? null
                            : notesCtl.text.trim(),
                        updatedAt: DateTime.now().toIso8601String(),
                        propertyId: propId,
                        linkedPaymentIds: selectedPayments.toList(),
                      ),
                    );
                Navigator.pop(ctx);
              },
            ),
          );
        },
      ),
    );
  }

  void _depositDetails(BuildContext context, BankDeposit d) {
    final s = ref.read(appDataProvider);
    final bank = s.banks.where((b) => b.id == d.bankId).toList();
    final cur = s.selectedCurrency;
    final isConfirmed = d.status.toLowerCase().trim() == 'confirmed';
    final statusColor = isConfirmed
        ? const Color(0xFF10B981)
        : (d.status.toLowerCase().trim() == 'pending'
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444));
    final hasReceipt = d.receiptImage?.isNotEmpty == true;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Bank Deposit Details',
        icon: Icons.account_balance,
        iconColor: AppColors.primary,
        size: SheetSize.standard,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSectionTitle('Bank Information'),
            _detailCard([
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      color: Color(0xFF3B82F6),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.bankName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (bank.isNotEmpty &&
                            bank.first.accountNumber?.isNotEmpty == true)
                          Text(
                            'Acc: ${bank.first.accountNumber!}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final newStatus = isConfirmed ? 'pending' : 'confirmed';
                      final updated = d.copyWith(
                        status: newStatus,
                        updatedAt: DateTime.now().toIso8601String(),
                      );
                      ref.read(appDataProvider.notifier).upsertDeposit(updated);
                      Navigator.pop(ctx);
                      _depositDetails(context, updated);
                    },
                    child: StatusBadge(d.status),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            _detailSectionTitle('Deposit Details'),
            _detailCard([
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Amount:',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    AmountText(
                      fmtMoney(cur, d.amount),
                      size: 16,
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
              ),
              _detailRow('Date:', fmtDate(d.depositDate)),
              if (d.referenceNumber?.isNotEmpty == true)
                _detailRow('Reference:', d.referenceNumber!),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Status (Tap to toggle):',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        final newStatus = isConfirmed ? 'pending' : 'confirmed';
                        final updated = d.copyWith(
                          status: newStatus,
                          updatedAt: DateTime.now().toIso8601String(),
                        );
                        ref
                            .read(appDataProvider.notifier)
                            .upsertDeposit(updated);
                        Navigator.pop(ctx);
                        _depositDetails(context, updated);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isConfirmed
                                  ? Icons.check_circle
                                  : Icons.hourglass_top_rounded,
                              size: 11,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              d.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (d.description.isNotEmpty)
                _detailRow('Description:', d.description),
              if (d.notes?.isNotEmpty == true) _detailRow('Notes:', d.notes!),
            ]),
            if (hasReceipt) ...[
              const SizedBox(height: 16),
              _detailSectionTitle('Receipt'),
              _detailCard([
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('View Attached Receipt'),
                    onPressed: () => MediaFiles.open(d.receiptImage!),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),
          ],
        ),
        footer: SheetActions(
          primaryLabel: 'Edit',
          primaryIcon: const Icon(
            Icons.edit_outlined,
            size: 18,
            color: Colors.white,
          ),
          onPrimary: () {
            Navigator.pop(ctx);
            _depositSheet(context, d, 0);
          },
          cancelLabel: '',
          primaryFlex: 1,
          leadingAction: Expanded(
            child: SizedBox(
              height: 46,
              child: DangerButton(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    'Delete deposit?',
                    'This cannot be undone.',
                  );
                  if (!ok) return;
                  ref.read(appDataProvider.notifier).deleteDeposit(d.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Delete',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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

  void _depositLongPress(BuildContext context, BankDeposit d, double net) {
    final isConfirmed = d.status.toLowerCase().trim() == 'confirmed';
    showAdaptiveModalSheet(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Deposit Actions',
        icon: Icons.account_balance,
        iconColor: AppColors.primary,
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          children: [
            ListTile(
              leading: Icon(
                isConfirmed
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_outline,
                color: isConfirmed
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
              ),
              title: Text(
                isConfirmed ? 'Mark as Pending' : 'Mark as Confirmed',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(ctx);
                final updated = d.copyWith(
                  status: isConfirmed ? 'pending' : 'confirmed',
                  updatedAt: DateTime.now().toIso8601String(),
                );
                ref.read(appDataProvider.notifier).upsertDeposit(updated);
                showAppToast(
                  context,
                  !isConfirmed
                      ? 'Deposit marked as Confirmed'
                      : 'Deposit marked as Pending',
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _depositSheet(context, d, net);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  'Delete deposit?',
                  'This cannot be undone.',
                );
                if (ok) {
                  ref.read(appDataProvider.notifier).deleteDeposit(d.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Preview & Sync ----------

  Future<void> _syncSheet(BuildContext context, String type) async {
    final s0 = ref.read(appDataProvider);
    final target0 = _key(s0.selectedYear, _month);
    var sources = <String>[_prevKey()];
    var target = target0;
    var sourcePropertyId = s0.effectivePropertyId;

    bool matchesSourceProp(String? itemPropId) {
      if (s0.properties.isEmpty) return true;
      final normId =
          (itemPropId == null ||
              itemPropId.isEmpty ||
              itemPropId == 'prop-default')
          ? s0.properties.first.id
          : itemPropId;
      return normId == sourcePropertyId;
    }

    final tenantById = {for (final t in s0.tenants) t.id: t};

    String expSig(String cat, String desc, double amt) =>
        '${cat.trim().toLowerCase()}_${desc.trim().toLowerCase()}_$amt';

    List<Payment> rentItems() {
      final out = <Payment>[];
      if (type != 'expenses') {
        final seenTenants = <String>{};
        final seenUnits = <String>{};
        for (final src in sources) {
          final srcPayments = s0.payments.where(
            (p) =>
                matchesSourceProp(p.propertyId) &&
                (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
                    .startsWith(src),
          );
          for (final p in srcPayments) {
            if (p.tenantId.isEmpty) continue;
            final t = tenantById[p.tenantId];
            if (t != null && t.status == 'inactive') continue;
            final u = t?.unit.trim() ?? '';
            if (seenTenants.contains(p.tenantId)) continue;
            if (u.isNotEmpty && seenUnits.contains(u)) continue;

            seenTenants.add(p.tenantId);
            if (u.isNotEmpty) seenUnits.add(u);
            out.add(p);
          }
        }
      }
      return out;
    }

    List<Expense> expItems() {
      final out = <Expense>[];
      if (type != 'rentRoll') {
        final seenSignatures = <String>{};
        for (final src in sources) {
          final srcExpenses = s0.expenses.where(
            (e) =>
                matchesSourceProp(e.propertyId) &&
                (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(src),
          );
          for (final e in srcExpenses) {
            final sig = expSig(e.category, e.description, e.amount);
            if (seenSignatures.contains(sig)) continue;
            seenSignatures.add(sig);
            out.add(e);
          }
        }
      }
      return out;
    }

    List<Payment> targetRent(String tgt) => s0.scopedPayments
        .where(
          (p) => (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
              .startsWith(tgt),
        )
        .toList();

    bool rentDup(Payment p, List<Payment> existing) {
      final u = tenantById[p.tenantId]?.unit.trim();
      return existing.any((e) {
        if (e.tenantId == p.tenantId) return true;
        final eu = tenantById[e.tenantId]?.unit.trim();
        return u != null && u.isNotEmpty && eu == u;
      });
    }

    String? rentDupReason(Payment p, List<Payment> existing) {
      final u = tenantById[p.tenantId]?.unit.trim();
      var tenant = false, unit = false;
      for (final e in existing) {
        if (e.tenantId == p.tenantId) tenant = true;
        final eu = tenantById[e.tenantId]?.unit.trim();
        if (u != null && u.isNotEmpty && eu == u) unit = true;
      }
      if (tenant && unit) return 'both';
      if (tenant) return 'tenant';
      if (unit) return 'unit';
      return null;
    }

    List<Expense> targetExp(String tgt) => s0.scopedExpenses
        .where(
          (e) =>
              (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(tgt),
        )
        .toList();

    bool expDup(Expense e, List<Expense> existing) {
      final sig = expSig(e.category, e.description, e.amount);
      return existing.any(
        (x) => expSig(x.category, x.description, x.amount) == sig,
      );
    }

    await showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final rItems = rentItems();
          final eItems = expItems();
          final exRent = targetRent(target);
          final exExp = targetExp(target);
          final fresh = [
            ...rItems.where((p) => !rentDup(p, exRent)),
            ...eItems.where((e) => !expDup(e, exExp)),
          ].length;
          final totalRent = rItems.fold<double>(0, (a, p) => a + p.amount);
          final totalExp = eItems.fold<double>(0, (a, e) => a + e.amount);
          return AppModalSheet(
            title: 'Sync Preview',
            icon: Icons.sync,
            iconColor: AppColors.primary,
            size: SheetSize.standard,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s0.properties.length > 1)
                  _syncArrowRow(
                    'Property',
                    s0.properties
                        .firstWhere(
                          (p) => p.id == sourcePropertyId,
                          orElse: () => s0.properties.first,
                        )
                        .name,
                    'Change',
                    () async {
                      final chosen = await showDialog<String>(
                        context: context,
                        builder: (c) => SimpleDialog(
                          title: const Text('Select Source Property'),
                          children: s0.properties
                              .map(
                                (p) => SimpleDialogOption(
                                  onPressed: () => Navigator.pop(c, p.id),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.business,
                                        size: 18,
                                        color: p.id == sourcePropertyId
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: TextStyle(
                                            fontWeight: p.id == sourcePropertyId
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      );
                      if (chosen != null && chosen != sourcePropertyId) {
                        setS(() => sourcePropertyId = chosen);
                      }
                    },
                  ),
                _syncArrowRow(
                  'From',
                  sources.map(_short).join(', '),
                  'Change',
                  () async {
                    final r = await _pickMonths(sources);
                    if (r != null && r.isNotEmpty) setS(() => sources = r);
                  },
                ),
                _syncArrowRow('To', _short(target), 'Change', () async {
                  final r = await _pickMonthYear(s0.selectedYear, _month);
                  if (r != null) {
                    setS(() => target = _key(r.$1, r.$2));
                  }
                }),
                const Divider(height: 24),
                if ((type != 'expenses' ? rItems.length : eItems.length) == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No entries found for the selected months.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ..._syncPreviewList(
                    type,
                    rItems,
                    eItems,
                    (p) => rentDup(p, exRent),
                    (e) => expDup(e, exExp),
                    tenantById,
                    (p) => rentDupReason(p, exRent),
                  ),
                const SizedBox(height: 12),
                if (rItems.isNotEmpty)
                  _syncSummaryRow(
                    Icons.home_outlined,
                    'Rent Roll',
                    rItems.length,
                    totalRent,
                    AppColors.primary,
                  ),
                if (eItems.isNotEmpty)
                  _syncSummaryRow(
                    Icons.receipt_long_outlined,
                    'Expenses',
                    eItems.length,
                    totalExp,
                    AppColors.accentDark,
                  ),
                const SizedBox(height: 8),
                Text(
                  '$fresh entries will be synced • duplicate entries skipped',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            footer: SheetActions(
              primaryLabel: 'Confirm Sync',
              primaryIcon: const Icon(
                Icons.sync,
                size: 19,
                color: Colors.white,
              ),
              onPrimary: fresh == 0
                  ? null
                  : () {
                      final n = ref.read(appDataProvider.notifier);
                      if (type != 'expenses') {
                        final inFlightTenants = <String>{
                          for (final e in exRent) e.tenantId,
                        };
                        final inFlightUnits = <String>{
                          for (final e in exRent)
                            if (tenantById[e.tenantId]?.unit
                                    .trim()
                                    .isNotEmpty ??
                                false)
                              tenantById[e.tenantId]!.unit.trim(),
                        };

                        for (final p in rItems) {
                          final u = tenantById[p.tenantId]?.unit.trim() ?? '';
                          if (inFlightTenants.contains(p.tenantId)) continue;
                          if (u.isNotEmpty && inFlightUnits.contains(u)) {
                            continue;
                          }

                          inFlightTenants.add(p.tenantId);
                          if (u.isNotEmpty) inFlightUnits.add(u);

                          final isSameProp =
                              sourcePropertyId == s0.effectivePropertyId;
                          String resolvedTenantId = p.tenantId;
                          if (!isSameProp && u.isNotEmpty) {
                            final targetMatch = s0.scopedTenants
                                .where(
                                  (t) =>
                                      t.unit.trim().toLowerCase() ==
                                      u.toLowerCase(),
                                )
                                .firstOrNull;
                            if (targetMatch != null) {
                              resolvedTenantId = targetMatch.id;
                            }
                          }

                          final t = tenantById[resolvedTenantId];
                          final rentAmt = (t != null && t.rentAmount > 0)
                              ? t.rentAmount
                              : p.amount;

                          n.upsertPayment(
                            Payment(
                              id: newId(),
                              tenantId: resolvedTenantId,
                              amount: rentAmt,
                              status: 'pending',
                              paidForMonth: target,
                              displayMonth: target,
                              propertyId: s0.effectivePropertyId,
                            ),
                          );
                        }
                      }
                      if (type != 'rentRoll') {
                        final inFlightExp = <String>{
                          for (final x in exExp)
                            expSig(x.category, x.description, x.amount),
                        };

                        for (final e in eItems) {
                          final sig = expSig(
                            e.category,
                            e.description,
                            e.amount,
                          );
                          if (inFlightExp.contains(sig)) continue;
                          inFlightExp.add(sig);

                          n.upsertExpense(
                            Expense(
                              id: newId(),
                              category: e.category,
                              description: e.description,
                              amount: e.amount,
                              date: DateTime.now().toIso8601String(),
                              status: 'pending',
                              expenseForMonth: target,
                              displayMonth: target,
                              propertyId: s0.effectivePropertyId,
                            ),
                          );
                        }
                      }
                      Navigator.pop(ctx);
                      showAppToast(
                        context,
                        'Synced $fresh entries',
                        isSuccess: true,
                      );
                    },
            ),
          );
        },
      ),
    );
  }

  List<Widget> _syncPreviewList(
    String type,
    List<Payment> rItems,
    List<Expense> eItems,
    bool Function(Payment) rentDup,
    bool Function(Expense) expDup,
    Map<String, Tenant> tenantById,
    String? Function(Payment) rentReason,
  ) {
    final out = <Widget>[];
    if (type != 'expenses') {
      for (final p in rItems) {
        final reason = rentReason(p);
        final dupLabel = reason == 'unit'
            ? 'Duplicate Unit'
            : reason == 'tenant'
            ? 'Duplicate Tenant'
            : reason == 'both'
            ? 'Duplicate (Unit & Tenant)'
            : null;
        out.add(
          _syncItem(
            tenantById[p.tenantId]?.name ?? 'Tenant',
            'Rent • ${tenantById[p.tenantId]?.unit ?? ''}',
            '${p.amount}',
            dupLabel,
          ),
        );
      }
    }
    if (type != 'rentRoll') {
      for (final e in eItems) {
        final dup = expDup(e);
        out.add(
          _syncItem(
            e.description,
            e.category,
            '${e.amount}',
            dup ? 'Duplicate' : null,
          ),
        );
      }
    }
    return out;
  }

  Widget _syncItem(
    String title,
    String subtitle,
    String amount,
    String? dupLabel,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        if (dupLabel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              dupLabel,
              style: const TextStyle(fontSize: 10, color: AppColors.error),
            ),
          ),
      ],
    ),
  );

  Widget _syncArrowRow(
    String label,
    String value,
    String action,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );

  Widget _syncSummaryRow(
    IconData icon,
    String label,
    int count,
    double total,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 12),
        Text(
          fmtMoney(ref.read(appDataProvider).selectedCurrency, total),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ],
    ),
  );

  Future<List<String>?> _pickMonths(List<String> initial) async {
    final s = ref.read(appDataProvider);
    final base = DateTime(
      s.selectedYear,
      _month,
    ).subtract(const Duration(days: 1));
    final list = <String>[];
    var y = base.year;
    var m = base.month;
    for (var i = 0; i < 12; i++) {
      list.add(_key(y, m));
      m--;
      if (m < 1) {
        m = 12;
        y--;
      }
    }
    final sel = {...initial};
    return showAdaptiveModalSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: 'Select Source Months',
            icon: Ionicons.calendarOutline,
            iconColor: AppColors.primary,
            size: SheetSize.standard,
            body: Column(
              children: list.map((k) {
                final parts = k.split('-');
                final mIdx = parts.length > 1
                    ? (int.tryParse(parts[1]) ?? 0)
                    : 0;
                final label = (mIdx >= 1 && mIdx <= 12)
                    ? '${_monthLong[mIdx]} ${parts[0]}'
                    : k;
                return CheckboxListTile(
                  value: sel.contains(k),
                  activeColor: AppColors.primary,
                  dense: true,
                  title: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      sel.add(k);
                    } else {
                      sel.remove(k);
                    }
                  }),
                );
              }).toList(),
            ),
            footer: SheetActions(
              primaryLabel: 'Done',
              onPrimary: () => Navigator.pop(ctx, sel.toList()),
            ),
          );
        },
      ),
    );
  }
}

/// Expanding fan FAB — Speed Dial for Quick Actions on Overview
class _FanFab extends StatefulWidget {
  final VoidCallback onRent;
  final VoidCallback onExpense;
  final VoidCallback onNote;
  final VoidCallback onDeposit;
  final ValueChanged<bool>? onOpenChanged;

  const _FanFab({
    super.key,
    required this.onRent,
    required this.onExpense,
    required this.onNote,
    required this.onDeposit,
    this.onOpenChanged,
  });

  @override
  State<_FanFab> createState() => _FanFabState();
}

class _FanFabState extends State<_FanFab> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void collapse() {
    if (_open) {
      _toggle();
    }
  }

  void _toggle() {
    setState(() => _open = !_open);
    widget.onOpenChanged?.call(_open);
    if (_open) {
      _ctl.forward();
    } else {
      _ctl.reverse();
    }
  }

  void _fire(VoidCallback fn) {
    _toggle();
    Future.delayed(const Duration(milliseconds: 180), fn);
  }

  Widget _actionItem({
    required int index,
    required IconData icon,
    required String label,
    required Color accentColor,
    required List<Color> gradient,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final start = (index * 0.1).clamp(0.0, 0.7);
    final end = (start + 0.4).clamp(0.0, 1.0);
    final itemProgress = Interval(
      start,
      end,
      curve: Curves.easeOutBack,
    ).transform(_ctl.value).clamp(0.0, 1.0);

    return Opacity(
      opacity: itemProgress,
      child: Transform.scale(
        scale: 0.6 + 0.4 * itemProgress,
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F2B2B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1D4A4A)
                        : const Color(0xFFDFE6E6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: isDark ? Colors.white : const Color(0xFF132A2A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Mini Action Circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.25 : 0.4),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: isDark ? 0.45 : 0.35,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(child: Icon(icon, size: 20, color: Colors.white)),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainButton(bool isDark) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, child) {
          final rotationAngle = _ctl.value * 0.7853982; // 45 deg in rad
          final scale = 1.0 + 0.05 * math.sin(_ctl.value * math.pi);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F766E), // Rich teal
                    Color(0xFF059669), // Vibrant emerald
                    Color(0xFF10B981), // Fresh lively jade
                  ],
                ),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF34D399).withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? const Color(0xFF059669).withValues(alpha: 0.45)
                        : const Color(0xFF059669).withValues(alpha: 0.38),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: Transform.rotate(
                  angle: rotationAngle,
                  child: const Icon(
                    Ionicons.add,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        final isOpen = _open || _ctl.value > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isOpen) ...[
              _actionItem(
                index: 3,
                icon: Ionicons.business,
                label: 'Bank Deposit',
                accentColor: const Color(0xFF8B5CF6),
                gradient: const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
                onTap: () => _fire(widget.onDeposit),
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _actionItem(
                index: 2,
                icon: Ionicons.documentTextOutline,
                label: 'Add Note',
                accentColor: const Color(0xFF0EA5E9),
                gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
                onTap: () => _fire(widget.onNote),
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _actionItem(
                index: 1,
                icon: Ionicons.cardOutline,
                label: 'Add Expense',
                accentColor: const Color(0xFFF43F5E),
                gradient: const [Color(0xFFE11D48), Color(0xFFFB7185)],
                onTap: () => _fire(widget.onExpense),
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _actionItem(
                index: 0,
                icon: Ionicons.cashOutline,
                label: 'Add Payment',
                accentColor: const Color(0xFF10B981),
                gradient: const [Color(0xFF059669), Color(0xFF10B981)],
                onTap: () => _fire(widget.onRent),
                isDark: isDark,
              ),
              const SizedBox(height: 16),
            ],
            _mainButton(isDark),
          ],
        );
      },
    );
  }
}

DateTime _parseDate(String? iso) {
  try {
    if (iso != null && iso.isNotEmpty) return DateTime.parse(iso);
  } catch (_) {}
  return DateTime.now();
}
