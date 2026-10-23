import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/models/game.dart';
import '../ui/theme.dart';

enum ArtKind { cover, banner, icon }

/// Arte do jogo (capa, banner ou ícone) com cache em disco. Quando o
/// repositório não tem imagem, gera uma capa com gradiente e iniciais.
class GameArt extends StatelessWidget {
  const GameArt({super.key, required this.game, this.kind = ArtKind.cover, this.fit = BoxFit.cover, this.showTitleOnFallback = true});

  final Game game;
  final ArtKind kind;
  final BoxFit fit;
  final bool showTitleOnFallback;

  String? get _url => switch (kind) {
        ArtKind.cover => game.coverUrl ?? game.bannerUrl,
        ArtKind.banner => game.bannerUrl ?? game.coverUrl,
        ArtKind.icon => game.iconUrl,
      };

  @override
  Widget build(BuildContext context) {
    final url = _url;
    final fallback = GeneratedArt(game: game, kind: kind, showTitle: showTitleOnFallback);
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
      memCacheWidth: kind == ArtKind.icon ? 128 : (kind == ArtKind.cover ? 480 : 1280),
    );
  }
}

/// Capa gerada quando o jogo não tem imagem: gradiente com um monograma (as
/// iniciais). O nome do jogo fica sempre na legenda, nunca escrito na capa.
class GeneratedArt extends StatelessWidget {
  const GeneratedArt({super.key, required this.game, this.kind = ArtKind.cover, this.showTitle = true});
  final Game game;
  final ArtKind kind;

  /// Mostra o monograma (falso = só o gradiente, ex.: fundo desfocado).
  final bool showTitle;

  static const _palettes = [
    [Color(0xFF1A9FFF), Color(0xFF0B2A4A)],
    [Color(0xFF8E44AD), Color(0xFF1B0F2E)],
    [Color(0xFF16A085), Color(0xFF07231E)],
    [Color(0xFFE67E22), Color(0xFF2E1505)],
    [Color(0xFFC0392B), Color(0xFF2A0907)],
    [Color(0xFF2C3E50), Color(0xFF0B1016)],
    [Color(0xFF27AE60), Color(0xFF082414)],
    [Color(0xFFD4AC0D), Color(0xFF2A2203)],
  ];

  static String initials(String name) => name
      .split(RegExp(r'[\s:()_-]+'))
      .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9À-ÿ]').hasMatch(w[0]))
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[game.name.hashCode.abs() % _palettes.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final s = c.biggest.shortestSide;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Luz suave no canto, para a capa não ficar chapada.
            Positioned(
              left: -s * 0.4,
              top: -s * 0.4,
              child: Container(
                width: s * 1.2,
                height: s * 1.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent]),
                ),
              ),
            ),
            Positioned(
              right: -s * 0.15,
              bottom: -s * 0.15,
              child: Icon(Icons.sports_esports_rounded, size: s * 0.9, color: Colors.white.withValues(alpha: 0.06)),
            ),
            if (showTitle)
              Center(
                child: Container(
                  width: s * 0.56,
                  height: s * 0.56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: s * 0.012),
                  ),
                  child: Text(
                    initials(game.name),
                    style: TextStyle(
                      fontSize: s * 0.22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: s * 0.01,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Fundo desfocado (banner do jogo em foco), com transição suave entre jogos.
class BlurredBackdrop extends StatelessWidget {
  const BlurredBackdrop({super.key, required this.game, this.sigma = 36, this.opacity = 0.55});
  final Game? game;
  final double sigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: PH.bg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: game == null
              ? const SizedBox.expand()
              : Opacity(
                  key: ValueKey(game!.id),
                  opacity: opacity,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                    child: GameArt(game: game!, kind: ArtKind.banner, showTitleOnFallback: false),
                  ),
                ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x660A0D12), Color(0xCC0A0D12), PH.bg],
              stops: [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }
}
