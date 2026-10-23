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

class GeneratedArt extends StatelessWidget {
  const GeneratedArt({super.key, required this.game, this.kind = ArtKind.cover, this.showTitle = true});
  final Game game;
  final ArtKind kind;
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

  /// Tamanho que faz a palavra mais longa caber em uma linha.
  double _titleSize(double width, double shortest) {
    final longest = game.name.split(RegExp(r'\s+')).fold<int>(1, (m, w) => w.length > m ? w.length : m);
    final byWidth = width * 0.84 / (longest * 0.62);
    return [shortest * 0.14, byWidth].reduce((a, b) => a < b ? a : b).clamp(10, 40).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[game.name.hashCode.abs() % _palettes.length];
    final initials = game.name
        .split(RegExp(r'[\s:()-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final s = c.biggest.shortestSide;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -s * 0.15,
              bottom: -s * 0.15,
              child: Icon(Icons.sports_esports_rounded, size: s * 0.9, color: Colors.white.withValues(alpha: 0.06)),
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.all(s * 0.08),
                child: kind == ArtKind.icon || !showTitle
                    ? Text(initials, style: TextStyle(fontSize: s * 0.4, fontWeight: FontWeight.w900, color: Colors.white70))
                    : Text(
                        game.name,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: _titleSize(c.maxWidth, s),
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.05,
                          shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
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
