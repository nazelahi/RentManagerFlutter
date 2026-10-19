import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../documents/documents_view.dart';
import '../overview/overview_view.dart';
import '../work_orders/work_orders_view.dart';
import 'desktop_batch_rent_modal.dart';
import 'desktop_rent_receipt_modal.dart';
import 'desktop_cash_flow_modal.dart';

/// Raycast / Spotlight style Command Palette (Cmd + K) for macOS desktop.
class DesktopCommandPalette extends ConsumerStatefulWidget {
  final Function(int tabIndex) onNavigate;
  final Function(Tenant tenant) onSelectTenant;
  final VoidCallback onAddTenant;
  final VoidCallback onLogPayment;

  const DesktopCommandPalette({
    super.key,
    required this.onNavigate,
    required this.onSelectTenant,
    required this.onAddTenant,
    required this.onLogPayment,
  });

  static Future<void> show({
    required BuildContext context,
    required Function(int tabIndex) onNavigate,
    required Function(Tenant tenant) onSelectTenant,
    required VoidCallback onAddTenant,
    required VoidCallback onLogPayment,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierDismissible: true,
      builder: (_) => DesktopCommandPalette(
        onNavigate: onNavigate,
        onSelectTenant: onSelectTenant,
        onAddTenant: onAddTenant,
        onLogPayment: onLogPayment,
      ),
    );
  }

  @override
  ConsumerState<DesktopCommandPalette> createState() =>
      _DesktopCommandPaletteState();
}

