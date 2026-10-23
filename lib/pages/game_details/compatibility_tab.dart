import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/models/compatibility_result.dart';
import '../../core/models/game.dart';
import '../../core/platform_info.dart';
import '../../services/hardware/hardware_service.dart';
import '../../ui/theme.dart';
import '../../widgets/badges.dart';
import 'game_details_page.dart';

/// Relatório completo do motor de compatibilidade:
/// "Seu dispositivo" → "Resultado" → verificações (✔ / ⚠ / ✖) → pontuação por componente.
class CompatibilityTab extends StatelessWidget {
  const CompatibilityTab({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final hw = context.watch<HardwareService>().profile;
    final c = game.compatibility;
    final wide = !PH.compact(context);

    final device = Panel(
      title: 'Seu dispositivo',
      child: hw == null
          ? const Text('Hardware ainda não analisado.', style: TextStyle(color: PH.textDim))
          : Column(children: [
              InfoRow('Aparelho', hw.deviceLabel),
              InfoRow('CPU', hw.cpuName ?? hw.socModel ?? '—'),
              InfoRow('GPU', hw.gpuName ?? '—'),
              InfoRow('RAM', formatRamMb(hw.ramMb)),
              InfoRow('Arquitetura', archLabel(hw.primaryArch)),
              InfoRow(platformLabel(hw.platform), hw.platform == 'linux' ? (hw.distro ?? hw.kernel ?? '—') : (hw.osVersion ?? '—')),
            ]),
    );

    final result = Panel(
      title: 'Resultado',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ScoreRing(result: c, size: 110),
          const SizedBox(width: 22),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Compatibilidade: ${c.score}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(c.level.label, style: TextStyle(color: PH.compat(c.level), fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text(c.message),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        for (final e in CompatibilityResult.maxBreakdown.entries) _Bar(label: e.key, value: c.breakdown[e.key] ?? 0, max: e.value),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (wide)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: device),
              const SizedBox(width: 16),
              Expanded(child: result),
            ]),
          ),
        )
      else ...[
        device,
        result,
      ],
      Panel(
        title: 'Verificações',
        child: Column(children: [
          for (final check in c.checks) _CheckRow(check: check),
          if (c.checks.isEmpty) const Text('Sem verificações (hardware não analisado).', style: TextStyle(color: PH.textDim)),
        ]),
      ),
      if (c.estimated)
        const Panel(
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: PH.yellow),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Este repositório não declara requisitos. A avaliação usa arquitetura dos arquivos, API gráfica e '
                'a tabela de desempenho de CPU/GPU — veja também os relatos da comunidade.',
                style: TextStyle(color: PH.textDim),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});
  final CompatCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      CheckStatus.pass => (Icons.check_rounded, PH.green),
      CheckStatus.warn => (Icons.warning_amber_rounded, PH.yellow),
      CheckStatus.fail => (Icons.close_rounded, PH.red),
      CheckStatus.unknown => (Icons.help_outline_rounded, PH.textFaint),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 14),
        SizedBox(width: 140, child: Text(check.label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text(check.detail, style: TextStyle(color: check.status == CheckStatus.fail ? PH.red : PH.text))),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.max});
  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final f = max == 0 ? 0.0 : value / max;
    final color = f >= 0.8 ? PH.green : (f >= 0.5 ? PH.yellow : PH.red);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: PH.textDim, fontWeight: FontWeight.w600))),
        Expanded(child: PHProgress(value: f, height: 8, color: color)),
        SizedBox(width: 60, child: Text('$value/$max', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
