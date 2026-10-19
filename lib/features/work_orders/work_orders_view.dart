import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/wave_animation.dart';
import '../desktop/desktop_work_orders_view.dart';

/// Port of `src/screens/WorkOrdersScreen.tsx` — fixed header (search toggle +
/// add), year selector, 4 status filter tabs, stats, collapsible search with
/// suggestions, bulk-selection mode, status-tinted row cards with cost table,
/// long-press action menu, sectioned details modal, and Add (single/multiple) /
/// Edit (full-screen) modals.

// ===== status helpers (Expo getStatusColor/Bg/Border/icon) =====
Color _woColor(String s) {
  switch (s) {
    case 'completed':
      return const Color(0xFF4CAF50);
    case 'in-progress':
      return const Color(0xFF2196F3);
    case 'pending':
      return const Color(0xFFFF9800);
    case 'cancelled':
      return const Color(0xFF9E9E9E);
    default:
      return const Color(0xFF4CAF50);
  }
}

Color _woBg(String s) {
  if (!AppColors.isDark) {
    switch (s) {
      case 'in-progress':
        return const Color.fromRGBO(33, 150, 243, 0.08);
      case 'pending':
        return const Color.fromRGBO(255, 152, 0, 0.08);
      case 'cancelled':
        return const Color.fromRGBO(158, 158, 158, 0.08);
      default:
        return AppColors.cardBackground;
    }
  }
  switch (s) {
    case 'in-progress':
      return const Color.fromRGBO(33, 150, 243, 0.08);
    case 'pending':
      return const Color.fromRGBO(255, 152, 0, 0.08);
    case 'cancelled':
      return const Color.fromRGBO(158, 158, 158, 0.08);
    default:
      return const Color.fromRGBO(255, 255, 255, 0.03);
  }
}

Color _woBorder(String s) {
  if (!AppColors.isDark) {
    switch (s) {
      case 'in-progress':
        return const Color.fromRGBO(33, 150, 243, 0.25);
      case 'pending':
        return const Color.fromRGBO(255, 152, 0, 0.25);
      case 'cancelled':
        return const Color.fromRGBO(158, 158, 158, 0.25);
      default:
        return AppColors.border;
    }
  }
  switch (s) {
    case 'in-progress':
      return const Color.fromRGBO(33, 150, 243, 0.15);
    case 'pending':
      return const Color.fromRGBO(255, 152, 0, 0.15);
    case 'cancelled':
      return const Color.fromRGBO(158, 158, 158, 0.15);
    default:
      return const Color.fromRGBO(255, 255, 255, 0.08);
  }
}

IconData _woIcon(String s) {
  switch (s) {
    case 'completed':
      return Icons.check_circle;
    case 'in-progress':
      return Icons.play_circle;
    case 'cancelled':
      return Icons.cancel;
    default:
      return Icons.schedule;
  }
}

IconData _woGlyph(String s) {
  switch (s) {
    case 'completed':
      return Icons.check;
    case 'in-progress':
      return Icons.play_arrow;
    case 'cancelled':
      return Icons.close;
    default:
      return Icons.schedule;
  }
}

String _woLabel(String s) {
  switch (s) {
    case 'in-progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    case 'pending':
      return 'Pending';
    default:
      return s;
  }
}

const List<String> _woStatuses = [
  'pending',
  'in-progress',
  'completed',
  'cancelled',
];

const List<String> _filterTabs = ['all', 'pending', 'in-progress', 'completed'];

class WorkOrdersView extends ConsumerStatefulWidget {
  static final globalKey = GlobalKey<_WorkOrdersViewState>();
  const WorkOrdersView({super.key});

  static void showAddModal(BuildContext context) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WorkOrderFormSheet(initial: null, isEdit: false),
    );
  }

  static void showEditModal(BuildContext context, WorkOrder o) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkOrderFormSheet(initial: o, isEdit: true),
    );
  }

  @override
  ConsumerState<WorkOrdersView> createState() => _WorkOrdersViewState();
}

class _WorkOrdersViewState extends ConsumerState<WorkOrdersView> {
  String _q = '';
  String _status = 'all';
  late int _year = DateTime.now().year;
  bool _searchOpen = false;
  bool _searchFocused = false;
  bool _showSuggestions = false;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _saving = false;

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

  // ---- derived data ----
  List<String> _suggestions(List<WorkOrder> all) {
    if (_q.length < 2) return [];
    final q = _q.toLowerCase();
    final out = <String>{};
    for (final o in all) {
      void add(String? v) {
        if (v != null && v.toLowerCase().contains(q)) out.add(v);
      }

      add(o.title);
      add(o.description);
      add(o.category);
      add(o.status);
      add(o.assignedTo);
    }
    return out.take(8).toList();
  }

