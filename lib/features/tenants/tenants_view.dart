import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import '../../core/widgets/wave_animation.dart';

import '../desktop/desktop_tenants_view.dart';
import '../overview/overview_view.dart';
import '../reports/reports_view.dart';
import '../documents/documents_view.dart';

/// Port of `src/screens/TenantsScreen.tsx` — stats, status tabs, list/grid,
/// search, sort, call/mail actions, long-press select, details with documents,
/// full add/edit form.
class TenantsView extends ConsumerStatefulWidget {
  const TenantsView({super.key});

  // ignore: library_private_types_in_public_api
  static final GlobalKey<_TenantsViewState> globalKey =
      GlobalKey<_TenantsViewState>();

  static void showEditModal(BuildContext context, {Tenant? tenant}) {
    globalKey.currentState?._edit(context, tenant);
  }

  static void showDetails(BuildContext context, Tenant tenant) {
    globalKey.currentState?._details(context, tenant);
  }

  @override
  ConsumerState<TenantsView> createState() => _TenantsViewState();
}

class _TenantsViewState extends ConsumerState<TenantsView> {
  String _q = '';
  String _statusTab = 'all';
  bool _grid = false;
  bool _selecting = false;
  final Set<String> _selected = {};

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchNode = FocusNode();
  bool _searchOpen = false;
  bool _searchFocus = false;
  bool _showSuggestions = false;

