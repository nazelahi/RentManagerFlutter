import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/storage/app_media_backup.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';

/// Modern 3-Pane / Responsive Master-Detail Document Vault for macOS Desktop.
class DesktopDocumentsView extends ConsumerStatefulWidget {
  final VoidCallback onAddDocument;
  final void Function(RentDoc doc)? onEditDocument;
  final void Function(RentDoc doc)? onViewDocument;
  final VoidCallback? onSyncTenantDocs;

  const DesktopDocumentsView({
    super.key,
    required this.onAddDocument,
    this.onEditDocument,
    this.onViewDocument,
    this.onSyncTenantDocs,
  });

  @override
  ConsumerState<DesktopDocumentsView> createState() =>
      _DesktopDocumentsViewState();
}

class _DesktopDocumentsViewState extends ConsumerState<DesktopDocumentsView> {
  String _selectedCategory = 'all'; // 'all' | 'expired' | category.type
  String? _selectedDocId;
  String _fileTypeFilter = 'all'; // 'all' | 'pdf' | 'image' | 'other'
  String _searchQuery = '';
  late final TextEditingController _searchController = TextEditingController();
  bool _isGridView = true;
  String _sortBy = 'newest'; // 'newest' | 'oldest' | 'name' | 'expiry'
  final Set<String> _collapsedGroups = {};
  bool _isDraggingOver = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _compareDocs(RentDoc a, RentDoc b, String sortBy) {
    switch (sortBy) {
      case 'oldest':
        final cmp = a.uploadedDate.compareTo(b.uploadedDate);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case 'name':
        final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        if (cmp != 0) return cmp;
        return b.uploadedDate.compareTo(a.uploadedDate);
      case 'expiry':
        final ea = (a.expiryDate ?? '').trim();
        final eb = (b.expiryDate ?? '').trim();
        if (ea.isNotEmpty && eb.isNotEmpty) {
          final cmp = ea.compareTo(eb);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (ea.isNotEmpty && eb.isEmpty) return -1;
        if (ea.isEmpty && eb.isNotEmpty) return 1;
        return b.uploadedDate.compareTo(a.uploadedDate);
      case 'newest':
      default:
        final cmp = b.uploadedDate.compareTo(a.uploadedDate);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
  }

  int _compareGroups(DocumentGroup a, DocumentGroup b, String sortBy) {
    switch (sortBy) {
      case 'oldest':
        String getEarliestDate(DocumentGroup g) {
          final dates = g.documents
              .map((d) => d.uploadedDate.trim())
              .where((d) => d.isNotEmpty)
              .toList();
          if (dates.isEmpty) return g.uploadedDate;
          dates.sort();
          return dates.first;
        }
        final da = getEarliestDate(a);
        final db = getEarliestDate(b);
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case 'name':
        final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        if (cmp != 0) return cmp;
        return b.uploadedDate.compareTo(a.uploadedDate);
      case 'expiry':
        String getEarliestExpiry(DocumentGroup g) {
          final expiries = g.documents
              .map((d) => (d.expiryDate ?? '').trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (expiries.isEmpty) return '';
          expiries.sort();
          return expiries.first;
        }
        final ea = getEarliestExpiry(a);
        final eb = getEarliestExpiry(b);
        if (ea.isNotEmpty && eb.isNotEmpty) {
          final cmp = ea.compareTo(eb);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        if (ea.isNotEmpty && eb.isEmpty) return -1;
        if (ea.isEmpty && eb.isNotEmpty) return 1;
        return b.uploadedDate.compareTo(a.uploadedDate);
      case 'newest':
      default:
        String getLatestDate(DocumentGroup g) {
          final dates = g.documents
              .map((d) => d.uploadedDate.trim())
              .where((d) => d.isNotEmpty)
              .toList();
          if (dates.isEmpty) return g.uploadedDate;
          dates.sort((x, y) => y.compareTo(x));
          return dates.first;
        }
        final da = getLatestDate(a);
        final db = getLatestDate(b);
        final cmp = db.compareTo(da);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
  }

  ({List<DocumentGroup> groups, List<RentDoc> individual}) _organize(
      AppDataState s, List<RentDoc> docs, String sortBy) {
    final byGroup = <String, List<RentDoc>>{};
    final individual = <RentDoc>[];
    for (final d in docs) {
      if (d.groupId != null && d.groupId!.isNotEmpty) {
        byGroup.putIfAbsent(d.groupId!, () => []).add(d);
      } else {
        individual.add(d);
      }
    }
    final stored = {for (final g in s.documentGroups) g.id: g};
    final groups = <DocumentGroup>[];
    byGroup.forEach((gid, list) {
      list.sort((a, b) => _compareDocs(a, b, sortBy));
      final first = list.first;
      final existing = stored[gid];
      final isTenantGroup = first.tags.contains('tenant-group');
      final title = (existing != null && existing.title.isNotEmpty)
          ? existing.title
          : (isTenantGroup && (first.tenant ?? '').isNotEmpty
              ? 'Tenant Documents - ${first.tenant}'
              : first.title);
      final description = (existing?.description?.isNotEmpty == true)
          ? existing!.description
          : (isTenantGroup
              ? 'Documents for tenant ${first.tenant} in unit ${first.unit}'
              : first.description);
      groups.add(DocumentGroup(
        id: gid,
        title: title,
        type: existing?.type.isNotEmpty == true ? existing!.type : first.type,
        description: description,
        uploadedBy: existing?.uploadedBy ?? first.uploadedBy,
        uploadedDate: existing?.uploadedDate ?? first.uploadedDate,
        unit: existing?.unit ?? first.unit,
        tenant: existing?.tenant ?? first.tenant,
        documents: list,
        isCollapsed: existing?.isCollapsed ?? false,
      ));
    });

    groups.sort((a, b) => _compareGroups(a, b, sortBy));
    individual.sort((a, b) => _compareDocs(a, b, sortBy));
    return (groups: groups, individual: individual);
  }

  bool _isImage(String? uri) {
    if (uri == null) return false;
    return RegExp(r'\.(png|jpg|jpeg|gif|webp)$', caseSensitive: false)
        .hasMatch(uri);
  }

  bool _isPdf(RentDoc d) {
    if (d.isPdf) return true;
    final name = d.fileName.toLowerCase();
    final uri = (d.fileUri ?? '').toLowerCase();
    return name.endsWith('.pdf') || uri.endsWith('.pdf');
  }

  bool _isImageDoc(RentDoc d) {
    if (_isImage(d.fileUri) || _isImage(d.fileName)) return true;
    return false;
  }

  Color _categoryColor(String type) {
    switch (type.toLowerCase()) {
      case 'lease':
        return const Color(0xFF10B981);
      case 'id-card':
        return const Color(0xFF3B82F6);
      case 'receipt':
        return const Color(0xFF8B5CF6);
      case 'maintenance':
        return const Color(0xFFF59E0B);
      case 'notice':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF14B8A6);
    }
  }

  IconData _categoryIcon(String type) {
    switch (type.toLowerCase()) {
      case 'lease':
        return Ionicons.documentTextOutline;
      case 'id-card':
        return Ionicons.cardOutline;
      case 'receipt':
        return Ionicons.receiptOutline;
      case 'maintenance':
        return Ionicons.constructOutline;
      case 'notice':
        return Ionicons.megaphoneOutline;
      default:
        return Ionicons.folderOutline;
    }
  }

  String _prettyType(String t) {
    if (t.isEmpty) return t;
    if (t == 'id-card') return 'ID Card';
    final s = t.replaceAll('-', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  bool _isExpired(RentDoc d) {
    if (d.status.toLowerCase() == 'expired') return true;
    if (d.expiryDate != null && d.expiryDate!.isNotEmpty) {
      final exp = DateTime.tryParse(d.expiryDate!);
      if (exp != null && exp.isBefore(DateTime.now())) return true;
    }
    return false;
  }

  void _confirmDelete(RentDoc doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.isDark
            ? const Color(0xFF0F2627)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Document?'),
        content: Text(
          'Are you sure you want to delete "${doc.title.isNotEmpty ? doc.title : doc.fileName}"? This cannot be undone.',
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
              ref.read(appDataProvider.notifier).deleteDocument(doc.id);
              if (_selectedDocId == doc.id) {
                setState(() {
                  _selectedDocId = null;
                });
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _openDocument(RentDoc d) {
    setState(() => _selectedDocId = d.id);
    if (widget.onViewDocument != null) {
      widget.onViewDocument!(d);
    } else {
      _showDocumentPreviewModal(d);
    }
  }

  Future<void> _handleDroppedDocuments(List<dynamic> files) async {
    if (files.isEmpty) return;
    int addedCount = 0;
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
        docType = 'inspection';
      } else if (['doc', 'docx', 'txt'].contains(ext)) {
        docType = 'notice';
      }

      final cleanTitle = fileName
          .replaceAll(RegExp(r'\.[^.]+$'), '')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ');

      final newDoc = RentDoc(
        id: const Uuid().v4(),
        title: cleanTitle.isNotEmpty ? cleanTitle : fileName,
        type: (_selectedCategory != 'all' && _selectedCategory != 'expired')
            ? _selectedCategory
            : docType,
        fileName: fileName,
        fileSize: '--',
        fileUri: finalUri,
        uploadedDate: DateTime.now().toIso8601String(),
        uploadedBy: 'Desktop User',
        status: 'active',
        isPdf: ext == 'pdf',
      );

      ref.read(appDataProvider.notifier).upsertDocument(newDoc);
      addedCount++;
    }

    if (mounted && addedCount > 0) {
      showAppToast(context,
          'Imported $addedCount document${addedCount > 1 ? 's' : ''} to Vault');
    }
  }

  Widget _buildDropOverlay(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF042F2E) : const Color(0xFFCCFBF1))
            .withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(12),
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
                  Ionicons.cloudUploadOutline,
                  color: Color(0xFF10B981),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Drop Files to Upload',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Files will be saved directly into your Vault',
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
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showDocumentContextMenu(
      BuildContext context, Offset position, RentDoc doc) async {
    setState(() => _selectedDocId = doc.id);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final isDark = AppColors.isDark;
    final hasFile = doc.fileUri != null && doc.fileUri!.isNotEmpty;

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
          value: 'view',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.eyeOutline,
            label: 'View / Preview',
            isDark: isDark,
          ),
        ),
        if (hasFile) ...[
          PopupMenuItem(
            value: 'open_external',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.openOutline,
              label: 'Open in System App',
              isDark: isDark,
            ),
          ),
          PopupMenuItem(
            value: 'share',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.shareOutline,
              label: 'Share / AirDrop',
              isDark: isDark,
            ),
          ),
        ],
        if (widget.onEditDocument != null)
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: _contextMenuItem(
              icon: Ionicons.createOutline,
              label: 'Edit Details',
              isDark: isDark,
            ),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: _contextMenuItem(
            icon: Ionicons.trashOutline,
            label: 'Delete Document',
            isDestructive: true,
            isDark: isDark,
          ),
        ),
      ],
    );

