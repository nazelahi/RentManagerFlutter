import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/wave_animation.dart';
import '../../services/report_export_service.dart';
import '../desktop/desktop_reports_view.dart';

/// Strict 1:1 port of `src/screens/ReportsScreen.tsx`.
///
/// Layout: fixed header (title + subtitle + floating export button), a
/// gradient Month/Year selector, a custom tenant dropdown, a single row of
/// Income/Expense/Work/Net summary cards (All Tenants only), a Rent Roll /
/// Expenses tab selector (All Tenants only), the content branch (tenant card +
/// Tenant Summary when a specific tenant is picked, rent/expense tables when
/// All Tenants), an always-visible Completed Work Orders section, and HTML/CSV
/// exports. Depends on `MonthYearPickerModal` and `TenantRentHistoryModal`.
class ReportsView extends ConsumerStatefulWidget {
  static final globalKey = GlobalKey<_ReportsViewState>();
  const ReportsView({super.key});

  static void showExportCsv(BuildContext context) {
    if (DesktopReportsView.globalKey.currentState != null) {
      DesktopReportsView.globalKey.currentState!.exportCsv();
    } else {
      globalKey.currentState?._exportCsv();
    }
  }

  static void showExportPdf(BuildContext context) {
    if (DesktopReportsView.globalKey.currentState != null) {
      DesktopReportsView.globalKey.currentState!.exportPdf();
    } else {
      globalKey.currentState?._exportPdf();
    }
  }

  static void showPrint(BuildContext context) {
    showExportPdf(context);
  }

  static void showExportTenant(BuildContext context, Tenant tenant) {
    final container = ProviderScope.containerOf(context, listen: false);
    final s = container.read(appDataProvider);
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      DesktopReportsView.showTenantExportDialog(context, tenant, s);
      return;
    }
    final cur = s.selectedCurrency;
    final history = s.scopedPayments
        .where((p) => p.tenantId == tenant.id && p.status == 'paid')
        .toList();
    globalKey.currentState?._exportTenantHistory(tenant, history, cur);
  }

  @override
  ConsumerState<ReportsView> createState() => _ReportsViewState();
}

typedef _RentRow = ({Tenant tenant, Payment payment});

class _ReportsViewState extends ConsumerState<ReportsView> {
  // Local month/year (init = current month/year), independent of global state.
  late String _mk;
  String _tenant = 'all';
  String _tab = 'rentRoll';
  bool _showTenantDropdown = false;
  bool _showExport = false;

  // Loading skeleton wave (mirrors the OverviewView behavior).
  bool _wave = false;
  Timer? _waveTimer;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mk = '${now.year}-${now.month.toString().padLeft(2, '0')}';
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

