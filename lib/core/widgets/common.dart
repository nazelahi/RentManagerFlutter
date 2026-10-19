import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/drive_backup_service.dart';
import '../state/app_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

import 'package:ionicons/ionicons.dart';

export '../theme/app_theme.dart';

String fmtMoney(String currency, dynamic amount) {
  final n = amount is num ? amount : num.tryParse('$amount') ?? 0;
  final s = NumberFormat('#,##0').format(n.abs());
  return n < 0 ? '-$currency$s' : '$currency$s';
}

String fmtDate(String iso, {String pattern = 'MMM d, yyyy'}) {
  try {
    return DateFormat(pattern).format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

/// Port of `src/components/Header.tsx`.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSettings;
  final VoidCallback? onInfo;
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSettings,
    this.onInfo,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: Responsive.font(context, 20),
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        if (onInfo != null)
          IconButton(
            icon: Icon(Icons.info_outline, color: AppColors.iconSecondary),
            onPressed: onInfo,
          ),
        if (onSettings != null)
          IconButton(
            icon: Icon(Icons.settings_outlined, color: AppColors.iconSecondary),
            onPressed: onSettings,
          ),
      ],
    ),
  );
}

/// Port of `src/components/EmptyState.tsx`.
/// Centralized haptic feedback so every surface feels the same.
/// Mobile impact presets; wraps try/catch so unsupported platforms are silent.
class AppHaptics {
  AppHaptics._();

  /// Light tick — selection, chip toggle, hoverless tap intent.
  static void light() => HapticFeedback.lightImpact().catchError((_) {});

  /// Medium thud — long-press → context menu, destructive intent.
  static void medium() => HapticFeedback.mediumImpact().catchError((_) {});

  /// Strong double-pulse — committed save / action success.
  static void success() => HapticFeedback.heavyImpact().catchError((_) {});

  /// Smart tap — light for soft targets, medium for destructive ones.
  static void tap({bool destructive = false}) =>
      destructive ? medium() : light();
}

/// Shared pull-to-refresh wrapper for mobile list scroll areas.
/// Pulls the latest Google Drive snapshot (when signed in / auto-sync on),
/// then reloads persistent storage state. Skips silently on errors.
class PullToRefresh extends ConsumerWidget {
  final Widget child;
  final bool reloadStorage;

  const PullToRefresh({
    super.key,
    required this.child,
    this.reloadStorage = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await DriveBackupService.checkAndPullLatest(ref);
        } catch (_) {}
        if (reloadStorage) {
          try {
            await ref.read(appDataProvider.notifier).loadAll();
          } catch (_) {}
        }
      },
      color: AppColors.primary,
      backgroundColor: AppColors.isDark
          ? const Color(0xFF0C2425)
          : Colors.white,
      strokeWidth: 2.4,
      displacement: 46,
      edgeOffset: 4,
      semanticsLabel: 'Refresh data',
      child: child,
    );
  }
}

// hook placeholder replaced below

/// Port of `src/components/EmptyState.tsx`.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.iconMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Status pill — port of getStatusColor/getStatusBackgroundColor usage.
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.statusBackground(status),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: AppColors.statusColor(status).withValues(alpha: 0.4),
      ),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(
        color: AppColors.statusColor(status),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Summary stat card (Income / Expenses / Net).
class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AmountText(value, size: 15, color: color),
        ],
      ),
    ),
  );
}

/// Tab selector — port of `TabSelector.tsx` (rentRoll | expenses)
/// with icons (people/card) and gradient active tab.
class RentExpenseTabs extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const RentExpenseTabs({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    Widget tab(String key, IconData icon, String label) {
      final active = value == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(key),
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
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.isDark ? null : AppColors.surface,
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
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          tab('rentRoll', Icons.people, 'Rent Roll'),
          tab('expenses', Icons.credit_card, 'Expenses'),
        ],
      ),
    );
  }
}

