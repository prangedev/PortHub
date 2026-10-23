import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../ui/theme.dart';

/// Bolinha de compatibilidade (verde / amarelo / vermelho) com score opcional.
class CompatBadge extends StatelessWidget {
  const CompatBadge({super.key, required this.result, this.showScore = true, this.showLabel = false, this.size = 10});
  final CompatibilityResult result;
  final bool showScore;
  final bool showLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PH.compat(result.level);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)]),
      ),
      if (showScore && result.level != CompatLevel.unknown) ...[
        const SizedBox(width: 6),
        Text('${result.score}%', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: size * 1.25)),
      ],
      if (showLabel) ...[
        const SizedBox(width: 6),
        Text(result.level.label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: size * 1.25)),
      ],
    ]);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});
  final InstallStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      InstallStatus.installed => (PH.green, Icons.check_circle_rounded),
      InstallStatus.updateAvailable => (PH.yellow, Icons.system_update_alt_rounded),
      InstallStatus.notInstalled => (PH.textDim, Icons.cloud_download_outlined),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: dense ? 12 : 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            dense && status == InstallStatus.updateAvailable ? 'Atualizar' : status.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: dense ? 10.5 : 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class TagPill extends StatelessWidget {
  const TagPill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? PH.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PH.stroke),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// Anel de score de compatibilidade (0–100).
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.result, this.size = 96});
  final CompatibilityResult result;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PH.compat(result.level);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: result.score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, c),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(result.level == CompatLevel.unknown ? '—' : '${(v * 100).round()}%',
                  style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w900, color: c)),
              Text('compat.', style: TextStyle(fontSize: size * 0.11, color: PH.textDim)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// Barra de progresso fina estilo Steam.
class PHProgress extends StatelessWidget {
  const PHProgress({super.key, required this.value, this.height = 6, this.color = PH.accent});
  final double? value;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: value, minHeight: height, backgroundColor: Colors.white10, color: color),
      );
}
