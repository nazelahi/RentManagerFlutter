import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../overview/overview_view.dart';
import 'desktop_batch_rent_modal.dart';
import 'desktop_rent_receipt_modal.dart';
import 'desktop_cash_flow_modal.dart';

/// Executive Bento-Grid Dashboard for macOS Desktop.
class DesktopOverviewView extends ConsumerStatefulWidget {
  final Function(Tenant tenant) onSelectTenant;
  final VoidCallback onAddTenant;
  final VoidCallback onLogPayment;
  final VoidCallback? onLogExpense;
  final VoidCallback? onDeposit;
  final void Function(String monthKey, MonthlyNote? existing)? onAddNote;
  final void Function(BankDeposit deposit)? onDepositDetails;
  final void Function(BankDeposit deposit)? onEditDeposit;
  final void Function(Payment payment, Tenant? tenant)? onPaymentDetails;
  final void Function(Expense expense)? onExpenseDetails;
  final void Function(Payment payment, Tenant? tenant)? onEditPayment;
  final void Function(Expense expense)? onEditExpense;

  // ignore: library_private_types_in_public_api
  static final GlobalKey<_DesktopOverviewViewState> globalKey =
      GlobalKey<_DesktopOverviewViewState>();

  static void showSyncDialog(BuildContext context, [String initialType = 'all']) {
    globalKey.currentState?._showDesktopSyncDialog(context, initialType);
  }

  const DesktopOverviewView({
    super.key,
    required this.onSelectTenant,
    required this.onAddTenant,
    required this.onLogPayment,
    this.onLogExpense,
    this.onDeposit,
    this.onAddNote,
    this.onDepositDetails,
    this.onEditDeposit,
    this.onPaymentDetails,
    this.onExpenseDetails,
    this.onEditPayment,
    this.onEditExpense,
  });

  @override
  ConsumerState<DesktopOverviewView> createState() =>
      _DesktopOverviewViewState();
}

class _ExpenseCategoryStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _ExpenseCategoryStyle(this.icon, this.color, this.bgColor);
}

class _DesktopOverviewViewState extends ConsumerState<DesktopOverviewView> {
  int _month = DateTime.now().month;
  String _rentRollFilter = 'all'; // 'all', 'paid', 'pending'
  String _expenseFilter = 'all'; // 'all', 'pending', 'paid'
  bool _showQuickExpenseBar = false;
  final TextEditingController _quickExpenseTitleController =
      TextEditingController();
  final TextEditingController _quickExpenseAmountController =
      TextEditingController();
  String _quickExpenseCategory = 'Maintenance';

  bool _showQuickRentRollBar = false;
  String? _quickRentTenantId;
  final TextEditingController _quickRentAmountController =
      TextEditingController();
  final TextEditingController _quickRentNotesController =
      TextEditingController();
  String _quickRentStatus = 'paid';

  @override
  void dispose() {
    _quickExpenseTitleController.dispose();
    _quickExpenseAmountController.dispose();
    _quickRentAmountController.dispose();
    _quickRentNotesController.dispose();
    super.dispose();
  }
  final List<String> _monthNames = const [
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
    'December'
  ];
  final List<String> _shortMonthNames = const [
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
    'Dec'
  ];

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