  /// Briefly show the skeleton wave, mirroring OverviewView's switch delay.
  void _flashWave() {
    _waveTimer?.cancel();
    setState(() => _wave = true);
    _waveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _wave = false);
    });
  }

  // ----- month/year helpers -----
  String get _year => _mk.substring(0, 4);
  String get _month => _mk.substring(5, 7);
  int get _monthIndex => int.tryParse(_month) ?? 1;

  String _monthNameLong(String my) {
    final i = int.tryParse(my.length >= 7 ? my.substring(5, 7) : '') ?? 0;
    if (i < 1 || i > 12) return my;
    return _monthNames[i - 1];
  }

  String _monthNameShort(String? my) {
    if (my == null || my.isEmpty) return '';
    final parts = my.split('-');
    if (parts.length < 2) return my;
    final i = int.tryParse(parts[1]) ?? 0;
    if (i < 1 || i > 12) return my;
    return _monthShort[i - 1];
  }

  void _changeMonth(int delta) {
    var m = _monthIndex + delta;
    var y = int.parse(_year);
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    setState(() => _mk = '$y-${m.toString().padLeft(2, '0')}');
    _flashWave();
  }

  void _changeYear(int delta) {
    final y = int.parse(_year) + delta;
    setState(() => _mk = '$y-$_month');
    _flashWave();
  }

  Future<void> _pickMonth() async {
    final res = await showAdaptiveModalSheet<({String month, String year})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MonthYearSheet(
        initialMonth: _month,
        initialYear: _year,
        title: 'Select Month',
      ),
    );
    if (res == null || !mounted) return;
    if (res.month != _month) {
      setState(() => _mk = '$_year-${res.month}');
      _flashWave();
    }
  }

  Future<void> _pickYear() async {
    final res = await showAdaptiveModalSheet<({String month, String year})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MonthYearSheet(
        initialMonth: _month,
        initialYear: _year,
        title: 'Select Year',
      ),
    );
    if (res == null || !mounted) return;
    if (res.year != _year) {
      setState(() => _mk = '${res.year}-$_month');
      _flashWave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final cur = s.selectedCurrency;
    final year = int.parse(_year);
    final tenantById = {for (final t in s.scopedTenants) t.id: t};

    // ----- FilteredData (strict: paid-only, exact paidForMonth) -----
    final rent = <_RentRow>[];
    for (final p in s.scopedPayments) {
      if (p.status != 'paid') continue;
      if (_tenant != 'all' && p.tenantId != _tenant) continue;
      final t = tenantById[p.tenantId];
      if (t == null) continue;
      final pfm = p.paidForMonth ?? p.displayMonth;
      if (pfm == null || pfm.isEmpty) continue;
      final pMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(pfm);
      if (pMatch == null) continue;
      if (pMatch.group(1) == _year && pMatch.group(2) == _month) {
        rent.add((tenant: t, payment: p));
      }
    }
    rent.sort((a, b) {
      final ua = a.tenant.unit;
      final ub = b.tenant.unit;
      final na = RegExp(r'\d+').firstMatch(ua)?.group(0) ?? '0';
      final nb = RegExp(r'\d+').firstMatch(ub)?.group(0) ?? '0';
      final c = (int.tryParse(na) ?? 0).compareTo(int.tryParse(nb) ?? 0);
      return c != 0 ? c : ua.compareTo(ub);
    });

    final expenses = s.scopedExpenses.where((e) {
      if (_tenant != 'all') return false;
      if (e.status != 'paid') return false;
      final efm = e.expenseForMonth ?? e.displayMonth;
      if (efm == null || efm.isEmpty) return false;
      final eMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(efm);
      if (eMatch == null) return false;
      return eMatch.group(1) == _year && eMatch.group(2) == _month;
    }).toList();

    // Completed work orders in the selected month.
    final workOrders = s.scopedWorkOrders.where((w) {
      if (w.status != 'completed') return false;
      final raw = (w.completedAt ?? '').trim();
      final stamp = DateTime.tryParse(raw.isNotEmpty ? raw : w.createdAt);
      if (stamp == null) return false;
      return stamp.year == year && stamp.month == int.parse(_month);
    }).toList();

    final totalRent = rent.fold<double>(0, (a, r) => a + r.payment.amount);
    final totalExpenses =
        expenses.fold<double>(0, (a, e) => a + e.amount);
    final totalWork = workOrders.fold<double>(
        0, (a, w) => a + (w.workerCost ?? 0) + (w.productPrice ?? 0));
    final net = totalRent - totalExpenses - totalWork;

    final noData =
        s.scopedTenants.isEmpty && s.scopedPayments.isEmpty && s.scopedExpenses.isEmpty;
    final selectedTenant =
        _tenant == 'all' ? null : tenantById[_tenant];

    final topPadding = MediaQuery.of(context).padding.top;

    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopReportsView(
        key: DesktopReportsView.globalKey,
        onExportCsv: () => _exportCsv(),
        onExportPdf: () => _exportPdf(),
        onPrint: () => _printReport(),
        onExportTenantHistory: (t) {
          final history = s.scopedPayments
              .where((p) => p.tenantId == t.id && p.status == 'paid')
              .toList();
          _exportTenantHistory(t, history, cur);
        },
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Column(
              children: [
                _header(context, s),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        _monthYearSelector(),
                        const SizedBox(height: 12),
                        _tenantFilter(s),
                        const SizedBox(height: 12),
                        if (_tenant == 'all') ...[
                          _summaryRow(cur, totalRent, totalExpenses, totalWork, net),
                          RentExpenseTabs(
                            value: _tab,
                            onChanged: (t) {
                              if (t == _tab) return;
                              setState(() => _tab = t);
                              _flashWave();
                            },
                          ),
                        ],
                        if (_wave)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: WaveAnimation(
                                count: 6, icon: Icons.assessment_outlined),
                          )
                        else
                          _content(
                            s: s,
                            cur: cur,
                            noData: noData,
                            selectedTenant: selectedTenant,
                            rent: rent,
                            expenses: expenses,
                            workOrders: workOrders,
                            totalRent: totalRent,
                          ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_showExport)
              Positioned(
                top: topPadding + 58,
                right: 16,
                child: _exportPopup(),
              ),
          ],
        ),
      ),
    );
  }

  // ----- Header -----
  Widget _header(BuildContext context, AppDataState s) {
    final isDark = AppColors.isDark;
    final topPadding = MediaQuery.of(context).padding.top;
    final monthLabel = '${_monthNameShort(_mk)} $_year';
    final propName = s.activeProperty?.name ?? s.propertyManager?.propertyName ?? 'Active Property';

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
          // Left: Reports Icon Badge
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
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
                      Icons.bar_chart_rounded,
                      size: 22,
                      color: isDark ? AppColors.primary : Colors.white,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.primary : const Color(0xFF34D399),
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
          const SizedBox(width: 10),

          // Center: Title + Date pill + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        monthLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  propName,
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

          // Right: Export Action Button
          GestureDetector(
            onTap: () => setState(() => _showExport = !_showExport),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _showExport
                    ? (isDark
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.35))
                    : (isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.06)
                        : Colors.white.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.1)
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                Icons.download_rounded,
                size: 20,
                color: isDark ? AppColors.primary : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportPopup() => Container(
        width: 170,
        decoration: BoxDecoration(
          color: AppColors.dropdownBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _exportOption('Export as CSV', const Color(0xFF28A745),
              Icons.table_chart_outlined, () => _exportCsv()),
          _exportOption('Save as PDF', const Color(0xFFDC3545),
              Icons.picture_as_pdf_outlined, () => _exportPdf()),
        ]),
      );

  Widget _exportOption(String label, Color color, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  // ----- Month / Year selector -----
  Widget _monthYearSelector() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.isDark ? null : AppColors.surface,
            gradient: AppColors.isDark
                ? const LinearGradient(colors: [
                    Color.fromRGBO(255, 255, 255, 0.1),
                    Color.fromRGBO(255, 255, 255, 0.05),
                  ])
                : null,
            borderRadius: BorderRadius.circular(8),
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
          child: Row(children: [
            Expanded(
                child: _selectorSection(
                    value: _monthNameLong(_mk),
                    onPrev: () => _changeMonth(-1),
                    onNext: () => _changeMonth(1),
                    onTap: _pickMonth)),
            Expanded(
                child: _selectorSection(
                    value: _year,
                    onPrev: () => _changeYear(-1),
                    onNext: () => _changeYear(1),
                    onTap: _pickYear)),
          ]),
        ),
      );

  Widget _selectorSection(
          {required String value,
          required VoidCallback onPrev,
          required VoidCallback onNext,
          required VoidCallback onTap}) =>
      Row(children: [
        _arrow(Icons.chevron_left, onPrev),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                              letterSpacing: 0.2))),
                ]),
          ),
        ),
        _arrow(Icons.chevron_right, onNext),
      ]);

  Widget _arrow(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: AppColors.primary)),
      );

  // ----- Tenant filter (custom dropdown) -----
  Widget _tenantFilter(AppDataState s) {
    final name = _tenant == 'all'
        ? 'All Tenants'
        : s.scopedTenants
            .where((t) => t.id == _tenant)
            .map((t) => t.name)
            .firstOrNull ??
            'All Tenants';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(children: [
        GestureDetector(
          onTap: () =>
              setState(() => _showTenantDropdown = !_showTenantDropdown),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color.fromRGBO(76, 175, 80, 0.3)),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.text,
                          fontWeight: FontWeight.w500))),
              Icon(
                  _showTenantDropdown
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: AppColors.primary),
            ]),
          ),
        ),
        if (_showTenantDropdown)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.dropdownBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color.fromRGBO(76, 175, 80, 0.5)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dropdownOption('All Tenants', _tenant == 'all',
                      () => _switchTenant('all')),
                  ...s.scopedTenants.map((t) => _dropdownOption(
                      t.name, _tenant == t.id, () => _switchTenant(t.id))),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  void _switchTenant(String id) {
    if (_tenant == id) return;
    setState(() {
      _tenant = id;
      _showTenantDropdown = false;
    });
    _flashWave();
  }

  Widget _dropdownOption(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? const Color.fromRGBO(76, 175, 80, 0.2)
                : Colors.transparent,
            border: Border(
                bottom: BorderSide(color: AppColors.border)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: active ? AppColors.primary : AppColors.text,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  // ----- Summary cards -----
  Widget _summaryRow(String cur, double income, double expense,
          double work, double net) =>
      Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          Expanded(
              child: _miniStat(
                  icon: Icons.trending_up,
                  color: AppColors.primary,
                  label: 'Income',
                  value: fmtMoney(cur, income))),
          const SizedBox(width: 6),
          Expanded(
              child: _miniStat(
                  icon: Icons.trending_down,
                  color: AppColors.error,
                  label: 'Expense',
                  value: fmtMoney(cur, expense))),
          const SizedBox(width: 6),
          Expanded(
              child: _miniStat(
                  icon: Icons.construction,
                  color: AppColors.accentDark,
                  label: 'Work',
                  value: fmtMoney(cur, work))),
          const SizedBox(width: 6),
          Expanded(
              child: _miniStat(
                  icon: Icons.account_balance_wallet,
                  color: net >= 0 ? AppColors.primary : AppColors.error,
                  label: 'Net',
                  value: fmtMoney(cur, net),
                  valueColor:
                      net >= 0 ? AppColors.primary : AppColors.error)),
        ]),
      );

  Widget _miniStat(
          {required IconData icon,
          required Color color,
          required String label,
          required String value,
          Color? valueColor}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.borderLight, width: 1.5),
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
            children: [
              Row(children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500))),
              ]),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: valueColor ?? AppColors.text)),
              ),
            ]),
      );

  // ----- Content -----
  Widget _content(
      {required AppDataState s,
      required String cur,
      required bool noData,
      required Tenant? selectedTenant,
      required List<_RentRow> rent,
      required List<Expense> expenses,
      required List<WorkOrder> workOrders,
      required double totalRent}) {
    if (noData) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: _emptyCard(Icons.description, 'No Data Available',
            'No data found. Please add some tenants, rent roll entries, or expenses to generate reports.'),
      );
    }
    if (selectedTenant != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(children: [
          // Tenant card title.
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.isDark ? null : AppColors.cardBackground,
              gradient: AppColors.isDark
                  ? const LinearGradient(colors: [
                      Color.fromRGBO(255, 255, 255, 0.1),
                      Color.fromRGBO(255, 255, 255, 0.05),
                    ])
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color.fromRGBO(76, 175, 80, 0.3)),
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
            child: Row(children: [
              Expanded(
                  child: Text(selectedTenant.name,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                          letterSpacing: 0.1))),
              Text('Unit ${selectedTenant.unit.isEmpty ? 'N/A' : selectedTenant.unit}',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          if (rent.isEmpty)
            _emptyCard(Icons.home, 'No Rent Data',
                'No paid rent entries found for ${selectedTenant.name} in $_mk')
          else
            ...rent.map((r) => _rentRow(s, cur, r)),
          _tenantSummary(s, cur, selectedTenant, rent, totalRent),
        ]),
      );
    }
    // All Tenants.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(children: [
        if (_tab == 'rentRoll')
          ...(rent.isEmpty
              ? [
                  _emptyCard(Icons.home, 'No Rent Data',
                      'No paid rent entries found for $_mk')
                ]
              : rent.map((r) => _rentRow(s, cur, r)))
        else
          ..._expensesSection(s, cur, expenses),
        const SizedBox(height: 8),
        _completedWorkSection(workOrders, cur),
      ]),
    );
  }

  Widget _rentRow(AppDataState s, String cur, _RentRow r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: GestureDetector(
          onTap: () => _openRentHistory(r.tenant),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.03)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.08)
                      : AppColors.border),
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
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AvatarView(
                    name: r.tenant.name,
                    uri: r.tenant.avatar,
                    radius: 18),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.tenant.name,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                              letterSpacing: 0.1)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(
                                255, 152, 0, 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color.fromRGBO(
                                    255, 152, 0, 0.3)),
                          ),
                          child: Text(
                            _monthNameShort(r.payment.displayMonth ??
                                r.payment.paidForMonth ??
                                'N/A'),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.accentDark,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtMoney(cur, r.payment.amount),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                        letterSpacing: 0.1)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                      r.payment.paidDate == null
                          ? 'N/A'
                          : fmtDate(r.payment.paidDate!),
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ]),
              ]),
            ]),
          ),
        ),
      );

  // ----- Expenses (ports ExpensesTable) -----
  List<Widget> _expensesSection(
      AppDataState s, String cur, List<Expense> expenses) {
    if (expenses.isEmpty) {
      return [
        _emptyCard(Icons.credit_card, 'No Expenses',
            'No expenses found for this period')
      ];
    }
    return expenses.map((e) {
      final pending = e.status != 'paid';
      final bg = pending
          ? (AppColors.isDark
              ? const Color.fromRGBO(255, 152, 0, 0.08)
              : const Color(0xFFFFF7ED))
          : (AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.03)
              : AppColors.cardBackground);
      final border = pending
          ? const Color.fromRGBO(255, 152, 0, 0.3)
          : (AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.08)
              : AppColors.border);
      final catHex = s.expenseCategories
              .where((c) => c.name == e.category)
              .map((c) => c.color)
              .firstOrNull ??
          '#4CAF50';
      final catColor = _hexColor(catHex);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
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
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          pending
                              ? Icons.access_time
                              : Icons.check_circle,
                          size: 12,
                          color: pending
                              ? AppColors.accentDark
                              : AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(e.description,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text,
                                  letterSpacing: 0.2))),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: catColor,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(e.category,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: _contrast(catColor))),
                    ),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtMoney(cur, e.amount),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                      letterSpacing: 0.1)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.calendar_today,
                    size: 12, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(fmtDate(e.date),
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ]),
              if (e.receipt != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.receipt_long,
                      size: 12, color: AppColors.primary),
                  const SizedBox(width: 4),
                  const Text('Receipt available',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ]),
              ],
            ]),
          ]),
        ),
      );
    }).toList();
  }

  // ----- Completed work orders section -----
  Widget _completedWorkSection(List<WorkOrder> workOrders, String cur) =>
      Column(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.isDark ? null : AppColors.cardBackground,
            gradient: AppColors.isDark
                ? const LinearGradient(colors: [
                    Color.fromRGBO(34, 139, 34, 0.3),
                    Color.fromRGBO(34, 139, 34, 0.2),
                    Color.fromRGBO(34, 139, 34, 0.1),
                  ])
                : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.isDark
                    ? const Color.fromRGBO(34, 139, 34, 0.3)
                    : AppColors.border),
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
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.isDark
                        ? const Color.fromRGBO(34, 139, 34, 0.2)
                        : const Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.isDark
                            ? const Color.fromRGBO(34, 139, 34, 0.3)
                            : AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.check_circle,
                      size: 14, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Completed Work Orders',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                                letterSpacing: 0.1)),
                        Text('Maintenance tasks completed in $_year',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500)),
                      ]),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.isDark
                    ? const Color.fromRGBO(34, 139, 34, 0.15)
                    : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.isDark
                        ? const Color.fromRGBO(34, 139, 34, 0.3)
                        : AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                Text('${workOrders.length}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                Text(workOrders.length == 1 ? 'Order' : 'Orders',
                    style: TextStyle(
                        fontSize: 8,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (workOrders.isEmpty)
          _emptyCard(Icons.construction, 'No Completed Work Orders',
              'No completed work orders found for $_year')
        else
          ...workOrders.map((w) => _workOrderRow(w, cur)),
      ]);

  Widget _workOrderRow(WorkOrder w, String cur) {
    final cost = (w.workerCost ?? 0) + (w.productPrice ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.03)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : AppColors.border),
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
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                                letterSpacing: 0.3)),
                        Text(w.category,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500)),
                      ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(76, 175, 80, 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    const Icon(Icons.credit_card,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(fmtMoney(cur, cost),
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Text(w.description,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.2,
                            fontWeight: FontWeight.w500))),
                if (w.dueDate.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.done_all,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(fmtDate(w.dueDate),
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3)),
                  ]),
              ]),
              if (w.unit != null && w.unit!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Unit: ${w.unit}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2)),
              ],
            ]),
      ),
    );
  }

  // ----- Tenant Summary -----
  Widget _tenantSummary(AppDataState s, String cur, Tenant t,
          List<_RentRow> rent, double totalRent) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.isDark ? null : AppColors.cardBackground,
              gradient: AppColors.isDark
                  ? const LinearGradient(colors: [
                      Color.fromRGBO(76, 175, 80, 0.15),
                      Color.fromRGBO(76, 175, 80, 0.08),
                    ])
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color.fromRGBO(76, 175, 80, 0.3)),
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
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(76, 175, 80, 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color.fromRGBO(76, 175, 80, 0.3)),
                    ),
                    child: const Icon(Icons.account_circle,
                        size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tenant Summary',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                  letterSpacing: 0.1)),
                          Text(
                              '${t.name} - Unit ${t.unit.isEmpty ? 'N/A' : t.unit}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500)),
                        ]),
                  ),
                ]),
              ),
              Text(_mk,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _tenantStat(Icons.trending_up, AppColors.primary,
                'Total Rent Collected', fmtMoney(cur, totalRent)),
            const SizedBox(width: 8),
            _tenantStat(Icons.receipt_long, AppColors.accentDark,
                'Payment Count', '${rent.length}'),
            const SizedBox(width: 8),
            _tenantStat(
                Icons.calendar_today,
                AppColors.info,
                'Report Period',
                '${_monthNameLong(_mk)} $_year'),
          ]),
        ]),
      );

  Widget _tenantStat(
          IconData icon, Color color, String label, String value) =>
      Expanded(
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
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
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.1)
                    : color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text)),
                    ),
                  ]),
            ),
          ]),
        ),
      );

  // ----- Empty state card -----
  Widget _emptyCard(IconData icon, String title, String subtitle) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.isDark ? null : AppColors.cardBackground,
          gradient: AppColors.isDark
              ? const LinearGradient(colors: [
                  Color.fromRGBO(255, 255, 255, 0.03),
                  Color.fromRGBO(255, 255, 255, 0.01),
                ])
              : null,
          borderRadius: BorderRadius.circular(16),
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
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 32, color: AppColors.error),
          ),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4)),
          ),
        ]),
      );

  // ----- Tenant rent history modal -----
  void _openRentHistory(Tenant t) {
    final s = ref.read(appDataProvider);
    final history = s.scopedPayments
        .where((p) => p.tenantId == t.id && p.status == 'paid')
        .toList()
      ..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TenantRentHistorySheet(
        tenant: t,
        rentHistory: history,
        currency: s.selectedCurrency,
        onExport: () => _exportTenantHistory(t, history, s.selectedCurrency),
      ),
    );
  }

  DateTime _dateOf(Payment p) {
    final raw = p.paidDate ?? p.paidForMonth ?? '';
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ----- exports -----
  Future<void> _exportCsv() async {
    setState(() => _showExport = false);
    final s = ref.read(appDataProvider);
    final data = ReportExportService.prepareData(
      state: s,
      monthKey: _mk,
      tenantId: _tenant,
    );
    final csvContent = ReportExportService.generateReportCsv(data);
    final fileName = 'reports_${_mk}_${_tenant == 'all' ? 'all_tenants' : 'tenant'}.csv';
    await ReportExportService.exportCsv(
      context: context,
      csvContent: csvContent,
      fileName: fileName,
    );
  }

  Future<void> _exportPdf() async {
    setState(() => _showExport = false);
    final s = ref.read(appDataProvider);
    final data = ReportExportService.prepareData(
      state: s,
      monthKey: _mk,
      tenantId: _tenant,
    );
    final pdfBytes = await ReportExportService.generateReportPdf(data);
    final fileName = 'reports_${_mk}_${_tenant == 'all' ? 'all_tenants' : 'tenant'}.pdf';
    if (!mounted) return;
    await ReportExportService.exportPdf(
      context: context,
      pdfBytes: pdfBytes,
      fileName: fileName,
    );
  }

  Future<void> _printReport() async {
    setState(() => _showExport = false);
    final s = ref.read(appDataProvider);
    final data = ReportExportService.prepareData(
      state: s,
      monthKey: _mk,
      tenantId: _tenant,
    );
    final pdfBytes = await ReportExportService.generateReportPdf(data);
    if (!mounted) return;
    await ReportExportService.printPdf(
      context: context,
      pdfBytes: pdfBytes,
      documentName: 'RentManager_Report_$_mk',
    );
  }

  Future<void> _exportTenantHistory(
      Tenant t, List<Payment> history, String cur) async {
    final s = ref.read(appDataProvider);
    final pdfBytes = await ReportExportService.generateTenantStatementPdf(
      tenant: t,
      history: history,
      currency: cur,
      propertyManager: s.propertyManager,
    );
    if (!mounted) return;
    await ReportExportService.exportPdf(
      context: context,
      pdfBytes: pdfBytes,
      fileName: 'Statement_${t.name.replaceAll(' ', '_')}.pdf',
    );
  }
}

