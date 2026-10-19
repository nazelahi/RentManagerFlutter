import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/models/models.dart';
import '../core/state/app_data.dart';
import '../core/widgets/common.dart';
import 'financial_analytics_service.dart';

/// Service for generating and exporting high-fidelity Executive Cash Flow & Financial Health Forecast PDFs
/// matching the exact visual layout and style of the Desktop Forecast Screen.
class ForecastPdfExportService {
  static Future<void> exportForecastPdf({
    required BuildContext context,
    required AppDataState state,
    required FinancialMetrics metrics,
    required CashFlowForecastResult forecast,
    required int year,
    required int month,
    required int forecastHorizon,
    String? propertyName,
  }) async {
    try {
      final pdfBytes = await generateForecastPdf(
        state: state,
        metrics: metrics,
        forecast: forecast,
        year: year,
        month: month,
        forecastHorizon: forecastHorizon,
        propertyName: propertyName,
      );

      final dateStr = DateFormat('yyyy-MM').format(DateTime(year, month));
      final cleanProp = (propertyName ?? (state.activeProperty?.name ?? 'Property'))
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final fileName = 'CashFlow_Forecast_${cleanProp}_$dateStr.pdf';

      final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

      if (isDesktop) {
        try {
          final uri = await FilePicker.saveFile(
            dialogTitle: 'Save Executive Forecast PDF',
            fileName: fileName,
            bytes: pdfBytes,
          );
          if (uri != null && context.mounted) {
            final filePath = uri.toFilePath();
            showAppToast(
              context,
              'Forecast PDF exported: $fileName',
              isSuccess: true,
              actionLabel: 'Open',
              onAction: () async {
                try {
                  await OpenFilex.open(filePath);
                } catch (_) {}
              },
            );
          }
          return;
        } catch (e) {
          debugPrint('FilePicker saveFile error: $e');
        }
      }

      // Mobile or fallback: share sheet
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Failed to export Forecast PDF: $e', isError: true);
      }
    }
  }

  static Future<void> printForecastPdf({
    required BuildContext context,
    required AppDataState state,
    required FinancialMetrics metrics,
    required CashFlowForecastResult forecast,
    required int year,
    required int month,
    required int forecastHorizon,
    String? propertyName,
  }) async {
    try {
      final pdfBytes = await generateForecastPdf(
        state: state,
        metrics: metrics,
        forecast: forecast,
        year: year,
        month: month,
        forecastHorizon: forecastHorizon,
        propertyName: propertyName,
      );

      await Printing.layoutPdf(
        name: 'Executive_CashFlow_Forecast',
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Print failed: $e', isError: true);
      }
    }
  }

  static Future<Uint8List> generateForecastPdf({
    required AppDataState state,
    required FinancialMetrics metrics,
    required CashFlowForecastResult forecast,
    required int year,
    required int month,
    required int forecastHorizon,
    String? propertyName,
  }) async {
    final pdf = pw.Document();
    final cur = state.selectedCurrency;

    // Load fonts safely with fallback
    pw.Font baseFont;
    pw.Font boldFont;
    try {
      baseFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      baseFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    final theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);

    final resolvedPropertyName = propertyName ??
        (state.activeProperty?.name ?? 'Primary Property');

    final periodLabel = DateFormat('MMMM yyyy').format(DateTime(year, month));
    final targetEndDate = DateTime(year, month + forecastHorizon);
    final horizonRangeLabel =
        '$periodLabel - ${DateFormat('MMMM yyyy').format(targetEndDate)}';

    // Theme Colors matching screen
    final cTeal = PdfColor.fromHex('#0F766E');
    final cEmerald = PdfColor.fromHex('#10B981');
    final cDark = PdfColor.fromHex('#0F172A');
    final cMuted = PdfColor.fromHex('#64748B');
    final cCardBg = PdfColor.fromHex('#F1F5F9');
    final cBorder = PdfColor.fromHex('#E2E8F0');
    final cGreen = PdfColor.fromHex('#059669');
    final cRed = PdfColor.fromHex('#DC2626');
    final cAmber = PdfColor.fromHex('#D97706');
    final cSky = PdfColor.fromHex('#0284C7');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        theme: theme,
        header: (pw.Context ctx) => _buildPdfHeader(
          ctx: ctx,
          propertyName: resolvedPropertyName,
          periodLabel: periodLabel,
          horizon: forecastHorizon,
          horizonRangeLabel: horizonRangeLabel,
          cTeal: cTeal,
          cEmerald: cEmerald,
          cDark: cDark,
          cMuted: cMuted,
          cBorder: cBorder,
        ),
        footer: (pw.Context ctx) => _buildPdfFooter(
          ctx: ctx,
          manager: state.propertyManager,
          cMuted: cMuted,
          cBorder: cBorder,
        ),
        build: (pw.Context ctx) => [
          pw.SizedBox(height: 12),

          // 1. Executive KPI Ribbon (4 Metric Cards matching desktop modal)
          _buildExecutiveKpiRibbon(
            m: metrics,
            cur: cur,
            cCardBg: cCardBg,
            cBorder: cBorder,
            cDark: cDark,
            cMuted: cMuted,
            cGreen: cGreen,
            cRed: cRed,
            cSky: cSky,
            cAmber: cAmber,
          ),
          pw.SizedBox(height: 16),

          // 2. Forecast Summary Stat Pills
          _buildForecastSummaryPills(
            forecast: forecast,
            horizon: forecastHorizon,
            cur: cur,
            cGreen: cGreen,
            cRed: cRed,
            cSky: cSky,
            cBorder: cBorder,
            cCardBg: cCardBg,
          ),
          pw.SizedBox(height: 14),

          // 3. Projected Monthly Cash Flow Table
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'FORWARD $forecastHorizon-MONTH PREDICTIVE CASH FLOW BREAKDOWN',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                  color: cMuted,
                ),
              ),
              pw.Text(
                'Based on active leases & historical recurring operating costs',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: cMuted,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          _buildForecastTable(
            forecast: forecast,
            cur: cur,
            cTeal: cTeal,
            cBorder: cBorder,
            cGreen: cGreen,
            cRed: cRed,
            cMuted: cMuted,
            cDark: cDark,
          ),
          pw.SizedBox(height: 18),

          // 4. Lease Expiry Radar & Pipeline
          _buildLeasePipelineSection(
            forecast: forecast,
            cur: cur,
            cBorder: cBorder,
            cCardBg: cCardBg,
            cDark: cDark,
            cMuted: cMuted,
            cGreen: cGreen,
            cRed: cRed,
            cAmber: cAmber,
          ),
          pw.SizedBox(height: 18),

          // 5. Revenue Waterfall & NOI Formula Breakdown
          _buildSolvencySection(
            m: metrics,
            cur: cur,
            cBorder: cBorder,
            cCardBg: cCardBg,
            cDark: cDark,
            cMuted: cMuted,
            cTeal: cTeal,
            cGreen: cGreen,
            cRed: cRed,
            cSky: cSky,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ==================== PDF HEADER ====================
  static pw.Widget _buildPdfHeader({
    required pw.Context ctx,
    required String propertyName,
    required String periodLabel,
    required int horizon,
    required String horizonRangeLabel,
    required PdfColor cTeal,
    required PdfColor cEmerald,
    required PdfColor cDark,
    required PdfColor cMuted,
    required PdfColor cBorder,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: cBorder, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Icon badge
          pw.Container(
            width: 32,
            height: 32,
            decoration: pw.BoxDecoration(
              color: cTeal,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Center(
              child: pw.Text(
                'RM',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 10),

          // Title & Subtitle
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      'Executive Financial Health & Cash Flow Forecast',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: cDark,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#ECFDF5'),
                        border: pw.Border.all(color: cEmerald, width: 0.8),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Text(
                        'PREDICTIVE ENGINE',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: cTeal,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Scope: $propertyName | Horizon: $horizon Months ($horizonRangeLabel)',
                  style: pw.TextStyle(fontSize: 8.5, color: cMuted),
                ),
              ],
            ),
          ),

          // Meta right
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                periodLabel,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: cTeal,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 8, color: cMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== EXECUTIVE KPI RIBBON ====================
  static pw.Widget _buildExecutiveKpiRibbon({
    required FinancialMetrics m,
    required String cur,
    required PdfColor cCardBg,
    required PdfColor cBorder,
    required PdfColor cDark,
    required PdfColor cMuted,
    required PdfColor cGreen,
    required PdfColor cRed,
    required PdfColor cSky,
    required PdfColor cAmber,
  }) {
    return pw.Row(
      children: [
        // 1. Net Operating Income (NOI)
        pw.Expanded(
          child: _kpiCard(
            title: 'Net Operating Income (NOI)',
            value: '$cur ${m.netOperatingIncome.toStringAsFixed(0)}',
            subtitle: 'Operating Margin: ${m.operatingMargin.toStringAsFixed(1)}%',
            accentColor: m.netOperatingIncome >= 0 ? cGreen : cRed,
            deltaText: m.noiChangePct != null
                ? '${m.noiChangePct! >= 0 ? '+' : ''}${m.noiChangePct!.toStringAsFixed(0)}%'
                : null,
            cCardBg: cCardBg,
            cBorder: cBorder,
            cDark: cDark,
            cMuted: cMuted,
          ),
        ),
        pw.SizedBox(width: 8),

        // 2. Operating Expense Ratio (OER)
        pw.Expanded(
          child: _kpiCard(
            title: 'Operating Expense Ratio (OER)',
            value: '${m.operatingExpenseRatio.toStringAsFixed(1)}%',
            subtitle: m.operatingExpenseRatio <= 35
                ? 'Optimal (<35%)'
                : m.operatingExpenseRatio <= 50
                    ? 'Normal (35-50%)'
                    : 'Elevated (>50%)',
            accentColor: m.operatingExpenseRatio <= 40 ? cSky : cAmber,
            deltaText: m.expenseChangePct != null
                ? '${m.expenseChangePct! >= 0 ? '+' : ''}${m.expenseChangePct!.toStringAsFixed(0)}%'
                : null,
            cCardBg: cCardBg,
            cBorder: cBorder,
            cDark: cDark,
            cMuted: cMuted,
          ),
        ),
        pw.SizedBox(width: 8),

        // 3. Collection Efficiency
        pw.Expanded(
          child: _kpiCard(
            title: 'Collection Efficiency',
            value: '${m.collectionEfficiency.toStringAsFixed(1)}%',
            subtitle: 'On-time: ${m.onTimeRate.toStringAsFixed(0)}% | Pending: $cur ${m.pendingRent.toStringAsFixed(0)}',
            accentColor: m.collectionEfficiency >= 95 ? cGreen : cAmber,
            cCardBg: cCardBg,
            cBorder: cBorder,
            cDark: cDark,
            cMuted: cMuted,
          ),
        ),
        pw.SizedBox(width: 8),

        // 4. Occupancy & Vacancy
        pw.Expanded(
          child: _kpiCard(
            title: 'Occupancy & Vacancy',
            value: '${m.occupancyRate.toStringAsFixed(1)}%',
            subtitle: '${m.occupiedUnits} occupied / ${m.vacantUnits} vacant (Loss: $cur ${m.vacancyLoss.toStringAsFixed(0)})',
            accentColor: m.occupancyRate >= 90 ? cTealColor : cAmber,
            cCardBg: cCardBg,
            cBorder: cBorder,
            cDark: cDark,
            cMuted: cMuted,
          ),
        ),
      ],
    );
  }

  static const cTealColor = PdfColor.fromInt(0xFF0F766E);

  static pw.Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required PdfColor accentColor,
    String? deltaText,
    required PdfColor cCardBg,
    required PdfColor cBorder,
    required PdfColor cDark,
    required PdfColor cMuted,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: pw.BoxDecoration(
        color: cCardBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: cBorder, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 7.8,
                    fontWeight: pw.FontWeight.bold,
                    color: cMuted,
                  ),
                ),
              ),
              if (deltaText != null)
                pw.Text(
                  deltaText,
                  style: pw.TextStyle(
                    fontSize: 7.8,
                    fontWeight: pw.FontWeight.bold,
                    color: accentColor,
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: cDark,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            subtitle,
            maxLines: 1,
            style: pw.TextStyle(fontSize: 7.2, color: cMuted),
          ),
        ],
      ),
    );
  }

  // ==================== FORECAST SUMMARY PILLS ====================
  static pw.Widget _buildForecastSummaryPills({
    required CashFlowForecastResult forecast,
    required int horizon,
    required String cur,
    required PdfColor cGreen,
    required PdfColor cRed,
    required PdfColor cSky,
    required PdfColor cBorder,
    required PdfColor cCardBg,
  }) {
    final avgNet = forecast.totalProjectedNet / horizon;
    return pw.Row(
      children: [
        _pill(
          title: 'Total Projected Inflow',
          value: '$cur ${forecast.totalProjectedInflow.toStringAsFixed(0)}',
          color: cGreen,
          cBorder: cBorder,
          cCardBg: cCardBg,
        ),
        pw.SizedBox(width: 8),
        _pill(
          title: 'Total Projected Outflow',
          value: '$cur ${forecast.totalProjectedOutflow.toStringAsFixed(0)}',
          color: cRed,
          cBorder: cBorder,
          cCardBg: cCardBg,
        ),
        pw.SizedBox(width: 8),
        _pill(
          title: 'Projected Net Surplus',
          value: '${forecast.totalProjectedNet >= 0 ? '+' : '-'}$cur ${forecast.totalProjectedNet.abs().toStringAsFixed(0)}',
          color: forecast.totalProjectedNet >= 0 ? cGreen : cRed,
          cBorder: cBorder,
          cCardBg: cCardBg,
        ),
        pw.SizedBox(width: 8),
        _pill(
          title: 'Avg. Monthly Net Flow',
          value: '${avgNet >= 0 ? '+' : '-'}$cur ${avgNet.abs().toStringAsFixed(0)}/mo',
          color: cSky,
          cBorder: cBorder,
          cCardBg: cCardBg,
        ),
      ],
    );
  }

  static pw.Widget _pill({
    required String title,
    required String value,
    required PdfColor color,
    required PdfColor cBorder,
    required PdfColor cCardBg,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: cCardBg,
          borderRadius: pw.BorderRadius.circular(5),
          border: pw.Border.all(color: cBorder, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#475569'),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FORECAST TABLE ====================
  static pw.Widget _buildForecastTable({
    required CashFlowForecastResult forecast,
    required String cur,
    required PdfColor cTeal,
    required PdfColor cBorder,
    required PdfColor cGreen,
    required PdfColor cRed,
    required PdfColor cMuted,
    required PdfColor cDark,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: cBorder, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: cBorder, width: 0.6),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.0),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FlexColumnWidth(2.2),
          3: pw.FlexColumnWidth(2.2),
          4: pw.FlexColumnWidth(2.2),
          5: pw.FlexColumnWidth(1.8),
        },
        children: [
          // Header Row
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
            ),
            children: [
              _th('MONTH'),
              _th('PROJECTED INFLOW'),
              _th('EST. OPERATING COSTS'),
              _th('PROJECTED NET'),
              _th('CUMULATIVE RESERVE'),
              _th('LEASES AT RISK'),
            ],
          ),

          // Data Rows
          ...forecast.projections.map((p) {
            final isPositive = p.projectedNet >= 0;
            return pw.TableRow(
              children: [
                _td(p.monthLabel, isBold: true, color: cDark),
                _td('$cur ${p.projectedInflow.toStringAsFixed(0)}', color: cGreen, isBold: true),
                _td('$cur ${p.projectedOutflow.toStringAsFixed(0)}', color: cRed, isBold: true),
                _td(
                  '${isPositive ? '+' : '-'}$cur ${p.projectedNet.abs().toStringAsFixed(0)}',
                  color: isPositive ? cGreen : cRed,
                  isBold: true,
                ),
                _td('$cur ${p.cumulativeReserve.toStringAsFixed(0)}', color: cMuted),
                _tdRisk(p.expiringLeasesCount),
              ],
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _th(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#475569'),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static pw.Widget _td(String text, {bool isBold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColor.fromHex('#1E293B'),
        ),
      ),
    );
  }

  static pw.Widget _tdRisk(int expiringCount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      child: expiringCount > 0
          ? pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FEF3C7'),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(
                '$expiringCount Expiring',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#D97706'),
                ),
              ),
            )
          : pw.Text(
              'Stable',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColor.fromHex('#94A3B8'),
              ),
            ),
    );
  }

  // ==================== LEASE PIPELINE SECTION ====================
  static pw.Widget _buildLeasePipelineSection({
    required CashFlowForecastResult forecast,
    required String cur,
    required PdfColor cBorder,
    required PdfColor cCardBg,
    required PdfColor cDark,
    required PdfColor cMuted,
    required PdfColor cGreen,
    required PdfColor cRed,
    required PdfColor cAmber,
  }) {
    final list = forecast.upcomingExpirations;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'UPCOMING LEASE EXPIRATIONS & RENEWAL RADAR (${list.length})',
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
                color: cMuted,
              ),
            ),
            pw.Text(
              'Initiate renewal discussions 60 days before expiration to eliminate vacancy loss',
              style: pw.TextStyle(fontSize: 8, color: cMuted, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        if (list.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: cCardBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: cBorder, width: 0.8),
            ),
            child: pw.Center(
              child: pw.Text(
                'Lease Pipeline Fully Stable - No active leases expiring in the next 120 days.',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: cGreen,
                ),
              ),
            ),
          )
        else
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: cBorder, width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              children: list.take(6).map((item) {
                final t = item.tenant;
                final isCritical = item.urgency == 'critical';
                final isWarning = item.urgency == 'warning';
                final badgeColor = isCritical ? cRed : (isWarning ? cAmber : cGreen);
                final badgeBg = isCritical
                    ? PdfColor.fromHex('#FEE2E2')
                    : (isWarning ? PdfColor.fromHex('#FEF3C7') : PdfColor.fromHex('#ECFDF5'));

                final unitStr = t.unit.trim().toLowerCase().startsWith('unit')
                    ? t.unit.trim()
                    : (t.unit.trim().isNotEmpty ? 'Unit ${t.unit.trim()}' : 'Unit N/A');

                final contact = [t.phone.trim(), t.email.trim()]
                    .where((s) => s.isNotEmpty)
                    .join(' | ');

                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: cBorder, width: 0.5),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: badgeBg,
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                        child: pw.Text(
                          item.urgency.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              t.name,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: cDark,
                              ),
                            ),
                            pw.Text(
                              '$unitStr${contact.isNotEmpty ? ' - $contact' : ''}',
                              style: pw.TextStyle(fontSize: 8, color: cMuted),
                            ),
                          ],
                        ),
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            '$cur ${t.rentAmount.toStringAsFixed(0)} / mo',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: cDark,
                            ),
                          ),
                          pw.Text(
                            'Expires: ${DateFormat('MMM d, yyyy').format(item.expiryDate)} (${item.daysRemaining < 0 ? 'Expired' : '${item.daysRemaining}d left'})',
                            style: pw.TextStyle(fontSize: 7.8, color: cMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ==================== SOLVENCY & WATERFALL SECTION ====================
  static pw.Widget _buildSolvencySection({
    required FinancialMetrics m,
    required String cur,
    required PdfColor cBorder,
    required PdfColor cCardBg,
    required PdfColor cDark,
    required PdfColor cMuted,
    required PdfColor cTeal,
    required PdfColor cGreen,
    required PdfColor cRed,
    required PdfColor cSky,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Revenue & Rent Roll Waterfall
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: cCardBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: cBorder, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'REVENUE & RENT ROLL WATERFALL',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5,
                    color: cMuted,
                  ),
                ),
                pw.SizedBox(height: 8),
                _waterfallRow('Gross Potential Rent (100% Occupancy)', '$cur ${m.grossPotentialRent.toStringAsFixed(0)}', cDark),
                _waterfallRow('(-) Vacancy Loss (${m.vacantUnits} vacant units)', '- $cur ${m.vacancyLoss.toStringAsFixed(0)}', cRed),
                _waterfallRow('(=) Scheduled Active Rent', '$cur ${m.scheduledRent.toStringAsFixed(0)}', cDark, isBold: true),
                _waterfallRow('Pending Arrears (not collected)', '$cur ${m.pendingRent.toStringAsFixed(0)}', cRed),
                _waterfallRow('(=) Actual Collected Rent', '$cur ${m.collectedRent.toStringAsFixed(0)}', cGreen, isBold: true),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Collection Rate: ${m.collectionEfficiency.toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: cDark)),
                    pw.Text('On-Time: ${m.onTimeRate.toStringAsFixed(0)}%', style: pw.TextStyle(fontSize: 8, color: cMuted)),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),

        // Right: Net Operating Income (NOI) Formula
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: cCardBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: cBorder, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NET OPERATING INCOME (NOI) FORMULA',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.5,
                    color: cMuted,
                  ),
                ),
                pw.SizedBox(height: 8),
                _waterfallRow('Gross Operating Revenue (Collected + Deposits)', '$cur ${m.grossRevenue.toStringAsFixed(0)}', cDark),
                _waterfallRow('(-) Operating Expenses (Repairs, Utilities, Bills)', '- $cur ${m.totalOperatingExpenses.toStringAsFixed(0)}', cRed),
                _waterfallRow('(=) Net Operating Income (NOI)', '$cur ${m.netOperatingIncome.toStringAsFixed(0)}', cSky, isBold: true),
                _waterfallRow('Operating Expense Ratio (OER)', '${m.operatingExpenseRatio.toStringAsFixed(1)}%', cDark),
                _waterfallRow('Operating Profit Margin', '${m.operatingMargin.toStringAsFixed(1)}%', cDark),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#ECFDF5'),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: PdfColor.fromHex('#A7F3D0'), width: 0.6),
                  ),
                  child: pw.Text(
                    'Industry Benchmark: Strong residential assets maintain an OER <40% and collection efficiency >95%.',
                    style: pw.TextStyle(fontSize: 7.2, color: cTeal),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _waterfallRow(String label, String value, PdfColor valColor, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColor.fromHex('#334155'),
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.2,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valColor,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PDF FOOTER ====================
  static pw.Widget _buildPdfFooter({
    required pw.Context ctx,
    required PropertyManager? manager,
    required PdfColor cMuted,
    required PdfColor cBorder,
  }) {
    final managerName = manager?.name.isNotEmpty == true ? manager!.name : 'Property Management';
    final contact = [
      manager?.phone.isNotEmpty == true ? manager!.phone : null,
      manager?.email.isNotEmpty == true ? manager!.email : null,
    ].whereType<String>().join(' | ');

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: cBorder, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Financial intelligence verified - Local deterministic cash flow model',
            style: pw.TextStyle(fontSize: 7.5, color: cMuted),
          ),
          pw.Text(
            '$managerName${contact.isNotEmpty ? ' ($contact)' : ''} | Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: cMuted),
          ),
        ],
      ),
    );
  }
}