  String _formatKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (m >= 1 && m <= 12) {
      return '${_monthNames[m]} $y';
    }
    return key;
  }

  Widget _contextMenuItem({
    required IconData icon,
    required String label,
    bool isDestructive = false,
    required bool isDark,
  }) {
    final color = isDestructive
        ? const Color(0xFFEF4444)
        : (AppColors.heading);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  void _openCashFlowForecast() {
    final selectedYear = ref.read(appDataProvider).selectedYear;
    DesktopCashFlowModal.show(context, year: selectedYear, month: _month);
  }

  void _safeToast(String message, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    showAppToast(context, message, isSuccess: isSuccess, isError: isError);
  }

  Future<void> _showPaymentContextMenu(
    BuildContext context,
    Offset position,
    Payment payment,
    Tenant? tenant,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;
    final isPaid = payment.status == 'paid';
    final cur = ref.read(appDataProvider).selectedCurrency;

    final item = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isDark ? const Color(0xFF0F2425) : Colors.white,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'details',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.eyeOutline,
            label: 'View Details',
            isDark: isDark,
          ),
        ),
        PopupMenuItem(
          value: 'receipt',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.receiptOutline,
            label: 'Rent Receipt / Invoice...',
            isDark: isDark,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_status',
          height: 36,
          child: _contextMenuItem(
            icon: isPaid ? Ionicons.timeOutline : Ionicons.checkmarkCircleOutline,
            label: isPaid ? 'Mark as Pending' : 'Mark as Paid',
            isDark: isDark,
          ),
        ),
        if (widget.onEditPayment != null)
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Payment',
              isDark: isDark,
            ),
          ),
        if (tenant != null) ...[
          PopupMenuItem(
            value: 'tenant',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.personOutline,
              label: 'View ${tenant.name}',
              isDark: isDark,
            ),
          ),
        ],
        PopupMenuItem(
          value: 'copy',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.copyOutline,
            label: 'Copy Amount ($cur ${payment.amount.toStringAsFixed(0)})',
            isDark: isDark,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.trashOutline,
            label: 'Delete Payment',
            isDestructive: true,
            isDark: isDark,
          ),
        ),
      ],
    );

    if (!context.mounted || item == null) return;

    if (item == 'details') {
      if (widget.onPaymentDetails != null) {
        widget.onPaymentDetails!(payment, tenant);
      } else if (widget.onEditPayment != null) {
        widget.onEditPayment!(payment, tenant);
      } else if (tenant != null) {
        widget.onSelectTenant(tenant);
      }
    } else if (item == 'receipt') {
      DesktopRentReceiptModal.show(context, payment: payment, tenant: tenant);
    } else if (item == 'toggle_status') {
      final newStatus = isPaid ? 'pending' : 'paid';
      final updated = Payment(
        id: payment.id,
        tenantId: payment.tenantId,
        amount: payment.amount,
        status: newStatus,
        dueDate: payment.dueDate,
        paidDate: newStatus == 'paid'
            ? (payment.paidDate ?? DateTime.now().toIso8601String().substring(0, 10))
            : null,
        paidForMonth: payment.paidForMonth,
        paymentMonthName: payment.paymentMonthName,
        displayMonth: payment.displayMonth,
        notes: payment.notes,
      );
      ref.read(appDataProvider.notifier).upsertPayment(updated);
      _safeToast(
        newStatus == 'paid' ? 'Payment marked as Paid' : 'Payment marked as Pending',
        isSuccess: true,
      );
    } else if (item == 'edit') {
      widget.onEditPayment?.call(payment, tenant);
    } else if (item == 'tenant' && tenant != null) {
      widget.onSelectTenant(tenant);
    } else if (item == 'copy') {
      Clipboard.setData(ClipboardData(text: payment.amount.toStringAsFixed(2)));
      _safeToast('Amount copied to clipboard', isSuccess: true);
    } else if (item == 'delete') {
      _confirmDeletePayment(payment, tenant);
    }
  }

  void _confirmDeletePayment(Payment payment, Tenant? tenant) {
    final cur = ref.read(appDataProvider).selectedCurrency;
    final title = tenant != null
        ? '${tenant.name} ($cur ${payment.amount.toStringAsFixed(0)})'
        : '$cur ${payment.amount.toStringAsFixed(0)}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            AppColors.isDark ? const Color(0xFF0F2627) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Payment Record?'),
        content: Text(
            'Are you sure you want to delete payment record for $title? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(appDataProvider.notifier).deletePayment(payment.id);
              _safeToast('Payment record deleted', isSuccess: true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExpenseContextMenu(
    BuildContext context,
    Offset position,
    Expense expense,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;
    final isPaid = expense.status == 'paid' || expense.status.isEmpty;
    final cur = ref.read(appDataProvider).selectedCurrency;

    final item = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isDark ? const Color(0xFF0F2425) : Colors.white,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'details',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.eyeOutline,
            label: 'View Details',
            isDark: isDark,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_status',
          height: 36,
          child: _contextMenuItem(
            icon: isPaid ? Ionicons.timeOutline : Ionicons.checkmarkCircleOutline,
            label: isPaid ? 'Mark as Pending' : 'Mark as Paid',
            isDark: isDark,
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.copyOutline,
            label: 'Duplicate Expense',
            isDark: isDark,
          ),
        ),
        if (widget.onEditExpense != null)
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Expense',
              isDark: isDark,
            ),
          ),
        PopupMenuItem(
          value: 'copy',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.clipboardOutline,
            label: 'Copy Description ($cur ${expense.amount.toStringAsFixed(0)})',
            isDark: isDark,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.trashOutline,
            label: 'Delete Expense',
            isDestructive: true,
            isDark: isDark,
          ),
        ),
      ],
    );

    if (!mounted || item == null) return;

    if (item == 'details') {
      if (widget.onExpenseDetails != null) {
        widget.onExpenseDetails!(expense);
      } else {
        widget.onEditExpense?.call(expense);
      }
    } else if (item == 'toggle_status') {
      final newStatus = isPaid ? 'pending' : 'paid';
      final updated = Expense(
        id: expense.id,
        category: expense.category,
        description: expense.description,
        amount: expense.amount,
        date: expense.date,
        status: newStatus,
        paidDate: newStatus == 'paid'
            ? (expense.paidDate ?? DateTime.now().toIso8601String().substring(0, 10))
            : null,
        expenseForMonth: expense.expenseForMonth,
        displayMonth: expense.displayMonth,
        receipt: expense.receipt,
        receiptFiles: expense.receiptFiles,
      );
      ref.read(appDataProvider.notifier).upsertExpense(updated);
      _safeToast(
        newStatus == 'paid' ? 'Expense marked as Paid' : 'Expense marked as Pending',
        isSuccess: true,
      );
    } else if (item == 'duplicate') {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final copy = Expense(
        id: newId(),
        category: expense.category,
        description: '${expense.description} (Copy)',
        amount: expense.amount,
        date: dateStr,
        status: expense.status,
        paidDate: expense.paidDate,
        expenseForMonth: expense.expenseForMonth,
        displayMonth: expense.displayMonth,
        receipt: expense.receipt,
        receiptFiles: expense.receiptFiles,
      );
      ref.read(appDataProvider.notifier).upsertExpense(copy);
      _safeToast('Expense duplicated successfully', isSuccess: true);
    } else if (item == 'edit') {
      widget.onEditExpense?.call(expense);
    } else if (item == 'copy') {
      Clipboard.setData(ClipboardData(text: expense.description));
      _safeToast('Description copied to clipboard', isSuccess: true);
    } else if (item == 'delete') {
      _confirmDeleteExpense(expense);
    }
  }

  void _confirmDeleteExpense(Expense expense) {
    final cur = ref.read(appDataProvider).selectedCurrency;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            AppColors.isDark ? const Color(0xFF0F2627) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Expense?'),
        content: Text(
            'Are you sure you want to delete "${expense.description}" ($cur ${expense.amount.toStringAsFixed(0)})? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(appDataProvider.notifier).deleteExpense(expense.id);
              _safeToast('Expense deleted', isSuccess: true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDepositContextMenu(
    BuildContext context,
    Offset position,
    BankDeposit deposit,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;
    final isConfirmed = deposit.status.toLowerCase().trim() == 'confirmed';
    final cur = ref.read(appDataProvider).selectedCurrency;

    final item = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isDark ? const Color(0xFF0F2425) : Colors.white,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'details',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.eyeOutline,
            label: 'View Deposit Details',
            isDark: isDark,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_status',
          height: 36,
          child: _contextMenuItem(
            icon: isConfirmed ? Ionicons.timeOutline : Ionicons.checkmarkDoneCircleOutline,
            label: isConfirmed ? 'Mark as Pending' : 'Mark as Confirmed',
            isDark: isDark,
          ),
        ),
        if (widget.onEditDeposit != null)
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Deposit',
              isDark: isDark,
            ),
          ),
        PopupMenuItem(
          value: 'copy',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.copyOutline,
            label: 'Copy Amount ($cur ${deposit.amount.toStringAsFixed(0)})',
            isDark: isDark,
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.trashOutline,
            label: 'Delete Deposit',
            isDestructive: true,
            isDark: isDark,
          ),
        ),
      ],
    );

    if (!mounted || item == null) return;

    if (item == 'details') {
      if (widget.onDepositDetails != null) {
        widget.onDepositDetails!(deposit);
      } else {
        widget.onEditDeposit?.call(deposit);
      }
    } else if (item == 'toggle_status') {
      final isConf = deposit.status.toLowerCase().trim() == 'confirmed';
      final newStatus = isConf ? 'pending' : 'confirmed';
      final now = DateTime.now().toIso8601String();
      final updated = deposit.copyWith(
        status: newStatus,
        updatedAt: now,
      );
      ref.read(appDataProvider.notifier).upsertDeposit(updated);
      _safeToast(
        newStatus == 'confirmed'
            ? 'Deposit marked as Confirmed'
            : 'Deposit marked as Pending',
        isSuccess: true,
      );
    } else if (item == 'edit') {
      widget.onEditDeposit?.call(deposit);
    } else if (item == 'copy') {
      Clipboard.setData(ClipboardData(text: deposit.amount.toStringAsFixed(2)));
      _safeToast('Amount copied to clipboard', isSuccess: true);
    } else if (item == 'delete') {
      _confirmDeleteDeposit(deposit);
    }
  }

  void _confirmDeleteDeposit(BankDeposit deposit) {
    final cur = ref.read(appDataProvider).selectedCurrency;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            AppColors.isDark ? const Color(0xFF0F2627) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Bank Deposit?'),
        content: Text(
            'Are you sure you want to delete deposit of $cur ${deposit.amount.toStringAsFixed(0)} for ${deposit.bankName}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(appDataProvider.notifier).deleteDeposit(deposit.id);
              _safeToast('Bank deposit deleted', isSuccess: true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionButton({
    required String label,
    required String tooltip,
    required bool isDark,
    required VoidCallback onTap,
    List<Color>? gradientColors,
    IconData icon = Ionicons.add,
  }) {
    final colors = gradientColors ?? const [Color(0xFF0F766E), Color(0xFF059669)];
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: Colors.white),
                const SizedBox(width: 3.5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSyncButton({
    required String label,
    required String tooltip,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF103333)
                  : const Color(0xFFEDF7F4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF34D399).withValues(alpha: 0.35)
                    : const Color(0xFF059669).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Ionicons.syncOutline,
                  size: 11.5,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderQuickButton({
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
    List<Color>? gradientColors,
    String? tooltip,
  }) {
    final colors = isActive
        ? (isDark
            ? const [Color(0xFF475569), Color(0xFF334155)]
            : const [Color(0xFF64748B), Color(0xFF475569)])
        : (gradientColors ?? const [Color(0xFF0F766E), Color(0xFF10B981)]);
    return Tooltip(
      message: tooltip ??
          (isActive
              ? 'Close instant logger'
              : 'Instant Logger (Quick Add)'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                isActive ? Ionicons.close : Ionicons.flashOutline,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildEmptyStateSyncButton({
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF103333)
                : const Color(0xFFEDF7F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF34D399).withValues(alpha: 0.4)
                  : const Color(0xFF059669).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Ionicons.syncOutline,
                size: 13,
                color: isDark
                    ? const Color(0xFF34D399)
                    : const Color(0xFF059669),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDesktopSyncDialog(BuildContext context, [String initialType = 'all']) async {
    final s = ref.read(appDataProvider);
    final cur = s.selectedCurrency;
    final isDark = AppColors.isDark;
    final targetMonthKey = _key(s.selectedYear, _month);
    final targetMonthTitle = '${_monthNames[_month]} ${s.selectedYear}';

    // Source options: up to 12 months preceding the current target month
    final sourceOptions = <String>[];
    var sy = s.selectedYear;
    var sm = _month - 1;
    if (sm < 1) {
      sm = 12;
      sy--;
    }
    for (var i = 0; i < 12; i++) {
      sourceOptions.add(_key(sy, sm));
      sm--;
      if (sm < 1) {
        sm = 12;
        sy--;
      }
    }
    if (sourceOptions.isEmpty) {
      sourceOptions.add(_prevKey());
    }

    String selectedType = initialType;
    String selectedSource = sourceOptions.first;
    String selectedSourceProperty = s.effectivePropertyId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentAppState = ref.watch(appDataProvider);
          if (currentAppState.properties.isNotEmpty &&
              !currentAppState.properties.any((p) => p.id == selectedSourceProperty)) {
            selectedSourceProperty = currentAppState.effectivePropertyId;
          }

          bool matchesSourceProp(String? itemPropId) {
            if (currentAppState.properties.isEmpty) return true;
            final normId = (itemPropId == null || itemPropId.isEmpty || itemPropId == 'prop-default')
                ? currentAppState.properties.first.id
                : itemPropId;
            return normId == selectedSourceProperty;
          }

          final tenantById = {for (final t in currentAppState.tenants) t.id: t};

          String expSig(String cat, String desc, double amt) =>
              '${cat.trim().toLowerCase()}_${desc.trim().toLowerCase()}_$amt';

          // Items from selected source month and selected source property
          final rItems = <Payment>[];
          if (selectedType != 'expenses') {
            final seenTenants = <String>{};
            final seenUnits = <String>{};
            final srcPayments = currentAppState.payments.where((p) =>
                matchesSourceProp(p.propertyId) &&
                (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '').startsWith(selectedSource));
            for (final p in srcPayments) {
              if (p.tenantId.isEmpty) continue;
              final t = tenantById[p.tenantId];
              if (t != null && t.status == 'inactive') continue;
              final u = t?.unit.trim() ?? '';
              if (seenTenants.contains(p.tenantId)) continue;
              if (u.isNotEmpty && seenUnits.contains(u)) continue;

              seenTenants.add(p.tenantId);
              if (u.isNotEmpty) seenUnits.add(u);
              rItems.add(p);
            }
          }

          // Expenses from selected source month and selected source property
          final eItems = <Expense>[];
          if (selectedType != 'rentRoll') {
            final seenExp = <String>{};
            final srcExpenses = currentAppState.expenses.where((e) =>
                matchesSourceProp(e.propertyId) &&
                (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(selectedSource));
            for (final e in srcExpenses) {
              final sig = expSig(e.category, e.description, e.amount);
              if (seenExp.contains(sig)) continue;
              seenExp.add(sig);
              eItems.add(e);
            }
          }

          // Target existing items for duplicate detection (strictly scoped to the active target property)
          final exRent = currentAppState.scopedPayments
              .where((p) =>
                  (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
                      .startsWith(targetMonthKey))
              .toList();

          bool rentDup(Payment p) {
            final u = tenantById[p.tenantId]?.unit.trim();
            return exRent.any((e) {
              if (e.tenantId == p.tenantId) return true;
              final eu = tenantById[e.tenantId]?.unit.trim();
              return u != null && u.isNotEmpty && eu == u;
            });
          }

          String? rentDupReason(Payment p) {
            final u = tenantById[p.tenantId]?.unit.trim();
            var t = false, un = false;
            for (final e in exRent) {
              if (e.tenantId == p.tenantId) t = true;
              final eu = tenantById[e.tenantId]?.unit.trim();
              if (u != null && u.isNotEmpty && eu == u) un = true;
            }
            if (t && un) return 'Duplicate (Unit & Tenant)';
            if (t) return 'Duplicate Tenant';
            if (un) return 'Duplicate Unit';
            return null;
          }

          final exExp = currentAppState.scopedExpenses
              .where((e) =>
                  (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(targetMonthKey))
              .toList();

          bool expDup(Expense e) {
            final sig = expSig(e.category, e.description, e.amount);
            return exExp.any((x) => expSig(x.category, x.description, x.amount) == sig);
          }

          final freshRent = rItems.where((p) => !rentDup(p)).toList();
          final dupRentCount = rItems.where((p) => rentDup(p)).length;

          final freshExp = eItems.where((e) => !expDup(e)).toList();
          final dupExpCount = eItems.where((e) => expDup(e)).length;

          final freshTotalCount = freshRent.length + freshExp.length;
          final dupTotalCount = dupRentCount + dupExpCount;

          final totalRentAmount = rItems.fold<double>(0, (a, p) => a + p.amount);
          final totalExpAmount = eItems.fold<double>(0, (a, e) => a + e.amount);

          final dialogBg = isDark ? const Color(0xFF0C2425) : Colors.white;
          final cardBg = isDark ? const Color(0xFF091A1B) : const Color(0xFFF8FAFC);
          final borderColor = isDark
              ? const Color.fromRGBO(255, 255, 255, 0.08)
              : const Color(0xFFE2E8F0);
          final textPrimary = AppColors.heading;
          final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 620,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.86,
                ),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.22),
                      blurRadius: 36,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Dialog Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Ionicons.sync, size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sync Previous Month Roll',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Preview & duplicate recurring entries into $targetMonthTitle',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Ionicons.close, size: 18),
                          color: textSecondary,
                          splashRadius: 18,
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Controls: Type Segmented Tabs
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSyncTypePill('all', 'All Entries', selectedType, isDark, (val) {
                                setDialogState(() => selectedType = val);
                              }),
                              _buildSyncTypePill('rentRoll', 'Rent Roll Only', selectedType, isDark, (val) {
                                setDialogState(() => selectedType = val);
                              }),
                              _buildSyncTypePill('expenses', 'Expenses Only', selectedType, isDark, (val) {
                                setDialogState(() => selectedType = val);
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Source -> Target Visual Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (currentAppState.properties.length > 1) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'SOURCE PROPERTY',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 30,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: dialogBg,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: borderColor),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: selectedSourceProperty,
                                            isDense: true,
                                            isExpanded: true,
                                            icon: const Icon(Ionicons.chevronDown, size: 12),
                                            dropdownColor: dialogBg,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                            items: currentAppState.properties.map((p) {
                                              return DropdownMenuItem<String>(
                                                value: p.id,
                                                child: Text(p.name, overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (newProp) {
                                              if (newProp != null && newProp != selectedSourceProperty) {
                                                setDialogState(() => selectedSourceProperty = newProp);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: const Icon(
                                    Ionicons.arrowForward,
                                    size: 16,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TARGET PROPERTY',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 30,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Ionicons.business, size: 12, color: Color(0xFF10B981)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                currentAppState.activeProperty?.name ?? 'Active Property',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              // Source Month Selector
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SOURCE MONTH',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 30,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: dialogBg,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: sourceOptions.contains(selectedSource)
                                              ? selectedSource
                                              : (sourceOptions.isNotEmpty ? sourceOptions.first : null),
                                          isDense: true,
                                          isExpanded: true,
                                          icon: const Icon(Ionicons.chevronDown, size: 12),
                                          dropdownColor: dialogBg,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: textPrimary,
                                          ),
                                          items: sourceOptions.map((sKey) {
                                            return DropdownMenuItem<String>(
                                              value: sKey,
                                              child: Text(_formatKey(sKey)),
                                            );
                                          }).toList(),
                                          onChanged: (newSrc) {
                                            if (newSrc != null && newSrc != selectedSource) {
                                              setDialogState(() => selectedSource = newSrc);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: const Icon(
                                  Ionicons.arrowForward,
                                  size: 16,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              // Target Month Display
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'TARGET MONTH',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 30,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Ionicons.calendar, size: 12, color: Color(0xFF10B981)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              targetMonthTitle,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          ),
                                        ],
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
                    const SizedBox(height: 12),

                    // Metrics Strip
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSyncMetricChip(
                              icon: Ionicons.checkmarkCircle,
                              label: '$freshTotalCount Ready to Sync',
                              color: const Color(0xFF10B981),
                              isDark: isDark,
                            ),
                            if (dupTotalCount > 0) ...[
                              const SizedBox(width: 8),
                              _buildSyncMetricChip(
                                icon: Ionicons.alertCircleOutline,
                                label: '$dupTotalCount Duplicates (Skipped)',
                                color: const Color(0xFFF59E0B),
                                isDark: isDark,
                              ),
                            ],
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selectedType != 'expenses' && rItems.isNotEmpty)
                              Text(
                                'Rent: $cur ${totalRentAmount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                            if (selectedType == 'all' && rItems.isNotEmpty && eItems.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text('•', style: TextStyle(color: textSecondary)),
                              ),
                            if (selectedType != 'rentRoll' && eItems.isNotEmpty)
                              Text(
                                'Exp: $cur ${totalExpAmount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Preview Items List Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ENTRY PREVIEW (${rItems.length + eItems.length})',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            'STATUS',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable list of items
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: dialogBg,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          border: Border(
                            left: BorderSide(color: borderColor),
                            right: BorderSide(color: borderColor),
                            bottom: BorderSide(color: borderColor),
                          ),
                        ),
                        child: (rItems.isEmpty && eItems.isEmpty)
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 36),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Ionicons.folderOpenOutline, size: 28, color: textSecondary),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No entries found in ${_formatKey(selectedSource)}.',
                                        style: TextStyle(fontSize: 12, color: textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                children: [
                                  if (selectedType != 'expenses')
                                    for (final p in rItems)
                                      _buildSyncRentItem(
                                        payment: p,
                                        tenant: tenantById[p.tenantId],
                                        cur: cur,
                                        dupReason: rentDupReason(p),
                                        isDark: isDark,
                                        borderColor: borderColor,
                                      ),
                                  if (selectedType != 'rentRoll')
                                    for (final e in eItems)
                                      _buildSyncExpenseItem(
                                        expense: e,
                                        cur: cur,
                                        isDup: expDup(e),
                                        isDark: isDark,
                                        borderColor: borderColor,
                                      ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dialog Actions (Cancel & Confirm Sync)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: freshTotalCount == 0
                              ? null
                              : () {
                                  final n = ref.read(appDataProvider.notifier);
                                  if (selectedType != 'expenses') {
                                    final inFlightTenants = <String>{
                                      for (final e in exRent) e.tenantId
                                    };
                                    final inFlightUnits = <String>{
                                      for (final e in exRent)
                                        if (tenantById[e.tenantId]?.unit.trim().isNotEmpty ?? false)
                                          tenantById[e.tenantId]!.unit.trim()
                                    };

                                    for (final p in rItems) {
                                      final u = tenantById[p.tenantId]?.unit.trim() ?? '';
                                      if (inFlightTenants.contains(p.tenantId)) continue;
                                      if (u.isNotEmpty && inFlightUnits.contains(u)) continue;

                                      inFlightTenants.add(p.tenantId);
                                      if (u.isNotEmpty) inFlightUnits.add(u);

                                      final isSameProp = selectedSourceProperty == currentAppState.effectivePropertyId;
                                      String resolvedTenantId = p.tenantId;
                                      if (!isSameProp && u.isNotEmpty) {
                                        final targetMatch = currentAppState.scopedTenants
                                            .where((t) => t.unit.trim().toLowerCase() == u.toLowerCase())
                                            .firstOrNull;
                                        if (targetMatch != null) {
                                          resolvedTenantId = targetMatch.id;
                                        }
                                      }

                                      final t = tenantById[resolvedTenantId];
                                      final rentAmt = (t != null && t.rentAmount > 0)
                                          ? t.rentAmount
                                          : p.amount;

                                      n.upsertPayment(Payment(
                                        id: newId(),
                                        tenantId: resolvedTenantId,
                                        amount: rentAmt,
                                        status: 'pending',
                                        paidForMonth: targetMonthKey,
                                        displayMonth: targetMonthKey,
                                        propertyId: currentAppState.effectivePropertyId,
                                      ));
                                    }
                                  }
                                  if (selectedType != 'rentRoll') {
                                    final inFlightExp = <String>{
                                      for (final x in exExp)
                                        expSig(x.category, x.description, x.amount)
                                    };

                                    for (final e in eItems) {
                                      final sig = expSig(e.category, e.description, e.amount);
                                      if (inFlightExp.contains(sig)) continue;
                                      inFlightExp.add(sig);

                                      n.upsertExpense(Expense(
                                        id: newId(),
                                        category: e.category,
                                        description: e.description,
                                        amount: e.amount,
                                        date: DateTime.now().toIso8601String(),
                                        status: 'pending',
                                        expenseForMonth: targetMonthKey,
                                        displayMonth: targetMonthKey,
                                        propertyId: currentAppState.effectivePropertyId,
                                      ));
                                    }
                                  }
                                  Navigator.pop(ctx);
                                  showAppToast(
                                    context,
                                    'Synced $freshTotalCount ${freshTotalCount == 1 ? "entry" : "entries"} into $targetMonthTitle',
                                    isSuccess: true,
                                  );
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            disabledBackgroundColor: isDark
                                ? const Color(0xFF103333).withValues(alpha: 0.5)
                                : const Color(0xFFE2E8F0),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Ionicons.sync, size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                freshTotalCount == 0
                                    ? 'Nothing to Sync'
                                    : 'Confirm Sync ($freshTotalCount)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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
        },
      ),
    );
  }

  Widget _buildSyncTypePill(
    String type,
    String label,
    String currentType,
    bool isDark,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = type == currentType;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(type),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF10B981).withValues(alpha: 0.22) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF10B981))
                  : Colors.transparent,
            ),
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncMetricChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncRentItem({
    required Payment payment,
    required Tenant? tenant,
    required String cur,
    required String? dupReason,
    required bool isDark,
    required Color borderColor,
  }) {
    final isDup = dupReason != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Ionicons.cashOutline, size: 13, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tenant?.name ?? 'Tenant',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    if (tenant?.unit.isNotEmpty == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF10282A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          tenant!.unit,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Rent Roll • $cur ${payment.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (isDup)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.alertCircle, size: 11, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 3.5),
                  Text(
                    dupReason,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Ionicons.checkmark, size: 11, color: Color(0xFF10B981)),
                  SizedBox(width: 3.5),
                  Text(
                    'Ready',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSyncExpenseItem({
    required Expense expense,
    required String cur,
    required bool isDup,
    required bool isDark,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Icon(Ionicons.receiptOutline, size: 13, color: Color(0xFFEF4444)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        expense.description.isNotEmpty ? expense.description : expense.category,
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
                      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF10282A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        expense.category,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Expense • $cur ${expense.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (isDup)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Ionicons.alertCircle, size: 11, color: Color(0xFFF59E0B)),
                  SizedBox(width: 3.5),
                  Text(
                    'Duplicate',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Ionicons.checkmark, size: 11, color: Color(0xFF10B981)),
                  SizedBox(width: 3.5),
                  Text(
                    'Ready',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final cur = s.selectedCurrency;
    final isDark = AppColors.isDark;
    final mk = _key(s.selectedYear, _month);

    final monthPayments = s.scopedPayments
        .where((p) =>
            (p.paidForMonth ?? p.displayMonth ?? p.paidDate ?? '')
                .startsWith(mk))
        .toList();
    final monthExpenses = s.scopedExpenses
        .where((e) =>
            (e.expenseForMonth ?? e.displayMonth ?? e.date).startsWith(mk))
        .toList();

    double sumWhere(Iterable<Payment> ps, bool Function(Payment) f) =>
        ps.where(f).fold(0.0, (a, p) => a + p.amount);

    final income = sumWhere(monthPayments, (p) => p.status == 'paid');
    final pending = sumWhere(monthPayments, (p) => p.status != 'paid');
    // Match the mobile overview: pending expenses are not money spent yet.
    final spent = monthExpenses
        .where((e) => e.status == 'paid' || e.status.isEmpty)
        .fold<double>(0, (a, e) => a + e.amount);
    final net = income - spent;

    final totalUnits = s.scopedTenants.length;
    final paidUnits = monthPayments.where((p) => p.status == 'paid').length;
    final occupancyRate = totalUnits == 0
        ? 100.0
        : ((paidUnits / totalUnits) * 100).clamp(0.0, 100.0);

    final tenantById = {for (final t in s.scopedTenants) t.id: t};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        children: [
          // 1. Month / Year Control Header
          _buildMonthHeader(s, isDark),

          const SizedBox(height: 10),

          // 2. Bento Row: 5 Metric Cards (Compact)
          _buildKpiGrid(cur, income, spent, net, pending, occupancyRate, isDark),

          const SizedBox(height: 10),

          // 3. Bento Row: Analytics & Rent / Expenses Breakdown
          RepaintBoundary(
            child: _buildAnalyticsRow(monthPayments, monthExpenses, cur, isDark),
          ),

          const SizedBox(height: 10),

          // 4. Bento Row: Live Rent Roll & Expense Roll Tables Side-by-Side
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 850;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: RepaintBoundary(
                        child: _buildRentRollTable(
                            monthPayments, tenantById, cur, income, pending, mk, isDark),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: RepaintBoundary(
                        child: _buildExpenseRollTable(
                            monthExpenses, cur, spent, mk, isDark),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    RepaintBoundary(
                      child: _buildRentRollTable(
                          monthPayments, tenantById, cur, income, pending, mk, isDark),
                    ),
                    const SizedBox(height: 10),
                    RepaintBoundary(
                      child: _buildExpenseRollTable(
                          monthExpenses, cur, spent, mk, isDark),
                    ),
                  ],
                );
              }
            },
          ),

          const SizedBox(height: 10),

          // 5. Bento Row: Monthly Checklist Notes & Bank Deposits
          _buildNotesAndDepositsSection(s, cur, mk, income, spent, net, isDark),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(AppDataState s, bool isDark) {
    final availableYears = <int>{
      DateTime.now().year - 3,
      DateTime.now().year - 2,
      DateTime.now().year - 1,
      DateTime.now().year,
      DateTime.now().year + 1,
      DateTime.now().year + 2,
      s.selectedYear,
    };
    for (final p in s.scopedPayments) {
      final y = DateTime.tryParse(p.paidForMonth ?? '')?.year ??
          DateTime.tryParse(p.paidDate ?? '')?.year;
      if (y != null) availableYears.add(y);
    }
    for (final e in s.scopedExpenses) {
      final y = DateTime.tryParse(e.expenseForMonth ?? '')?.year ??
          DateTime.tryParse(e.date)?.year;
      if (y != null) availableYears.add(y);
    }
    final sortedYears = availableYears.toList()..sort();

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 820;

          // Header badge & title
          final titleWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5.5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF103333)
                      : const Color(0xFFEDF7F4),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Ionicons.calendarOutline,
                  size: 14,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ACCOUNTING PERIOD',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  Text(
                    '${_monthNames[_month]} ${s.selectedYear}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.heading,
                    ),
                  ),
                ],
              ),
            ],
          );

          // All 12 months in a horizontal segmented track
          final monthsTrack = Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF051718).withValues(alpha: 0.6)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.05)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int m = 1; m <= 12; m++) ...[
                    if (m > 1) const SizedBox(width: 2),
                    _buildMonthPill(m, isDark),
                  ],
                ],
              ),
            ),
          );

          // Year dropdown selector on the right
          final yearDropdown = Container(
            height: 29,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0C2425)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.08)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Ionicons.calendar,
                  size: 12,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669),
                ),
                const SizedBox(width: 5),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: s.selectedYear,
                    icon: const Padding(
                      padding: EdgeInsets.only(left: 3),
                      child: Icon(Ionicons.chevronDown, size: 11),
                    ),
                    dropdownColor: isDark
                        ? const Color(0xFF0F2627)
                        : Colors.white,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                    onChanged: (int? newYear) {
                      if (newYear != null && newYear != s.selectedYear) {
                        ref.read(appDataProvider.notifier).setYear(newYear);
                      }
                    },
                    items: sortedYears.map((int y) {
                      return DropdownMenuItem<int>(
                        value: y,
                        child: Text(
                          '$y',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );

          final syncPeriodButton = Tooltip(
            message: 'Sync previous period roll & expenses',
            waitDuration: const Duration(milliseconds: 400),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showDesktopSyncDialog(context, 'all'),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  height: 29,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF0F766E), Color(0xFF10B981)]
                          : const [Color(0xFF059669), Color(0xFF10B981)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.35),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: isDark ? 0.35 : 0.22),
                        blurRadius: 5,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Ionicons.sync,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Sync',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleWidget,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        syncPeriodButton,
                        const SizedBox(width: 8),
                        yearDropdown,
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(child: monthsTrack),
              ],
            );
          }

          return Row(
            children: [
              titleWidget,
              Container(
                height: 20,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: borderColor,
              ),
              Expanded(
                child: Center(
                  child: monthsTrack,
                ),
              ),
              Container(
                height: 20,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: borderColor,
              ),
              yearDropdown,
              const SizedBox(width: 8),
              syncPeriodButton,
              const SizedBox(width: 6),
              Tooltip(
                message: 'Executive Financial Health & Cash Flow Forecast (⇧⌘F)',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openCashFlowForecast,
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      height: 29,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.35),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.22),
                            blurRadius: 5,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.analyticsOutline, size: 12, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'Forecast',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMonthPill(int m, bool isDark) {
    final isSelected = m == _month;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _month = m);
        },
        borderRadius: BorderRadius.circular(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF059669) : const Color(0xFF0F766E))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            _shortMonthNames[m],
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiGrid(String cur, double income, double spent, double net,
      double pending, double occupancyRate, bool isDark) {
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 820;
      final cards = [
        _kpiCard(
          title: 'Collected Rent',
          value: '$cur ${income.toStringAsFixed(0)}',
          subtitle: 'Paid rent this month',
          icon: Ionicons.trendingUp,
          accentColor: const Color(0xFF10B981),
          isDark: isDark,
        ),
        _kpiCard(
          title: 'Total Expenses',
          value: '$cur ${spent.toStringAsFixed(0)}',
          subtitle: 'Spent this month',
          icon: Ionicons.trendingDown,
          accentColor: const Color(0xFFEF4444),
          isDark: isDark,
        ),
        _kpiCard(
          title: 'Net Cash Flow',
          value: '$cur ${net.toStringAsFixed(0)}',
          subtitle: net >= 0 ? 'Operating surplus' : 'Operating deficit',
          icon: Ionicons.wallet,
          accentColor: net >= 0
              ? const Color(0xFF10B981)
              : const Color(0xFFEF4444),
          isDark: isDark,
        ),
        _kpiCard(
          title: 'Pending & Overdue',
          value: '$cur ${pending.toStringAsFixed(0)}',
          subtitle: pending > 0 ? 'Action required' : 'All clear',
          icon: Ionicons.alertCircle,
          accentColor: pending > 0
              ? const Color(0xFFF59E0B)
              : const Color(0xFF10B981),
          isDark: isDark,
        ),
        _kpiCard(
          title: 'Occupancy Rate',
          value: '${occupancyRate.toStringAsFixed(0)}%',
          subtitle: 'Active rented units',
          icon: Ionicons.business,
          accentColor: const Color(0xFF06B6D4),
          isDark: isDark,
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
          const SizedBox(width: 8),
          Expanded(child: cards[1]),
          const SizedBox(width: 8),
          Expanded(child: cards[2]),
          const SizedBox(width: 8),
          Expanded(child: cards[3]),
          const SizedBox(width: 8),
          Expanded(child: cards[4]),
        ],
      );
    });
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? _openCashFlowForecast,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.transparent,
        child: HoverTinter(
          builder: (hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
      decoration: BoxDecoration(
        color: isDark
            ? Color.alphaBlend(
                hovered ? const Color.fromRGBO(255, 255, 255, 0.07) : const Color(0x00000000),
                const Color(0xFF091E1F))
            : hovered ? const Color(0xFFF5FAF8) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.08)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
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
              fontWeight: FontWeight.w500,
              color: accentColor,
            ),
          ),
        ],
      ),
        ),
      ),
    ),
  );
}

  Widget _buildAnalyticsRow(List<Payment> monthPayments,
      List<Expense> monthExpenses, String cur, bool isDark) {
    // Rent metrics
    final paidPayments = monthPayments.where((p) => p.status == 'paid');
    final paidRentCount = paidPayments.length;
    final totalRentCount = monthPayments.length;
    final paidRentRatio = totalRentCount == 0 ? 0.0 : (paidRentCount / totalRentCount).clamp(0.0, 1.0);
    final paidRentAmount = paidPayments.fold<double>(0.0, (a, p) => a + p.amount);
    final pendingRentAmount = monthPayments
        .where((p) => p.status != 'paid')
        .fold<double>(0.0, (a, p) => a + p.amount);

    // Expense metrics
    final totalExpenseCount = monthExpenses.length;
    final paidExpenses = monthExpenses.where((e) => e.status == 'paid' || e.status.isEmpty);
    final pendingExpenses = monthExpenses.where((e) => e.status == 'pending');
    final paidExpenseCount = paidExpenses.length;
    final pendingExpenseCount = pendingExpenses.length;
    final paidExpenseAmount = paidExpenses.fold<double>(0.0, (a, e) => a + e.amount);
    final pendingExpenseAmount = pendingExpenses.fold<double>(0.0, (a, e) => a + e.amount);
    final totalSpent = monthExpenses.fold<double>(0.0, (a, e) => a + e.amount);
    final expensePaidRatio = totalSpent == 0
        ? 0.0
        : (paidExpenseAmount / totalSpent).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;
        final isMedium = constraints.maxWidth >= 680 && constraints.maxWidth < 1050;

        final rentCard = Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E1F) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Ionicons.cashOutline,
                        size: 13, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rent Collection Status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$paidRentCount of $totalRentCount Paid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _verticalStatusBar(
                    ratio: paidRentRatio,
                    paidColor: const Color(0xFF10B981),
                    pendingColor: const Color(0xFFF59E0B),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _legendItem(
                          'Paid',
                          '$cur ${paidRentAmount.toStringAsFixed(0)} ($paidRentCount)',
                          const Color(0xFF10B981),
                          isDark,
                        ),
                        const SizedBox(height: 4),
                        _legendItem(
                          'Pending',
                          '$cur ${pendingRentAmount.toStringAsFixed(0)} (${totalRentCount - paidRentCount})',
                          const Color(0xFFF59E0B),
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final expenseCard = Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E1F) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Ionicons.receiptOutline,
                        size: 13, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Expenses Summary Status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$paidExpenseCount of $totalExpenseCount Settled',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: pendingExpenseCount == 0
                          ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _verticalStatusBar(
                    ratio: expensePaidRatio,
                    paidColor: pendingExpenseCount == 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    pendingColor: const Color(0xFFEF4444),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _legendItem(
                          'Settled',
                          '$cur ${paidExpenseAmount.toStringAsFixed(0)} ($paidExpenseCount)',
                          const Color(0xFF10B981),
                          isDark,
                        ),
                        const SizedBox(height: 4),
                        _legendItem(
                          'Pending',
                          '$cur ${pendingExpenseAmount.toStringAsFixed(0)} ($pendingExpenseCount)',
                          const Color(0xFFF59E0B),
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (isWide || isMedium) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: rentCard),
              const SizedBox(width: 12),
              Expanded(child: expenseCard),
            ],
          );
        }

        return Column(
          children: [
            rentCard,
            const SizedBox(height: 10),
            expenseCard,
          ],
        );
      },
    );
  }

  Widget _verticalStatusBar({
    required double ratio,
    required Color paidColor,
    required Color pendingColor,
    required bool isDark,
  }) {
    final r = ratio.clamp(0.0, 1.0);
    return Container(
      width: 12,
      height: 46,
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.05)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.08)
              : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 1 - r,
              widthFactor: 1,
              child: ColoredBox(
                color: pendingColor.withValues(alpha: isDark ? 0.45 : 0.55),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: r,
              widthFactor: 1,
              child: ColoredBox(color: paidColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(
      String label, String value, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppColors.heading,
          ),
        ),
      ],
    );
  }

  String _formatDateShort(String d) {
    if (d.isEmpty) return '';
    final dt = DateTime.tryParse(d);
    if (dt != null && dt.month >= 1 && dt.month <= 12) {
      return '${dt.day} ${_shortMonthNames[dt.month]}';
    }
    if (d.length >= 10) {
      final clean = d.substring(0, 10);
      final parts = clean.split('-');
      if (parts.length == 3) {
        final mIndex = int.tryParse(parts[1]) ?? 0;
        final day = int.tryParse(parts[2]) ?? 0;
        if (mIndex >= 1 && mIndex <= 12 && day > 0) {
          return '$day ${_shortMonthNames[mIndex]}';
        }
      }
    }
    return d.length > 5 ? d.substring(5) : d;
  }

  Widget _buildTenantAvatar(Tenant? tenant, bool isDark) {
    return AvatarView(
      name: tenant?.name ?? 'UT',
      uri: tenant?.avatar,
      radius: 12.5,
      borderColor: isDark
          ? const Color(0xFF144547)
          : const Color(0xFF99F6E4),
      borderWidth: 1.0,
    );
  }

  Widget _buildFilterTab({
    required String label,
    required int count,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.20 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: isDark ? 0.6 : 0.45)
                  : (isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.08)
                      : const Color(0xFFE2E8F0)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (AppColors.heading)
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: isDark ? 0.35 : 0.22)
                      : (isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.06)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? activeColor
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

  Widget _buildMetricStripItem({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  static _ExpenseCategoryStyle _getExpenseCategoryStyle(
      String category, bool isDark) {
    final cat = category.toLowerCase().trim();
    if (cat.contains('utilit') ||
        cat.contains('elect') ||
        cat.contains('power') ||
        cat.contains('water') ||
        cat.contains('gas')) {
      return _ExpenseCategoryStyle(
        Ionicons.flashOutline,
        const Color(0xFFF59E0B),
        const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('clean') ||
        cat.contains('janitor') ||
        cat.contains('wash') ||
        cat.contains('trash')) {
      return _ExpenseCategoryStyle(
        Ionicons.sparklesOutline,
        const Color(0xFF06B6D4),
        const Color(0xFF06B6D4).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('maint') ||
        cat.contains('repair') ||
        cat.contains('plumb') ||
        cat.contains('fix') ||
        cat.contains('labor')) {
      return _ExpenseCategoryStyle(
        Ionicons.buildOutline,
        const Color(0xFFF97316),
        const Color(0xFFF97316).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('prop') ||
        cat.contains('manage') ||
        cat.contains('fee') ||
        cat.contains('admin')) {
      return _ExpenseCategoryStyle(
        Ionicons.businessOutline,
        const Color(0xFF8B5CF6),
        const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('suppl') ||
        cat.contains('mater') ||
        cat.contains('hardware') ||
        cat.contains('item')) {
      return _ExpenseCategoryStyle(
        Ionicons.cubeOutline,
        const Color(0xFF10B981),
        const Color(0xFF10B981).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('tax') ||
        cat.contains('legal') ||
        cat.contains('insur') ||
        cat.contains('law')) {
      return _ExpenseCategoryStyle(
        Ionicons.shieldCheckmarkOutline,
        const Color(0xFF6366F1),
        const Color(0xFF6366F1).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    } else if (cat.contains('internet') ||
        cat.contains('wifi') ||
        cat.contains('phone') ||
        cat.contains('network')) {
      return _ExpenseCategoryStyle(
        Ionicons.wifiOutline,
        const Color(0xFF3B82F6),
        const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.16 : 0.10),
      );
    }
    return _ExpenseCategoryStyle(
      Ionicons.receiptOutline,
      const Color(0xFFEC4899),
      const Color(0xFFEC4899).withValues(alpha: isDark ? 0.16 : 0.10),
    );
  }

  Widget _buildRentRollTable(
      List<Payment> monthPayments,
      Map<String, Tenant> tenantById,
      String cur,
      double income,
      double pending,
      String mk,
      bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final headerColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final paidPayments =
        monthPayments.where((p) => p.status == 'paid').toList();
    final pendingPayments =
        monthPayments.where((p) => p.status != 'paid').toList();
    final totalExpected =
        monthPayments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final collectionRate =
        totalExpected > 0 ? (income / totalExpected * 100) : 0.0;

    final paymentsByTenant = <String, List<Payment>>{};
    for (final p in monthPayments) {
      if (p.tenantId.isNotEmpty) {
        paymentsByTenant.putIfAbsent(p.tenantId, () => []).add(p);
      }
    }

    int compareByUnit(Payment p1, Payment p2) {
      final u1 = tenantById[p1.tenantId]?.unit ?? '';
      final u2 = tenantById[p2.tenantId]?.unit ?? '';
      if (u1.isEmpty && u2.isEmpty) return 0;
      if (u1.isEmpty) return 1;
      if (u2.isEmpty) return -1;
      final ra = RegExp(r'(\d+)').firstMatch(u1);
      final rb = RegExp(r'(\d+)').firstMatch(u2);
      if (ra != null && rb != null) {
        final c = int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
        if (c != 0) return c;
      }
      return u1.compareTo(u2);
    }

    List<Payment> displayPayments;
    if (_rentRollFilter == 'paid') {
      displayPayments = paidPayments..sort(compareByUnit);
    } else if (_rentRollFilter == 'pending') {
      displayPayments = pendingPayments..sort(compareByUnit);
    } else {
      displayPayments = List<Payment>.from(monthPayments)..sort(compareByUnit);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 530;
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF10B981)],
                        ),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.28),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Ionicons.walletOutline,
                        size: 13.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rent Roll',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color:
                              AppColors.heading,
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),
                    _buildHeaderQuickButton(
                      isActive: _showQuickRentRollBar,
                      isDark: isDark,
                      tooltip: _showQuickRentRollBar
                          ? 'Close quick rent logger'
                          : 'Instant Rent Roll Logger (Quick Add)',
                      gradientColors: const [Color(0xFF047857), Color(0xFF10B981)],
                      onTap: () => setState(
                          () => _showQuickRentRollBar = !_showQuickRentRollBar),
                    ),
                    const SizedBox(width: 5),
                    _buildHeaderActionButton(
                      label: isCompact ? 'Add' : 'Add Rent',
                      tooltip: 'Record rent payment for this month',
                      isDark: isDark,
                      onTap: () => OverviewView.showPaymentSheet(context),
                    ),
                    const SizedBox(width: 5),
                    _buildHeaderActionButton(
                      label: isCompact ? 'Batch' : 'Batch Collect',
                      tooltip: 'Batch collect monthly rent from all active tenants (⇧⌘B)',
                      icon: Ionicons.layersOutline,
                      gradientColors: const [Color(0xFF2563EB), Color(0xFF4F46E5)],
                      isDark: isDark,
                      onTap: () {
                        final selectedYear = ref.read(appDataProvider).selectedYear;
                        DesktopBatchRentModal.show(context, year: selectedYear, month: _month);
                      },
                    ),
                    const SizedBox(width: 5),
                    _buildHeaderSyncButton(
                      label: isCompact ? 'Sync' : 'Sync Roll',
                      tooltip: 'Sync Rent Roll from previous month',
                      isDark: isDark,
                      onTap: () => _showDesktopSyncDialog(context, 'rentRoll'),
                    ),
                  ],
                );
              },
            ),
          ),

          // Inline Quick Rent Roll Input Bar
          if (_showQuickRentRollBar)
            _buildQuickRentRollBar(mk, cur, isDark, borderColor),

          // Dedicated Filter Row
          if (monthPayments.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
              color:
                  isDark ? const Color(0xFF07191A) : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  _buildFilterTab(
                    label: 'All',
                    count: monthPayments.length,
                    isSelected: _rentRollFilter == 'all',
                    activeColor: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () => setState(() => _rentRollFilter = 'all'),
                  ),
                  const SizedBox(width: 5),
                  _buildFilterTab(
                    label: 'Paid',
                    count: paidPayments.length,
                    isSelected: _rentRollFilter == 'paid',
                    activeColor: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () => setState(() => _rentRollFilter = 'paid'),
                  ),
                  const SizedBox(width: 5),
                  _buildFilterTab(
                    label: 'Due',
                    count: pendingPayments.length,
                    isSelected: _rentRollFilter == 'pending',
                    activeColor: const Color(0xFFF59E0B),
                    isDark: isDark,
                    onTap: () =>
                        setState(() => _rentRollFilter = 'pending'),
                  ),
                ],
              ),
            ),

          // Executive Metric Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF061A1B) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.05)
                      : const Color(0xFFE2E8F0),
                ),
                bottom: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.06)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'EXPECTED',
                    value: '$cur ${totalExpected.toStringAsFixed(0)}',
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF334155),
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'COLLECTED',
                    value:
                        '$cur ${income.toStringAsFixed(0)} (${collectionRate.toStringAsFixed(0)}%)',
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'DUE',
                    value: '$cur ${pending.toStringAsFixed(0)}',
                    color: pending > 0
                        ? const Color(0xFFF59E0B)
                        : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // Table Column Headers
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
            color: isDark ? const Color(0xFF091E1F) : const Color(0xFFF1F5F9),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    'UNIT',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'TENANT & CONTACT',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: Text(
                    'RENT',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 65,
                  child: Text(
                    'STATUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.06)
                : const Color(0xFFE2E8F0),
          ),

          // Table Body
          if (monthPayments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: isDark ? 0.12 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Ionicons.walletOutline,
                        size: 24,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No rent roll entries for this month.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildEmptyStateSyncButton(
                      label: 'Sync Previous Month Rent Roll',
                      isDark: isDark,
                      onTap: () => _showDesktopSyncDialog(context, 'rentRoll'),
                    ),
                  ],
                ),
              ),
            )
          else if (displayPayments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No ${_rentRollFilter.toUpperCase()} units in this period.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() => _rentRollFilter = 'all'),
                      child: const Text('Show all units',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < displayPayments.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.04)
                          : const Color(0xFFF1F5F9),
                    ),
                  () {
                    final p = displayPayments[i];
                    final t = tenantById[p.tenantId];
                    final isPaid = p.status == 'paid';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        hoverColor: isDark
                            ? const Color(0xFF0F2E2F)
                            : const Color(0xFFF8FAFC),
                        onTap: () {
                          if (widget.onPaymentDetails != null) {
                            widget.onPaymentDetails!(p, t);
                          } else if (widget.onEditPayment != null) {
                            widget.onEditPayment!(p, t);
                          } else if (t != null) {
                            widget.onSelectTenant(t);
                          }
                        },
                        onSecondaryTapDown: (details) =>
                            _showPaymentContextMenu(context, details.globalPosition, p, t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6.5),
                          child: Row(
                            children: [
                              // Unit Badge
                              SizedBox(
                                width: 52,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0C2A2B)
                                          : const Color(0xFFE6F4F1),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF144547)
                                            : const Color(0xFFBBE5DD),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      t?.unit.isNotEmpty == true
                                          ? '#${t!.unit}'
                                          : '—',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'monospace',
                                        color: isDark
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Tenant Avatar & Details
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    _buildTenantAvatar(t, isDark),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            t?.name ?? 'Unknown Tenant',
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
                                          Text(
                                            isPaid
                                                ? (p.paidDate != null &&
                                                        p.paidDate!.isNotEmpty
                                                    ? 'Paid • ${_formatDateShort(p.paidDate!)}'
                                                    : 'Paid in full')
                                                : (t != null &&
                                                        t.phone.isNotEmpty
                                                    ? t.phone
                                                    : 'Due for this month'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              color: isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Amount Column
                              SizedBox(
                                width: 78,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$cur ${p.amount.toStringAsFixed(0)}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      isPaid ? 'Collected' : 'Pending',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: isPaid
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Status Pill
                              SizedBox(
                                width: 65,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? const Color(0xFF10B981).withValues(
                                              alpha: isDark ? 0.16 : 0.12)
                                          : const Color(0xFFF59E0B).withValues(
                                              alpha: isDark ? 0.16 : 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: isPaid
                                            ? const Color(0xFF10B981)
                                                .withValues(
                                                    alpha: isDark ? 0.4 : 0.3)
                                            : const Color(0xFFF59E0B)
                                                .withValues(
                                                    alpha: isDark ? 0.4 : 0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isPaid
                                                ? Ionicons.checkmarkCircle
                                                : Ionicons.timeOutline,
                                            size: 9.5,
                                            color: isPaid
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFF59E0B),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            isPaid ? 'PAID' : 'DUE',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                              color: isPaid
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ],
                                      ),
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
              ],
            ),

          // Footer Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF07191A) : const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.05)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Showing ${displayPayments.length} of ${monthPayments.length} units',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                Text(
                  'Total: $cur ${displayPayments.fold<double>(0.0, (s, p) => s + p.amount).toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseRollTable(List<Expense> monthExpenses, String cur,
      double totalSpent, String mk, bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final headerColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final paidExpenses = monthExpenses
        .where((e) => e.status == 'paid' || e.status.isEmpty)
        .toList();
    final pendingExpenses =
        monthExpenses.where((e) => e.status == 'pending').toList();
    final pendingSpent =
        pendingExpenses.fold<double>(0.0, (a, e) => a + e.amount);
    final settledSpent = totalSpent - pendingSpent;

    List<Expense> displayExpenses;
    if (_expenseFilter == 'paid') {
      displayExpenses = paidExpenses;
    } else if (_expenseFilter == 'pending') {
      displayExpenses = pendingExpenses;
    } else {
      displayExpenses = monthExpenses;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFBE123C), Color(0xFFF43F5E)],
                    ),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFF43F5E).withValues(alpha: 0.28),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Ionicons.receiptOutline,
                    size: 13.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Expenses',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color:
                          AppColors.heading,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildHeaderQuickButton(
                  isActive: _showQuickExpenseBar,
                  isDark: isDark,
                  tooltip: _showQuickExpenseBar
                      ? 'Close quick expense logger'
                      : 'Instant Expense Logger (Quick Add)',
                  gradientColors: const [Color(0xFF0F766E), Color(0xFF0D9488)],
                  onTap: () => setState(
                      () => _showQuickExpenseBar = !_showQuickExpenseBar),
                ),
                const SizedBox(width: 5),
                _buildHeaderActionButton(
                  label: 'Add Expense',
                  tooltip: 'Record expense for this month',
                  isDark: isDark,
                  gradientColors: const [
                    Color(0xFFBE123C),
                    Color(0xFFE11D48)
                  ],
                  icon: Ionicons.add,
                  onTap: () => OverviewView.showExpenseSheet(context),
                ),
                const SizedBox(width: 5),
                _buildHeaderSyncButton(
                  label: 'Sync Expenses',
                  tooltip: 'Sync Expenses from previous month',
                  isDark: isDark,
                  onTap: () => _showDesktopSyncDialog(context, 'expenses'),
                ),
              ],
            ),
          ),

          // Inline Quick Expense Input Bar
          if (_showQuickExpenseBar)
            _buildQuickExpenseBar(mk, cur, isDark, borderColor),
          // Dedicated Filter Row
          if (monthExpenses.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
              color:
                  isDark ? const Color(0xFF07191A) : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  _buildFilterTab(
                    label: 'All',
                    count: monthExpenses.length,
                    isSelected: _expenseFilter == 'all',
                    activeColor: const Color(0xFFEF4444),
                    isDark: isDark,
                    onTap: () => setState(() => _expenseFilter = 'all'),
                  ),
                  const SizedBox(width: 5),
                  _buildFilterTab(
                    label: 'Pending',
                    count: pendingExpenses.length,
                    isSelected: _expenseFilter == 'pending',
                    activeColor: const Color(0xFFF59E0B),
                    isDark: isDark,
                    onTap: () =>
                        setState(() => _expenseFilter = 'pending'),
                  ),
                  const SizedBox(width: 5),
                  _buildFilterTab(
                    label: 'Paid',
                    count: paidExpenses.length,
                    isSelected: _expenseFilter == 'paid',
                    activeColor: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () => setState(() => _expenseFilter = 'paid'),
                  ),
                ],
              ),
            ),

          // Executive Metric Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF061A1B) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.05)
                      : const Color(0xFFE2E8F0),
                ),
                bottom: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.06)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'TOTAL',
                    value: '$cur ${totalSpent.toStringAsFixed(0)}',
                    color: const Color(0xFFEF4444),
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'SETTLED',
                    value: '$cur ${settledSpent.toStringAsFixed(0)}',
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildMetricStripItem(
                    label: 'PENDING',
                    value: '$cur ${pendingSpent.toStringAsFixed(0)}',
                    color: pendingSpent > 0
                        ? const Color(0xFFF59E0B)
                        : (isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B)),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // Table Column Headers
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
            color: isDark ? const Color(0xFF091E1F) : const Color(0xFFF1F5F9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EXPENSE / DESCRIPTION',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    'DATE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    'AMOUNT',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 65,
                  child: Text(
                    'STATUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: headerColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.06)
                : const Color(0xFFE2E8F0),
          ),

          // Table Body
          if (monthExpenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: isDark ? 0.12 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Ionicons.receiptOutline,
                        size: 24,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No expenses recorded for this month.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildEmptyStateSyncButton(
                      label: 'Sync Previous Month Expenses',
                      isDark: isDark,
                      onTap: () => _showDesktopSyncDialog(context, 'expenses'),
                    ),
                  ],
                ),
              ),
            )
          else if (displayExpenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No ${_expenseFilter.toUpperCase()} expenses in this period.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() => _expenseFilter = 'all'),
                      child: const Text('Show all expenses',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < displayExpenses.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.04)
                          : const Color(0xFFF1F5F9),
                    ),
                  () {
                    final e = displayExpenses[i];
                    final dateFormatted = _formatDateShort(e.date);
                    final isPaid = e.status == 'paid' || e.status.isEmpty;
                    final catStyle =
                        _getExpenseCategoryStyle(e.category, isDark);

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        hoverColor: isDark
                            ? const Color(0xFF0F2E2F)
                            : const Color(0xFFF8FAFC),
                        onTap: () {
                          if (widget.onExpenseDetails != null) {
                            widget.onExpenseDetails!(e);
                          } else {
                            widget.onEditExpense?.call(e);
                          }
                        },
                        onSecondaryTapDown: (details) =>
                            _showExpenseContextMenu(context, details.globalPosition, e),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6.5),
                          child: Row(
                            children: [
                              // Combined Description + Category Tag below
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      e.description.isNotEmpty
                                          ? e.description
                                          : e.category,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Category Tag
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: catStyle.bgColor,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: catStyle.color.withValues(
                                                  alpha: isDark ? 0.35 : 0.25),
                                              width: 0.7,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(catStyle.icon,
                                                  size: 9.5,
                                                  color: catStyle.color),
                                              const SizedBox(width: 3),
                                              Text(
                                                e.category,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: catStyle.color,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if ((e.receipt != null &&
                                                e.receipt!.isNotEmpty) ||
                                            e.receiptFiles.isNotEmpty) ...[
                                          const SizedBox(width: 5),
                                          Tooltip(
                                            message: 'View Attached Receipt',
                                            child: InkWell(
                                              onTap: () {
                                                final r = (e.receipt != null &&
                                                        e.receipt!.isNotEmpty)
                                                    ? e.receipt!
                                                    : e.receiptFiles.first;
                                                MediaFiles.open(r);
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4.5,
                                                        vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF3B82F6)
                                                      .withValues(alpha: 0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: const Color(0xFF3B82F6)
                                                        .withValues(alpha: 0.35),
                                                    width: 0.7,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Ionicons.attachOutline,
                                                        size: 9.5,
                                                        color: Color(0xFF3B82F6)),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'Receipt',
                                                      style: TextStyle(
                                                        fontSize: 8.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(0xFF3B82F6),
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
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Date Column
                              SizedBox(
                                width: 48,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0C2021)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      dateFormatted,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Amount Column
                              SizedBox(
                                width: 72,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '-$cur ${e.amount.toStringAsFixed(0)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                    Text(
                                      isPaid ? 'Settled' : 'Pending',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: isPaid
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Status Pill
                              SizedBox(
                                width: 68,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? const Color(0xFF10B981).withValues(
                                              alpha: isDark ? 0.16 : 0.12)
                                          : const Color(0xFFF59E0B).withValues(
                                              alpha: isDark ? 0.16 : 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: isPaid
                                            ? const Color(0xFF10B981)
                                                .withValues(
                                                    alpha: isDark ? 0.4 : 0.3)
                                            : const Color(0xFFF59E0B)
                                                .withValues(
                                                    alpha: isDark ? 0.4 : 0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isPaid
                                                ? Ionicons.checkmarkCircle
                                                : Ionicons.timeOutline,
                                            size: 9.5,
                                            color: isPaid
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFF59E0B),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            isPaid ? 'PAID' : 'PENDING',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                              color: isPaid
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ],
                                      ),
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
              ],
            ),

          // Footer Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF07191A) : const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.05)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Showing ${displayExpenses.length} of ${monthExpenses.length} entries',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                Text(
                  'Total: $cur ${displayExpenses.fold<double>(0.0, (s, e) => s + e.amount).toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitQuickRentRoll(String mk, String cur) {
    final s = ref.read(appDataProvider);
    final activeTenants =
        s.scopedTenants.where((t) => t.status != 'inactive').toList();
    if (activeTenants.isEmpty) {
      _safeToast('No active tenants available to record rent', isError: true);
      return;
    }
    final tenantId = _quickRentTenantId ?? activeTenants.first.id;
    final tenant = s.scopedTenants.firstWhere(
      (t) => t.id == tenantId,
      orElse: () => activeTenants.first,
    );
    final amt = double.tryParse(_quickRentAmountController.text.trim()) ??
        tenant.rentAmount;
    if (amt <= 0) {
      _safeToast('Please enter a valid rent amount', isError: true);
      return;
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final notes = _quickRentNotesController.text.trim();
    final newPayment = Payment(
      id: newId(),
      tenantId: tenant.id,
      amount: amt,
      status: _quickRentStatus,
      paidDate: _quickRentStatus == 'paid' ? today : null,
      paidForMonth: mk,
      displayMonth: mk,
      notes: notes.isNotEmpty ? notes : null,
      propertyId: tenant.propertyId,
    );
    ref.read(appDataProvider.notifier).upsertPayment(newPayment);
    _quickRentNotesController.clear();
    _safeToast(
      'Recorded ${_quickRentStatus == 'paid' ? 'Paid' : 'Pending'} Rent: ${tenant.name} ($cur ${amt.toStringAsFixed(0)})',
      isSuccess: true,
    );
  }

  Widget _buildQuickRentRollBar(
      String mk, String cur, bool isDark, Color borderColor) {
    final s = ref.read(appDataProvider);
    final activeTenants =
        s.scopedTenants.where((t) => t.status != 'inactive').toList();

    if (activeTenants.isNotEmpty) {
      if (_quickRentTenantId == null ||
          !activeTenants.any((t) => t.id == _quickRentTenantId)) {
        _quickRentTenantId = activeTenants.first.id;
        if (_quickRentAmountController.text.isEmpty &&
            activeTenants.first.rentAmount > 0) {
          _quickRentAmountController.text =
              activeTenants.first.rentAmount.toStringAsFixed(0);
        }
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071E19) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.flash, size: 13, color: Color(0xFF10B981)),
              const SizedBox(width: 5),
              Text(
                'Instant Rent Roll Logger',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const Spacer(),
              Text(
                'Month: ${_formatKey(mk)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => _showQuickRentRollBar = false),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Ionicons.close,
                    size: 14,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activeTenants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No active tenants found. Add a tenant to quickly log rent.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            )
          else
            Row(
              children: [
                // Tenant Selector
                Expanded(
                  flex: 4,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF081819) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _quickRentTenantId,
                        isExpanded: true,
                        dropdownColor:
                            isDark ? const Color(0xFF0F2627) : Colors.white,
                        isDense: true,
                        icon: Icon(
                          Ionicons.chevronDown,
                          size: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color:
                              AppColors.heading,
                        ),
                        items: activeTenants.map((t) {
                          return DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              '${t.name}${t.unit.isNotEmpty ? ' (${t.unit})' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _quickRentTenantId = val;
                              final hit = activeTenants.firstWhere(
                                  (t) => t.id == val,
                                  orElse: () => activeTenants.first);
                              if (hit.rentAmount > 0) {
                                _quickRentAmountController.text =
                                    hit.rentAmount.toStringAsFixed(0);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Status Dropdown (Paid / Pending)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF081819) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _quickRentStatus,
                      dropdownColor:
                          isDark ? const Color(0xFF0F2627) : Colors.white,
                      isDense: true,
                      icon: Icon(
                        Ionicons.chevronDown,
                        size: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _quickRentStatus == 'paid'
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text('Paid'),
                        ),
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _quickRentStatus = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Amount Field
                SizedBox(
                  width: 115,
                  height: 32,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF081819) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '$cur ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _quickRentAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*')),
                            ],
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _submitQuickRentRoll(mk, cur),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              fillColor: Colors.transparent,
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Notes Field (Optional)
              Expanded(
                flex: 3,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF081819) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Center(
                    child: TextField(
                      controller: _quickRentNotesController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitQuickRentRoll(mk, cur),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.heading,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: 'Notes / method (opt)...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Save button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 32),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Ionicons.checkmark, size: 14),
                label: const Text('Save',
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700)),
                onPressed: () => _submitQuickRentRoll(mk, cur),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submitQuickExpense(String mk, String cur) {
    final title = _quickExpenseTitleController.text.trim();
    final amt = double.tryParse(_quickExpenseAmountController.text.trim()) ?? 0.0;
    if (title.isEmpty) {
      _safeToast('Please enter an expense description', isError: true);
      return;
    }
    if (amt <= 0) {
      _safeToast('Please enter an amount greater than 0', isError: true);
      return;
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final newExp = Expense(
      id: newId(),
      category: _quickExpenseCategory,
      description: title,
      amount: amt,
      date: today,
      status: 'paid',
      paidDate: today,
      expenseForMonth: mk,
      displayMonth: mk,
    );
    ref.read(appDataProvider.notifier).upsertExpense(newExp);
    _quickExpenseTitleController.clear();
    _quickExpenseAmountController.clear();
    _safeToast(
      'Logged $_quickExpenseCategory: $cur ${amt.toStringAsFixed(0)}',
      isSuccess: true,
    );
  }

  Widget _buildQuickExpenseBar(
      String mk, String cur, bool isDark, Color borderColor) {
    final s = ref.read(appDataProvider);
    final appCategories = s.expenseCategories
        .map((c) => c.name)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    final categories = appCategories.isNotEmpty
        ? appCategories
        : const [
            'Maintenance',
            'Utilities',
            'Cleaning',
            'Supplies',
            'Taxes',
            'Internet',
            'Property Fee',
            'Other',
          ];
    if (!categories.contains(_quickExpenseCategory)) {
      _quickExpenseCategory = categories.first;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2627) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.flash, size: 13, color: Color(0xFF0D9488)),
              const SizedBox(width: 5),
              Text(
                'Instant Expense Logger',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const Spacer(),
              Text(
                'Month: ${_formatKey(mk)}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => _showQuickExpenseBar = false),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Ionicons.close,
                    size: 14,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Description field
              Expanded(
                flex: 4,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF081819) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Center(
                    child: TextField(
                      controller: _quickExpenseTitleController,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _submitQuickExpense(mk, cur),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.heading,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: 'Expense description / vendor...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Category Dropdown
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF081819) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _quickExpenseCategory,
                    dropdownColor:
                        isDark ? const Color(0xFF0F2627) : Colors.white,
                    isDense: true,
                    icon: Icon(
                      Ionicons.chevronDown,
                      size: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                    items: categories.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _quickExpenseCategory = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Amount field
              SizedBox(
                width: 115,
                height: 32,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF081819) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$cur ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quickExpenseAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*')),
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submitQuickExpense(mk, cur),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            fillColor: Colors.transparent,
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Save button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 32),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Ionicons.checkmark, size: 14),
                label: const Text('Save',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                onPressed: () => _submitQuickExpense(mk, cur),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesAndDepositsSection(
      AppDataState s,
      String cur,
      String mk,
      double rentCollected,
      double paidExpenses,
      double net,
      bool isDark) {
    final monthNotes = s.scopedMonthlyNotes.where((x) => x.month == mk).toList();
    final monthDeposits = s.scopedBankDeposits
        .where((d) => d.depositDate.startsWith(mk))
        .toList();

    final confirmedDeposits = monthDeposits
        .where((d) => d.status.toLowerCase().trim() == 'confirmed')
        .toList();
    final pendingDeposits = monthDeposits
        .where((d) => d.status.toLowerCase().trim() != 'confirmed')
        .toList();

    final confirmedTotal =
        confirmedDeposits.fold<double>(0.0, (a, d) => a + d.amount);
    final pendingTotal =
        pendingDeposits.fold<double>(0.0, (a, d) => a + d.amount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 850;
        final checklist = _buildChecklistCard(s, monthNotes, mk, isDark);
        final bankDeposits = _buildBankDepositsCard(
          s,
          monthDeposits,
          confirmedTotal,
          pendingTotal,
          rentCollected,
          paidExpenses,
          net,
          cur,
          isDark,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: checklist),
              const SizedBox(width: 10),
              Expanded(flex: 5, child: bankDeposits),
            ],
          );
        } else {
          return Column(
            children: [
              checklist,
              const SizedBox(height: 10),
              bankDeposits,
            ],
          );
        }
      },
    );
  }

  Widget _buildChecklistCard(
      AppDataState s, List<MonthlyNote> notes, String mk, bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Icon(Ionicons.documentTextOutline,
                          size: 13, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Notes',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                        Text(
                          notes.isEmpty
                              ? 'No notes added'
                              : '${notes.length} note${notes.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          // Add note button
                InkWell(
                  onTap: () => widget.onAddNote?.call(mk, null),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF103333)
                          : const Color(0xFFEDF7F4),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF34D399).withValues(alpha: 0.3)
                            : const Color(0xFF059669).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.add,
                            size: 11,
                            color: isDark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF059669)),
                        const SizedBox(width: 4),
                        Text(
                          'Add Note',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: borderColor),

          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Ionicons.listOutline,
                        size: 22,
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1)),
                    const SizedBox(height: 4),
                    Text(
                      'No notes for this month',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: notes.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.04)
                    : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, i) {
                final n = notes[i];
                String? propName;
                if (s.isAllProperties &&
                    s.properties.isNotEmpty &&
                    n.propertyId != null) {
                  final hit =
                      s.properties.where((p) => p.id == n.propertyId).toList();
                  if (hit.isNotEmpty) propName = hit.first.name;
                }
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onAddNote?.call(mk, n),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    n.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (propName != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      propName,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF3B82F6),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Ionicons.trashOutline, size: 12),
                            color: const Color(0xFFEF4444),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            tooltip: 'Delete note',
                            onPressed: () async {
                              final ok = await confirmDialog(
                                  context,
                                  'Delete Note',
                                  'Are you sure you want to delete this note?');
                              if (ok && context.mounted) {
                                ref
                                    .read(appDataProvider.notifier)
                                    .deleteNote(n.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReconciliationBadge({
    required double confirmedDeposited,
    required double pendingDeposited,
    required double rentCollected,
    required double paidExpenses,
    required double net,
    required String cur,
    required bool isDark,
  }) {
    if (rentCollected <= 0 && confirmedDeposited <= 0 && pendingDeposited <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'No rent collected',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      );
    }

    if (rentCollected <= 0 && (confirmedDeposited > 0 || pendingDeposited > 0)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: Text(
          'Deposited: $cur ${(confirmedDeposited + pendingDeposited).toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10B981),
          ),
        ),
      );
    }

    // Determine reconciliation state:
    // 1. Matches or exceeds Gross Rent
    // 2. Matches or exceeds Net Income (Rent Collected - Paid Expenses)
    final bool matchesGross = confirmedDeposited >= rentCollected;
    final bool matchesNet = paidExpenses > 0 && confirmedDeposited >= net && net > 0;
    final bool isReconciled = matchesGross || matchesNet;

    final double benchmark = (paidExpenses > 0 && net > 0) ? net : rentCollected;
    final String benchmarkLabel = (paidExpenses > 0 && net > 0) ? 'Net Cash' : 'Rent';
    final double diff = (benchmark - confirmedDeposited).clamp(0, double.infinity);

    final Color color = isReconciled
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);

    final String badgeText;
    final String tooltipMessage;

    if (matchesGross) {
      badgeText = 'Reconciled (Gross)';
      tooltipMessage =
          'Bank deposits ($cur ${confirmedDeposited.toStringAsFixed(0)}) match or exceed total rent collected ($cur ${rentCollected.toStringAsFixed(0)}).';
    } else if (matchesNet) {
      badgeText = 'Reconciled (Net Cash)';
      tooltipMessage =
          'Bank deposits ($cur ${confirmedDeposited.toStringAsFixed(0)}) match or exceed Net Income ($cur ${net.toStringAsFixed(0)} = Rent $cur ${rentCollected.toStringAsFixed(0)} - Exp $cur ${paidExpenses.toStringAsFixed(0)}).';
    } else if ((confirmedDeposited + pendingDeposited) >= benchmark) {
      badgeText = 'Pending Confirmation';
      tooltipMessage =
          'Pending deposits ($cur ${pendingDeposited.toStringAsFixed(0)}) will reconcile $benchmarkLabel ($cur ${benchmark.toStringAsFixed(0)}) once marked as confirmed.';
    } else {
      badgeText = 'Unmatched: $cur ${diff.toStringAsFixed(0)}';
      final pendingHint = pendingDeposited > 0
          ? ' ($cur ${pendingDeposited.toStringAsFixed(0)} is pending confirmation)'
          : '';
      tooltipMessage =
          '$cur ${diff.toStringAsFixed(0)} un-deposited $benchmarkLabel ($benchmarkLabel: $cur ${benchmark.toStringAsFixed(0)} - Confirmed: $cur ${confirmedDeposited.toStringAsFixed(0)})$pendingHint.';
    }

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReconciled
                  ? Ionicons.checkmarkCircleOutline
                  : Ionicons.alertCircleOutline,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 3.5),
            Text(
              badgeText,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankDepositsCard(
    AppDataState s,
    List<BankDeposit> deposits,
    double confirmedTotal,
    double pendingTotal,
    double rentCollected,
    double paidExpenses,
    double net,
    String cur,
    bool isDark,
  ) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    final confirmedCount = deposits
        .where((d) => d.status.toLowerCase().trim() == 'confirmed')
        .length;
    final pendingCount = deposits.length - confirmedCount;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(Ionicons.businessOutline,
                            size: 13, color: Color(0xFF3B82F6)),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bank Deposits',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.heading,
                              ),
                            ),
                            Text(
                              deposits.isEmpty
                                  ? (paidExpenses > 0
                                      ? 'Net Cash: $cur ${net.toStringAsFixed(0)} (Rent $cur ${rentCollected.toStringAsFixed(0)} - Exp $cur ${paidExpenses.toStringAsFixed(0)})'
                                      : 'No deposits logged')
                                  : (pendingCount > 0
                                      ? 'Confirmed: $cur ${confirmedTotal.toStringAsFixed(0)} ($confirmedCount) • Pending: $cur ${pendingTotal.toStringAsFixed(0)} ($pendingCount)'
                                      : 'Total Confirmed: $cur ${confirmedTotal.toStringAsFixed(0)} (${deposits.length} deposits)'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildReconciliationBadge(
                      confirmedDeposited: confirmedTotal,
                      pendingDeposited: pendingTotal,
                      rentCollected: rentCollected,
                      paidExpenses: paidExpenses,
                      net: net,
                      cur: cur,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => widget.onDeposit?.call(),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.add, size: 11, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Add Deposit',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
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
          ),

          Divider(height: 1, color: borderColor),

          if (deposits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Ionicons.cardOutline,
                        size: 22,
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1)),
                    const SizedBox(height: 4),
                    Text(
                      'No bank deposits recorded for this month',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: deposits.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.04)
                    : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, i) {
                final d = deposits[i];
                String? propName;
                if (s.isAllProperties &&
                    s.properties.isNotEmpty &&
                    d.propertyId != null) {
                  final hit =
                      s.properties.where((p) => p.id == d.propertyId).toList();
                  if (hit.isNotEmpty) propName = hit.first.name;
                }
                final dateStr = d.depositDate.length >= 10
                    ? d.depositDate.substring(0, 10)
                    : d.depositDate;
                final isConfirmed = d.status.toLowerCase().trim() == 'confirmed';
                final isPending = d.status.toLowerCase().trim() == 'pending';
                final statusColor = isConfirmed
                    ? const Color(0xFF10B981)
                    : (isPending ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (widget.onDepositDetails != null) {
                        widget.onDepositDetails!(d);
                      } else {
                        widget.onEditDeposit?.call(d);
                      }
                    },
                    onSecondaryTapDown: (details) =>
                        _showDepositContextMenu(context, details.globalPosition, d),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5.5),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Icon(Ionicons.business,
                                size: 12, color: Color(0xFF3B82F6)),
                          ),
                          const SizedBox(width: 8),
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
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    if (propName != null) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          propName,
                                          style: const TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF3B82F6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  d.referenceNumber?.isNotEmpty == true
                                      ? 'Ref: ${d.referenceNumber} • $dateStr'
                                      : dateStr,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              final isConf = d.status.toLowerCase().trim() == 'confirmed';
                              final newStatus = isConf ? 'pending' : 'confirmed';
                              final now = DateTime.now().toIso8601String();
                              final updated = d.copyWith(
                                status: newStatus,
                                updatedAt: now,
                              );
                              ref.read(appDataProvider.notifier).upsertDeposit(updated);
                              _safeToast(
                                newStatus == 'confirmed'
                                    ? 'Deposit marked as Confirmed'
                                    : 'Deposit marked as Pending',
                                isSuccess: true,
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isConfirmed
                                        ? Ionicons.checkmarkCircle
                                        : Ionicons.timeOutline,
                                    size: 10,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    d.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$cur ${d.amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(Ionicons.trashOutline, size: 12),
                            color: const Color(0xFFEF4444),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            tooltip: 'Delete deposit',
                            onPressed: () async {
                              final ok = await confirmDialog(
                                  context,
                                  'Delete Deposit',
                                  'Are you sure you want to delete this bank deposit?');
                              if (ok && context.mounted) {
                                ref
                                    .read(appDataProvider.notifier)
                                    .deleteDeposit(d.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
