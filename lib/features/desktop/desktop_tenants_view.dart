import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/storage/app_media_backup.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../services/report_export_service.dart';
import 'desktop_rent_receipt_modal.dart';

/// 2-Column Master-Detail Split View for Tenants on macOS Desktop.
class DesktopTenantsView extends ConsumerStatefulWidget {
  final Tenant? initialSelectedTenant;
  final VoidCallback onAddTenant;
  final Function(Tenant tenant) onLogPayment;
  final Function(Tenant tenant)? onEditTenant;
  final Function(Tenant tenant)? onDeleteTenant;
  final Function(Tenant tenant)? onSelectTenant;
  final void Function(Payment payment, Tenant? tenant)? onPaymentDetails;
  final void Function(Payment payment, Tenant? tenant)? onEditPayment;
  final void Function(Tenant tenant)? onExportStatement;
  final void Function(RentDoc doc)? onViewDocument;
  final void Function(Tenant tenant)? onAddDocument;

  const DesktopTenantsView({
    super.key,
    this.initialSelectedTenant,
    required this.onAddTenant,
    required this.onLogPayment,
    this.onEditTenant,
    this.onDeleteTenant,
    this.onSelectTenant,
    this.onPaymentDetails,
    this.onEditPayment,
    this.onExportStatement,
    this.onViewDocument,
    this.onAddDocument,
  });

  @override
  ConsumerState<DesktopTenantsView> createState() => _DesktopTenantsViewState();
}

class _DesktopTenantsViewState extends ConsumerState<DesktopTenantsView> {
  String? _selectedTenantId;
  String _searchQuery = '';
  String _filter = 'all'; // 'all' | 'active' | 'vacant'
  bool _isDossierDragging = false;

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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

