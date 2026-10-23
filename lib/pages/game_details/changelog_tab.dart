import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/models/game.dart';
import '../../core/version_compare.dart';
import '../../ui/theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/focusable.dart';
import 'game_details_page.dart';

/// Changelog a partir das releases do GitHub, com os assets detectados.
class ChangelogTab extends StatelessWidget {
  const ChangelogTab({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    if (game.releases.isEmpty) {
      return const Panel(child: Text('Nenhuma release publicada.', style: TextStyle(color: PH.textDim)));
    }
    return Column(children: [
      for (final r in game.releases)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(r.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              TagPill(r.tag, icon: Icons.sell_outlined),
              if (r == game.latestRelease) const TagPill('Mais recente', color: PH.green),
              if (r.prerelease) const TagPill('Pré-lançamento', color: PH.yellow),
              if (game.installed && game.installedVersion != null && compareVersions(r.tag, game.installedVersion!) == 0)
                const TagPill('Instalada', color: PH.accentSoft),
              Text(formatDate(r.publishedAt), style: const TextStyle(color: PH.textDim)),
            ]),
            if (r.body.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              MarkdownBody(
                data: r.body.length > 6000 ? '${r.body.substring(0, 6000)}…' : r.body,
                onTapLink: (_, href, _) {
                  if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                },
                imageBuilder: (_, _, _) => const SizedBox.shrink(),
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(height: 1.45, color: PH.text),
                  a: const TextStyle(color: PH.accentSoft),
                ),
              ),
            ],
            if (r.assets.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('ARQUIVOS', style: TextStyle(color: PH.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in r.assets.where((a) => a.installable))
                  Focusable(
                    glow: false,
                    focusScale: 1.03,
                    borderRadius: 6,
                    onActivate: () => launchUrl(Uri.parse(a.url), mode: LaunchMode.externalApplication),
                    builder: (context, f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: a == game.bestAsset ? PH.accent.withValues(alpha: 0.18) : PH.surfaceHi,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          '${a.summary}${a.checksum != null ? ' · ${a.checksum!.split(':').first.toUpperCase()}' : ''}'
                          '${a == game.bestAsset ? ' · recomendado' : ''}',
                          style: const TextStyle(color: PH.textDim, fontSize: 11.5),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
    ]);
  }
}