/// Month + year selector row — port of MonthYearPickerModal trigger row.
class MonthYearRow extends StatelessWidget {
  final int year;
  final int month;
  final ValueChanged<int> onMonth;
  final ValueChanged<int> onYear;
  const MonthYearRow({
    super.key,
    required this.year,
    required this.month,
    required this.onMonth,
    required this.onYear,
  });
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Row(
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left, color: AppColors.iconSecondary),
          onPressed: () {
            var m = month - 1, y = year;
            if (m < 1) {
              m = 12;
              y--;
            }
            onMonth(m);
            onYear(y);
          },
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => _MonthYearDialog(
                year: year,
                month: month,
                onPick: (m, y) {
                  onMonth(m);
                  onYear(y);
                },
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '${_months[month - 1]} $year',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, color: AppColors.iconSecondary),
          onPressed: () {
            var m = month + 1, y = year;
            if (m > 12) {
              m = 1;
              y++;
            }
            onMonth(m);
            onYear(y);
          },
        ),
      ],
    ),
  );
}

class _MonthYearDialog extends StatelessWidget {
  final int year, month;
  final void Function(int m, int y) onPick;
  const _MonthYearDialog({
    required this.year,
    required this.month,
    required this.onPick,
  });
  @override
  Widget build(BuildContext context) {
    var y = year;
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      title: Text(
        'Select Month & Year',
        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
      ),
      content: StatefulBuilder(
        builder: (ctx, setS) => SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove, color: AppColors.text),
                    onPressed: () => setS(() => y--),
                  ),
                  Text(
                    '$y',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add, color: AppColors.text),
                    onPressed: () => setS(() => y++),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var m = 1; m <= 12; m++)
                    ChoiceChip(
                      label: Text(
                        MonthYearRow._months[m - 1],
                        style: TextStyle(
                          color: m == month ? Colors.white : AppColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: m == month,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      onSelected: (_) {
                        onPick(m, y);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Themed text field — port of FormInput/FormField.
class AppField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final TextInputType keyboard;
  final int maxLines;
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard = TextInputType.text,
    this.maxLines = 1,
  });
  @override
  Widget build(BuildContext context) => Padding(
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
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(hintText: hint ?? label),
        ),
      ],
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String body,
) async =>
    (await showDialog<bool>(
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
        content: Text(body, style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    )) ??
    false;

/// Avatar with initial fallback — port of TenantAvatar/DefaultAvatar:
/// green gradient circle, white bold initial, optional green border.
class AvatarView extends StatefulWidget {
  final String name;
  final String? uri;
  final double radius;
  final Color? borderColor;
  final double borderWidth;
  const AvatarView({
    super.key,
    required this.name,
    this.uri,
    this.radius = 22,
    this.borderColor,
    this.borderWidth = 0,
  });

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  bool _loadError = false;

  @override
  void didUpdateWidget(covariant AvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _loadError = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    final u = widget.uri ?? '';
    if (u.isNotEmpty && !_loadError) {
      if (u.startsWith('http://') ||
          u.startsWith('https://') ||
          u.startsWith('content://')) {
        image = NetworkImage(u);
      } else {
        final filePath = u.startsWith('file://')
            ? Uri.parse(u).toFilePath()
            : u;
        final f = File(filePath);
        try {
          if (f.existsSync()) {
            image = FileImage(f);
          }
        } catch (_) {}
      }
    }

    final border = widget.borderWidth > 0
        ? Border.all(
            color: widget.borderColor ?? AppColors.primary,
            width: widget.borderWidth,
          )
        : null;

    if (image != null) {
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
      final targetPx = (widget.radius * 2 * dpr).ceil().clamp(32, 512);
      final optimizedImage = ResizeImage(
        image,
        width: targetPx,
        height: targetPx,
      );

      return Container(
        width: widget.radius * 2,
        height: widget.radius * 2,
        decoration: BoxDecoration(shape: BoxShape.circle, border: border),
        child: ClipOval(
          child: Image(
            image: optimizedImage,
            width: widget.radius * 2,
            height: widget.radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _loadError = true);
              });
              return _fallbackInitials(border);
            },
          ),
        ),
      );
    }
    return _fallbackInitials(border);
  }

  Widget _fallbackInitials(Border? border) {
    final n = widget.name.trim();
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark, Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        n.isEmpty ? '?' : n[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: widget.radius * 0.8,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Bottom-sheet drag handle — ports bottomSheetHandle (40x4).
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Bottom-sheet header — ports bottomSheetHeader: optional leading icon +
/// bold title on the left, optional trailing widget, close (X) button on the right,
/// followed by spacing and a surfaceBorder divider to match the Settings modal header.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onClose;
  final Widget? trailing;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;

  const SheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.showDivider = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: iconColor ?? AppColors.primary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.08)
                      : const Color.fromRGBO(0, 0, 0, 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Ionicons.close,
                  size: 18,
                  color: isDark ? Colors.white70 : const Color(0xFF4D6E6E),
                ),
              ),
            ),
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.surfaceBorder),
        ],
      ],
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    return content;
  }
}

