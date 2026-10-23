import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compatibility/hardware_tiers.dart';
import '../core/formatters.dart';
import '../core/models/hardware_profile.dart';
import '../core/platform_info.dart';
import '../services/hardware/hardware_service.dart';
import '../services/library_service.dart';
import '../ui/theme.dart';
import '../widgets/badges.dart';
import '../widgets/ph_button.dart';

/// Relatório da avaliação automática de hardware.
class HardwarePage extends StatelessWidget {
  const HardwarePage({super.key});

  @override
  Widget build(BuildContext context) {
    final hwService = context.watch<HardwareService>();
    final lib = context.watch<LibraryService>();
    final hw = hwService.profile;
    final pad = PH.compact(context) ? 16.0 : 48.0;

    return ListView(padding: EdgeInsets.fromLTRB(pad, 24, pad, 40), children: [
      Row(children: [
        Text('Seu dispositivo', style: Theme.of(context).textTheme.headlineMedium),
        const Spacer(),
        PHButton(
          dense: true,
          autofocus: true,
          icon: Icons.refresh_rounded,
          label: hwService.scanning ? 'Analisando…' : 'Analisar novamente',
          onPressed: hwService.scanning ? null : hwService.scan,
        ),
      ]),
      const SizedBox(height: 6),
      Text(hw == null ? 'Nenhuma análise ainda.' : 'Última análise: ${formatDate(hw.scannedAt)} (${timeAgo(hw.scannedAt)})',
          style: const TextStyle(color: PH.textDim)),
      const SizedBox(height: 20),
      if (hw != null) ...[
        _Summary(hw: hw, lib: lib),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, children: [for (final s in sections(hw)) _Section(title: s.$1, icon: s.$2, rows: s.$3)]),
      ],
    ]);
  }

  /// Seções exibidas (também usadas na primeira execução).
  static List<(String, IconData, List<(String, String)>)> sections(HardwareProfile hw) {
    final (cpuTier, cpuKnown) = HardwareTiers.cpuTier(hw);
    final (gpuTier, gpuKnown) = HardwareTiers.gpuTier(hw);
    String v(double? x) => x == null ? '—' : x.toString();
    return [
      ('Sistema', Icons.devices_rounded, [
        ('Aparelho', hw.deviceLabel),
        if (hw.manufacturer != null) ('Fabricante', hw.manufacturer!),
        ('Sistema', '${hw.osName ?? platformLabel(hw.platform)} ${hw.platform == 'android' ? (hw.osVersion ?? '') : ''}'.trim()),
        if (hw.androidSdk != null) ('API Android', '${hw.androidSdk}'),
        if (hw.distro != null) ('Distribuição', hw.distro!),
        if (hw.kernel != null) ('Kernel', hw.kernel!),
        ('ABI / Arquitetura', hw.abis.isEmpty ? '—' : hw.abis.map(archLabel).join(', ')),
      ]),
      ('Processador', Icons.memory_rounded, [
        ('CPU', hw.cpuName ?? '—'),
        if (hw.socModel != null) ('SoC', hw.socModel!),
        ('Núcleos', hw.cpuCores?.toString() ?? '—'),
        if (hw.cpuThreads != null) ('Threads', '${hw.cpuThreads}'),
        if (hw.cpuMaxMhz != null) ('Frequência máx.', '${hw.cpuMaxMhz} MHz'),
        ('Desempenho estimado', '$cpuTier/100${cpuKnown ? '' : ' (estimado pelos núcleos)'}'),
      ]),
      ('Gráficos', Icons.videogame_asset_rounded, [
        ('GPU', hw.gpuName ?? '—'),
        if (hw.gpuVendor != null) ('Fabricante', hw.gpuVendor!),
        if (hw.gpuDriver != null) ('Driver', hw.gpuDriver!),
        ('Vulkan', hw.vulkan ? 'Sim ${hw.vulkanVersion ?? ''}'.trim() : 'Não'),
        if (hw.platform == 'android') ('OpenGL ES', v(hw.glEsVersion)),
        if (hw.platform != 'android') ('OpenGL', v(hw.openGlVersion)),
        if (hw.platform == 'windows') ('DirectX', hw.directX?.toString() ?? '—'),
        ('Desempenho estimado', '$gpuTier/100${gpuKnown ? '' : ' (estimado)'}'),
      ]),
      ('Memória e tela', Icons.storage_rounded, [
        ('RAM', formatRamMb(hw.ramMb)),
        ('Espaço livre', formatRamMb(hw.freeStorageMb)),
        if (hw.totalStorageMb != null) ('Armazenamento total', formatRamMb(hw.totalStorageMb)),
        ('Tela', hw.screenWidth == null ? '—' : '${hw.screenWidth} × ${hw.screenHeight}'),
        ('Taxa de atualização', hw.refreshRate == null ? '—' : '${hw.refreshRate!.round()} Hz'),
      ]),
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.hw, required this.lib});
  final HardwareProfile hw;
  final LibraryService lib;

  @override
  Widget build(BuildContext context) {
    final total = lib.games.length;
    Widget stat(String label, int n, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: c)),
            Text(label, style: const TextStyle(color: PH.textDim, fontWeight: FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF14304A), PH.surface]),
        borderRadius: BorderRadius.circular(PH.radiusLg),
      ),
      child: Row(children: [
        const Icon(Icons.insights_rounded, size: 46, color: PH.accentSoft),
        const SizedBox(width: 22),
        stat('Compatíveis', lib.compatible.length, PH.green),
        stat('Parciais', lib.partial.length, PH.yellow),
        stat('Incompatíveis', lib.incompatible.length, PH.red),
        stat('No catálogo', total, PH.text),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.rows});
  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final w = PH.compact(context) ? double.infinity : 520.0;
    return Container(
      width: w,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: PH.accent),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        const SizedBox(height: 12),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 170, child: Text(k, style: const TextStyle(color: PH.textDim))),
              Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        if (rows.isEmpty) const TagPill('Sem dados'),
      ]),
    );
  }
}
