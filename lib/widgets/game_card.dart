import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models/game.dart';
import '../ui/theme.dart';
import 'badges.dart';
import 'focusable.dart';
import 'game_art.dart';

enum CardStyle { portrait, landscape }

/// Card de jogo: capa, nome, compatibilidade, tamanho e status.
/// Retrato (2:3, biblioteca) ou paisagem (16:9, "Recentemente jogados").
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onOpen,
    this.onFocus,
    this.style = CardStyle.portrait,
    this.width,
    this.autofocus = false,
    this.focusNode,
    this.progress,
  });

  final Game game;
  final VoidCallback onOpen;
  final ValueChanged<Game>? onFocus;
  final CardStyle style;
  final double? width;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Progresso de download em andamento (0–1), se houver.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final s = PH.scale(context);
    final w = width ?? (style == CardStyle.portrait ? 168 * s : 340 * s);
    final h = style == CardStyle.portrait ? w * 1.5 : w * 9 / 16;
    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            autofocus: autofocus,
            focusNode: focusNode,
            onActivate: onOpen,
            scrollAlignment: 0.35,
            onFocusChange: (f) {
              if (f) onFocus?.call(game);
            },
            builder: (context, focused) => ClipRRect(
              borderRadius: BorderRadius.circular(PH.radius),
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GameArt(
                      game: game,
                      kind: style == CardStyle.portrait ? ArtKind.cover : ArtKind.banner,
                      // No cartão deitado o nome já vai no rodapé.
                      showTitleOnFallback: style == CardStyle.portrait,
                    ),
                    // Gradiente inferior para legibilidade.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.transparent, Color(0xDD000000)],
                          stops: [0, 0.55, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Glass(child: CompatBadge(result: game.compatibility, size: 9)),
                    ),
                    if (game.favorite)
                      const Positioned(top: 8, left: 8, child: _Glass(child: Icon(Icons.star_rounded, size: 14, color: PH.yellow))),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        // A capa gerada já escreve o nome; não repete no foco.
                        if (style == CardStyle.landscape || (focused && (game.coverUrl ?? game.bannerUrl) != null))
                          Text(game.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.1)),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (game.status != InstallStatus.notInstalled) Flexible(child: StatusChip(status: game.status, dense: true)),
                          const Spacer(),
                          const SizedBox(width: 4),
                          Text(formatBytes(game.size), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ]),
                        if (progress != null) ...[const SizedBox(height: 6), PHProgress(value: progress, height: 4)],
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (style == CardStyle.portrait) ...[
            const SizedBox(height: 8),
            Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(game.category, maxLines: 1, style: const TextStyle(color: PH.textDim, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
        child: child,
      );
}