/// Desktop hover/keyboard polish wrapper for list rows and cards.
/// Adds a mouse-hover tint (slight lift via scale), and draws a visible focus
/// ring when the card receives keyboard focus. Tap + long-press optional.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? hoverColor;
  final bool filled;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding,
    this.margin,
    this.hoverColor,
    this.filled = true,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final hoverTint =
        widget.hoverColor ??
        (isDark
            ? const Color.fromRGBO(255, 255, 255, 0.07)
            : const Color.fromRGBO(0, 0, 0, 0.035));
    final focusTint =
        widget.hoverColor ??
        (isDark
            ? const Color.fromRGBO(76, 175, 80, 0.16)
            : const Color.fromRGBO(76, 175, 80, 0.10));

    Widget core = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        color: _hovering
            ? hoverTint
            : _focused
            ? focusTint
            : (widget.filled ? AppColors.surface : Colors.transparent),
        border: _focused || _hovering
            ? Border.all(
                color: AppColors.primary.withValues(
                  alpha: _focused ? 0.55 : 0.25,
                ),
              )
            : null,
      ),
      child: widget.child,
    );

    core = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: (widget.onTap != null || widget.onLongPress != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: Focus(
        onFocusChange: (focus) => setState(() => _focused = focus),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            final cb = widget.onTap;
            if (cb != null) {
              cb();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: widget.borderRadius,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: core,
        ),
      ),
    );
    if (widget.margin != null) {
      core = Padding(padding: widget.margin!, child: core);
    }
    return core;
  }
}

/// Listen-only hover wrapper that rebuilds its child with the hover state.
/// For cards whose inner Container paints an opaque color on top of the
/// InkWell, so a plain theme hoverColor never shows: pass the hovered flag
/// into the builder and swap the surface color yourself.
class HoverTinter extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  const HoverTinter({super.key, required this.builder});

  @override
  State<HoverTinter> createState() => _HoverTinterState();
}

class _HoverTinterState extends State<HoverTinter> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: widget.builder(_hovering),
  );
}

/// Primary gradient button — ports saveButton/saveGradient
/// (green gradient, height 44, radius 12, white 600 text).
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final TextStyle? textStyle;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height,
    this.borderRadius,
    this.textStyle,
  });

  GradientButton.icon({
    super.key,
    required this.onPressed,
    required Widget icon,
    required Widget label,
    this.height,
    this.borderRadius,
    this.textStyle,
  }) : child = _IconLabel(icon: icon, label: label);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final r = borderRadius ?? BorderRadius.circular(12);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: height ?? 44,
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                )
              : null,
          color: enabled ? null : const Color.fromRGBO(128, 128, 128, 0.3),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: r is BorderRadius ? r : BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: DefaultTextStyle(
                  style:
                      textStyle ??
                      TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: enabled ? Colors.white : Colors.white54,
                      ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  final Widget icon;
  final Widget label;
  const _IconLabel({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [icon, const SizedBox(width: 6), label],
  );
}

/// Danger outline button — ports cancelButton (red tint outline).
class DangerButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final TextStyle? textStyle;

  const DangerButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height,
    this.borderRadius,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final r = borderRadius ?? BorderRadius.circular(12);
    return SizedBox(
      height: height ?? 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: Color.fromRGBO(244, 67, 54, 0.3),
            width: 1.5,
          ),
          backgroundColor: const Color.fromRGBO(244, 67, 54, 0.1),
          foregroundColor: const Color(0xFFF44336),
          shape: RoundedRectangleBorder(borderRadius: r),
          textStyle:
              textStyle ??
              const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
        ),
        child: child,
      ),
    );
  }
}

