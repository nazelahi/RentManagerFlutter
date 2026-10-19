import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';

/// Desktop Batch Rent Collection Modal
///
/// Enables landlords to review all active tenants for any selected month,
/// preview expected vs collected rent, adjust individual amounts/methods,
/// and record all due rent payments in a single click.
class DesktopBatchRentModal extends ConsumerStatefulWidget {
  final int? initialYear;
  final int? initialMonth;

  const DesktopBatchRentModal({
    super.key,
    this.initialYear,
    this.initialMonth,
  });

  static Future<void> show(
    BuildContext context, {
    int? year,
    int? month,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => DesktopBatchRentModal(
        initialYear: year,
        initialMonth: month,
      ),
    );
  }

  @override
  ConsumerState<DesktopBatchRentModal> createState() =>
      _DesktopBatchRentModalState();
}

class _TenantBatchRowState {
  final Tenant tenant;
  final Payment? existingPayment;
  bool isSelected;
  double amount;
  String paymentMethod;
  final TextEditingController amountController;
  final TextEditingController notesController;

  _TenantBatchRowState({
    required this.tenant,
    this.existingPayment,
    required this.isSelected,
    required this.amount,
    required this.paymentMethod,
    required this.amountController,
    required this.notesController,
  });

  bool get isPaid => existingPayment != null && existingPayment!.status == 'paid';
}