  // Loading skeleton wave (mirrors the OverviewView behavior).
  bool _wave = false;
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();
    _searchNode.addListener(() {
      if (mounted) setState(() => _searchFocus = _searchNode.hasFocus);
    });
    _wave = true;
    _waveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _wave = false);
    });
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _searchCtrl.dispose();
    _searchNode.dispose();
    super.dispose();
  }

  /// Briefly show the skeleton wave, mirroring OverviewView's filter switch.
  void _flashWave() {
    _waveTimer?.cancel();
    setState(() => _wave = true);
    _waveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _wave = false);
    });
  }

  static int _unitSort(Tenant a, Tenant b) {
    final ra = RegExp(r'(\d+)').firstMatch(a.unit);
    final rb = RegExp(r'(\d+)').firstMatch(b.unit);
    if (ra != null && rb != null) {
      final c = int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
      if (c != 0) return c;
    }
    return a.unit.compareTo(b.unit);
  }

  bool _matches(Tenant t) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return t.name.toLowerCase().contains(q) ||
        t.unit.toLowerCase().contains(q) ||
        t.email.toLowerCase().contains(q) ||
        t.phone.toLowerCase().contains(q) ||
        t.status.toLowerCase().contains(q);
  }

  List<String> _suggestions(List<Tenant> tenants) {
    if (_q.length < 2) return [];
    final q = _q.toLowerCase();
    final set = <String>{};
    for (final t in tenants) {
      if (t.name.toLowerCase().contains(q)) set.add(t.name);
      if (t.unit.toLowerCase().contains(q)) set.add(t.unit);
      if (t.email.toLowerCase().contains(q)) set.add(t.email);
      if (t.phone.toLowerCase().contains(q)) set.add(t.phone);
      if (t.status.toLowerCase().contains(q)) set.add(t.status);
    }
    return set.take(8).toList();
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _mail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sms(String phone) async {
    final uri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Color _statusBg(String status) => status == 'inactive'
      ? const Color.fromRGBO(255, 107, 107, 0.08)
      : (AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.03)
            : AppColors.cardBackground);

  Color _statusBorder(String status) => status == 'inactive'
      ? const Color.fromRGBO(255, 107, 107, 0.15)
      : (AppColors.isDark
            ? const Color.fromRGBO(255, 255, 255, 0.08)
            : AppColors.border);

  IconData _statusIcon(String status) =>
      status == 'active' ? Icons.check_circle : Icons.cancel;

  Color _statusIconColor(String status) =>
      status == 'active' ? AppColors.primary : AppColors.error;

  Future<void> _deleteTenant(BuildContext context, Tenant t) async {
    final ok = await confirmDialog(
      context,
      'Delete Tenant',
      '⚠️ WARNING: This will permanently delete ${t.name} and ALL associated data including:\n\n• All tenant documents\n• All rent roll records for this tenant\n• All payment history\n\nThis action cannot be undone. Are you sure you want to continue?',
    );
    if (!ok) return;
    ref.read(appDataProvider.notifier).deleteTenant(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return DesktopTenantsView(
        onAddTenant: () => _edit(context, null),
        onEditTenant: (t) => _edit(context, t),
        onLogPayment: (t) => OverviewView.showPaymentSheet(context, tenant: t),
        onDeleteTenant: (t) => _deleteTenant(context, t),
        onPaymentDetails: (p, t) =>
            OverviewView.showRentDetails(context, payment: p, tenant: t),
        onEditPayment: (p, t) =>
            OverviewView.showPaymentSheet(context, payment: p, tenant: t),
        onSelectTenant: (t) => _details(context, t),
        onExportStatement: (t) => ReportsView.showExportTenant(context, t),
        onViewDocument: (d) => DocumentsView.showViewModal(context, d),
        onAddDocument: (t) => DocumentsView.showAddModal(context),
      );
    }

    final s = ref.watch(appDataProvider);
    final searched = s.scopedTenants.where(_matches).toList();
    final list =
        searched
            .where((t) => _statusTab == 'all' || t.status == _statusTab)
            .toList()
          ..sort(_unitSort);
    // Header/tab counts describe the whole property, independent of the
    // active status tab or search query.
    final total = s.scopedTenants.length;
    final active = s.scopedTenants.where((t) => t.status == 'active').length;
    final inactive = total - active;

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
            _header(context, total, s),
            if (_searchOpen) _searchSection(s.scopedTenants),
            _stats(total, active, inactive),
            _filterTabs(total, active, inactive),
            if (_selecting) _selectionBar(),
            Expanded(
              child: _wave
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: WaveAnimation(
                        count: 6,
                        icon: Ionicons.peopleOutline,
                      ),
                    )
                  : PullToRefresh(
                      child: list.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) =>
                                  SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: const EmptyState(
                                        icon: Icons.people_outline,
                                        title: 'No Tenants Found',
                                        subtitle: 'Start by adding your first tenant using the + button above.',
                                      ),
                                    ),
                                  ),
                            )
                          : _grid
                          ? GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 1.35,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                              itemCount: list.length,
                              itemBuilder: (_, i) => _gridCard(list[i], s),
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              itemCount: list.length,
                              itemBuilder: (_, i) => _rowCard(list[i], s),
                            ),
                    ),
            ),
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
          // Left: Tenants Icon Badge with subtle active dot
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
                      Icons.people_alt_rounded,
                      size: 22,
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

          // Center: Title + Total count pill + Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tenants',
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

          // Right: Action buttons (Search, View Mode toggle, Add tenant)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerSearchToggle(isDark),
              const SizedBox(width: 6),
              _viewModeToggle(isDark),
              const SizedBox(width: 6),
              _headerAddButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerSearchToggle(bool isDark) => GestureDetector(
    onTap: _toggleSearch,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _searchOpen
            ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.35))
            : (isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.06)
                  : Colors.white.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.1)
              : Colors.white.withValues(alpha: 0.35),
        ),
      ),
      child: Icon(
        _searchOpen ? Icons.close_rounded : Icons.search_rounded,
        size: 18,
        color: isDark ? AppColors.icon : Colors.white,
      ),
    ),
  );

  Widget _viewModeToggle(bool isDark) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: isDark
          ? const Color.fromRGBO(255, 255, 255, 0.06)
          : Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isDark
            ? const Color.fromRGBO(255, 255, 255, 0.1)
            : Colors.white.withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _viewModeButton(Icons.view_list_rounded, false, isDark),
        _viewModeButton(Icons.grid_view_rounded, true, isDark),
      ],
    ),
  );

  Widget _viewModeButton(IconData icon, bool grid, bool isDark) {
    final active = _grid == grid;
    return GestureDetector(
      onTap: () => setState(() => _grid = grid),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppColors.primary : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: active
              ? (isDark ? Colors.white : const Color(0xFF0F766E))
              : (isDark
                    ? AppColors.textSecondary
                    : Colors.white.withValues(alpha: 0.85)),
        ),
      ),
    );
  }

  Widget _headerAddButton(bool isDark) => GestureDetector(
    onTap: () => _edit(context, null),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.4),
        ),
      ),
      child: Icon(
        Icons.add_rounded,
        size: 20,
        color: isDark ? AppColors.primary : Colors.white,
      ),
    ),
  );

  // ===== Search =====

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _q = '';
        _searchCtrl.clear();
        _showSuggestions = false;
        _searchFocus = false;
        _searchNode.unfocus();
      }
    });
  }

  Widget _searchSection(List<Tenant> tenants) {
    final sugg = _suggestions(tenants);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 18,
                  color: _searchFocus
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchNode,
                    autofocus: true,
                    onChanged: (v) => setState(() {
                      _q = v;
                      _showSuggestions = v.isNotEmpty;
                    }),
                    style: TextStyle(color: AppColors.text, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search tenants...',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() {
                      _q = '';
                      _searchCtrl.clear();
                      _showSuggestions = false;
                    }),
                    child: Padding(
                      padding: EdgeInsets.all(4),
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
          if (_showSuggestions && sugg.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color.fromRGBO(255, 255, 255, 0.2),
                ),
              ),
              child: Column(
                children: [
                  for (final suggestion in sugg)
                    GestureDetector(
                      onTap: () => setState(() {
                        _searchCtrl.text = suggestion;
                        _q = suggestion;
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
                                suggestion,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            Text(
                              '${_suggestionCount(tenants, suggestion)}',
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  int _suggestionCount(List<Tenant> tenants, String suggestion) {
    final q = suggestion.toLowerCase();
    return tenants.where((t) {
      return t.name.toLowerCase().contains(q) ||
          t.unit.toLowerCase().contains(q) ||
          t.email.toLowerCase().contains(q) ||
          t.phone.toLowerCase().contains(q) ||
          t.status.toLowerCase().contains(q);
    }).length;
  }

  // ===== Stats =====

  Widget _stats(int total, int active, int inactive) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
    child: Row(
      children: [
        _statCard('$total', 'Total Tenants', Icons.people),
        const SizedBox(width: 4),
        _statCard('$active', 'Active', Icons.check_circle),
        const SizedBox(width: 4),
        _statCard('$inactive', 'Inactive', Icons.home),
      ],
    ),
  );

  Widget _statCard(String number, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.cardBackground,
        gradient: AppColors.isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.fromRGBO(255, 255, 255, 0.08),
                  Color.fromRGBO(255, 255, 255, 0.03),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(76, 175, 80, 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: AppColors.primary),
          ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  // ===== Filter tabs =====

  Widget _filterTabs(int total, int active, int inactive) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Container(
      padding: const EdgeInsets.all(3),
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
        border: Border.all(
          color: AppColors.isDark
              ? const Color.fromRGBO(255, 255, 255, 0.1)
              : AppColors.border,
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
      child: Row(
        children: [
          _filterTab('all', 'All ($total)'),
          _filterTab('active', 'Active ($active)'),
          _filterTab('inactive', 'Inactive ($inactive)'),
        ],
      ),
    ),
  );

  Widget _filterTab(String value, String label) {
    final active = _statusTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_statusTab == value) return;
          setState(() {
            _statusTab = value;
            _selecting = false;
            _selected.clear();
          });
          _flashWave();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Selection bar =====

  Widget _selectionBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        Text(
          '${_selected.length} selected',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _selectionAction(Icons.done_all, 'All', _selectAll),
            const SizedBox(width: 8),
            _selectionAction(
              Icons.close,
              'None',
              _clearSelection,
              lead: Icons.close,
              color: AppColors.error,
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(width: 8),
              _selectionAction(
                Icons.delete,
                'Delete',
                () async {
                  final ok = await confirmDialog(
                    context,
                    'Delete Selected Tenants',
                    'Are you sure you want to delete ${_selected.length} tenant(s)? This will also delete all associated documents. This action cannot be undone.',
                  );
                  if (!ok) return;
                  final nn = ref.read(appDataProvider.notifier);
                  for (final id in _selected) {
                    nn.deleteTenant(id);
                  }
                  setState(() {
                    _selected.clear();
                    _selecting = false;
                  });
                },
                lead: Icons.delete,
                danger: true,
              ),
            ],
            const SizedBox(width: 8),
            _selectionAction(
              Icons.close,
              'Cancel',
              _cancelSelection,
              lead: Icons.close,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _selectionAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    IconData? lead,
    bool danger = false,
    Color? color,
  }) {
    final tint = color ?? (danger ? AppColors.error : AppColors.primary);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(lead ?? icon, size: 14, color: tint),
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
      ),
    );
  }

  void _selectAll() {
    setState(() {
      _selected.addAll(ref.read(appDataProvider).tenants.map((t) => t.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  // ===== List card =====

  Widget _rowCard(Tenant t, AppDataState s) {
    final sel = _selected.contains(t.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: GestureDetector(
        onTap: () => _selecting ? _toggleSelect(t.id) : _details(context, t),
        onLongPress: () => setState(() {
          _selecting = true;
          _selected.add(t.id);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: sel
                ? const Color.fromRGBO(76, 175, 80, 0.08)
                : _statusBg(t.status),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel
                  ? const Color.fromRGBO(76, 175, 80, 0.2)
                  : _statusBorder(t.status),
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
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Hero(
                      tag: 'tenant-avatar-${t.id}',
                      child: AvatarView(
                        name: t.name,
                        uri: t.avatar,
                        radius: 16,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _statusIcon(t.status),
                              size: 14,
                              color: _statusIconColor(t.status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Unit ${t.unit}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 80),
                    alignment: Alignment.centerRight,
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          fmtMoney(s.selectedCurrency, t.rentAmount),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: 0.1,
                          ),
                        ),
                        Text(
                          '/month',
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
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppColors.isDark
                          ? const Color.fromRGBO(255, 255, 255, 0.1)
                          : AppColors.borderLight,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 12,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Joined: ${fmtDate(t.joinDate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    _listActionButton(
                      Icons.call,
                      t.phone.isNotEmpty,
                      () => _call(t.phone),
                    ),
                    const SizedBox(width: 4),
                    _listActionButton(
                      Icons.mail,
                      t.email.isNotEmpty,
                      () => _mail(t.email),
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

  Widget _listActionButton(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: enabled
                ? const Color.fromRGBO(76, 175, 80, 0.1)
                : (AppColors.isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.05)
                      : AppColors.surface),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enabled
                  ? const Color.fromRGBO(76, 175, 80, 0.2)
                  : (AppColors.isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.1)
                        : AppColors.borderLight),
            ),
          ),
          child: Icon(
            icon,
            size: 12,
            color: enabled ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      );

  // ===== Grid card =====

  Widget _gridCard(Tenant t, AppDataState s) {
    final sel = _selected.contains(t.id);
    return GestureDetector(
      onTap: () => _selecting ? _toggleSelect(t.id) : _details(context, t),
      onLongPress: () => setState(() {
        _selecting = true;
        _selected.add(t.id);
      }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel
              ? const Color.fromRGBO(76, 175, 80, 0.08)
              : _statusBg(t.status),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel
                ? const Color.fromRGBO(76, 175, 80, 0.2)
                : _statusBorder(t.status),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: 'tenant-avatar-${t.id}',
                        child: AvatarView(
                          name: t.name,
                          uri: t.avatar,
                          radius: 21,
                        ),
                      ),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color.fromRGBO(0, 0, 0, 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _statusIcon(t.status),
                            size: 14,
                            color: _statusIconColor(t.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Unit ${t.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            fmtMoney(s.selectedCurrency, t.rentAmount),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '/month',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _gridActionButton(
                    Icons.call,
                    t.phone.isNotEmpty,
                    () => _call(t.phone),
                  ),
                  _gridActionButton(
                    Icons.mail,
                    t.email.isNotEmpty,
                    () => _mail(t.email),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridActionButton(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled
                ? const Color.fromRGBO(76, 175, 80, 0.1)
                : const Color.fromRGBO(255, 255, 255, 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled
                  ? const Color.fromRGBO(76, 175, 80, 0.2)
                  : const Color.fromRGBO(255, 255, 255, 0.1),
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      );

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  // ===== Details =====

  void _details(BuildContext context, Tenant t) {
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final s = ref.watch(appDataProvider);
            final currentTenant =
                s.tenants.where((x) => x.id == t.id).firstOrNull ?? t;
            final synced = s.documents
                .where((d) => d.tenant == currentTenant.name)
                .toList();
            return AppModalSheet(
              title: 'Tenant Details',
              icon: Ionicons.person,
              iconColor: AppColors.primary,
              size: SheetSize.standard,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tenantHeaderCard(ctx, currentTenant, synced),
                  _detailSection(
                    'Financial Information',
                    Ionicons.walletOutline,
                    [
                      _infoRow(
                        icon: Ionicons.cashOutline,
                        iconColor: AppColors.primary,
                        label: 'Rent Amount',
                        value: fmtMoney(
                          s.selectedCurrency,
                          currentTenant.rentAmount,
                        ),
                      ),
                      _infoRow(
                        icon: Ionicons.shieldCheckmarkOutline,
                        iconColor: AppColors.accentDark,
                        label: 'Advance Payment',
                        value:
                            (currentTenant.advancePaymentAmount != null &&
                                currentTenant.advancePaymentAmount! > 0)
                            ? fmtMoney(
                                s.selectedCurrency,
                                currentTenant.advancePaymentAmount!,
                              )
                            : 'None',
                      ),
                      if (currentTenant.advancePaymentMonth?.isNotEmpty == true)
                        _infoRow(
                          icon: Ionicons.calendarOutline,
                          iconColor: AppColors.accentDark,
                          label: 'Advance Month',
                          value: currentTenant.advancePaymentMonth!,
                        ),
                      _infoRow(
                        icon: Ionicons.timeOutline,
                        iconColor: AppColors.primary,
                        label: 'Lease Start',
                        value: fmtDate(currentTenant.joinDate),
                      ),
                    ],
                  ),
                  _detailSection('Contact Information', Ionicons.callOutline, [
                    _infoRow(
                      icon: Ionicons.callOutline,
                      iconColor: AppColors.primary,
                      label: 'Phone',
                      value: currentTenant.phone.isNotEmpty
                          ? currentTenant.phone
                          : 'Not provided',
                      onTap: currentTenant.phone.isNotEmpty
                          ? () => _call(currentTenant.phone)
                          : null,
                    ),
                    _infoRow(
                      icon: Ionicons.mailOutline,
                      iconColor: AppColors.info,
                      label: 'Email',
                      value: currentTenant.email.isNotEmpty
                          ? currentTenant.email
                          : 'Not provided',
                      onTap: currentTenant.email.isNotEmpty
                          ? () => _mail(currentTenant.email)
                          : null,
                    ),
                  ]),
                  _detailSection(
                    'Personal & Identity',
                    Ionicons.personOutline,
                    [
                      _infoRow(
                        icon: Ionicons.peopleOutline,
                        iconColor: AppColors.primary,
                        label: "Father's Name",
                        value: currentTenant.fathersName?.isNotEmpty == true
                            ? currentTenant.fathersName!
                            : 'Not provided',
                      ),
                      _infoRow(
                        icon: Ionicons.cardOutline,
                        iconColor: AppColors.info,
                        label: 'ID Number',
                        value: currentTenant.idNumber?.isNotEmpty == true
                            ? currentTenant.idNumber!
                            : 'Not provided',
                      ),
                      _infoRow(
                        icon: Ionicons.giftOutline,
                        iconColor: const Color(0xFFEC4899),
                        label: 'Date of Birth',
                        value: currentTenant.dateOfBirth?.isNotEmpty == true
                            ? fmtDate(currentTenant.dateOfBirth!)
                            : 'Not provided',
                      ),
                      _infoRow(
                        icon: Ionicons.calendarOutline,
                        iconColor: AppColors.primary,
                        label: 'Join Date',
                        value: fmtDate(currentTenant.joinDate),
                      ),
                      if (currentTenant.address?.isNotEmpty == true)
                        _infoRow(
                          icon: Ionicons.locationOutline,
                          iconColor: const Color(0xFFEF4444),
                          label: 'Permanent Address',
                          value: currentTenant.address!,
                        ),
                    ],
                  ),
                  _detailSection(
                    'Utility Meters',
                    Ionicons.speedometerOutline,
                    [
                      _infoRow(
                        icon: Ionicons.flashOutline,
                        iconColor: const Color(0xFFF59E0B),
                        label: 'Electric Meter',
                        value:
                            currentTenant.electricMeterNumber?.isNotEmpty ==
                                true
                            ? currentTenant.electricMeterNumber!
                            : 'Not provided',
                      ),
                      _infoRow(
                        icon: Ionicons.flameOutline,
                        iconColor: const Color(0xFFEF4444),
                        label: 'Gas Meter',
                        value: currentTenant.gasMeterNumber?.isNotEmpty == true
                            ? currentTenant.gasMeterNumber!
                            : 'Not provided',
                      ),
                    ],
                  ),
                  _documentsSection(currentTenant, synced),
                  const SizedBox(height: 8),
                ],
              ),
              footer: SheetActions(
                primaryLabel: 'Edit Tenant',
                primaryIcon: const Icon(Icons.edit, size: 16),
                onPrimary: () {
                  Navigator.pop(ctx);
                  _edit(context, currentTenant);
                },
                cancelLabel: '',
                primaryFlex: 2,
                leadingAction: Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 46,
                    child: DangerButton(
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          'Delete Tenant',
                          '⚠️ WARNING: This will permanently delete ${currentTenant.name} and ALL associated data including:\n\n• All tenant documents\n• All rent roll records for this tenant\n• All payment history\n\nThis action cannot be undone. Are you sure you want to continue?',
                        );
                        if (!ok) return;
                        ref
                            .read(appDataProvider.notifier)
                            .deleteTenant(currentTenant.id);
                        if (context.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Delete'),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tenantHeaderCard(BuildContext ctx, Tenant t, List<RentDoc> synced) {
    final isDark = AppColors.isDark;
    final isActive = t.status == 'active';
    final statusColor = isActive ? AppColors.primary : AppColors.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? const Color.fromRGBO(255, 255, 255, 0.07)
              : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: 'Tap to update profile picture',
                child: GestureDetector(
                  onTap: () async {
                    final p = await MediaPicker.pickImage(ctx);
                    if (p != null) {
                      final updated = t.copyWith(avatar: p);
                      ref.read(appDataProvider.notifier).upsertTenant(updated);
                      if (ctx.mounted) {
                        showAppToast(
                          ctx,
                          'Profile picture updated for ${t.name}',
                          isSuccess: true,
                        );
                      }
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: 'tenant-avatar-${t.id}',
                        child: AvatarView(
                          name: t.name,
                          uri: t.avatar,
                          radius: 26,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? AppColors.surface : Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 11,
                            color: Colors.white,
                          ),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isActive ? Icons.check_circle : Icons.cancel,
                                size: 10,
                                color: statusColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Unit ${t.unit}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Ionicons.calendarOutline,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Joined ${fmtDate(t.joinDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
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
            ],
          ),
          const SizedBox(height: 12),
          // Quick Actions displayed directly below tenant name section
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.07)
                      : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _quickActionButton(
                    icon: Ionicons.callOutline,
                    label: 'Call',
                    color: AppColors.primary,
                    onTap: t.phone.isEmpty ? null : () => _call(t.phone),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _quickActionButton(
                    icon: Ionicons.chatbubbleEllipsesOutline,
                    label: 'SMS',
                    color: const Color(0xFF10B981),
                    onTap: t.phone.isEmpty ? null : () => _sms(t.phone),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _quickActionButton(
                    icon: Ionicons.mailOutline,
                    label: 'Email',
                    color: AppColors.info,
                    onTap: t.email.isEmpty ? null : () => _mail(t.email),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _quickActionButton(
                    icon: Ionicons.documentTextOutline,
                    label: 'Docs',
                    color: AppColors.accentDark,
                    badge: synced.isNotEmpty || t.documents.isNotEmpty
                        ? '${synced.length + t.documents.length}'
                        : null,
                    onTap: () {
                      final allDocs = [
                        ...t.documents.map((d) => (d.name, d.uri)),
                        ...synced.map((d) => (d.title, d.fileUri ?? '')),
                      ];
                      if (allDocs.isNotEmpty && allDocs.first.$2.isNotEmpty) {
                        MediaFiles.open(allDocs.first.$2);
                      } else {
                        showAppToast(
                          ctx,
                          allDocs.isEmpty
                              ? 'No documents attached'
                              : 'Document has no file attached',
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    String? badge,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isEnabled ? 0.09 : 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: isEnabled ? 0.22 : 0.08),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isEnabled
                        ? color
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -7,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isEnabled
                      ? color
                      : AppColors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );

  Widget _detailSection(String title, IconData icon, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    final isDark = AppColors.isDark;
    final altColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.055)
        : const Color(0xFFF1F5F5);

    final List<Widget> styledRows = [];
    for (int i = 0; i < children.length; i++) {
      styledRows.add(
        ColoredBox(
          color: i.isOdd ? altColor : Colors.transparent,
          child: children[i],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.07)
                    : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(children: styledRows),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final rowWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? iconColor : AppColors.text,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: iconColor.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: rowWidget),
      );
    }
    return rowWidget;
  }

  Widget _documentsSection(Tenant t, List<RentDoc> synced) {
    final docs = [
      ...t.documents.map((d) => (d.name, d.uri, d.type, d.uploadedAt)),
      ...synced.map((d) => (d.title, d.fileUri ?? '', d.type, d.uploadedDate)),
    ];
    final isDark = AppColors.isDark;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.07)
        : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Documents', icon: Ionicons.documentTextOutline),
        if (docs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Center(
              child: Text(
                'No documents available',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
        else
          ...docs.map(
            (d) => GestureDetector(
              onTap: d.$2.isEmpty ? null : () => MediaFiles.open(d.$2),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: Row(
                  children: [
                    _docThumb(d.$2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.$1,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            d.$3.replaceAll('-', ' ').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fmtDate(d.$4),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _docThumb(String uri) {
    ImageProvider? img;
    final lower = uri.toLowerCase();
    final isImg =
        lower.startsWith('http') ||
        lower.startsWith('content://') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
    if (uri.startsWith('http')) {
      img = NetworkImage(uri);
    } else if (uri.isNotEmpty) {
      final f = File(uri);
      try {
        if (f.existsSync()) img = FileImage(f);
      } catch (_) {}
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 52,
        height: 52,
        child: (img != null && isImg)
            ? Image(
                image: img,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _docThumbFallback(uri),
              )
            : _docThumbFallback(uri),
      ),
    );
  }

  Widget _docThumbFallback(String uri) => Container(
    color: AppColors.surfaceHover,
    child: Icon(
      uri.toLowerCase().endsWith('.pdf')
          ? Icons.picture_as_pdf
          : Icons.insert_drive_file,
      color: AppColors.iconSecondary,
    ),
  );

  void _syncResultAlert(String title, String message) {
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

  // ===== Add/Edit form =====

  /// Add/Edit modal — ports AddTenantModal + TenantEditModal.
  void _edit(BuildContext context, Tenant? t) {
    final name = TextEditingController(text: t?.name ?? '');
    final unit = TextEditingController(text: t?.unit ?? '');
    final phone = TextEditingController(text: t?.phone ?? '');
    final email = TextEditingController(text: t?.email ?? '');
    final rent = TextEditingController(
      text: t != null ? '${t.rentAmount}' : '',
    );
    final father = TextEditingController(text: t?.fathersName ?? '');
    final address = TextEditingController(text: t?.address ?? '');
    final idNo = TextEditingController(text: t?.idNumber ?? '');
    final dob = TextEditingController(text: t?.dateOfBirth ?? '');
    final gas = TextEditingController(text: t?.gasMeterNumber ?? '');
    final elec = TextEditingController(text: t?.electricMeterNumber ?? '');
    final advAmt = TextEditingController(
      text: t?.advancePaymentAmount != null ? '${t!.advancePaymentAmount}' : '',
    );
    final advMonth = TextEditingController(text: t?.advancePaymentMonth ?? '');
    final docs = <TenantDocument>[...(t?.documents ?? [])];
    String status = t?.status ?? 'active';
    String? avatar = t?.avatar;
    DateTime joinDate = _parseDateOrNow(t?.joinDate);
    String? error;
    const docTypes = ['id-card', 'lease', 'contract', 'other'];
    const docLabels = {
      'id-card': 'ID Card',
      'lease': 'Lease',
      'contract': 'Contract',
      'other': 'Other',
    };
    showAdaptiveModalSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AppModalSheet(
            title: t == null ? 'Add New Tenant' : 'Edit Tenant',
            icon: Icons.person_add,
            iconColor: AppColors.primary,
            size: SheetSize.expanded,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Picture
                _formSectionTitle('Profile Picture'),
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final p = await MediaPicker.pickImage(ctx);
                          if (p != null) {
                            setS(() => avatar = p);
                          }
                        },
                        child: Stack(
                          children: [
                            AvatarView(
                              name: name.text.isEmpty ? 'T' : name.text,
                              uri: avatar,
                              radius: 40,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.photo_camera,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (Platform.isMacOS ||
                                Platform.isWindows ||
                                Platform.isLinux)
                            ? (avatar != null
                                  ? 'Click to change profile picture'
                                  : 'Click to add profile picture')
                            : (avatar != null
                                  ? 'Tap to change profile picture'
                                  : 'Tap to add profile picture'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Basic Information
                _formSectionTitle('Basic Information'),
                AppField(
                  label: 'Tenant Name *',
                  controller: name,
                  hint: 'Enter tenant name',
                ),
                AppField(
                  label: 'Unit *',
                  controller: unit,
                  hint: 'Enter unit number',
                ),
                AppField(
                  label: "Father's Name",
                  controller: father,
                  hint: "Enter father's name",
                ),
                AppField(
                  label: 'Address',
                  controller: address,
                  hint: 'Enter address',
                  maxLines: 2,
                ),
                AppField(
                  label: 'ID Number',
                  controller: idNo,
                  hint: 'Enter ID number',
                ),
                AppField(
                  label: 'Date of Birth',
                  controller: dob,
                  hint: 'YYYY-MM-DD',
                ),
                _formLabel('Status'),
                Row(
                  children: [
                    for (final st in ['active', 'inactive']) ...[
                      GestureDetector(
                        onTap: () => setS(() => status = st),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: status == st
                                ? AppColors.primary
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: status == st
                                  ? AppColors.primary
                                  : AppColors.surfaceBorder,
                            ),
                          ),
                          child: Text(
                            st[0].toUpperCase() + st.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              color: status == st
                                  ? Colors.white
                                  : AppColors.text,
                              fontWeight: status == st
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // Contact Information
                _formSectionTitle('Contact Information'),
                AppField(
                  label: 'Phone',
                  controller: phone,
                  hint: 'Enter phone number',
                  keyboard: TextInputType.phone,
                ),
                AppField(
                  label: 'Email',
                  controller: email,
                  hint: 'Enter email',
                  keyboard: TextInputType.emailAddress,
                ),
                const SizedBox(height: 4),
                // Financial Information
                _formSectionTitle('Financial Information'),
                AppField(
                  label: 'Rent Amount *',
                  controller: rent,
                  hint: 'Enter rent amount',
                  keyboard: TextInputType.number,
                ),
                const SizedBox(height: 4),
                // Advance Payment Settings
                _formSectionTitle('Advance Payment Settings'),
                AppField(
                  label: 'Advance Payment Amount',
                  controller: advAmt,
                  hint: 'Enter advance payment amount',
                  keyboard: TextInputType.number,
                ),
                AppField(
                  label: 'Advance Payment Month',
                  controller: advMonth,
                  hint: 'Enter month (e.g., January 2024)',
                ),
                const SizedBox(height: 4),
                // Lease Information
                _formSectionTitle('Lease Information'),
                _formLabel('Join Date (Year: ${joinDate.year})'),
                Text(
                  'This tenant will be associated with the selected year. You can specify a specific date or leave as default.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                DateFieldRow(
                  label: 'Join Date',
                  value: joinDate,
                  onChanged: (d) => setS(() => joinDate = d),
                ),
                // Meter Information
                _formSectionTitle('Meter Information'),
                AppField(
                  label: 'Gas Meter Number',
                  controller: gas,
                  hint: 'Enter gas meter number',
                ),
                AppField(
                  label: 'Electric Meter Number',
                  controller: elec,
                  hint: 'Enter electric meter number',
                ),
                const SizedBox(height: 4),
                // Documents
                _formSectionTitle('Documents'),
                _formLabel('Tenant Documents'),
                for (final d in docs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        _docThumb(d.uri),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            d.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: docTypes.contains(d.type) ? d.type : 'other',
                          dropdownColor: AppColors.dropdownBackground,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                          items: [
                            for (final dt in docTypes)
                              DropdownMenuItem(
                                value: dt,
                                child: Text(
                                  docLabels[dt]!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setS(() {
                              final i = docs.indexOf(d);
                              docs[i] = TenantDocument(
                                id: d.id,
                                name: d.name,
                                uri: d.uri,
                                type: v,
                                uploadedAt: d.uploadedAt,
                              );
                            });
                          },
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.cancel,
                            color: AppColors.error,
                            size: 20,
                          ),
                          onPressed: () => setS(() => docs.remove(d)),
                        ),
                      ],
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
                    final p = await MediaPicker.pickDocument(ctx);
                    if (p == null) return;
                    setS(
                      () => docs.add(
                        TenantDocument(
                          id: newId(),
                          name: p.name,
                          uri: p.path,
                          type: 'other',
                          uploadedAt: DateTime.now().toIso8601String(),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color.fromRGBO(76, 175, 80, 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.add_circle,
                          size: 24,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Add Document',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
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
            footer: SheetActions(
              primaryLabel: t == null ? 'Add Tenant' : 'Save Changes',
              primaryIcon: const Icon(
                Icons.check_circle_outline,
                size: 19,
                color: Colors.white,
              ),
              onPrimary: () {
                if (name.text.trim().isEmpty ||
                    unit.text.trim().isEmpty ||
                    rent.text.trim().isEmpty) {
                  setS(() => error = 'Please fill in all required fields');
                  return;
                }
                final rentVal = double.tryParse(rent.text.trim());
                if (rentVal == null || rentVal <= 0) {
                  setS(
                    () => error =
                        'Rent amount must be a valid number greater than 0',
                  );
                  return;
                }
                if (email.text.trim().isNotEmpty &&
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email.text.trim())) {
                  setS(() => error = 'Please enter a valid email address');
                  return;
                }
                final isNew = t == null;
                final newTenant = Tenant(
                  id: t?.id ?? newId(),
                  name: name.text.trim(),
                  unit: unit.text.trim(),
                  phone: phone.text.trim(),
                  email: email.text.trim(),
                  rentAmount: rentVal,
                  status: status,
                  joinDate: joinDate.toIso8601String(),
                  avatar: avatar,
                  fathersName: father.text.trim().isEmpty
                      ? null
                      : father.text.trim(),
                  address: address.text.trim().isEmpty
                      ? null
                      : address.text.trim(),
                  idNumber: idNo.text.trim().isEmpty ? null : idNo.text.trim(),
                  dateOfBirth: dob.text.trim().isEmpty ? null : dob.text.trim(),
                  gasMeterNumber: gas.text.trim().isEmpty
                      ? null
                      : gas.text.trim(),
                  electricMeterNumber: elec.text.trim().isEmpty
                      ? null
                      : elec.text.trim(),
                  deposit: t?.deposit,
                  documents: docs,
                  advancePaymentAmount: double.tryParse(advAmt.text),
                  advancePaymentMonth: advMonth.text.trim().isEmpty
                      ? null
                      : advMonth.text.trim(),
                  leaseStartDate: t?.leaseStartDate,
                  leaseEndDate: t?.leaseEndDate,
                );
                final notifier = ref.read(appDataProvider.notifier);
                notifier.upsertTenant(newTenant);
                // Expo `AddTenantModal` syncs attached documents to the
                // main Documents screen on create (not on edit).
                final syncResult = (isNew && docs.isNotEmpty)
                    ? notifier.syncTenantDocuments(newTenant)
                    : null;
                if (syncResult != null) {
                  notifier.recordTenantSync(
                    TenantSyncStatus(
                      tenantName: newTenant.name,
                      totalDocuments: docs.length,
                      syncedDocuments: syncResult.synced,
                      failedDocuments: syncResult.failed,
                      status: syncResult.failed > 0
                          ? (syncResult.synced > 0 ? 'partial' : 'failed')
                          : 'completed',
                      lastSyncDate: DateTime.now()
                          .toIso8601String()
                          .split('T')
                          .first,
                    ),
                  );
                }
                Navigator.pop(ctx);
                if (syncResult != null) {
                  if (syncResult.failed > 0) {
                    _syncResultAlert(
                      'Document Sync Warning',
                      'Tenant created successfully!\n\n'
                          'Document sync results:\n'
                          '• ${syncResult.synced} documents synced successfully\n'
                          '• ${syncResult.failed} documents failed to sync\n\n'
                          'You can retry syncing these documents from the Documents screen.',
                    );
                  } else if (syncResult.synced > 3) {
                    _syncResultAlert(
                      'Success',
                      'Tenant created successfully!\n\n'
                          '${syncResult.synced} documents synced to the Documents screen.',
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _formSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.text,
      ),
    ),
  );

  Widget _formLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

DateTime _parseDateOrNow(String? iso) {
  try {
    if (iso != null && iso.isNotEmpty) {
      return DateTime.parse(iso);
    }
  } catch (_) {}
  return DateTime.now();
}
