import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/wave_animation.dart';
import '../desktop/desktop_zakat_view.dart';

/// Strict 1:1 port of `src/screens/ZakatScreen.tsx`.
///
/// Fixed header (title/subtitle + search toggle + add button) over a gradient,
/// a scroll body with an expandable search field, an Inflow/Outflow/Balance
/// summary row, an Inflow|Outflow tab selector, bulk-selection controls, a
/// category filter chip row, the inflow/outflow transaction list (with empty
/// states), the "Islamic Tools" section and the Zakat Calculator card. Also
/// ports the Add/Edit (single + multiple) transaction sheet, Transaction
/// Details sheet, full-screen receipt viewer, Zakat Calculator sheet and the
/// category-management sheet.
class ZakatView extends ConsumerStatefulWidget {
  const ZakatView({super.key});

  static void showAddModal(
    BuildContext context, {
    ZakatTransaction? edit,
    String initialType = 'inflow',
  }) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTxnSheet(edit: edit, initialType: initialType),
    );
  }

  static void showDetailsModal(BuildContext context, ZakatTransaction txn) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DetailsSheet(
        txn: txn,
        onEdit: () {
          Navigator.pop(ctx);
          showAddModal(context, edit: txn, initialType: txn.type);
        },
        onDelete: () async {
          final ok = await confirmDialog(
            context,
            'Delete Transaction',
            'Are you sure you want to delete this ${txn.type == 'inflow' ? 'inflow' : 'outflow'} transaction? This action cannot be undone.',
          );
          if (!ok || !ctx.mounted) return;
          ProviderScope.containerOf(
            ctx,
            listen: false,
          ).read(appDataProvider.notifier).deleteZakat(txn.id);
          Navigator.pop(ctx);
        },
        onViewReceipt: () {
          if (txn.receiptUri != null && txn.receiptUri!.isNotEmpty) {
            showDialog<void>(
              context: context,
              barrierColor: const Color.fromRGBO(0, 0, 0, 0.9),
              builder: (c) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(c),
                      child: Container(
                        color: Colors.transparent,
                        alignment: Alignment.center,
                        child: InteractiveViewer(
                          child: _receiptImage(
                            txn.receiptUri!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 50,
                    right: 20,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(c),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color.fromRGBO(0, 0, 0, 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Ionicons.close,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  static void showCalculatorModal(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CalculatorSheet(),
    );
  }

  static void showCategoriesModal(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CategoryManagerSheet(initialTab: 'inflow'),
    );
  }

  @override
  ConsumerState<ZakatView> createState() => _ZakatViewState();
}

class _ZakatViewState extends ConsumerState<ZakatView> {
  String _activeTxnTab = 'inflow';
  String? _filterCategory;
  String _searchQuery = '';
  final TextEditingController _searchCtl = TextEditingController();
  bool _isSearchExpanded = false;
  bool _isSearchFocused = false;
  bool _isSwitchingTab = false;
  bool _isSwitchingCategory = false;

  bool _isSelectionMode = false;
  final Set<String> _selectedTxnIds = {};

  // Loading skeleton wave (mirrors the OverviewView behavior).
  bool _wave = false;
  Timer? _waveTimer;

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
    _searchCtl.dispose();
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

  // ----- helpers -----
  static const _monthShort = [
    '',
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// Ports formatZakatDate (e.g. "9sep 25").
  String _zakatDate(String? iso) {
    if (iso == null || iso.isEmpty) return iso ?? '';
    try {
      final d = DateTime.parse(iso);
      final yy = (d.year % 100).toString().padLeft(2, '0');
      return '${d.day}${_monthShort[d.month]} $yy';
    } catch (_) {
      return iso;
    }
  }

  String _catName(String? id, List<ZakatCategory> all) {
    if (id == null || id.isEmpty) return '';
    final hit = all.where((c) => c.id == id);
    return hit.isEmpty ? 'Deleted Category' : hit.first.name;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, msg, isError: error, isSuccess: !error);
  }

  Future<void> _switchTab(String newTab) async {
    if (newTab == _activeTxnTab || _isSwitchingTab) return;
    _flashWave();
    setState(() => _isSwitchingTab = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _activeTxnTab = newTab;
      _isSwitchingTab = false;
    });
  }

  Future<void> _switchCategory(String? categoryId) async {
    if (categoryId == _filterCategory || _isSwitchingCategory) return;
    _flashWave();
    setState(() => _isSwitchingCategory = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _filterCategory = categoryId;
      _isSwitchingCategory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final cur = s.selectedCurrency;

    final query = _searchQuery.toLowerCase().trim();
    bool matchesSearch(ZakatTransaction z) {
      if (query.isEmpty) return true;
      final description = (z.description ?? '').toLowerCase();
      final category = _catName(z.category, s.zakatCategories).toLowerCase();
      final amount = z.amount.toString();
      final date = z.date;
      return description.contains(query) ||
          category.contains(query) ||
          amount.contains(query) ||
          date.contains(query);
    }

    // totals — honors category filter + search across both types.
    final totalsList = s.scopedZakat.where((z) {
      if (_filterCategory != null && z.category != _filterCategory) {
        return false;
      }
      return matchesSearch(z);
    });
    final inflow = totalsList
        .where((z) => z.type == 'inflow')
        .fold<double>(0, (a, z) => a + z.amount);
    final outflow = totalsList
        .where((z) => z.type == 'outflow')
        .fold<double>(0, (a, z) => a + z.amount);

    // transactions — active tab + category + search (original order preserved).
    final list = s.scopedZakat.where((z) {
      if (z.type != _activeTxnTab) return false;
      if (_filterCategory != null && z.category != _filterCategory) {
        return false;
      }
      return matchesSearch(z);
    }).toList();

    final availableCategories = s.zakatCategories
        .where((c) => c.type == _activeTxnTab || c.type == 'both')
        .toList();

    final total = s.scopedZakat.length;

    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopZakatView(
        onAddInflow: () => _openAddSheet(context, null, 'inflow'),
        onAddOutflow: () => _openAddSheet(context, null, 'outflow'),
        onEditTxn: (z) => _openAddSheet(context, z, z.type),
        onViewTxn: (z) => _openDetails(context, z),
        onOpenCalculator: () => _openCalculator(context),
        onManageCategories: () => ZakatView.showCategoriesModal(context),
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
        body: Column(
          children: [
            _header(context, total),
            Expanded(
              child: PullToRefresh(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 10, bottom: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isSearchExpanded) _searchSection(),
                      _summaryRow(cur, inflow, outflow, inflow - outflow),
                      _tabSelector(),
                      if (_isSelectionMode) _selectionControls(),
                      if (s.scopedZakat.isNotEmpty)
                        _categoryFilterRow(availableCategories),
                      if (_wave)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: WaveAnimation(
                            count: 6,
                            icon: Ionicons.heartOutline,
                          ),
                        )
                      else
                        _content(s, cur, list),
                      _islamicTools(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int total) {
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
          // Left: Zakat Icon Badge
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
                      Ionicons.pricetag,
                      size: 20,
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
          const SizedBox(width: 10),

          // Center: Title + Count pill + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Zakat',
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
                        horizontal: 7,
                        vertical: 2,
                      ),
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
                        '$total',
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
                  'Manage your zakat calculations',
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

          // Right: Action buttons (Search, Add)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _zakatBtn(
                icon: _isSearchExpanded
                    ? Icons.close_rounded
                    : Icons.search_rounded,
                isDark: isDark,
                isActive: _isSearchExpanded,
                onTap: _toggleSearch,
              ),
              const SizedBox(width: 6),
              _zakatBtn(
                icon: Icons.add_rounded,
                isDark: isDark,
                isAdd: true,
                onTap: () => _openAddSheet(context, null, 'inflow'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _zakatBtn({
    required IconData icon,
    required bool isDark,
    bool isActive = false,
    bool isAdd = false,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isAdd
            ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.25))
            : isActive
            ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.35))
            : (isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.06)
                  : Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAdd
              ? (isDark
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.4))
              : (isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.1)
                    : Colors.white.withValues(alpha: 0.35)),
        ),
      ),
      child: Icon(
        icon,
        size: isAdd ? 20 : 18,
        color: isAdd
            ? (isDark ? AppColors.primary : Colors.white)
            : (isDark ? AppColors.icon : Colors.white),
      ),
    ),
  );

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchQuery = '';
        _searchCtl.clear();
        _isSearchFocused = false;
      }
    });
  }

  Widget _searchSection() {
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.screenPadding,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              Ionicons.search,
              size: 18,
              color: _isSearchFocused
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Focus(
                onFocusChange: (f) => setState(() => _isSearchFocused = f),
                child: TextField(
                  autofocus: true,
                  controller: _searchCtl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(fontSize: 14, color: AppColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    hintText: 'Search zakat transactions...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtl.clear();
                  setState(() => _searchQuery = '');
                },
                child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Ionicons.closeCircle,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String cur,
    double inflow,
    double outflow,
    double balance,
  ) {
    Widget card(IconData icon, Color iconColor, String title, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 12, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    title,
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
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.horizontalMargin,
        right: AppSpacing.horizontalMargin,
        bottom: 6,
      ),
      child: Row(
        children: [
          card(
            Ionicons.arrowDown,
            AppColors.primary,
            'Inflow',
            fmtMoney(cur, inflow),
          ),
          const SizedBox(width: 10),
          card(
            Ionicons.arrowUp,
            AppColors.error,
            'Outflow',
            fmtMoney(cur, outflow),
          ),
          const SizedBox(width: 10),
          card(
            Ionicons.statsChart,
            AppColors.textSecondary,
            'Balance',
            fmtMoney(cur, balance),
          ),
        ],
      ),
    );
  }

  Widget _tabSelector() {
    final disabled = _isSwitchingTab || _isSwitchingCategory;
    Widget tab(String key, IconData icon, String label) {
      final active = _activeTxnTab == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchTab(key),
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: active
                    ? const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: 0.1,
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.horizontalMargin,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
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
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          tab('inflow', Ionicons.arrowDown, 'Inflow'),
          tab('outflow', Ionicons.arrowUp, 'Outflow'),
        ],
      ),
    );
  }

  Widget _selectionControls() {
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.horizontalMargin,
        right: AppSpacing.horizontalMargin,
        bottom: 8,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.isDark
              ? const Color.fromRGBO(0, 0, 0, 0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.isDark
                ? const Color.fromRGBO(255, 255, 255, 0.05)
                : AppColors.border,
            width: 1.5,
          ),
          boxShadow: AppColors.isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_selectedTxnIds.length} selected',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _selectionButton(
                  Ionicons.checkmarkDone,
                  AppColors.primary,
                  'All',
                  _selectAll,
                ),
                _selectionButton(
                  Ionicons.close,
                  AppColors.error,
                  'None',
                  () => setState(() => _selectedTxnIds.clear()),
                ),
                if (_selectedTxnIds.isNotEmpty)
                  _selectionButton(
                    Ionicons.trash,
                    AppColors.error,
                    'Delete',
                    _bulkDelete,
                    danger: true,
                  ),
                _selectionButton(
                  Ionicons.close,
                  AppColors.textSecondary,
                  'Cancel',
                  _toggleSelectionMode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionButton(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        constraints: const BoxConstraints(minWidth: 60),
        decoration: BoxDecoration(
          color: danger
              ? const Color.fromRGBO(255, 107, 107, 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: danger
                ? const Color.fromRGBO(255, 107, 107, 0.3)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: danger ? AppColors.error : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryFilterRow(List<ZakatCategory> cats) {
    Widget chip({
      required bool active,
      required VoidCallback onTap,
      IconData? icon,
      Color? iconColor,
      required String label,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: _isSwitchingCategory ? 0.5 : 1,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: active
                  ? const Color.fromRGBO(76, 175, 80, 0.2)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? const Color.fromRGBO(76, 175, 80, 0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.horizontalMargin,
        right: AppSpacing.horizontalMargin,
        bottom: 12,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(
              active: _filterCategory == null,
              onTap: () => _switchCategory(null),
              label: 'All',
            ),
            for (final cat in cats)
              chip(
                active: _filterCategory == cat.id,
                onTap: () => _switchCategory(cat.id),
                icon: _ion(cat.icon),
                iconColor: _filterCategory == cat.id
                    ? Colors.white
                    : _hex(cat.color),
                label: cat.name,
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(AppDataState s, String cur, List<ZakatTransaction> list) {
    Widget body;
    if (s.scopedZakat.isEmpty) {
      body = _emptyState(
        icon: Ionicons.heart,
        title: 'No Zakat Transactions',
        subtext: 'No zakat transactions found. Start by adding your first zakat transaction using the + button above.',
      );
    } else if (list.isEmpty) {
      final isInflow = _activeTxnTab == 'inflow';
      body = _emptyState(
        icon: isInflow ? Ionicons.arrowDown : Ionicons.arrowUp,
        title: 'No ${isInflow ? 'Inflow' : 'Outflow'} Transactions',
        subtext:
            'No ${isInflow ? 'inflow' : 'outflow'} transactions found. Start by adding your first ${isInflow ? 'inflow' : 'outflow'} transaction using the + button above.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final z in list) _row(s, cur, z)],
      );
    }
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.horizontalMargin,
        right: AppSpacing.horizontalMargin,
        bottom: 10,
      ),
      child: body,
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtext,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      alignment: Alignment.center,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.isDark ? null : AppColors.cardBackground,
          gradient: AppColors.isDark
              ? const LinearGradient(
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.08),
                    Color.fromRGBO(255, 255, 255, 0.04),
                  ],
                )
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.errorBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: AppColors.error),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                subtext,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AppDataState s, String cur, ZakatTransaction z) {
    final isInflow = z.type == 'inflow';
    final selected = _selectedTxnIds.contains(z.id);
    final title = (z.description ?? '').isNotEmpty
        ? z.description!
        : (isInflow ? 'Zakat Inflow' : 'Zakat Outflow');
    final meta = (z.category ?? '').isNotEmpty
        ? _catName(z.category, s.zakatCategories)
        : 'No Category';

    return Dismissible(
      key: ValueKey('zakat-${z.id}'),
      direction: _isSelectionMode
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
                title: const Text('Delete Zakat Entry?'),
                content: Text(
                  'Delete "$title" (${fmtMoney(cur, z.amount)}) permanently?',
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
        ref.read(appDataProvider.notifier).deleteZakat(z.id);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: GestureDetector(
          onTap: () {
            if (_isSelectionMode) {
              _toggleTxnSelection(z);
            } else {
              _openDetails(context, z);
            }
          },
          onLongPress: () {
            AppHaptics.medium();
            _handleLongPress(z);
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? const Color.fromRGBO(76, 175, 80, 0.08)
                  : (AppColors.isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.03)
                        : AppColors.cardBackground),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color.fromRGBO(76, 175, 80, 0.2)
                    : (AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.08)
                          : AppColors.border),
              ),
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
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isInflow
                        ? const Color.fromRGBO(76, 175, 80, 0.2)
                        : const Color.fromRGBO(255, 107, 107, 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isInflow ? Ionicons.arrowDown : Ionicons.arrowUp,
                    size: 14,
                    color: isInflow ? AppColors.primary : AppColors.error,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        meta,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 80),
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isInflow ? '+' : '-'}${fmtMoney(cur, z.amount)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isInflow ? AppColors.primary : AppColors.error,
                        ),
                      ),
                      Text(
                        _zakatDate(z.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _islamicTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.horizontalMargin,
          ),
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: const Text(
            'Islamic Tools',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _openCalculator(context),
          child: Container(
            margin: const EdgeInsets.only(
              left: AppSpacing.horizontalMargin,
              right: AppSpacing.horizontalMargin,
              bottom: 16,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Ionicons.calculator,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zakat Calculator',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Calculate your Zakat obligations',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Ionicons.chevronForward,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----- selection handling -----
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedTxnIds.clear();
    });
  }

  void _toggleTxnSelection(ZakatTransaction z) {
    setState(() {
      if (!_selectedTxnIds.remove(z.id)) _selectedTxnIds.add(z.id);
    });
  }

  void _selectAll() {
    final s = ref.read(appDataProvider);
    setState(() {
      _selectedTxnIds
        ..clear()
        ..addAll(
          s.scopedZakat.where((z) => z.type == _activeTxnTab).map((z) => z.id),
        );
    });
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

  void _handleLongPress(ZakatTransaction z) {
    if (_isSelectionMode) {
      _toggleTxnSelection(z);
      return;
    }
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AppModalSheet(
          size: SheetSize.compact,
          scrollable: false,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
          title: 'Transaction Actions',
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Ionicons.checkmarkDone,
                  color: AppColors.primary,
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
                  _toggleSelectionMode();
                },
              ),
              ListTile(
                leading: Icon(
                  Ionicons.documentText,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'View',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDetails(context, z);
                },
              ),
              ListTile(
                leading: Icon(Ionicons.create, color: AppColors.textSecondary),
                title: Text(
                  'Edit',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAddSheet(context, z, z.type);
                },
              ),
              ListTile(
                leading: const Icon(Ionicons.trash, color: AppColors.error),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await confirmDialog(
                    context,
                    'Delete Transaction',
                    'Are you sure you want to delete this transaction? This action cannot be undone.',
                  );
                  if (!ok || !mounted) return;
                  ref.read(appDataProvider.notifier).deleteZakat(z.id);
                  _toast('Transaction deleted successfully');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openAddSheet(
    BuildContext context,
    ZakatTransaction? edit,
    String initialType,
  ) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTxnSheet(edit: edit, initialType: initialType),
    );
  }

  void _openDetails(BuildContext context, ZakatTransaction z) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DetailsSheet(
        txn: z,
        onEdit: () {
          Navigator.pop(ctx);
          _openAddSheet(context, z, z.type);
        },
        onDelete: () async {
          final ok = await confirmDialog(
            context,
            'Delete Transaction',
            'Are you sure you want to delete this ${z.type == 'inflow' ? 'inflow' : 'outflow'} transaction? This action cannot be undone.',
          );
          if (!ok || !mounted) return;
          ref.read(appDataProvider.notifier).deleteZakat(z.id);
          if (ctx.mounted) Navigator.pop(ctx);
          _toast('Transaction deleted successfully');
        },
        onViewReceipt: () => _viewReceipt(z.receiptUri!),
      ),
    );
  }

  void _viewReceipt(String uri) {
    showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.9),
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                color: Colors.transparent,
                alignment: Alignment.center,
                child: InteractiveViewer(
                  child: _receiptImage(uri, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          Positioned(
            top: 50,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color.fromRGBO(0, 0, 0, 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.close,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCalculator(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CalculatorSheet(),
    );
  }
}

Widget _inputLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 12,
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w500,
    ),
  ),
);

InputDecoration _inputDecoration({String? hint}) {
  final isDark = AppColors.isDark;
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: isDark
        ? const Color.fromRGBO(255, 255, 255, 0.06)
        : const Color(0xFFF4F7F6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.15)
            : const Color(0xFFDCE3E3),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.15)
            : const Color(0xFFDCE3E3),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );
}

// ---------------------------------------------------------------------------
// Add / Edit transaction sheet
// ---------------------------------------------------------------------------

class _Draft {
  String type = 'inflow';
  double amount = 0;
  String date;
  String description = '';
  String category = '';
  String receiptUri = '';
  _Draft({required this.date});
}

class _AddTxnSheet extends ConsumerStatefulWidget {
  final ZakatTransaction? edit;
  final String initialType;
  const _AddTxnSheet({required this.edit, required this.initialType});
  @override
  ConsumerState<_AddTxnSheet> createState() => _AddTxnSheetState();
}

class _AddTxnSheetState extends ConsumerState<_AddTxnSheet> {
  late String _type;
  late final TextEditingController _amountCtl;
  late final TextEditingController _descCtl;
  late DateTime _date;
  String _category = '';
  ZakatCategory? _selectedCategory;
  String _receipt = '';
  bool _multiple = false;
  bool _showCatPicker = false;
  bool _submitting = false;
  String? _amountError;
  String? _descError;

  final List<_Draft> _drafts = [];
  int _cur = 0;
  final Map<int, Map<String, String>> _verrors = {};

  bool get _editing => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _type = e?.type ?? widget.initialType;
    _amountCtl = TextEditingController(text: e != null ? '${e.amount}' : '');
    _descCtl = TextEditingController(text: e?.description ?? '');
    _date = _parseDate(e?.date);
    _category = e?.category ?? '';
    _receipt = e?.receiptUri ?? '';
    if (e != null && e.category != null) {
      final hit = ref
          .read(appDataProvider)
          .zakatCategories
          .where((c) => c.id == e.category);
      _selectedCategory = hit.isEmpty ? null : hit.first;
    }
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  static DateTime _parseDate(String? iso) {
    if (iso != null && iso.isNotEmpty) {
      final d = DateTime.tryParse(iso);
      if (d != null) return d;
    }
    return DateTime.now();
  }

  String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _fmtBtn(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);

  String get _curType => _multiple ? _drafts[_cur].type : _type;

  bool get _formValid {
    if (_multiple) {
      return _drafts[_cur].amount > 0 &&
          _drafts[_cur].category.trim().isNotEmpty;
    }
    return (double.tryParse(_amountCtl.text) ?? 0) > 0 &&
        _category.trim().isNotEmpty;
  }

  void _initDrafts() {
    _drafts
      ..clear()
      ..add(_Draft(date: _today()));
    _cur = 0;
  }

  void _addDraft() {
    setState(() {
      _drafts.add(_Draft(date: _today()));
      _cur = _drafts.length - 1;
    });
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.removeAt(index);
      if (_cur >= _drafts.length) _cur = _drafts.length - 1;
    });
  }

  Map<String, String> _validate(_Draft d) {
    final err = <String, String>{};
    if (d.amount <= 0) err['amount'] = 'Amount must be a positive number';
    if (d.description.trim().length < 3) {
      err['description'] = 'Description must be at least 3 characters';
    }
    if (d.date.isEmpty) err['date'] = 'Date is required';
    if (d.type.isEmpty) err['type'] = 'Transaction type is required';
    return err;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, msg, isError: error, isSuccess: !error);
  }

  void _saveSingle() {
    if (_submitting) return;
    if (_amountCtl.text.trim().isEmpty) {
      _toast('Please enter an amount', error: true);
      return;
    }
    if (_descCtl.text.trim().isEmpty) {
      _toast('Please enter a source', error: true);
      return;
    }
    final amountValue = double.tryParse(_amountCtl.text);
    if (amountValue == null || amountValue <= 0) {
      _toast('Please enter a valid amount greater than 0', error: true);
      return;
    }
    _submitting = true;
    final e = widget.edit;
    final txn = ZakatTransaction(
      id: e?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: _type,
      amount: amountValue,
      date: DateFormat('yyyy-MM-dd').format(_date),
      description: _descCtl.text.trim(),
      category: _category.trim(),
      receiptUri: _receipt,
    );
    ref.read(appDataProvider.notifier).upsertZakat(txn);
    Navigator.pop(context);
    _toast(
      e == null
          ? 'Zakat transaction added successfully'
          : 'Zakat transaction updated successfully',
    );
  }

  void _saveMultiple() {
    final valid = _drafts
        .where(
          (t) =>
              t.amount > 0 &&
              t.description.trim().isNotEmpty &&
              t.date.isNotEmpty,
        )
        .toList();
    if (valid.isEmpty) {
      _toast('Please add at least one valid transaction', error: true);
      return;
    }
    final nn = ref.read(appDataProvider.notifier);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < valid.length; i++) {
      final t = valid[i];
      nn.upsertZakat(
        ZakatTransaction(
          id: 'zakat_${stamp}_$i',
          type: t.type,
          amount: t.amount,
          date: t.date,
          description: t.description.trim(),
          category: t.category,
          receiptUri: t.receiptUri.isEmpty ? null : t.receiptUri,
        ),
      );
    }
    Navigator.pop(context);
    _toast('Successfully added ${valid.length} transactions');
  }

  void _openCategoryManager() {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryManagerSheet(initialTab: _type),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Select Transaction Date',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      if (_multiple) {
        _drafts[_cur].date = DateFormat('yyyy-MM-dd').format(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(appDataProvider).zakatCategories;
    final cats = all
        .where((c) => c.type == _curType || c.type == 'both')
        .toList();
    final title = _editing
        ? 'Edit Transaction'
        : _multiple
        ? 'Add Multiple Transactions'
        : 'Add Transaction';
    final saveText = _submitting
        ? 'Processing...'
        : _editing
        ? 'Save'
        : _multiple
        ? 'Add ${_drafts.length} Transactions'
        : 'Add';
    final saveIcon = _submitting
        ? Ionicons.hourglass
        : _multiple
        ? Ionicons.list
        : Ionicons.save;

    final isDark = AppColors.isDark;

    return AppModalSheet(
      title: title,
      icon: _editing ? Ionicons.create : Ionicons.add,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_editing) ...[
            _modeIconToggle(
              multi: _multiple,
              isDark: isDark,
              onChanged: (m) => setState(() {
                _multiple = m;
                if (_multiple && _drafts.isEmpty) _initDrafts();
              }),
            ),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _openCategoryManager,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.06)
                    : const Color(0xFFF0F5F3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.1)
                      : const Color(0xFFDFE6E6),
                ),
              ),
              child: Center(
                child: Icon(
                  Ionicons.settings,
                  size: 16,
                  color: isDark
                      ? const Color(0xFFA0D8D8).withValues(alpha: 0.8)
                      : const Color(0xFF0F766E),
                ),
              ),
            ),
          ),
        ],
      ),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _segmentRow(),
          const SizedBox(height: 16),
          _amountField(),
          const SizedBox(height: 16),
          _dateField(),
          const SizedBox(height: 16),
          _categoryField(cats),
          const SizedBox(height: 16),
          _sourceField(),
          const SizedBox(height: 16),
          _receiptField(),
          if (_multiple) ...[const SizedBox(height: 16), _transactionList()],
        ],
      ),
      footer: SheetActions(
        primaryLabel: saveText,
        primaryIcon: Icon(saveIcon, size: 16),
        onPrimary: (!_formValid || _submitting)
            ? null
            : (_editing
                  ? _saveSingle
                  : _multiple
                  ? _saveMultiple
                  : _saveSingle),
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.pop(context),
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
            icon: Icons.add_circle_outline_rounded,
            tooltip: 'Single transaction',
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
            tooltip: 'Multiple transactions',
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

  Widget _segmentRow() {
    Widget seg(String key, String label) {
      final active = _curType == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            if (_multiple) {
              _drafts[_cur].type = key;
            } else {
              _type = key;
            }
            _selectedCategory = null;
            _category = '';
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? const Color.fromRGBO(76, 175, 80, 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? const Color.fromRGBO(76, 175, 80, 0.35)
                    : const Color.fromRGBO(255, 255, 255, 0.2),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg('inflow', 'Inflow'),
        const SizedBox(width: 10),
        seg('outflow', 'Outflow'),
      ],
    );
  }

  Widget _amountField() {
    final text = _multiple ? _drafts[_cur].amount.toString() : _amountCtl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputLabel('Amount * ${_multiple ? '(Transaction ${_cur + 1})' : ''}'),
        TextField(
          controller: _multiple
              ? TextEditingController(text: text)
              : _amountCtl,
          onChanged: (v) {
            if (_multiple) {
              setState(() {
                _drafts[_cur].amount = double.tryParse(v) ?? 0;
                _verrors[_cur] = _validate(_drafts[_cur]);
              });
            } else {
              setState(() => _amountError = null);
            }
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(fontSize: 14, color: AppColors.text),
          decoration: _inputDecoration(hint: '0.00 (required)'),
        ),
        if (_amountError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _amountError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _dateField() {
    final d = _multiple ? _parseDate(_drafts[_cur].date) : _date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputLabel('Date ${_multiple ? '(Transaction ${_cur + 1})' : ''}'),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.2)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fmtBtn(d),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Ionicons.calendar,
                  size: 16,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryField(List<ZakatCategory> cats) {
    final label = _multiple
        ? (_drafts[_cur].category.isNotEmpty
              ? _catNameOf(_drafts[_cur].category, cats)
              : 'Select a category...')
        : (_selectedCategory != null ? null : 'Select a category...');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputLabel('Category ${_multiple ? '(Transaction ${_cur + 1})' : ''}'),
        GestureDetector(
          onTap: () => setState(() => _showCatPicker = !_showCatPicker),
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.1)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.2)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                if (!_multiple && _selectedCategory != null)
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _hex(_selectedCategory!.color),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _ion(_selectedCategory!.icon),
                          size: 16,
                          color: _contrast(_hex(_selectedCategory!.color)),
                        ),
                      ),
                      Text(
                        _selectedCategory!.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  Expanded(
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Icon(
                  _showCatPicker ? Ionicons.chevronUp : Ionicons.chevronDown,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_showCatPicker)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? const Color.fromRGBO(10, 31, 31, 0.95)
                  : AppColors.dropdownBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.2)
                    : AppColors.border,
              ),
              boxShadow: AppColors.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _catOption(
                    onTap: () {
                      setState(() {
                        if (_multiple) {
                          _drafts[_cur].category = '';
                        } else {
                          _selectedCategory = null;
                          _category = '';
                        }
                        _showCatPicker = false;
                      });
                    },
                    child: Text(
                      'Clear Selection',
                      style: TextStyle(fontSize: 14, color: AppColors.text),
                    ),
                  ),
                  for (final c in cats)
                    _catOption(
                      onTap: () {
                        setState(() {
                          if (_multiple) {
                            _drafts[_cur].category = c.id;
                            _verrors[_cur] = _validate(_drafts[_cur]);
                          } else {
                            _selectedCategory = c;
                            _category = c.id;
                          }
                          _showCatPicker = false;
                        });
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _hex(c.color),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _ion(c.icon),
                              size: 16,
                              color: _contrast(_hex(c.color)),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _catNameOf(String id, List<ZakatCategory> cats) {
    final hit = cats.where((c) => c.id == id);
    return hit.isEmpty ? 'Deleted Category' : hit.first.name;
  }

  Widget _catOption({required VoidCallback onTap, required Widget child}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
            ),
          ),
          child: child,
        ),
      );

  Widget _sourceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputLabel('Source * ${_multiple ? '(Transaction ${_cur + 1})' : ''}'),
        TextField(
          controller: _multiple
              ? TextEditingController(text: _drafts[_cur].description)
              : _descCtl,
          onChanged: (v) {
            if (_multiple) {
              setState(() {
                _drafts[_cur].description = v;
                _verrors[_cur] = _validate(_drafts[_cur]);
              });
            } else {
              setState(() => _descError = null);
            }
          },
          maxLines: 3,
          style: TextStyle(fontSize: 14, color: AppColors.text),
          decoration: _inputDecoration(hint: 'Enter source (required)'),
        ),
        if (_descError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _descError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _receiptField() {
    final uri = _multiple ? _drafts[_cur].receiptUri : _receipt;
    Future<void> pick() async {
      final p = await MediaPicker.pickImage(context);
      if (p == null) return;
      setState(() {
        if (_multiple) {
          _drafts[_cur].receiptUri = p;
        } else {
          _receipt = p;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inputLabel(
          'Receipt (optional) ${_multiple ? '(Transaction ${_cur + 1})' : ''}',
        ),
        if (uri.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _receiptImage(uri, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    if (_multiple) {
                      _drafts[_cur].receiptUri = '';
                    } else {
                      _receipt = '';
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHover,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color.fromRGBO(255, 255, 255, 0.15),
                      ),
                    ),
                    child: const Text(
                      'Remove',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
          GestureDetector(
            onTap: pick,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.18)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Browse Receipt Image',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.1)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.isDark
                            ? const Color.fromRGBO(255, 255, 255, 0.2)
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Choose from Gallery',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.1)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.isDark
                            ? const Color.fromRGBO(255, 255, 255, 0.2)
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Capture Photo',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _transactionList() {
    return SizedBox(
      height: 190,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction List',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: _addDraft,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Ionicons.add,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _drafts.length; i++) _draftItem(i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftItem(int index) {
    final d = _drafts[index];
    final hasErrors = (_verrors[index] ?? {}).isNotEmpty;
    final active = _cur == index;
    return GestureDetector(
      onTap: () => setState(() => _cur = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: hasErrors ? const Color.fromRGBO(255, 107, 107, 0.05) : null,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : (hasErrors
                          ? const Color.fromRGBO(255, 107, 107, 0.1)
                          : AppColors.surface),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasErrors
                      ? AppColors.error
                      : (active ? AppColors.primary : AppColors.border),
                ),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? Colors.white
                      : (hasErrors ? AppColors.error : AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.description.isNotEmpty
                              ? d.description
                              : 'No source',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppColors.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fmtMoney('', d.amount),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 40),
                      decoration: BoxDecoration(
                        color: d.type == 'inflow'
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFB45309),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        d.type == 'inflow' ? 'INFLOW' : 'OUTFLOW',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_drafts.length > 1)
              GestureDetector(
                onTap: () => _removeDraft(index),
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 107, 107, 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color.fromRGBO(255, 107, 107, 0.3),
                    ),
                  ),
                  child: const Icon(
                    Ionicons.trash,
                    size: 16,
                    color: AppColors.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details sheet
// ---------------------------------------------------------------------------

class _DetailsSheet extends ConsumerWidget {
  final ZakatTransaction txn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewReceipt;
  const _DetailsSheet({
    required this.txn,
    required this.onEdit,
    required this.onDelete,
    required this.onViewReceipt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(appDataProvider).selectedCurrency;
    Widget card(String label, Widget value) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
    Widget val(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.text,
      ),
    );

    return AppModalSheet(
      title: 'Transaction Details',
      icon: Ionicons.documentText,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card('Type', val(txn.type == 'inflow' ? 'Inflow' : 'Outflow')),
          const SizedBox(height: 16),
          card('Amount', val(fmtMoney(cur, txn.amount))),
          const SizedBox(height: 16),
          card('Date', val(txn.date)),
          if ((txn.category ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            card('Category', val(txn.category!)),
          ],
          if ((txn.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            card('Source', val(txn.description!)),
          ],
          if ((txn.receiptUri ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            card(
              'Receipt',
              GestureDetector(
                onTap: onViewReceipt,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 220,
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _receiptImage(
                          txn.receiptUri!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Container(
                      height: 220,
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Ionicons.expand,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: GradientButton.icon(
                height: 40,
                borderRadius: BorderRadius.circular(10),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.1,
                ),
                onPressed: onEdit,
                icon: const Icon(
                  Ionicons.create,
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text('Edit'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 40,
              child: DangerButton(
                height: 40,
                borderRadius: BorderRadius.circular(10),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                onPressed: onDelete,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Ionicons.trash, size: 16, color: Colors.white),
                    SizedBox(width: 5),
                    Text('Delete'),
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

// ---------------------------------------------------------------------------
// Calculator sheet
// ---------------------------------------------------------------------------

class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet();
  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  final _amountCtl = TextEditingController();
  String _zakatType = 'cash';
  double _result = 0;
  static const _rate = 0.025;

  @override
  void dispose() {
    _amountCtl.dispose();
    super.dispose();
  }

  void _calc() {
    final v = double.tryParse(_amountCtl.text) ?? 0;
    // Nisab (silver standard approximation shown in the desktop assessment).
    const nisabThreshold = 600.0;
    setState(() => _result = v >= nisabThreshold ? v * _rate : 0);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCurrency = ProviderScope.containerOf(context)
        .read(appDataProvider)
        .selectedCurrency;
    final amount = double.tryParse(_amountCtl.text) ?? 0;
    return AppModalSheet(
      title: 'Zakat Calculator',
      icon: Ionicons.calculatorOutline,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(76, 175, 80, 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color.fromRGBO(76, 175, 80, 0.35),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Zakat',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _inputLabel('Asset Type'),
          Row(
            children: [
              for (final t in const [
                'cash',
                'gold',
                'silver',
                'business',
                'livestock',
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _zakatType = t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _zakatType == t
                            ? const Color.fromRGBO(76, 175, 80, 0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _zakatType == t
                              ? const Color.fromRGBO(76, 175, 80, 0.35)
                              : (AppColors.isDark
                                    ? const Color.fromRGBO(255, 255, 255, 0.2)
                                    : AppColors.borderLight),
                        ),
                      ),
                      child: Text(
                        t[0].toUpperCase() + t.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _zakatType == t
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _inputLabel('Total Value'),
          TextField(
            controller: _amountCtl,
            onChanged: (_) => _calc(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 14, color: AppColors.text),
            decoration: _inputDecoration(hint: 'Enter total value'),
          ),
          if (_result > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.isDark
                      ? const Color.fromRGBO(0, 0, 0, 0.15)
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.05)
                        : AppColors.border,
                    width: 1.5,
                  ),
                  boxShadow: AppColors.isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Zakat Amount (2.5%)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmtMoney(selectedCurrency, _result),
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on $_zakatType assets worth ${fmtMoney(selectedCurrency, amount)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.isDark
                  ? const Color.fromRGBO(0, 0, 0, 0.15)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.05)
                    : AppColors.border,
                width: 1.5,
              ),
              boxShadow: AppColors.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Icon(
                  Ionicons.informationCircle,
                  size: 12,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zakat is calculated at 2.5% of your total wealth that has been held for one lunar year.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: SheetActions(
        primaryLabel: 'Close',
        cancelLabel: '',
        onPrimary: () => Navigator.pop(context),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category management sheet
// ---------------------------------------------------------------------------

class _CategoryManagerSheet extends ConsumerStatefulWidget {
  final String initialTab;
  const _CategoryManagerSheet({required this.initialTab});
  @override
  ConsumerState<_CategoryManagerSheet> createState() =>
      _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends ConsumerState<_CategoryManagerSheet> {
  late String _tab;
  final _nameCtl = TextEditingController();
  String _icon = 'heart';
  String _color = '#4CAF50';

  static const _icons = [
    'heart',
    'star',
    'bookmark',
    'flag',
    'diamond',
    'trophy',
    'medal',
    'ribbon',
  ];
  static const _colors = [
    '#4CAF50',
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#96CEB4',
    '#FFEAA7',
    '#DDA0DD',
    '#74B9FF',
    '#FD79A8',
    '#A29BFE',
  ];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab == 'outflow' ? 'outflow' : 'inflow';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameCtl.clear();
    _icon = 'heart';
    _color = '#4CAF50';
  }

  int _usage(String id) =>
      ref.read(appDataProvider).zakat.where((z) => z.category == id).length;

  String _nameOf(String id) {
    final hit = ref
        .read(appDataProvider)
        .zakatCategories
        .where((c) => c.id == id);
    return hit.isEmpty ? 'Deleted Category' : hit.first.name;
  }

  void _addCategory() {
    if (_nameCtl.text.trim().isEmpty) {
      _toast('Category name is required', error: true);
      return;
    }
    final nn = ref.read(appDataProvider.notifier);
    final st = ref.read(appDataProvider);
    nn.setZakatCategories([
      ...st.zakatCategories,
      ZakatCategory(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: _nameCtl.text.trim(),
        icon: _icon,
        color: _color,
        description: '',
        isDefault: false,
        type: _tab,
      ),
    ]);
    setState(_resetForm);
    _toast('Category added successfully');
  }

  Future<void> _deleteCategory(ZakatCategory cat) async {
    final usage = _usage(cat.id);
    final name = _nameOf(cat.id);
    if (usage > 0) {
      final choice = await showAdaptiveModalSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => AppModalSheet(
          size: SheetSize.compact,
          scrollable: false,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
          title: 'Category In Use',
          subtitle: name,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'This category "$name" is currently used by $usage transaction${usage == 1 ? '' : 's'}. What would you like to do?',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Ionicons.swapHorizontalOutline,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'Assign to Default Category',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Keep transactions and reassign to default',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'assign'),
              ),
              ListTile(
                leading: const Icon(
                  Ionicons.removeCircleOutline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove Category Reference',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Leave transactions uncategorized',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || choice == 'cancel') return;
      final nn = ref.read(appDataProvider.notifier);
      final state = ref.read(appDataProvider);
      if (choice == 'remove') {
        nn.setZakat([
          for (final t in state.zakat)
            t.category == cat.id
                ? ZakatTransaction(
                    id: t.id,
                    type: t.type,
                    amount: t.amount,
                    date: t.date,
                    description: t.description,
                    category: null,
                    receiptUri: t.receiptUri,
                  )
                : t,
        ]);
        nn.setZakatCategories(
          state.zakatCategories.where((c) => c.id != cat.id).toList(),
        );
        _toast(
          'Category deleted and removed from $usage transaction${usage == 1 ? '' : 's'}',
        );
      } else {
        final type = cat.type == 'both' ? 'inflow' : cat.type;
        final defaults = state.zakatCategories
            .where((c) => (c.type == type || c.type == 'both') && c.isDefault)
            .toList();
        if (defaults.isNotEmpty) {
          nn.setZakat([
            for (final t in state.zakat)
              t.category == cat.id
                  ? ZakatTransaction(
                      id: t.id,
                      type: t.type,
                      amount: t.amount,
                      date: t.date,
                      description: t.description,
                      category: defaults.first.id,
                      receiptUri: t.receiptUri,
                    )
                  : t,
          ]);
        } else {
          nn.setZakat([
            for (final t in state.zakat)
              t.category == cat.id
                  ? ZakatTransaction(
                      id: t.id,
                      type: t.type,
                      amount: t.amount,
                      date: t.date,
                      description: t.description,
                      category: null,
                      receiptUri: t.receiptUri,
                    )
                  : t,
          ]);
        }
        nn.setZakatCategories(
          state.zakatCategories.where((c) => c.id != cat.id).toList(),
        );
        _toast('Category deleted and reassigned to default category');
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.border),
          ),
          title: Text(
            'Delete Category',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$name"? This action cannot be undone.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final nn = ref.read(appDataProvider.notifier);
      nn.setZakatCategories(
        ref
            .read(appDataProvider)
            .zakatCategories
            .where((c) => c.id != cat.id)
            .toList(),
      );
      _toast('Category deleted successfully');
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, msg, isError: error, isSuccess: !error);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final cats = s.zakatCategories
        .where((c) => c.type == _tab || c.type == 'both')
        .toList();
    return AppModalSheet(
      title: 'Manage Categories',
      icon: Ionicons.settings,
      iconColor: AppColors.primary,
      headerTrailing: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _tabBtn(Ionicons.arrowDown, 'inflow'),
            const SizedBox(width: 4),
            _tabBtn(Ionicons.arrowUp, 'outflow'),
          ],
        ),
      ),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add category form
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add New Category',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                _inputLabel('Category Name *'),
                TextField(
                  controller: _nameCtl,
                  style: TextStyle(fontSize: 14, color: AppColors.text),
                  decoration: _inputDecoration(hint: 'Enter category name'),
                ),
                const SizedBox(height: 8),
                _inputLabel('Icon'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ic in _icons)
                      GestureDetector(
                        onTap: () => setState(() => _icon = ic),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _icon == ic
                                ? AppColors.primary
                                : AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _icon == ic
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _ion(ic),
                            size: 16,
                            color: _icon == ic
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _inputLabel('Color'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _colors)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _hex(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: _color == c ? 3 : 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(_resetForm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color.fromRGBO(255, 255, 255, 0.2),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _addCategory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'Add Category',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Categories list
          Text(
            '${_tab == 'inflow' ? 'Inflow' : 'Outflow'} Categories',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          if (cats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No categories available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            for (final cat in cats) _categoryItem(cat),
        ],
      ),
      footer: SheetActions(
        primaryLabel: 'Close',
        cancelLabel: '',
        onPrimary: () => Navigator.pop(context),
      ),
    );
  }

  Widget _tabBtn(IconData icon, String key) => GestureDetector(
    onTap: () => setState(() => _tab = key),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _tab == key ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        icon,
        size: 18,
        color: _tab == key ? Colors.white : AppColors.textSecondary,
      ),
    ),
  );

  Widget _categoryItem(ZakatCategory cat) {
    final isCustom = !cat.isDefault && cat.id.startsWith('custom-');
    final usage = _usage(cat.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _hex(cat.color),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _ion(cat.icon),
              size: 16,
              color: _contrast(_hex(cat.color)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                Row(
                  children: [
                    if (isCustom)
                      const Padding(
                        padding: EdgeInsets.only(right: 8, top: 2),
                        child: Text(
                          'CUSTOM',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (usage > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(160, 216, 216, 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$usage transaction${usage == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isCustom)
            GestureDetector(
              onTap: () => _deleteCategory(cat),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.trash,
                  size: 16,
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Widget _receiptImage(String uri, {BoxFit fit = BoxFit.cover}) {
  Widget fallback() => Container(
    color: AppColors.surface,
    alignment: Alignment.center,
    child: Icon(Ionicons.documentText, color: AppColors.textSecondary),
  );
  if (uri.startsWith('http')) {
    return Image.network(uri, fit: fit, errorBuilder: (_, _, _) => fallback());
  }
  if (uri.startsWith('content://')) {
    return Image.network(uri, fit: fit, errorBuilder: (_, _, _) => fallback());
  }
  return Image.file(File(uri), fit: fit, errorBuilder: (_, _, _) => fallback());
}

IconData _ion(String name) {
  switch (name) {
    case 'arrow-down':
      return Ionicons.arrowDown;
    case 'arrow-up':
      return Ionicons.arrowUp;
    case 'refresh':
      return Ionicons.refresh;
    case 'trending-up':
      return Ionicons.trendingUp;
    case 'stats-chart':
      return Ionicons.statsChart;
    case 'calculator':
      return Ionicons.calculator;
    case 'create':
      return Ionicons.create;
    case 'add':
      return Ionicons.add;
    case 'add-circle':
      return Ionicons.addCircle;
    case 'list':
      return Ionicons.list;
    case 'settings':
      return Ionicons.settings;
    case 'close':
      return Ionicons.close;
    case 'close-circle':
      return Ionicons.closeCircle;
    case 'search':
      return Ionicons.search;
    case 'calendar':
      return Ionicons.calendar;
    case 'information-circle':
      return Ionicons.informationCircle;
    case 'checkmark-done':
      return Ionicons.checkmarkDone;
    case 'trash':
      return Ionicons.trash;
    case 'chevron-forward':
      return Ionicons.chevronForward;
    case 'chevron-up':
      return Ionicons.chevronUp;
    case 'chevron-down':
      return Ionicons.chevronDown;
    case 'document-text':
      return Ionicons.documentText;
    case 'expand':
      return Ionicons.expand;
    case 'hourglass':
      return Ionicons.hourglass;
    case 'save':
      return Ionicons.save;
    case 'restaurant':
      return Ionicons.restaurant;
    case 'school':
      return Ionicons.school;
    case 'medical':
      return Ionicons.medical;
    case 'people':
      return Ionicons.people;
    case 'business':
      return Ionicons.business;
    case 'home':
      return Ionicons.home;
    case 'water':
      return Ionicons.water;
    case 'warning':
      return Ionicons.warning;
    case 'heart':
      return Ionicons.heart;
    case 'grid':
      return Ionicons.grid;
    case 'star':
      return Ionicons.star;
    case 'bookmark':
      return Ionicons.bookmark;
    case 'flag':
      return Ionicons.flag;
    case 'diamond':
      return Ionicons.diamond;
    case 'trophy':
      return Ionicons.trophy;
    case 'medal':
      return Ionicons.medal;
    case 'ribbon':
      return Ionicons.ribbon;
    default:
      return Ionicons.pricetag;
  }
}

Color _hex(String value) {
  var h = value.replaceAll('#', '').trim();
  if (h.length == 3) {
    h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
  }
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? AppColors.iconSecondary : Color(v);
}

Color _contrast(Color c) {
  final lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
  return lum > 0.6 ? AppColors.backgroundDark : Colors.white;
}
