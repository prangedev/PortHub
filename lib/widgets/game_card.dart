import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models/game.dart';
import '../ui/theme.dart';
import 'badges.dart';
import 'focusable.dart';
import 'game_art.dart';

enum CardStyle { portrait, landscape }

/// Altura da legenda (nome + linha de informações) abaixo da capa.
const gameCardCaptionHeight = 52.0;

/// Card de jogo: a capa fica limpa (só selos de compatibilidade e status) e o
/// nome vai sempre abaixo dela. Retrato (2:3, biblioteca) ou paisagem (16:9,
/// "Recentemente jogados").
class GameCard extends StatefulWidget {
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
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final style = widget.style;
    final progress = widget.progress;
    final s = PH.scale(context);
    final w = widget.width ?? (style == CardStyle.portrait ? 168 * s : 340 * s);
    final h = style == CardStyle.portrait ? w * 1.5 : w * 9 / 16;
    final info = [game.category, if (game.size != null) formatBytes(game.size)].join(' · ');

    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // O destaque (borda + brilho) fica só na capa; a legenda acompanha pela cor.
          Focusable(
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onActivate: widget.onOpen,
            scrollAlignment: 0.35,
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) widget.onFocus?.call(game);
            },
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(PH.radius),
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GameArt(game: game, kind: style == CardStyle.portrait ? ArtKind.cover : ArtKind.banner),
                    // Leve sombra no topo só para os selos ficarem legíveis.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Colors.transparent],
                          stops: [0, 0.3],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Glass(child: CompatBadge(result: game.compatibility, size: 9)),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (game.favorite) const _Glass(child: Icon(Icons.star_rounded, size: 14, color: PH.yellow)),
                          if (game.status != InstallStatus.notInstalled) ...[
                            if (game.favorite) const SizedBox(width: 4),
                            _StatusDot(status: game.status),
                          ],
                        ],
                      ),
                    ),
                    if (progress != null)
                      Positioned(left: 8, right: 8, bottom: 8, child: PHProgress(value: progress, height: 5)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: gameCardCaptionHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: _focused ? Colors.white : PH.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      if (game.status != InstallStatus.notInstalled)
                        TextSpan(
                          text: game.status == InstallStatus.updateAvailable ? 'Atualização · ' : 'Instalado · ',
                          style: TextStyle(
                            color: game.status == InstallStatus.updateAvailable ? PH.yellow : PH.green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      TextSpan(text: info),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PH.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selo de status na capa: verde (instalado) ou amarelo (atualização).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final InstallStatus status;

  @override
  Widget build(BuildContext context) {
    final update = status == InstallStatus.updateAvailable;
    // Só o ícone: o texto do status vai na legenda (cabe em capas estreitas).
    return _Glass(
      child: Icon(
        update ? Icons.system_update_alt_rounded : Icons.check_circle_rounded,
        size: 14,
        color: update ? PH.yellow : PH.green,
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

/// Grade de capas (sliver) com a altura certa para capa 2:3 + legenda. Uma
/// proporção fixa não serve: com cartões pequenos a legenda não encolhe junto.
class GameCardGrid extends StatelessWidget {
  const GameCardGrid({super.key, required this.count, required this.itemBuilder, required this.maxTileWidth});

  final int count;
  final double maxTileWidth;
  final Widget Function(BuildContext context, int index, double tileWidth) itemBuilder;

  static const _spacing = 20.0;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(builder: (context, constraints) {
        final cols = ((constraints.crossAxisExtent + _spacing) / (maxTileWidth + _spacing)).ceil().clamp(1, 12);
        final tileW = (constraints.crossAxisExtent - _spacing * (cols - 1)) / cols;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 22,
            crossAxisSpacing: _spacing,
            // +4 = borda de foco da capa.
            mainAxisExtent: tileW * 1.5 + 4 + gameCardCaptionHeight,
          ),
          delegate: SliverChildBuilderDelegate((context, i) => itemBuilder(context, i, tileW), childCount: count),
        );
      });
}