/// Ambient theme-based background with subtle radial glows and atmospheric gradient.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 1. Primary atmospheric gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.backgroundGradient(isDark),
            ),
          ),
        ),
        // 2. Subtle top-right ambient emerald glow
        Positioned(
          top: -40,
          right: -40,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF10B981).withValues(alpha: 0.12),
                          const Color(0xFF0F766E).withValues(alpha: 0.04),
                          Colors.transparent,
                        ]
                      : [
                          const Color(0xFF10B981).withValues(alpha: 0.10),
                          const Color(0xFF34D399).withValues(alpha: 0.04),
                          Colors.transparent,
                        ],
                ),
              ),
            ),
          ),
        ),
        // 3. Subtle mid-left ambient teal glow
        Positioned(
          top: 320,
          left: -60,
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF0F766E).withValues(alpha: 0.08),
                          Colors.transparent,
                        ]
                      : [
                          const Color(0xFF059669).withValues(alpha: 0.04),
                          Colors.transparent,
                        ],
                ),
              ),
            ),
          ),
        ),
        // 4. Foreground content
        child,
      ],
    );
  }
}

/// Active desktop toast overlay entry to ensure clean single-notification replacement.
OverlayEntry? _activeDesktopToastEntry;
Timer? _activeDesktopToastTimer;

/// Displays an adaptive toast notification:
/// - On Desktop (screen width >= 800px): Sleek Top-Right macOS-style Notification HUD
///   with frosted glassmorphism, animated entrance, hover-pause, and direct dismiss.
/// - On Mobile: Standard floating bottom SnackBar.
void showAppToast(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final isDesktop = Responsive.isDesktop(context);

  if (isDesktop) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      _showDesktopTopRightToast(
        overlay: overlay,
        context: context,
        message: message,
        isError: isError,
        isSuccess: isSuccess,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );
      return;
    }
  }

  // Fallback / Mobile: Standard SnackBar
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearSnackBars();

  final bg = isError
      ? (AppColors.isDark ? const Color(0xFF3B1818) : const Color(0xFFFFEBEE))
      : isSuccess
      ? (AppColors.isDark ? const Color(0xFF133826) : const Color(0xFFE8F5E9))
      : (AppColors.isDark ? const Color(0xFF1E293B) : const Color(0xFF263238));

  final borderColor = isError
      ? AppColors.error.withValues(alpha: 0.5)
      : isSuccess
      ? AppColors.success.withValues(alpha: 0.5)
      : (AppColors.isDark ? Colors.white24 : Colors.black12);

  final textColor = isError
      ? (AppColors.isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828))
      : isSuccess
      ? (AppColors.isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
      : Colors.white;

  final iconData = isError
      ? Icons.error_outline_rounded
      : isSuccess
      ? Icons.check_circle_outline_rounded
      : Icons.info_outline_rounded;

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      duration: duration,
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      content: Row(
        children: [
          Icon(iconData, size: 20, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      action: actionLabel != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: isError ? AppColors.error : AppColors.primary,
              onPressed: onAction ?? () {},
            )
          : null,
    ),
  );
}

void _showDesktopTopRightToast({
  required OverlayState overlay,
  required BuildContext context,
  required String message,
  required bool isError,
  required bool isSuccess,
  required Duration duration,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _activeDesktopToastTimer?.cancel();
  _activeDesktopToastEntry?.remove();
  _activeDesktopToastEntry = null;

  final isDark = Theme.of(context).brightness == Brightness.dark;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _DesktopToastWidget(
      message: message,
      isError: isError,
      isSuccess: isSuccess,
      isDark: isDark,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: () {
        _activeDesktopToastTimer?.cancel();
        if (_activeDesktopToastEntry == entry) {
          entry.remove();
          _activeDesktopToastEntry = null;
        }
      },
    ),
  );

  _activeDesktopToastEntry = entry;
  overlay.insert(entry);
}

