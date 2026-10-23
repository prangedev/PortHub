import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/game.dart';
import '../downloads/download_manager.dart';
import '../ui/theme.dart';
import 'game_card.dart';

/// Prateleira horizontal de cards (seção da tela inicial).
class GameShelf extends StatelessWidget {
  const GameShelf({
    super.key,
    required this.title,
    required this.games,
    required this.onOpen,
    this.onFocus,
    this.style = CardStyle.portrait,
    this.icon,
    this.subtitle,
    this.autofocusFirst = false,
    this.emptyText,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Game> games;
  final void Function(Game) onOpen;
  final ValueChanged<Game>? onFocus;
  final CardStyle style;
  final bool autofocusFirst;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty && emptyText == null) return const SizedBox.shrink();
    final s = PH.scale(context);
    final cardW = style == CardStyle.portrait ? 168 * s : 340 * s;
    // +4 = borda de foco (2 px de cada lado) + legenda com nome e informações.
    final cardH = (style == CardStyle.portrait ? cardW * 1.5 : cardW * 9 / 16) + 4 + gameCardCaptionHeight;
    final downloads = context.watch<DownloadManager>();
    final pad = PH.compact(context) ? 16.0 : 48.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: PH.accentSoft), const SizedBox(width: 10)],
            Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: PH.text)),
            const SizedBox(width: 10),
            Text('${games.length}', style: const TextStyle(color: PH.textFaint, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(width: 16),
              Flexible(
                  child:
                      Text(subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 13))),
            ],
          ]),
        ),
        if (games.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Text(emptyText!, style: const TextStyle(color: PH.textFaint)),
          )
        else
          SizedBox(
            height: cardH + 24,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
              itemCount: games.length,
              separatorBuilder: (_, _) => SizedBox(width: 18 * s),
              itemBuilder: (context, i) {
                final g = games[i];
                final t = downloads.taskFor(g.id);
                return GameCard(
                  game: g,
                  style: style,
                  width: cardW,
                  autofocus: autofocusFirst && i == 0,
                  onOpen: () => onOpen(g),
                  onFocus: onFocus,
                  progress: t?.progress,
                );
              },
            ),
          ),
      ]),
    );
  }
}