class _DesktopCommandPaletteState
    extends ConsumerState<DesktopCommandPalette> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  String _selectedCategory = 'ALL'; // 'ALL', 'TENANTS', 'ACTIONS', 'NAVIGATION'

  final List<String> _categories = const [
    'ALL',
    'TENANTS',
    'ACTIONS',
    'NAVIGATION',
  ];

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 60.0;
    final targetOffset = index * itemHeight;
    final currentOffset = _scrollController.offset;
    const viewportHeight = 360.0;
    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  void _cycleCategory() {
    final curIdx = _categories.indexOf(_selectedCategory);
    final nextIdx = (curIdx + 1) % _categories.length;
    setState(() {
      _selectedCategory = _categories[nextIdx];
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final query = _queryController.text.trim().toLowerCase();

    // 1. Navigation items
    final navItems = [
      _PaletteItem(
        title: 'Overview Dashboard',
        subtitle: 'Monthly rent roll, cash flow, and summary',
        icon: Ionicons.homeOutline,
        category: 'NAVIGATION',
        shortcut: '⌘1',
        action: () => widget.onNavigate(0),
      ),
      _PaletteItem(
        title: 'Tenants Directory',
        subtitle: 'View, add, and manage building tenants',
        icon: Ionicons.peopleOutline,
        category: 'NAVIGATION',
        shortcut: '⌘2',
        action: () => widget.onNavigate(1),
      ),
      _PaletteItem(
        title: 'Work Orders & Maintenance',
        subtitle: 'Track property repair requests and contractors',
        icon: Ionicons.constructOutline,
        category: 'NAVIGATION',
        shortcut: '⌘3',
        action: () => widget.onNavigate(2),
      ),
      _PaletteItem(
        title: 'Documents & Leases',
        subtitle: 'Manage legal agreements and property files',
        icon: Ionicons.documentTextOutline,
        category: 'NAVIGATION',
        shortcut: '⌘4',
        action: () => widget.onNavigate(3),
      ),
      _PaletteItem(
        title: 'Financial Reports',
        subtitle: 'Cash flow analytics, income & tax statements',
        icon: Ionicons.barChartOutline,
        category: 'NAVIGATION',
        shortcut: '⌘5',
        action: () => widget.onNavigate(4),
      ),
      if (s.preferences.showZakat)
        _PaletteItem(
          title: 'Zakat Calculator',
          subtitle: 'Calculate and record annual zakat on rental assets',
          icon: Ionicons.pricetagOutline,
          category: 'NAVIGATION',
          shortcut: '⌘6',
          action: () => widget.onNavigate(5),
        ),
    ];

    // 2. Action items
    final actionItems = [
      _PaletteItem(
        title: 'Add New Tenant',
        subtitle: 'Register a new tenant, lease terms, and unit',
        icon: Ionicons.personAddOutline,
        category: 'ACTIONS',
        action: widget.onAddTenant,
      ),
      _PaletteItem(
        title: 'Add Rent',
        subtitle: 'Record collected rent or invoice payment',
        icon: Ionicons.cashOutline,
        category: 'ACTIONS',
        shortcut: '⇧⌘P',
        action: widget.onLogPayment,
      ),
      _PaletteItem(
        title: 'Batch Rent Collection Sheet',
        subtitle: '1-click monthly roll to collect all active tenants',
        icon: Ionicons.layersOutline,
        category: 'ACTIONS',
        shortcut: '⇧⌘B',
        action: () => DesktopBatchRentModal.show(context),
      ),
      _PaletteItem(
        title: 'Generate Rent Receipt & Invoice',
        subtitle: 'Branded PDF payment receipt with manager signature block',
        icon: Ionicons.receiptOutline,
        category: 'ACTIONS',
        shortcut: '⇧⌘I',
        action: () => DesktopRentReceiptModal.show(context),
      ),
      _PaletteItem(
        title: 'Cash Flow Forecast & Financial Health',
        subtitle: '6-12 month predictive cash flow, NOI, and lease renewal pipeline',
        icon: Ionicons.trendingUpOutline,
        category: 'ACTIONS',
        shortcut: '⇧⌘F',
        action: () => DesktopCashFlowModal.show(context),
      ),
      _PaletteItem(
        title: 'Add Expense',
        subtitle: 'Record maintenance, utility, or property operational expense',
        icon: Ionicons.receiptOutline,
        category: 'ACTIONS',
        action: () => OverviewView.showExpenseSheet(context),
      ),
      _PaletteItem(
        title: 'Sync Previous Month Roll',
        subtitle: 'Roll forward rent payments or recurring expenses from previous month',
        icon: Ionicons.syncOutline,
        category: 'ACTIONS',
        action: () => OverviewView.showSyncSheet(context),
      ),
      _PaletteItem(
        title: 'Add Work Order',
        subtitle: 'File maintenance or contractor repair ticket',
        icon: Ionicons.buildOutline,
        category: 'ACTIONS',
        action: () => WorkOrdersView.showAddModal(context),
      ),
      _PaletteItem(
        title: 'Add Document',
        subtitle: 'Add property deed, tenant lease, or insurance file',
        icon: Ionicons.cloudUploadOutline,
        category: 'ACTIONS',
        action: () => DocumentsView.showAddModal(context),
      ),
      _PaletteItem(
        title: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
        subtitle: 'Toggle macOS appearance mode',
        icon: isDark ? Ionicons.sunnyOutline : Ionicons.moonOutline,
        category: 'ACTIONS',
        action: () {
          ref
              .read(appDataProvider.notifier)
              .setThemeMode(isDark ? 'light' : 'dark');
        },
      ),
    ];

    // 3. Tenant results
    final tenantItems = s.tenants.map((t) {
      return _PaletteItem(
        title: t.name,
        subtitle:
            'Unit ${t.unit.isEmpty ? 'N/A' : t.unit} • ${s.selectedCurrency} ${t.rentAmount.toStringAsFixed(0)}/mo • ${t.phone.isNotEmpty ? t.phone : 'No phone'}',
        icon: Ionicons.personOutline,
        category: 'TENANTS',
        tenant: t,
        action: () => widget.onSelectTenant(t),
      );
    }).toList();

    // Counts for tabs
    final allItems = [...tenantItems, ...actionItems, ...navItems];
    final allMatching = query.isEmpty
        ? allItems
        : allItems.where((item) => item.matches(query)).toList();

    final filtered = _selectedCategory == 'ALL'
        ? allMatching
        : allMatching
            .where((item) => item.category == _selectedCategory)
            .toList();

    if (_selectedIndex >= filtered.length) {
      _selectedIndex = filtered.isEmpty ? 0 : filtered.length - 1;
    }

    final cardBg = isDark ? const Color(0xFF07191A) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.12)
        : const Color(0xFFE2E8F0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              if (_selectedIndex < filtered.length - 1) {
                _selectedIndex++;
                _scrollToSelected(_selectedIndex);
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() {
              if (_selectedIndex > 0) {
                _selectedIndex--;
                _scrollToSelected(_selectedIndex);
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (filtered.isNotEmpty && _selectedIndex < filtered.length) {
              Navigator.of(context).pop();
              filtered[_selectedIndex].action();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.tab) {
            _cycleCategory();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Click outside to close backdrop
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),

            // Modal card
            Center(
              child: GestureDetector(
                onTap: () {}, // Prevent tap inside from closing
                child: Container(
                  width: 620,
                  margin: const EdgeInsets.only(top: 60, bottom: 60),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.22),
                        blurRadius: 36,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Search Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F2626)
                                    : const Color(0xFFE6F4EA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Ionicons.searchOutline,
                                size: 18,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _queryController,
                                autofocus: true,
                                onChanged: (_) =>
                                    setState(() => _selectedIndex = 0),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search tenants, units, commands, reports... (⌘K)',
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_queryController.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Tooltip(
                                  message: 'Clear search',
                                  child: InkWell(
                                    onTap: () {
                                      _queryController.clear();
                                      setState(() => _selectedIndex = 0);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Ionicons.closeCircle,
                                        size: 18,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Explicit Close Button with Tooltip and Escape Hint
                            Tooltip(
                              message: 'Close search modal (Esc)',
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF132B2B)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Ionicons.close,
                                        size: 14,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ESC',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
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
                        ),
                      ),

                      // Category Filter Chips
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: Row(
                          children: [
                            _categoryChip(
                              'ALL',
                              'All',
                              allMatching.length,
                              isDark,
                              borderColor,
                            ),
                            const SizedBox(width: 8),
                            _categoryChip(
                              'TENANTS',
                              'Tenants',
                              allMatching
                                  .where((i) => i.category == 'TENANTS')
                                  .length,
                              isDark,
                              borderColor,
                            ),
                            const SizedBox(width: 8),
                            _categoryChip(
                              'ACTIONS',
                              'Actions',
                              allMatching
                                  .where((i) => i.category == 'ACTIONS')
                                  .length,
                              isDark,
                              borderColor,
                            ),
                            const SizedBox(width: 8),
                            _categoryChip(
                              'NAVIGATION',
                              'Navigation',
                              allMatching
                                  .where((i) => i.category == 'NAVIGATION')
                                  .length,
                              isDark,
                              borderColor,
                            ),
                          ],
                        ),
                      ),

                      Divider(height: 1, color: borderColor),

                      // Results List
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: filtered.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Ionicons.searchOutline,
                                      size: 36,
                                      color: isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No matching commands or tenants',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try searching for tenant names, units, "Payment", or "Reports"',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextButton.icon(
                                      onPressed: () {
                                        _queryController.clear();
                                        setState(() {
                                          _selectedCategory = 'ALL';
                                          _selectedIndex = 0;
                                        });
                                      },
                                      icon: const Icon(Ionicons.refreshOutline,
                                          size: 14),
                                      label: const Text('Reset search'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                itemBuilder: (context, i) {
                                  final item = filtered[i];
                                  final isSelected = i == _selectedIndex;

                                  return InkWell(
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      item.action();
                                    },
                                    hoverColor: Colors.transparent,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 3),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF0F766E)
                                                    .withValues(alpha: 0.35)
                                                : const Color(0xFF059669)
                                                    .withValues(alpha: 0.12))
                                            : Colors.transparent,
                                        border: isSelected
                                            ? Border.all(
                                                color: isDark
                                                    ? const Color(0xFF10B981)
                                                        .withValues(alpha: 0.5)
                                                    : const Color(0xFF059669)
                                                        .withValues(alpha: 0.4),
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          // Leading Avatar / Icon
                                          if (item.tenant != null)
                                            AvatarView(
                                              name: item.tenant!.name,
                                              uri: item.tenant!.avatar,
                                              radius: 17,
                                              borderColor: isSelected
                                                  ? AppColors.primary
                                                  : null,
                                              borderWidth:
                                                  isSelected ? 1.5 : 0,
                                            )
                                          else
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: isSelected
                                                    ? const Color(0xFF059669)
                                                    : (isDark
                                                        ? const Color(0xFF0F2626)
                                                        : const Color(
                                                            0xFFF1F5F9)),
                                              ),
                                              child: Icon(
                                                item.icon,
                                                size: 17,
                                                color: isSelected
                                                    ? Colors.white
                                                    : (isDark
                                                        ? const Color(
                                                            0xFF34D399)
                                                        : const Color(
                                                            0xFF059669)),
                                              ),
                                            ),
                                          const SizedBox(width: 12),

                                          // Title & Subtitle
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        item.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isDark
                                                              ? Colors.white
                                                              : const Color(
                                                                  0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                    if (item.tenant != null) ...[
                                                      const SizedBox(width: 8),
                                                      _statusBadge(
                                                        item.tenant!.status,
                                                        isDark,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: isDark
                                                        ? const Color(0xFF94A3B8)
                                                        : const Color(
                                                            0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Shortcut hint or Category tag
                                          if (item.shortcut != null)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 6),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF132B2B)
                                                    : const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color: borderColor),
                                              ),
                                              child: Text(
                                                item.shortcut!,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? const Color(0xFF34D399)
                                                      : const Color(0xFF059669),
                                                ),
                                              ),
                                            ),

                                          if (isSelected)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF10B981)
                                                        .withValues(alpha: 0.22)
                                                    : const Color(0xFF059669)
                                                        .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '↵ Open',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF34D399)
                                                          : const Color(
                                                              0xFF059669),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF0A1F20)
                                                    : const Color(0xFFE2E8F0),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                item.category,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.7,
                                                  color: isDark
                                                      ? const Color(0xFF64748B)
                                                      : const Color(0xFF475569),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      Divider(height: 1, color: borderColor),

                      // Footer Navigation Bar & Close Button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        child: Row(
                          children: [
                            Text(
                              'Navigate ↑ ↓',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Select ↵',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Filter Tab',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                            const Spacer(),

                            // Explicit Clickable Close in Footer
                            InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(5),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Ionicons.closeCircleOutline,
                                      size: 14,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Close (Esc)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(
    String categoryKey,
    String label,
    int count,
    bool isDark,
    Color borderColor,
  ) {
    final isSelected = _selectedCategory == categoryKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = categoryKey;
          _selectedIndex = 0;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? const Color(0xFF0F766E).withValues(alpha: 0.35)
                  : const Color(0xFF059669).withValues(alpha: 0.12))
              : (isDark ? const Color(0xFF0D2223) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                : borderColor,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669))
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? const Color(0xFF10B981).withValues(alpha: 0.25)
                        : const Color(0xFF059669).withValues(alpha: 0.2))
                    : (isDark
                        ? const Color(0xFF142B2C)
                        : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? (isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status, bool isDark) {
    Color bg;
    Color fg;
    String text;

    switch (status.toLowerCase()) {
      case 'active':
        bg = const Color(0xFF10B981).withValues(alpha: 0.16);
        fg = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
        text = 'Active';
        break;
      case 'late':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.16);
        fg = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
        text = 'Late';
        break;
      case 'vacated':
      case 'inactive':
        bg = const Color(0xFFEF4444).withValues(alpha: 0.16);
        fg = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
        text = 'Vacated';
        break;
      default:
        bg = const Color(0xFF64748B).withValues(alpha: 0.16);
        fg = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
        text = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _PaletteItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String category;
  final String? shortcut;
  final Tenant? tenant;
  final VoidCallback action;

  _PaletteItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    this.shortcut,
    this.tenant,
    required this.action,
  });

  bool matches(String query) {
    if (title.toLowerCase().contains(query)) return true;
    if (subtitle.toLowerCase().contains(query)) return true;
    if (category.toLowerCase().contains(query)) return true;
    if (tenant != null) {
      if (tenant!.unit.toLowerCase().contains(query)) return true;
      if (tenant!.phone.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}
