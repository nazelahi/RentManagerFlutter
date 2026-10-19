import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../services/report_export_service.dart';
import 'desktop_cash_flow_modal.dart';

/// Modern Executive Financial Analytics & Reporting Dashboard for macOS Desktop.
class DesktopReportsView extends ConsumerStatefulWidget {
  static final globalKey = GlobalKey<_DesktopReportsViewState>();

  final VoidCallback? onExportCsv;
  final VoidCallback? onExportPdf;
  final VoidCallback? onPrint;
  final void Function(Tenant tenant)? onExportTenantHistory;

  const DesktopReportsView({
    super.key,
    this.onExportCsv,
    this.onExportPdf,
    this.onPrint,
    this.onExportTenantHistory,
  });

  static void showTenantExportDialog(
      BuildContext context, Tenant tenant, AppDataState s) {
    _DesktopReportsViewState.showTenantExportDialog(context, tenant, s);
  }

  @override
  ConsumerState<DesktopReportsView> createState() => _DesktopReportsViewState();
}

class _AnnualMonthData {
  final int monthIndex;
  final String monthName;
  final String monthKey;
  final double rent;
  final double expenses;
  final double maintenance;
  final double net;
  final double margin;

  const _AnnualMonthData({
    required this.monthIndex,
    required this.monthName,
    required this.monthKey,
    required this.rent,
    required this.expenses,
    required this.maintenance,
    required this.net,
    required this.margin,
  });
}

class _DesktopReportsViewState extends ConsumerState<DesktopReportsView> {
  late String _mk;
  String _selectedTenantId = 'all'; // 'all' or tenant.id
  String _activeTab = 'all'; // 'all' | 'rent' | 'expenses' | 'maintenance'
  String _reportPeriod = 'monthly'; // 'monthly' | 'annual'

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mk = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String get _year => _mk.substring(0, 4);
  String get _month => _mk.substring(5, 7);
  int get _monthIndex => int.tryParse(_month) ?? 1;

  void _stepMonth(int delta) {
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
  }

  void _stepYear(int delta) {
    final y = int.parse(_year) + delta;
    setState(() => _mk = '$y-$_month');
  }

  List<_AnnualMonthData> _computeAnnualMonths(AppDataState s, int year) {
    final months = <_AnnualMonthData>[];
    final tenantById = {for (final t in s.scopedTenants) t.id: t};

    for (int m = 1; m <= 12; m++) {
      final mStr = m.toString().padLeft(2, '0');
      final mk = '$year-$mStr';

      // Rent
      double mRent = 0;
      for (final p in s.scopedPayments) {
        if (p.status != 'paid') continue;
        if (_selectedTenantId != 'all' && p.tenantId != _selectedTenantId) continue;
        final t = tenantById[p.tenantId];
        if (t == null) continue;
        final pfm = p.paidForMonth;
        if (pfm == null) continue;
        if (pfm.startsWith(mk)) {
          mRent += p.amount;
        }
      }

      // Operating Expenses
      double mExp = 0;
      if (_selectedTenantId == 'all') {
        for (final e in s.scopedExpenses) {
          if (e.status != 'paid') continue;
          final efm = e.expenseForMonth;
          if (efm != null && efm.startsWith(mk)) {
            mExp += e.amount;
          }
        }
      }

      // Work Orders (Maintenance - Scoped)
      double mMaint = 0;
      for (final w in s.scopedWorkOrders) {
        if (w.status != 'completed') continue;
        final dt = DateTime.tryParse(w.completedAt ?? w.createdAt);
        if (dt != null && dt.year == year && dt.month == m) {
          mMaint += (w.workerCost ?? 0) + (w.productPrice ?? 0);
        }
      }

      final mNet = mRent - mExp - mMaint;
      final mMargin = mRent > 0 ? ((mNet / mRent) * 100).clamp(-100.0, 100.0) : 0.0;

      months.add(_AnnualMonthData(
        monthIndex: m,
        monthName: _monthNames[m - 1],
        monthKey: mk,
        rent: mRent,
        expenses: mExp,
        maintenance: mMaint,
        net: mNet,
        margin: mMargin,
      ));
    }
    return months;
  }

