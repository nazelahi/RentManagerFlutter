import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Platform channel bridge to native macOS window management.
class DesktopWindowService {
  DesktopWindowService._();

  static const MethodChannel _channel =
      MethodChannel('com.nazelahi.rentmanager/window');

  /// Closes the application window.
  static Future<void> close() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('close');
    } catch (_) {}
  }

  /// Minimizes the window to the macOS Dock.
  static Future<void> minimize() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('minimize');
    } catch (_) {}
  }

  /// Toggles native macOS full-screen mode.
  static Future<void> toggleFullScreen() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('toggleFullScreen');
    } catch (_) {}
  }

  /// Zooms/maximizes the window.
  static Future<void> zoom() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('zoom');
    } catch (_) {}
  }

  /// Checks if the window is currently in full-screen mode.
  static Future<bool> isFullScreen() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isFullScreen');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Custom-styled macOS Window Controller Buttons (Traffic Lights).
///
/// Features rich Liquid Glass aesthetics, tactile hover micro-animations,
/// crisp icon glyphs, and tooltips.
class DesktopWindowControls extends StatefulWidget {
  final double size;
  final double spacing;
  final bool showIconsOnlyOnHover;

  const DesktopWindowControls({
    super.key,
    this.size = 12.5,
    this.spacing = 7.5,
    this.showIconsOnlyOnHover = true,
  });

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls> {
  bool _isGroupHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isGroupHovered = true),
      onExit: (_) => setState(() => _isGroupHovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Close Button (Coral Red)
          _WindowButton(
            tooltip: 'Close (⌘W)',
            baseColor: const Color(0xFFFF5F56),
            borderColor: const Color(0xFFE0443E),
            hoverIcon: Icons.close_rounded,
            iconSize: 8.5,
            size: widget.size,
            isGroupHovered: _isGroupHovered,
            alwaysShowIcon: !widget.showIconsOnlyOnHover,
            onTap: DesktopWindowService.close,
          ),
          SizedBox(width: widget.spacing),

          // 2. Minimize Button (Amber Gold)
          _WindowButton(
            tooltip: 'Minimize (⌘M)',
            baseColor: const Color(0xFFFFBD2E),
            borderColor: const Color(0xFFDEA123),
            hoverIcon: Icons.remove_rounded,
            iconSize: 9.0,
            size: widget.size,
            isGroupHovered: _isGroupHovered,
            alwaysShowIcon: !widget.showIconsOnlyOnHover,
            onTap: DesktopWindowService.minimize,
          ),
          SizedBox(width: widget.spacing),

          // 3. Zoom / Full-Screen Button (Emerald Green)
          _WindowButton(
            tooltip: 'Toggle Full Screen (⌃⌘F)',
            baseColor: const Color(0xFF27C93F),
            borderColor: const Color(0xFF1AAB29),
            hoverIcon: Icons.unfold_more_rounded,
            iconRotation: 0.785398, // 45 degrees
            iconSize: 8.5,
            size: widget.size,
            isGroupHovered: _isGroupHovered,
            alwaysShowIcon: !widget.showIconsOnlyOnHover,
            onTap: DesktopWindowService.toggleFullScreen,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final String tooltip;
  final Color baseColor;
  final Color borderColor;
  final IconData hoverIcon;
  final double iconSize;
  final double? iconRotation;
  final double size;
  final bool isGroupHovered;
  final bool alwaysShowIcon;
  final VoidCallback onTap;

  const _WindowButton({
    required this.tooltip,
    required this.baseColor,
    required this.borderColor,
    required this.hoverIcon,
    required this.iconSize,
    this.iconRotation,
    required this.size,
    required this.isGroupHovered,
    required this.alwaysShowIcon,
    required this.onTap,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isItemHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final showIcon = widget.alwaysShowIcon || widget.isGroupHovered;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isItemHovered = true),
          onExit: (_) => setState(() => _isItemHovered = false),
          child: AnimatedScale(
            scale: _isPressed
                ? 0.90
                : (_isItemHovered ? 1.15 : 1.0),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.baseColor,
                border: Border.all(
                  color: widget.borderColor,
                  width: 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.baseColor.withValues(
                      alpha: _isItemHovered ? 0.55 : 0.20,
                    ),
                    blurRadius: _isItemHovered ? 6 : 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedOpacity(
                  opacity: showIcon ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: Transform.rotate(
                    angle: widget.iconRotation ?? 0.0,
                    child: Icon(
                      widget.hoverIcon,
                      size: widget.iconSize,
                      color: const Color(0xFF4A100B).withValues(alpha: 0.75),
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
