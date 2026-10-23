import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/models/community_report.dart';
import '../../core/models/game.dart';
import '../../core/models/hardware_profile.dart';
import '../../services/community_service.dart';
import '../../services/hardware/hardware_service.dart';
import '../../ui/theme.dart';
import '../../widgets/ph_button.dart';
import '../navigation.dart';
import 'game_details_page.dart';

/// PortHub Compatibility Database: relatos reais da comunidade (estilo ProtonDB).
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key, required this.game});
  final Game game;

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  late Future<List<CommunityReport>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<CommunityService>().reports(widget.game.id);

  static Color ratingColor(CommunityRating? r) => switch (r) {
        CommunityRating.platinum => const Color(0xFFB4C7DC),
        CommunityRating.gold => const Color(0xFFCFB53B),
        CommunityRating.silver => const Color(0xFFA6A6A6),
        CommunityRating.bronze => const Color(0xFFCD7F32),
        CommunityRating.borked => PH.red,
        null => PH.textFaint,
      };

  @override
  Widget build(BuildContext context) {
    final community = context.read<CommunityService>();
    final hw = context.watch<HardwareService>().profile;
    final g = widget.game;

    if (!community.configured) {
      return const Panel(
        title: 'PortHub Compatibility Database',
        child: Text(
          'Conecte-se a uma base comunitária para ver relatos reais de desempenho (FPS, aparelho testado, problemas '
          'conhecidos). Configure a URL em Configurações → Comunidade. O servidor de referência está na pasta /backend '
          'do projeto.',
          style: TextStyle(color: PH.textDim, height: 1.45),
        ),
      );
    }

    return FutureBuilder<List<CommunityReport>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final reports = snap.data ?? const [];
        final s = CommunityService.summarize(reports, hw);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Panel(
            title: 'PortHub Compatibility Database',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('Compatibilidade oficial', '${g.compatibility.score}%'),
              InfoRow('Relatos da comunidade', s.rating?.label ?? 'Sem relatos',
                  trailing: Container(width: 14, height: 14, decoration: BoxDecoration(color: ratingColor(s.rating), shape: BoxShape.circle))),
              InfoRow('FPS médio', s.averageFps == null ? '—' : '${s.averageFps!.round()} FPS'),
              InfoRow('Testado em', s.mostTestedDevice ?? '—'),
              InfoRow('Problemas conhecidos', s.knownIssues.isEmpty ? 'Nenhum relatado' : s.knownIssues.join(', ')),
              InfoRow('Total de relatos', '${s.total}'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: PH.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.groups_rounded, color: PH.accentSoft),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.message, style: const TextStyle(height: 1.4))),
                ]),
              ),
              const SizedBox(height: 14),
              PHButton(
                dense: true,
                icon: Icons.rate_review_rounded,
                label: 'Enviar meu relato',
                onPressed: hw == null ? null : () => _submit(context, hw),
              ),
            ]),
          ),
          for (final r in reports.take(30))
            Panel(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: ratingColor(r.rating).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text(r.rating.label, style: TextStyle(color: ratingColor(r.rating), fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.deviceModel}${r.soc != null ? ' · ${r.soc}' : ''}${r.gpu != null ? ' · ${r.gpu}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${r.fps != null ? '${r.fps!.round()} FPS · ' : ''}${formatRamMb(r.ramMb)} · ${r.osVersion ?? r.platform} · ${timeAgo(r.createdAt)}'
                      '${hw != null && CommunityService.isSimilar(r, hw) ? ' · hardware semelhante ao seu' : ''}',
                      style: const TextStyle(color: PH.textDim, fontSize: 13),
                    ),
                    if (r.notes.isNotEmpty) ...[const SizedBox(height: 6), Text(r.notes)],
                    if (r.issues.isNotEmpty) ...[const SizedBox(height: 4), Text('Problemas: ${r.issues.join(', ')}', style: const TextStyle(color: PH.yellow))],
                  ]),
                ),
              ]),
            ),
        ]);
      },
    );
  }

  Future<void> _submit(BuildContext context, HardwareProfile hw) async {
    final report = await showDialog<CommunityReport>(context: context, builder: (_) => _ReportDialog(game: widget.game, hw: hw));
    if (report == null || !context.mounted) return;
    final err = await context.read<CommunityService>().submit(report);
    if (!context.mounted) return;
    showMessage(context, err ?? 'Relato enviado. Obrigado!', error: err != null);
    if (err == null) setState(_load);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.game, required this.hw});
  final Game game;
  final HardwareProfile hw;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  CommunityRating _rating = CommunityRating.gold;
  final _fps = TextEditingController();
  final _issues = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _fps.dispose();
    _issues.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hw = widget.hw;
    return AlertDialog(
      title: Text('Relato: ${widget.game.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${hw.deviceLabel} · ${hw.cpuName ?? hw.socModel ?? ''} · ${hw.gpuName ?? ''}', style: const TextStyle(color: PH.textDim)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in CommunityRating.values)
                PHChip(label: r.label, selected: _rating == r, onTap: () => setState(() => _rating = r)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: _fps, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'FPS médio (opcional)')),
            const SizedBox(height: 12),
            TextField(controller: _issues, decoration: const InputDecoration(labelText: 'Problemas (separados por vírgula)')),
            const SizedBox(height: 12),
            TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            CommunityReport(
              gameId: widget.game.id,
              platform: hw.platform,
              deviceModel: hw.deviceLabel,
              soc: hw.socModel ?? hw.cpuName,
              gpu: hw.gpuName,
              ramMb: hw.ramMb,
              osVersion: hw.platform == 'android' ? 'Android ${hw.osVersion}' : (hw.distro ?? hw.osName),
              rating: _rating,
              fps: double.tryParse(_fps.text.replaceAll(',', '.')),
              issues: _issues.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
              notes: _notes.text.trim(),
              gameVersion: widget.game.installedVersion ?? widget.game.version,
            ),
          ),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
