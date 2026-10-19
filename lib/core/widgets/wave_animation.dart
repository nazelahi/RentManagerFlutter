import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

/// Port of `src/components/GenericWaveAnimation.tsx` — a looping skeleton
/// "wave" used while data is loading or switching between tabs/months.
class WaveAnimation extends StatefulWidget {
  final int count;
  final String type; // inflow | outflow | neutral
  final IconData icon;
  const WaveAnimation({
    super.key,
    this.count = 6,
    this.type = 'neutral',
    this.icon = Ionicons.barChart,
  });

  @override
  State<WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<WaveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  int get _n => widget.count.clamp(1, 20);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_n - 1) * 120 + 800 + 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.type) {
      case 'inflow':
        return const Color(0xFF4CAF50);
      case 'outflow':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFF2196F3);
    }
  }

  Color get _rippleColor {
    switch (widget.type) {
      case 'inflow':
        return const Color.fromRGBO(76, 175, 80, 0.1);
      case 'outflow':
        return const Color.fromRGBO(255, 107, 107, 0.1);
      default:
        return const Color.fromRGBO(33, 150, 243, 0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(_n, _row),
    );
  }

  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  Widget _row(int i) {
    final total = _c.duration!.inMilliseconds.toDouble();
    final start = i * 120.0;
    final waveA = start / total, waveB = (start + 800) / total;
    final opA = (start + 100) / total, opB = (start + 700) / total;
    final ripA = (start + 300) / total, ripB = (start + 1300) / total;
    final c = _color;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value;
        final wp = _seg(t, waveA, waveB);
        final op = _seg(t, opA, opB);
        final waveOpacity =
            wp < 0.3 ? wp / 0.3 * 0.7 : 0.7 + 0.3 * ((wp - 0.3) / 0.7);
        final opacity = (op * waveOpacity).clamp(0.0, 1.0);
        final scale = 0.85 + 0.15 * wp;
        final rp = _seg(t, ripA, ripB);
        final rippleOpacity =
            rp <= 0 ? 0.0 : (rp < 0.5 ? rp * 0.6 : (1 - rp) * 0.6);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Stack(
            children: [
              Opacity(
                opacity: rippleOpacity,
                child: Transform.scale(
                  scale: 0.8 + 0.3 * rp,
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: _rippleColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(0, 50 * (1 - wp)),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color.fromRGBO(255, 255, 255, 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(widget.icon, size: 14, color: c),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FractionallySizedBox(
                                  widthFactor: 0.8,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: const Color.fromRGBO(
                                          255, 255, 255, 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FractionallySizedBox(
                                  widthFactor: 0.6,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: const Color.fromRGBO(
                                          255, 255, 255, 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 16,
                            width: 80,
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(4),
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
      },
    );
  }
}
