import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';

/// Modern Executive Zakat & Wealth Purification Dashboard for macOS Desktop.
///
/// Features a compact Bento-grid KPI overview, responsive 2-column transaction table,
/// interactive Gold/Silver Nisab assessment card, category filters, and quick modal triggers.
class DesktopZakatView extends ConsumerStatefulWidget {
  final VoidCallback onAddInflow;
  final VoidCallback onAddOutflow;
  final void Function(ZakatTransaction txn)? onEditTxn;
  final void Function(ZakatTransaction txn)? onViewTxn;
  final VoidCallback? onOpenCalculator;
  final VoidCallback? onManageCategories;

  const DesktopZakatView({
    super.key,
    required this.onAddInflow,
    required this.onAddOutflow,
    this.onEditTxn,
    this.onViewTxn,
    this.onOpenCalculator,
    this.onManageCategories,
  });

  @override
  ConsumerState<DesktopZakatView> createState() => _DesktopZakatViewState();
}

class _DesktopZakatViewState extends ConsumerState<DesktopZakatView> {
  String? _filterCategory;
  String _searchQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedTxnIds = {};

  final NumberFormat _currencyFmt = NumberFormat('#,##0.00');

  String _formatMoney(num v) {
    if (v == v.roundToDouble()) {
      return NumberFormat('#,##0').format(v);
    }
    return _currencyFmt.format(v);
  }

