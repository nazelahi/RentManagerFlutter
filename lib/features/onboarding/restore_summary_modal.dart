import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/theme/app_colors.dart';
import 'setup_sheet.dart';

/// Port of `src/components/RestoreSummaryModal.tsx` — per-data-type restore
/// summary with counts.
Future<void> showRestoreSummarySheet(
    BuildContext context, Map<String, dynamic>? restoredData) async {
  final data = restoredData ?? <String, dynamic>{};

  int len(String key) {
    final v = data[key];
    if (v == null) return 0;
    dynamic decoded = v;
    if (v is String) {
      try {
        decoded = jsonDecode(v);
      } catch (_) {
        return v.trim().isEmpty ? 0 : 1;
      }
    }
    if (decoded is List) return decoded.length;
    return 0;
  }

  int mapLen(String key) {
    final v = data[key];
    if (v == null) return 0;
    dynamic decoded = v;
    if (v is String) {
      try {
        decoded = jsonDecode(v);
      } catch (_) {
        return 0;
      }
    }
    if (decoded is Map) return decoded.keys.length;
    return 0;
  }

  final items = <_SummaryItem>[
    _SummaryItem('Property Manager', data['propertyManager'] != null ? 1 : 0,
        Ionicons.person, const Color(0xFF2196F3),
        data['propertyManager'] != null ? 'Restored' : 'Not restored'),
    _SummaryItem('Tenants', len('tenants'), Ionicons.people,
        const Color(0xFF4CAF50), '${len('tenants')} tenant(s) restored'),
    _SummaryItem('Payments', len('payments'), Ionicons.card,
        const Color(0xFFFF9800), '${len('payments')} payment(s) restored'),
    _SummaryItem('Expenses', len('expenses'), Ionicons.receipt,
        const Color(0xFF9C27B0), '${len('expenses')} expense(s) restored'),
    _SummaryItem('Work Orders', len('workOrders'), Ionicons.construct,
        const Color(0xFF607D8B),
        '${len('workOrders')} work order(s) restored'),
    _SummaryItem('Banks', len('banks'), Ionicons.business,
        const Color(0xFF795548), '${len('banks')} bank(s) restored'),
    _SummaryItem('Documents', len('documents'), Ionicons.document,
        const Color(0xFF607D8B), '${len('documents')} document(s) restored'),
    _SummaryItem('Document Groups', len('documentGroups'), Ionicons.folder,
        const Color(0xFF9C27B0),
        '${len('documentGroups')} document group(s) restored'),
    _SummaryItem('Reports', len('reports'), Ionicons.barChart,
        const Color(0xFFFF5722), '${len('reports')} report(s) restored'),
    _SummaryItem('Document Categories', len('documentCategories'), Ionicons.list,
        const Color(0xFF3F51B5),
        '${len('documentCategories')} document categor(ies) restored'),
    _SummaryItem('Predefined Descriptions', len('predefinedDescriptions'),
        Ionicons.text, const Color(0xFF795548),
        '${len('predefinedDescriptions')} predefined description(s) restored'),
    _SummaryItem('Recently Deleted Docs', len('recentlyDeletedDocs'),
        Ionicons.trash, const Color(0xFFF44336),
        '${len('recentlyDeletedDocs')} recently deleted doc(s) restored'),
    _SummaryItem('Monthly Notes', mapLen('monthlyNotes'), Ionicons.documentText,
        const Color(0xFFFF9800),
        '${mapLen('monthlyNotes')} monthly note(s) restored'),
    _SummaryItem('Bank Deposits', len('bankDeposits'), Ionicons.card,
        const Color(0xFF2196F3), '${len('bankDeposits')} bank deposit(s) restored'),
    _SummaryItem('Zakat Transactions', len('zakat'), Ionicons.calculator,
        const Color(0xFFE91E63), '${len('zakat')} zakat transaction(s) restored'),
    _SummaryItem('App Preferences', data['preferences'] != null ? 1 : 0,
        Ionicons.settings, const Color(0xFFFF5722),
        data['preferences'] != null
            ? 'App preferences restored'
            : 'No preferences restored'),
    _SummaryItem('Currency Setting',
        (data['selectedCurrency'] ?? '').toString().isNotEmpty ? 1 : 0,
        Ionicons.cash, const Color(0xFFFFC107),
        (data['selectedCurrency'] ?? '').toString().isNotEmpty
            ? 'Currency: ${data['selectedCurrency']}'
            : 'No currency setting restored'),
    _SummaryItem('Expense Categories', len('expenseCategories'), Ionicons.list,
        const Color(0xFF3F51B5),
        '${len('expenseCategories')} expense categor(ies) restored'),
  ];

  final total = items.fold<int>(0, (a, b) => a + b.count);

  await showSetupSheet<void>(
    context: context,
    builder: (ctx, height) => SetupSheet(
      icon: Ionicons.checkmarkCircle,
      title: 'Restore Complete',
      onClose: () => Navigator.pop(ctx),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(76, 175, 80, 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                const Icon(Ionicons.cloudDownload,
                    size: 32, color: AppColors.primary),
                const SizedBox(height: 12),
                const Text('Data Restored Successfully!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 8),
                Text('$total item(s) have been restored from your backup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Restored Data Summary',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
            ),
            for (final it in items) _summaryRow(it),
          ],
        ),
      ),
      footer: Container(
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: AppColors.surfaceBorder)),
        ),
        padding: const EdgeInsets.all(20),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Ionicons.arrowForward, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Continue to App',
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SummaryItem {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final String description;
  const _SummaryItem(this.title, this.count, this.icon, this.color,
      this.description);
}

Widget _summaryRow(_SummaryItem it) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: it.color, shape: BoxShape.circle),
        child: Icon(it.icon, size: 20, color: Colors.white),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(it.title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
            ),
            Text(it.description,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      ),
      Container(
        constraints: const BoxConstraints(minWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text('${it.count}',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: it.color)),
      ),
    ]),
  );
}
