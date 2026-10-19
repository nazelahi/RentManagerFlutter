import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';

/// 2-Column Master-Detail Split View for Work Orders on macOS Desktop.
class DesktopWorkOrdersView extends ConsumerStatefulWidget {
  final VoidCallback onAddOrder;
  final void Function(WorkOrder order)? onEditOrder;
  final void Function(WorkOrder order)? onSelectOrder;
  final void Function(WorkOrder order)? onDeleteOrder;

  const DesktopWorkOrdersView({
    super.key,
    required this.onAddOrder,
    this.onEditOrder,
    this.onSelectOrder,
    this.onDeleteOrder,
  });

  @override
  ConsumerState<DesktopWorkOrdersView> createState() =>
      _DesktopWorkOrdersViewState();
}

class _DesktopWorkOrdersViewState extends ConsumerState<DesktopWorkOrdersView> {
  String? _selectedOrderId;
  String _searchQuery = '';
  late final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'all'; // 'all' | 'pending' | 'in-progress' | 'completed' | 'cancelled'
  late int _selectedYear = DateTime.now().year;
  bool _isKanbanView = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Status visual attributes
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return const Color(0xFF10B981);
      case 'in-progress':
        return const Color(0xFF3B82F6);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF10B981);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Ionicons.checkmarkCircle;
      case 'in-progress':
        return Ionicons.playCircle;
      case 'cancelled':
        return Ionicons.closeCircle;
      default:
        return Ionicons.timeOutline;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'in-progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  void _changeStatus(WorkOrder o, String newStatus) {
    final updated = WorkOrder(
      id: o.id,
      title: o.title,
      description: o.description,
      status: newStatus,
      category: o.category,
      assignedTo: o.assignedTo,
      createdAt: o.createdAt,
      dueDate: o.dueDate,
      unit: o.unit,
      productPrice: o.productPrice,
      workerCost: o.workerCost,
      receipt: o.receipt,
      tenantId: o.tenantId,
      priority: o.priority,
      completedAt: newStatus == 'completed'
          ? (o.completedAt ?? DateTime.now().toIso8601String())
          : null,
    );
    ref.read(appDataProvider.notifier).upsertWorkOrder(updated);
    showAppToast(
      context,
      'Status updated to ${_statusLabel(newStatus)}',
      isSuccess: true,
    );
  }

  void _confirmDelete(WorkOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.isDark
            ? const Color(0xFF0F2627)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Work Order?'),
        content: Text(
          'Are you sure you want to delete "${order.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (widget.onDeleteOrder != null) {
                widget.onDeleteOrder!(order);
              } else {
                ref.read(appDataProvider.notifier).deleteWorkOrder(order.id);
              }
              if (_selectedOrderId == order.id) {
                setState(() => _selectedOrderId = null);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _contextMenuItem({
    required IconData icon,
    required String label,
    bool isDestructive = false,
    required bool isDark,
    Color? colorOverride,
  }) {
    final color = colorOverride ??
        (isDestructive
            ? const Color(0xFFEF4444)
            : (AppColors.heading));
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

  Future<void> _showWorkOrderContextMenu(
      BuildContext context, Offset position, WorkOrder order) async {
    setState(() => _selectedOrderId = order.id);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;
    final st = order.status.toLowerCase();

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
        if (st != 'in-progress')
          PopupMenuItem(
            value: 'status_in_progress',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.playCircleOutline,
              label: 'Mark In Progress',
              isDark: isDark,
              colorOverride: const Color(0xFF3B82F6),
            ),
          ),
        if (st != 'completed')
          PopupMenuItem(
            value: 'status_completed',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.checkmarkCircleOutline,
              label: 'Mark Completed',
              isDark: isDark,
              colorOverride: const Color(0xFF10B981),
            ),
          ),
        if (st != 'pending')
          PopupMenuItem(
            value: 'status_pending',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.timeOutline,
              label: 'Mark Pending',
              isDark: isDark,
              colorOverride: const Color(0xFFF59E0B),
            ),
          ),
        if (widget.onEditOrder != null) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Work Order',
              isDark: isDark,
            ),
          ),
        ],
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.trashOutline,
            label: 'Delete Work Order',
            isDestructive: true,
            isDark: isDark,
          ),
        ),
      ],
    );

    if (!mounted || item == null) return;

    if (item == 'status_in_progress') {
      _changeStatus(order, 'in-progress');
    } else if (item == 'status_completed') {
      _changeStatus(order, 'completed');
    } else if (item == 'status_pending') {
      _changeStatus(order, 'pending');
    } else if (item == 'edit') {
      widget.onEditOrder?.call(order);
    } else if (item == 'delete') {
      _confirmDelete(order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final cur = s.selectedCurrency;

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    // Filter work orders
    final allOrders = s.scopedWorkOrders;
    final filtered = allOrders.where((o) {
      // Year filter
      final y = DateTime.tryParse(o.createdAt)?.year;
      if (y != null && y != _selectedYear) return false;

      // Status filter
      if (_filterStatus != 'all' &&
          o.status.toLowerCase() != _filterStatus.toLowerCase()) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesTitle = o.title.toLowerCase().contains(q);
        final matchesDesc = o.description.toLowerCase().contains(q);
        final matchesCat = o.category.toLowerCase().contains(q);
        final matchesAssignee = o.assignedTo.toLowerCase().contains(q);
        final matchesUnit = o.unit?.toLowerCase().contains(q) ?? false;
        if (!matchesTitle &&
            !matchesDesc &&
            !matchesCat &&
            !matchesAssignee &&
            !matchesUnit) {
          return false;
        }
      }
      return true;
    }).toList();

    // Default select first item if none selected
    if (_selectedOrderId == null && filtered.isNotEmpty) {
      _selectedOrderId = filtered.first.id;
    }

    final selectedOrder = s.scopedWorkOrders
        .where((o) => o.id == _selectedOrderId)
        .firstOrNull;

    if (_isKanbanView) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildKanbanLayout(filtered, allOrders, s, cur, isDark, borderColor),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final listWidth = constraints.maxWidth < 800
              ? 270.0
              : (constraints.maxWidth < 1050 ? 295.0 : 320.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. LEFT PANEL: Master List (Compact)
              Container(
                width: listWidth,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF061819).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.6),
                  border: Border(
                    right: BorderSide(color: borderColor, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    // Top Header with Title, Year Selector & View Switcher
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Work Orders',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${filtered.length}',
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildViewSwitcher(isDark, borderColor),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Action row: Search & New Order Button
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0D2526)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Ionicons.searchOutline,
                                        size: 15,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          onChanged: (v) =>
                                              setState(() => _searchQuery = v.trim()),
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.heading,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: 'Search title, unit, vendor...',
                                            hintStyle: TextStyle(
                                              fontSize: 12,
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
                                      if (_searchQuery.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 6),
                                            child: Icon(
                                              Ionicons.closeCircle,
                                              size: 14,
                                              color: isDark
                                                  ? const Color(0xFF64748B)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'Add Work Order',
                                waitDuration: const Duration(milliseconds: 350),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: widget.onAddOrder,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF0F766E), Color(0xFF059669)],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF059669).withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Ionicons.add,
                                          size: 17, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Filter Tabs Row & Year Selector
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Container(
                                  height: 24,
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0D2526)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Ionicons.chevronBack, size: 10),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                        tooltip: 'Previous Year',
                                        onPressed: () => setState(() => _selectedYear--),
                                      ),
                                      Text(
                                        '$_selectedYear',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.heading,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Ionicons.chevronForward, size: 10),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                        tooltip: 'Next Year',
                                        onPressed: () => setState(() => _selectedYear++),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                _buildFilterTab('all', 'All', allOrders.length, isDark),
                                const SizedBox(width: 4),
                                _buildFilterTab(
                                    'pending',
                                    'Pending',
                                    allOrders.where((o) => o.status == 'pending').length,
                                    isDark,
                                    color: const Color(0xFFF59E0B)),
                                const SizedBox(width: 4),
                                _buildFilterTab(
                                    'in-progress',
                                    'In Progress',
                                    allOrders.where((o) => o.status == 'in-progress').length,
                                    isDark,
                                    color: const Color(0xFF3B82F6)),
                                const SizedBox(width: 4),
                                _buildFilterTab(
                                    'completed',
                                    'Done',
                                    allOrders.where((o) => o.status == 'completed').length,
                                    isDark,
                                    color: const Color(0xFF10B981)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),
                    // Work Orders Master List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Ionicons.constructOutline,
                                    size: 32,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'No work orders found',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              itemCount: filtered.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 3),
                              itemBuilder: (context, i) {
                                final o = filtered[i];
                                final isSelected = o.id == _selectedOrderId;
                                final totalCost =
                                    (o.productPrice ?? 0) + (o.workerCost ?? 0);
                                final stColor = _statusColor(o.status);

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _selectedOrderId = o.id);
                                    },
                                    onSecondaryTapDown: (details) =>
                                        _showWorkOrderContextMenu(
                                            context, details.globalPosition, o),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? (isDark
                                                ? const Color(0xFF132B2B)
                                                : const Color(0xFFEDF7F4))
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: isSelected
                                            ? Border.all(
                                                color: const Color(0xFF10B981)
                                                    .withValues(alpha: 0.5),
                                                width: 1,
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Status icon indicator
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Icon(
                                              _statusIcon(o.status),
                                              size: 14,
                                              color: stColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Main info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        o.title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: isDark
                                                              ? Colors.white
                                                              : const Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                    ),
                                                    if (totalCost > 0)
                                                      Text(
                                                        '$cur ${totalCost.toStringAsFixed(0)}',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: isDark
                                                              ? const Color(0xFF34D399)
                                                              : const Color(0xFF059669),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    if (o.unit != null &&
                                                        o.unit!.isNotEmpty) ...[
                                                      Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 5,
                                                            vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF10B981)
                                                              .withValues(alpha: 0.14),
                                                          borderRadius:
                                                              BorderRadius.circular(3),
                                                        ),
                                                        child: Text(
                                                          o.unit!,
                                                          style: const TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(0xFF10B981),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 5),
                                                    ],
                                                    Expanded(
                                                      child: Text(
                                                        o.assignedTo.isNotEmpty
                                                            ? o.assignedTo
                                                            : o.category,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          color: isDark
                                                              ? const Color(0xFF94A3B8)
                                                              : const Color(0xFF64748B),
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      _formatShortDate(o.createdAt),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: isDark
                                                            ? const Color(0xFF64748B)
                                                            : const Color(0xFF94A3B8),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              // 2. RIGHT PANEL: Detail Inspector (Compact)
              Expanded(
                child: selectedOrder == null
                    ? _buildEmptyState(isDark)
                    : Container(
                        alignment: Alignment.topLeft,
                        child: _buildDetailPane(
                            context, selectedOrder, s, cur, isDark, borderColor),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewSwitcher(bool isDark, Color borderColor) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2526) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switcherButton(
            label: 'List',
            icon: Ionicons.listOutline,
            isSelected: !_isKanbanView,
            isDark: isDark,
            onTap: () => setState(() => _isKanbanView = false),
          ),
          _switcherButton(
            label: 'Kanban',
            icon: Ionicons.gridOutline,
            isSelected: _isKanbanView,
            isDark: isDark,
            onTap: () => setState(() => _isKanbanView = true),
          ),
        ],
      ),
    );
  }

  Widget _switcherButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF0F766E) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 13,
            color: isSelected
                ? Colors.white
                : (isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanLayout(
    List<WorkOrder> filtered,
    List<WorkOrder> allOrders,
    AppDataState s,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    final pendingOrders =
        filtered.where((o) => o.status.toLowerCase() == 'pending').toList();
    final inProgressOrders =
        filtered.where((o) => o.status.toLowerCase() == 'in-progress').toList();
    final completedOrders =
        filtered.where((o) => o.status.toLowerCase() == 'completed').toList();
    final cancelledOrders =
        filtered.where((o) => o.status.toLowerCase() == 'cancelled').toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Control Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF061819).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                // Title and badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Work Orders Kanban',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${filtered.length} total',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                // View switcher
                _buildViewSwitcher(isDark, borderColor),
                const SizedBox(width: 14),
                // Year selector
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D2526)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Ionicons.chevronBack, size: 12),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 20, minHeight: 20),
                        tooltip: 'Previous Year',
                        onPressed: () => setState(() => _selectedYear--),
                      ),
                      Text(
                        '$_selectedYear',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Ionicons.chevronForward, size: 12),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 20, minHeight: 20),
                        tooltip: 'Next Year',
                        onPressed: () => setState(() => _selectedYear++),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Search Input
                Expanded(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0D2526)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Ionicons.searchOutline,
                            size: 14,
                            color: isDark ? Colors.white38 : Colors.black38),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search tickets by title, unit, vendor...',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) =>
                                setState(() => _searchQuery = val.trim()),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Icon(Ionicons.closeCircle, size: 14),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Add ticket button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onAddOrder,
                  icon: const Icon(Ionicons.add, size: 15),
                  label: const Text(
                    'New Order',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 4 Kanban Columns
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool useHorizontalScroll = constraints.maxWidth < 1080;
                final double columnWidth =
                    useHorizontalScroll ? 265.0 : (constraints.maxWidth - 36) / 4;

                final columns = [
                  _buildKanbanColumn(
                    statusKey: 'pending',
                    title: 'Pending',
                    color: const Color(0xFFF59E0B),
                    icon: Ionicons.timeOutline,
                    orders: pendingOrders,
                    width: columnWidth,
                    s: s,
                    cur: cur,
                    isDark: isDark,
                    borderColor: borderColor,
                  ),
                  _buildKanbanColumn(
                    statusKey: 'in-progress',
                    title: 'In Progress',
                    color: const Color(0xFF3B82F6),
                    icon: Ionicons.playOutline,
                    orders: inProgressOrders,
                    width: columnWidth,
                    s: s,
                    cur: cur,
                    isDark: isDark,
                    borderColor: borderColor,
                  ),
                  _buildKanbanColumn(
                    statusKey: 'completed',
                    title: 'Completed',
                    color: const Color(0xFF10B981),
                    icon: Ionicons.checkmarkCircleOutline,
                    orders: completedOrders,
                    width: columnWidth,
                    s: s,
                    cur: cur,
                    isDark: isDark,
                    borderColor: borderColor,
                  ),
                  _buildKanbanColumn(
                    statusKey: 'cancelled',
                    title: 'Cancelled',
                    color: const Color(0xFF94A3B8),
                    icon: Ionicons.closeCircleOutline,
                    orders: cancelledOrders,
                    width: columnWidth,
                    s: s,
                    cur: cur,
                    isDark: isDark,
                    borderColor: borderColor,
                  ),
                ];

                if (useHorizontalScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < columns.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          columns[i],
                        ],
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: columns[i]),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanColumn({
    required String statusKey,
    required String title,
    required Color color,
    required IconData icon,
    required List<WorkOrder> orders,
    required double width,
    required AppDataState s,
    required String cur,
    required bool isDark,
    required Color borderColor,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF071F20).withValues(alpha: 0.6)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Ionicons.add, size: 15),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Add Ticket to $title',
                  onPressed: widget.onAddOrder,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          // Drag Target / List
          Expanded(
            child: DragTarget<WorkOrder>(
              onWillAcceptWithDetails: (details) =>
                  details.data.status.toLowerCase() != statusKey.toLowerCase(),
              onAcceptWithDetails: (details) {
                _changeStatus(details.data, statusKey);
              },
              builder: (context, candidateData, rejectedData) {
                final isHovered = candidateData.isNotEmpty;
                return Container(
                  decoration: BoxDecoration(
                    color: isHovered
                        ? color.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                    border: isHovered
                        ? Border.all(color: color, width: 2)
                        : null,
                  ),
                  child: orders.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No $title tickets',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: orders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            return _buildKanbanCard(
                              order: order,
                              s: s,
                              cur: cur,
                              isDark: isDark,
                              borderColor: borderColor,
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanCard({
    required WorkOrder order,
    required AppDataState s,
    required String cur,
    required bool isDark,
    required Color borderColor,
  }) {
    final totalCost = (order.productPrice ?? 0.0) + (order.workerCost ?? 0.0);
    final stColor = _statusColor(order.status);

    return Draggable<WorkOrder>(
      data: order,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        color: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F2627) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            order.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _kanbanCardBody(
            order, totalCost, stColor, s, cur, isDark, borderColor),
      ),
      child: _kanbanCardBody(
          order, totalCost, stColor, s, cur, isDark, borderColor),
    );
  }

  Widget _kanbanCardBody(
    WorkOrder order,
    double totalCost,
    Color stColor,
    AppDataState s,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    final status = order.status.toLowerCase();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D2526) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor:
              isDark ? const Color(0xFF133638) : const Color(0xFFF1F5F9),
          onTap: () {
            _showOrderDetailsDialog(
                context, order, s, cur, isDark, borderColor);
          },
          onSecondaryTapDown: (details) {
            _showWorkOrderContextMenu(context, details.globalPosition, order);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Priority & Unit
                Row(
                  children: [
                    if (order.priority != null && order.priority!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _priorityColor(order.priority!)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.priority!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _priorityColor(order.priority!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    if (order.unit != null && order.unit!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.unit!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTapDown: (details) {
                        _showWorkOrderContextMenu(
                            context, details.globalPosition, order);
                      },
                      child: Icon(
                        Ionicons.ellipsisHorizontal,
                        size: 14,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Title
                Text(
                  order.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                    height: 1.25,
                  ),
                ),
                if (order.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    order.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                      height: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Assignee & Cost row
                Row(
                  children: [
                    Icon(
                      Ionicons.personOutline,
                      size: 11,
                      color: isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.assignedTo.isNotEmpty
                            ? order.assignedTo
                            : (order.category.isNotEmpty
                                ? order.category
                                : 'Unassigned'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    if (totalCost > 0) ...[
                      Text(
                        '$cur ${totalCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _formatShortDate(order.createdAt),
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Quick progression action bar
                Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white10
                        : const Color(0xFFF1F5F9)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'pending') ...[
                      _quickMoveButton(
                        label: 'Start Work →',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _changeStatus(order, 'in-progress'),
                      ),
                    ] else if (status == 'in-progress') ...[
                      _quickMoveButton(
                        label: '✕ Cancel',
                        color: const Color(0xFF94A3B8),
                        onTap: () => _changeStatus(order, 'cancelled'),
                      ),
                      const SizedBox(width: 6),
                      _quickMoveButton(
                        label: '✓ Done',
                        color: const Color(0xFF10B981),
                        onTap: () => _changeStatus(order, 'completed'),
                      ),
                    ] else if (status == 'completed') ...[
                      _quickMoveButton(
                        label: '↺ Reopen',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _changeStatus(order, 'in-progress'),
                      ),
                    ] else if (status == 'cancelled') ...[
                      _quickMoveButton(
                        label: '↺ Restore',
                        color: const Color(0xFFF59E0B),
                        onTap: () => _changeStatus(order, 'pending'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickMoveButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  void _showOrderDetailsDialog(
    BuildContext context,
    WorkOrder order,
    AppDataState s,
    String cur,
    bool isDark,
    Color borderColor,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF081F20) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    Text(
                      'Work Order Inspector',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedOrderId = order.id;
                          _isKanbanView = false;
                        });
                      },
                      icon: const Icon(Ionicons.listOutline, size: 14),
                      label: const Text('Open in Split View',
                          style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Ionicons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child:
                    _buildDetailPane(ctx, order, s, cur, isDark, borderColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String key, String label, int count, bool isDark,
      {Color? color}) {
    final isSelected = _filterStatus == key;
    final activeColor = color ?? const Color(0xFF10B981);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _filterStatus = key),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.2 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? activeColor
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? activeColor
                      : (isDark
                          ? const Color(0xFF64748B)
                          : const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF132B2B).withValues(alpha: 0.5)
                  : const Color(0xFFEDF7F4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Ionicons.constructOutline,
              size: 38,
              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a Work Order',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a work order from the list or create a new maintenance request',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: widget.onAddOrder,
            icon: const Icon(Ionicons.add, size: 16),
            label: const Text(
              'Add Work Order',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context, WorkOrder o, AppDataState s,
      String cur, bool isDark, Color borderColor) {
    final tenant = o.tenantId != null
        ? s.tenants.where((t) => t.id == o.tenantId).firstOrNull
        : null;

    final totalCost = (o.productPrice ?? 0) + (o.workerCost ?? 0);
    final stColor = _statusColor(o.status);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        // 1. TOP HEADER & QUICK ACTIONS (Compact Bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF091E1F) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final isNarrow = constraints.maxWidth < 650;

                final headerInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Status pill with dropdown
                        PopupMenuButton<String>(
                          tooltip: 'Change Status',
                          onSelected: (st) => _changeStatus(o, st),
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'pending',
                              child: Row(
                                children: [
                                  Icon(Ionicons.timeOutline, size: 15, color: Color(0xFFF59E0B)),
                                  SizedBox(width: 8),
                                  Text('Pending', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'in-progress',
                              child: Row(
                                children: [
                                  Icon(Ionicons.playCircle, size: 15, color: Color(0xFF3B82F6)),
                                  SizedBox(width: 8),
                                  Text('In Progress', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'completed',
                              child: Row(
                                children: [
                                  Icon(Ionicons.checkmarkCircle, size: 15, color: Color(0xFF10B981)),
                                  SizedBox(width: 8),
                                  Text('Completed', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'cancelled',
                              child: Row(
                                children: [
                                  Icon(Ionicons.closeCircle, size: 15, color: Color(0xFF94A3B8)),
                                  SizedBox(width: 8),
                                  Text('Cancelled', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: stColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: stColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon(o.status), size: 13, color: stColor),
                                const SizedBox(width: 5),
                                Text(
                                  _statusLabel(o.status).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: stColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Ionicons.chevronDown, size: 11, color: stColor),
                              ],
                            ),
                          ),
                        ),
                        if (o.priority != null && o.priority!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: _priorityColor(o.priority!).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              o.priority!.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: _priorityColor(o.priority!),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          'Created ${_formatShortDate(o.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      o.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.heading,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                );

                final headerActions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onEditOrder?.call(o),
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color.fromRGBO(255, 255, 255, 0.06)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.pencilOutline,
                                  size: 15, color: AppColors.heading),
                              const SizedBox(width: 6),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.heading,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onSelectOrder?.call(o),
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4)
                                .withValues(alpha: isDark ? 0.14 : 0.08),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: const Color(0xFF06B6D4)
                                  .withValues(alpha: isDark ? 0.28 : 0.22),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.eyeOutline,
                                  size: 15, color: Color(0xFF06B6D4)),
                              SizedBox(width: 6),
                              Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF06B6D4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Delete Work Order',
                      waitDuration: const Duration(milliseconds: 350),
                      child: InkWell(
                        onTap: () => _confirmDelete(o),
                        borderRadius: BorderRadius.circular(9),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444)
                                .withValues(alpha: isDark ? 0.14 : 0.08),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: isDark ? 0.28 : 0.22),
                            ),
                          ),
                          child: const Center(
                            child: Icon(Ionicons.trashOutline,
                                size: 15, color: Color(0xFFEF4444)),
                          ),
                        ),
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerInfo,
                      const SizedBox(height: 8),
                      headerActions,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: headerInfo),
                    const SizedBox(width: 12),
                    headerActions,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // 2. INTERACTIVE PROGRESS STEPPER
          _buildProgressStepper(o, isDark, borderColor),
          const SizedBox(height: 10),

          // 3. FINANCIAL / COST SUMMARY BENTO (3 Compact Cards)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Parts & Materials',
                  '$cur ${(o.productPrice ?? 0).toStringAsFixed(0)}',
                  Ionicons.cubeOutline,
                  const Color(0xFF3B82F6),
                  isDark,
                  borderColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Labor / Contractor',
                  '$cur ${(o.workerCost ?? 0).toStringAsFixed(0)}',
                  Ionicons.hammerOutline,
                  const Color(0xFF8B5CF6),
                  isDark,
                  borderColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Total Cost',
                  '$cur ${totalCost.toStringAsFixed(0)}',
                  Ionicons.walletOutline,
                  const Color(0xFF10B981),
                  isDark,
                  borderColor,
                  isPrimary: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 4. DISPATCH & NOTIFICATION QUICK-BAR
          _buildDispatchQuickBar(o, tenant, totalCost, cur, isDark, borderColor),
          const SizedBox(height: 10),

          // 5. LOCATION & ASSIGNMENT DETAILS (Compact Micro-Grid)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF091E1F) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Ionicons.informationCircleOutline, size: 15, color: Color(0xFF10B981)),
                    const SizedBox(width: 7),
                    Text(
                      'Assignment & Location Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width >= 600 ? 4 : (width >= 340 ? 2 : 1);

                    final items = [
                      _buildCompactDetailItem(
                        icon: Ionicons.businessOutline,
                        iconColor: const Color(0xFF10B981),
                        label: 'Unit / Tenant',
                        value: o.unit != null && o.unit!.isNotEmpty ? '${o.unit!} ${tenant != null ? "(${tenant.name})" : ""}' : '—',
                        isDark: isDark,
                        subColor: subColor,
                      ),
                      _buildCompactDetailItem(
                        icon: Ionicons.pricetagOutline,
                        iconColor: const Color(0xFF3B82F6),
                        label: 'Category',
                        value: o.category.isNotEmpty ? o.category : 'General',
                        isDark: isDark,
                        subColor: subColor,
                      ),
                      _buildCompactDetailItem(
                        icon: Ionicons.personOutline,
                        iconColor: const Color(0xFF8B5CF6),
                        label: 'Assigned To',
                        value: o.assignedTo.isNotEmpty ? o.assignedTo : 'Unassigned',
                        isDark: isDark,
                        subColor: subColor,
                      ),
                      _buildCompactDetailItem(
                        icon: Ionicons.calendarOutline,
                        iconColor: const Color(0xFFF59E0B),
                        label: 'Due Date',
                        value: o.dueDate.isNotEmpty ? o.dueDate : (o.completedAt != null ? 'Done: ${_formatShortDate(o.completedAt!)}' : '—'),
                        isDark: isDark,
                        subColor: subColor,
                      ),
                    ];

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 32,
                      ),
                      itemBuilder: (context, index) => items[index],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 6. WORK DESCRIPTION & SCOPE (Compact)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF091E1F) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Ionicons.documentTextOutline, size: 15, color: Color(0xFF06B6D4)),
                    const SizedBox(width: 7),
                    Text(
                      'Work Description & Scope',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  o.description.isNotEmpty
                      ? o.description
                      : 'No detailed description provided for this work order.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 7. ATTACHMENTS & REPAIR PHOTOS DROPZONE
          _buildAttachmentsSection(o, isDark, borderColor),
      ],
    );
  }

  Widget _buildProgressStepper(WorkOrder o, bool isDark, Color borderColor) {
    final status = o.status.toLowerCase();
    final stages = [
      {
        'key': 'pending',
        'label': '1. Logged',
        'icon': Ionicons.timeOutline,
        'color': const Color(0xFFF59E0B)
      },
      {
        'key': 'in-progress',
        'label': '2. In Progress',
        'icon': Ionicons.playOutline,
        'color': const Color(0xFF3B82F6)
      },
      {
        'key': 'completed',
        'label': '3. Completed',
        'icon': Ionicons.checkmarkCircleOutline,
        'color': const Color(0xFF10B981)
      },
    ];

    final isCancelled = status == 'cancelled';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'WORKFLOW PIPELINE',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              if (isCancelled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF94A3B8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CANCELLED',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < stages.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                Expanded(
                  flex: 3,
                  child: _buildStageButton(
                    stageKey: stages[i]['key'] as String,
                    label: stages[i]['label'] as String,
                    icon: stages[i]['icon'] as IconData,
                    color: stages[i]['color'] as Color,
                    isActive: status == stages[i]['key'],
                    isDark: isDark,
                    onTap: () => _changeStatus(o, stages[i]['key'] as String),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageButton({
    required String stageKey,
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: isDark ? 0.22 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.5) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: isActive
                  ? color
                  : (isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? (isDark ? Colors.white : color)
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

  Widget _buildDispatchQuickBar(WorkOrder o, Tenant? tenant, double totalCost,
      String cur, bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Ionicons.paperPlaneOutline,
                    size: 12, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 6),
              Text(
                'Dispatch & Notify',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Notify Tenant
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              side: BorderSide(
                  color: const Color(0xFF10B981).withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Ionicons.chatbubbleEllipsesOutline, size: 12),
            label: const Text('Notify Tenant',
                style:
                    TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            onPressed: () {
              final tenantName = tenant?.name ?? 'Tenant';
              final unitStr = o.unit != null && o.unit!.isNotEmpty
                  ? 'for Unit ${o.unit}'
                  : '';
              final msg =
                  'Hi $tenantName, update regarding your maintenance ticket $unitStr ("${o.title}"): The ticket is currently ${_statusLabel(o.status).toUpperCase()}. Total estimated cost: $cur ${totalCost.toStringAsFixed(0)}.';
              Clipboard.setData(ClipboardData(text: msg));
              showAppToast(context,
                  'Tenant notification message copied to clipboard!',
                  isSuccess: true);
            },
          ),
          const SizedBox(width: 6),
          // Dispatch Contractor
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: BorderSide(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Ionicons.hammerOutline, size: 12),
            label: const Text('Dispatch Contractor',
                style:
                    TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            onPressed: () {
              final worker =
                  o.assignedTo.isNotEmpty ? o.assignedTo : 'Contractor';
              final dispatchText =
                  'DISPATCH TICKET #${o.id.length >= 6 ? o.id.substring(0, 6) : o.id}\n'
                  'To: $worker\n'
                  'Task: ${o.title}\n'
                  'Unit: ${o.unit ?? "General"}\n'
                  'Category: ${o.category}\n'
                  'Labor / Parts: $cur ${(o.workerCost ?? 0).toStringAsFixed(0)} / $cur ${(o.productPrice ?? 0).toStringAsFixed(0)}\n'
                  'Notes: ${o.description}';
              Clipboard.setData(ClipboardData(text: dispatchText));
              showAppToast(context,
                  'Contractor dispatch summary copied to clipboard!',
                  isSuccess: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(
      WorkOrder o, bool isDark, Color borderColor) {
    final hasReceipt = o.receipt != null && o.receipt!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.receiptOutline,
                  size: 15, color: Color(0xFF10B981)),
              const SizedBox(width: 7),
              Text(
                'Attached Invoices & Repair Photos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const Spacer(),
              if (hasReceipt)
                TextButton.icon(
                  onPressed: () {
                    final updated = o.copyWith(receipt: '');
                    ref
                        .read(appDataProvider.notifier)
                        .upsertWorkOrder(updated);
                    showAppToast(context, 'Attachment removed',
                        isSuccess: true);
                  },
                  icon: const Icon(Ionicons.trashOutline,
                      size: 12, color: Color(0xFFEF4444)),
                  label: const Text('Remove',
                      style: TextStyle(
                          fontSize: 10.5, color: Color(0xFFEF4444))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasReceipt)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildReceiptImage(o.receipt!),
            )
          else
            DropTarget(
              onDragDone: (details) async {
                if (details.files.isNotEmpty) {
                  final file = details.files.first;
                  final updated = o.copyWith(receipt: file.path);
                  ref
                      .read(appDataProvider.notifier)
                      .upsertWorkOrder(updated);
                  showAppToast(context, 'Attached photo: ${file.name}',
                      isSuccess: true);
                }
              },
              child: InkWell(
                onTap: () async {
                  final p = await MediaPicker.pickImage(context);
                  if (p != null) {
                    final updated = o.copyWith(receipt: p);
                    ref
                        .read(appDataProvider.notifier)
                        .upsertWorkOrder(updated);
                    if (mounted) {
                      showAppToast(
                          context, 'Attached repair photo / receipt',
                          isSuccess: true);
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF061819).withValues(alpha: 0.5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.white12
                          : const Color(0xFFCBD5E1),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ionicons.cloudUploadOutline,
                            size: 20,
                            color: isDark
                                ? const Color(0xFF10B981)
                                : const Color(0xFF059669)),
                        const SizedBox(height: 4),
                        Text(
                          'Drag & drop repair photos/receipts here, or click to upload',
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      String label, String value, IconData icon, Color color, bool isDark, Color borderColor,
      {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isPrimary
            ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
            : (isDark ? const Color(0xFF091E1F) : Colors.white),
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
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
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
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
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

  Widget _buildCompactDetailItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isDark,
    required Color subColor,
  }) {
    final hasVal = value != '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0D2526).withValues(alpha: 0.55)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.05)
              : const Color(0xFFEDF2F7),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 4),
          Flexible(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: subColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: '$label: $value',
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: hasVal ? FontWeight.w600 : FontWeight.w400,
                  color: hasVal
                      ? (AppColors.heading)
                      : subColor.withValues(alpha: 0.55),
                  fontStyle: hasVal ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptImage(String path) {
    if (path.startsWith('http') || path.startsWith('content://')) {
      return Image.network(path, height: 160, width: double.infinity, fit: BoxFit.cover);
    }
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(f, height: 160, width: double.infinity, fit: BoxFit.cover);
    }
    return Container(
      height: 90,
      width: double.infinity,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Text('Receipt image not found at path', style: TextStyle(fontSize: 11.5)),
    );
  }

  Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
      case 'high':
      case 'urgent':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String _formatShortDate(String s) {
    if (s.isEmpty) return '—';
    if (s.length >= 10) return s.substring(5, 10);
    return s;
  }
}