class _DesktopToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final bool isSuccess;
  final bool isDark;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _DesktopToastWidget({
    required this.message,
    required this.isError,
    required this.isSuccess,
    required this.isDark,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  @override
  State<_DesktopToastWidget> createState() => _DesktopToastWidgetState();
}

class _DesktopToastWidgetState extends State<_DesktopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _controller.forward();
    _startTimer(widget.duration);
  }

  void _startTimer(Duration duration) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(duration, _dismiss);
  }

  void _pauseTimer() {
    _dismissTimer?.cancel();
  }

  void _resumeTimer() {
    _startTimer(const Duration(milliseconds: 2000));
  }

  void _dismiss() {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    _dismissTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    final bg = widget.isError
        ? (isDark ? const Color(0xEB2B1114) : const Color(0xFBFDF2F2))
        : widget.isSuccess
        ? (isDark ? const Color(0xEB0A251B) : const Color(0xFBF0FDF4))
        : (isDark ? const Color(0xEB0E1E26) : const Color(0xFBF8FAFC));

    final borderColor = widget.isError
        ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.45 : 0.35)
        : widget.isSuccess
        ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.45 : 0.35)
        : (isDark
              ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
              : const Color(0xFF0284C7).withValues(alpha: 0.25));

    final iconBg = widget.isError
        ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.20 : 0.14)
        : widget.isSuccess
        ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.14)
        : const Color(0xFF0284C7).withValues(alpha: isDark ? 0.20 : 0.12);

    final iconColor = widget.isError
        ? const Color(0xFFEF4444)
        : widget.isSuccess
        ? const Color(0xFF10B981)
        : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7));

    final title = widget.isError
        ? 'ALERT'
        : widget.isSuccess
        ? 'SUCCESS'
        : 'RENTMANAGER';

    final titleColor = widget.isError
        ? const Color(0xFFF87171)
        : widget.isSuccess
        ? const Color(0xFF34D399)
        : (isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7));

    final textColor = widget.isError
        ? (isDark ? const Color(0xFFFEE2E2) : const Color(0xFF991B1B))
        : widget.isSuccess
        ? (isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46))
        : (AppColors.heading);

    final iconData = widget.isError
        ? Ionicons.alertCircleOutline
        : widget.isSuccess
        ? Ionicons.checkmarkCircleOutline
        : Ionicons.informationCircleOutline;

    return Positioned(
      top: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.35, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: Curves.easeOutCubic,
                ),
              ),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
            child: MouseRegion(
              onEnter: (_) => _pauseTimer(),
              onExit: (_) => _resumeTimer(),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 390, minWidth: 310),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.12,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: iconColor.withValues(alpha: isDark ? 0.12 : 0.06),
                      blurRadius: 20,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: 1.2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status Icon Badge (34x34)
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(iconData, size: 19, color: iconColor),
                          ),
                          const SizedBox(width: 12),
                          // Content Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: titleColor,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'now',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.message,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                                if (widget.actionLabel != null) ...[
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () {
                                      _dismiss();
                                      widget.onAction?.call();
                                    },
                                    child: Text(
                                      widget.actionLabel!,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: iconColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Close ✕ button
                          IconButton(
                            icon: const Icon(Ionicons.close, size: 15),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            splashRadius: 16,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            onPressed: _dismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Adaptive modal sheet that displays as a sleek Right-Side Slide-Over Drawer
/// on desktop/macOS (Linear / Xcode inspector style) and a standard Bottom Sheet on mobile.
Future<T?> showAdaptiveModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  double desktopWidth = 520,
}) {
  final isDesktop = Responsive.isDesktop(context);
  if (isDesktop) {
    final isDark = AppColors.isDark;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: barrierLabel ?? 'Dismiss',
      barrierColor:
          barrierColor ?? Colors.black.withValues(alpha: isDark ? 0.45 : 0.28),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: isDark
                ? const Color(0xFF051515)
                : (backgroundColor ?? AppColors.sheetBackground),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
            child: Container(
              width: desktopWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.08)
                        : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                child: AppBackground(child: SafeArea(child: builder(ctx))),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  final isDark = AppColors.isDark;
  final effectiveConstraints =
      constraints ??
      BoxConstraints(
        maxWidth: double.infinity,
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      );
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierLabel: barrierLabel,
    elevation: elevation ?? 0,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: effectiveConstraints,
    barrierColor:
        barrierColor ?? Colors.black.withValues(alpha: isDark ? 0.45 : 0.28),
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    builder: (sheetCtx) {
      final isDark = AppColors.isDark;
      return Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF051515)
              : (backgroundColor ?? AppColors.sheetBackground),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            left: BorderSide(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            right: BorderSide(
              color: isDark
                  ? const Color.fromRGBO(255, 255, 255, 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: Colors.transparent,
            child: AppBackground(child: builder(sheetCtx)),
          ),
        ),
      );
    },
  );
}