  Future<void> exportCsv() async {
    final s = ref.read(appDataProvider);

    if (_reportPeriod == 'annual') {
      final year = int.parse(_year);
      final annualMonths = _computeAnnualMonths(s, year);
      final totalAnnualRent = annualMonths.fold<double>(0, (a, m) => a + m.rent);
      final totalAnnualExpenses = annualMonths.fold<double>(0, (a, m) => a + m.expenses);
      final totalAnnualMaint = annualMonths.fold<double>(0, (a, m) => a + m.maintenance);
      final totalAnnualNet = totalAnnualRent - totalAnnualExpenses - totalAnnualMaint;
      final annualMargin = totalAnnualRent > 0 ? (totalAnnualNet / totalAnnualRent) * 100 : 0.0;

      final buffer = StringBuffer();
      buffer.writeln('Annual Financial & Cash Flow Report - $_year');
      buffer.writeln('Tenant Filter: ${_selectedTenantId == "all" ? "All Tenants & Units" : "Selected"}');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String().substring(0, 10)}');
      buffer.writeln('');
      buffer.writeln('Month,Gross Rent,Operating Expenses,Maintenance Costs,Net Cash Flow,Profit Margin %');
      for (final m in annualMonths) {
        buffer.writeln('${m.monthName} $_year,${m.rent.toStringAsFixed(2)},${m.expenses.toStringAsFixed(2)},${m.maintenance.toStringAsFixed(2)},${m.net.toStringAsFixed(2)},${m.margin.toStringAsFixed(1)}%');
      }
      buffer.writeln('Annual Total,${totalAnnualRent.toStringAsFixed(2)},${totalAnnualExpenses.toStringAsFixed(2)},${totalAnnualMaint.toStringAsFixed(2)},${totalAnnualNet.toStringAsFixed(2)},${annualMargin.toStringAsFixed(1)}%');

      final fileName = 'annual_financial_report_${_year}_${_selectedTenantId == 'all' ? 'all_tenants' : 'tenant'}.csv';
      await ReportExportService.exportCsv(
        context: context,
        csvContent: buffer.toString(),
        fileName: fileName,
      );
      return;
    }