  String _categoryName(String? id, List<ZakatCategory> all) {
    if (id == null || id.isEmpty) return 'General';
    final hit = all.where((c) => c.id == id);
    return hit.isEmpty ? 'General' : hit.first.name;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, msg, isError: error, isSuccess: !error);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedTxnIds.remove(id)) {
        _selectedTxnIds.add(id);
      }
    });
  }

  Future<void> _deleteSingle(ZakatTransaction z) async {
    final ok = await confirmDialog(
      context,
      'Delete Transaction',
      'Are you sure you want to delete this ${z.type == 'inflow' ? 'inflow' : 'outflow'} of ${ref.read(appDataProvider).selectedCurrency}${_formatMoney(z.amount)}? This action cannot be undone.',
    );
    if (!ok || !mounted) return;
    ref.read(appDataProvider.notifier).deleteZakat(z.id);
    _toast('Transaction deleted successfully');
  }

  Future<void> _bulkDelete() async {
    if (_selectedTxnIds.isEmpty) return;
    final count = _selectedTxnIds.length;
    final ok = await confirmDialog(
      context,
      'Delete Selected Transactions',
      'Are you sure you want to delete $count transaction(s)? This action cannot be undone.',
    );
    if (!ok || !mounted) return;
    ref.read(appDataProvider.notifier).deleteZakats(_selectedTxnIds.toList());
    setState(() {
      _selectedTxnIds.clear();
      _isSelectionMode = false;
    });
    _toast('$count transaction(s) deleted successfully');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final cur = s.selectedCurrency;

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF091E1F) : Colors.white;

    final query = _searchQuery.toLowerCase().trim();
    bool matchesSearch(ZakatTransaction z) {
      if (query.isEmpty) return true;
      final desc = (z.description ?? '').toLowerCase();
      final cat = _categoryName(z.category, s.zakatCategories).toLowerCase();
      final amt = z.amount.toString();
      final dt = z.date;
      return desc.contains(query) ||
          cat.contains(query) ||
          amt.contains(query) ||
          dt.contains(query);
    }

    // Totals calculations (respect the active category filter, like mobile).
    final allList = s.scopedZakat
        .where((z) =>
            matchesSearch(z) &&
            (_filterCategory == null || z.category == _filterCategory))
        .toList();
    final totalInflow = allList
        .where((z) => z.type == 'inflow')
        .fold<double>(0, (a, z) => a + z.amount);
    final totalOutflow = allList
        .where((z) => z.type == 'outflow')
        .fold<double>(0, (a, z) => a + z.amount);
    final netPool = totalInflow - totalOutflow;
    // Zakat is only due once the net pool reaches Nisab (silver standard shown
    // in the assessment card below).
    const nisabThreshold = 600.0;
    final zakatDue =
        netPool >= nisabThreshold ? netPool * 0.025 : 0.0;

    // Separate inflow / outflow lists (newest first), like the Overview's
    // side-by-side Rent Roll & Expenses tables.
    List<ZakatTransaction> txnsOf(String type) => s.scopedZakat.where((z) {
          if (z.type != type) return false;
          if (_filterCategory != null && z.category != _filterCategory) {
            return false;
          }
          return matchesSearch(z);
        }).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final inflowList = txnsOf('inflow');
    final outflowList = txnsOf('outflow');

    final availableCategories = s.zakatCategories
        .where((c) => c.type == 'inflow' || c.type == 'outflow' || c.type == 'both')
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TOP HEADER & DESKTOP CONTROLS (Compact Bar)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isNarrow = constraints.maxWidth < 1050;
                final titleCol = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Ionicons.walletOutline,
                          size: 16, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Zakat & Wealth Purification',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.heading,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                '2.5% Rate',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Islamic wealth accounting, Nisab standards & Hawl tracking',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                final controls = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Search box (Standard 34px)
                    Container(
                      width: 170,
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF091E1F) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Ionicons.searchOutline,
                              size: 15,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.heading,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                filled: false,
                                hintText: 'Search...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _searchQuery = ''),
                              child: const Icon(Ionicons.closeCircle,
                                  size: 13, color: Color(0xFF94A3B8)),
                            ),
                        ],
                      ),
                    ),

                    // Primary Add Inflow Button
                    InkWell(
                      onTap: widget.onAddInflow,
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.add, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Inflow',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Add Outflow Button
                    InkWell(
                      onTap: widget.onAddOutflow,
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF091E1F) : Colors.white,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.arrowUpOutline,
                                size: 13, color: Color(0xFFF59E0B)),
                            SizedBox(width: 4),
                            Text(
                              'Outflow',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Full Calculator Button
                    if (widget.onOpenCalculator != null)
                      InkWell(
                        onTap: widget.onOpenCalculator,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF091E1F) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.calculatorOutline,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF0F766E)),
                              const SizedBox(width: 4),
                              Text(
                                'Calculator',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Manage Categories Button
                    if (widget.onManageCategories != null)
                      InkWell(
                        onTap: widget.onManageCategories,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF091E1F) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.pricetagsOutline,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                'Categories',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleCol,
                      const SizedBox(height: 10),
                      controls,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    titleCol,
                    controls,
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            // 2. COMPACT BENTO KPI GRID (Top Metric Cards)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final w = constraints.maxWidth;
                final crossAxisCount = w >= 700 ? 4 : (w >= 420 ? 2 : 1);

                final cards = [
                  _kpiCard(
                    title: 'Total Inflows',
                    value: '$cur${_formatMoney(totalInflow)}',
                    subtitle: '${allList.where((z) => z.type == 'inflow').length} records',
                    icon: Ionicons.arrowDownCircle,
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                  _kpiCard(
                    title: 'Total Outflows',
                    value: '$cur${_formatMoney(totalOutflow)}',
                    subtitle: '${allList.where((z) => z.type == 'outflow').length} distributions',
                    icon: Ionicons.arrowUpCircle,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                  _kpiCard(
                    title: 'Net Zakatable Pool',
                    value: '$cur${_formatMoney(netPool)}',
                    subtitle: netPool >= 0 ? 'Net holding balance' : 'Deficit',
                    icon: Ionicons.walletOutline,
                    color: const Color(0xFF3B82F6),
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                  ),
                  _kpiCard(
                    title: 'Zakat Due (2.5%)',
                    value: '$cur${_formatMoney(zakatDue)}',
                    subtitle: '1 Hawl cycle',
                    icon: Ionicons.shieldCheckmarkOutline,
                    color: const Color(0xFF8B5CF6),
                    isDark: isDark,
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isPrimary: true,
                  ),
                ];

                if (crossAxisCount == 4) {
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
                } else if (crossAxisCount == 2) {
                  final itemWidth = ((w - 10) / 2).floorToDouble();
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
                  );
                }

                return Column(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      cards[i],
                    ],
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            // 3. Side-by-side Inflow & Outflow tables (Overview style)
            _buildTransactionsSection(
              inflowList,
              outflowList,
              availableCategories,
              cur,
              isDark,
              cardBg,
              borderColor,
            ),

            const SizedBox(height: 12),

            // 4. Nisab & Islamic tools
            _buildNisabAndToolsPane(
                cur, netPool, zakatDue, isDark, cardBg, borderColor),
          ],
        ),
      ),
    );
  }

  /// Compact KPI Card Builder
  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    bool isPrimary = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPrimary
            ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
            : cardBg,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
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
              color: isPrimary
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (AppColors.heading),
            ),
          ),
        ],
      ),
    );
  }

  /// Side-by-side Inflow & Outflow tables, mirroring the Overview's
  /// Rent Roll / Expenses layout.
  Widget _buildTransactionsSection(
    List<ZakatTransaction> inflowList,
    List<ZakatTransaction> outflowList,
    List<ZakatCategory> categories,
    String cur,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTransactionsToolbar(
          categories,
          inflowList.length + outflowList.length,
          isDark,
          cardBg,
          borderColor,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final inflowPane = _buildTransactionPane(
                inflowList, 'inflow', cur, isDark, cardBg, borderColor);
            final outflowPane = _buildTransactionPane(
                outflowList, 'outflow', cur, isDark, cardBg, borderColor);
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: inflowPane),
                  const SizedBox(width: 12),
                  Expanded(child: outflowPane),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                inflowPane,
                const SizedBox(height: 12),
                outflowPane,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTransactionsToolbar(
    List<ZakatCategory> categories,
    int totalCount,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _categoryChip(
                        label: 'All Categories',
                        isSelected: _filterCategory == null,
                        onTap: () => setState(() => _filterCategory = null),
                        isDark: isDark,
                      ),
                      for (final cat in categories)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _categoryChip(
                            label: cat.name,
                            isSelected: _filterCategory == cat.id,
                            onTap: () =>
                                setState(() => _filterCategory = cat.id),
                            isDark: isDark,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F2B2C)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$totalCount Records',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF0F766E),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  setState(() {
                    _isSelectionMode = !_isSelectionMode;
                    _selectedTxnIds.clear();
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: _isSelectionMode
                        ? (isDark
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFF059669).withValues(alpha: 0.1))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isSelectionMode
                          ? const Color(0xFF059669)
                          : borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSelectionMode
                            ? Ionicons.checkmarkDone
                            : Ionicons.checkboxOutline,
                        size: 12,
                        color: _isSelectionMode
                            ? const Color(0xFF10B981)
                            : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isSelectionMode ? 'Done' : 'Select',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isSelectionMode
                              ? const Color(0xFF10B981)
                              : (isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_isSelectionMode && _selectedTxnIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1C1318) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedTxnIds.length} selected',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _bulkDelete,
                    child: const Row(
                      children: [
                        Icon(Ionicons.trashOutline,
                            size: 13, color: Color(0xFFEF4444)),
                        SizedBox(width: 4),
                        Text(
                          'Delete Selected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
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

  /// Single-type transaction table (Inflow or Outflow).
  Widget _buildTransactionPane(
    List<ZakatTransaction> list,
    String type,
    String cur,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    final s = ref.watch(appDataProvider);
    final isInflow = type == 'inflow';
    final accent = isInflow ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final total = list.fold<double>(0, (a, z) => a + z.amount);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pane Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5.5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isInflow
                          ? const [Color(0xFF0F766E), Color(0xFF10B981)]
                          : const [Color(0xFFB45309), Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    isInflow ? Ionicons.arrowDownOutline : Ionicons.arrowUpOutline,
                    size: 13.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInflow ? 'Inflow' : 'Outflow',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.heading,
                        ),
                      ),
                      Text(
                        '${list.length} record${list.length == 1 ? '' : 's'}',
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
                Text(
                  '$cur${_formatMoney(total)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: isInflow ? widget.onAddInflow : widget.onAddOutflow,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.add, size: 12, color: accent),
                        const SizedBox(width: 3),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
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

          // Table / List
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                children: [
                  Icon(
                    Ionicons.receiptOutline,
                    size: 32,
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No transactions found',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Try clearing your search or add a new inflow or outflow.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              color: isDark
                  ? const Color(0xFF061819).withValues(alpha: 0.7)
                  : const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  if (_isSelectionMode) const SizedBox(width: 28),
                  const SizedBox(
                    width: 90,
                    child: Text(
                      'TYPE & DATE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'CATEGORY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'DESCRIPTION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(
                    width: 95,
                    child: Text(
                      'AMOUNT',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 50),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: borderColor),
              itemBuilder: (ctx, idx) {
                final z = list[idx];
                final isInflow = z.type == 'inflow';
                final isSelected = _selectedTxnIds.contains(z.id);
                final catName = _categoryName(z.category, s.zakatCategories);

                return InkWell(
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(z.id);
                    } else if (widget.onViewTxn != null) {
                      widget.onViewTxn!(z);
                    }
                  },
                  hoverColor: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.05)
                      : const Color(0xFF059669).withValues(alpha: 0.03),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: isSelected
                        ? (isDark ? const Color(0xFF059669).withValues(alpha: 0.15) : const Color(0xFF059669).withValues(alpha: 0.08))
                        : Colors.transparent,
                    child: Row(
                      children: [
                        if (_isSelectionMode) ...[
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(z.id),
                              activeColor: const Color(0xFF059669),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],

                        // Type & Date
                        SizedBox(
                          width: 90,
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isInflow
                                      ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.12)
                                      : const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Icon(
                                  isInflow ? Ionicons.arrowDown : Ionicons.arrowUp,
                                  size: 12,
                                  color: isInflow ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  z.date,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Category Pill
                        SizedBox(
                          width: 80,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isInflow ? const Color(0xFF059669) : const Color(0xFFD97706)).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              catName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isInflow ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Description / Notes
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (z.description ?? '').trim().isEmpty ? 'Zakat Transaction' : z.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.heading,
                                  ),
                                ),
                              ),
                              if (z.receiptUri != null && z.receiptUri!.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(Ionicons.attachOutline, size: 12, color: Color(0xFF059669)),
                              ],
                            ],
                          ),
                        ),

                        // Amount with sign
                        SizedBox(
                          width: 95,
                          child: Text(
                            '${isInflow ? '+' : '-'}$cur${_formatMoney(z.amount)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Quick Actions (Edit, Delete)
                        SizedBox(
                          width: 44,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (widget.onEditTxn != null)
                                InkWell(
                                  onTap: () => widget.onEditTxn!(z),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Icon(Ionicons.createOutline, size: 13.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                  ),
                                ),
                              InkWell(
                                onTap: () => _deleteSingle(z),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(Ionicons.trashOutline, size: 13.5, color: Color(0xFFEF4444)),
                                ),
                              ),
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
        ],
      ),
    );
  }

  /// Right Pane: Live Nisab & Islamic Tools Card (Compact)
  Widget _buildNisabAndToolsPane(
    String cur,
    double netPool,
    double zakatDue,
    bool isDark,
    Color cardBg,
    Color borderColor,
  ) {
    return Column(
      children: [
        // Card 1: Interactive Nisab Thresholds Card
        Container(
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
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Ionicons.shieldCheckmarkOutline, size: 14, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nisab Assessment',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                        Text(
                          'Islamic minimum wealth qualification',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 8),

              // Gold & Silver Standards (Compact)
              Row(
                children: [
                  Expanded(
                    child: _nisabTile(
                      title: 'Gold (85g 24k)',
                      standard: '~\$5,500',
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _nisabTile(
                      title: 'Silver (595g)',
                      standard: '~\$600',
                      color: const Color(0xFF94A3B8),
                      isDark: isDark,
                      borderColor: borderColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Live Pool vs Nisab status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF051718) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: netPool > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : borderColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Holding Net Balance:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '$cur${_formatMoney(netPool)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.heading,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated Due (2.5%):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '$cur${_formatMoney(zakatDue)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (widget.onOpenCalculator != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenCalculator,
                    icon: const Icon(Ionicons.calculatorOutline, size: 13),
                    label: const Text('Detailed Calculator', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF0F766E),
                      side: BorderSide(color: isDark ? const Color(0xFF34D399).withValues(alpha: 0.4) : const Color(0xFF0F766E).withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Card 2: 8 Qur'anic Beneficiaries (Compact Chip Cloud)
        Container(
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
                  const Icon(Ionicons.heartOutline, size: 14, color: Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Eligible Beneficiaries (At-Tawbah 9:60)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _beneficiaryTag('Poor (Fuqara)', isDark),
                  _beneficiaryTag('Needy (Masakin)', isDark),
                  _beneficiaryTag('Administrators', isDark),
                  _beneficiaryTag('Reconciling Hearts', isDark),
                  _beneficiaryTag('Freeing Captives', isDark),
                  _beneficiaryTag('In Debt (Gharimin)', isDark),
                  _beneficiaryTag('Cause of Allah', isDark),
                  _beneficiaryTag('Wayfarer (Traveler)', isDark),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _beneficiaryTag(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF051718) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isDark ? const Color.fromRGBO(255, 255, 255, 0.05) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _nisabTile({
    required String title,
    required String standard,
    required Color color,
    required bool isDark,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF051718) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                Text(
                  standard,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F766E) : const Color(0xFF059669))
              : (isDark ? const Color(0xFF051718) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}