/// Standardized height tiers for bottom modal sheets.
enum SheetSize {
  /// Compact content-focused sheets (e.g. quick pickers, confirmations). Max ~55% screen height.
  compact,

  /// Standard form sheet (e.g. Add Expense, Add Tenant, Add Payment). Max ~85% screen height.
  standard,

  /// Deep / multi-section sheet (e.g. Document preview, Detailed checklist). Max ~95% screen height.
  expanded,
}

/// Unified, reusable modal sheet container that enforces visual consistency across
/// all mobile bottom sheets and desktop slide-over panels.
class AppModalSheet extends StatelessWidget {
  /// The modal title. If provided, renders a standard [SheetHeader].
  final String? title;

  /// Optional subtitle rendered beneath [title].
  final String? subtitle;

  /// Optional leading icon in header.
  final IconData? icon;

  /// Optional color for [icon]. Defaults to [AppColors.primary].
  final Color? iconColor;

  /// Optional trailing widget in header (e.g., status pill, extra actions).
  final Widget? headerTrailing;

  /// Callback when header close (X) button is pressed. Defaults to `Navigator.of(context).pop()`.
  final VoidCallback? onClose;

  /// Completely custom header widget if not using [title] + [SheetHeader].
  final Widget? customHeader;

  /// Whether to show the bottom border divider in the header. Defaults to true.
  final bool showHeaderDivider;

  /// The main content of the sheet.
  final Widget body;

  /// Optional pinned footer at the bottom of the sheet (e.g., [SheetActions]).
  final Widget? footer;

  /// Standardized height tier. Defaults to [SheetSize.standard].
  final SheetSize size;

  /// Optional custom maximum height factor (0.0 to 1.0). Overrides [size] if set.
  final double? customMaxHeightFactor;

  /// Whether the [body] should be automatically wrapped in a [SingleChildScrollView]. Defaults to true.
  final bool scrollable;

  /// Content padding. Defaults to `EdgeInsets.fromLTRB(10, 16, 10, 20)`.
  final EdgeInsetsGeometry padding;

  /// Cross axis alignment for the sheet layout. Defaults to [CrossAxisAlignment.stretch].
  final CrossAxisAlignment crossAxisAlignment;

  /// Whether to automatically pad the bottom to avoid the software keyboard. Defaults to true.
  final bool avoidBottomInset;

  const AppModalSheet({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.headerTrailing,
    this.onClose,
    this.customHeader,
    this.showHeaderDivider = true,
    required this.body,
    this.footer,
    this.size = SheetSize.standard,
    this.customMaxHeightFactor,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(10, 16, 10, 20),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.avoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxFactor =
        customMaxHeightFactor ??
        switch (size) {
          SheetSize.compact => 0.55,
          SheetSize.standard => 0.85,
          SheetSize.expanded => 0.95,
        };
    final maxHeight = screenHeight * maxFactor;

    Widget headerWidget;
    if (customHeader != null) {
      headerWidget = customHeader!;
    } else if (title != null) {
      headerWidget = SheetHeader(
        title: title!,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        trailing: headerTrailing,
        showDivider: showHeaderDivider,
        onClose: onClose ?? () => Navigator.of(context).pop(),
      );
    } else {
      headerWidget = const SizedBox.shrink();
    }

    final hasHeader = headerWidget is! SizedBox;
    final resolvedPadding = padding.resolve(Directionality.of(context));
    // Unified 10dp horizontal padding across all bottom modal sheet sections (Header, Body, Footer).
    final horizontalPad = resolvedPadding.left > 0
        ? resolvedPadding.left
        : 10.0;

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (hasHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPad,
                resolvedPadding.top,
                horizontalPad,
                0,
              ),
              child: headerWidget,
            ),
          if (hasHeader) const SizedBox(height: 10),
          Flexible(
            child: scrollable
                ? SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      hasHeader ? 0 : resolvedPadding.top,
                      horizontalPad,
                      footer != null ? 12 : resolvedPadding.bottom,
                    ),
                    child: body,
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      hasHeader ? 0 : resolvedPadding.top,
                      horizontalPad,
                      footer != null ? 12 : resolvedPadding.bottom,
                    ),
                    child: body,
                  ),
          ),
          if (footer != null) _DockedSheetFooter(child: footer!),
        ],
      ),
    );

    if (avoidBottomInset) {
      content = Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: content,
      );
    }

    return Material(color: Colors.transparent, child: content);
  }
}

