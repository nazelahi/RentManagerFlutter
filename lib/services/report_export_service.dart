import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/models.dart';
import '../core/state/app_data.dart';
import '../core/widgets/common.dart';

class ReportExportData {
  final String monthKey;
  final String year;
  final String month;
  final String monthName;
  final String tenantId;
  final Tenant? selectedTenant;
  final PropertyManager? propertyManager;
  final List<({Tenant tenant, Payment payment})> rentRows;
  final List<Expense> expenses;
  final List<WorkOrder> workOrders;
  final double totalRent;
  final double totalExpenses;
  final double totalWork;
  final double net;
  final String currency;

  ReportExportData({
    required this.monthKey,
    required this.year,
    required this.month,
    required this.monthName,
    required this.tenantId,
    required this.selectedTenant,
    this.propertyManager,
    required this.rentRows,
    required this.expenses,
    required this.workOrders,
    required this.totalRent,
    required this.totalExpenses,
    required this.totalWork,
    required this.net,
    required this.currency,
  });
}

class ReportExportService {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String getMonthName(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length >= 2) {
      final m = int.tryParse(parts[1]) ?? 1;
      final y = parts[0];
      return '${_monthNames[(m - 1).clamp(0, 11)]} $y';
    }
    return monthKey;
  }

  static ReportExportData prepareData({
    required AppDataState state,
    required String monthKey,
    String tenantId = 'all',
  }) {
    final parts = monthKey.split('-');
    final yearStr = parts.isNotEmpty ? parts[0] : DateTime.now().year.toString();
    final monthStr = parts.length > 1 ? parts[1] : DateTime.now().month.toString().padLeft(2, '0');
    final monthName = getMonthName(monthKey);
    final cur = state.selectedCurrency;
    final year = int.tryParse(yearStr) ?? DateTime.now().year;
    final monthNum = int.tryParse(monthStr) ?? DateTime.now().month;
    final tenantById = {for (final t in state.scopedTenants) t.id: t};

    // Filter Rent (Scoped)
    final rentRows = <({Tenant tenant, Payment payment})>[];
    for (final p in state.scopedPayments) {
      if (p.status != 'paid') continue;
      if (tenantId != 'all' && p.tenantId != tenantId) continue;
      final t = tenantById[p.tenantId];
      if (t == null) continue;
      final pfm = p.paidForMonth ?? p.displayMonth;
      if (pfm == null || pfm.isEmpty) continue;
      final pMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(pfm);
      if (pMatch == null) continue;
      if (pMatch.group(1) == yearStr && pMatch.group(2) == monthStr) {
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

    // Filter Expenses (Scoped)
    final expenses = state.scopedExpenses.where((e) {
      if (tenantId != 'all') return false;
      if (e.status != 'paid') return false;
      final efm = e.expenseForMonth ?? e.displayMonth;
      if (efm == null || efm.isEmpty) return false;
      final eMatch = RegExp(r'^(\d{4})-(\d{2})').firstMatch(efm);
      if (eMatch == null) return false;
      return eMatch.group(1) == yearStr && eMatch.group(2) == monthStr;
    }).toList();

    // Filter Work Orders (Scoped) — count work completed in THIS month only
    final workOrders = state.scopedWorkOrders.where((w) {
      if (w.status != 'completed') return false;
      if (tenantId != 'all' && w.tenantId != tenantId) return false;
      final doneStamp = w.completedAt != null && w.completedAt!.trim().isNotEmpty
          ? DateTime.tryParse(w.completedAt!.trim())
          : null;
      final stamp = doneStamp ?? DateTime.tryParse(w.createdAt);
      if (stamp == null) return false;
      return stamp.year == year && stamp.month == monthNum;
    }).toList();

    final totalRent = rentRows.fold<double>(0, (a, r) => a + r.payment.amount);
    final totalExpenses = expenses.fold<double>(0, (a, e) => a + e.amount);
    final totalWork = workOrders.fold<double>(
        0, (a, w) => a + (w.workerCost ?? 0) + (w.productPrice ?? 0));
    final net = totalRent - totalExpenses - totalWork;

    final selectedTenant = tenantId == 'all' ? null : tenantById[tenantId];

    return ReportExportData(
      monthKey: monthKey,
      year: yearStr,
      month: monthStr,
      monthName: monthName,
      tenantId: tenantId,
      selectedTenant: selectedTenant,
      propertyManager: state.propertyManager != null
          ? (state.activeProperty != null
              ? state.propertyManager!.copyWith(
                  propertyName: state.activeProperty!.name,
                  address: state.activeProperty!.address.isNotEmpty
                      ? state.activeProperty!.address
                      : state.propertyManager!.address,
                )
              : state.propertyManager)
          : null,
      rentRows: rentRows,
      expenses: expenses,
      workOrders: workOrders,
      totalRent: totalRent,
      totalExpenses: totalExpenses,
      totalWork: totalWork,
      net: net,
      currency: cur,
    );
  }

  // ==================== CSV GENERATION ====================

  static String _formatCsvRow(List<String> cells, int targetCols) {
    final padded = List<String>.from(cells);
    while (padded.length < targetCols) {
      padded.add('');
    }
    if (padded.length > targetCols) {
      padded.length = targetCols;
    }
    String safe(String c) {
      final t = c.replaceAll('\r', ' ').trim();
      if (t.isNotEmpty && const ['=', '+', '-', '@', '\t'].any(t.startsWith)) {
        // Prefix a `'` so spreadsheet apps treat it as text, not a formula.
        return "'$c";
      }
      return c;
    }
    return padded.map((c) => '"${safe(c).replaceAll('"', '""')}"').join(',');
  }

  static String generateReportCsv(ReportExportData data) {
    const colCount = 9;
    final now = DateTime.now();
    final cur = data.currency;
    final prop = data.propertyManager;
    final propName = prop?.propertyName?.trim();
    final hasPropName = propName != null && propName.isNotEmpty;
    final propAddress = prop?.address.trim();
    final hasPropAddress = propAddress != null && propAddress.isNotEmpty;

    final csvRows = <List<String>>[
      // Document Header
      ['RentManager - Property Management Report'],
      ['Report Period', data.monthName],
      ['Generated At', DateFormat('yyyy-MM-dd HH:mm:ss').format(now)],
      ['Currency Unit', cur],
      [
        'Scope',
        data.selectedTenant != null
            ? '${data.selectedTenant!.name} (${data.selectedTenant!.unit})'
            : 'All Tenants',
      ],
      if (hasPropName) ['Property: $propName', propName],
      if (hasPropAddress) ['Address: $propAddress', propAddress],
      if (prop?.ownerName != null && prop!.ownerName!.trim().isNotEmpty)
        ['Owner: ${prop.ownerName!.trim()}', prop.ownerName!.trim()],
      if (prop != null && prop.name.trim().isNotEmpty)
        [
          'Manager: ${prop.name.trim()}',
          '${prop.name.trim()}${prop.phone.trim().isNotEmpty ? ' (${prop.phone.trim()})' : ''}',
        ],
      [],

      // Section 1: Financial Summary
      ['FINANCIAL SUMMARY'],
      ['Summary Metric', 'Amount ($cur)', 'Transaction Count / Details'],
      [
        'Total Rent Collected',
        data.totalRent.toStringAsFixed(2),
        '${data.rentRows.length} rent payment(s)',
      ],
      [
        'Total Expenses',
        data.totalExpenses.toStringAsFixed(2),
        '${data.expenses.length} operating expense(s)',
      ],
      [
        'Work Order Costs',
        data.totalWork.toStringAsFixed(2),
        '${data.workOrders.length} completed work order(s)',
      ],
      [
        'Net Operating Income (NOI)',
        data.net.toStringAsFixed(2),
        'Total Rent - Operating Expenses - Work Orders',
      ],
      [],

      // Section 2: Itemized Transactions Table
      ['ITEMIZED TRANSACTIONS'],
      [
        'Type',
        'Tenant / Assigned To',
        'Unit',
        'Description / Title',
        'Category',
        'Amount ($cur)',
        'Date',
        'Status',
        'Notes',
      ],
      for (final r in data.rentRows)
        [
          'Rent',
          r.tenant.name,
          r.tenant.unit.isNotEmpty ? r.tenant.unit : 'N/A',
          'Rent for ${r.payment.displayMonth ?? r.payment.paidForMonth ?? 'Period'}',
          'Rent Payment',
          r.payment.amount.toStringAsFixed(2),
          r.payment.paidDate ?? '—',
          r.payment.status.toUpperCase(),
          r.payment.notes ?? '—',
        ],
      for (final e in data.expenses)
        [
          'Expense',
          'N/A',
          'N/A',
          e.description,
          e.category,
          e.amount.toStringAsFixed(2),
          e.date,
          e.status.toUpperCase(),
          '—',
        ],
      for (final w in data.workOrders)
        [
          'Work Order',
          w.assignedTo.isNotEmpty ? w.assignedTo : 'Unassigned',
          w.unit != null && w.unit!.isNotEmpty ? w.unit! : 'N/A',
          w.title,
          w.category,
          ((w.workerCost ?? 0) + (w.productPrice ?? 0)).toStringAsFixed(2),
          w.dueDate,
          w.status.toUpperCase(),
          w.description,
        ],
      [],

      // Grand Totals at bottom
      [
        'SUBTOTAL: RENT',
        '',
        '',
        '',
        '',
        data.totalRent.toStringAsFixed(2),
        '',
        '',
        '',
      ],
      [
        'SUBTOTAL: EXPENSES',
        '',
        '',
        '',
        '',
        data.totalExpenses.toStringAsFixed(2),
        '',
        '',
        '',
      ],
      [
        'SUBTOTAL: WORK ORDERS',
        '',
        '',
        '',
        '',
        data.totalWork.toStringAsFixed(2),
        '',
        '',
        '',
      ],
      [
        'NET OPERATING BALANCE',
        '',
        '',
        '',
        '',
        data.net.toStringAsFixed(2),
        '',
        '',
        '',
      ],
    ];

    final buffer = StringBuffer();
    // UTF-8 BOM so Excel & Numbers open with proper character encoding
    buffer.write('\uFEFF');
    for (final row in csvRows) {
      buffer.writeln(_formatCsvRow(row, colCount));
    }
    return buffer.toString();
  }

  static String generateTenantStatementCsv({
    required Tenant tenant,
    required List<Payment> history,
    required String currency,
    PropertyManager? propertyManager,
  }) {
    const colCount = 6;
    final now = DateTime.now();
    final totalPaid = history
        .where((p) => p.status == 'paid')
        .fold<double>(0, (a, p) => a + p.amount);
    final prop = propertyManager;
    final propName = prop?.propertyName?.trim();
    final hasPropName = propName != null && propName.isNotEmpty;
    final propAddress = prop?.address.trim();
    final hasPropAddress = propAddress != null && propAddress.isNotEmpty;

    final csvRows = <List<String>>[
      // Document Header
      ['RentManager - Tenant Rent History Statement'],
      [],

      // Premises & Property Details
      ['PROPERTY & PREMISES DETAILS'],
      ['Property: ${hasPropName ? propName : 'Premises'}', hasPropName ? propName : '—'],
      if (hasPropAddress) ['Address: $propAddress', propAddress],
      if (prop?.ownerName != null && prop!.ownerName!.trim().isNotEmpty)
        ['Owner: ${prop.ownerName!.trim()}', prop.ownerName!.trim()],
      if (prop != null && prop.name.trim().isNotEmpty)
        [
          'Manager: ${prop.name.trim()}',
          '${prop.name.trim()}${prop.phone.trim().isNotEmpty ? ' (${prop.phone.trim()})' : ''}',
        ],
      if (prop != null && prop.email.trim().isNotEmpty)
        ['Manager Email', prop.email.trim()],
      [],

      // Tenant & Lease Summary
      ['TENANT & LEASE SUMMARY'],
      ['Tenant Name', tenant.name],
      ['Assigned Space', 'Unit ${tenant.unit.isNotEmpty ? tenant.unit : 'N/A'}'],
      if (tenant.phone.isNotEmpty) ['Phone', tenant.phone],
      if (tenant.email.isNotEmpty) ['Email', tenant.email],
      if (tenant.address != null && tenant.address!.trim().isNotEmpty)
        ['Permanent Address', tenant.address!.trim()],
      ['Lease Status', tenant.status.toUpperCase()],
      ['Lease Start Date', _formatPdfDate(tenant.leaseStartDate ?? tenant.joinDate)],
      ['Monthly Rent Rate', tenant.rentAmount.toStringAsFixed(2)],
      ['Security Deposit Held', (tenant.deposit ?? 0).toStringAsFixed(2)],
      ['Total Rent Paid to Date', totalPaid.toStringAsFixed(2)],
      ['Statement Generated', DateFormat('yyyy-MM-dd HH:mm:ss').format(now)],
      [],

      // Payment History
      ['PAYMENT RECORDS'],
      [
        '#',
        'Period / Month',
        'Paid Date',
        'Amount ($currency)',
        'Status',
        'Notes',
      ],
      for (int i = 0; i < history.length; i++)
        [
          '${i + 1}',
          history[i].displayMonth ?? history[i].paidForMonth ?? 'Rent Payment',
          _formatPdfDate(history[i].paidDate),
          history[i].amount.toStringAsFixed(2),
          history[i].status.toUpperCase(),
          (history[i].notes != null && history[i].notes!.isNotEmpty)
              ? history[i].notes!
              : '—',
        ],
      [],

      // Summary Total Row
      [
        'TOTAL PAID RECORDED',
        '${history.length} Completed Payment(s)',
        '',
        totalPaid.toStringAsFixed(2),
        'RECONCILED',
        'Official Account Record',
      ],
    ];

    final buffer = StringBuffer();
    // UTF-8 BOM so Excel & Numbers open with proper character encoding
    buffer.write('\uFEFF');
    for (final row in csvRows) {
      buffer.writeln(_formatCsvRow(row, colCount));
    }
    return buffer.toString();
  }

  static Future<_PdfThemeConfig> _getPdfTheme() async {
    try {
      final base = await PdfGoogleFonts.robotoRegular();
      final bold = await PdfGoogleFonts.robotoBold();
      final italic = await PdfGoogleFonts.robotoItalic();
      final boldItalic = await PdfGoogleFonts.robotoBoldItalic();

      final fallbacks = <pw.Font>[];
      bool hasBengaliFallback = false;
      try {
        final bengali = await PdfGoogleFonts.notoSansBengaliRegular();
        if (!bengali.fontName.toLowerCase().contains('helvetica')) {
          fallbacks.add(bengali);
          hasBengaliFallback = true;
        }
      } catch (_) {}
      try {
        final bengaliBold = await PdfGoogleFonts.notoSansBengaliBold();
        if (!bengaliBold.fontName.toLowerCase().contains('helvetica')) {
          fallbacks.add(bengaliBold);
          hasBengaliFallback = true;
        }
      } catch (_) {}
      try {
        final devanagari = await PdfGoogleFonts.notoSansDevanagariRegular();
        if (!devanagari.fontName.toLowerCase().contains('helvetica')) {
          fallbacks.add(devanagari);
        }
      } catch (_) {}
      try {
        final notoSans = await PdfGoogleFonts.notoSansRegular();
        if (!notoSans.fontName.toLowerCase().contains('helvetica')) {
          fallbacks.add(notoSans);
        }
      } catch (_) {}

      final hasFallbacks = fallbacks.isNotEmpty;
      return _PdfThemeConfig(
        theme: pw.ThemeData.withFont(
          base: base,
          bold: bold,
          italic: italic,
          boldItalic: boldItalic,
          fontFallback: hasFallbacks ? fallbacks : null,
        ),
        hasBengaliFallback: hasBengaliFallback,
        hasUnicodeFallback: hasFallbacks,
      );
    } catch (_) {
      return _PdfThemeConfig(
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          italic: pw.Font.helveticaOblique(),
          boldItalic: pw.Font.helveticaBoldOblique(),
        ),
        hasBengaliFallback: false,
        hasUnicodeFallback: false,
      );
    }
  }

  static String _resolveCurrency(String currency, _PdfThemeConfig themeConfig) {
    final c = currency.trim();
    if (c == '৳' && !themeConfig.hasBengaliFallback) {
      return 'Tk';
    }
    if (!themeConfig.hasUnicodeFallback) {
      if (c == '₹') return 'Rs';
      if (c == '₽') return 'RUB';
      if (c == '₩') return 'KRW';
      if (c == '₪') return 'ILS';
    }
    return c;
  }

  static String _fmtPdfMoney(String cur, double amount) {
    final numFmt = NumberFormat('#,##0.00');
    final formatted = numFmt.format(amount);
    final c = cur.trim();
    if (c == '\$') return '\$$formatted';
    return '$c $formatted';
  }

  // ==================== PDF GENERATION ====================

  static Future<Uint8List> generateReportPdf(ReportExportData data) async {
    final themeConfig = await _getPdfTheme();
    final doc = pw.Document(theme: themeConfig.theme);

    final now = DateTime.now();
    final cur = _resolveCurrency(data.currency, themeConfig);
    final prop = data.propertyManager;
    final propName = prop?.propertyName?.trim();
    final hasPropName = propName != null && propName.isNotEmpty;
    final propAddress = prop?.address.trim();
    final hasPropAddress = propAddress != null && propAddress.isNotEmpty;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 22,
                      height: 22,
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFF0F766E),
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'RM',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          hasPropName ? propName : 'RentManager',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F766E),
                          ),
                        ),
                        if (hasPropName)
                          pw.Text(
                            'RentManager Property Management',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Executive Financial & Operations Report',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF0F172A),
                      ),
                    ),
                    if (hasPropAddress)
                      pw.Text(
                        propAddress,
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${DateFormat('MMM d, yyyy · h:mm a').format(now)}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Title & Scope Banner
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF1F5F9),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Period: ${data.monthName}',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF0F172A),
                        ),
                      ),
                      if (hasPropName || hasPropAddress) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Property: ${hasPropName ? propName : 'Residential Property'}${hasPropAddress ? ' • $propAddress' : ''}',
                          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F766E)),
                        ),
                      ],
                      if (prop?.ownerName?.isNotEmpty == true || prop?.name.isNotEmpty == true) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          'Owner: ${prop?.ownerName ?? 'N/A'}${prop?.name.isNotEmpty == true ? ' • Manager: ${prop!.name} (${prop.phone})' : ''}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Text(
                        data.selectedTenant != null
                            ? 'Scope: Tenant ${data.selectedTenant!.name} (Unit ${data.selectedTenant!.unit})'
                            : 'Scope: All Property Tenants & Operations',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Net Income',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                      ),
                      pw.Text(
                        _fmtPdfMoney(cur, data.net),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: data.net >= 0
                              ? const PdfColor.fromInt(0xFF059669)
                              : const PdfColor.fromInt(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Financial KPI Summary Cards
            pw.Row(
              children: [
                _buildKpiPdfCard('Total Rent', _fmtPdfMoney(cur, data.totalRent), const PdfColor.fromInt(0xFF059669)),
                pw.SizedBox(width: 8),
                _buildKpiPdfCard('Expenses', _fmtPdfMoney(cur, data.totalExpenses), const PdfColor.fromInt(0xFFDC2626)),
                pw.SizedBox(width: 8),
                _buildKpiPdfCard('Work Orders', _fmtPdfMoney(cur, data.totalWork), const PdfColor.fromInt(0xFFD97706)),
                pw.SizedBox(width: 8),
                _buildKpiPdfCard(
                  'Net Income',
                  _fmtPdfMoney(cur, data.net),
                  data.net >= 0 ? const PdfColor.fromInt(0xFF059669) : const PdfColor.fromInt(0xFFDC2626),
                ),
              ],
            ),
            pw.SizedBox(height: 18),

            // Section 1: Rent Roll Details
            pw.Text(
              'Rent Roll Details (${data.rentRows.length})',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A)),
            ),
            pw.SizedBox(height: 6),
            if (data.rentRows.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('No rent payments recorded for this period.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Tenant', 'Unit', 'Period', 'Amount', 'Paid Date', 'Status'],
                data: [
                  for (final r in data.rentRows)
                    [
                      r.tenant.name,
                      r.tenant.unit,
                      r.payment.displayMonth ?? r.payment.paidForMonth ?? '-',
                      _fmtPdfMoney(cur, r.payment.amount),
                      r.payment.paidDate ?? '-',
                      r.payment.status.toUpperCase(),
                    ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0F766E)),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.center,
                  5: pw.Alignment.center,
                },
              ),
            pw.SizedBox(height: 18),

            // Section 2: Expense Details (Only if All Tenants)
            if (data.tenantId == 'all') ...[
              pw.Text(
                'Expense Details (${data.expenses.length})',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A)),
              ),
              pw.SizedBox(height: 6),
              if (data.expenses.isEmpty)
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey200),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('No expenses recorded for this period.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                )
              else
                pw.TableHelper.fromTextArray(
                  headers: ['Category', 'Description', 'Date', 'Amount', 'Status'],
                  data: [
                    for (final e in data.expenses)
                      [
                        e.category,
                        e.description,
                        e.date,
                        _fmtPdfMoney(cur, e.amount),
                        e.status.toUpperCase(),
                      ],
                  ],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF334155)),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.center,
                  },
                ),
              pw.SizedBox(height: 18),
            ],

            // Section 3: Completed Work Orders
            pw.Text(
              'Completed Work Orders in ${data.year} (${data.workOrders.length})',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A)),
            ),
            pw.SizedBox(height: 6),
            if (data.workOrders.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('No work orders completed in ${data.year}.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Title', 'Unit', 'Category', 'Assigned To', 'Cost', 'Due Date'],
                data: [
                  for (final w in data.workOrders)
                    [
                      w.title,
                      w.unit ?? 'N/A',
                      w.category,
                      w.assignedTo,
                      _fmtPdfMoney(cur, ((w.workerCost ?? 0) + (w.productPrice ?? 0))),
                      w.dueDate,
                    ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF475569)),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                },
              ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> generateTenantStatementPdf({
    required Tenant tenant,
    required List<Payment> history,
    required String currency,
    PropertyManager? propertyManager,
  }) async {
    final themeConfig = await _getPdfTheme();
    final doc = pw.Document(theme: themeConfig.theme);

    final now = DateTime.now();
    final cur = _resolveCurrency(currency, themeConfig);
    final totalPaid = history
        .where((p) => p.status == 'paid')
        .fold<double>(0, (a, p) => a + p.amount);
    final prop = propertyManager;
    final propName = prop?.propertyName?.trim();
    final hasPropName = propName != null && propName.isNotEmpty;
    final propAddress = prop?.address.trim();
    final hasPropAddress = propAddress != null && propAddress.isNotEmpty;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        header: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 24,
                      height: 24,
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFF0F766E),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'RM',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          hasPropName ? propName : 'RentManager',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F766E),
                          ),
                        ),
                        pw.Text(
                          hasPropAddress
                              ? '$propAddress • Tenant Payment Statement'
                              : 'Tenant Payment History Statement',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      tenant.name,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF0F172A),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Unit ${tenant.unit.isEmpty ? 'N/A' : tenant.unit} • Generated ${DateFormat('MMM d, yyyy').format(now)}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'RentManager · Official Account Statement · Generated ${DateFormat('MMM d, yyyy · h:mm a').format(now)}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // 1. Top Property & Tenant Profile Card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF8FAFC),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Property & Management Information
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PROPERTY & PREMISES',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F766E),
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          hasPropName ? propName : 'Premises / Property',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F172A),
                          ),
                        ),
                        if (hasPropAddress) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            propAddress,
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        ],
                        if (prop?.ownerName != null && prop!.ownerName!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Owner: ${prop.ownerName!.trim()}',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                        ],
                        if (prop != null && prop.name.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Manager: ${prop.name.trim()}${prop.phone.trim().isNotEmpty ? ' (${prop.phone.trim()})' : ''}',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                        ],
                        if (prop != null && prop.email.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Email: ${prop.email.trim()}',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 1,
                    height: 85,
                    color: const PdfColor.fromInt(0xFFE2E8F0),
                    margin: const pw.EdgeInsets.symmetric(horizontal: 10),
                  ),
                  // Right: Tenant & Lease Summary
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'TENANT & LEASE DETAILS',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFF0F766E),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                pw.SizedBox(height: 3),
                                pw.Text(
                                  tenant.name,
                                  style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: pw.BoxDecoration(
                                color: tenant.status.toLowerCase() == 'active'
                                    ? const PdfColor.fromInt(0xFFE6F4EA)
                                    : const PdfColor.fromInt(0xFFF1F5F9),
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: pw.Text(
                                tenant.status.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: tenant.status.toLowerCase() == 'active'
                                      ? const PdfColor.fromInt(0xFF137333)
                                      : const PdfColor.fromInt(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Unit: ${tenant.unit.isEmpty ? 'N/A' : tenant.unit}'
                          '${tenant.phone.isNotEmpty ? '  •  Phone: ${tenant.phone}' : ''}'
                          '${tenant.email.isNotEmpty ? '  •  ${tenant.email}' : ''}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                        if (tenant.address != null && tenant.address!.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Permanent Address: ${tenant.address!.trim()}',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                          ),
                        ],
                        pw.SizedBox(height: 4),
                        pw.Row(
                          children: [
                            pw.Text(
                              'Lease Start: ${_formatPdfDate(tenant.leaseStartDate ?? tenant.joinDate)}',
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                            ),
                            pw.SizedBox(width: 10),
                            pw.Text(
                              'Rent: ${_fmtPdfMoney(cur, tenant.rentAmount)}/mo',
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF0F766E),
                              ),
                            ),
                            pw.SizedBox(width: 10),
                            pw.Text(
                              'Deposit: ${_fmtPdfMoney(cur, tenant.deposit ?? 0)}',
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // 2. Financial Overview Cards (KPIs)
            pw.Row(
              children: [
                _buildStatementKpiCard(
                  'Monthly Rent Rate',
                  _fmtPdfMoney(cur, tenant.rentAmount),
                  'Agreed monthly rent',
                  const PdfColor.fromInt(0xFF0F766E),
                ),
                pw.SizedBox(width: 8),
                _buildStatementKpiCard(
                  'Total Collected to Date',
                  _fmtPdfMoney(cur, totalPaid),
                  '${history.length} completed payments',
                  const PdfColor.fromInt(0xFF059669),
                ),
                pw.SizedBox(width: 8),
                _buildStatementKpiCard(
                  'Security Deposit Held',
                  _fmtPdfMoney(cur, tenant.deposit ?? 0),
                  'Deposit account balance',
                  const PdfColor.fromInt(0xFF0284C7),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // 3. Payment History Section Title
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Payment History',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF0F172A),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Itemized list of recorded rental payments',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF1F5F9),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: const PdfColor.fromInt(0xFFCBD5E1)),
                  ),
                  child: pw.Text(
                    '${history.length} Total Records',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),

            // 4. Transactions Table
            if (history.isEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                  borderRadius: pw.BorderRadius.circular(6),
                  color: const PdfColor.fromInt(0xFFF8FAFC),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'No completed payment records found for this tenant.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ),
              )
            else ...[
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Period / Month', 'Payment Date', 'Status', 'Reference / Notes', 'Amount'],
                data: [
                  for (int i = 0; i < history.length; i++)
                    [
                      '${i + 1}',
                      history[i].displayMonth ?? history[i].paidForMonth ?? 'Rent Payment',
                      _formatPdfDate(history[i].paidDate),
                      history[i].status.toUpperCase(),
                      (history[i].notes != null && history[i].notes!.isNotEmpty)
                          ? history[i].notes!
                          : '—',
                      _fmtPdfMoney(cur, history[i].amount),
                    ],
                ],
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8.5,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF0F766E),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
                border: pw.TableBorder.all(
                  color: const PdfColor.fromInt(0xFFE2E8F0),
                  width: 0.6,
                ),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8FAFC),
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(26),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2.6),
                  3: const pw.FlexColumnWidth(1.8),
                  4: const pw.FlexColumnWidth(3.5),
                  5: const pw.FlexColumnWidth(2.5),
                },
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerLeft,
                  5: pw.Alignment.centerRight,
                },
              ),

              // Total Summary Row
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF0FDF4),
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFF86EFAC), width: 0.8),
                  borderRadius: const pw.BorderRadius.vertical(bottom: pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL REVENUE RECORDED (${history.length} PAYMENTS)',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF166534),
                      ),
                    ),
                    pw.Text(
                      _fmtPdfMoney(cur, totalPaid),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 18),

            // 5. Official Verification & Signatures Block
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF8FAFC),
                border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'OFFICIAL RECORD CERTIFICATION',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF64748B),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'This statement is an official electronic record of rental payments received for ${tenant.name}${hasPropName ? ' at $propName' : ''}. All figures and transactions above have been reconciled with active records.',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 170,
                            height: 0.8,
                            color: const PdfColor.fromInt(0xFF94A3B8),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            prop != null && prop.name.trim().isNotEmpty
                                ? '${prop.name.trim()} (Property Manager)'
                                : 'Authorized Property Manager Signature',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                          pw.Text(
                            hasPropName ? '$propName Management' : 'Date: ____________________',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 170,
                            height: 0.8,
                            color: const PdfColor.fromInt(0xFF94A3B8),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '${tenant.name} (Tenant Acknowledgement)',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                          pw.Text(
                            'Date: ____________________',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static String _formatPdfDate(String? s) {
    if (s == null || s.trim().isEmpty) return '—';
    final trimmed = s.trim();
    try {
      final dt = DateTime.tryParse(trimmed);
      if (dt != null) {
        return DateFormat('MMM d, yyyy').format(dt);
      }
    } catch (_) {}
    if (trimmed.contains('T')) {
      final datePart = trimmed.split('T').first;
      final dt = DateTime.tryParse(datePart);
      if (dt != null) return DateFormat('MMM d, yyyy').format(dt);
      return datePart;
    }
    if (trimmed.contains(' ')) {
      final datePart = trimmed.split(' ').first;
      final dt = DateTime.tryParse(datePart);
      if (dt != null) return DateFormat('MMM d, yyyy').format(dt);
      return datePart;
    }
    return trimmed;
  }

  static pw.Widget _buildStatementKpiCard(
      String title, String value, String subtitle, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
          color: PdfColors.white,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: color),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildKpiPdfCard(String title, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(5),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
          color: PdfColors.white,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== RENT RECEIPT & INVOICE GENERATOR ====================

  static Future<Uint8List> generateRentReceiptPdf({
    required Payment payment,
    required Tenant tenant,
    PropertyManager? propertyManager,
    required String currency,
    String? receiptNumber,
    String? customNotes,
    String documentType = 'RECEIPT', // 'RECEIPT' or 'INVOICE'
  }) async {
    final themeConfig = await _getPdfTheme();
    final doc = pw.Document(theme: themeConfig.theme);
    final cur = _resolveCurrency(currency, themeConfig);
    final prop = propertyManager;
    final propName = prop?.propertyName?.trim();
    final hasPropName = propName != null && propName.isNotEmpty;
    final propAddress = prop?.address.trim();
    final hasPropAddress = propAddress != null && propAddress.isNotEmpty;
    final propPhone = prop?.phone.trim();
    final hasPropPhone = propPhone != null && propPhone.isNotEmpty;
    final propEmail = prop?.email.trim();
    final hasPropEmail = propEmail != null && propEmail.isNotEmpty;
    final managerName = prop?.name.trim();
    final hasManagerName = managerName != null && managerName.isNotEmpty;

    final receiptNo = (receiptNumber != null && receiptNumber.isNotEmpty)
        ? receiptNumber
        : 'REC-${payment.paidForMonth?.replaceAll('-', '') ?? DateTime.now().year.toString()}-${payment.id.length >= 6 ? payment.id.substring(0, 6).toUpperCase() : payment.id.toUpperCase()}';

    final issueDate = DateFormat('MMMM dd, yyyy').format(DateTime.now());
    final paidDateStr = payment.paidDate != null && payment.paidDate!.isNotEmpty
        ? DateFormat('MMMM dd, yyyy').format(DateTime.tryParse(payment.paidDate!) ?? DateTime.now())
        : issueDate;

    final rentPeriod = payment.displayMonth ??
        (payment.paidForMonth != null ? getMonthName(payment.paidForMonth!) : 'Current Period');
    final rentAmount = tenant.rentAmount;
    // Only actually-received money counts as paid. A pending record whose
    // amount happens to equal the rent must not render as "PAID IN FULL".
    final paidAmount = payment.status == 'paid' ? payment.amount : 0.0;
    final balanceDue = (rentAmount - paidAmount) > 0 ? (rentAmount - paidAmount) : 0.0;
    final isPaid = payment.status == 'paid' && paidAmount >= rentAmount - 0.01;
    final isPartiallyPaid =
        payment.status == 'paid' && paidAmount > 0 && !isPaid;
    final paymentStatusLabel = isPaid
        ? 'PAID IN FULL'
        : isPartiallyPaid
            ? 'PARTIALLY SETTLED'
            : 'PAYMENT DUE';

    String paymentMethod = 'Bank Transfer';
    String? transactionNotes = payment.notes;
    if (payment.notes != null) {
      if (payment.notes!.contains('Method: ')) {
        final parts = payment.notes!.split('Method: ')[1].split(' • ');
        if (parts.isNotEmpty) paymentMethod = parts[0];
      }
    }

    final isReceipt = documentType.toUpperCase() != 'INVOICE';
    final docTitle = isReceipt ? 'RENT PAYMENT RECEIPT' : 'RENT PAYMENT INVOICE';
    const primaryColor = PdfColor.fromInt(0xFF0F766E);
    const darkColor = PdfColor.fromInt(0xFF0F172A);
    const slate500 = PdfColor.fromInt(0xFF64748B);
    const slate700 = PdfColor.fromInt(0xFF334155);
    const bgCard = PdfColor.fromInt(0xFFF8FAFC);
    const borderCard = PdfColor.fromInt(0xFFE2E8F0);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header Banner
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Landlord / Management Identity
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            width: 32,
                            height: 32,
                            decoration: pw.BoxDecoration(
                              color: primaryColor,
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                hasPropName && propName.length >= 2
                                    ? propName.substring(0, 2).toUpperCase()
                                    : 'RM',
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                hasPropName ? propName : 'Property Management',
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: darkColor,
                                ),
                              ),
                              pw.Text(
                                hasManagerName
                                    ? 'Managed by $managerName'
                                    : 'Residential Property Statement',
                                style: const pw.TextStyle(fontSize: 8.5, color: slate500),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      if (hasPropAddress)
                        pw.Text(propAddress, style: const pw.TextStyle(fontSize: 8.5, color: slate700)),
                      if (hasPropPhone || hasPropEmail)
                        pw.Text(
                          [
                            if (hasPropPhone) 'Tel: $propPhone',
                            if (hasPropEmail) 'Email: $propEmail',
                          ].join('  |  '),
                          style: const pw.TextStyle(fontSize: 8, color: slate500),
                        ),
                    ],
                  ),

                  // Right: Receipt Metadata & Status Badge
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: isPaid
                              ? const PdfColor.fromInt(0xFFECFDF5)
                              : const PdfColor.fromInt(0xFFFFFBEB),
                          border: pw.Border.all(
                            color: isPaid
                                ? const PdfColor.fromInt(0xFFA7F3D0)
                                : const PdfColor.fromInt(0xFFFDE68A),
                          ),
                          borderRadius: pw.BorderRadius.circular(5),
                        ),
                        child: pw.Text(
                          docTitle,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: isPaid
                                ? const PdfColor.fromInt(0xFF065F46)
                                : const PdfColor.fromInt(0xFF92400E),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        '#$receiptNo',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: darkColor),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Issue Date: $issueDate', style: const pw.TextStyle(fontSize: 8, color: slate500)),
                      pw.Text('Payment Date: $paidDateStr', style: const pw.TextStyle(fontSize: 8, color: slate500)),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),
              pw.Container(height: 1, color: borderCard),
              pw.SizedBox(height: 16),

              // 2. Two-Column Information Cards
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left Card: Tenant Information
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: bgCard,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: borderCard),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'TENANT & PREMISES DETAILS',
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            tenant.name,
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: darkColor),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Unit: ${tenant.unit.isNotEmpty ? tenant.unit : 'Main Unit'}',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF047857)),
                          ),
                          if (tenant.phone.isNotEmpty)
                            pw.Text('Phone: ${tenant.phone}', style: const pw.TextStyle(fontSize: 8.5, color: slate700)),
                          if (tenant.email.isNotEmpty)
                            pw.Text('Email: ${tenant.email}', style: const pw.TextStyle(fontSize: 8.5, color: slate700)),
                          if (tenant.address != null && tenant.address!.isNotEmpty)
                            pw.Text('Premises: ${tenant.address}', style: const pw.TextStyle(fontSize: 8.5, color: slate700)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Right Card: Payment Summary
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: bgCard,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: borderCard),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PAYMENT PARTICULARS',
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Payment Method:', style: const pw.TextStyle(fontSize: 8.5, color: slate500)),
                              pw.Text(paymentMethod, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkColor)),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Rent Month / Period:', style: const pw.TextStyle(fontSize: 8.5, color: slate500)),
                              pw.Text(rentPeriod, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkColor)),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Status:', style: const pw.TextStyle(fontSize: 8.5, color: slate500)),
                              pw.Text(
                                paymentStatusLabel,
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: isPaid
                                      ? const PdfColor.fromInt(0xFF10B981)
                                      : isPartiallyPaid
                                          ? const PdfColor.fromInt(0xFFD97706)
                                          : const PdfColor.fromInt(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Transaction Ref:', style: const pw.TextStyle(fontSize: 8.5, color: slate500)),
                              pw.Text(
                                payment.id.length >= 8 ? payment.id.substring(0, 8).toUpperCase() : payment.id,
                                style: const pw.TextStyle(fontSize: 8, color: slate700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              // 3. Itemized Transactions Table
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderCard),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Table(
                  border: pw.TableBorder(
                    horizontalInside: pw.BorderSide(color: borderCard, width: 0.6),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3.5),
                    1: pw.FlexColumnWidth(2.0),
                    2: pw.FlexColumnWidth(2.0),
                    3: pw.FlexColumnWidth(2.0),
                    4: pw.FlexColumnWidth(2.0),
                  },
                  children: [
                    // Table Header
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF1F5F9),
                        borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(8)),
                      ),
                      children: [
                        _tableCell('DESCRIPTION', isHeader: true),
                        _tableCell('UNIT', isHeader: true),
                        _tableCell('PERIOD', isHeader: true),
                        _tableCell('RENT DUE', isHeader: true, align: pw.TextAlign.right),
                        _tableCell('AMOUNT PAID', isHeader: true, align: pw.TextAlign.right),
                      ],
                    ),
                    // Row 1: Primary Rent
                    pw.TableRow(
                      children: [
                        _tableCell('Monthly Residential Lease Rent\n(Tenancy agreement on record)'),
                        _tableCell(tenant.unit.isNotEmpty ? 'Unit ${tenant.unit}' : 'Primary'),
                        _tableCell(rentPeriod),
                        _tableCell(_fmtPdfMoney(cur, rentAmount), align: pw.TextAlign.right),
                        _tableCell(_fmtPdfMoney(cur, paidAmount), isBold: true, align: pw.TextAlign.right, textColor: const PdfColor.fromInt(0xFF0F766E)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // 4. Financial Calculation Summary Callout (Right aligned)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 250,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: bgCard,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: borderCard),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Subtotal Due:', style: const pw.TextStyle(fontSize: 8.5, color: slate500)),
                            pw.Text(_fmtPdfMoney(cur, rentAmount), style: const pw.TextStyle(fontSize: 9, color: slate700)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Paid:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkColor)),
                            pw.Text(
                              _fmtPdfMoney(cur, paidAmount),
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F766E)),
                            ),
                          ],
                        ),
                        pw.Divider(color: borderCard, height: 10),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Balance Remaining:', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: balanceDue > 0 ? const PdfColor.fromInt(0xFFDC2626) : slate500)),
                            pw.Text(
                              _fmtPdfMoney(cur, balanceDue),
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: balanceDue > 0 ? const PdfColor.fromInt(0xFFDC2626) : const PdfColor.fromInt(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 14),

              // 5. Notes / Terms Card
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF0FDF4),
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFFBBF7D0)),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'RECEIPT ACKNOWLEDGEMENT & REMARKS',
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF166534)),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      (customNotes != null && customNotes.isNotEmpty)
                          ? customNotes
                          : ((transactionNotes != null && transactionNotes.isNotEmpty)
                              ? 'Notes: $transactionNotes\nReceived with thanks. This official receipt confirms satisfaction of payment for the stated lease term.'
                              : 'Received with thanks. This official electronic receipt confirms satisfaction of payment for the referenced premises and period.'),
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF14532D)),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // 6. Authorized Signatures & Verification Block
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: pw.BoxDecoration(
                  color: bgCard,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: borderCard),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        // Left signature: Landlord
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(width: 170, height: 0.8, color: slate500),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              hasManagerName ? managerName : 'Authorized Property Manager',
                              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: darkColor),
                            ),
                            pw.Text(
                              hasPropName ? '$propName Management' : 'Landlord / Management Signatory',
                              style: const pw.TextStyle(fontSize: 7, color: slate500),
                            ),
                          ],
                        ),

                        // Center stamp
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: const PdfColor.fromInt(0xFF0F766E), width: 1.2),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            'OFFICIALLY VERIFIED',
                            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F766E)),
                          ),
                        ),

                        // Right signature: Tenant
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(width: 170, height: 0.8, color: slate500),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              tenant.name,
                              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: darkColor),
                            ),
                            pw.Text(
                              'Tenant Acknowledgement',
                              style: const pw.TextStyle(fontSize: 7, color: slate500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              // 7. Security / Integrity Micro Footer
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'RentManager Desktop System | Official Electronic Record ID: ${payment.id}',
                    style: const pw.TextStyle(fontSize: 6.5, color: slate500),
                  ),
                  pw.Text(
                    'Generated on $issueDate | Page 1 of 1',
                    style: const pw.TextStyle(fontSize: 6.5, color: slate500),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _tableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? textColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.5 : 8.5,
          fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: textColor ?? (isHeader ? const PdfColor.fromInt(0xFF475569) : const PdfColor.fromInt(0xFF0F172A)),
        ),
      ),
    );
  }

  // ==================== EXPORT DISPATCHERS ====================

  static Future<void> exportCsv({
    required BuildContext context,
    required String csvContent,
    required String fileName,
    Rect? sharePositionOrigin,
  }) async {
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final defaultOrigin = sharePositionOrigin ??
        Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100);
    final bytes = Uint8List.fromList(utf8.encode(csvContent));

    if (isDesktop) {
      try {
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Save Report CSV',
          fileName: fileName,
          bytes: bytes,
        );
        if (uri != null && context.mounted) {
          final filePath = uri.toFilePath();
          showAppToast(
            context,
            'CSV saved: $fileName',
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

    // Fallback or Mobile: Write to temp dir & share / open
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$fileName');
      await f.writeAsBytes(bytes);

      if (isDesktop) {
        if (context.mounted) {
          showAppToast(
            context,
            'CSV saved to temporary storage',
            isSuccess: true,
            actionLabel: 'Open',
            onAction: () => OpenFilex.open(f.path),
          );
        }
      } else {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(f.path, mimeType: 'text/csv')],
          subject: 'Export $fileName',
          sharePositionOrigin: defaultOrigin,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Export CSV failed: $e', isError: true);
      }
    }
  }

  static Future<void> exportPdf({
    required BuildContext context,
    required Uint8List pdfBytes,
    required String fileName,
    Rect? sharePositionOrigin,
  }) async {
    final isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final defaultOrigin = sharePositionOrigin ??
        Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100);

    if (isDesktop) {
      try {
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Save Report PDF',
          fileName: fileName,
          bytes: pdfBytes,
        );
        if (uri != null && context.mounted) {
          final filePath = uri.toFilePath();
          showAppToast(
            context,
            'PDF saved: $fileName',
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

    // Mobile / fallback: share PDF
    try {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
        bounds: defaultOrigin,
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Export PDF failed: $e', isError: true);
      }
    }
  }

  static Future<void> printPdf({
    required BuildContext context,
    required Uint8List pdfBytes,
    required String documentName,
  }) async {
    try {
      await Printing.layoutPdf(
        name: documentName,
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Print failed: $e', isError: true);
      }
    }
  }
}

class _PdfThemeConfig {
  final pw.ThemeData theme;
  final bool hasBengaliFallback;
  final bool hasUnicodeFallback;
  _PdfThemeConfig({
    required this.theme,
    required this.hasBengaliFallback,
    required this.hasUnicodeFallback,
  });
}