class _DesktopBatchRentModalState
    extends ConsumerState<DesktopBatchRentModal> {
  late int _selectedYear;
  late int _selectedMonth;
  late DateTime _collectionDate;
  String _defaultPaymentMethod = 'Bank Transfer';

  final Map<String, _TenantBatchRowState> _rowStates = {};
  bool _initialized = false;

  static const _monthNames = [
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

  static const _paymentMethods = [
    'Bank Transfer',
    'Cash',
    'Check',
    'Online / Card',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = widget.initialYear ?? now.year;
    _selectedMonth = widget.initialMonth ?? now.month;
    _collectionDate = now;
  }

  @override
  void dispose() {
    for (final row in _rowStates.values) {
      row.amountController.dispose();
      row.notesController.dispose();
    }
    super.dispose();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
  String get _monthDisplayName =>
      '${_monthNames[_selectedMonth]} $_selectedYear';

  void _syncRows(AppDataState s) {
    final activeTenants = s.scopedTenants
        .where((t) => t.status != 'inactive' && t.status != 'past')
        .toList();

    // Clean up old controllers not present anymore
    final activeIds = activeTenants.map((t) => t.id).toSet();
    _rowStates.removeWhere((id, state) {
      final keep = activeIds.contains(id);
      if (!keep) {
        state.amountController.dispose();
        state.notesController.dispose();
      }
      return !keep;
    });

    for (final tenant in activeTenants) {
      final existingPayment = s.scopedPayments.cast<Payment?>().firstWhere(
            (p) =>
                p != null &&
                p.tenantId == tenant.id &&
                ((p.paidForMonth != null && p.paidForMonth == _monthKey) ||
                    (p.paidForMonth == null &&
                        p.paidDate != null &&
                        p.paidDate!.startsWith(_monthKey))),
            orElse: () => null,
          );

      final isAlreadyPaid =
          existingPayment != null && existingPayment.status == 'paid';

      if (_rowStates.containsKey(tenant.id)) {
        // Update existing state with latest tenant/payment info
        final cur = _rowStates[tenant.id]!;
        _rowStates[tenant.id] = _TenantBatchRowState(
          tenant: tenant,
          existingPayment: existingPayment,
          isSelected: isAlreadyPaid ? false : cur.isSelected,
          amount: isAlreadyPaid
              ? existingPayment.amount
              : cur.amount,
          paymentMethod: cur.paymentMethod,
          amountController: cur.amountController,
          notesController: cur.notesController,
        );
      } else {
        // Initial setup for this tenant
        final rent = tenant.rentAmount;
        final amountCtl = TextEditingController(
          text: rent > 0 ? rent.toStringAsFixed(0) : '0',
        );
        final notesCtl = TextEditingController();

        _rowStates[tenant.id] = _TenantBatchRowState(
          tenant: tenant,
          existingPayment: existingPayment,
          isSelected: !isAlreadyPaid, // Default: select all unpaid
          amount: rent,
          paymentMethod: _defaultPaymentMethod,
          amountController: amountCtl,
          notesController: notesCtl,
        );
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth += delta;
      if (_selectedMonth > 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else if (_selectedMonth < 1) {
        _selectedMonth = 12;
        _selectedYear--;
      }
      _initialized = false;
    });
  }

  void _selectAllUnpaid() {
    setState(() {
      for (final row in _rowStates.values) {
        if (!row.isPaid) {
          row.isSelected = true;
        }
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (final row in _rowStates.values) {
        row.isSelected = false;
      }
    });
  }

  void _applyDefaultMethodToAll(String method) {
    setState(() {
      _defaultPaymentMethod = method;
      for (final row in _rowStates.values) {
        if (!row.isPaid) {
          row.paymentMethod = method;
        }
      }
    });
  }

  Future<void> _pickCollectionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _collectionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: AppColors.isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF0F766E),
                    onPrimary: Colors.white,
                    surface: Color(0xFF0F2627),
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF0F766E),
                    onPrimary: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _collectionDate = picked);
    }
  }

  Future<void> _commitBatchCollection(String currency) async {
    final selectedRows = _rowStates.values
        .where((r) => r.isSelected && !r.isPaid && r.amount > 0)
        .toList();

    if (selectedRows.isEmpty) {
      showAppToast(
        context,
        'No unpaid tenants selected for collection.',
        isError: true,
      );
      return;
    }

    final newPayments = <Payment>[];
    final isoDate = _collectionDate.toIso8601String();

    for (final row in selectedRows) {
      final noteParts = <String>[];
      if (row.paymentMethod.isNotEmpty) {
        noteParts.add('Method: ${row.paymentMethod}');
      }
      final customNote = row.notesController.text.trim();
      if (customNote.isNotEmpty) {
        noteParts.add(customNote);
      }

      final payment = Payment(
        id: row.existingPayment?.id ?? newId(),
        tenantId: row.tenant.id,
        amount: row.amount,
        status: 'paid',
        paidDate: isoDate,
        paidForMonth: _monthKey,
        displayMonth: _monthDisplayName,
        notes: noteParts.isEmpty ? null : noteParts.join(' • '),
        propertyId: row.tenant.propertyId,
      );
      newPayments.add(payment);
    }

    ref.read(appDataProvider.notifier).upsertPayments(newPayments);

    final totalCollected =
        selectedRows.fold<double>(0.0, (sum, r) => sum + r.amount);

    if (mounted) {
      Navigator.of(context).pop();
      showAppToast(
        context,
        'Recorded ${selectedRows.length} rent payments ($currency${totalCollected.toStringAsFixed(0)}) for $_monthDisplayName',
        isSuccess: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final currency = s.selectedCurrency.isEmpty ? '\$' : s.selectedCurrency;

    if (!_initialized) {
      _syncRows(s);
      _initialized = true;
    }

    final rows = _rowStates.values.toList()
      ..sort((a, b) {
        // Unpaid first, then by unit, then name
        if (a.isPaid != b.isPaid) return a.isPaid ? 1 : -1;
        return a.tenant.name.compareTo(b.tenant.name);
      });

    // Compute live summary stats
    final totalExpected =
        rows.fold<double>(0.0, (sum, r) => sum + r.tenant.rentAmount);
    final totalPaid = rows
        .where((r) => r.isPaid)
        .fold<double>(0.0, (sum, r) => sum + (r.existingPayment?.amount ?? r.amount));
    final paidCount = rows.where((r) => r.isPaid).length;

    final selectedRows = rows.where((r) => r.isSelected && !r.isPaid).toList();
    final selectedTotal =
        selectedRows.fold<double>(0.0, (sum, r) => sum + r.amount);
    final remainingDue = (totalExpected - totalPaid).clamp(0.0, double.infinity);

    final bg = isDark ? const Color(0xFF041718) : Colors.white;
    final cardBg = isDark ? const Color(0xFF082224) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: Container(
          width: 980,
          constraints: const BoxConstraints(maxWidth: 1100, minWidth: 720),
          height: 680,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.60 : 0.18),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Header
              _buildTopHeader(isDark, borderColor),

              // 2. Month Selector & Summary Bento Bar
              _buildMonthAndSummaryBar(
                isDark: isDark,
                cardBg: cardBg,
                borderColor: borderColor,
                currency: currency,
                totalExpected: totalExpected,
                totalPaid: totalPaid,
                paidCount: paidCount,
                totalTenants: rows.length,
                remainingDue: remainingDue,
              ),

              // 3. Batch Action Toolbar
              _buildBatchToolbar(
                isDark: isDark,
                borderColor: borderColor,
                unpaidCount: rows.where((r) => !r.isPaid).length,
                selectedCount: selectedRows.length,
              ),

              // 4. Interactive Spreadsheet Table
              Expanded(
                child: rows.isEmpty
                    ? _buildEmptyState(isDark)
                    : _buildTable(
                        rows: rows,
                        isDark: isDark,
                        borderColor: borderColor,
                        currency: currency,
                      ),
              ),

              // 5. Bottom Action Bar
              _buildBottomBar(
                isDark: isDark,
                borderColor: borderColor,
                currency: currency,
                selectedCount: selectedRows.length,
                selectedTotal: selectedTotal,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Ionicons.layersOutline, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Rent Collection Sheet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fast monthly roll • Review, adjust amounts, and record multiple rent payments simultaneously',
                  style: TextStyle(
                    fontSize: 11.5,
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
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF1F5F9),
                ),
                child: Center(
                  child: Icon(
                    Ionicons.close,
                    size: 16,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthAndSummaryBar({
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required String currency,
    required double totalExpected,
    required double totalPaid,
    required int paidCount,
    required int totalTenants,
    required double remainingDue,
  }) {
    final progress = totalExpected > 0 ? (totalPaid / totalExpected).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF061E20).withValues(alpha: 0.6)
            : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Month navigation capsule
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0C2729) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Ionicons.chevronBack, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    splashRadius: 14,
                    onPressed: () => _changeMonth(-1),
                    tooltip: 'Previous Month',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Ionicons.calendarOutline,
                            size: 13, color: Color(0xFF14B8A6)),
                        const SizedBox(width: 6),
                        Text(
                          _monthDisplayName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Ionicons.chevronForward, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    splashRadius: 14,
                    onPressed: () => _changeMonth(1),
                    tooltip: 'Next Month',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),

            // 3 KPI Metric Pills
            _buildKpiPill(
              label: 'Total Expected',
              value: '$currency${totalExpected.toStringAsFixed(0)}',
              sub: '$totalTenants Active Leases',
              isDark: isDark,
              borderColor: borderColor,
              color: AppColors.heading,
            ),
            const SizedBox(width: 8),
            _buildKpiPill(
              label: 'Already Paid',
              value: '$currency${totalPaid.toStringAsFixed(0)}',
              sub: '$paidCount of $totalTenants (${(progress * 100).toStringAsFixed(0)}%)',
              isDark: isDark,
              borderColor: borderColor,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            _buildKpiPill(
              label: 'Pending Collection',
              value: '$currency${remainingDue.toStringAsFixed(0)}',
              sub: '${totalTenants - paidCount} Unpaid',
              isDark: isDark,
              borderColor: borderColor,
              color: remainingDue > 0
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF10B981),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiPill({
    required String label,
    required String value,
    required String sub,
    required bool isDark,
    required Color borderColor,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C2729) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 9.5,
              color: isDark
                  ? const Color(0xFF64748B)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchToolbar({
    required bool isDark,
    required Color borderColor,
    required int unpaidCount,
    required int selectedCount,
  }) {
    final dateStr =
        '${_collectionDate.year}-${_collectionDate.month.toString().padLeft(2, '0')}-${_collectionDate.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Select buttons
            _smallButton(
              label: 'Select All Unpaid ($unpaidCount)',
              icon: Ionicons.checkmarkDoneOutline,
              isDark: isDark,
              onTap: _selectAllUnpaid,
            ),
            const SizedBox(width: 6),
            _smallButton(
              label: 'Deselect All',
              icon: Ionicons.closeOutline,
              isDark: isDark,
              onTap: _deselectAll,
            ),
            const SizedBox(width: 20),

          // Batch Payment Date
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Collection Date:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _pickCollectionDate,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0C2729)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Ionicons.calendarClearOutline,
                          size: 11.5, color: Color(0xFF14B8A6)),
                      const SizedBox(width: 5),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              AppColors.heading,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

          // Default Method Picker
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Batch Method:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0C2729)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _defaultPaymentMethod,
                    isDense: true,
                    icon: const Icon(Ionicons.chevronDown, size: 11),
                    dropdownColor:
                        isDark ? const Color(0xFF0B2424) : Colors.white,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                    onChanged: (val) {
                      if (val != null) _applyDefaultMethodToAll(val);
                    },
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _smallButton({
    required String label,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0C2729)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFCBD5E1),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: const Color(0xFF14B8A6)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.heading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable({
    required List<_TenantBatchRowState> rows,
    required bool isDark,
    required Color borderColor,
    required String currency,
  }) {
    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF061A1B)
                : const Color(0xFFF1F5F9),
            border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 32), // Checkbox spacing
              const Expanded(
                flex: 3,
                child: Text('TENANT & LEASE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const Expanded(
                flex: 2,
                child: Text('UNIT',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const Expanded(
                flex: 2,
                child: Text('EXPECTED',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const Expanded(
                flex: 3,
                child: Text('COLLECT AMOUNT',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const Expanded(
                flex: 3,
                child: Text('PAYMENT METHOD',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const Expanded(
                flex: 3,
                child: Text('NOTES / REF',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
              const SizedBox(
                width: 90,
                child: Text('STATUS',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B))),
              ),
            ],
          ),
        ),

        // Table Rows List
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: borderColor.withValues(alpha: 0.5)),
            itemBuilder: (context, index) {
              final row = rows[index];
              return _buildTableRow(
                row: row,
                isDark: isDark,
                borderColor: borderColor,
                currency: currency,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableRow({
    required _TenantBatchRowState row,
    required bool isDark,
    required Color borderColor,
    required String currency,
  }) {
    final t = row.tenant;
    final isPaid = row.isPaid;

    return Container(
      color: row.isSelected
          ? (isDark
              ? const Color(0xFF0F766E).withValues(alpha: 0.12)
              : const Color(0xFF059669).withValues(alpha: 0.05))
          : (isPaid
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.015)
                  : Colors.grey.withValues(alpha: 0.03))
              : Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Checkbox
          SizedBox(
            width: 32,
            child: isPaid
                ? const Icon(Ionicons.checkmarkCircle,
                    size: 16, color: Color(0xFF10B981))
                : Checkbox(
                    value: row.isSelected,
                    activeColor: const Color(0xFF0F766E),
                    onChanged: (val) {
                      setState(() => row.isSelected = val ?? false);
                    },
                  ),
          ),

          // 2. Tenant & Lease
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isDark
                      ? const Color(0xFF0F766E).withValues(alpha: 0.25)
                      : const Color(0xFF059669).withValues(alpha: 0.12),
                  child: Text(
                    t.name.isNotEmpty ? t.name[0].toUpperCase() : 'T',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      if (t.phone.isNotEmpty)
                        Text(
                          t.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Unit Badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0C2425)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: borderColor, width: 0.6),
                ),
                child: Text(
                  t.unit.isEmpty ? 'Unit —' : t.unit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ),
          ),

          // 4. Expected Rent
          Expanded(
            flex: 2,
            child: Text(
              '$currency${t.rentAmount.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ),

          // 5. Collect Amount (Editable)
          Expanded(
            flex: 3,
            child: isPaid
                ? Text(
                    '$currency${(row.existingPayment?.amount ?? row.amount).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  )
                : Container(
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    child: TextField(
                      controller: row.amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                      decoration: InputDecoration(
                        prefixText: '$currency ',
                        prefixStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF082224)
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor, width: 0.8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor, width: 0.8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: Color(0xFF14B8A6), width: 1.2),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val) ?? 0.0;
                        setState(() => row.amount = parsed);
                      },
                    ),
                  ),
          ),

          // 6. Payment Method Dropdown
          Expanded(
            flex: 3,
            child: isPaid
                ? Text(
                    row.existingPayment?.notes?.contains('Method: ') == true
                        ? row.existingPayment!.notes!
                            .split('Method: ')[1]
                            .split(' • ')[0]
                        : 'Recorded',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  )
                : Container(
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF082224) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: row.paymentMethod,
                        isDense: true,
                        isExpanded: true,
                        icon: const Icon(Ionicons.chevronDown, size: 10),
                        dropdownColor:
                            isDark ? const Color(0xFF0B2424) : Colors.white,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => row.paymentMethod = val);
                          }
                        },
                        items: _paymentMethods
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
          ),

          // 7. Notes Textfield
          Expanded(
            flex: 3,
            child: isPaid
                ? Text(
                    row.existingPayment?.notes ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                  )
                : Container(
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    child: TextField(
                      controller: row.notesController,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.heading,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Check #104',
                        hintStyle: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFF94A3B8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF082224)
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor, width: 0.8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: borderColor, width: 0.8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                              color: Color(0xFF14B8A6), width: 1.2),
                        ),
                      ),
                    ),
                  ),
          ),

          // 8. Status Badge
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerRight,
              child: isPaid
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.35),
                            width: 0.8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.checkmark,
                              size: 10, color: Color(0xFF10B981)),
                          SizedBox(width: 3),
                          Text(
                            'Paid',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.30),
                            width: 0.8),
                      ),
                      child: const Text(
                        'Unpaid',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Ionicons.peopleOutline,
            size: 40,
            color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 10),
          Text(
            'No Active Tenants Found',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Register tenants in the Tenants tab to start batch collection.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar({
    required bool isDark,
    required Color borderColor,
    required String currency,
    required int selectedCount,
    required double selectedTotal,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF061A1B) : const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Ionicons.checkboxOutline,
            size: 16,
            color: selectedCount > 0
                ? const Color(0xFF14B8A6)
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selectedCount > 0
                  ? '$selectedCount tenant${selectedCount > 1 ? 's' : ''} selected • Total: $currency${selectedTotal.toStringAsFixed(0)}'
                  : 'Select tenants to record payment',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.heading,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Cancel button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Primary Commit Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: selectedCount > 0
                  ? () => _commitBatchCollection(currency)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: selectedCount > 0
                      ? const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: isDark
                              ? [Colors.grey.shade700, Colors.grey.shade800]
                              : [Colors.grey.shade300, Colors.grey.shade400],
                        ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selectedCount > 0
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Ionicons.flashOutline,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      selectedCount > 0
                          ? 'Collect $selectedCount Payments • $currency${selectedTotal.toStringAsFixed(0)}'
                          : 'Collect 0 Payments',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