Color _hexColor(String hex) {
  try {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

Color _contrast(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// Port of `MonthYearPickerModal.tsx` — Month/Year toggle, month grid (3 col)
/// and year grid (4 col, currentYear ± 10) with Cancel/Confirm.
class _MonthYearSheet extends StatefulWidget {
  final String initialMonth;
  final String initialYear;
  final String title;
  const _MonthYearSheet(
      {required this.initialMonth,
      required this.initialYear,
      required this.title});
  @override
  State<_MonthYearSheet> createState() => _MonthYearSheetState();
}

class _MonthYearSheetState extends State<_MonthYearSheet> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  late String _tempMonth;
  late String _tempYear;
  late int _currentYear;
  String _view = 'month';

  @override
  void initState() {
    super.initState();
    _tempMonth = widget.initialMonth;
    _tempYear = widget.initialYear;
    _currentYear = int.tryParse(widget.initialYear) ?? DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var i = _currentYear - 10; i <= _currentYear + 10; i++) i];
    return AppModalSheet(
      title: widget.title,
      icon: Icons.calendar_today_outlined,
      iconColor: AppColors.primary,
      size: SheetSize.standard,
      scrollable: false,
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            _toggle('Month', 'month'),
            _toggle('Year', 'year'),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _view == 'month'
              ? _monthGrid()
              : _yearGrid(years),
        ),
      ]),
      footer: SheetActions(
        primaryLabel: 'Confirm',
        onPrimary: () => Navigator.pop(
            context, (month: _tempMonth, year: _tempYear)),
      ),
    );
  }

  Widget _toggle(String label, String value) {
    final active = _view == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _view = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? Colors.white
                      : AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _monthGrid() => SingleChildScrollView(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < 12; i++)
            SizedBox(
              width: (MediaQuery.of(context).size.width - 80) / 3,
              child: _cell(
                _months[i],
                selected: _tempMonth == (i + 1).toString().padLeft(2, '0'),
                onTap: () => setState(() =>
                    _tempMonth = (i + 1).toString().padLeft(2, '0')),
              ),
            ),
        ]),
      );

  Widget _yearGrid(List<int> years) => Column(children: [
        Row(children: [
          _yearNav(Icons.chevron_left, () => setState(() => _currentYear--)),
          Expanded(
              child: Text('$_currentYear',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text))),
          _yearNav(Icons.chevron_right, () => setState(() => _currentYear++)),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final y in years)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 80) / 4,
                  child: _cell('$y',
                      selected: _tempYear == '$y',
                      onTap: () => setState(() {
                            _tempYear = '$y';
                            _currentYear = y;
                          })),
                ),
            ]),
          ),
        ),
      ]);

  Widget _yearNav(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 20, color: AppColors.icon),
        ),
      );

  Widget _cell(String label,
          {required bool selected, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.text)),
        ),
      );
}

