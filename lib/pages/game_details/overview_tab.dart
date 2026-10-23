import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/game.dart';
import '../../services/library_service.dart';
import '../../services/summarizer_service.dart';
import '../../ui/theme.dart';
import '../../widgets/ph_button.dart';
import 'game_details_page.dart';

/// Descrição, resumo (IA local opcional), README completo e issues fixadas.
class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.game});
  final Game game;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  bool _summarizing = false;
  bool _fullReadme = false;

  Future<void> _summarize() async {
    final g = widget.game;
    if (g.readme == null) return;
    setState(() => _summarizing = true);
    final text = await context.read<SummarizerService>().summarize(g.readme!, gameName: g.name);
    g.aiSummary = text;
    if (mounted) {
      await context.read<LibraryService>().save(g);
      setState(() => _summarizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final summarizer = context.read<SummarizerService>();
    final readme = g.readme;
    final longReadme = readme != null && readme.length > 1500;
    final shown = readme == null ? null : (_fullReadme || readme.length <= 12000 ? readme : '${readme.substring(0, 12000)}\n\n…');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        title: 'Sobre',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.description.isEmpty ? 'Sem descrição.' : g.description, style: const TextStyle(fontSize: 16, height: 1.45)),
          if (g.aiSummary != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: PH.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.auto_awesome_rounded, color: PH.accentSoft, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(g.aiSummary!, style: const TextStyle(height: 1.45))),
              ]),
            ),
          ],
          if (longReadme) ...[
            const SizedBox(height: 14),
            PHButton(
              dense: true,
              icon: Icons.auto_awesome_rounded,
              label: _summarizing
                  ? 'Resumindo…'
                  : (summarizer.aiEnabled ? 'Resumir com IA local' : 'Gerar resumo'),
              onPressed: _summarizing ? null : _summarize,
            ),
          ],
        ]),
      ),
      if (g.pinnedIssues.isNotEmpty)
        Panel(
          title: 'Issues fixadas',
          child: Column(children: [
            for (final i in g.pinnedIssues)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.push_pin_rounded, color: PH.yellow),
                title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(i.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => launchUrl(Uri.parse(i.url), mode: LaunchMode.externalApplication),
              ),
          ]),
        ),
      Panel(
        title: 'README',
        child: shown == null
            ? const Text('README ainda não carregado (será buscado quando houver conexão).', style: TextStyle(color: PH.textDim))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MarkdownBody(
                  data: shown,
                  selectable: false,
                  onTapLink: (text, href, title) {
                    if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                  },
                  imageBuilder: (uri, title, alt) {
                    final url = uri.toString();
                    if (url.toLowerCase().contains('.svg') || !url.startsWith('http')) return const SizedBox.shrink();
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: CachedNetworkImage(imageUrl: url, errorWidget: (_, _, _) => const SizedBox.shrink()),
                    );
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(fontSize: 15, height: 1.5, color: PH.text),
                    a: const TextStyle(color: PH.accentSoft),
                    code: const TextStyle(fontFamily: 'monospace', backgroundColor: PH.surfaceHi, fontSize: 13),
                    codeblockDecoration: BoxDecoration(color: PH.bg2, borderRadius: BorderRadius.circular(8)),
                    blockquoteDecoration: BoxDecoration(color: PH.surfaceHi, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                if (!_fullReadme && readme!.length > 12000)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PHButton(dense: true, label: 'Mostrar README completo', onPressed: () => setState(() => _fullReadme = true)),
                  ),
              ]),
      ),
    ]);
  }
}