/// Pinned docked bottom action bar container for modal sheets.
class _DockedSheetFooter extends StatelessWidget {
  final Widget child;
  const _DockedSheetFooter({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    // When keyboard is open, keyboard already pushes the sheet up above itself.
    // When closed, add comfortable spacing for device home indicator/gesture navigation.
    final effectiveBottomPadding = bottomInset > 0
        ? 8.0
        : (8.0 +
              (safeAreaBottom > 0
                  ? (safeAreaBottom * 0.4).clamp(4.0, 14.0)
                  : 0.0));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF071818) : const Color(0xFFFCFDFD),
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.08)
                : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(10, 8, 10, effectiveBottomPadding),
      child: child,
    );
  }
}

/// Standardized action footer for modal sheets (Cancel + Primary Action button).
class SheetActions extends StatelessWidget {
  /// The primary button label (e.g. "Save", "Submit", "Add Expense").
  final String primaryLabel;

  /// The primary button callback. If null, button appears disabled.
  final VoidCallback? onPrimary;

  /// Optional icon for primary button.
  final Widget? primaryIcon;

  /// Secondary/Cancel button label. Defaults to 'Cancel'. If empty, cancel button is omitted.
  final String cancelLabel;

  /// Secondary/Cancel button callback. Defaults to `Navigator.of(context).pop()`.
  final VoidCallback? onCancel;

  /// Optional icon for cancel button.
  final Widget? cancelIcon;

  /// Optional leading action widget (e.g., delete/archive button).
  final Widget? leadingAction;

  /// Shows loading indicator in place of primary button.
  final bool isLoading;

  /// Flex ratio for primary button. Defaults to 2.
  final int primaryFlex;

  /// Flex ratio for cancel button. Defaults to 1.
  final int cancelFlex;

  /// Button row height. Defaults to 40 (compact size).
  final double height;

  /// Whether to show a top divider above the actions row. Defaults to false.
  final bool showTopDivider;

  const SheetActions({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.cancelIcon,
    this.leadingAction,
    this.isLoading = false,
    this.primaryFlex = 2,
    this.cancelFlex = 1,
    this.height = 40,
    this.showTopDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final row = Row(
      children: [
        if (leadingAction != null) ...[
          leadingAction!,
          const SizedBox(width: 8),
        ],
        if (cancelLabel.isNotEmpty) ...[
          Expanded(
            flex: cancelFlex,
            child: SizedBox(
              height: height,
              child: OutlinedButton(
                onPressed: onCancel ?? () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  side: BorderSide(
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.12)
                        : const Color(0xFFD2DCDC),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundColor: AppColors.textSecondary,
                  backgroundColor: isDark
                      ? const Color.fromRGBO(255, 255, 255, 0.04)
                      : const Color(0xFFF1F5F5),
                ),
                child: cancelIcon != null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          cancelIcon!,
                          const SizedBox(width: 5),
                          Text(
                            cancelLabel,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        cancelLabel,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: primaryFlex,
          child: SizedBox(
            height: height,
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : (primaryIcon != null
                      ? GradientButton.icon(
                          height: height,
                          borderRadius: BorderRadius.circular(10),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          ),
                          icon: primaryIcon!,
                          label: Text(primaryLabel),
                          onPressed: onPrimary,
                        )
                      : GradientButton(
                          height: height,
                          borderRadius: BorderRadius.circular(10),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          ),
                          onPressed: onPrimary,
                          child: Text(primaryLabel),
                        )),
          ),
        ),
      ],
    );

    if (showTopDivider) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.surfaceBorder, width: 1),
          ),
        ),
        padding: const EdgeInsets.only(top: 8),
        child: row,
      );
    }
    return row;
  }
}
