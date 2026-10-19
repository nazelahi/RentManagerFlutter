import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/forecast_pdf_export_service.dart';

/// Interactive Executive Financial Health & Predictive Cash Flow Forecast Modal.
class DesktopCashFlowModal extends ConsumerStatefulWidget {
  final int initialYear;
  final int initialMonth;

  const DesktopCashFlowModal({
    super.key,
    required this.initialYear,
    required this.initialMonth,
  });

  static Future<void> show(
    BuildContext context, {
    int? year,
    int? month,
  }) {
    final now = DateTime.now();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      barrierDismissible: true,
      builder: (_) => DesktopCashFlowModal(
        initialYear: year ?? now.year,
        initialMonth: month ?? now.month,
      ),
    );
  }

  @override
  ConsumerState<DesktopCashFlowModal> createState() => _DesktopCashFlowModalState();
}

class _DesktopCashFlowModalState extends ConsumerState<DesktopCashFlowModal> {
  late int _selectedYear;
  late int _selectedMonth;
  int _forecastHorizon = 6; // 6 or 12 months
  int _activeViewTab = 0; // 0: Cash Flow Forecast, 1: Lease Expiry Pipeline, 2: NOI & Efficiency
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
  }

  Future<void> _handleExportPdf(
    AppDataState state,
    FinancialMetrics m,
    CashFlowForecastResult forecast,
  ) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final scopeLabel = _scopeLabel(state);
      await ForecastPdfExportService.exportForecastPdf(
        context: context,
        state: state,
        metrics: m,
        forecast: forecast,
        year: _selectedYear,
        month: _selectedMonth,
        forecastHorizon: _forecastHorizon,
        propertyName: scopeLabel,
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _handlePrintPdf(
    AppDataState state,
    FinancialMetrics m,
    CashFlowForecastResult forecast,
  ) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final scopeLabel = _scopeLabel(state);
      await ForecastPdfExportService.printForecastPdf(
        context: context,
        state: state,
        metrics: m,
        forecast: forecast,
        year: _selectedYear,
        month: _selectedMonth,
        forecastHorizon: _forecastHorizon,
        propertyName: scopeLabel,
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  void _handleCopySummary(FinancialMetrics m, CashFlowForecastResult forecast, String cur) {
    final state = ref.read(appDataProvider);
    final scopeLabel = _scopeLabel(state);
    final buffer = StringBuffer();
    buffer.writeln('=== EXECUTIVE FINANCIAL HEALTH & CASH FLOW FORECAST ===');
    buffer.writeln('Property: $scopeLabel');
    buffer.writeln('Period: ${DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth))}');
    buffer.writeln('Net Operating Income (NOI): $cur ${m.netOperatingIncome.toStringAsFixed(0)} (Margin: ${m.operatingMargin.toStringAsFixed(1)}%)');
    buffer.writeln('Operating Expense Ratio (OER): ${m.operatingExpenseRatio.toStringAsFixed(1)}%');
    buffer.writeln('Collection Efficiency: ${m.collectionEfficiency.toStringAsFixed(1)}% (Collected: $cur ${m.collectedRent.toStringAsFixed(0)} / Due: $cur ${m.scheduledRent.toStringAsFixed(0)})');
    buffer.writeln('Occupancy Rate: ${m.occupancyRate.toStringAsFixed(1)}% (${m.occupiedUnits}/${m.totalUnits} Units)');
    buffer.writeln('\n--- $_forecastHorizon-Month Predictive Forecast ---');
    buffer.writeln('Total Projected Inflow: $cur ${forecast.totalProjectedInflow.toStringAsFixed(0)}');
    buffer.writeln('Total Projected Outflow: $cur ${forecast.totalProjectedOutflow.toStringAsFixed(0)}');
    buffer.writeln('Total Projected Net Cash Flow: $cur ${forecast.totalProjectedNet.toStringAsFixed(0)}');
    buffer.writeln('Upcoming Lease Expirations (90d): ${forecast.upcomingExpirations.length} Tenants');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    showAppToast(context, 'Executive financial summary copied to clipboard', isSuccess: true);
  }

  String _scopeLabel(AppDataState state) =>
      (state.selectedPropertyId == 'all' || state.selectedPropertyId.isEmpty)
          ? 'All Properties (Portfolio)'
          : (state.activeProperty?.name ?? 'All Properties (Portfolio)');

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final cur = state.selectedCurrency;

    final metrics = FinancialAnalyticsService.computeMetrics(
      state: state,
      year: _selectedYear,
      month: _selectedMonth,
    );

    final forecast = FinancialAnalyticsService.computeCashFlowForecast(
      state: state,
      monthsAhead: _forecastHorizon,
      startYear: _selectedYear,
      startMonth: _selectedMonth,
    );

    final borderColor = isDark
        ? const Color(0xFF1E3A3A)
        : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 26),
      child: Container(
        width: 1040,
        height: 720,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF091E20) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. Top Header Bar
            _buildTopBar(isDark, borderColor, metrics, forecast, cur, state),

            // 2. Executive KPI Ribbon
            _buildExecutiveRibbon(metrics, isDark, borderColor, cur),

            // 3. Tab Switcher
            _buildTabSwitcher(isDark, borderColor, forecast.upcomingExpirations.length),

            // 4. Main Tab Content
            Expanded(
              child: _activeViewTab == 0
                  ? _buildForecastView(forecast, isDark, borderColor, cur)
                  : _activeViewTab == 1
                      ? _buildPipelineView(forecast, isDark, borderColor, cur)
                      : _buildEfficiencyView(metrics, isDark, borderColor, cur),
            ),

            // 5. Bottom Status / Action Footer
            _buildFooter(metrics, forecast, isDark, borderColor, cur, state),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    bool isDark,
    Color borderColor,
    FinancialMetrics m,
    CashFlowForecastResult forecast,
    String cur,
    AppDataState state,
  ) {
    final propertyLabel = _scopeLabel(state);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Ionicons.analyticsOutline, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Executive Financial Health & Cash Flow Forecast',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PREDICTIVE ENGINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Net Operating Income (NOI), Operating Expense Ratio (OER), and forward-looking solvency model • $propertyLabel',
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

          // Period selector
          _buildMonthPickerPill(isDark, borderColor),
          const SizedBox(width: 10),

          // Direct Export to PDF in Top Bar
          IconButton(
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10B981),
                    ),
                  )
                : Icon(
                    Ionicons.downloadOutline,
                    size: 18,
                    color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                  ),
            tooltip: 'Export Forecast to PDF',
            splashRadius: 16,
            onPressed: _isExportingPdf
                ? null
                : () => _handleExportPdf(state, m, forecast),
          ),

          // Copy summary
          IconButton(
            icon: Icon(
              Ionicons.copyOutline,
              size: 17,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            tooltip: 'Copy Executive Summary',
            splashRadius: 16,
            onPressed: () => _handleCopySummary(m, forecast, cur),
          ),

          // Close button
          IconButton(
            icon: Icon(
              Ionicons.close,
              size: 18,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            splashRadius: 16,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPickerPill(bool isDark, Color borderColor) {
    final date = DateTime(_selectedYear, _selectedMonth);
    final monthName = DateFormat('MMMM yyyy').format(date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061416) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                final d = DateTime(_selectedYear, _selectedMonth - 1);
                _selectedYear = d.year;
                _selectedMonth = d.month;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2.0),
              child: Icon(Ionicons.chevronBack, size: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              monthName,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.heading,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                final d = DateTime(_selectedYear, _selectedMonth + 1);
                _selectedYear = d.year;
                _selectedMonth = d.month;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2.0),
              child: Icon(Ionicons.chevronForward, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveRibbon(
    FinancialMetrics m,
    bool isDark,
    Color borderColor,
    String cur,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061416) : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          // 1. Net Operating Income (NOI)
          Expanded(
            child: _metricCard(
              title: 'Net Operating Income (NOI)',
              value: '$cur ${m.netOperatingIncome.toStringAsFixed(0)}',
              subtitle: 'Operating Margin: ${m.operatingMargin.toStringAsFixed(1)}%',
              icon: Ionicons.cashOutline,
              accentColor: m.netOperatingIncome >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              isDark: isDark,
              deltaPct: m.noiChangePct,
            ),
          ),
          const SizedBox(width: 10),

          // 2. Operating Expense Ratio (OER)
          Expanded(
            child: _metricCard(
              title: 'Operating Expense Ratio (OER)',
              value: '${m.operatingExpenseRatio.toStringAsFixed(1)}%',
              subtitle: m.operatingExpenseRatio <= 35
                  ? 'Optimal performance (<35%)'
                  : m.operatingExpenseRatio <= 50
                      ? 'Normal benchmark (35-50%)'
                      : 'Elevated expenses (>50%)',
              icon: Ionicons.pieChartOutline,
              accentColor: m.operatingExpenseRatio <= 40 ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B),
              isDark: isDark,
              deltaPct: m.expenseChangePct != null ? -m.expenseChangePct! : null,
            ),
          ),
          const SizedBox(width: 10),

          // 3. Collection Efficiency
          Expanded(
            child: _metricCard(
              title: 'Collection Efficiency',
              value: '${m.collectionEfficiency.toStringAsFixed(1)}%',
              subtitle: 'On-time rate: ${m.onTimeRate.toStringAsFixed(0)}% | Pending: $cur ${m.pendingRent.toStringAsFixed(0)}',
              icon: Ionicons.checkmarkDoneCircleOutline,
              accentColor: m.collectionEfficiency >= 95 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),

          // 4. Occupancy & Vacancy
          Expanded(
            child: _metricCard(
              title: 'Occupancy & Vacancy',
              value: '${m.occupancyRate.toStringAsFixed(1)}%',
              subtitle: '${m.occupiedUnits} occupied | ${m.vacantUnits} vacant (Loss: $cur ${m.vacancyLoss.toStringAsFixed(0)})',
              icon: Ionicons.businessOutline,
              accentColor: m.occupancyRate >= 90 ? const Color(0xFF6366F1) : const Color(0xFFF59E0B),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    double? deltaPct,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B2224) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF16383A) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accentColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ),
              if (deltaPct != null) ...[
                const SizedBox(width: 4),
                Icon(
                  deltaPct >= 0 ? Ionicons.arrowUp : Ionicons.arrowDown,
                  size: 9.5,
                  color: deltaPct >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                Text(
                  '${deltaPct.abs().toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: deltaPct >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(bool isDark, Color borderColor, int pipelineCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tabPill(
                    index: 0,
                    label: 'Predictive Cash Flow',
                    icon: Ionicons.trendingUpOutline,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 6),
                  _tabPill(
                    index: 1,
                    label: 'Lease Renewal Pipeline ($pipelineCount)',
                    icon: Ionicons.timeOutline,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 6),
                  _tabPill(
                    index: 2,
                    label: 'NOI & Solvency Breakdown',
                    icon: Ionicons.layersOutline,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Horizon toggle (only visible on forecast tab)
          if (_activeViewTab == 0)
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF061416) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _horizonSegmentPill(6, '6 Months', isDark),
                  _horizonSegmentPill(12, '12 Months', isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required int index,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _activeViewTab == index;
    return InkWell(
      onTap: () => setState(() => _activeViewTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F766E).withValues(alpha: isDark ? 0.25 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? const Color(0xFF0F766E)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _horizonSegmentPill(int months, String label, bool isDark) {
    final isSelected = _forecastHorizon == months;
    return InkWell(
      onTap: () => setState(() => _forecastHorizon = months),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F766E) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  // ==================== TAB 1: FORECAST VIEW ====================

  Widget _buildForecastView(
    CashFlowForecastResult forecast,
    bool isDark,
    Color borderColor,
    String cur,
  ) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Visual Forecast Chart Header & Summary Row
          Row(
            children: [
              _forecastSummaryPill(
                title: 'Total Projected Inflow',
                value: '$cur ${forecast.totalProjectedInflow.toStringAsFixed(0)}',
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _forecastSummaryPill(
                title: 'Total Projected Outflow',
                value: '$cur ${forecast.totalProjectedOutflow.toStringAsFixed(0)}',
                color: const Color(0xFFEF4444),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _forecastSummaryPill(
                title: 'Projected Net Surplus',
                value: '${forecast.totalProjectedNet >= 0 ? '+' : '-'}$cur ${forecast.totalProjectedNet.abs().toStringAsFixed(0)}',
                color: forecast.totalProjectedNet >= 0
                    ? const Color(0xFF059669)
                    : const Color(0xFFDC2626),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _forecastSummaryPill(
                title: 'Avg. Monthly Net Flow',
                value: '${(forecast.totalProjectedNet / _forecastHorizon) >= 0 ? '+' : '-'}$cur ${(forecast.totalProjectedNet / _forecastHorizon).abs().toStringAsFixed(0)}/mo',
                color: const Color(0xFF38BDF8),
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Visual Bar Comparison Chart
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B2224) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: _buildVisualBarChart(forecast, isDark, cur),
            ),
          ),
          const SizedBox(height: 14),

          // Data Table
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B2224) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildForecastTable(forecast, isDark, borderColor, cur),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _forecastSummaryPill({
    required String title,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.25),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualBarChart(CashFlowForecastResult forecast, bool isDark, String cur) {
    final maxAmount = forecast.projections.fold<double>(
      1000.0,
      (max, p) => math.max(max, math.max(p.projectedInflow, p.projectedOutflow)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _chartLegendItem('Projected Inflow', const Color(0xFF10B981), isDark),
                const SizedBox(width: 14),
                _chartLegendItem('Projected Outflow', const Color(0xFFEF4444), isDark),
                const SizedBox(width: 14),
                _chartLegendItem('Net Margin', const Color(0xFF0EA5E9), isDark),
              ],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Forward $_forecastHorizon-Month Projection (Based on current active leases & historical recurring costs)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: forecast.projections.map((p) {
              final inHeightFactor = p.projectedInflow > 0
                  ? (p.projectedInflow / maxAmount).clamp(0.06, 1.0)
                  : 0.0;
              final outHeightFactor = p.projectedOutflow > 0
                  ? (p.projectedOutflow / maxAmount).clamp(0.06, 1.0)
                  : 0.0;
              final isPositive = p.projectedNet >= 0;
              final absNet = p.projectedNet.abs();
              final netStr = absNet >= 1000
                  ? '${isPositive ? '+' : '-'}$cur${(absNet / 1000).toStringAsFixed(1)}k'
                  : '${isPositive ? '+' : '-'}$cur${absNet.toStringAsFixed(0)}';

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Net indicator pill on top
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (isPositive
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444))
                              .withValues(alpha: isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          netStr,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Dual Bars (anchored to bottom)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Inflow bar
                            Expanded(
                              child: FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor: inHeightFactor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF047857), Color(0xFF10B981)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),

                            // Outflow bar
                            Expanded(
                              child: FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor: outHeightFactor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Month Label
                      Text(
                        p.monthLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _chartLegendItem(String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4.5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildForecastTable(
    CashFlowForecastResult forecast,
    bool isDark,
    Color borderColor,
    String cur,
  ) {
    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: isDark ? const Color(0xFF07191A) : const Color(0xFFF1F5F9),
          child: Row(
            children: const [
              Expanded(flex: 2, child: Text('MONTH', style: _tableHeaderStyle)),
              Expanded(flex: 2, child: Text('PROJECTED INFLOW', style: _tableHeaderStyle)),
              Expanded(flex: 2, child: Text('EST. OPERATING COSTS', style: _tableHeaderStyle)),
              Expanded(flex: 2, child: Text('PROJECTED NET', style: _tableHeaderStyle)),
              Expanded(flex: 2, child: Text('CUMULATIVE RESERVE', style: _tableHeaderStyle)),
              Expanded(flex: 2, child: Text('LEASES AT RISK', style: _tableHeaderStyle)),
            ],
          ),
        ),

        // Table Rows
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: forecast.projections.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
            itemBuilder: (ctx, idx) {
              final p = forecast.projections[idx];
              final isPositive = p.projectedNet >= 0;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.monthLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$cur ${p.projectedInflow.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$cur ${p.projectedOutflow.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${isPositive ? '+' : ''}$cur ${p.projectedNet.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$cur ${p.cumulativeReserve.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: p.expiringLeasesCount > 0
                          ? Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${p.expiringLeasesCount} Expiring',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Stable',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== TAB 2: PIPELINE VIEW ====================

  Widget _buildPipelineView(
    CashFlowForecastResult forecast,
    bool isDark,
    Color borderColor,
    String cur,
  ) {
    final list = forecast.upcomingExpirations;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Ionicons.checkmarkCircleOutline,
              size: 48,
              color: const Color(0xFF10B981).withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            Text(
              'Lease Pipeline Fully Stable',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No active leases expiring in the next 120 days. Occupancy is secure.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UPCOMING LEASE EXPIRATIONS & RENEWAL RADAR (${list.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Proactively initiate renewal discussions 60 days before expiration to eliminate vacancy loss',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final item = list[i];
                final t = item.tenant;
                final isCritical = item.urgency == 'critical';
                final isWarning = item.urgency == 'warning';
                final badgeColor = isCritical
                    ? const Color(0xFFEF4444)
                    : isWarning
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981);

                final unitStr = t.unit.trim().toLowerCase().startsWith('unit')
                    ? t.unit.trim()
                    : (t.unit.trim().isNotEmpty ? 'Unit ${t.unit.trim()}' : 'Unit N/A');

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0B2224) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCritical
                          ? badgeColor.withValues(alpha: 0.5)
                          : borderColor,
                      width: isCritical ? 1.2 : 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Ionicons.alertOutline, size: 16, color: badgeColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.heading,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Builder(
                              builder: (_) {
                                final contact = [t.phone.trim(), t.email.trim()]
                                    .where((s) => s.isNotEmpty)
                                    .join(' • ');
                                return Text(
                                  '$unitStr${contact.isNotEmpty ? ' • $contact' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$cur ${t.rentAmount.toStringAsFixed(0)} / mo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Expires: ${DateFormat('MMM d, yyyy').format(item.expiryDate)}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.daysRemaining < 0
                              ? 'Expired (${item.daysRemaining.abs()}d ago)'
                              : '${item.daysRemaining} Days Left',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 3: EFFICIENCY VIEW ====================

  Widget _buildEfficiencyView(
    FinancialMetrics m,
    bool isDark,
    Color borderColor,
    String cur,
  ) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Left: Rent Potential vs Collection Waterfall
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B2224) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'REVENUE & RENT ROLL WATERFALL',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _breakdownRow('Gross Potential Rent (100% Occupancy)', '$cur ${m.grossPotentialRent.toStringAsFixed(0)}', isDark),
                  _breakdownRow('(-) Vacancy Loss (${m.vacantUnits} vacant units)', '- $cur ${m.vacancyLoss.toStringAsFixed(0)}', isDark, isDeduction: true),
                  _breakdownRow('(=) Scheduled Active Rent', '$cur ${m.scheduledRent.toStringAsFixed(0)}', isDark, isHighlight: true),
                  _breakdownRow('(-) Outstanding / Pending Arrears', '- $cur ${m.pendingRent.toStringAsFixed(0)}', isDark, isDeduction: true),
                  _breakdownRow('(=) Actual Collected Rent', '$cur ${m.collectedRent.toStringAsFixed(0)}', isDark, isHighlight: true, highlightColor: const Color(0xFF10B981)),
                  const Spacer(),
                  // Efficiency Bar
                  Text(
                    'Collection Rate: ${m.collectionEfficiency.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (m.collectionEfficiency / 100.0).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: isDark ? const Color(0xFF133233) : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Right: Operating Expense Ratio & NOI Performance
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B2224) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'NET OPERATING INCOME (NOI) FORMULA',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _breakdownRow('Gross Operating Revenue (Collected + Deposits)', '$cur ${m.grossRevenue.toStringAsFixed(0)}', isDark),
                  _breakdownRow('(-) Operating Expenses (Repairs, Utilities, Bills)', '- $cur ${m.totalOperatingExpenses.toStringAsFixed(0)}', isDark, isDeduction: true),
                  const Divider(height: 20),
                  _breakdownRow('(=) Net Operating Income (NOI)', '$cur ${m.netOperatingIncome.toStringAsFixed(0)}', isDark, isHighlight: true, highlightColor: const Color(0xFF0EA5E9)),
                  _breakdownRow('Operating Expense Ratio (OER)', '${m.operatingExpenseRatio.toStringAsFixed(1)}%', isDark),
                  _breakdownRow('Operating Profit Margin', '${m.operatingMargin.toStringAsFixed(1)}%', isDark),
                  const Spacer(),
                  // Benchmark info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: isDark ? 0.20 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'Industry Benchmark: Strong residential properties maintain an OER below 40% and a collection efficiency above 95%.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(
    String label,
    String value,
    bool isDark, {
    bool isDeduction = false,
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                color: isHighlight
                    ? (AppColors.heading)
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: highlightColor ??
                  (isDeduction
                      ? const Color(0xFFEF4444)
                      : isHighlight
                          ? (AppColors.heading)
                          : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155))),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FOOTER ====================

  Widget _buildFooter(
    FinancialMetrics m,
    CashFlowForecastResult forecast,
    bool isDark,
    Color borderColor,
    String cur,
    AppDataState state,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061416) : const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Ionicons.shieldCheckmarkOutline,
                  size: 14,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Financial intelligence verified • Local deterministic cash flow model',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              // 1. Direct PDF Export
              FilledButton.icon(
                onPressed: _isExportingPdf ? null : () => _handleExportPdf(state, m, forecast),
                icon: _isExportingPdf
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Ionicons.downloadOutline, size: 14),
                label: Text(_isExportingPdf ? 'Exporting PDF...' : 'Export to PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),

              // 2. Print / Preview
              OutlinedButton.icon(
                onPressed: _isExportingPdf ? null : () => _handlePrintPdf(state, m, forecast),
                icon: const Icon(Ionicons.printOutline, size: 14),
                label: const Text('Print'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.heading,
                  side: BorderSide(color: borderColor, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),

              // 3. Copy Summary
              OutlinedButton.icon(
                onPressed: () => _handleCopySummary(m, forecast, cur),
                icon: const Icon(Ionicons.copyOutline, size: 14),
                label: const Text('Copy Summary'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.heading,
                  side: BorderSide(color: borderColor, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),

              // 4. Close / Done
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  side: BorderSide(color: borderColor, width: 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _tableHeaderStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.5,
  color: Color(0xFF64748B),
);
