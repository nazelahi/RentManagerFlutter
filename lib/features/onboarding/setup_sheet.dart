import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';

/// Opens a modal bottom sheet sized like the Expo `bottomSheetContent`
/// (backgroundDark, top radius 20, ~90% of the available viewport).
/// Keyboard insets are handled by [AppModalSheet] itself (avoidBottomInset),
/// and the height cap is derived from the keyboard-adjusted available space.
Future<T?> showSetupSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext ctx, double height) builder,
}) {
  final height = MediaQuery.of(context).size.height * 0.9;
  return showAdaptiveModalSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.overlay,
    builder: (ctx) => builder(ctx, height),
  );
}

/// Standard bottom-sheet container: handle bar, header (icon + title + close),
/// body (fills remaining space) and an optional footer.
class SetupSheet extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback? onClose;
  final Widget body;
  final Widget? footer;

  const SetupSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor = AppColors.primary,
    this.onClose,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Cap the sheet height at ~90% of the space still visible above the
    // software keyboard so content (including buttons) stays reachable.
    final available = (mq.size.height - mq.viewInsets.bottom) * 0.9;
    final factor = (available / mq.size.height).clamp(0.4, 0.95);

    return AppModalSheet(
      icon: icon,
      iconColor: iconColor,
      title: title,
      customMaxHeightFactor: factor,
      scrollable: false,
      avoidBottomInset: true,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 20),
      body: body,
      footer: footer,
    );
  }
}