  Future<void> _showTenantContextMenu(
      BuildContext context, Offset position, Tenant tenant) async {
    setState(() => _selectedTenantId = tenant.id);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;

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
          value: 'payment',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.cashOutline,
            label: 'Log Rent Payment',
            isDark: isDark,
          ),
        ),
        if (widget.onAddDocument != null)
          PopupMenuItem(
            value: 'add_doc',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.cloudUploadOutline,
              label: 'Add Document',
              isDark: isDark,
            ),
          ),
        if (widget.onExportStatement != null)
          PopupMenuItem(
            value: 'statement',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.receiptOutline,
              label: 'Export Statement',
              isDark: isDark,
            ),
          ),
        if (tenant.phone.isNotEmpty)
          PopupMenuItem(
            value: 'call',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.callOutline,
              label: 'Call (${tenant.phone})',
              isDark: isDark,
            ),
          ),
        if (tenant.email.isNotEmpty)
          PopupMenuItem(
            value: 'email',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.mailOutline,
              label: 'Email Tenant',
              isDark: isDark,
            ),
          ),
        if (widget.onEditTenant != null) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Tenant',
              isDark: isDark,
            ),
          ),
        ],
        if (widget.onDeleteTenant != null) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'delete',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.trashOutline,
              label: 'Delete Tenant',
              isDestructive: true,
              isDark: isDark,
            ),
          ),
        ],
      ],
    );

    if (!mounted || item == null) return;

    if (item == 'payment') {
      widget.onLogPayment(tenant);
    } else if (item == 'add_doc') {
      widget.onAddDocument?.call(tenant);
    } else if (item == 'statement') {
      widget.onExportStatement?.call(tenant);
    } else if (item == 'call' && tenant.phone.isNotEmpty) {
      _launch('tel:${tenant.phone}');
    } else if (item == 'email' && tenant.email.isNotEmpty) {
      _launch('mailto:${tenant.email}');
    } else if (item == 'edit') {
      widget.onEditTenant?.call(tenant);
    } else if (item == 'delete') {
      widget.onDeleteTenant?.call(tenant);
    }
  }

  Future<void> _handleDroppedTenantFiles(
      List<dynamic> files, Tenant tenant) async {
    if (files.isEmpty) return;
    int addedCount = 0;
    final newDocs = <TenantDocument>[];

    for (final file in files) {
      final filePath = file.path as String;
      if (filePath.isEmpty) continue;
      final fileName = filePath.split(Platform.pathSeparator).last;

      final persistentPath =
          await AppMediaBackup.persistPickedFile(filePath, category: 'doc');
      final finalUri = persistentPath.isNotEmpty ? persistentPath : filePath;

      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';
      String docType = 'other';
      if (['pdf'].contains(ext)) {
        docType = 'contract';
      } else if (['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext)) {
        docType = 'id';
      }

      final docId = const Uuid().v4();
      final td = TenantDocument(
        id: docId,
        name: fileName,
        uri: finalUri,
        type: docType,
        uploadedAt: DateTime.now().toIso8601String(),
      );
      newDocs.add(td);

      final rentDoc = RentDoc(
        id: docId,
        title: '${tenant.name} - $fileName',
        type: docType,
        fileName: fileName,
        fileSize: '--',
        fileUri: finalUri,
        uploadedDate: DateTime.now().toIso8601String(),
        uploadedBy: 'Desktop Drop',
        tenant: tenant.name,
        unit: tenant.unit,
        tags: const ['tenant-group'],
        status: 'active',
        isPdf: ext == 'pdf',
      );
      ref.read(appDataProvider.notifier).upsertDocument(rentDoc);
      addedCount++;
    }

    if (newDocs.isNotEmpty) {
      final updated = tenant.copyWith(
        documents: [...tenant.documents, ...newDocs],
      );
      ref.read(appDataProvider.notifier).upsertTenant(updated);
    }

    if (mounted && addedCount > 0) {
      showAppToast(context,
          'Attached $addedCount document${addedCount > 1 ? 's' : ''} to ${tenant.name}');
    }
  }

  Widget _buildTenantDropOverlay(bool isDark, Tenant tenant) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF042F2E) : const Color(0xFFCCFBF1))
            .withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981),
          width: 2.5,
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F2425) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.attachOutline,
                  color: Color(0xFF10B981),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Attach to ${tenant.name}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Files will be linked to Unit ${tenant.unit} dossier',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedTenant != null) {
      _selectedTenantId = widget.initialSelectedTenant!.id;
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

    // Filter tenants
    final tenants = s.scopedTenants.where((t) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = t.name.toLowerCase().contains(q);
        final matchesUnit = t.unit.toLowerCase().contains(q);
        final matchesPhone = t.phone.toLowerCase().contains(q);
        if (!matchesName && !matchesUnit && !matchesPhone) return false;
      }
      if (_filter == 'active') return t.status.toLowerCase().trim() == 'active';
      if (_filter == 'vacant') {
        return t.unit.trim().isEmpty ||
            t.name.toLowerCase().contains('vacant');
      }
      return true;
    }).toList();

    // Default select first tenant if none selected
    if (_selectedTenantId == null && tenants.isNotEmpty) {
      _selectedTenantId = tenants.first.id;
    }

    final selectedTenant = s.scopedTenants
        .where((t) => t.id == _selectedTenantId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final masterWidth = constraints.maxWidth < 800
              ? 270.0
              : (constraints.maxWidth < 1050 ? 295.0 : 320.0);

          return Row(
            children: [
              // 1. LEFT PANEL: Master List (Responsive)
              Container(
                width: masterWidth,
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
                // Top Search & Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    children: [
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
                                      onChanged: (val) =>
                                          setState(() => _searchQuery = val.trim()),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Filter by name, unit...',
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Add Tenant',
                            waitDuration: const Duration(milliseconds: 350),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onAddTenant,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF0F766E),
                                        Color(0xFF059669),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF059669)
                                            .withValues(alpha: 0.25),
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
                      const SizedBox(height: 8),
                      // Filter chips
                      Row(
                        children: [
                          _filterChip('all', 'All (${s.scopedTenants.length})', isDark),
                          const SizedBox(width: 6),
                          _filterChip('active', 'Active', isDark),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),

                // Tenants List
                Expanded(
                  child: tenants.isEmpty
                      ? Center(
                          child: Text(
                            'No tenants match filter',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: tenants.length,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          itemBuilder: (context, i) {
                            final t = tenants[i];
                            final isSelected = t.id == _selectedTenantId;

                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedTenantId = t.id),
                              onSecondaryTapDown: (details) =>
                                  _showTenantContextMenu(
                                      context, details.globalPosition, t),
                              borderRadius: BorderRadius.circular(10),
                              hoverColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin:
                                    const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark
                                          ? const Color(0xFF0F766E)
                                              .withValues(alpha: 0.25)
                                          : const Color(0xFF059669)
                                              .withValues(alpha: 0.10))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isSelected
                                      ? Border.all(
                                          color: isDark
                                              ? const Color(0xFF10B981)
                                              .withValues(alpha: 0.6)
                                              : const Color(0xFF059669)
                                                  .withValues(alpha: 0.5),
                                        )
                                      : Border.all(color: Colors.transparent),
                                ),
                                child: Row(
                                  children: [
                                    // Tenant Avatar with Unit Badge
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        AvatarView(
                                          name: t.name,
                                          uri: t.avatar,
                                          radius: 20,
                                          borderColor: isSelected
                                              ? const Color(0xFF10B981)
                                              : (isDark
                                                  ? const Color(0xFF1E3A3A)
                                                  : const Color(0xFFCBD5E1)),
                                          borderWidth: 1.5,
                                        ),
                                        Positioned(
                                          right: -3,
                                          bottom: -3,
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFF059669)
                                                  : (isDark
                                                      ? const Color(0xFF0F2B2C)
                                                      : const Color(0xFF0F766E)),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isDark
                                                    ? const Color(0xFF091E1F)
                                                    : Colors.white,
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              t.unit,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.name,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$cur ${t.rentAmount.toStringAsFixed(0)}/mo',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Ionicons.chevronForward,
                                      size: 15,
                                      color: isSelected
                                          ? (isDark
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF059669))
                                          : (isDark
                                              ? const Color(0xFF475569)
                                              : const Color(0xFFCBD5E1)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // 2. RIGHT PANEL: Rich Detail Dossier
          Expanded(
            child: selectedTenant == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF132B2B).withValues(alpha: 0.5)
                                : const Color(0xFFEDF7F4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Ionicons.peopleOutline,
                            size: 48,
                            color: isDark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select a Tenant',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose a tenant from the directory or register a new lease',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: const Icon(Ionicons.personAddOutline, size: 15),
                          label: const Text('Add New Tenant'),
                          onPressed: widget.onAddTenant,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : DropTarget(
                    onDragEntered: (_) =>
                        setState(() => _isDossierDragging = true),
                    onDragExited: (_) =>
                        setState(() => _isDossierDragging = false),
                    onDragDone: (detail) async {
                      setState(() => _isDossierDragging = false);
                      await _handleDroppedTenantFiles(
                          detail.files, selectedTenant);
                    },
                    child: Stack(
                      children: [
                        _buildTenantDossier(selectedTenant, s, cur, isDark),
                        if (_isDossierDragging)
                          Positioned.fill(
                            child: _buildTenantDropOverlay(
                                isDark, selectedTenant),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    },
  ),
);
  }

  Widget _filterChip(String key, String label, bool isDark) {
    final active = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? const Color(0xFF059669) : const Color(0xFF0F766E))
              : (isDark ? const Color(0xFF0E2728) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildTenantDossier(
      Tenant tenant, AppDataState s, String cur, bool isDark) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final tenantPayments =
        s.payments.where((p) => p.tenantId == tenant.id).toList();
    final tenantWorkOrders =
        s.workOrders.where((w) => w.tenantId == tenant.id).toList();

    final depositVal = tenant.deposit ?? 0.0;
    final leaseStartVal = _formatDateOnly(tenant.leaseStartDate ?? tenant.joinDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        // Top Tenant Header — workspace toolbar style (matches Documents).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF061819).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 980;
              final subColor =
                  isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

              Widget miniActionBtn({
                required IconData icon,
                required Color color,
                required String tooltip,
                required VoidCallback onTap,
              }) {
                return Tooltip(
                  message: tooltip,
                  waitDuration: const Duration(milliseconds: 350),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: color
                              .withValues(alpha: isDark ? 0.28 : 0.22),
                        ),
                      ),
                      child: Center(
                        child: Icon(icon, size: 15, color: color),
                      ),
                    ),
                  ),
                );
              }

              final tenantHeaderInfo = Row(
                children: [
                  Tooltip(
                    message: 'Click to upload or change profile picture',
                    child: InkWell(
                      onTap: () async {
                        final p = await MediaPicker.pickImage(context);
                        if (p != null) {
                          final updated = tenant.copyWith(avatar: p);
                          ref
                              .read(appDataProvider.notifier)
                              .upsertTenant(updated);
                          if (mounted) {
                            showAppToast(
                              context,
                              'Avatar updated for ${tenant.name}',
                              isSuccess: true,
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AvatarView(
                            name: tenant.name,
                            uri: tenant.avatar,
                            radius: 22,
                            borderColor: const Color(0xFF10B981),
                            borderWidth: 1.5,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFF059669),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF091E1F)
                                      : Colors.white,
                                  width: 1.2,
                                ),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              tenant.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.heading,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                'UNIT ${tenant.unit}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                            if (tenant.status.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (tenant.status.toLowerCase() == 'active'
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF64748B))
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  tenant.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: tenant.status.toLowerCase() == 'active'
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (tenant.phone.isNotEmpty) ...[
                              const Icon(Ionicons.callOutline,
                                  size: 11, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text(
                                tenant.phone,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: subColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            if (tenant.email.isNotEmpty) ...[
                              const Icon(Ionicons.mailOutline,
                                  size: 11, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  tenant.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: subColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                            if (tenant.phone.isEmpty && tenant.email.isEmpty)
                              Text(
                                'No phone or email recorded',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: subColor.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final tenantHeaderActions = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onLogPayment(tenant),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.cashOutline,
                                size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Record Payment',
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
                  ),
                  if (tenant.phone.isNotEmpty) ...[
                    miniActionBtn(
                      icon: Ionicons.callOutline,
                      color: const Color(0xFF10B981),
                      tooltip: 'Call: ${tenant.phone}',
                      onTap: () => _launch('tel:${tenant.phone}'),
                    ),
                    miniActionBtn(
                      icon: Ionicons.chatbubbleOutline,
                      color: const Color(0xFF3B82F6),
                      tooltip: 'SMS: ${tenant.phone}',
                      onTap: () => _launch('sms:${tenant.phone}'),
                    ),
                  ],
                  miniActionBtn(
                    icon: Ionicons.cameraOutline,
                    color: const Color(0xFF10B981),
                    tooltip: 'Change / Upload Profile Picture',
                    onTap: () async {
                      final p = await MediaPicker.pickImage(context);
                      if (p != null) {
                        final updated = tenant.copyWith(avatar: p);
                        ref
                            .read(appDataProvider.notifier)
                            .upsertTenant(updated);
                        if (mounted) {
                          showAppToast(
                            context,
                            'Avatar updated for ${tenant.name}',
                            isSuccess: true,
                          );
                        }
                      }
                    },
                  ),
                  if (tenant.email.isNotEmpty)
                    miniActionBtn(
                      icon: Ionicons.mailOutline,
                      color: const Color(0xFF8B5CF6),
                      tooltip: 'Email: ${tenant.email}',
                      onTap: () => _launch('mailto:${tenant.email}'),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (widget.onExportStatement != null) {
                          widget.onExportStatement!(tenant);
                        } else {
                          _showExportStatementDialog(tenant, s);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
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
                            Icon(Ionicons.documentTextOutline,
                                size: 15, color: Color(0xFF06B6D4)),
                            SizedBox(width: 6),
                            Text(
                              'Statement',
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
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onEditTenant?.call(tenant),
                      borderRadius: BorderRadius.circular(8),
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
                  miniActionBtn(
                    icon: Ionicons.trashOutline,
                    color: const Color(0xFFEF4444),
                    tooltip: 'Delete Tenant',
                    onTap: () => widget.onDeleteTenant?.call(tenant),
                  ),
                ],
              );

              return isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tenantHeaderInfo,
                        const SizedBox(height: 8),
                        tenantHeaderActions,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: tenantHeaderInfo),
                        const SizedBox(width: 12),
                        tenantHeaderActions,
                      ],
                    );
            },
          ),
        ),

        const SizedBox(height: 14),

        // Financial Overview & Lease Terms Bento Row (4-Card Mac Bento)
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isNarrow = constraints.maxWidth < 640;

            String expiryValue = 'Month-to-Month';
            String expirySubtitle = 'Standard recurring';
            Color expiryColor = const Color(0xFF6366F1);

            if (tenant.leaseEndDate != null && tenant.leaseEndDate!.trim().isNotEmpty) {
              final parsedDate = DateTime.tryParse(tenant.leaseEndDate!.trim());
              if (parsedDate != null) {
                final diff = parsedDate.difference(DateTime.now()).inDays;
                if (diff < 0) {
                  expiryValue = 'Expired (${diff.abs()}d ago)';
                  expirySubtitle = 'Ended ${_formatDateOnly(tenant.leaseEndDate)} • Tap to renew';
                  expiryColor = const Color(0xFFEF4444);
                } else if (diff <= 30) {
                  expiryValue = 'Expires in $diff days';
                  expirySubtitle = 'Ends ${_formatDateOnly(tenant.leaseEndDate)} • Tap to renew';
                  expiryColor = const Color(0xFFF59E0B);
                } else {
                  expiryValue = '$diff days left';
                  expirySubtitle = 'Expires ${_formatDateOnly(tenant.leaseEndDate)}';
                  expiryColor = const Color(0xFF10B981);
                }
              }
            }

            final cards = [
              _infoBento(
                title: 'Monthly Rent',
                value: '$cur ${tenant.rentAmount.toStringAsFixed(0)}',
                subtitle: 'Due on 1st of each month',
                icon: Ionicons.cardOutline,
                isDark: isDark,
              ),
              _infoBento(
                title: 'Security Deposit',
                value: '$cur ${depositVal.toStringAsFixed(0)}',
                subtitle: 'Held in deposit account',
                icon: Ionicons.shieldCheckmarkOutline,
                isDark: isDark,
              ),
              _infoBento(
                title: 'Lease Start',
                value: leaseStartVal.isNotEmpty ? leaseStartVal : 'Standard',
                subtitle: 'Active lease terms',
                icon: Ionicons.calendarOutline,
                isDark: isDark,
              ),
              _infoBento(
                title: 'Lease Expiry',
                value: expiryValue,
                subtitle: expirySubtitle,
                icon: Ionicons.timeOutline,
                isDark: isDark,
                valueColor: expiryColor,
                onTap: () => _showRenewLeaseDialog(tenant),
                badge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: expiryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'RENEW',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: expiryColor,
                    ),
                  ),
                ),
              ),
            ];

            if (isNarrow) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: cards[2]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
                const SizedBox(width: 12),
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ],
            );
          },
        ),

        const SizedBox(height: 14),

        // Personal Identity & Utilities Bento Card
        _buildIdentityAndUtilitiesCard(tenant, isDark, borderColor),

        const SizedBox(height: 14),

        // Payment History
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E1F) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 10),
              if (tenantPayments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No recorded payments for this tenant.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tenantPayments.length,
                  separatorBuilder: (_, index) => Divider(
                    height: 1,
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.05)
                        : const Color(0xFFF1F5F9),
                  ),
                  itemBuilder: (context, i) {
                    final p = tenantPayments[i];
                    final isPaid = p.status == 'paid';

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                      onTap: () {
                        if (widget.onPaymentDetails != null) {
                          widget.onPaymentDetails!(p, tenant);
                        } else {
                          widget.onEditPayment?.call(p, tenant);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              isPaid
                                  ? Ionicons.checkmarkCircle
                                  : Ionicons.timeOutline,
                              size: 16,
                              color: isPaid
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.paidForMonth ?? p.displayMonth ?? 'Rent',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$cur ${p.amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Ionicons.receiptOutline, size: 14),
                              tooltip: 'Generate Rent Receipt...',
                              splashRadius: 14,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              padding: EdgeInsets.zero,
                              onPressed: () => DesktopRentReceiptModal.show(context, payment: p, tenant: tenant),
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
        ),

        const SizedBox(height: 14),

        // Associated Maintenance Tickets
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E1F) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Ionicons.constructOutline,
                          size: 16, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 8),
                      Text(
                        'Associated Maintenance Tickets (${tenantWorkOrders.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => _showCreateWorkOrderDialog(tenant),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.addOutline,
                              size: 13, color: Color(0xFF06B6D4)),
                          SizedBox(width: 4),
                          Text(
                            'New Ticket',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF06B6D4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (tenantWorkOrders.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.04),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Ionicons.checkmarkCircleOutline,
                          size: 24,
                          color: const Color(0xFF10B981).withValues(alpha: 0.7)),
                      const SizedBox(height: 6),
                      Text(
                        'No maintenance tickets logged for Unit ${tenant.unit}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...tenantWorkOrders.map(
                    (w) => _buildWorkOrderRow(w, cur, isDark, borderColor)),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Tenant Documents & Leases
        _buildTenantDocumentsCard(tenant, s, isDark, borderColor),
      ],
    );
  }

  Widget _buildIdentityAndUtilitiesCard(
      Tenant t, bool isDark, Color borderColor) {
    final subColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final valColor = AppColors.heading;

    final fields = [
      t.fathersName,
      t.idNumber,
      t.dateOfBirth,
      t.address,
      t.electricMeterNumber,
      t.gasMeterNumber,
    ];
    final completedCount =
        fields.where((f) => f != null && f.trim().isNotEmpty).length;

    Widget item(IconData icon, Color iconColor, String label, String? value) {
      final textVal =
          (value != null && value.trim().isNotEmpty) ? value.trim() : '—';
      final isSet = textVal != '—';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0D2526).withValues(alpha: 0.55)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.05)
                : const Color(0xFFEDF2F7),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: subColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: isSet ? textVal : '$label not provided',
                child: Text(
                  textVal,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                    color: isSet ? valColor : subColor.withValues(alpha: 0.55),
                    fontStyle: isSet ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final items = [
      item(Ionicons.peopleOutline, const Color(0xFF3B82F6), "Father's Name",
          t.fathersName),
      item(Ionicons.cardOutline, const Color(0xFF8B5CF6), "ID / Passport",
          t.idNumber),
      item(Ionicons.calendarOutline, const Color(0xFFEC4899), "Date of Birth",
          _formatDateOnly(t.dateOfBirth)),
      item(Ionicons.locationOutline, const Color(0xFFEF4444),
          "Permanent Address", t.address),
      item(Ionicons.flashOutline, const Color(0xFFF59E0B), "Electric Meter",
          t.electricMeterNumber),
      item(Ionicons.flameOutline, const Color(0xFFF97316), "Gas Meter",
          t.gasMeterNumber),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.personCircleOutline,
                  size: 15, color: Color(0xFF10B981)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Personal Identity & Utility Meters',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: completedCount == 6
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : (isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.06)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: completedCount == 6
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : (isDark
                            ? const Color.fromRGBO(255, 255, 255, 0.08)
                            : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Text(
                  '$completedCount of 6 on file',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: completedCount == 6
                        ? const Color(0xFF10B981)
                        : subColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 720 ? 3 : (width >= 450 ? 2 : 1);

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
    );
  }

  Widget _buildTenantDocumentsCard(
      Tenant t, AppDataState s, bool isDark, Color borderColor) {
    final syncedDocs = s.documents.where((d) => d.tenant == t.name).toList();
    final directDocs = t.documents;
    final totalDocs = syncedDocs.length + directDocs.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Ionicons.documentTextOutline,
                  size: 16, color: Color(0xFF06B6D4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Attached Documents ($totalDocs)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
              ),
              if (widget.onAddDocument != null)
                TextButton.icon(
                  icon: const Icon(Ionicons.cloudUploadOutline, size: 14),
                  label: const Text('Upload Document',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  onPressed: () => widget.onAddDocument!(t),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF06B6D4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (totalDocs == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No documents or leases uploaded for this tenant.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else ...[
            for (final d in directDocs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D2526).withValues(alpha: 0.5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.04)
                          : const Color(0xFFEDF2F7),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Ionicons.documentOutline,
                          size: 15, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.type.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (d.uri.isNotEmpty)
                        IconButton(
                          icon: const Icon(Ionicons.openOutline, size: 14),
                          tooltip: 'Open Document',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 26, minHeight: 26),
                          onPressed: () => MediaFiles.open(d.uri),
                        ),
                    ],
                  ),
                ),
              ),
            for (final d in syncedDocs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D2526).withValues(alpha: 0.5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.04)
                          : const Color(0xFFEDF2F7),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Ionicons.fileTrayFullOutline,
                          size: 15, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.type.replaceAll('-', ' ').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF06B6D4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (d.fileUri != null && d.fileUri!.isNotEmpty)
                        IconButton(
                          icon: const Icon(Ionicons.openOutline, size: 14),
                          tooltip: 'Open in Vault',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 26, minHeight: 26),
                          onPressed: () {
                            if (widget.onViewDocument != null) {
                              widget.onViewDocument!(d);
                            } else {
                              MediaFiles.open(d.fileUri!);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _infoBento({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    Color? valueColor,
    VoidCallback? onTap,
    Widget? badge,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
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
              Icon(icon,
                  size: 15,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF059669)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge,
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: valueColor ?? (AppColors.heading),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
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
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cardContent,
      );
    }
    return cardContent;
  }

  String _formatDateOnly(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return 'Standard';
    final s = dateStr.trim();
    try {
      final dt = DateTime.tryParse(s);
      if (dt != null) {
        return fmtDate(s, pattern: 'MMM d, yyyy');
      }
    } catch (_) {}
    if (s.contains('T')) {
      final part = s.split('T').first;
      final dt = DateTime.tryParse(part);
      if (dt != null) return fmtDate(part, pattern: 'MMM d, yyyy');
      return part;
    }
    if (s.contains(' ')) {
      final part = s.split(' ').first;
      final dt = DateTime.tryParse(part);
      if (dt != null) return fmtDate(part, pattern: 'MMM d, yyyy');
      return part;
    }
    return s;
  }

  Widget _buildWorkOrderRow(
      WorkOrder w, String cur, bool isDark, Color borderColor) {
    Color badgeColor = const Color(0xFFF59E0B);
    if (w.status.toLowerCase() == 'completed') {
      badgeColor = const Color(0xFF10B981);
    } else if (w.status.toLowerCase() == 'in_progress' ||
        w.status.toLowerCase() == 'in progress') {
      badgeColor = const Color(0xFF06B6D4);
    } else if (w.status.toLowerCase() == 'cancelled') {
      badgeColor = const Color(0xFFEF4444);
    }

    final totalCost = (w.productPrice ?? 0) + (w.workerCost ?? 0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF0F2B2C) : const Color(0xFFF8FAFC))
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Ionicons.constructOutline, size: 14, color: badgeColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        w.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    if (w.priority != null && w.priority!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (w.priority!.toLowerCase() == 'urgent'
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          w.priority!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: w.priority!.toLowerCase() == 'urgent'
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${w.category} • Logged ${_formatDateOnly(w.createdAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (totalCost > 0) ...[
            Text(
              '$cur ${totalCost.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              w.status.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportStatementDialog(Tenant tenant, AppDataState s) async {
    final cur = s.selectedCurrency;
    final history = s.payments.where((p) => p.tenantId == tenant.id).toList();
    final isDark = AppColors.isDark;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F2425) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Ionicons.documentTextOutline,
                  size: 20, color: Color(0xFF06B6D4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export Account Statement',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                    '${tenant.name} • Unit ${tenant.unit} (${history.length} payment records)',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose format to download or print official tenant statement:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF1E3A3A) : const Color(0xFFE2E8F0),
                  ),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Ionicons.documentOutline, color: Color(0xFFEF4444), size: 20),
                ),
                title: const Text('Export as PDF Document',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Formatted official account statement with summary cards & branding',
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Ionicons.downloadOutline, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    final pdfBytes = await ReportExportService.generateTenantStatementPdf(
                      tenant: tenant,
                      history: history,
                      currency: cur,
                      propertyManager: s.propertyManager,
                    );
                    if (mounted) {
                      final cleanName = tenant.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
                      final fileName = 'Statement_${cleanName}_Unit${tenant.unit}.pdf';
                      await ReportExportService.exportPdf(
                        context: context,
                        pdfBytes: pdfBytes,
                        fileName: fileName,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showAppToast(context, 'PDF generation error: $e', isError: true);
                    }
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF1E3A3A) : const Color(0xFFE2E8F0),
                  ),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Ionicons.gridOutline, color: Color(0xFF10B981), size: 20),
                ),
                title: const Text('Export as CSV Spreadsheet',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Raw records compatible with Microsoft Excel, Sheets & QuickBooks',
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Ionicons.downloadOutline, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    final csv = ReportExportService.generateTenantStatementCsv(
                      tenant: tenant,
                      history: history,
                      currency: cur,
                      propertyManager: s.propertyManager,
                    );
                    if (mounted) {
                      final cleanName = tenant.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
                      final fileName = 'Statement_${cleanName}_Unit${tenant.unit}.csv';
                      await ReportExportService.exportCsv(
                        context: context,
                        csvContent: csv,
                        fileName: fileName,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showAppToast(context, 'CSV generation error: $e', isError: true);
                    }
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF1E3A3A) : const Color(0xFFE2E8F0),
                  ),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Ionicons.printOutline, color: Color(0xFF3B82F6), size: 20),
                ),
                title: const Text('Direct Print Statement',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Open macOS system print dialog or send directly to connected printer',
                    style: TextStyle(fontSize: 11.5)),
                trailing: const Icon(Ionicons.chevronForwardOutline, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    final pdfBytes = await ReportExportService.generateTenantStatementPdf(
                      tenant: tenant,
                      history: history,
                      currency: cur,
                      propertyManager: s.propertyManager,
                    );
                    if (mounted) {
                      await ReportExportService.printPdf(
                        context: context,
                        pdfBytes: pdfBytes,
                        documentName: 'Statement - ${tenant.name}',
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showAppToast(context, 'Printing error: $e', isError: true);
                    }
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenewLeaseDialog(Tenant tenant) async {
    final s = ref.read(appDataProvider);
    final cur = s.selectedCurrency;
    final isDark = AppColors.isDark;

    DateTime initialEnd = DateTime.now().add(const Duration(days: 365));
    if (tenant.leaseEndDate != null && tenant.leaseEndDate!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(tenant.leaseEndDate!.trim());
      if (parsed != null) {
        initialEnd = parsed.isAfter(DateTime.now())
            ? parsed.add(const Duration(days: 365))
            : DateTime.now().add(const Duration(days: 365));
      }
    }

    DateTime selectedEnd = initialEnd;
    final rentCtrl =
        TextEditingController(text: tenant.rentAmount.toStringAsFixed(0));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F2425) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Ionicons.reloadOutline,
                      size: 20, color: Color(0xFF10B981)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Renew Lease Terms',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                        '${tenant.name} • Unit ${tenant.unit}',
                        style: TextStyle(
                          fontSize: 12,
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
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Duration Extension',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('+6 Months'),
                        onPressed: () {
                          setDialogState(() {
                            selectedEnd =
                                DateTime.now().add(const Duration(days: 182));
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('+1 Year (12 Mo)'),
                        onPressed: () {
                          setDialogState(() {
                            selectedEnd =
                                DateTime.now().add(const Duration(days: 365));
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('+2 Years'),
                        onPressed: () {
                          setDialogState(() {
                            selectedEnd =
                                DateTime.now().add(const Duration(days: 730));
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'New Lease Expiry Date',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedEnd,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedEnd = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF091E1F)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1E3A3A)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Ionicons.calendarOutline,
                              size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Text(
                            fmtDate(selectedEnd.toIso8601String(),
                                pattern: 'MMM d, yyyy'),
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          const Text('Change',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF10B981))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Adjusted Monthly Rent ($cur)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: rentCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '$cur ',
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF091E1F)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF1E3A3A)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Ionicons.checkmarkOutline, size: 16),
                label: const Text('Confirm Renewal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final newRent =
                      double.tryParse(rentCtrl.text.trim()) ?? tenant.rentAmount;
                  final updated = tenant.copyWith(
                    leaseEndDate:
                        selectedEnd.toIso8601String().split('T').first,
                    rentAmount: newRent,
                    status: 'active',
                  );
                  ref.read(appDataProvider.notifier).upsertTenant(updated);
                  Navigator.of(ctx).pop();
                  if (mounted) {
                    showAppToast(
                      context,
                      'Lease renewed for ${tenant.name} until ${fmtDate(selectedEnd.toIso8601String(), pattern: 'MMM d, yyyy')}',
                      isSuccess: true,
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateWorkOrderDialog(Tenant tenant) async {
    final isDark = AppColors.isDark;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'normal';
    String category = 'General Maintenance';

    final categories = [
      'General Maintenance',
      'Plumbing',
      'Electrical',
      'HVAC',
      'Appliance',
      'Carpentry',
      'Pest Control',
      'Security',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F2425) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Ionicons.constructOutline,
                      size: 20, color: Color(0xFF06B6D4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New Maintenance Ticket',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                        'Assigned to Unit ${tenant.unit} • ${tenant.name}',
                        style: TextStyle(
                          fontSize: 12,
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
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Issue / Job Title',
                      hintText: 'e.g. Kitchen sink faucet leaking',
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF091E1F)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: InputDecoration(
                            labelText: 'Category',
                            isDense: true,
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF091E1F)
                                : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          items: categories
                              .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c,
                                      style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDialogState(() => category = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: InputDecoration(
                            labelText: 'Priority',
                            isDense: true,
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF091E1F)
                                : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'low',
                                child: Text('Low',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'normal',
                                child: Text('Normal',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'high',
                                child: Text('High',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.orange))),
                            DropdownMenuItem(
                                value: 'urgent',
                                child: Text('Urgent',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red))),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => priority = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Details / Contractor Notes',
                      hintText: 'Describe symptoms, location, urgency...',
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF091E1F)
                          : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Ionicons.addOutline, size: 16),
                label: const Text('Create Ticket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final t = titleCtrl.text.trim();
                  if (t.isEmpty) {
                    showAppToast(context, 'Please enter a ticket title',
                        isError: true);
                    return;
                  }
                  final now = DateTime.now();
                  final newWo = WorkOrder(
                    id: 'wo_${now.millisecondsSinceEpoch}',
                    title: t,
                    description: descCtrl.text.trim(),
                    status: 'pending',
                    category: category,
                    priority: priority,
                    assignedTo: 'Unassigned',
                    unit: tenant.unit,
                    tenantId: tenant.id,
                    createdAt: now.toIso8601String(),
                    dueDate: now.add(const Duration(days: 3)).toIso8601String(),
                  );
                  ref.read(appDataProvider.notifier).upsertWorkOrder(newWo);
                  Navigator.of(ctx).pop();
                  if (mounted) {
                    showAppToast(
                      context,
                      'Maintenance ticket logged for Unit ${tenant.unit}',
                      isSuccess: true,
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