    if (!mounted || item == null) return;

    if (item == 'view') {
      _openDocument(doc);
    } else if (item == 'open_external' && doc.fileUri != null) {
      MediaFiles.open(doc.fileUri!);
    } else if (item == 'share' && doc.fileUri != null) {
      MediaFiles.share(doc.fileUri!);
    } else if (item == 'edit') {
      widget.onEditDocument?.call(doc);
    } else if (item == 'delete') {
      _confirmDelete(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;

    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    final allDocs = s.scopedDocuments;
    final expiredDocs = allDocs.where(_isExpired).toList();

    // Filter documents
    final filtered = allDocs.where((d) {
      // Category filter
      if (_selectedCategory == 'expired') {
        if (!_isExpired(d)) return false;
      } else if (_selectedCategory != 'all') {
        if (d.type.toLowerCase() != _selectedCategory.toLowerCase()) {
          return false;
        }
      }

      // Quick file type filter
      if (_fileTypeFilter == 'pdf' && !_isPdf(d)) return false;
      if (_fileTypeFilter == 'image' && !_isImageDoc(d)) return false;
      if (_fileTypeFilter == 'other' && (_isPdf(d) || _isImageDoc(d))) return false;

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesTitle = d.title.toLowerCase().contains(q);
        final matchesDesc = (d.description ?? '').toLowerCase().contains(q);
        final matchesFile = d.fileName.toLowerCase().contains(q);
        final matchesUnit = (d.unit ?? '').toLowerCase().contains(q);
        final matchesTenant = (d.tenant ?? '').toLowerCase().contains(q);
        final matchesTags = d.tags.any((t) => t.toLowerCase().contains(q));
        if (!matchesTitle &&
            !matchesDesc &&
            !matchesFile &&
            !matchesUnit &&
            !matchesTenant &&
            !matchesTags) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sort documents
    filtered.sort((a, b) => _compareDocs(a, b, _sortBy));

    final org = _organize(s, filtered, _sortBy);
    final selectedDoc = allDocs.where((d) => d.id == _selectedDocId).firstOrNull;

    void openSelectedDocument() {
      final docToOpen = selectedDoc ?? filtered.firstOrNull;
      if (docToOpen != null) {
        _openDocument(docToOpen);
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): openSelectedDocument,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): openSelectedDocument,
        const SingleActivator(LogicalKeyboardKey.space): openSelectedDocument,
        const SingleActivator(LogicalKeyboardKey.enter): openSelectedDocument,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final sidebarWidth = constraints.maxWidth < 950 ? 200.0 : 225.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. LEFT SIDEBAR: Categories & Folders
                  Container(
                    width: sidebarWidth,
                    decoration: BoxDecoration(
                      color: isDark
                      ? const Color(0xFF061819).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.6),
                  border: Border(
                    right: BorderSide(color: borderColor, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Document Vault',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.heading,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF132B2B)
                                  : const Color(0xFFEDF7F4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${allDocs.length}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Search box
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
                                  hintText: 'Search vault files...',
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
                const SizedBox(height: 10),

                // Folder & Category Navigation
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _buildCategoryRow('all', 'All Files', Ionicons.folderOutline,
                          allDocs.length, const Color(0xFF10B981), isDark),
                      if (expiredDocs.isNotEmpty)
                        _buildCategoryRow('expired', 'Expired Documents',
                            Ionicons.alertCircleOutline, expiredDocs.length,
                            const Color(0xFFEF4444), isDark),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'CATEGORIES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Standard Categories
                      _buildCategoryRow('lease', 'Lease Agreements',
                          Ionicons.documentTextOutline,
                          allDocs.where((d) => d.type == 'lease').length,
                          const Color(0xFF10B981), isDark),
                      _buildCategoryRow('id-card', 'Tenant ID Cards',
                          Ionicons.cardOutline,
                          allDocs.where((d) => d.type == 'id-card').length,
                          const Color(0xFF3B82F6), isDark),
                      _buildCategoryRow('receipt', 'Receipts & Proofs',
                          Ionicons.receiptOutline,
                          allDocs.where((d) => d.type == 'receipt').length,
                          const Color(0xFF8B5CF6), isDark),
                      _buildCategoryRow('maintenance', 'Maintenance',
                          Ionicons.constructOutline,
                          allDocs.where((d) => d.type == 'maintenance').length,
                          const Color(0xFFF59E0B), isDark),
                      _buildCategoryRow('notice', 'Notices & Legal',
                          Ionicons.megaphoneOutline,
                          allDocs.where((d) => d.type == 'notice').length,
                          const Color(0xFFEF4444), isDark),

                      // Custom categories from database if any
                      for (final cat in s.documentCategories)
                        if (!['lease', 'id-card', 'receipt', 'maintenance', 'notice']
                            .contains(cat.type))
                          _buildCategoryRow(
                            cat.type,
                            cat.name,
                            _categoryIcon(cat.type),
                            allDocs.where((d) => d.type == cat.type).length,
                            _categoryColor(cat.type),
                            isDark,
                          ),
                    ],
                  ),
                ),

                // Vault Health & Stats Summary Card
                _buildVaultHealthCard(allDocs, expiredDocs, isDark, borderColor),

                // Bottom sync button
                if (widget.onSyncTenantDocs != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.heading,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        minimumSize: const Size.fromHeight(34),
                      ),
                      onPressed: widget.onSyncTenantDocs,
                      icon: const Icon(Ionicons.syncOutline, size: 14),
                      label: const Text('Sync Tenant Docs',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
              ],
            ),
          ),

          // 2. CENTER PANEL: Document Workspace (Grid / Table)
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _isDraggingOver = true),
              onDragExited: (_) => setState(() => _isDraggingOver = false),
              onDragDone: (detail) async {
                setState(() => _isDraggingOver = false);
                await _handleDroppedDocuments(detail.files);
              },
              child: Stack(
                children: [
                  Column(
              children: [
                // Top Workspace Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF061819).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.3),
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, tb) {
                      final showTypePills = tb.maxWidth >= 780;
                      final isCompactSort = tb.maxWidth < 650;
                      final isCompactUpload = tb.maxWidth < 500;

                      return Row(
                        children: [
                          // Folder title & count
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _selectedCategory == 'all'
                                        ? 'All Files'
                                        : (_selectedCategory == 'expired'
                                            ? 'Expired Documents'
                                            : _prettyType(_selectedCategory)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.heading,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromRGBO(255, 255, 255, 0.06)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${filtered.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Quick file type filter pills
                          if (showTypePills) ...[
                            const SizedBox(width: 12),
                            _buildFileTypeFilterChip('all', 'All', isDark, borderColor),
                            const SizedBox(width: 6),
                            _buildFileTypeFilterChip('pdf', 'PDFs', isDark, borderColor),
                            const SizedBox(width: 6),
                            _buildFileTypeFilterChip('image', 'Images', isDark, borderColor),
                          ],

                          const Spacer(),

                          // Redesigned Sort Selector
                          _buildSortSelector(isDark, borderColor, isCompactSort),
                          const SizedBox(width: 8),

                          // View Mode Toggle (Grid / List)
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color.fromRGBO(255, 255, 255, 0.05)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Grid View',
                                  icon: Icon(Ionicons.gridOutline,
                                      size: 15,
                                      color: _isGridView
                                          ? (isDark
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF059669))
                                          : (isDark
                                              ? const Color(0xFF64748B)
                                              : const Color(0xFF94A3B8))),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  onPressed: () => setState(() => _isGridView = true),
                                ),
                                IconButton(
                                  tooltip: 'List View',
                                  icon: Icon(Ionicons.listOutline,
                                      size: 16,
                                      color: !_isGridView
                                          ? (isDark
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF059669))
                                          : (isDark
                                              ? const Color(0xFF64748B)
                                              : const Color(0xFF94A3B8))),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  onPressed: () => setState(() => _isGridView = false),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Upload Button
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: widget.onAddDocument,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 30,
                                padding: EdgeInsets.symmetric(horizontal: isCompactUpload ? 8 : 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0F766E), Color(0xFF059669)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF059669).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Ionicons.cloudUploadOutline,
                                        size: 15, color: Colors.white),
                                    if (!isCompactUpload) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Add Document',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Document Files Container
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(isDark)
                      : (_isGridView
                          ? _buildGroupedGridView(
                              org.groups, org.individual, isDark, borderColor)
                          : _buildGroupedTableView(
                              org.groups, org.individual, isDark, borderColor)),
                ),
              ],
            ),
            if (_isDraggingOver)
              Positioned.fill(
                child: _buildDropOverlay(isDark),
              ),
          ],
        ),
      ),
    ),

        ],
      );
    },
  ),
),
),
);
  }

  Widget _buildCategoryRow(String key, String label, IconData icon, int count,
      Color color, bool isDark) {
    final isSelected = _selectedCategory == key;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedCategory = key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? const Color(0xFF132B2B)
                      : const Color(0xFFEDF7F4))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.5),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? const Color(0xFF10B981) : color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? (AppColors.heading)
                          : (isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF334155)),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF1A3838)
                            : const Color(0xFFD1FAE5))
                        : (isDark
                            ? const Color.fromRGBO(255, 255, 255, 0.05)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? const Color(0xFF10B981)
                          : (isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
              ],
            ),
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF132B2B).withValues(alpha: 0.5)
                  : const Color(0xFFEDF7F4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Ionicons.documentTextOutline,
              size: 44,
              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No documents in this view',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload leases, tenant IDs, receipts, or maintenance records',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: widget.onAddDocument,
            icon: const Icon(Ionicons.cloudUploadOutline, size: 16),
            label: const Text('Add Document', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedGridView(
      List<DocumentGroup> groups,
      List<RentDoc> individual,
      bool isDark,
      Color borderColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. GROUPS SECTION
        for (final g in groups) ...[
          _buildGroupCard(g, isDark, borderColor),
          const SizedBox(height: 14),
        ],

        // 2. INDIVIDUAL / SINGLE SECTION
        if (individual.isNotEmpty) ...[
          if (groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Ionicons.documentOutline,
                    size: 15,
                    color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Individual Documents (${individual.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ],
              ),
            ),
          if (individual.length == 1)
            _buildSingleDocCard(individual.first, isDark, borderColor)
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemCount: individual.length,
              itemBuilder: (context, i) =>
                  _buildGridCard(individual[i], isDark, borderColor),
            ),
        ],
      ],
    );
  }

  Widget _buildGroupCard(DocumentGroup g, bool isDark, Color borderColor) {
    final collapsed = _collapsedGroups.contains(g.id);
    final isPhotoGroup = g.documents.isNotEmpty &&
        g.documents.every((d) => _isImage(d.fileUri));
    final typeColor = _categoryColor(g.type);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar (clickable to expand/collapse)
          InkWell(
            onTap: () {
              setState(() {
                if (collapsed) {
                  _collapsedGroups.remove(g.id);
                } else {
                  _collapsedGroups.add(g.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isPhotoGroup ? Ionicons.imagesOutline : _categoryIcon(g.type),
                      size: 19,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.heading,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                _prettyType(g.type).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: typeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${g.documents.length} ${isPhotoGroup ? 'photo' : 'document'}${g.documents.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                              ),
                            ),
                            if (g.unit != null && g.unit!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text('•', style: TextStyle(fontSize: 10, color: borderColor)),
                              const SizedBox(width: 6),
                              Icon(Ionicons.homeOutline, size: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              const SizedBox(width: 3),
                              Text(
                                'Unit ${g.unit}',
                                style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                              ),
                            ],
                            if (g.tenant != null && g.tenant!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text('•', style: TextStyle(fontSize: 10, color: borderColor)),
                              const SizedBox(width: 6),
                              Icon(Ionicons.personOutline, size: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              const SizedBox(width: 3),
                              Text(
                                g.tenant!,
                                style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                              ),
                            ],
                            if (g.uploadedDate.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text('•', style: TextStyle(fontSize: 10, color: borderColor)),
                              const SizedBox(width: 6),
                              Text(
                                _formatDate(g.uploadedDate),
                                style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Chevron button
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF061819) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Ionicons.chevronDown,
                        size: 15,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (g.description != null && g.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                g.description!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ),

          // Expanded Documents in Group
          if (!collapsed) ...[
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: g.documents.length,
                itemBuilder: (context, i) =>
                    _buildGridCard(g.documents[i], isDark, borderColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleDocCard(RentDoc d, bool isDark, Color borderColor) {
    final isSelected = d.id == _selectedDocId;
    final isImg = _isImage(d.fileUri);
    final expired = _isExpired(d);
    final typeColor = _categoryColor(d.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDocument(d),
        onSecondaryTapDown: (details) =>
            _showDocumentContextMenu(context, details.globalPosition, d),
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.transparent,
        child: HoverTinter(
          builder: (hovered) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
                : (isDark
                    ? Color(hovered ? 0xFF0F2626 : 0xFF091E1F)
                    : hovered ? const Color(0xFFF5FAF8) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : hovered
                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                      : borderColor,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 64x64 Preview Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF041011) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: isImg && d.fileUri != null
                            ? _buildThumbnailImage(d.fileUri!)
                            : Icon(
                                d.isPdf
                                    ? Ionicons.documentTextOutline
                                    : _categoryIcon(d.type),
                                size: 32,
                                color: typeColor,
                              ),
                      ),
                      if (expired)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'EXPIRED',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Document Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            d.title.isNotEmpty ? d.title : d.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.heading,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _prettyType(d.type).toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (d.unit != null && d.unit!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.homeOutline, size: 12, color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                              const SizedBox(width: 4),
                              Text(
                                'Unit ${d.unit}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        if (d.tenant != null && d.tenant!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.personOutline, size: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                d.tenant!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        if (d.fileSize.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.folderOutline, size: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                d.fileSize,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.calendarOutline, size: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(d.uploadedDate),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Actions
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      side: BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                    ),
                    onPressed: () => _openDocument(d),
                    icon: const Icon(Ionicons.eyeOutline, size: 13),
                    label: const Text('Preview', style: TextStyle(fontSize: 11.5)),
                  ),
                  if (widget.onEditDocument != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Edit Document',
                      icon: const Icon(Ionicons.createOutline, size: 16),
                      onPressed: () => widget.onEditDocument!(d),
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

  Widget _buildGridCard(RentDoc d, bool isDark, Color borderColor) {
    final isSelected = d.id == _selectedDocId;
    final isImg = _isImage(d.fileUri);
    final expired = _isExpired(d);
    final typeColor = _categoryColor(d.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDocument(d),
        onSecondaryTapDown: (details) =>
            _showDocumentContextMenu(context, details.globalPosition, d),
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.transparent,
        child: HoverTinter(
          builder: (hovered) => Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? const Color(0xFF132B2B)
                    : const Color(0xFFEDF7F4))
                : (isDark
                    ? Color(hovered ? 0xFF0F2626 : 0xFF091E1F)
                    : hovered ? const Color(0xFFF5FAF8) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : hovered
                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                      : borderColor,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File Preview Thumbnail Area
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF041011)
                        : const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: isImg && d.fileUri != null
                            ? ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                child: _buildThumbnailImage(d.fileUri!),
                              )
                            : Icon(
                                d.isPdf
                                    ? Ionicons.documentTextOutline
                                    : _categoryIcon(d.type),
                                size: 40,
                                color: typeColor,
                              ),
                      ),
                      // Expiry / Type Badge on Top
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: expired
                                ? const Color(0xFFEF4444)
                                : typeColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            expired ? 'EXPIRED' : _prettyType(d.type).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Top Right Quick Action (Preview)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openDocument(d),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: (isDark ? const Color(0xFF061819) : Colors.white)
                                    .withValues(alpha: 0.88),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: borderColor.withValues(alpha: 0.7),
                                  width: 0.8,
                                ),
                              ),
                              child: Icon(
                                Ionicons.eyeOutline,
                                size: 13,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Info area
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title.isNotEmpty ? d.title : d.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (d.unit != null && d.unit!.isNotEmpty) ...[
                          Text(
                            d.unit!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('•', style: TextStyle(fontSize: 10, color: borderColor)),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            d.tenant ?? d.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.fileSize.isNotEmpty ? d.fileSize : '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(d.uploadedDate),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
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
      ),
    );
  }

  
  Widget _buildTableHeader(bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF07191A)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          const SizedBox(width: 54),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              'DOCUMENT / NAME',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Text(
              'CATEGORY',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              'UNIT / TENANT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: Text(
              'DATE / EXPIRY',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 65,
            child: Text(
              'SIZE',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedTableView(
      List<DocumentGroup> groups,
      List<RentDoc> individual,
      bool isDark,
      Color borderColor) {
    return Column(
      children: [
        // Pinned Table Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildTableHeader(isDark, borderColor),
        ),
        // Scrollable Table Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // 1. GROUPS SECTION
              for (final g in groups) ...[
                _buildGroupTableRow(g, isDark, borderColor),
                const SizedBox(height: 8),
              ],

              // 2. INDIVIDUAL / SINGLE SECTION
              if (individual.isNotEmpty) ...[
                if (groups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                    child: Row(
                      children: [
                        Icon(
                          Ionicons.documentOutline,
                          size: 14,
                          color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Individual Documents (${individual.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final d in individual) ...[
                  _buildTableRow(d, isDark, borderColor),
                  const SizedBox(height: 4),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRowThumbnail(RentDoc d, bool isDark, Color borderColor) {
    final isImg = _isImage(d.fileUri) || _isImage(d.fileName);
    final hasUri = d.fileUri != null && d.fileUri!.isNotEmpty;
    final typeColor = _categoryColor(d.type);
    final isPdf = d.isPdf || d.fileName.toLowerCase().endsWith('.pdf');

    Widget content;
    if (isImg && hasUri) {
      content = _buildThumbnailImage(d.fileUri!, iconSize: 16);
    } else if (isPdf) {
      content = Container(
        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Ionicons.documentTextOutline,
              size: 14,
              color: Color(0xFFEF4444),
            ),
            SizedBox(height: 1),
            Text(
              'PDF',
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w900,
                color: Color(0xFFEF4444),
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    } else if (isImg) {
      content = Container(
        color: typeColor.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(
          Ionicons.imageOutline,
          size: 16,
          color: typeColor,
        ),
      );
    } else {
      content = Container(
        color: typeColor.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(
          _categoryIcon(d.type),
          size: 16,
          color: typeColor,
        ),
      );
    }

    return Container(
      width: 32,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF041011) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: borderColor.withValues(alpha: isDark ? 0.6 : 0.8),
          width: 0.8,
        ),
      ),
      child: content,
    );
  }

  Widget _buildGroupRowThumbnail(
      DocumentGroup g, bool isDark, Color borderColor) {
    final isPhotoGroup = g.documents.isNotEmpty &&
        g.documents.every((d) => _isImage(d.fileUri) || _isImage(d.fileName));
    final typeColor = _categoryColor(g.type);

    Widget content;
    final firstImgDoc = g.documents.cast<RentDoc?>().firstWhere(
          (d) =>
              d != null &&
              (_isImage(d.fileUri) || _isImage(d.fileName)) &&
              d.fileUri != null &&
              d.fileUri!.isNotEmpty,
          orElse: () => null,
        );

    if (firstImgDoc != null && firstImgDoc.fileUri != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailImage(firstImgDoc.fileUri!, iconSize: 16),
          if (g.documents.length > 1)
            Positioned(
              right: 1.5,
              bottom: 1.5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '+${g.documents.length}',
                  style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      content = Container(
        color: typeColor.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Icon(
          isPhotoGroup ? Ionicons.imagesOutline : Ionicons.folderOutline,
          size: 16,
          color: typeColor,
        ),
      );
    }

    return Container(
      width: 32,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF041011) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: borderColor.withValues(alpha: isDark ? 0.6 : 0.8),
          width: 0.8,
        ),
      ),
      child: content,
    );
  }

  Widget _buildGroupTableRow(DocumentGroup g, bool isDark, Color borderColor) {
    final collapsed = _collapsedGroups.contains(g.id);
    final isPhotoGroup = g.documents.isNotEmpty &&
        g.documents.every((d) => _isImage(d.fileUri));
    final typeColor = _categoryColor(g.type);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF091E1F) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Header Row
          InkWell(
            onTap: () {
              setState(() {
                if (collapsed) {
                  _collapsedGroups.remove(g.id);
                } else {
                  _collapsedGroups.add(g.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          child: Center(
                            child: AnimatedRotation(
                              turns: collapsed ? 0 : 0.25,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Ionicons.chevronForward,
                                size: 13,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildGroupRowThumbnail(g, isDark, borderColor),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 1: Document / Name
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            g.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${g.documents.length} ${isPhotoGroup ? 'photos' : 'docs'}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 2: Category
                  SizedBox(
                    width: 95,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _prettyType(g.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 3: Unit & Tenant
                  Expanded(
                    flex: 3,
                    child: Text(
                      g.unit != null && g.unit!.isNotEmpty
                          ? '${g.unit} (${g.tenant ?? '—'})'
                          : (g.tenant ?? '—'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 4: Upload Date
                  SizedBox(
                    width: 95,
                    child: Text(
                      _formatDate(g.uploadedDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 5: Size
                  SizedBox(
                    width: 65,
                    child: Text(
                      '${g.documents.length} items',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Column 6: Actions
                  SizedBox(
                    width: 60,
                    child: Center(
                      child: IconButton(
                        tooltip: collapsed ? 'Expand group' : 'Collapse group',
                        icon: Icon(
                          collapsed
                              ? Ionicons.chevronDown
                              : Ionicons.chevronUp,
                          size: 14,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                            minWidth: 26, minHeight: 26),
                        onPressed: () {
                          setState(() {
                            if (collapsed) {
                              _collapsedGroups.remove(g.id);
                            } else {
                              _collapsedGroups.add(g.id);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // If expanded, list child documents with seamless nested rows
          if (!collapsed) ...[
            Divider(height: 1, color: borderColor),
            for (final doc in g.documents) ...[
              _buildTableRow(doc, isDark, borderColor, isNested: true),
              if (doc != g.documents.last)
                Divider(
                  height: 1,
                  indent: 78,
                  color: borderColor.withValues(alpha: 0.4),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTableRow(RentDoc d, bool isDark, Color borderColor,
      {bool isNested = false}) {
    final isSelected = d.id == _selectedDocId;
    final expired = _isExpired(d);
    final typeColor = _categoryColor(d.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDocument(d),
        borderRadius: BorderRadius.circular(isNested ? 0 : 8),
        hoverColor: isDark
            ? const Color(0xFF132B2B).withValues(alpha: 0.5)
            : const Color(0xFFEDF7F4).withValues(alpha: 0.6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
                : (isNested
                    ? Colors.transparent
                    : (isDark ? const Color(0xFF091E1F) : Colors.white)),
            borderRadius: isNested ? null : BorderRadius.circular(8),
            border: isNested
                ? null
                : Border.all(
                    color: isSelected ? const Color(0xFF10B981) : borderColor,
                  ),
            boxShadow: isNested
                ? null
                : [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 22),
                    _buildRowThumbnail(d, isDark, borderColor),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Column 1: Document / Name
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.title.isNotEmpty ? d.title : d.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.heading,
                      ),
                    ),
                    if (d.fileName.isNotEmpty && d.fileName != d.title) ...[
                      const SizedBox(height: 1),
                      Text(
                        d.fileName,
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
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Column 2: Category
              SizedBox(
                width: 95,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _prettyType(d.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: typeColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Column 3: Unit & Tenant
              Expanded(
                flex: 3,
                child: Text(
                  d.unit != null && d.unit!.isNotEmpty
                      ? '${d.unit} (${d.tenant ?? '—'})'
                      : (d.tenant ?? '—'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Column 4: Expiry / Upload Date
              SizedBox(
                width: 95,
                child: expired
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Expired',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        d.expiryDate != null && d.expiryDate!.isNotEmpty
                            ? _formatDate(d.expiryDate!)
                            : _formatDate(d.uploadedDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              // Column 5: File Size
              SizedBox(
                width: 65,
                child: Text(
                  d.fileSize.isNotEmpty ? d.fileSize : '—',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Column 6: Actions
              SizedBox(
                width: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Preview Document',
                      icon: const Icon(Ionicons.eyeOutline, size: 13.5),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                          minWidth: 26, minHeight: 26),
                      onPressed: () => _openDocument(d),
                    ),
                    if (widget.onEditDocument != null)
                      IconButton(
                        tooltip: 'Edit Document',
                        icon: const Icon(Ionicons.createOutline, size: 13.5),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                            minWidth: 26, minHeight: 26),
                        onPressed: () => widget.onEditDocument!(d),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDocumentPreviewModal(RentDoc d) {
    final isDark = AppColors.isDark;
    final isImg = _isImage(d.fileUri);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      desktopWidth: 560,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final previewHeight = (screenHeight * 0.42).clamp(280.0, 480.0);

        return AppModalSheet(
          title: d.title.isNotEmpty ? d.title : d.fileName,
          subtitle: d.fileName.isNotEmpty && d.fileName != d.title ? d.fileName : null,
          icon: d.isPdf
              ? Ionicons.documentTextOutline
              : (isImg ? Ionicons.imageOutline : _categoryIcon(d.type)),
          iconColor: const Color(0xFF10B981),
          size: SheetSize.standard,
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview Box
              Container(
                height: previewHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF041011) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: isImg && d.fileUri != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: InteractiveViewer(
                                minScale: 0.8,
                                maxScale: 4.0,
                                child: _buildThumbnailImage(d.fileUri!),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  d.isPdf
                                      ? Ionicons.documentTextOutline
                                      : _categoryIcon(d.type),
                                  size: 64,
                                  color: _categoryColor(d.type),
                                ),
                                const SizedBox(height: 12),
                                if (d.fileUri != null && d.fileUri!.isNotEmpty)
                                  FilledButton.tonalIcon(
                                    onPressed: () => MediaFiles.open(d.fileUri!),
                                    icon: const Icon(Ionicons.openOutline, size: 14),
                                    label: const Text('Open in System App'),
                                  ),
                              ],
                            ),
                    ),
                    if (isImg && d.fileUri != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          onPressed: () => MediaFiles.open(d.fileUri!),
                          icon: const Icon(Ionicons.openOutline, size: 13),
                          label: const Text('Open External', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Metadata details
              _buildInfoRow('Type', _prettyType(d.type).toUpperCase(), isDark),
              if (d.fileSize.isNotEmpty)
                _buildInfoRow('File Size', d.fileSize, isDark),
              _buildInfoRow('Uploaded By', d.uploadedBy, isDark),
              _buildInfoRow('Uploaded Date', _formatDate(d.uploadedDate), isDark),
              if (d.expiryDate != null && d.expiryDate!.isNotEmpty)
                _buildInfoRow(
                  'Expiry Date',
                  _formatDate(d.expiryDate!),
                  isDark,
                  isHighlight: _isExpired(d),
                ),
              if (d.unit != null && d.unit!.isNotEmpty)
                _buildInfoRow('Unit / Apt', d.unit!, isDark),
              if (d.tenant != null && d.tenant!.isNotEmpty)
                _buildInfoRow('Tenant', d.tenant!, isDark),
              if (d.description != null && d.description!.isNotEmpty)
                _buildInfoRow('Description', d.description!, isDark),
            ],
          ),


          footer: Row(
            children: [
              if (d.fileUri != null && d.fileUri!.isNotEmpty) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    MediaFiles.open(d.fileUri!);
                  },
                  icon: const Icon(Ionicons.openOutline, size: 15),
                  label: const Text('Open File',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.heading,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => MediaFiles.share(d.fileUri!),
                  icon: const Icon(Ionicons.shareOutline, size: 15),
                  label: const Text('Share', style: TextStyle(fontSize: 13)),
                ),
              ],
              if (widget.onEditDocument != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.heading,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onEditDocument?.call(d);
                  },
                  icon: const Icon(Ionicons.pencilOutline, size: 15),
                  label: const Text('Edit', style: TextStyle(fontSize: 13)),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Delete File',
                icon: const Icon(Ionicons.trashOutline, size: 16, color: Color(0xFFEF4444)),
                style: IconButton.styleFrom(
                  side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDelete(d);
                },
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                color: isHighlight
                    ? const Color(0xFFEF4444)
                    : (AppColors.heading),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailImage(String path, {double iconSize = 36}) {
    if (path.startsWith('http') || path.startsWith('content://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Ionicons.imageOutline, size: iconSize, color: Colors.grey),
      );
    }
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(
        f,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Ionicons.imageOutline, size: iconSize, color: Colors.grey),
      );
    }
    return Icon(Ionicons.imageOutline, size: iconSize, color: Colors.grey);
  }

  Widget _buildFileTypeFilterChip(
      String key, String label, bool isDark, Color borderColor) {
    final isSelected = _fileTypeFilter == key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _fileTypeFilter = key),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF132B2B) : const Color(0xFFEDF7F4))
                : (isDark
                    ? const Color(0xFF0C2424).withValues(alpha: 0.5)
                    : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : (isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.10)
                      : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortSelector(
      bool isDark, Color borderColor, bool isCompactSort) {
    const sortOptions = [
      ('newest', 'Newest First', 'Newest', Ionicons.timeOutline, Color(0xFF10B981)),
      ('oldest', 'Oldest First', 'Oldest', Ionicons.hourglassOutline, Color(0xFF3B82F6)),
      ('name', 'Name (A-Z)', 'Name', Ionicons.textOutline, Color(0xFF8B5CF6)),
      ('expiry', 'Expiry Date', 'Expiry', Ionicons.calendarOutline, Color(0xFFF59E0B)),
    ];

    final current = sortOptions.firstWhere(
      (opt) => opt.$1 == _sortBy,
      orElse: () => sortOptions.first,
    );

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0C2424)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.12)
              : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current.$1,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor:
              isDark ? const Color(0xFF0F2627) : Colors.white,
          icon: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Ionicons.chevronDown,
              size: 11.5,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.heading,
          ),
          onChanged: (v) {
            if (v != null) {
              setState(() => _sortBy = v);
            }
          },
          selectedItemBuilder: (context) {
            return sortOptions.map((opt) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    opt.$4,
                    size: 12.5,
                    color: opt.$5,
                  ),
                  const SizedBox(width: 5),
                  if (!isCompactSort) ...[
                    Text(
                      'Sort: ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                  Text(
                    isCompactSort ? opt.$3 : opt.$2,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ],
              );
            }).toList();
          },
          items: sortOptions.map((opt) {
            final isSelected = opt.$1 == _sortBy;
            return DropdownMenuItem<String>(
              value: opt.$1,
              child: Row(
                children: [
                  Icon(opt.$4, size: 13.5, color: opt.$5),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                            : (AppColors.heading),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Ionicons.checkmark,
                      size: 13.5,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVaultHealthCard(List<RentDoc> allDocs,
      List<RentDoc> expiredDocs, bool isDark, Color borderColor) {
    final pdfCount = allDocs.where((d) => d.isPdf).length;
    final imgCount = allDocs.where((d) => _isImage(d.fileUri)).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF091E1F)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Ionicons.shieldCheckmarkOutline,
                size: 13,
                color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
              ),
              const SizedBox(width: 6),
              Text(
                'VAULT OVERVIEW',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Total Files',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  ),
                ),
              ),
              Text(
                '${allDocs.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'PDFs / Images',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$pdfCount / $imgCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          if (expiredDocs.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _selectedCategory = 'expired'),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Ionicons.alertCircle, size: 12, color: Color(0xFFEF4444)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${expiredDocs.length} Expired Documents',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
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

  String _formatDate(String s) {
    if (s.isEmpty) return '—';
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }
}
