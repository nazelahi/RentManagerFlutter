import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import 'desktop_property_modal.dart';

/// Interactive macOS Sequoia Property Switcher for Desktop.
///
/// Enables instant switching between "All Properties (Portfolio)" and
/// individual properties, displaying live unit counts, address details,
/// and immediate access to property configuration modals.
class DesktopPropertySwitcher extends ConsumerWidget {
  const DesktopPropertySwitcher({super.key});

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'commercial':
        return Ionicons.briefcaseOutline;
      case 'mixed':
        return Ionicons.businessOutline;
      case 'villa':
        return Ionicons.storefrontOutline;
      case 'residential':
      default:
        return Ionicons.homeOutline;
    }
  }

  void _showPropertyMenu(BuildContext context, WidgetRef ref) async {
    final s = ref.read(appDataProvider);
    final isDark = AppColors.isDark;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height + 6,
      offset.dx + size.width,
      offset.dy + size.height + 6,
    );

    final bg = isDark ? const Color(0xFF071F20) : Colors.white;
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);
    final textPrimary = AppColors.heading;
    final textMuted =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final selected = await showMenu<String>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      items: [
        // Section Header
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'PROPERTIES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: textMuted,
            ),
          ),
        ),

        // Each Property
        ...s.properties.map((p) {
          final isSelected = s.selectedPropertyId == p.id;
          final tenantCount = s.tenants
              .where((t) =>
                  (t.propertyId.isEmpty ? 'prop-default' : t.propertyId) ==
                  p.id)
              .length;

          return PopupMenuItem<String>(
            value: 'prop:${p.id}',
            height: 52,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0F766E).withValues(alpha: 0.18)
                        : (isDark
                            ? const Color(0xFF0F2627)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _iconForType(p.propertyType),
                    size: 16,
                    color: isSelected
                        ? const Color(0xFF14B8A6)
                        : textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        p.address.isNotEmpty
                            ? '${p.address} • $tenantCount/${p.totalUnits} units'
                            : '${p.propertyType.toUpperCase()} • $tenantCount/${p.totalUnits} units',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Ionicons.checkmark,
                    size: 16,
                    color: Color(0xFF14B8A6),
                  ),
                ],
                const SizedBox(width: 4),
                // Edit button
                IconButton(
                  icon: Icon(Ionicons.settingsOutline,
                      size: 14, color: textMuted),
                  tooltip: 'Property Settings',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    Navigator.of(context).pop();
                    DesktopPropertyModal.show(context, property: p);
                  },
                ),
              ],
            ),
          );
        }),

        const PopupMenuDivider(height: 12),

        // Action: Add Property
        PopupMenuItem<String>(
          value: 'add_new',
          height: 44,
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Ionicons.add,
                  size: 16,
                  color: Color(0xFF14B8A6),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Add New Property...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF14B8A6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    if (selected == 'add_new') {
      if (context.mounted) {
        DesktopPropertyModal.show(context);
      }
    } else if (selected.startsWith('prop:')) {
      final propId = selected.substring(5);
      ref.read(appDataProvider.notifier).selectProperty(propId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;

    final prop = s.activeProperty;
    final displayName = prop?.name ?? 'Select Property';
    final unitCount = prop != null && prop.totalUnits > 0
        ? prop.totalUnits
        : s.tenants
            .where((t) =>
                (t.propertyId.isEmpty ? 'prop-default' : t.propertyId) ==
                prop?.id)
            .length;
    final countLabel = '$unitCount units';
    final icon = _iconForType(prop?.propertyType ?? 'residential');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showPropertyMenu(context, ref),
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF0F766E).withValues(alpha: 0.06),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B2223) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color:
                    isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F2627)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Ionicons.chevronDown,
                size: 11,
                color:
                    isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
