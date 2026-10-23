import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/models/game.dart';
import '../../core/platform_info.dart';
import '../../services/hardware/hardware_service.dart';
import '../../ui/theme.dart';
import 'game_details_page.dart';

/// Requisitos declarados x seu dispositivo.
class RequirementsTab extends StatelessWidget {
  const RequirementsTab({super.key, required this.game});
  final Game game;

  static String _tier(int? t) => t == null
      ? '—'
      : t >= 85
          ? 'Alto ($t)'
          : t >= 50
              ? 'Médio ($t)'
              : 'Básico ($t)';

  static String _v(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  Widget build(BuildContext context) {
    final r = game.requirements;
    final hw = context.watch<HardwareService>().profile;
    final rows = <(String, String, String)>[
      ('Plataformas', r.platforms.isEmpty ? 'Conforme releases' : r.platforms.map(platformLabel).join(', '), platformLabel(hw?.platform ?? hostPlatform.name)),
      ('Arquitetura', r.architectures.isEmpty ? 'Qualquer' : r.architectures.map(archLabel).join(', '), archLabel(hw?.primaryArch)),
      ('RAM mínima', formatRamMb(r.minRamMb), formatRamMb(hw?.ramMb)),
      if (r.recommendedRamMb != null) ('RAM recomendada', formatRamMb(r.recommendedRamMb), formatRamMb(hw?.ramMb)),
      if (r.minAndroid != null || hw?.platform == 'android') ('Android', r.minAndroid == null ? '—' : '${_v(r.minAndroid)}+', hw?.osVersion ?? '—'),
      ('Vulkan', r.vulkan == null ? 'Não declarado' : (r.vulkan! ? 'Obrigatório' : 'Não usa'), hw == null ? '—' : (hw.vulkan ? 'Suportado ${hw.vulkanVersion ?? ''}' : 'Não suportado')),
      if (r.minGlEs != null || hw?.platform == 'android') ('OpenGL ES', r.minGlEs == null ? '—' : '${_v(r.minGlEs)}+', _v(hw?.glEsVersion)),
      if (r.minOpenGl != null || (hw != null && hw.platform != 'android')) ('OpenGL', r.minOpenGl == null ? '—' : '${_v(r.minOpenGl)}+', _v(hw?.openGlVersion)),
      if (r.minDirectX != null || hw?.platform == 'windows') ('DirectX', r.minDirectX == null ? '—' : '${r.minDirectX}+', hw?.directX?.toString() ?? '—'),
      ('Armazenamento', r.minStorageMb == null ? formatBytes(game.size) : formatRamMb(r.minStorageMb), formatRamMb(hw?.freeStorageMb)),
      ('Desempenho de CPU', _tier(r.cpuTier), hw?.cpuName ?? hw?.socModel ?? '—'),
      ('Desempenho de GPU', _tier(r.gpuTier), hw?.gpuName ?? '—'),
    ];

    return Panel(
      title: 'Requisitos',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.4)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            const TableRow(children: [
              _H('Item'),
              _H('Exigido'),
              _H('Seu dispositivo'),
            ]),
            for (final (label, need, have) in rows)
              TableRow(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: PH.stroke))),
                children: [
                  _C(label, dim: true),
                  _C(need),
                  _C(have),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          r.sources.isEmpty
              ? 'O repositório não declara requisitos. Porters podem adicionar um porthub.yaml (veja o README do PortHub).'
              : 'Fonte: ${r.sources.join(', ')}',
          style: const TextStyle(color: PH.textFaint, fontSize: 12.5),
        ),
      ]),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}

class _C extends StatelessWidget {
  const _C(this.t, {this.dim = false});
  final String t;
  final bool dim;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: dim ? PH.textDim : PH.text)),
      );
}
