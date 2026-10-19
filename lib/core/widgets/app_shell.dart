import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../services/deep_linking.dart';
import '../state/app_data.dart';
import '../theme/app_colors.dart';
import 'common.dart';
import '../../features/desktop/desktop_shell.dart';
import '../../features/documents/documents_view.dart';
import '../../features/overview/overview_view.dart';
import '../../features/reports/reports_view.dart';
import '../../features/settings/settings_view.dart';
import '../../features/tenants/tenants_view.dart';
import '../../features/work_orders/work_orders_view.dart';
import '../../features/zakat/zakat_view.dart';

/// Port of `App.tsx` renderScreen() + BottomNavigation — 6 tabs with the
/// original icon set (home/people/construct/document/bar-chart/pricetag)
/// and the white-on-green active pill.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    // Port of DeepLinkingService navigation (rentmanager://screen/...).
    DeepLinkBus.pending.addListener(_onDeepLink);
    // A link received during splash/auth/onboarding is already in the notifier
    // before this shell mounts; ValueNotifier does not replay it, so consume it
    // once after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && DeepLinkBus.pending.value != null) _onDeepLink();
    });
  }

  @override
  void dispose() {
    DeepLinkBus.pending.removeListener(_onDeepLink);
    super.dispose();
  }

  void _onDeepLink() {
    if (Responsive.isDesktop(context)) return;
    final url = DeepLinkBus.pending.value;
    if (url == null) return;
    DeepLinkBus.pending.value = null;
    final tab = DeepLinkBus.tabIndexFor(url);
    if (tab == null || !mounted) return;
    setState(() {
      if (tab == -1) {
        _showSettings = true;
      } else {
        _index = tab;
        _showSettings = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      return const DesktopShell();
    }

    final s = ref.watch(appDataProvider);
    final showZakat = s.preferences.showZakat;

    final tabs = [
      _Tab('Overview', Ionicons.homeOutline, Ionicons.home),
      _Tab('Tenants', Ionicons.peopleOutline, Ionicons.people),
      _Tab('Work', Ionicons.constructOutline, Ionicons.construct),
      _Tab('Documents', Ionicons.documentTextOutline, Ionicons.documentText),
      _Tab('Reports', Ionicons.barChartOutline, Ionicons.barChart),
      if (showZakat)
        _Tab('Zakat', Ionicons.pricetagOutline, Ionicons.pricetag),
    ];
    if (_index >= tabs.length) _index = 0;

    Widget body;
    switch (tabs[_index].label) {
      case 'Tenants':
        body = const TenantsView();
        break;
      case 'Work':
        body = const WorkOrdersView();
        break;
      case 'Documents':
        body = const DocumentsView();
        break;
      case 'Reports':
        body = const ReportsView();
        break;
      case 'Zakat':
        body = const ZakatView();
        break;
      default:
        body = OverviewView(
          onSettings: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SettingsView(),
            ),
          ),
        );
    }

    return PopScope(
      canPop: !_showSettings,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showSettings) {
          setState(() => _showSettings = false);
        }
      },
      child: Stack(children: [
        _scaffold(body, tabs),
        if (_showSettings)
          Positioned.fill(
            child: SettingsView(
              onClose: () => setState(() => _showSettings = false),
            ),
          ),
      ]),
    );
  }

  Widget _scaffold(Widget body, List<_Tab> tabs) {
    final isDark = AppColors.isDark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF030D0D) : const Color(0xFFEDF4F2),
      body: AppBackground(child: body),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF091F1F) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8E8),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _navTabItem(
                      index: i,
                      tab: tabs[i],
                      isSelected: i == _index && !_showSettings,
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _index = i;
                          _showSettings = false;
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navTabItem({
    required int index,
    required _Tab tab,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeColor =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final inactiveColor = isDark
        ? const Color(0xFFA0D8D8).withValues(alpha: 0.6)
        : const Color(0xFF64748B);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active pill indicator around the icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: isSelected ? 46 : 34,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
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
                              .withValues(alpha: isDark ? 0.45 : 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  isSelected ? tab.filled : tab.outlined,
                  size: 19,
                  color: isSelected ? Colors.white : inactiveColor,
                ),
              ),
            ),
            const SizedBox(height: 3),
            // Tab Label
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: isSelected ? 0.15 : 0,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData outlined;
  final IconData filled;
  _Tab(this.label, this.outlined, this.filled);
}
