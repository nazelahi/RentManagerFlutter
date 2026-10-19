import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/wave_animation.dart';
import '../../services/auto_deduplication_service.dart';
import '../desktop/desktop_documents_view.dart';

/// Port of `src/screens/DocumentsScreen.tsx` — strict 1:1:
/// inline header (sync/search/add), stats, expired alert, expandable search
/// with suggestions, category tabs + dedicated category page, grouped +
/// individual grid docs, bulk Add Document modal, viewer, edit, group
/// carousel/edit, category manager and tenant document sync.
class DocumentsView extends ConsumerStatefulWidget {
  static final globalKey = GlobalKey<_DocumentsViewState>();
  const DocumentsView({super.key});

  static void showAddModal(BuildContext context) {
    globalKey.currentState?._bulkUpload();
  }

  static void showEditModal(BuildContext context, RentDoc doc) {
    globalKey.currentState?._editDocument(doc);
  }

  static void showViewModal(BuildContext context, RentDoc doc) {
    globalKey.currentState?._openDoc(doc);
  }

  static void showSyncModal(BuildContext context) {
    globalKey.currentState?._tenantSyncModal();
  }

  @override
  ConsumerState<DocumentsView> createState() => _DocumentsViewState();
}

String _prettyType(String t) {
  if (t.isEmpty) return t;
  if (t == 'id-card') return 'ID Card';
  final s = t.replaceAll('-', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

Color _hexColor(String? hex, [Color? fallback]) {
  final fb = fallback ?? AppColors.iconSecondary;
  if (hex == null || hex.isEmpty) return fb;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  try {
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return fb;
  }
}

Color _typeColor(String t) => _hexColor(kDocTypeColors[t], AppColors.primary);

Color _statusColor(String s) =>
    _hexColor(kDocStatusColors[s.toLowerCase()], AppColors.primary);

IconData _iconFromName(String? name) {
  switch (name) {
    case 'document':
      return Icons.insert_drive_file_outlined;
    case 'document-text':
      return Icons.description_outlined;
    case 'receipt':
    case 'receipt-outline':
      return Icons.receipt_outlined;
    case 'build':
      return Icons.handyman_outlined;
    case 'shield':
      return Icons.shield_outlined;
    case 'shield-checkmark':
      return Icons.verified_user_outlined;
    case 'umbrella':
      return Icons.umbrella_outlined;
    case 'checkmark-circle':
      return Icons.check_circle_outline;
    case 'search':
      return Icons.search;
    case 'megaphone':
      return Icons.campaign_outlined;
    case 'card':
      return Icons.badge_outlined;
    case 'folder':
      return Icons.folder_outlined;
    case 'library':
      return Icons.collections_bookmark_outlined;
    case 'business':
      return Icons.business_outlined;
    case 'home':
      return Icons.home_outlined;
    case 'car':
      return Icons.directions_car_outlined;
    case 'medical':
      return Icons.medical_services_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'calculator':
      return Icons.calculate_outlined;
    case 'flash':
      return Icons.bolt_outlined;
    case 'sparkles':
      return Icons.auto_awesome_outlined;
    case 'construct':
      return Icons.handyman_outlined;
    case 'notifications':
      return Icons.notifications_outlined;
    case 'id-card':
      return Icons.badge_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

IconData _typeIcon(String t) => _iconFromName(kDocTypeIcons[t]);

bool _isImageUri(String? u) =>
    u != null &&
    RegExp(r'\.(png|jpg|jpeg|gif|webp)$', caseSensitive: false).hasMatch(u);

Color _contrastOn(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

const _kColorSwatches = <String>[
  '#FF6B6B',
  '#4ECDC4',
  '#45B7D1',
  '#96CEB4',
  '#FFEAA7',
  '#DDA0DD',
  '#98D8C8',
  '#F7DC6F',
  '#BB8FCE',
  '#85C1E9',
  '#F8C471',
  '#A9A9A9',
  '#FF9F43',
  '#6C5CE7',
  '#00B894',
  '#E17055',
  '#81ECEC',
  '#FDCB6E',
  '#E84393',
  '#2D3436',
];

const _kIconNames = <String>[
  'document',
  'document-text',
  'receipt',
  'build',
  'shield',
  'umbrella',
  'checkmark-circle',
  'search',
  'megaphone',
  'card',
  'folder',
  'library',
  'business',
  'home',
  'car',
  'medical',
  'restaurant',
  'calculator',
  'flash',
  'sparkles',
];

class _DocumentsViewState extends ConsumerState<DocumentsView> {
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _searchQuery = '';
  bool _isSearchExpanded = false;
  bool _isSearchFocused = false;
  bool _showSearchSuggestions = false;
  String? _selectedCategoryForView;
  final Set<String> _collapsed = {};

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
    _searchFocus.dispose();
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

  // ---- filtering ----
  bool _isExpired(RentDoc d) {
    if (d.status == 'expired') return true;
    final expiry = DateTime.tryParse(d.expiryDate?.trim() ?? '');
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  bool _matches(String q, RentDoc d) {
    final lq = q.toLowerCase();
    return d.title.toLowerCase().contains(lq) ||
        (d.description ?? '').toLowerCase().contains(lq) ||
        d.type.toLowerCase().contains(lq) ||
        (d.unit ?? '').toLowerCase().contains(lq) ||
        (d.tenant ?? '').toLowerCase().contains(lq) ||
        d.tags.any((t) => t.toLowerCase().contains(lq)) ||
        d.fileName.toLowerCase().contains(lq);
  }

  List<RentDoc> _filteredDocs(AppDataState s) {
    final list =
        s.scopedDocuments
            .where((d) => _searchQuery.isEmpty || _matches(_searchQuery, d))
            .toList()
          ..sort((a, b) => b.uploadedDate.compareTo(a.uploadedDate));
    return list;
  }

  List<String> _suggestions(List<RentDoc> docs) {
    if (_searchQuery.isEmpty) return [];
    final set = <String>{};
    for (final d in _filterDocsAll(docs)) {
      set.add(_prettyType(d.type));
      if (d.unit != null && d.unit!.isNotEmpty) set.add(d.unit!);
      if (d.tenant != null && d.tenant!.isNotEmpty) set.add(d.tenant!);
      set.addAll(d.tags);
      final dot = d.fileName.lastIndexOf('.');
      if (dot > 0) {
        final ext = d.fileName.substring(dot + 1).toLowerCase();
        if (ext.isNotEmpty) set.add(ext);
      }
    }
    final q = _searchQuery.toLowerCase();
    final out = set.where((x) => x.toLowerCase().contains(q)).toList()..sort();
    return out.take(5).toList();
  }

  List<RentDoc> _filterDocsAll(List<RentDoc> docs) {
    if (_searchQuery.isEmpty) return docs;
    return docs.where((d) => _matches(_searchQuery, d)).toList();
  }

  ({List<DocumentGroup> groups, List<RentDoc> individual}) _organize(
    AppDataState s,
    List<RentDoc> docs,
  ) {
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
      list.sort((a, b) => b.uploadedDate.compareTo(a.uploadedDate));
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
      groups.add(
        DocumentGroup(
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
        ),
      );
    });
    groups.sort((a, b) {
      final da = a.documents.isEmpty ? '' : a.documents.first.uploadedDate;
      final db = b.documents.isEmpty ? '' : b.documents.first.uploadedDate;
      return db.compareTo(da);
    });
    return (groups: groups, individual: individual);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopDocumentsView(
        onAddDocument: () => _bulkUpload(),
        onEditDocument: (d) => _editDocument(d),
        onViewDocument: (d) => _openDoc(d),
        onSyncTenantDocs: () => _tenantSyncModal(),
      );
    }

    final s = ref.watch(appDataProvider);
    final filtered = _filteredDocs(s);
    final expiredCount = s.scopedDocuments.where(_isExpired).length;
    final leaseCount = s.scopedDocuments.where((d) => d.type == 'lease').length;
    final idCardCount = s.scopedDocuments
        .where((d) => d.type == 'id-card')
        .length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: AppColors.isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: AppColors.isDark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: Column(
            children: [
              _buildHeader(context, s),
              Expanded(
                child: PullToRefresh(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      if (_isSearchExpanded) _buildSearch(filtered),
                      _buildStats(
                        s,
                        s.scopedDocuments.length,
                        leaseCount,
                        idCardCount,
                      ),
                      if (expiredCount > 0) _buildExpiredAlert(expiredCount),
                      _buildCategoryTabs(s, filtered),
                      if (_wave)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: WaveAnimation(
                            count: 6,
                            icon: Icons.description_outlined,
                          ),
                        )
                      else if (_selectedCategoryForView != null)
                        _buildCategoryPage(s, filtered)
                      else
                        _buildAllDocs(s, filtered),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppDataState s) {
    final tenants = s.scopedTenants;
    final total = s.scopedDocuments.length;
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
          // Left: Documents Icon Badge
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
                      Icons.description_rounded,
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
                      'Documents',
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

          // Right: Action buttons (Tenant sync if available, Search, Add)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tenants.isNotEmpty) ...[
                _headerBtn(
                  icon: Icons.cloud_upload_outlined,
                  isDark: isDark,
                  onTap: () => _tenantSyncModal(),
                ),
                const SizedBox(width: 6),
              ],
              _headerBtn(
                icon: _isSearchExpanded
                    ? Icons.close_rounded
                    : Icons.search_rounded,
                isDark: isDark,
                isActive: _isSearchExpanded,
                onTap: _toggleSearch,
              ),
              const SizedBox(width: 6),
              _headerBtn(
                icon: Icons.add_rounded,
                isDark: isDark,
                isAdd: true,
                onTap: () => _bulkUpload(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerBtn({
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
      if (_isSearchExpanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      } else {
        _searchQuery = '';
        _searchCtl.clear();
        _showSearchSuggestions = false;
        _isSearchFocused = false;
        _searchFocus.unfocus();
      }
    });
  }

  // ===================== Search =====================
  Widget _buildSearch(List<RentDoc> docs) {
    final suggestions = _suggestions(docs);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isSearchFocused ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  Icons.search,
                  size: 18,
                  color: _isSearchFocused
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    focusNode: _searchFocus,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _showSearchSuggestions = v.isNotEmpty;
                    }),
                    onTap: () => setState(() {
                      _isSearchFocused = true;
                      _showSearchSuggestions = _searchQuery.isNotEmpty;
                    }),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.cancel,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() {
                      _searchQuery = '';
                      _searchCtl.clear();
                      _showSearchSuggestions = false;
                    }),
                  ),
              ],
            ),
          ),
          if (_showSearchSuggestions && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceHover,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: suggestions
                    .map(
                      (sug) => InkWell(
                        onTap: () => setState(() {
                          _searchQuery = sug;
                          _searchCtl.text = sug;
                          _showSearchSuggestions = false;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
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
                                  sug,
                                  style: TextStyle(color: AppColors.text),
                                ),
                              ),
                              Text(
                                '${docs.where((d) => _matches(sug, d)).length}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
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
  }

  // ===================== Stats =====================
  Widget _buildStats(AppDataState s, int total, int leases, int idCards) {
    final loading = s.isLoading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: [
          _statCard('Total Files', loading ? '...' : '$total', Icons.folder),
          const SizedBox(width: 8),
          _statCard('Leases', loading ? '...' : '$leases', Icons.description),
          const SizedBox(width: 8),
          _statCard(
            'ID Cards',
            loading ? '...' : '$idCards',
            Icons.badge_outlined,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        gradient: AppColors.isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ===================== Expired alert =====================
  Widget _buildExpiredAlert(int n) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error.withValues(alpha: 0.2),
            AppColors.error.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          Text(
            '$n document${n > 1 ? 's' : ''} have expired',
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  // ===================== Category tabs =====================
  Widget _buildCategoryTabs(AppDataState s, List<RentDoc> filtered) {
    final cats = s.documentCategories
        .where((c) => _countCategory(filtered, c.type) > 0)
        .toList();
    if (cats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Text(
          'No documents found. Upload your first document to see categories here.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: cats.map((cat) {
          final active = _selectedCategoryForView == cat.type;
          final count = _countCategory(filtered, cat.type);
          final color = _hexColor(cat.color, _typeColor(cat.type));
          return GestureDetector(
            onTap: () => _switchCategory(cat.type),
            onLongPress: () {
              _bulkUpload(initialType: cat.type);
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: active
                      ? [
                          AppColors.primary.withValues(alpha: 0.3),
                          AppColors.primaryDark.withValues(alpha: 0.2),
                        ]
                      : [AppColors.surface, AppColors.surface],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: active ? AppColors.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFromName(cat.icon),
                      size: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        '$count files',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  int _countCategory(List<RentDoc> filtered, String type) =>
      filtered.where((d) => d.type == type).length;

  void _switchCategory(String type) {
    setState(() {
      _selectedCategoryForView = _selectedCategoryForView == type ? null : type;
    });
    _flashWave();
  }

  // ===================== All docs =====================
  Widget _emptyDocumentsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    final isDark = AppColors.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.07)
                : const Color(0xFFE2E8F0),
            width: 0.8,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Icon(icon, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===================== All docs =====================
  Widget _buildAllDocs(AppDataState s, List<RentDoc> filtered) {
    final org = _organize(s, filtered);
    final hasContent = org.groups.isNotEmpty || org.individual.isNotEmpty;
    if (!hasContent) {
      final isSearching = _searchQuery.isNotEmpty;
      return _emptyDocumentsCard(
        icon: isSearching
            ? Icons.search_off_rounded
            : Icons.description_outlined,
        title: isSearching ? 'No Matching Documents' : 'No Documents Found',
        subtitle: isSearching
            ? 'No documents match "$_searchQuery". Try a different search term.'
            : 'Start by uploading your first document using the + button above.',
        onAction: isSearching ? null : () => _bulkUpload(),
        actionLabel: isSearching ? null : 'Upload Document',
      );
    }
    return Column(
      children: [
        ...org.groups.map(_groupCard),
        if (org.individual.isNotEmpty) _individualGrid(org.individual),
      ],
    );
  }

  Widget _buildCategoryPage(AppDataState s, List<RentDoc> filtered) {
    final type = _selectedCategoryForView!;
    final docs = filtered.where((d) => d.type == type).toList();
    final org = _organize(s, docs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategoryForView = null;
                  });
                  _flashWave();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.arrow_back,
                    size: 14,
                    color: AppColors.icon,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(_typeIcon(type), size: 28, color: _typeColor(type)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_prettyType(type)} Documents',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      '${docs.length} documents',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _bulkUpload(initialType: type),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentDark.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.cloud_upload,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _bulkUpload(initialType: type),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.add, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        if (docs.isEmpty)
          _emptyDocumentsCard(
            icon: _searchQuery.isNotEmpty
                ? Icons.search_off_rounded
                : _typeIcon(type),
            title: _searchQuery.isNotEmpty
                ? 'No Matching ${_prettyType(type)} Documents'
                : 'No ${_prettyType(type)} Documents Found',
            subtitle: _searchQuery.isNotEmpty
                ? 'No ${_prettyType(type)} documents match "$_searchQuery".'
                : 'Start by uploading your first ${_prettyType(type)} document to this category.',
            onAction: () => _bulkUpload(initialType: type),
            actionLabel: 'Upload ${_prettyType(type)}',
          )
        else ...[
          ...org.groups.map(_groupCard),
          if (org.individual.isNotEmpty) _individualGrid(org.individual),
        ],
      ],
    );
  }

  Widget _individualGrid(List<RentDoc> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();
    if (docs.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: _singleDocCard(docs.first),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: docs.length,
      itemBuilder: (_, i) => _individualCard(docs[i]),
    );
  }

  Widget _singleDocCard(RentDoc d) => GestureDetector(
    onTap: () => _openDoc(d),
    onLongPress: () {
      AppHaptics.medium();
      _docMenu(d);
    },
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        gradient: AppColors.isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.07)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: _isImageUri(d.fileUri)
                  ? _fileImage(d.fileUri!, fit: BoxFit.cover)
                  : _docPreviewBadge(d),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.title.isEmpty ? 'Untitled Document' : d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chip(
                      _typeIcon(d.type),
                      _typeColor(d.type),
                      _prettyType(d.type),
                    ),
                    if (d.unit?.isNotEmpty == true)
                      _chip(
                        Icons.home_outlined,
                        AppColors.primary,
                        'Unit ${d.unit}',
                      ),
                    if (d.fileSize.isNotEmpty)
                      _chip(
                        Icons.folder_outlined,
                        AppColors.textSecondary,
                        d.fileSize,
                      ),
                    _chip(
                      Icons.calendar_today_outlined,
                      AppColors.textSecondary,
                      d.uploadedDate,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _docMenu(d),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.more_vert,
                size: 18,
                color: AppColors.iconSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _docPreviewBadge(RentDoc d) {
    final ext = (d.fileUri ?? d.fileName).split('.').last.toLowerCase();
    IconData icon = _typeIcon(d.type);
    Color color = _typeColor(d.type);
    String badge = _prettyType(d.type);
    if (d.isPdf || ext == 'pdf') {
      icon = Icons.picture_as_pdf_rounded;
      color = const Color(0xFFFF6B6B);
      badge = 'PDF';
    } else if (ext == 'doc' || ext == 'docx') {
      icon = Icons.description_rounded;
      color = const Color(0xFF2196F3);
      badge = 'DOC';
    }
    return Container(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: color),
            const SizedBox(height: 2),
            Text(
              badge.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _individualCard(RentDoc d) => GestureDetector(
    onTap: () => _openDoc(d),
    onLongPress: () {
      AppHaptics.medium();
      _docMenu(d);
    },
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        gradient: AppColors.isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.07)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _isImageUri(d.fileUri)
                      ? ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: _fileImage(d.fileUri!, fit: BoxFit.cover),
                        )
                      : ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: _docPreviewBadge(d),
                        ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(d.status),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.title.isEmpty ? 'Untitled Document' : d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _prettyType(d.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (d.unit?.isNotEmpty == true)
                      Text(
                        'Unit ${d.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.uploadedDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (d.fileSize.isNotEmpty)
                      Text(
                        d.fileSize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
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
  );

  Widget _fileImage(String uri, {BoxFit fit = BoxFit.cover}) {
    final remote = uri.startsWith('http') || uri.startsWith('content://');
    if (!remote && !_isImageUri(uri)) return _fileGlyph(uri);
    Widget fallback() => _fileGlyph(uri);
    if (remote) {
      return Image.network(
        uri,
        fit: fit,
        errorBuilder: (_, _, _) => fallback(),
      );
    }
    final f = File(uri);
    if (f.existsSync()) {
      return Image.file(f, fit: fit, errorBuilder: (_, _, _) => fallback());
    }
    return fallback();
  }

  Widget _fileGlyph(String uri) {
    final ext = uri.split('.').last.toLowerCase();
    IconData ic = Icons.insert_drive_file_outlined;
    Color col = AppColors.primary;
    if (ext == 'pdf') {
      ic = Icons.picture_as_pdf;
      col = const Color(0xFFFF6B6B);
    } else if (ext == 'doc' || ext == 'docx') {
      ic = Icons.description;
      col = const Color(0xFF2196F3);
    }
    return Container(
      color: AppColors.surface,
      child: Center(child: Icon(ic, color: col, size: 40)),
    );
  }

  // ===================== Group card =====================
  Widget _groupCard(DocumentGroup g) {
    final multi = g.documents.length > 1;
    final collapsed = multi && _collapsed.contains(g.id);
    final isPhotoGroup =
        g.documents.isNotEmpty &&
        g.documents.every((d) => _isImageUri(d.fileUri));
    final thumbs = g.documents.take(4).map((d) => d.fileUri).toList();
    final typeColor = _typeColor(g.type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.isDark ? null : AppColors.cardBackground,
          gradient: AppColors.isDark
              ? LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.isDark
                ? const Color.fromRGBO(255, 255, 255, 0.07)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                if (!multi && g.documents.isNotEmpty) {
                  _openDoc(g.documents.first);
                } else if (isPhotoGroup) {
                  _groupCarousel(g);
                } else if (multi) {
                  setState(() {
                    if (collapsed) {
                      _collapsed.remove(g.id);
                    } else {
                      _collapsed.add(g.id);
                    }
                  });
                }
              },
              onLongPress: () {
                AppHaptics.medium();
                _groupMenu(g);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _typeIcon(g.type),
                        size: 20,
                        color: typeColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            '${g.documents.length} ${isPhotoGroup ? 'photo' : 'document'}${g.documents.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (isPhotoGroup && thumbs.isNotEmpty && collapsed)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  ...thumbs.map(
                                    (u) => Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: u == null
                                              ? ColoredBox(
                                                  color: AppColors.surface,
                                                )
                                              : _fileImage(
                                                  u,
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (g.documents.length > 4)
                                    Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '+${g.documents.length - 4}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              _chip(
                                Icons.calendar_today_outlined,
                                AppColors.primary,
                                g.uploadedDate,
                              ),
                              if (g.unit?.isNotEmpty == true)
                                _chip(
                                  Icons.home_outlined,
                                  AppColors.info,
                                  'Unit ${g.unit}',
                                ),
                              if (g.tenant?.isNotEmpty == true)
                                _chip(
                                  Icons.person_outline,
                                  AppColors.accentDark,
                                  g.tenant!,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _groupMenu(g),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: AppColors.iconSecondary,
                        ),
                      ),
                    ),
                    if (multi)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: AnimatedRotation(
                          turns: collapsed ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 18,
                            color: AppColors.icon,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.iconSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (g.description?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  g.description!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            if (!collapsed) _groupDocRow(g),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(
        text,
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  );

  Widget _groupDocRow(DocumentGroup g) {
    if (g.documents.isEmpty) return const SizedBox.shrink();
    final isSingle = g.documents.length == 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colCount = isSingle ? 1 : (constraints.maxWidth > 500 ? 3 : 2);
          final spacing = 8.0;
          final itemWidth = isSingle
              ? constraints.maxWidth
              : (constraints.maxWidth - (colCount - 1) * spacing) / colCount;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: g.documents.map((d) {
              return SizedBox(
                width: itemWidth,
                child: _groupDocItem(d, isSingle: isSingle),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _groupDocItem(RentDoc d, {required bool isSingle}) => GestureDetector(
    onTap: () => _openDoc(d),
    onLongPress: () {
      AppHaptics.medium();
      _docMenu(d);
    },
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        gradient: AppColors.isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.07)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: isSingle ? 42 : 36,
              height: isSingle ? 42 : 36,
              child: _isImageUri(d.fileUri)
                  ? _fileImage(d.fileUri!, fit: BoxFit.cover)
                  : _docPreviewBadge(d),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.title.isEmpty ? 'Untitled Document' : d.title,
                  maxLines: isSingle ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (d.fileSize.isNotEmpty) ...[
                      Text(
                        d.fileSize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        d.uploadedDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isSingle) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: AppColors.iconSecondary),
          ],
        ],
      ),
    ),
  );

  // ===================== Long-press menu =====================
  void _docMenu(RentDoc d) {
    showAdaptiveModalSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppModalSheet(
        title: 'Document Actions',
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d.fileUri?.isNotEmpty == true) ...[
              ListTile(
                leading: const Icon(
                  Icons.open_in_new,
                  color: AppColors.primary,
                ),
                title: Text(
                  'Open File',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  MediaFiles.open(d.fileUri!);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.share_outlined,
                  color: AppColors.iconSecondary,
                ),
                title: Text(
                  'Share',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  MediaFiles.share(d.fileUri!);
                },
              ),
            ],
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editDocument(d);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteDocument(d);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _groupMenu(DocumentGroup g) {
    showAdaptiveModalSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppModalSheet(
        title: 'Group Actions',
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: AppColors.iconSecondary,
              ),
              title: Text(
                'Edit Group',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _editGroup(g);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete Group',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteGroup(g);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteDocument(RentDoc d) {
    final n = ref.read(appDataProvider.notifier);
    n.trashDocument(d.id);
    showAppToast(
      context,
      '${d.title.isEmpty ? "Document" : d.title} moved to trash',
      actionLabel: 'Undo',
      onAction: () => n.restoreDocument(d.id),
    );
  }

  void _deleteGroup(DocumentGroup g) async {
    final ok = await confirmDialog(
      context,
      'Delete Group',
      'Are you sure you want to delete this document group? This action cannot be undone.',
    );
    if (!ok) return;
    final n = ref.read(appDataProvider.notifier);
    for (final d in g.documents) {
      n.deleteDocument(d.id);
    }
    n.deleteDocumentGroup(g.id);
  }

  // ===================== Open / viewer =====================
  void _openDoc(RentDoc d) {
    if (_isImageUri(d.fileUri)) {
      _imageViewer(d);
    } else {
      _viewer(d);
    }
  }

  void _viewer(RentDoc d) {
    final isImg = _isImageUri(d.fileUri);
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final previewHeight = (screenHeight * 0.38).clamp(280.0, 440.0);

        return AppModalSheet(
          title: d.title.isEmpty ? 'Document Details' : d.title,
          icon: Icons.description_outlined,
          iconColor: AppColors.primary,
          size: SheetSize.standard,
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (isImg) {
                    _fullScreenImage(d);
                  } else if (d.fileUri?.isNotEmpty == true) {
                    MediaFiles.open(d.fileUri!);
                  }
                },
                child: Container(
                  height: previewHeight,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.07)
                          : AppColors.border,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: isImg
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 3,
                                  child: _fileImage(
                                    d.fileUri!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      d.isPdf
                                          ? Icons.picture_as_pdf_rounded
                                          : _typeIcon(d.type),
                                      size: 64,
                                      color: d.isPdf
                                          ? const Color(0xFFFF6B6B)
                                          : _typeColor(d.type),
                                    ),
                                    if (d.fileUri?.isNotEmpty == true) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.open_in_new,
                                              size: 14,
                                              color: AppColors.primary,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Tap to Open Document',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                      if (isImg)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_full,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Full Screen',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _metaRow(
                'Type',
                _prettyType(d.type).toUpperCase(),
                Icons.description,
              ),
              if (d.fileSize.isNotEmpty)
                _metaRow('File Size', d.fileSize, Icons.folder_outlined),
              _metaRow('Uploaded by', d.uploadedBy, Icons.person_outline),
              _metaRow('Uploaded', d.uploadedDate, Icons.schedule),
              if (d.unit?.isNotEmpty == true)
                _metaRow('Unit', d.unit!, Icons.home_outlined),
              if (d.tenant?.isNotEmpty == true)
                _metaRow('Tenant', d.tenant!, Icons.person),
              if (d.description?.isNotEmpty == true)
                _metaRow('Description', d.description!, Icons.notes),
            ],
          ),
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (d.fileUri?.isNotEmpty == true) ...[
                    _viewerAction(
                      Icons.open_in_new,
                      AppColors.primary,
                      'Open',
                      () => MediaFiles.open(d.fileUri!),
                    ),
                    _viewerAction(
                      Icons.share_outlined,
                      AppColors.info,
                      'Share',
                      () => MediaFiles.share(d.fileUri!),
                    ),
                  ],
                  _viewerAction(
                    Icons.edit_outlined,
                    AppColors.accentDark,
                    'Edit',
                    () {
                      Navigator.pop(ctx);
                      _editDocument(d);
                    },
                  ),
                  _viewerAction(
                    Icons.delete_outline,
                    const Color(0xFFF44336),
                    'Delete',
                    () {
                      Navigator.pop(ctx);
                      _deleteDocument(d);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SheetActions(
                primaryLabel: 'Close',
                onPrimary: () {
                  Navigator.pop(ctx);
                },
                cancelLabel: '',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metaRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: AppColors.text, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _viewerAction(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    ),
  );
  void _imageViewer(RentDoc d) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final previewHeight = (screenHeight * 0.62).clamp(400.0, 680.0);

        return AppModalSheet(
          title: d.title.isEmpty ? 'Image Preview' : d.title,
          icon: Icons.image,
          iconColor: AppColors.primary,
          size: SheetSize.standard,
          scrollable: false,
          body: SizedBox(
            height: previewHeight,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: _fileImage(d.fileUri!, fit: BoxFit.contain),
              ),
            ),
          ),
          footer: Row(
            children: [
              _viewerAction(
                Icons.open_in_full,
                AppColors.icon,
                'Full Screen',
                () {
                  Navigator.pop(ctx);
                  _fullScreenImage(d);
                },
              ),
              _viewerAction(
                Icons.download_outlined,
                AppColors.icon,
                'Save / Share',
                () => MediaFiles.share(d.fileUri!),
              ),
              _viewerAction(Icons.info_outline, AppColors.icon, 'Details', () {
                Navigator.pop(ctx);
                _viewer(d);
              }),
            ],
          ),
        );
      },
    );
  }

  void _fullScreenImage(RentDoc d) {
    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: _fileImage(d.fileUri!, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== Group carousel =====================
  void _groupCarousel(DocumentGroup g) {
    final images = g.documents.where((d) => _isImageUri(d.fileUri)).toList();
    int index = 0;
    final pageCtl = PageController();
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final carouselHeight = (screenHeight * 0.55).clamp(360.0, 600.0);

        return StatefulBuilder(
          builder: (ctx, setS) => AppModalSheet(
            title: g.title.isEmpty ? 'Group Images' : g.title,
            icon: Icons.collections,
            iconColor: AppColors.primary,
            size: SheetSize.standard,
            scrollable: true,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (images.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: EmptyState(
                      icon: Icons.collections_outlined,
                      title: 'No Images',
                      subtitle: "This group doesn't contain any images yet.",
                    ),
                  )
                else ...[
                  SizedBox(
                    height: carouselHeight,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: pageCtl,
                          itemCount: images.length,
                          onPageChanged: (i) => setS(() => index = i),
                          itemBuilder: (_, i) {
                            final doc = images[i];
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: InteractiveViewer(
                                      minScale: 0.8,
                                      maxScale: 4,
                                      child: _fileImage(
                                        doc.fileUri!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          doc.title,
                                          maxLines: 2,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '${i + 1} of ${images.length}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Row(
                                    children: [
                                      _carouselIcon(Icons.edit, () {
                                        Navigator.pop(ctx);
                                        _editDocument(doc);
                                      }),
                                      const SizedBox(width: 8),
                                      _carouselIcon(
                                        Icons.delete,
                                        () => _deleteDocument(doc),
                                        danger: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        if (images.length > 1) ...[
                          _navBtn(Icons.chevron_left, index == 0, () {
                            if (index > 0) {
                              pageCtl.previousPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.ease,
                              );
                            }
                          }, left: true),
                          _navBtn(
                            Icons.chevron_right,
                            index == images.length - 1,
                            () {
                              if (index < images.length - 1) {
                                pageCtl.nextPage(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.ease,
                                );
                              }
                            },
                            left: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.collections,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          Text(
                            '${images.length}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(
                            Icons.description,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          Text(
                            '${g.documents.length}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (g.description?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            g.description!,
                            maxLines: 2,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _pillAction(Icons.edit, AppColors.primary, 'Edit Group', () {
                  Navigator.pop(ctx);
                  _editGroup(g);
                }),
                const SizedBox(width: 8),
                _pillAction(
                  Icons.delete,
                  const Color(0xFFF44336),
                  'Delete Group',
                  () {
                    Navigator.pop(ctx);
                    _deleteGroup(g);
                  },
                  danger: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _carouselIcon(
    IconData icon,
    VoidCallback onTap, {
    bool danger = false,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: danger
            ? AppColors.error.withValues(alpha: 0.8)
            : Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    ),
  );

  Widget _navBtn(
    IconData icon,
    bool disabled,
    VoidCallback onTap, {
    required bool left,
  }) => Positioned(
    top: 100,
    left: left ? 8 : null,
    right: left ? null : 8,
    child: InkWell(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: disabled ? 0.3 : 0.7),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: disabled ? AppColors.textMuted : Colors.white,
        ),
      ),
    ),
  );

  Widget _pillAction(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );

  // ===================== Edit group =====================
  void _editGroup(DocumentGroup g) {
    final s = ref.read(appDataProvider);
    final title = TextEditingController(text: g.title);
    final desc = TextEditingController(text: g.description ?? '');
    String type = g.type;
    final combined = TextEditingController(
      text: (g.tenant?.isNotEmpty == true && g.unit?.isNotEmpty == true)
          ? '${g.tenant} - ${g.unit}'
          : (g.tenant ?? g.unit ?? ''),
    );
    final newImages = <String>[];
    final removedIds = <String>[];
    final hasTenantImages = g.documents.any(
      (d) => d.tags.contains('tenant-document'),
    );

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AppModalSheet(
          title: 'Edit Group',
          icon: Icons.folder_outlined,
          iconColor: AppColors.primary,
          size: SheetSize.standard,
          avoidBottomInset: true,
          scrollable: true,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppField(label: 'Group Title *', controller: title),
              const _Label('Group Type'),
              DropdownButtonFormField<String>(
                initialValue: kDocTypes.contains(type)
                    ? type
                    : (kDocTypes.isNotEmpty ? kDocTypes.first : null),
                isExpanded: true,
                dropdownColor: AppColors.dropdownBackground,
                items: kDocTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(_prettyType(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setS(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              _Label(
                hasTenantImages
                    ? 'Tenant & Unit (Optional) - Disabled due to tenant images'
                    : 'Tenant & Unit (Optional)',
              ),
              Builder(
                builder: (context) {
                  final tenantUnitOptions = <String>{};
                  final tenantUnitItems = <String>[''];
                  for (final t in s.scopedTenants) {
                    final label = '${t.name} - ${t.unit}';
                    if (label.trim().isNotEmpty &&
                        tenantUnitOptions.add(label)) {
                      tenantUnitItems.add(label);
                    }
                  }
                  if (combined.text.isNotEmpty &&
                      !tenantUnitOptions.contains(combined.text)) {
                    tenantUnitItems.add(combined.text);
                  }
                  final selectedTenantValue =
                      tenantUnitItems.contains(combined.text)
                      ? combined.text
                      : '';

                  return DropdownButtonFormField<String>(
                    initialValue: selectedTenantValue,
                    isExpanded: true,
                    dropdownColor: AppColors.dropdownBackground,
                    decoration: InputDecoration(
                      enabled: !hasTenantImages,
                      hintText: 'Select Tenant & Unit (Optional)',
                    ),
                    items: tenantUnitItems
                        .map(
                          (val) => DropdownMenuItem(
                            value: val,
                            child: Text(val.isEmpty ? 'None' : val),
                          ),
                        )
                        .toList(),
                    onChanged: hasTenantImages
                        ? null
                        : (v) => setS(() => combined.text = v ?? ''),
                  );
                },
              ),
              const SizedBox(height: 12),
              AppField(
                label: 'Description (Optional)',
                controller: desc,
                maxLines: 3,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Manage Images',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            final paths =
                                await MediaPicker.pickMultipleImages();
                            if (paths.isNotEmpty) {
                              setS(() => newImages.addAll(paths));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.add, size: 16, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Add Images',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...g.documents
                        .where(
                          (d) =>
                              _isImageUri(d.fileUri) &&
                              !removedIds.contains(d.id),
                        )
                        .map(
                          (d) => _imageManageRow(
                            title: d.title,
                            subtitle: d.tags.contains('tenant-document')
                                ? '${_prettyType(d.type)} (Tenant)'
                                : _prettyType(d.type),
                            uri: d.fileUri!,
                            icon: Icons.delete,
                            color: const Color(0xFFFF4444),
                            onTap: () => setS(() => removedIds.add(d.id)),
                            isTenant: d.tags.contains('tenant-document'),
                          ),
                        ),
                    ...newImages.asMap().entries.map(
                      (e) => _imageManageRow(
                        title: title.text.trim(),
                        subtitle: 'New',
                        uri: e.value,
                        icon: Icons.delete,
                        color: const Color(0xFFFF4444),
                        onTap: () => setS(() => newImages.removeAt(e.key)),
                      ),
                    ),
                    if (removedIds.isNotEmpty) ...[
                      Divider(height: 24, color: AppColors.border),
                      const Text(
                        'Removed Images',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF4444),
                        ),
                      ),
                      ...g.documents
                          .where(
                            (d) =>
                                _isImageUri(d.fileUri) &&
                                removedIds.contains(d.id),
                          )
                          .map(
                            (d) => _imageManageRow(
                              title: d.title,
                              subtitle: 'Removed',
                              uri: d.fileUri!,
                              icon: Icons.refresh,
                              color: AppColors.primary,
                              onTap: () => setS(() => removedIds.remove(d.id)),
                              removed: true,
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          footer: SheetActions(
            primaryLabel: 'Save Changes',
            primaryIcon: const Icon(Icons.check_circle_outline, size: 19),
            onPrimary: () {
              if (title.text.trim().length < 3) return;
              String? tenant, unit;
              final parts = combined.text.split(' - ');
              if (combined.text.trim().isNotEmpty) {
                tenant = parts[0].trim();
                if (parts.length > 1) unit = parts[1].trim();
              }
              final kept = g.documents
                  .where((d) => !removedIds.contains(d.id))
                  .toList();
              final added = newImages
                  .map(
                    (p) => RentDoc(
                      id: 'new-${DateTime.now().microsecondsSinceEpoch}-${p.hashCode}',
                      title: title.text.trim(),
                      type: type,
                      fileName: p.split('/').last,
                      fileSize: MediaPicker.fileSizeOf(p),
                      uploadedBy: g.uploadedBy,
                      uploadedDate: DateTime.now().toIso8601String(),
                      status: 'active',
                      fileUri: p,
                      description: desc.text.trim().isEmpty
                          ? 'Image uploaded to group'
                          : desc.text.trim(),
                      priority: 'medium',
                      tags: ['group-image'],
                      groupId: g.id,
                      unit: unit,
                      tenant: tenant,
                    ),
                  )
                  .toList();
              final nn = ref.read(appDataProvider.notifier);
              // Un-group removed documents so they actually disappear from the
              // group; updating only the group metadata is a no-op in the UI.
              final allDocs = ref.read(appDataProvider).documents;
              for (final removedId in removedIds) {
                final removed = allDocs
                    .where((d) => d.id == removedId)
                    .firstOrNull;
                if (removed != null) {
                  nn.upsertDocument(removed.copyWith(groupId: ''));
                }
              }
              for (final d in added) {
                nn.upsertDocument(d);
              }
              nn.upsertDocumentGroup(
                DocumentGroup(
                  id: g.id,
                  title: title.text.trim(),
                  type: type,
                  description: desc.text.trim().isEmpty
                      ? null
                      : desc.text.trim(),
                  uploadedBy: g.uploadedBy,
                  uploadedDate: g.uploadedDate,
                  unit: unit,
                  tenant: tenant,
                  documents: [...kept, ...added],
                  isCollapsed: g.isCollapsed,
                ),
              );
              Navigator.pop(ctx);
            },
            cancelLabel: 'Cancel',
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  Widget _imageManageRow({
    required String title,
    required String subtitle,
    required String uri,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isTenant = false,
    bool removed = false,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: removed
          ? AppColors.error.withValues(alpha: 0.1)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: removed
            ? AppColors.error.withValues(alpha: 0.3)
            : AppColors.border,
      ),
    ),
    child: Row(
      children: [
        Opacity(
          opacity: removed ? 0.5 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 50, height: 50, child: _fileImage(uri)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: removed ? const Color(0xFFFF4444) : Colors.white,
                      ),
                    ),
                  ),
                  if (isTenant)
                    const Icon(
                      Icons.person,
                      size: 12,
                      color: AppColors.primary,
                    ),
                ],
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: removed
                      ? const Color(0xFFFF4444)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ],
    ),
  );

  // ===================== Bulk Add Document modal =====================
  void _bulkUpload({String? initialType}) {
    final s = ref.read(appDataProvider);
    final cats = s.documentCategories;
    DocumentCategory? selectedCat = cats
        .where((c) => c.type == (initialType ?? ''))
        .cast<DocumentCategory?>()
        .firstOrNull;
    final titleCtl = TextEditingController();
    final descCtl = TextEditingController();
    final files = <String>[];
    String? tenantName;
    String? tenantUnit;

    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final valid =
              titleCtl.text.trim().isNotEmpty &&
              selectedCat != null &&
              files.isNotEmpty;
          return AppModalSheet(
            title: 'Add Document',
            icon: Icons.description_outlined,
            iconColor: AppColors.primary,
            size: SheetSize.standard,
            avoidBottomInset: true,
            scrollable: true,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Label('Category for All Files *')),
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        Future.delayed(
                          const Duration(milliseconds: 100),
                          () => _categoryManager(),
                        );
                      },
                      child: Row(
                        children: const [
                          Icon(
                            Icons.settings,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Manage',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final distinctCats = <DocumentCategory>[];
                    final seenCatIds = <String>{};
                    for (final c in cats) {
                      if (c.id.isNotEmpty && seenCatIds.add(c.id)) {
                        distinctCats.add(c);
                      }
                    }
                    final validSelectedCatId =
                        (selectedCat != null &&
                            seenCatIds.contains(selectedCat!.id))
                        ? selectedCat!.id
                        : (distinctCats.isNotEmpty
                              ? distinctCats.first.id
                              : null);

                    return DropdownButtonFormField<String>(
                      initialValue: validSelectedCatId,
                      isExpanded: true,
                      dropdownColor: AppColors.dropdownBackground,
                      decoration: const InputDecoration(
                        hintText: 'Select Category',
                      ),
                      items: distinctCats
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: _hexColor(
                                        c.color,
                                        _typeColor(c.type),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _iconFromName(c.icon),
                                      size: 14,
                                      color: _contrastOn(
                                        _hexColor(c.color, _typeColor(c.type)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(c.name),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(
                        () => selectedCat = cats
                            .where((c) => c.id == v)
                            .cast<DocumentCategory?>()
                            .firstOrNull,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                AppField(
                  label: 'Title for All Files *',
                  hint: 'Enter title for all files',
                  controller: titleCtl,
                ),
                AppField(
                  label: 'Description (Optional)',
                  hint: 'Enter description for all files',
                  controller: descCtl,
                  maxLines: 3,
                ),
                const _Label('Select Files'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final p = await MediaPicker.pickDocument(ctx);
                          if (p != null) setS(() => files.add(p.path));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.2),
                                AppColors.primaryDark.withValues(alpha: 0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.insert_drive_file,
                                size: 20,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Select Documents',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final ps = await MediaPicker.pickMultipleImages();
                          if (ps.isNotEmpty) setS(() => files.addAll(ps));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accentDark.withValues(alpha: 0.2),
                                AppColors.accentDark.withValues(alpha: 0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.camera_alt,
                                size: 20,
                                color: AppColors.accentDark,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Select Photos',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Label('Files to Upload (${files.length})'),
                const SizedBox(height: 6),
                if (files.isEmpty)
                  Text(
                    'No files selected yet.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: files.asMap().entries.map((e) {
                      final isImg = _isImageUri(e.value);
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: isImg
                                  ? _fileImage(e.value)
                                  : Container(
                                      color: AppColors.surface,
                                      child: const Icon(
                                        Icons.insert_drive_file,
                                        color: AppColors.primary,
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: InkWell(
                              onTap: () => setS(() => files.removeAt(e.key)),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 14),
                const _Label('Tenant & Unit'),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final bulkTenantOptions = <String>{};
                    final bulkTenantItems = <String>[];
                    for (final t in s.scopedTenants) {
                      final label = '${t.name} - ${t.unit}';
                      if (label.trim().isNotEmpty &&
                          bulkTenantOptions.add(label)) {
                        bulkTenantItems.add(label);
                      }
                    }
                    final currentCombined =
                        (tenantName != null && tenantUnit != null)
                        ? '$tenantName - $tenantUnit'
                        : null;
                    if (currentCombined != null &&
                        !bulkTenantOptions.contains(currentCombined)) {
                      bulkTenantItems.add(currentCombined);
                    }
                    final selectedBulkTenant =
                        (currentCombined != null &&
                            bulkTenantItems.contains(currentCombined))
                        ? currentCombined
                        : null;

                    return DropdownButtonFormField<String>(
                      initialValue: selectedBulkTenant,
                      isExpanded: true,
                      dropdownColor: AppColors.dropdownBackground,
                      decoration: const InputDecoration(
                        hintText: 'Select Tenant & Unit (Optional)',
                      ),
                      items: bulkTenantItems
                          .map(
                            (val) =>
                                DropdownMenuItem(value: val, child: Text(val)),
                          )
                          .toList(),
                      onChanged: (v) => setS(() {
                        if (v == null) return;
                        final parts = v.split(' - ');
                        tenantName = parts[0];
                        tenantUnit = parts.length > 1 ? parts[1] : null;
                      }),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
            footer: SheetActions(
              primaryLabel: 'Upload All Files',
              primaryIcon: const Icon(Icons.cloud_upload_outlined, size: 19),
              onPrimary: !valid
                  ? null
                  : () => _processBulkUpload(
                      ctx: ctx,
                      title: titleCtl.text.trim(),
                      description: descCtl.text.trim(),
                      category: selectedCat!,
                      files: files,
                      tenant: tenantName,
                      unit: tenantUnit,
                    ),
              cancelLabel: 'Cancel',
              onCancel: () => Navigator.pop(ctx),
            ),
          );
        },
      ),
    );
  }

  void _processBulkUpload({
    required BuildContext ctx,
    required String title,
    required String description,
    required DocumentCategory category,
    required List<String> files,
    String? tenant,
    String? unit,
  }) {
    final nn = ref.read(appDataProvider.notifier);
    final groupId =
        'group_${DateTime.now().millisecondsSinceEpoch}_${files.length}';
    final now = DateTime.now().toIso8601String();
    final docs = files
        .map(
          (p) => RentDoc(
            id: newId(),
            title: title,
            type: category.type,
            fileName: p.split('/').last,
            fileSize: MediaPicker.fileSizeOf(p),
            uploadedBy: 'Current User',
            uploadedDate: now,
            status: 'active',
            unit: unit,
            tenant: tenant,
            fileUri: p,
            description: description.isEmpty
                ? 'Added ${category.type} document'
                : description,
            priority: 'medium',
            tags: [category.type, 'bulk-upload'],
            groupId: groupId,
          ),
        )
        .toList();
    for (final d in docs) {
      nn.upsertDocument(d);
    }
    nn.upsertDocumentGroup(
      DocumentGroup(
        id: groupId,
        title: title,
        type: category.type,
        description: description.isEmpty ? null : description,
        uploadedBy: 'Current User',
        uploadedDate: now,
        unit: unit,
        tenant: tenant,
        documents: docs,
      ),
    );
    Navigator.pop(ctx);
    showAppToast(
      context,
      'Successfully uploaded ${docs.length} out of ${files.length} files as a group!',
      isSuccess: true,
    );
  }

  // ===================== Edit document =====================
  void _editDocument(RentDoc? d) {
    final s = ref.read(appDataProvider);
    final title = TextEditingController(text: d?.title ?? '');
    final desc = TextEditingController(text: d?.description ?? '');
    String type = d?.type ?? 'lease';
    String? fileUri = d?.fileUri;
    final combined = TextEditingController(
      text: (d?.tenant?.isNotEmpty == true && d?.unit?.isNotEmpty == true)
          ? '${d!.tenant} - ${d.unit}'
          : (d?.tenant ?? ''),
    );

    String? error;
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AppModalSheet(
          title: d == null ? 'Add Document' : 'Edit Document',
          icon: Icons.description_outlined,
          iconColor: AppColors.primary,
          size: SheetSize.standard,
          avoidBottomInset: true,
          scrollable: true,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              AppField(
                label: 'Document Title *',
                hint: 'Enter document title',
                controller: title,
              ),
              const _Label('Document Type'),
              DropdownButtonFormField<String>(
                initialValue: kDocTypes.contains(type)
                    ? type
                    : (kDocTypes.isNotEmpty ? kDocTypes.first : null),
                isExpanded: true,
                dropdownColor: AppColors.dropdownBackground,
                items: kDocTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(_prettyType(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setS(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              const _Label('Tenant & Unit (Optional)'),
              Builder(
                builder: (context) {
                  final docTenantOptions = <String>{};
                  final docTenantItems = <String>[''];
                  for (final t in s.scopedTenants) {
                    final label = '${t.name} - ${t.unit}';
                    if (label.trim().isNotEmpty &&
                        docTenantOptions.add(label)) {
                      docTenantItems.add(label);
                    }
                  }
                  if (combined.text.isNotEmpty &&
                      !docTenantOptions.contains(combined.text)) {
                    docTenantItems.add(combined.text);
                  }
                  final selectedDocTenant =
                      docTenantItems.contains(combined.text)
                      ? combined.text
                      : '';

                  return DropdownButtonFormField<String>(
                    initialValue: selectedDocTenant,
                    isExpanded: true,
                    dropdownColor: AppColors.dropdownBackground,
                    decoration: const InputDecoration(
                      hintText: 'Select Tenant & Unit (Optional)',
                    ),
                    items: docTenantItems
                        .map(
                          (val) => DropdownMenuItem(
                            value: val,
                            child: Text(val.isEmpty ? 'None' : val),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => combined.text = v ?? ''),
                  );
                },
              ),
              const SizedBox(height: 12),
              AppField(
                label: 'Description (Optional)',
                hint: 'Enter document description',
                controller: desc,
                maxLines: 4,
              ),
              const SizedBox(height: 4),
              _Label(
                fileUri == null
                    ? 'Document Image (Optional)'
                    : 'Document Image',
              ),
              const SizedBox(height: 6),
              if (fileUri != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: _fileImage(fileUri!, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        children: [
                          _miniBtn(Icons.camera_alt, 'Change', () async {
                            final p = await MediaPicker.pickImage(ctx);
                            if (p != null) setS(() => fileUri = p);
                          }),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => setS(() => fileUri = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cancel,
                                size: 22,
                                color: Color(0xFFFF4444),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                InkWell(
                  onTap: () async {
                    final p = await MediaPicker.pickImage(ctx);
                    if (p != null) setS(() => fileUri = p);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.textSecondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 24,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Add Image',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
          footer: SheetActions(
            primaryLabel: 'Save Changes',
            primaryIcon: const Icon(Icons.check_circle_outline, size: 19),
            onPrimary: () {
              if (title.text.trim().length < 3) {
                setS(() => error = 'Title must be at least 3 characters');
                return;
              }
              String? tenant, unit;
              if (combined.text.trim().isNotEmpty) {
                final parts = combined.text.split(' - ');
                tenant = parts[0].trim();
                if (parts.length > 1) unit = parts[1].trim();
              }
              final sharesGroup = d?.tags.contains('tenant-group') ?? false;
              ref
                  .read(appDataProvider.notifier)
                  .upsertDocument(
                    RentDoc(
                      id: d?.id ?? newId(),
                      title: title.text.trim(),
                      type: type,
                      fileName: d?.fileName ?? '${title.text.trim()}.jpg',
                      fileSize: d?.fileSize ?? 'Unknown',
                      uploadedBy: d?.uploadedBy ?? 'System',
                      uploadedDate:
                          d?.uploadedDate ?? DateTime.now().toIso8601String(),
                      status: d?.status ?? 'active',
                      unit: unit,
                      tenant: tenant,
                      fileUri: fileUri,
                      description: desc.text.trim(),
                      groupId: d?.groupId,
                      tags: d?.tags ?? [],
                      isPdf: d?.isPdf ?? false,
                      priority: d?.priority ?? (sharesGroup ? 'medium' : null),
                      expiryDate: d?.expiryDate,
                      pageCount: d?.pageCount ?? 0,
                    ),
                  );
              Navigator.pop(ctx);
              showAppToast(
                context,
                d == null
                    ? 'Document created successfully'
                    : 'Document updated successfully',
                isSuccess: true,
              );
            },
            cancelLabel: 'Cancel',
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  // ===================== Category manager =====================
  void _categoryManager() {
    final isEditing = <String, bool>{};
    final editId = <String, String?>{};
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final form = <String, String>{
      'type': 'other',
      'color': '#4CAF50',
      'icon': 'folder',
    };
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final s = ref.watch(appDataProvider);
          final cats = s.documentCategories;
          final editingId = editId['id'];
          final editing = editingId != null;
          final showForm = isEditing['on'] ?? false;
          final type = form['type']!;
          final color = form['color']!;
          final icon = form['icon']!;

          return AppModalSheet(
            title: 'Manage Document Categories',
            icon: Icons.folder_outlined,
            iconColor: AppColors.primary,
            size: SheetSize.standard,
            avoidBottomInset: true,
            scrollable: true,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showForm) ...[
                  Text(
                    editing ? 'Edit Category' : 'Add New Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppField(
                    label: 'Name *',
                    hint: 'Enter category name',
                    controller: nameCtl,
                  ),
                  const _Label('Type *'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kDocTypes.map((t) {
                      final sel = type == t;
                      return ChoiceChip(
                        label: Text(_prettyType(t)),
                        selected: sel,
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setS(() => form['type'] = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  AppField(
                    label: 'Description',
                    hint: 'Enter description (optional)',
                    controller: descCtl,
                    maxLines: 3,
                  ),
                  const _Label('Color'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kColorSwatches.map((c) {
                      final sel = color == c;
                      return GestureDetector(
                        onTap: () => setS(() => form['color'] = c),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _hexColor(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: sel
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const _Label('Icon'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kIconNames.map((n) {
                      final sel = icon == n;
                      return GestureDetector(
                        onTap: () => setS(() => form['icon'] = n),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: sel ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Icon(
                            _iconFromName(n),
                            size: 20,
                            color: sel
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: () => setS(() {
                              isEditing['on'] = false;
                              editId['id'] = null;
                            }),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: AppColors.textSecondary,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: GradientButton(
                            onPressed: () {
                              if (nameCtl.text.trim().isEmpty) {
                                showAppToast(
                                  context,
                                  'Please enter a category name',
                                  isError: true,
                                );
                                return;
                              }
                              final list = [
                                ...ref.read(appDataProvider).documentCategories,
                              ];
                              if (editing) {
                                final i = list.indexWhere(
                                  (c) => c.id == editingId,
                                );
                                if (i >= 0) {
                                  final old = list[i];
                                  list[i] = DocumentCategory(
                                    id: old.id,
                                    name: nameCtl.text.trim(),
                                    type: type,
                                    description: descCtl.text.trim(),
                                    color: color,
                                    icon: icon,
                                    isDefault: old.isDefault,
                                  );
                                }
                              } else {
                                list.add(
                                  DocumentCategory(
                                    id: newId(),
                                    name: nameCtl.text.trim(),
                                    type: type,
                                    description: descCtl.text.trim(),
                                    color: color,
                                    icon: icon,
                                  ),
                                );
                              }
                              ref
                                  .read(appDataProvider.notifier)
                                  .setDocumentCategories(list);
                              setS(() {
                                isEditing['on'] = false;
                                editId['id'] = null;
                              });
                            },
                            child: Text(editing ? 'Update' : 'Add'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Categories',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setS(() {
                          isEditing['on'] = true;
                          editId['id'] = null;
                          nameCtl.clear();
                          descCtl.clear();
                          form['type'] = 'other';
                          form['color'] = '#4CAF50';
                          form['icon'] = 'folder';
                        }),
                        child: Row(
                          children: const [
                            Icon(Icons.add, color: AppColors.primary, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'Add New',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...cats.map(
                    (c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _hexColor(c.color, _typeColor(c.type)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _iconFromName(c.icon),
                          size: 16,
                          color: _contrastOn(
                            _hexColor(c.color, _typeColor(c.type)),
                          ),
                        ),
                      ),
                      title: Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _prettyType(c.type),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (c.description?.isNotEmpty == true)
                            Text(
                              c.description!,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => setS(() {
                              isEditing['on'] = true;
                              editId['id'] = c.id;
                              nameCtl.text = c.name;
                              descCtl.text = c.description ?? '';
                              form['type'] = c.type;
                              form['color'] = c.color ?? '#4CAF50';
                              form['icon'] = c.icon ?? 'folder';
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: c.isDefault
                                ? () {
                                    showAppToast(
                                      context,
                                      'Default categories cannot be deleted',
                                      isError: true,
                                    );
                                  }
                                : () async {
                                    final ok = await confirmDialog(
                                      context,
                                      'Delete Category',
                                      'Are you sure you want to delete "${c.name}"?',
                                    );
                                    if (!ok) return;
                                    final nn = ref.read(
                                      appDataProvider.notifier,
                                    );
                                    nn.setDocumentCategories(
                                      ref
                                          .read(appDataProvider)
                                          .documentCategories
                                          .where((x) => x.id != c.id)
                                          .toList(),
                                    );
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color:
                                    (c.isDefault
                                            ? AppColors.textSecondary
                                            : const Color(0xFFFF5722))
                                        .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.delete,
                                size: 16,
                                color: c.isDefault
                                    ? AppColors.textSecondary
                                    : const Color(0xFFFF5722),
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
            footer: !showForm
                ? SheetActions(
                    primaryLabel: 'Close',
                    onPrimary: () => Navigator.pop(ctx),
                    cancelLabel: '',
                  )
                : null,
          );
        },
      ),
    );
  }

  // ===================== Tenant sync =====================
  void _tenantSyncModal() {
    final s = ref.read(appDataProvider);
    final nn = ref.read(appDataProvider.notifier);
    nn.loadTenantSyncStatuses();
    final syncing = <String>{};
    final loading = <String, bool>{'v': true};
    Future.delayed(
      const Duration(milliseconds: 300),
      () => loading['v'] = false,
    );
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AppModalSheet(
          title: 'Tenant Document Sync',
          icon: Icons.sync,
          iconColor: AppColors.primary,
          headerTrailing: GestureDetector(
            onTap: () => _cleanupDuplicates(s, setS),
            child: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 24,
            ),
          ),
          size: SheetSize.standard,
          scrollable: false,
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sync tenant documents to the main Documents screen. This allows you to manage all documents in one place with better organization and search capabilities.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: loading['v'] == true
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 12),
                            Text(
                              'Loading sync statuses...',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : s.scopedTenants.isEmpty
                    ? const Center(
                        child: EmptyState(
                          icon: Icons.people_outline,
                          title: 'No tenants available',
                          subtitle: 'Add tenants first to sync their documents',
                        ),
                      )
                    : ListView(
                        children: s.scopedTenants.map((t) {
                          final status = nn.tenantSyncStatusFor(t.name);
                          final hasDocs = t.documents.isNotEmpty;
                          final isSyncing = syncing.contains(t.name);
                          final statusColor = _syncColor(status);
                          final statusText = _syncText(status, t);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.08),
                                  Colors.white.withValues(alpha: 0.02),
                                  AppColors.surface,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            t.name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Unit ${t.unit}',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (status?.lastSyncDate != null) ...[
                                            const SizedBox(width: 10),
                                            Text(
                                              status!.lastSyncDate!,
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (status?.lastError != null)
                                        Text(
                                          'Error: ${status!.lastError}',
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (hasDocs &&
                                    (status == null ||
                                        status.status == 'pending' ||
                                        status.status == 'failed'))
                                  _syncBtn(
                                    isSyncing,
                                    AppColors.primary,
                                    () => _syncTenant(t, setS, syncing),
                                  ),
                                if (status != null &&
                                    status.failedDocuments > 0 &&
                                    hasDocs)
                                  _syncBtn(
                                    isSyncing,
                                    AppColors.accentDark,
                                    () => _syncTenant(
                                      t,
                                      setS,
                                      syncing,
                                      retry: true,
                                    ),
                                  ),
                                if (hasDocs && status?.status == 'completed')
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Color(0xCC4CAF50),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'All synced',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (!hasDocs)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file_outlined,
                                        size: 16,
                                        color: AppColors.textMuted,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'No documents',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
          footer: SheetActions(
            primaryLabel: 'Close',
            onPrimary: () => Navigator.pop(ctx),
            cancelLabel: '',
          ),
        ),
      ),
    );
  }

  Color _syncColor(TenantSyncStatus? s) {
    if (s == null) return const Color(0xFF6B7280);
    if (s.isSyncing) return const Color(0xFF3B82F6);
    if (s.failedDocuments > 0) return const Color(0xFFEF4444);
    if (s.syncedDocuments == s.totalDocuments) return const Color(0xFF10B981);
    return const Color(0xFFF59E0B);
  }

  String _syncText(TenantSyncStatus? s, Tenant t) {
    if (s == null) {
      return t.documents.isNotEmpty ? 'Not Synced' : 'No Documents';
    }
    if (s.isSyncing) return 'Syncing...';
    if (s.failedDocuments > 0) {
      return '${s.syncedDocuments}/${s.totalDocuments} synced (${s.failedDocuments} failed)';
    }
    return '${s.syncedDocuments}/${s.totalDocuments} synced';
  }

  Widget _syncBtn(bool syncing, Color color, VoidCallback onTap) => InkWell(
    onTap: syncing ? null : onTap,
    child: Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: syncing ? 0.1 : 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: syncing
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.sync, size: 16, color: color),
    ),
  );

  Future<void> _syncTenant(
    Tenant t,
    StateSetter setS,
    Set<String> syncing, {
    bool retry = false,
  }) async {
    if (t.documents.isEmpty) return;
    setS(() => syncing.add(t.name));
    final nn = ref.read(appDataProvider.notifier);
    final result = nn.syncTenantDocuments(t, retry: retry);
    final synced = result.synced;
    final failed = result.failed;
    nn.recordTenantSync(
      TenantSyncStatus(
        tenantName: t.name,
        totalDocuments: t.documents.length,
        syncedDocuments: synced,
        failedDocuments: failed,
        status: failed > 0 ? (synced > 0 ? 'partial' : 'failed') : 'completed',
        lastSyncDate: DateTime.now().toIso8601String().split('T').first,
      ),
    );
    if (mounted) {
      setS(() => syncing.remove(t.name));
      if (failed == 0) {
        _alert(
          'Sync Successful',
          'Successfully synced $synced documents for ${t.name}.',
        );
      } else {
        _alert('Sync Warning', 'Synced $synced, $failed failed for ${t.name}.');
      }
    }
  }

  void _cleanupDuplicates(AppDataState s, StateSetter setS) async {
    final ok = await confirmDialog(
      context,
      'Clean Up Duplicates',
      'This will remove duplicate tenant documents from the Documents screen. This action cannot be undone.',
    );
    if (!ok) return;
    final res = AutoDeduplicationService.reconcileDocuments(s.documents);
    final nn = ref.read(appDataProvider.notifier);
    for (final id in res.retiredIds) {
      nn.deleteDocument(id);
    }
    if (mounted) {
      _alert(
        'Cleanup Complete',
        'Removed ${res.retiredIds.length} duplicate documents.',
      );
    }
  }

  void _alert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text(
          title,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