    final data = ReportExportService.prepareData(
      state: s,
      monthKey: _mk,
      tenantId: _selectedTenantId,
    );
    final csvContent = ReportExportService.generateReportCsv(data);
    final fileName = 'reports_${_mk}_${_selectedTenantId == 'all' ? 'all_tenants' : 'tenant'}.csv';
    await ReportExportService.exportCsv(
      context: context,
      csvContent: csvContent,
      fileName: fileName,
    );
  }

  Future<void> exportPdf() async {
    final s = ref.read(appDataProvider);
    final data = ReportExportService.prepareData(
      state: s,
      monthKey: _mk,
      tenantId: _selectedTenantId,
    );
    final pdfBytes = await ReportExportService.generateReportPdf(data);
    final fileName = 'reports_${_mk}_${_selectedTenantId == 'all' ? 'all_tenants' : 'tenant'}.pdf';
    if (!mounted) return;
    await ReportExportService.exportPdf(
      context: context,
      pdfBytes: pdfBytes,
      fileName: fileName,
    );
  }

  Future<void> printReport() async {
    await exportPdf();
  }

  void _showTenantExportDialog(Tenant tenant) {
    final s = ref.read(appDataProvider);
    showTenantExportDialog(context, tenant, s);
  }

  static void showTenantExportDialog(
      BuildContext context, Tenant tenant, AppDataState s) {
    final history = s.payments
        .where((p) => p.tenantId == tenant.id && p.status == 'paid')
        .toList();
    final isDark = AppColors.isDark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F2324) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Ionicons.receiptOutline, size: 20, color: Color(0xFF059669)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Export ${tenant.name} Statement',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select export action for ${tenant.name} (Unit ${tenant.unit}):',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),
            _dialogActionTile(
              icon: Ionicons.documentOutline,
              color: const Color(0xFF0F766E),
              title: 'Save Statement PDF',
              subtitle: 'Save official high-resolution PDF document',
              onTap: () async {
                Navigator.of(ctx).pop();
                final pdfBytes = await ReportExportService.generateTenantStatementPdf(
                  tenant: tenant,
                  history: history,
                  currency: s.selectedCurrency,
                  propertyManager: s.propertyManager,
                );
                if (context.mounted) {
                  await ReportExportService.exportPdf(
                    context: context,
                    pdfBytes: pdfBytes,
                    fileName: 'Statement_${tenant.name.replaceAll(' ', '_')}.pdf',
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            _dialogActionTile(
              icon: Ionicons.documentTextOutline,
              color: const Color(0xFF10B981),
              title: 'Export Statement CSV',
              subtitle: 'Save spreadsheet with payment transactions',
              onTap: () async {
                Navigator.of(ctx).pop();
                final csv = ReportExportService.generateTenantStatementCsv(
                  tenant: tenant,
                  history: history,
                  currency: s.selectedCurrency,
                  propertyManager: s.propertyManager,
                );
                if (context.mounted) {
                  await ReportExportService.exportCsv(
                    context: context,
                    csvContent: csv,
                    fileName: 'Statement_${tenant.name.replaceAll(' ', '_')}.csv',
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  static Widget _dialogActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = AppColors.isDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color(0xFFE2E8F0),
          ),
          color: isDark ? const Color(0xFF091B1C) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final cur = s.selectedCurrency;
    final year = int.parse(_year);
    final tenantById = {for (final t in s.scopedTenants) t.id: t};

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    // Filtered Rent payments
    final rentRows = <({Tenant tenant, Payment payment})>[];
    for (final p in s.scopedPayments) {
      if (p.status != 'paid') continue;
      if (_selectedTenantId != 'all' && p.tenantId != _selectedTenantId) continue;
      final t = tenantById[p.tenantId];
      if (t == null) continue;
      final pfm = p.paidForMonth ?? p.displayMonth;
      if (pfm == null || pfm.isEmpty) continue;
      final pMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(pfm);
      if (pMatch == null) continue;
      if (pMatch.group(1) == _year && pMatch.group(2) == _month) {
        rentRows.add((tenant: t, payment: p));
      }
    }
    rentRows.sort((a, b) {
      final ua = a.tenant.unit;
      final ub = b.tenant.unit;
      final na = RegExp(r'\d+').firstMatch(ua)?.group(0) ?? '0';
      final nb = RegExp(r'\d+').firstMatch(ub)?.group(0) ?? '0';
      final c = (int.tryParse(na) ?? 0).compareTo(int.tryParse(nb) ?? 0);
      return c != 0 ? c : ua.compareTo(ub);
    });

    // Filtered Expenses
    final expenses = s.scopedExpenses.where((e) {
      if (_selectedTenantId != 'all') return false;
      if (e.status != 'paid') return false;
      final efm = e.expenseForMonth ?? e.displayMonth;
      if (efm == null || efm.isEmpty) return false;
      final eMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(efm);
      if (eMatch == null) return false;
      return eMatch.group(1) == _year && eMatch.group(2) == _month;
    }).toList();

    // Completed Work Orders in the selected month (Scoped)
    final workOrders = s.scopedWorkOrders.where((w) {
      if (w.status != 'completed') return false;
      final raw = (w.completedAt ?? '').trim();
      final stamp = DateTime.tryParse(raw.isNotEmpty ? raw : w.createdAt);
      if (stamp == null) return false;
      return stamp.year == year && stamp.month == int.parse(_month);
    }).toList();

    final totalRent = rentRows.fold<double>(0, (a, r) => a + r.payment.amount);
    final totalExpenses = expenses.fold<double>(0, (a, e) => a + e.amount);
    final totalWork = workOrders.fold<double>(
        0, (a, w) => a + (w.workerCost ?? 0) + (w.productPrice ?? 0));
    final net = totalRent - totalExpenses - totalWork;
    final profitMargin =
        totalRent > 0 ? ((net / totalRent) * 100).clamp(-100.0, 100.0) : 0.0;

    final selectedTenant =
        _selectedTenantId == 'all' ? null : tenantById[_selectedTenantId];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TOP HEADER & CONTROLS (Compact Bar)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isNarrow = constraints.maxWidth < 1200;
                final titleCol = Row(
                  mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Ionicons.barChartOutline,
                          size: 16, color: Color(0xFF10B981)),
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
                                  'Financial Reports & Analytics',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.heading,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color.fromRGBO(255, 255, 255, 0.06)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text(
                                  _reportPeriod == 'annual'
                                      ? 'Annual YTD $_year'
                                      : '${_monthNames[_monthIndex - 1]} $_year',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _reportPeriod == 'annual'
                                ? '12-Month cash flow comparison, operating expenses, and YTD performance'
                                : 'Cash flow, operating expenses, and net profit margins',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final controls = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Period Switcher: Monthly vs Annual YTD
                    _buildPeriodSwitcher(isDark, borderColor),

                    // Month or Year Navigator
                    if (_reportPeriod == 'monthly')
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF091E1F) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Ionicons.chevronBack, size: 13),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              tooltip: 'Previous Month',
                              onPressed: () => _stepMonth(-1),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                '${_monthNames[_monthIndex - 1].substring(0, 3)} $_year',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Ionicons.chevronForward, size: 13),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              tooltip: 'Next Month',
                              onPressed: () => _stepMonth(1),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF091E1F) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Ionicons.chevronBack, size: 13),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              tooltip: 'Previous Year',
                              onPressed: () => _stepYear(-1),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                _year,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Ionicons.chevronForward, size: 13),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              tooltip: 'Next Year',
                              onPressed: () => _stepYear(1),
                            ),
                          ],
                        ),
                      ),

                    // Tenant Filter Dropdown (Compact)
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF091E1F) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: Builder(
                          builder: (context) {
                            final distinctTenants = <Tenant>[];
                            final seenTenantIds = <String>{'all'};
                            for (final t in s.scopedTenants) {
                              if (t.id.isNotEmpty && seenTenantIds.add(t.id)) {
                                distinctTenants.add(t);
                              }
                            }
                            final safeTenantId = seenTenantIds.contains(_selectedTenantId)
                                ? _selectedTenantId
                                : 'all';

                            return DropdownButton<String>(
                              value: safeTenantId,
                              icon: const Icon(Ionicons.chevronDown, size: 12),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.heading,
                              ),
                              dropdownColor:
                                  isDark ? const Color(0xFF0F2627) : Colors.white,
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedTenantId = v);
                              },
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All Tenants & Units'),
                                ),
                                for (final t in distinctTenants)
                                  DropdownMenuItem(
                                    value: t.id,
                                    child: Text('${t.unit} - ${t.name}'),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // Cash Flow Forecast Modal Trigger
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF0F766E),
                        side: BorderSide(
                          color: (isDark ? const Color(0xFF10B981) : const Color(0xFF0F766E))
                              .withValues(alpha: 0.35),
                        ),
                        backgroundColor: (isDark ? const Color(0xFF10B981) : const Color(0xFF0F766E))
                            .withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => DesktopCashFlowModal.show(context),
                      icon: const Icon(Ionicons.trendingUpOutline, size: 13),
                      label: const Text('Cash Flow Forecast',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 4),

                    // Export Actions (Compact)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.heading,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: exportCsv,
                      icon: const Icon(Ionicons.documentTextOutline, size: 13),
                      label: const Text('Export CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: exportPdf,
                      icon: const Icon(Ionicons.documentOutline, size: 13),
                      label: const Text('Save PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleCol,
                    const SizedBox(height: 10),
                    controls,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            if (_reportPeriod == 'annual') ...[
              _buildAnnualSection(s, year, cur, isDark, borderColor),
            ] else ...[
              // 2. EXECUTIVE KPI CARDS (Compact Bento Style)
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isNarrow = constraints.maxWidth < 850;
                  final cards = [
                    _buildKpiCard(
                      'Rent Collected',
                      '$cur ${totalRent.toStringAsFixed(0)}',
                      '${rentRows.length} collection${rentRows.length == 1 ? '' : 's'}',
                      Ionicons.cashOutline,
                      const Color(0xFF10B981),
                      isDark,
                      borderColor,
                    ),
                    _buildKpiCard(
                      'Operating Expenses',
                      '$cur ${totalExpenses.toStringAsFixed(0)}',
                      '${expenses.length} item${expenses.length == 1 ? '' : 's'}',
                      Ionicons.receiptOutline,
                      const Color(0xFF8B5CF6),
                      isDark,
                      borderColor,
                    ),
                    _buildKpiCard(
                      'Maintenance Costs',
                      '$cur ${totalWork.toStringAsFixed(0)}',
                      '${workOrders.length} in $year',
                      Ionicons.constructOutline,
                      const Color(0xFFF59E0B),
                      isDark,
                      borderColor,
                    ),
                    _buildKpiCard(
                      'Net Operating Income',
                      '$cur ${net.toStringAsFixed(0)}',
                      '${profitMargin.toStringAsFixed(1)}% margin',
                      Ionicons.trendingUpOutline,
                      net >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      isDark,
                      borderColor,
                      isPrimary: true,
                    ),
                  ];

                  if (isNarrow) {
                    final itemWidth = ((constraints.maxWidth - 10) / 2).floorToDouble();
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[1]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[2]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[3]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              // 3. TENANT SPECIFIC PROFILE (if single tenant selected)
              if (selectedTenant != null) ...[
                _buildTenantProfileBanner(selectedTenant, rentRows, cur, isDark, borderColor),
                const SizedBox(height: 12),
              ],

              // 4. MAIN TABLES (Rent Roll, Expenses, Maintenance)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF091E1F) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    // Section Tabs Header (Horizontal Scroll)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          _buildSectionTab('all', 'Overview Summary', Ionicons.gridOutline, isDark),
                          const SizedBox(width: 6),
                          _buildSectionTab('rent', 'Rent Roll (${rentRows.length})', Ionicons.cashOutline, isDark),
                          const SizedBox(width: 6),
                          _buildSectionTab('expenses', 'Expenses (${expenses.length})', Ionicons.receiptOutline, isDark),
                          const SizedBox(width: 6),
                          _buildSectionTab('maintenance', 'Maintenance ($year)', Ionicons.constructOutline, isDark),
                          const SizedBox(width: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color.fromRGBO(255, 255, 255, 0.05)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Active Period: ${_monthNames[_monthIndex - 1]} $_year',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),

                    // Tab Contents
                    if (_activeTab == 'all')
                      _buildOverviewTables(rentRows, expenses, workOrders, cur, isDark, borderColor, totalRent, totalExpenses, totalWork, net, profitMargin)
                    else if (_activeTab == 'rent')
                      _buildRentTable(rentRows, cur, isDark, borderColor)
                    else if (_activeTab == 'expenses')
                      _buildExpensesTable(expenses, cur, isDark, borderColor)
                    else
                      _buildMaintenanceTable(workOrders, cur, isDark, borderColor),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSwitcher(bool isDark, Color borderColor) {
    final isMonthly = _reportPeriod == 'monthly';
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _periodSwitcherButton(
            label: 'Monthly',
            icon: Ionicons.calendarOutline,
            isSelected: isMonthly,
            isDark: isDark,
            onTap: () => setState(() => _reportPeriod = 'monthly'),
          ),
          _periodSwitcherButton(
            label: 'Annual / YTD',
            icon: Ionicons.analyticsOutline,
            isSelected: !isMonthly,
            isDark: isDark,
            onTap: () => setState(() => _reportPeriod = 'annual'),
          ),
        ],
      ),
    );
  }

  Widget _periodSwitcherButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F766E) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (AppColors.heading)
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnualSection(
    AppDataState s,
    int year,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    final annualMonths = _computeAnnualMonths(s, year);
    final totalAnnualRent =
        annualMonths.fold<double>(0, (a, m) => a + m.rent);
    final totalAnnualExpenses =
        annualMonths.fold<double>(0, (a, m) => a + m.expenses);
    final totalAnnualMaint =
        annualMonths.fold<double>(0, (a, m) => a + m.maintenance);
    final totalAnnualNet =
        totalAnnualRent - totalAnnualExpenses - totalAnnualMaint;
    final annualMargin = totalAnnualRent > 0
        ? ((totalAnnualNet / totalAnnualRent) * 100).clamp(-100.0, 100.0)
        : 0.0;
    final avgMonthlyNet = totalAnnualNet / 12.0;

    double maxBarVal = 100.0;
    for (final m in annualMonths) {
      if (m.rent > maxBarVal) maxBarVal = m.rent;
      if (m.expenses > maxBarVal) maxBarVal = m.expenses;
      if (m.maintenance > maxBarVal) maxBarVal = m.maintenance;
      if (m.net > maxBarVal) maxBarVal = m.net;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Annual Executive KPI Cards
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isNarrow = constraints.maxWidth < 850;
            final cards = [
              _buildKpiCard(
                'Annual Gross Income',
                '$cur ${totalAnnualRent.toStringAsFixed(0)}',
                'All 12 Months in $year',
                Ionicons.cashOutline,
                const Color(0xFF10B981),
                isDark,
                borderColor,
              ),
              _buildKpiCard(
                'Annual Operating Exp',
                '$cur ${totalAnnualExpenses.toStringAsFixed(0)}',
                'Operating expenses in $year',
                Ionicons.receiptOutline,
                const Color(0xFF8B5CF6),
                isDark,
                borderColor,
              ),
              _buildKpiCard(
                'Annual Maintenance',
                '$cur ${totalAnnualMaint.toStringAsFixed(0)}',
                'Repairs & service orders',
                Ionicons.constructOutline,
                const Color(0xFFF59E0B),
                isDark,
                borderColor,
              ),
              _buildKpiCard(
                'Annual Net Income (NOI)',
                '$cur ${totalAnnualNet.toStringAsFixed(0)}',
                '${annualMargin.toStringAsFixed(1)}% margin • $cur ${avgMonthlyNet.toStringAsFixed(0)}/mo avg',
                Ionicons.trendingUpOutline,
                totalAnnualNet >= 0
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                isDark,
                borderColor,
                isPrimary: true,
              ),
            ];

            if (isNarrow) {
              final itemWidth =
                  ((constraints.maxWidth - 10) / 2).floorToDouble();
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: cards
                    .map((c) => SizedBox(width: itemWidth, child: c))
                    .toList(),
              );
            }

            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
                const SizedBox(width: 10),
                Expanded(child: cards[2]),
                const SizedBox(width: 10),
                Expanded(child: cards[3]),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // 2. Quarterly Performance Breakdown Cards
        _buildQuarterlySection(annualMonths, cur, isDark, borderColor),
        const SizedBox(height: 12),

        // 3. 12-Month Financial Performance & Net Trends Chart
        _build12MonthTrendChart(
            annualMonths, maxBarVal, cur, isDark, borderColor),
        const SizedBox(height: 12),

        // 4. 12-Month Financial Table
        _buildAnnualBreakdownTable(
          annualMonths,
          totalAnnualRent,
          totalAnnualExpenses,
          totalAnnualMaint,
          totalAnnualNet,
          annualMargin,
          cur,
          isDark,
          borderColor,
        ),
      ],
    );
  }

  Widget _buildQuarterlySection(
    List<_AnnualMonthData> months,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    final q1Rent =
        months.sublist(0, 3).fold<double>(0, (a, m) => a + m.rent);
    final q1Exp = months
        .sublist(0, 3)
        .fold<double>(0, (a, m) => a + m.expenses + m.maintenance);
    final q1Net = q1Rent - q1Exp;

    final q2Rent =
        months.sublist(3, 6).fold<double>(0, (a, m) => a + m.rent);
    final q2Exp = months
        .sublist(3, 6)
        .fold<double>(0, (a, m) => a + m.expenses + m.maintenance);
    final q2Net = q2Rent - q2Exp;

    final q3Rent =
        months.sublist(6, 9).fold<double>(0, (a, m) => a + m.rent);
    final q3Exp = months
        .sublist(6, 9)
        .fold<double>(0, (a, m) => a + m.expenses + m.maintenance);
    final q3Net = q3Rent - q3Exp;

    final q4Rent =
        months.sublist(9, 12).fold<double>(0, (a, m) => a + m.rent);
    final q4Exp = months
        .sublist(9, 12)
        .fold<double>(0, (a, m) => a + m.expenses + m.maintenance);
    final q4Net = q4Rent - q4Exp;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isNarrow = constraints.maxWidth < 850;
        final cards = [
          _quarterCard('Q1 (Jan–Mar)', q1Rent, q1Exp, q1Net, cur, isDark, borderColor),
          _quarterCard('Q2 (Apr–Jun)', q2Rent, q2Exp, q2Net, cur, isDark, borderColor),
          _quarterCard('Q3 (Jul–Sep)', q3Rent, q3Exp, q3Net, cur, isDark, borderColor),
          _quarterCard('Q4 (Oct–Dec)', q4Rent, q4Exp, q4Net, cur, isDark, borderColor),
        ];

        if (isNarrow) {
          final itemWidth = ((constraints.maxWidth - 10) / 2).floorToDouble();
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
            const SizedBox(width: 10),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _quarterCard(
    String label,
    double rent,
    double exp,
    double net,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (isPositive
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isPositive ? 'Surplus' : 'Deficit',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isPositive
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$cur ${net.toStringAsFixed(0)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isPositive
                  ? (isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669))
                  : const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'In: $cur ${rent.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Out: $cur ${exp.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _build12MonthTrendChart(
    List<_AnnualMonthData> months,
    double maxBarVal,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Legend
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 680;
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Ionicons.statsChartOutline,
                      size: 16,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '12-Month Financial Performance & Trends ($_year)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                ],
              );
              final legend = Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chartLegendDot('Income', const Color(0xFF10B981), isDark),
                  _chartLegendDot('Expenses', const Color(0xFF8B5CF6), isDark),
                  _chartLegendDot('Maintenance', const Color(0xFFF59E0B), isDark),
                  _chartLegendDot('Net Profit', const Color(0xFF3B82F6), isDark),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    legend,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  legend,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Chart Bars Area
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months) ...[
                  Expanded(
                    child: Tooltip(
                      message:
                          '${m.monthName} $_year\n• Income: $cur ${m.rent.toStringAsFixed(0)}\n• Expenses: $cur ${m.expenses.toStringAsFixed(0)}\n• Maintenance: $cur ${m.maintenance.toStringAsFixed(0)}\n• Net: $cur ${m.net.toStringAsFixed(0)} (${m.margin.toStringAsFixed(1)}%)',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          setState(() {
                            _mk = m.monthKey;
                            _reportPeriod = 'monthly';
                          });
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Bars group
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Rent Bar
                                  _barItem(m.rent, maxBarVal, const Color(0xFF10B981)),
                                  const SizedBox(width: 2),
                                  // Expense Bar
                                  _barItem(m.expenses, maxBarVal, const Color(0xFF8B5CF6)),
                                  const SizedBox(width: 2),
                                  // Maintenance Bar
                                  _barItem(m.maintenance, maxBarVal, const Color(0xFFF59E0B)),
                                  const SizedBox(width: 2),
                                  // Net Bar
                                  _barItem(
                                    m.net.abs(),
                                    maxBarVal,
                                    m.net >= 0 ? const Color(0xFF3B82F6) : const Color(0xFFEF4444),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              m.monthName.substring(0, 3),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegendDot(String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _barItem(double value, double maxVal, Color color) {
    final double pct = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    final double h = (pct * 115).clamp(value > 0 ? 3.0 : 0.0, 115.0);

    return Container(
      width: 5.5,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }

  Widget _buildAnnualBreakdownTable(
    List<_AnnualMonthData> months,
    double totalRent,
    double totalExpenses,
    double totalMaint,
    double totalNet,
    double totalMargin,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '12-Month Cash Flow & Net Operating Income',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Click row to inspect details',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final double tableWidth = math.max(constraints.maxWidth, 720.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      // Columns Header Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: isDark ? const Color(0xFF0C2425) : const Color(0xFFF8FAFC),
                        child: const Row(
                          children: [
                            Expanded(flex: 2, child: Text('Month', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 2, child: Text('Rent Collected', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 2, child: Text('Operating Exp', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 2, child: Text('Maintenance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 2, child: Text('Net NOI', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 1, child: Text('Margin', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            SizedBox(width: 80, child: Text('Action', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                      // 12 Months Rows
                      for (var i = 0; i < months.length; i++) ...[
                        () {
                          final m = months[i];
                          final isPositive = m.net >= 0;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              hoverColor: isDark ? const Color(0xFF133638) : const Color(0xFFF1F5F9),
                              onTap: () {
                                setState(() {
                                  _mk = m.monthKey;
                                  _reportPeriod = 'monthly';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isDark ? const Color.fromRGBO(255, 255, 255, 0.04) : const Color(0xFFF1F5F9),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${m.monthName} $_year',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.heading,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$cur ${m.rent.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$cur ${m.expenses.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$cur ${m.maintenance.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B)),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$cur ${m.net.toStringAsFixed(0)}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isPositive
                                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                              : const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        '${m.margin.toStringAsFixed(0)}%',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Inspect →',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }(),
                      ],
                      // Grand Totals Summary Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        color: isDark ? const Color(0xFF0F2B2C) : const Color(0xFFEDF7F4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Annual Total ($_year)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$cur ${totalRent.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981)),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$cur ${totalExpenses.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6)),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$cur ${totalMaint.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFF59E0B)),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$cur ${totalNet.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: totalNet >= 0
                                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                      : const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${totalMargin.toStringAsFixed(0)}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            const SizedBox(width: 80),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, String sub, IconData icon,
      Color color, bool isDark, Color borderColor, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPrimary
            ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
            : (isDark ? const Color(0xFF091E1F) : Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPrimary
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: isPrimary
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (AppColors.heading),
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTab(String key, String title, IconData icon, bool isDark) {
    final isSelected = _activeTab == key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeTab = key),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTenantProfileBanner(Tenant t,
      List<({Tenant tenant, Payment payment})> rows, String cur, bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                t.name.isNotEmpty ? t.name.substring(0, 1).toUpperCase() : 'T',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'UNIT ${t.unit}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '•  Rent: $cur ${t.rentAmount.toStringAsFixed(0)}/mo  •  Deposit: $cur ${t.deposit?.toStringAsFixed(0) ?? '0'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF06B6D4),
              side: BorderSide(color: const Color(0xFF06B6D4).withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => _showTenantExportDialog(t),
            icon: const Icon(Ionicons.receiptOutline, size: 12),
            label: const Text('Export Statement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTables(
      List<({Tenant tenant, Payment payment})> rentRows,
      List<Expense> expenses,
      List<WorkOrder> workOrders,
      String cur,
      bool isDark,
      Color borderColor,
      double totalRent,
      double totalExpenses,
      double totalWork,
      double net,
      double profitMargin) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            if (wide) {
              return Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildMiniTable(
                        'Rent Collections',
                        rentRows.length,
                        _buildRentTable(rentRows, cur, isDark, borderColor, isMini: true),
                        isDark,
                        borderColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildMiniTable(
                        'Operating Expenses',
                        expenses.length,
                        _buildExpensesTable(expenses, cur, isDark, borderColor, isMini: true),
                        isDark,
                        borderColor,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _buildRentTable(rentRows, cur, isDark, borderColor),
                Divider(height: 1, color: borderColor),
                _buildExpensesTable(expenses, cur, isDark, borderColor),
              ],
            );
          },
        ),

        // Cash Flow Summary Ribbon
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF061819).withValues(alpha: 0.6)
                : const Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              const Icon(Ionicons.calculatorOutline, size: 13, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              Text(
                'Cash Flow:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Rent: +$cur ${totalRent.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      'Expenses: -$cur ${totalExpenses.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                    Text(
                      'Maintenance: -$cur ${totalWork.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    Text(
                      '= Net Income: $cur ${net.toStringAsFixed(0)} (${profitMargin.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: net >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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

  Widget _buildMiniTable(String title, int count, Widget table, bool isDark, Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061819).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isDark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          table,
        ],
      ),
    );
  }

  Widget _buildTableHeader(List<String> titles, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      color: isDark
          ? const Color(0xFF061819).withValues(alpha: 0.7)
          : const Color(0xFFF1F5F9),
      child: Row(
        children: [
          for (int i = 0; i < titles.length; i++)
            Expanded(
              flex: i == 1 ? 2 : 1,
              child: Text(
                titles[i],
                textAlign: i == titles.length - 1 ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRentTable(List<({Tenant tenant, Payment payment})> rows,
      String cur, bool isDark, Color borderColor, {bool isMini = false}) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No rent collections recorded for this period',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (!isMini) _buildTableHeader(['UNIT', 'TENANT & DATE', 'MONTH', 'AMOUNT'], isDark),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
          itemBuilder: (context, i) {
            final r = rows[i];
            final p = r.payment;
            final t = r.tenant;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: isMini ? 10 : 14, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t.unit,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: isMini ? 1 : 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heading,
                          ),
                        ),
                        Text(
                          p.paidDate != null ? 'Paid on ${p.paidDate}' : (p.displayMonth ?? 'Rent Payment'),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMini)
                    Expanded(
                      child: Text(
                        p.paidForMonth ?? 'Rent',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  Text(
                    '$cur ${p.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExpensesTable(List<Expense> list, String cur, bool isDark,
      Color borderColor, {bool isMini = false}) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No expenses recorded for this period',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (!isMini) _buildTableHeader(['CATEGORY', 'DESCRIPTION & DATE', 'STATUS', 'AMOUNT'], isDark),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
          itemBuilder: (context, i) {
            final e = list[i];

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: isMini ? 10 : 14, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.category,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: isMini ? 1 : 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.description.isNotEmpty ? e.description : e.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heading,
                          ),
                        ),
                        Text(
                          e.date,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isMini)
                    Expanded(
                      child: Text(
                        e.status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  Text(
                    '$cur ${e.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMaintenanceTable(List<WorkOrder> list, String cur, bool isDark,
      Color borderColor) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No completed maintenance work orders for $_year',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildTableHeader(['STATUS', 'TITLE & UNIT', 'CATEGORY & WORKER', 'TOTAL COST'], isDark),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
          itemBuilder: (context, i) {
            final w = list[i];
            final totalCost = (w.productPrice ?? 0) + (w.workerCost ?? 0);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  const Icon(Ionicons.checkmarkCircle, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  if (w.unit != null && w.unit!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        w.unit!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF06B6D4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heading,
                          ),
                        ),
                        Text(
                          w.category,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      w.assignedTo.isNotEmpty ? w.assignedTo : 'Unassigned',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Text(
                    '$cur ${totalCost.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
