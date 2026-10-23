import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models/download_task.dart';
import '../core/models/release_info.dart';
import '../downloads/download_manager.dart';
import '../services/game_actions.dart';
import '../services/library_service.dart';
import '../ui/theme.dart';
import '../widgets/badges.dart';
import '../widgets/game_art.dart';
import '../widgets/ph_button.dart';

/// Gerenciador de downloads: progresso, velocidade, ETA, pausar/continuar/cancelar.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final pad = PH.compact(context) ? 16.0 : 48.0;
    final active = dm.tasks.where((t) => !t.state.isFinished).toList();
    final done = dm.tasks.where((t) => t.state.isFinished).toList();

    return ListView(padding: EdgeInsets.fromLTRB(pad, 24, pad, 40), children: [
      Row(children: [
        Text('Downloads', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(width: 16),
        if (dm.activeCount > 0) Text('${dm.activeCount} ativo(s) · ${formatSpeed(dm.totalSpeed)}', style: const TextStyle(color: PH.textDim)),
        const Spacer(),
        if (done.isNotEmpty) PHButton(dense: true, icon: Icons.clear_all_rounded, label: 'Limpar concluídos', onPressed: dm.clearFinished),
      ]),
      const SizedBox(height: 20),
      if (dm.tasks.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: Column(children: [
              Icon(Icons.download_done_rounded, size: 64, color: PH.textFaint),
              SizedBox(height: 12),
              Text('Nenhum download. Escolha um jogo e toque em Instalar.', style: TextStyle(color: PH.textDim)),
            ]),
          ),
        ),
      if (active.isNotEmpty) ...[
        const _Label('Em andamento'),
        for (var i = 0; i < active.length; i++) _TaskTile(task: active[i], autofocus: i == 0),
      ],
      if (done.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _Label('Histórico'),
        for (final t in done) _TaskTile(task: t),
      ],
    ]);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
      );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, this.autofocus = false});
  final DownloadTask task;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final dm = context.read<DownloadManager>();
    final game = context.read<LibraryService>().byId(task.gameId);
    final t = task;
    final indeterminate = t.state == DownloadState.verifying || t.state == DownloadState.installing;
    final color = switch (t.state) {
      DownloadState.failed => PH.red,
      DownloadState.installed => PH.green,
      DownloadState.paused => PH.yellow,
      _ => PH.accent,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: PH.surface, borderRadius: BorderRadius.circular(PH.radius)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 68,
            child: game == null ? const ColoredBox(color: PH.surfaceHi) : GameArt(game: game, kind: ArtKind.banner, showTitleOnFallback: false),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(t.gameName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              const SizedBox(width: 10),
              TagPill(t.version, icon: Icons.sell_outlined),
              const SizedBox(width: 6),
              TagPill(t.kind.label),
              if (t.checksumVerified || (t.state == DownloadState.installed && t.checksum != null)) ...[
                const SizedBox(width: 6),
                const TagPill('Íntegro', color: PH.green, icon: Icons.verified_user_rounded),
              ],
            ]),
            const SizedBox(height: 8),
            if (!t.state.isFinished) PHProgress(value: indeterminate ? null : t.progress, color: color),
            const SizedBox(height: 6),
            Row(children: [
              Text(t.state.label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 12),
              Text('${formatBytes(t.receivedBytes)} / ${formatBytes(t.totalBytes)}', style: const TextStyle(color: PH.textDim, fontSize: 13)),
              if (t.state == DownloadState.downloading) ...[
                const SizedBox(width: 12),
                Text('${formatSpeed(t.speedBps)} · ETA ${formatEta(t.eta)}', style: const TextStyle(color: PH.textDim, fontSize: 13)),
              ],
            ]),
            if (t.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.error!, style: const TextStyle(color: PH.red, fontSize: 12.5))),
          ]),
        ),
        const SizedBox(width: 12),
        Wrap(spacing: 8, children: [
          if (t.state == DownloadState.downloading || t.state == DownloadState.queued)
            PHIconButton(icon: Icons.pause_rounded, tooltip: 'Pausar', onPressed: () => dm.pause(t)),
          if (t.state == DownloadState.paused || t.state == DownloadState.failed)
            PHIconButton(icon: Icons.play_arrow_rounded, tooltip: 'Continuar', onPressed: () => dm.resume(t)),
          if (t.state == DownloadState.completed)
            PHIconButton(
              icon: Icons.install_mobile_rounded,
              tooltip: 'Instalar',
              onPressed: () => context.read<GameActions>().installDownloaded(t),
            ),
          if (!t.state.isFinished && t.state != DownloadState.installing)
            PHIconButton(icon: Icons.close_rounded, tooltip: 'Cancelar', onPressed: () => dm.cancel(t)),
          if (t.state.isFinished || t.state == DownloadState.failed)
            PHIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Remover', onPressed: () => dm.remove(t)),
        ]),
      ]),
    );
  }
}