  int _suggestionCount(List<WorkOrder> all, String suggestion) {
    final q = suggestion.toLowerCase();
    return all.where((o) {
      return o.title.toLowerCase().contains(q) ||
          o.description.toLowerCase().contains(q) ||
          o.category.toLowerCase().contains(q) ||
          o.status.toLowerCase().contains(q) ||
          o.assignedTo.toLowerCase().contains(q);
    }).length;
  }

  List<WorkOrder> _filtered(List<WorkOrder> all) {
    final q = _q.toLowerCase();
    return all.where((o) {
      final y = DateTime.tryParse(o.createdAt)?.year;
      if (y != _year) return false;
      if (_status != 'all' && o.status != _status) return false;
      if (_q.isEmpty) return true;
      return o.title.toLowerCase().contains(q) ||
          o.description.toLowerCase().contains(q) ||
          o.category.toLowerCase().contains(q) ||
          o.status.toLowerCase().contains(q) ||
          o.assignedTo.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopWorkOrdersView(
        onAddOrder: () => _openAdd(context),
        onEditOrder: (o) => _openEdit(context, o),
        onSelectOrder: (o) => _details(context, o),
      );
    }

    final s = ref.watch(appDataProvider);
    final all = s.scopedWorkOrders;
    final filtered = _filtered(all);
    final pending = filtered.where((o) => o.status == 'pending').length;
    final inProgress = filtered.where((o) => o.status == 'in-progress').length;
    final completed = filtered.where((o) => o.status == 'completed').length;
    final suggestions = _suggestions(all);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Column(
              children: [
                _header(context, filtered.length, s),
                Expanded(
                  child: PullToRefresh(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchOpen) _searchSection(suggestions),
                          _stats(filtered.length, pending, completed),
                          _yearSelector(),
                          _filterTabsRow(
                            filtered.length,
                            pending,
                            inProgress,
                            completed,
                          ),
                          if (_selecting) _selectionBar(),
                          if (_wave)
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: WaveAnimation(
                                count: 6,
                                icon: Ionicons.constructOutline,
                              ),
                            )
                          else
                            _ordersList(s, filtered),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_saving) _savingPill(),
          ],
        ),
      ),
    );
  }

  // ===== Header =====

  Widget _header(BuildContext context, int total, AppDataState s) {
    final isDark = AppColors.isDark;
    final topPadding = MediaQuery.of(context).padding.top;
    final propName =
        s.activeProperty?.name ??
        s.propertyManager?.propertyName ??
        'Active Property';

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
          // Left: Work Orders Icon Badge
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
                      Icons.build_rounded,
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
                      'Work Orders',
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
                  propName,
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
              _headerButton(
                icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                isDark: isDark,
                isActive: _searchOpen,
                onTap: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _q = '';
                    _showSuggestions = false;
                  }
                }),
              ),
              const SizedBox(width: 8),
              _headerButton(
                icon: Icons.add_rounded,
                isDark: isDark,
                isAdd: true,
                onTap: () => _openAdd(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
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

  // ===== search =====
  Widget _searchSection(List<String> suggestions) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
    child: Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.isDark
                ? const Color.fromRGBO(255, 255, 255, 0.1)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.2)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 18,
                color: _searchFocused
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _q = v;
                    _showSuggestions = v.isNotEmpty;
                  }),
                  onTap: () => setState(() {
                    _searchFocused = true;
                    _showSuggestions = _q.isNotEmpty;
                  }),
                  style: TextStyle(color: AppColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search work orders...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (_q.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _q = '';
                    _showSuggestions = false;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_showSuggestions && suggestions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.dropdownBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: suggestions
                  .map(
                    (sg) => GestureDetector(
                      onTap: () => setState(() {
                        _q = sg;
                        _showSuggestions = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Color.fromRGBO(255, 255, 255, 0.1),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                sg,
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              '${_suggestionCount(ref.read(appDataProvider).scopedWorkOrders, sg)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );

  // ===== stats =====
  Widget _stats(int total, int pending, int completed) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
    child: Row(
      children: [
        _statCard(
          '$total',
          'Total Orders',
          Icons.construction,
          AppColors.primary,
        ),
        const SizedBox(width: 4),
        _statCard(
          '$pending',
          'Pending',
          Icons.schedule,
          const Color(0xFFFF9800),
        ),
        const SizedBox(width: 4),
        _statCard(
          '$completed',
          'Completed',
          Icons.check_circle,
          AppColors.primary,
        ),
      ],
    ),
  );

  Widget _statCard(String number, String label, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.isDark ? null : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
            gradient: AppColors.isDark
                ? const LinearGradient(
                    colors: [
                      Color.fromRGBO(255, 255, 255, 0.08),
                      Color.fromRGBO(255, 255, 255, 0.03),
                    ],
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(76, 175, 80, 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
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
      );

  // ===== year selector =====
  Widget _yearSelector() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        gradient: AppColors.isDark
            ? const LinearGradient(
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.1),
                  Color.fromRGBO(255, 255, 255, 0.05),
                ],
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _changeYear(-1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.chevron_left,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _pickYear(),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_year',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _changeYear(1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _changeYear(int delta) {
    final n = _year + delta;
    if (n < 1900 || n > 2100) return;
    setState(() => _year = n);
    _flashWave();
  }

  Future<void> _pickYear() async {
    var y = _year;
    final picked = await showAdaptiveModalSheet<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDark = AppColors.isDark;
          return AppModalSheet(
            title: 'Select Year',
            icon: Ionicons.calendarOutline,
            iconColor: AppColors.primary,
            size: SheetSize.compact,
            scrollable: false,
            body: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border.withValues(
                      alpha: isDark ? 0.4 : 0.7,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () =>
                          setS(() => y = (y - 1).clamp(1900, 2100)),
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Text(
                      '$y',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      onPressed: () =>
                          setS(() => y = (y + 1).clamp(1900, 2100)),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            footer: SheetActions(
              primaryLabel: 'Select Year',
              onPrimary: () => Navigator.pop(ctx, y),
            ),
          );
        },
      ),
    );
    if (picked != null) {
      setState(() => _year = picked);
      _flashWave();
    }
  }

  // ===== filter tabs =====
  Widget _filterTabsRow(int total, int pending, int inProgress, int completed) {
    final counts = {
      'all': total,
      'pending': pending,
      'in-progress': inProgress,
      'completed': completed,
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        gradient: AppColors.isDark
            ? const LinearGradient(
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.1),
                  Color.fromRGBO(255, 255, 255, 0.05),
                ],
              )
            : null,
      ),
      child: Row(
        children: _filterTabs.map((f) {
          final active = _status == f;
          final text = f == 'all'
              ? 'All (${counts[f]})'
              : '${_woLabel(f)} (${counts[f]})';
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_status == f) return;
                setState(() => _status = f);
                _flashWave();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===== selection bar =====
  Widget _selectionBar() => Container(
    margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
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
            '${_selected.length} selected',
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
            _selectionAction(
              icon: Icons.done_all,
              color: AppColors.primary,
              label: 'All',
              onTap: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(
                    _filtered(ref.read(appDataProvider).scopedWorkOrders)
                        .map((o) => o.id),
                  );
              }),
            ),
            _selectionAction(
              icon: Icons.close,
              color: AppColors.error,
              label: 'None',
              onTap: () => setState(() => _selected.clear()),
            ),
            if (_selected.isNotEmpty)
              _selectionAction(
                icon: Icons.delete,
                color: AppColors.error,
                label: 'Delete',
                danger: true,
                onTap: _bulkDelete,
              ),
            _selectionAction(
              icon: Icons.close,
              color: AppColors.textSecondary,
              label: 'Cancel',
              onTap: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _selectionAction({
    required IconData icon,
    required Color color,
    required String label,
    bool danger = false,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 60),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: danger
            ? const Color.fromRGBO(255, 107, 107, 0.1)
            : (AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.05)
                  : AppColors.surface),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: danger
              ? const Color.fromRGBO(255, 107, 107, 0.3)
              : (AppColors.isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.1)
                    : AppColors.border),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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

  Future<void> _bulkDelete() async {
    final n = _selected.length;
    final ok = await confirmDialog(
      context,
      'Delete Selected Work Orders',
      'Are you sure you want to delete $n work order(s)? This action cannot be undone.',
    );
    if (!ok) return;
    final notifier = ref.read(appDataProvider.notifier);
    for (final id in _selected.toList()) {
      notifier.deleteWorkOrder(id);
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    _flashSaving();
  }

  // ===== orders list =====
  Widget _ordersList(AppDataState s, List<WorkOrder> filtered) => Container(
    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
    child: filtered.isEmpty
        ? _emptyState()
        : Column(
            children: [
              for (final o in filtered) ...[
                _rowCard(s, o),
                const SizedBox(height: 4),
              ],
            ],
          ),
  );

  Widget _rowCard(AppDataState s, WorkOrder o) {
    final selected = _selected.contains(o.id);
    final showCosts = o.workerCost != null || o.productPrice != null;
    final total = (o.productPrice ?? 0) + (o.workerCost ?? 0);
    return GestureDetector(
      onTap: () {
        if (_selecting) {
          setState(() {
            if (selected) {
              _selected.remove(o.id);
            } else {
              _selected.add(o.id);
            }
          });
        } else {
          _details(context, o);
        }
      },
      onLongPress: () {
        AppHaptics.medium();
        if (_selecting) {
          setState(() {
            if (selected) {
              _selected.remove(o.id);
            } else {
              _selected.add(o.id);
            }
          });
        } else {
          _longPress(o);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color.fromRGBO(76, 175, 80, 0.08)
              : _woBg(o.status),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color.fromRGBO(76, 175, 80, 0.2)
                : _woBorder(o.status),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            o.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _woIcon(o.status),
                          size: 16,
                          color: _woColor(o.status),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        o.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (o.receipt != null && o.receipt!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(76, 175, 80, 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.receipt,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // description row
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      o.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (o.status == 'completed' && o.dueDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.done_all,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fmtDate(o.dueDate, pattern: 'dMMM yyyy'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (showCosts)
              Container(
                padding: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.1)
                          : AppColors.borderLight,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Row(
                        children: const [
                          Expanded(
                            child: _CostCell(text: 'Type', header: true),
                          ),
                          Expanded(
                            child: _CostCell(text: 'Amount', header: true),
                          ),
                          Expanded(
                            child: _CostCell(text: 'Status', header: true),
                          ),
                        ],
                      ),
                    ),
                    if (o.workerCost != null)
                      _costRow(
                        Icons.person,
                        const Color(0xFFFF9800),
                        'Worker',
                        fmtMoney(s.selectedCurrency, o.workerCost!),
                      ),
                    if (o.productPrice != null)
                      _costRow(
                        Icons.inventory_2,
                        const Color(0xFF2196F3),
                        'Materials',
                        fmtMoney(s.selectedCurrency, o.productPrice!),
                      ),
                    if (o.status == 'completed')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        color: const Color.fromRGBO(76, 175, 80, 0.05),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calculate,
                                    size: 14,
                                    color: Color(0xFFFFA726),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  fmtMoney(s.selectedCurrency, total),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
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
      ),
    );
  }

  Widget _costRow(IconData icon, Color color, String label, String amount) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.05)
                  : AppColors.borderLight,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  amount,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Paid',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _emptyState() => Container(
    constraints: const BoxConstraints(minHeight: 200),
    alignment: Alignment.center,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        gradient: AppColors.isDark
            ? const LinearGradient(
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.03),
                  Color.fromRGBO(255, 255, 255, 0.01),
                ],
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 107, 107, 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.construction,
              size: 32,
              color: AppColors.error,
            ),
          ),
          Text(
            'No Work Orders',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              'No work orders found for this period. Start by adding your first work order using the + button above.',
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

  Widget _savingPill() => Positioned(
    top: 60,
    right: 16,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
        gradient: const LinearGradient(
          colors: [
            Color.fromRGBO(76, 175, 80, 0.9),
            Color.fromRGBO(76, 175, 80, 0.7),
          ],
        ),
      ),
      child: Row(
        children: const [
          Icon(Icons.save, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Saving...',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  void _flashSaving() {
    setState(() => _saving = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _saving = false);
    });
  }

  // ===== long-press action menu =====
  Future<void> _longPress(WorkOrder o) async {
    final action = await showAdaptiveModalSheet<String>(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Work Order Actions',
        subtitle: o.title,
        icon: Icons.construction,
        iconColor: AppColors.accentDark,
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          children: [
            ListTile(
              leading: Icon(Ionicons.syncOutline, color: _woColor(o.status)),
              title: Text(
                'Change Status',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Current: ${_woLabel(o.status)}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'status'),
            ),
            ListTile(
              leading: Icon(
                Ionicons.checkmarkDoneOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Select Multiple',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            ListTile(
              leading: Icon(
                Ionicons.createOutline,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(
                Ionicons.trashOutline,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'status':
        _changeStatus(o);
        break;
      case 'select':
        setState(() {
          _selecting = true;
          _selected.add(o.id);
        });
        break;
      case 'edit':
        _openEdit(context, o);
        break;
      case 'delete':
        final ok = await confirmDialog(
          context,
          'Delete Work Order',
          'Are you sure you want to delete "${o.title}"?',
        );
        if (!ok) return;
        ref.read(appDataProvider.notifier).deleteWorkOrder(o.id);
        _flashSaving();
        break;
    }
  }

  Future<void> _changeStatus(WorkOrder o) async {
    final st = await showAdaptiveModalSheet<String>(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Change Status',
        subtitle: o.title,
        icon: Ionicons.syncOutline,
        iconColor: AppColors.primary,
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          children: [
            for (final s in _woStatuses)
              ListTile(
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _woColor(s),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  _woLabel(s),
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: o.status == s
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
                trailing: o.status == s
                    ? Icon(Icons.check, color: _woColor(s), size: 20)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (st == null) return;
    ref.read(appDataProvider.notifier).upsertWorkOrder(_copyStatus(o, st));
    _flashSaving();
  }

  WorkOrder _copyStatus(WorkOrder o, String status) => o.copyWith(
    status: status,
    completedAt: status == 'completed'
        ? (o.completedAt ?? DateTime.now().toIso8601String())
        : null,
    clearCompletedAt: status != 'completed',
  );

  // ===== details modal =====
  void _details(BuildContext context, WorkOrder o) {
    final s = ref.read(appDataProvider);
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppModalSheet(
        title: 'Work Order Details',
        icon: Icons.construction,
        iconColor: AppColors.accentDark,
        size: SheetSize.standard,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailSection('Basic Information', [
              _detailRow('Title', o.title),
              _detailRow('Category', o.category),
              _detailRow('Description', o.description),
              if (o.unit?.isNotEmpty == true) _detailRow('Unit', o.unit!),
              if (o.assignedTo.isNotEmpty)
                _detailRow('Assigned To', o.assignedTo),
              if (o.dueDate.isNotEmpty) _detailRow('Due Date', o.dueDate),
            ]),
            _detailSection('Status', [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  constraints: const BoxConstraints(minWidth: 80),
                  decoration: BoxDecoration(
                    color: _woColor(o.status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _woLabel(o.status),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ]),
            _timelineSection(o),
            if (o.productPrice != null || o.workerCost != null)
              _detailSection('Financial', [
                if (o.productPrice != null)
                  _detailRow(
                    'Product',
                    fmtMoney(s.selectedCurrency, o.productPrice!),
                  ),
                if (o.workerCost != null)
                  _detailRow(
                    'Worker',
                    fmtMoney(s.selectedCurrency, o.workerCost!),
                  ),
                _detailRow(
                  'Total Actual',
                  fmtMoney(
                    s.selectedCurrency,
                    (o.productPrice ?? 0) + (o.workerCost ?? 0),
                  ),
                  highlight: true,
                ),
              ]),
            if (o.receipt != null && o.receipt!.isNotEmpty)
              _receiptSection(o.receipt!),
          ],
        ),
        footer: SheetActions(
          primaryLabel: 'Edit',
          primaryIcon: const Icon(Icons.edit, size: 16, color: Colors.white),
          onPrimary: () {
            Navigator.pop(ctx);
            _openEdit(context, o);
          },
          cancelLabel: '',
          primaryFlex: 1,
          leadingAction: Expanded(
            child: SizedBox(
              height: 46,
              child: DangerButton(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    'Delete Work Order',
                    'Are you sure you want to delete "${o.title}"?',
                  );
                  if (!ok) return;
                  ref.read(appDataProvider.notifier).deleteWorkOrder(o.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _flashSaving();
                },
                child: const Text('Delete'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.04)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _detailRow(String label, String value, {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: highlight ? 14 : 13,
                color: highlight ? AppColors.primary : AppColors.textSecondary,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: highlight ? 16 : 14,
                  color: highlight ? AppColors.primary : AppColors.text,
                  fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _timelineSection(WorkOrder o) => _detailSection('Timeline', [
    _timelineItem(
      bg: AppColors.primaryLight,
      icon: Icons.create,
      iconColor: AppColors.primary,
      title: 'Work Order Created',
      subtitle: _fullDate(o.createdAt, withTime: true),
    ),
    if (o.dueDate.isNotEmpty)
      _timelineItem(
        bg: AppColors.warningLight,
        icon: Icons.calendar_today,
        iconColor: AppColors.warning,
        title: 'Due Date',
        subtitle: _fullDate(o.dueDate),
      ),
    _timelineItem(
      bg: _timelineStatusBg(o.status),
      icon: _woGlyph(o.status),
      iconColor: _woColor(o.status),
      title: 'Current Status: ${_woLabel(o.status)}',
      subtitle: o.status == 'completed'
          ? 'Work completed on ${_fullDate(o.completedAt ?? o.createdAt)}'
          : o.status == 'in-progress'
          ? 'Work in progress'
          : o.status == 'cancelled'
          ? 'Work cancelled'
          : 'Awaiting start',
    ),
  ]);

  Widget _timelineItem({
    required Color bg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 12, top: 2),
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Color _timelineStatusBg(String s) {
    switch (s) {
      case 'completed':
        return AppColors.successLight;
      case 'cancelled':
        return AppColors.errorLight;
      case 'pending':
      case 'in-progress':
        return AppColors.warningLight;
      default:
        return AppColors.surface;
    }
  }

  String _fullDate(String iso, {bool withTime = false}) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final mon = const [
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
      ][d.month - 1];
      if (!withTime) return '$mon ${d.day}, ${d.year}';
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '$mon ${d.day}, ${d.year}, ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return iso;
    }
  }

  Widget _receiptSection(String path) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receipt',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _image(path, height: 200, width: double.infinity),
              ),
              const SizedBox(height: 8),
              Text(
                'Work Order Receipt',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _image(String path, {double? height, double? width}) {
    final fit = BoxFit.cover;
    if (path.startsWith('http') || path.startsWith('content://')) {
      return Image.network(path, height: height, width: width, fit: fit);
    }
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(f, height: height, width: width, fit: fit);
    }
    return Container(
      height: height,
      width: width,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
    );
  }

  // ===== add / edit launchers =====
  void _openAdd(BuildContext context) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WorkOrderFormSheet(initial: null, isEdit: false),
    );
  }

  void _openEdit(BuildContext context, WorkOrder o) =>
      WorkOrdersView.showEditModal(context, o);
}

/// Small header/amount cell used by the cost table.
class _CostCell extends StatelessWidget {
  final String text;
  final bool header;
  const _CostCell({required this.text, this.header = false});
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: header ? AppColors.text : AppColors.textSecondary,
    ),
  );
}

/// Mutable entry used by the Add modal's multiple mode.
class _WOEntry {
  String title = '';
  String description = '';
  String category = 'General Maintenance';
  String assignedTo = '';
  String? unit;
  String? tenantId;
  String due = DateTime.now().toIso8601String();
  String product = '';
  String worker = '';
  String status = 'pending';
  String? receipt;
}

/// Shared Add / Edit form. Port of AddWorkOrderModal + EditWorkOrderModal.
class _WorkOrderFormSheet extends ConsumerStatefulWidget {
  final WorkOrder? initial;
  final bool isEdit;
  const _WorkOrderFormSheet({required this.initial, this.isEdit = false});
  @override
  ConsumerState<_WorkOrderFormSheet> createState() =>
      _WorkOrderFormSheetState();
}

class _WorkOrderFormSheetState extends ConsumerState<_WorkOrderFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _assign;
  late final TextEditingController _prod;
  late final TextEditingController _worker;
  String _cat = 'General Maintenance';
  String _status = 'pending';
  String? _unit;
  String? _tenantId;
  late DateTime _due;
  String? _receipt;
  bool _showCat = false;
  bool _showUnit = false;
  bool _multi = false;
  int _idx = 0;
  final List<_WOEntry> _list = [];

  @override
  void initState() {
    super.initState();
    final w = widget.initial;
    _title = TextEditingController(text: w?.title ?? '');
    _desc = TextEditingController(text: w?.description ?? '');
    _assign = TextEditingController(text: w?.assignedTo ?? '');
    _prod = TextEditingController(
      text: w?.productPrice != null ? '${w!.productPrice}' : '',
    );
    _worker = TextEditingController(
      text: w?.workerCost != null ? '${w!.workerCost}' : '',
    );
    _cat = w?.category ?? 'General Maintenance';
    _status = w?.status ?? 'pending';
    _unit = w?.unit;
    _tenantId = w?.tenantId;
    _due = _parseDate(w?.dueDate);
    _receipt = w?.receipt;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _assign.dispose();
    _prod.dispose();
    _worker.dispose();
    super.dispose();
  }

  DateTime _parseDate(String? iso) {
    try {
      if (iso != null && iso.isNotEmpty) return DateTime.parse(iso);
    } catch (_) {}
    return DateTime.now();
  }

  bool get _currentValid {
    if (_title.text.trim().isEmpty) return false;
    if (_desc.text.trim().isEmpty) return false;
    if (_cat.isEmpty) return false;
    if (_worker.text.trim().isNotEmpty &&
        double.tryParse(_worker.text.trim()) == null) {
      return false;
    }
    if (_prod.text.trim().isNotEmpty &&
        double.tryParse(_prod.text.trim()) == null) {
      return false;
    }
    return widget.isEdit || _worker.text.trim().isNotEmpty;
  }

  Map<String, List<String>> get _unitOptions {
    final map = <String, List<String>>{};
    for (final t in ref.read(appDataProvider).scopedTenants) {
      if (t.unit.isEmpty) continue;
      map.putIfAbsent(t.unit, () => []).add(t.name);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;
    final isDark = AppColors.isDark;
    return AppModalSheet(
      title: isEdit
          ? 'Edit Work Order'
          : (_multi ? 'Add Multiple Work' : 'Add Work'),
      icon: Icons.construction,
      iconColor: isEdit ? AppColors.primary : AppColors.accentDark,
      headerTrailing: isEdit
          ? null
          : _modeIconToggle(
              multi: _multi,
              isDark: isDark,
              onChanged: (m) => setState(() {
                _multi = m;
                if (_multi && _list.isEmpty) _addEntry();
              }),
            ),
      size: SheetSize.expanded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_form(), if (!isEdit && _multi) _multiPanel()],
      ),
      footer: _footer(),
    );
  }

  // ---- headers ----
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
            tooltip: 'Single work order',
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
            tooltip: 'Multiple work orders',
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

  // ---- form ----
  Widget _form() {
    final unitDrop = _dropdown(
      label: widget.isEdit ? 'Unit (Optional)' : 'Unit',
      display: (_unit == null || _unit!.isEmpty)
          ? 'Select unit (optional)'
          : _unit!,
      open: _showUnit,
      onToggle: () => setState(() => _showUnit = !_showUnit),
      options: [
        _option(
          'No unit',
          () => setState(() {
            _unit = null;
            _tenantId = null;
            _showUnit = false;
            _syncCurrent();
          }),
        ),
        ..._unitOptions.entries.map(
          (e) => _option(
            '${e.key} - ${e.value.join(', ')}',
            () => setState(() {
              _unit = e.key;
              final ts = ref.read(appDataProvider).scopedTenants;
              _tenantId = ts
                  .where((t) => t.unit == e.key)
                  .cast<Tenant?>()
                  .firstOrNull
                  ?.id;
              _showUnit = false;
              _syncCurrent();
            }),
          ),
        ),
      ],
    );
    final assignTo = _field(
      'Assigned To',
      _assign,
      hint: widget.isEdit
          ? 'Enter assigned person'
          : 'Enter assigned person/contractor',
    );
    final dueDate = _dateField(
      'Due Date',
      _due,
      (d) => setState(() {
        _due = d;
        _syncCurrent();
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _sectionTitle('Basic Information'),
        _field('Title', _title, required: true, hint: 'Enter work order title'),
        _field(
          'Description',
          _desc,
          required: true,
          multiline: true,
          hint: 'Enter detailed description',
        ),
        _dropdown(
          label: 'Category',
          required: true,
          display: _cat,
          open: _showCat,
          onToggle: () => setState(() => _showCat = !_showCat),
          options: kWorkOrderCategories
              .map(
                (c) => _option(
                  c,
                  () => setState(() {
                    _cat = c;
                    _showCat = false;
                    _syncCurrent();
                  }),
                ),
              )
              .toList(),
        ),
        if (widget.isEdit) ...[
          unitDrop,
          _sectionTitle('Assignment'),
          assignTo,
        ] else ...[
          assignTo,
          unitDrop,
        ],
        dueDate,
        _sectionTitle('Status'),
        _statusRow(),
        _sectionTitle('Financial'),
        _field(
          'Product Price (Optional)',
          _prod,
          keyboard: TextInputType.number,
          hint: 'Enter product/material cost',
        ),
        _field(
          'Worker Cost',
          _worker,
          required: true,
          keyboard: TextInputType.number,
          hint: 'Enter labor cost',
        ),
        _sectionTitle('Receipt (Optional)'),
        _receiptField(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: 0.2,
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c, {
    bool required = false,
    bool multiline = false,
    TextInputType? keyboard,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: multiline ? 3 : 1,
          onChanged: (_) => setState(_syncCurrent),
          style: TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint ?? label,
            hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      ],
    ),
  );

  Widget _dropdown({
    required String label,
    required String display,
    required bool open,
    required VoidCallback onToggle,
    required List<Widget> options,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    display,
                    style: TextStyle(color: AppColors.text, fontSize: 14),
                  ),
                ),
                Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(child: Column(children: options)),
          ),
      ],
    ),
  );

  Widget _option(String text, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(text, style: TextStyle(color: AppColors.text, fontSize: 14)),
    ),
  );

  Widget _dateField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final d = await pickAppDate(context, initial: value);
            if (d != null) onChanged(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                  style: TextStyle(color: AppColors.text, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statusRow() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final st
                in (widget.isEdit ? _woStatuses : _woStatuses.take(3)))
              GestureDetector(
                onTap: () => setState(() {
                  _status = st;
                  if (st == 'completed') {
                    // Expo sets dueDate to today when completed without one.
                  }
                  _syncCurrent();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _status == st
                        ? AppColors.primary
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _status == st
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _woLabel(st),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _status == st
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _receiptField() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload Receipt',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (_receipt != null && _receipt!.isNotEmpty)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _image(_receipt!, height: 160, width: double.infinity),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _receipt = null;
                    _syncCurrent();
                  }),
                  child: const Icon(
                    Icons.cancel,
                    size: 24,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: () async {
              final p = await MediaPicker.pickImage(context);
              if (p != null) {
                setState(() {
                  _receipt = p;
                  _syncCurrent();
                });
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: const [
                  Icon(Icons.camera_alt, size: 24, color: AppColors.primary),
                  SizedBox(height: 8),
                  Text(
                    'Upload Receipt',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  // ---- multiple-mode panel ----
  Widget _multiPanel() => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Work Order List',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(_addEntry),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Start adding work order entries\nBegin filling the form above to automatically create your first work order entry',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < _list.length; i++) _multiTile(i),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _multiTile(int i) {
    final e = _list[i];
    final total =
        (double.tryParse(e.product.isEmpty ? '0' : e.product) ?? 0) +
        (double.tryParse(e.worker.isEmpty ? '0' : e.worker) ?? 0);
    final active = i == _idx;
    return GestureDetector(
      onTap: () => setState(() => _loadIndex(i)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
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
                          e.title.isEmpty ? 'No title' : e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Category: ${e.category.isEmpty ? 'N/A' : e.category}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _woColor(e.status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _woLabel(e.status),
                          style: TextStyle(
                            fontSize: 10,
                            color: _woColor(e.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_list.length > 1)
              GestureDetector(
                onTap: () => setState(() => _removeEntry(i)),
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.delete, size: 16, color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    if (_multi) _syncCurrent();
    _list.add(_WOEntry());
    _idx = _list.length - 1;
    _loadIndex(_idx);
  }

  void _removeEntry(int i) {
    _list.removeAt(i);
    if (_idx >= _list.length) _idx = _list.length - 1;
    if (_idx < 0) _idx = 0;
    if (_list.isNotEmpty) _loadIndex(_idx);
  }

  void _loadIndex(int i) {
    final e = _list[i];
    _idx = i;
    _title.text = e.title;
    _desc.text = e.description;
    _assign.text = e.assignedTo;
    _prod.text = e.product;
    _worker.text = e.worker;
    _cat = e.category;
    _status = e.status;
    _unit = e.unit;
    _tenantId = e.tenantId;
    _due = _parseDate(e.due);
    _receipt = e.receipt;
  }

  void _syncCurrent() {
    if (!_multi || _list.isEmpty) return;
    final e = _list[_idx];
    e.title = _title.text;
    e.description = _desc.text;
    e.category = _cat;
    e.assignedTo = _assign.text;
    e.unit = _unit;
    e.tenantId = _tenantId;
    e.due = _due.toIso8601String();
    e.product = _prod.text;
    e.worker = _worker.text;
    e.status = _status;
    e.receipt = _receipt;
  }

  // ---- footer ----
  Widget _footer() {
    final valid = _currentValid;
    final saveLabel = widget.isEdit
        ? 'Save Changes'
        : (_multi
              ? (_list.isEmpty
                    ? 'Add Work Order'
                    : 'Save ${_list.length} ${_list.length == 1 ? "Entry" : "Entries"}')
              : 'Add Work Order');
    return SheetActions(
      primaryLabel: saveLabel,
      onPrimary: valid ? _save : null,
      primaryIcon: Icon(
        widget.isEdit ? Icons.check_circle_outline : Icons.add_circle_outline,
        size: 16,
        color: Colors.white,
      ),
      onCancel: () => Navigator.pop(context),
    );
  }

  void _save() {
    if (widget.isEdit) {
      final w = widget.initial!;
      ref
          .read(appDataProvider.notifier)
          .upsertWorkOrder(
            WorkOrder(
              id: w.id,
              title: _title.text.trim(),
              description: _desc.text.trim(),
              status: _status,
              category: _cat,
              assignedTo: _assign.text.trim().isEmpty
                  ? 'Unassigned'
                  : _assign.text.trim(),
              createdAt: w.createdAt,
              dueDate: _due.toIso8601String(),
              unit: _unit,
              productPrice: double.tryParse(_prod.text),
              workerCost: double.tryParse(_worker.text),
              receipt: _receipt,
              tenantId: _tenantId,
              priority: w.priority,
              completedAt: _status == 'completed'
                  ? (w.completedAt ?? DateTime.now().toIso8601String())
                  : null,
            ),
          );
      Navigator.pop(context);
      return;
    }

    final notifier = ref.read(appDataProvider.notifier);
    if (_multi) {
      _syncCurrent();
      final valid = _list.where(
        (e) =>
            e.title.trim().isNotEmpty &&
            e.description.trim().isNotEmpty &&
            e.category.isNotEmpty &&
            e.worker.trim().isNotEmpty,
      );
      for (var i = 0; i < valid.length; i++) {
        final e = valid.elementAt(i);
        notifier.upsertWorkOrder(_entryToWorkOrder(e, '${newId()}_$i'));
      }
    } else {
      notifier.upsertWorkOrder(_entryToWorkOrder(_currentEntry(), newId()));
    }
    Navigator.pop(context);
  }

  _WOEntry _currentEntry() => _WOEntry()
    ..title = _title.text.trim()
    ..description = _desc.text.trim()
    ..category = _cat
    ..assignedTo = _assign.text.trim()
    ..unit = _unit
    ..tenantId = _tenantId
    ..due = _due.toIso8601String()
    ..product = _prod.text
    ..worker = _worker.text
    ..status = _status
    ..receipt = _receipt;

  WorkOrder _entryToWorkOrder(_WOEntry e, String id) => WorkOrder(
    id: id,
    title: e.title.trim(),
    description: e.description.trim(),
    status: e.status,
    category: e.category,
    assignedTo: e.assignedTo.trim().isEmpty
        ? 'Unassigned'
        : e.assignedTo.trim(),
    createdAt: DateTime.now().toIso8601String(),
    dueDate: e.due,
    unit: (e.unit == null || e.unit!.isEmpty) ? null : e.unit,
    productPrice: double.tryParse(e.product),
    workerCost: double.tryParse(e.worker),
    receipt: e.receipt,
    tenantId: e.tenantId,
    completedAt: e.status == 'completed'
        ? DateTime.now().toIso8601String()
        : null,
  );

  Widget _image(String path, {double? height, double? width}) {
    if (path.startsWith('http') || path.startsWith('content://')) {
      return Image.network(
        path,
        height: height,
        width: width,
        fit: BoxFit.cover,
      );
    }
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(f, height: height, width: width, fit: BoxFit.cover);
    }
    return Container(
      height: height,
      width: width,
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
    );
  }
}