/// Port of `TenantRentHistoryModal.tsx` — tenant info card w/ export, summary
/// card and alternating paid-rent rows.
class _TenantRentHistorySheet extends StatelessWidget {
  final Tenant tenant;
  final List<Payment> rentHistory;
  final String currency;
  final VoidCallback onExport;
  const _TenantRentHistorySheet(
      {required this.tenant,
      required this.rentHistory,
      required this.currency,
      required this.onExport});

  @override
  Widget build(BuildContext context) {
    final total = rentHistory.fold<double>(0, (a, p) => a + p.amount);
    return AppModalSheet(
      title: 'Rent History',
      icon: Icons.receipt_long,
      iconColor: AppColors.primary,
      size: SheetSize.standard,
      body: Column(
        children: [
          // Tenant info card.
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              AvatarView(
                  name: tenant.name,
                  uri: tenant.avatar,
                  radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tenant.name,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text)),
                      const SizedBox(height: 4),
                      Text('Unit ${tenant.unit}',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500)),
                    ]),
              ),
              GestureDetector(
                onTap: rentHistory.isEmpty ? null : onExport,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: rentHistory.isEmpty
                        ? const Color.fromRGBO(76, 175, 80, 0.05)
                        : const Color.fromRGBO(76, 175, 80, 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color.fromRGBO(76, 175, 80, 0.3)),
                  ),
                  child: const Icon(Icons.download,
                      size: 20, color: AppColors.primary),
                ),
              ),
            ]),
          ),
          // Summary card.
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem('Total Payments', '${rentHistory.length}'),
                  _summaryItem('Total Amount', fmtMoney(currency, total)),
                  _summaryItem(
                      'Average Rent',
                      fmtMoney(currency,
                          rentHistory.isEmpty ? 0 : total / rentHistory.length)),
                ]),
          ),
          if (rentHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.receipt_long,
                      size: 32, color: AppColors.error),
                ),
                const SizedBox(height: 12),
                Text('No Rent History',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 8),
                Text('No paid rent entries found for this tenant',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary)),
              ]),
            )
          else
            for (var i = 0; i < rentHistory.length; i++)
              _rentItem(rentHistory[i], i),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) => Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
        ),
      ]);

  Widget _rentItem(Payment p, int index) {
    final monthName = p.displayMonth != null
        ? _shortMonth(p.displayMonth!)
        : p.paidForMonth != null
            ? _shortMonth(p.paidForMonth!)
            : 'Rent Payment';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.isDark
            ? (index.isEven
                ? const Color.fromRGBO(255, 255, 255, 0.03)
                : const Color.fromRGBO(255, 255, 255, 0.01))
            : (index.isEven
                ? AppColors.cardBackground
                : AppColors.surface),
        borderRadius: BorderRadius.circular(8),
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
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
              color: AppColors.primaryLight, shape: BoxShape.circle),
          child: const Icon(Icons.calendar_today,
              size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(monthName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                const SizedBox(height: 2),
                Text(
                    p.paidDate != null
                        ? fmtDate(p.paidDate!)
                        : 'Date not available',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtMoney(currency, p.amount),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text)),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4)),
            child: const Row(children: [
              Icon(Icons.check_circle, size: 10, color: AppColors.primary),
              SizedBox(width: 4),
              Text('Paid',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ]),
    );
  }

  static String _shortMonth(String my) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = my.split('-');
    if (parts.length < 2) return my;
    final i = int.tryParse(parts[1]) ?? 0;
    if (i < 1 || i > 12) return my;
    return names[i - 1];
  }
}
