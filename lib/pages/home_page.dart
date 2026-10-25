import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../services/library_service.dart';
import '../ui/theme.dart';
import '../widgets/badges.dart';
import '../widgets/game_art.dart';
import '../widgets/game_card.dart';
import '../widgets/game_shelf.dart';
import '../widgets/ph_button.dart';
import 'navigation.dart';

/// Tela inicial estilo Big Picture: fundo desfocado com o banner do jogo em
/// foco, destaque grande no topo e prateleiras horizontais por seção.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Game? _focused;

  void _onFocus(Game g) {
    if (_focused?.id != g.id) setState(() => _focused = g);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();

    if (lib.isEmpty) return _EmptyLibrary(lib: lib);

    final sections = <(String, IconData, List<Game>, CardStyle, String?)>[
      ('Recentemente jogados', Icons.history_rounded, lib.recentlyPlayed, CardStyle.landscape, null),
      ('Continuar jogando', Icons.play_circle_outline_rounded, lib.continuePlaying, CardStyle.portrait, null),
      ('Recomendados', Icons.auto_awesome_rounded, lib.recommended, CardStyle.portrait, 'Compatíveis e bem avaliados'),
      ('Compatíveis com meu aparelho', Icons.verified_rounded, lib.compatible, CardStyle.portrait, null),
      (
        'Parcialmente compatíveis',
        Icons.speed_rounded,
        lib.partial,
        CardStyle.portrait,
        'Podem ter queda de desempenho',
      ),
      ('Incompatíveis', Icons.block_rounded, lib.incompatible, CardStyle.portrait, 'Veja o motivo em cada jogo'),
      ('Atualizações disponíveis', Icons.system_update_alt_rounded, lib.updates, CardStyle.portrait, null),
      ('Favoritos', Icons.star_rounded, lib.favorites, CardStyle.portrait, null),
      ('Lista de desejos', Icons.bookmark_rounded, lib.wishlist, CardStyle.portrait, null),
      ('Biblioteca completa', Icons.grid_view_rounded, lib.games, CardStyle.portrait, null),
    ];
    final firstNonEmpty = sections.indexWhere((s) => s.$3.isNotEmpty);
    final hero = _focused ?? (firstNonEmpty >= 0 ? sections[firstNonEmpty].$3.first : null);

    // Em telas baixas (celular deitado) o destaque empurraria a primeira prateleira
    // para fora da tela; lá o fundo desfocado já mostra o jogo em foco.
    final showHero = MediaQuery.sizeOf(context).height >= 520;

    return Stack(
      fit: StackFit.expand,
      children: [
        BlurredBackdrop(game: hero),
        RefreshIndicator(
          onRefresh: lib.refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBanner(lib: lib),
                if (hero != null && showHero) _Hero(game: hero),
                if (!showHero) const SizedBox(height: 16),
                for (var i = 0; i < sections.length; i++)
                  GameShelf(
                    title: sections[i].$1,
                    icon: sections[i].$2,
                    games: sections[i].$3,
                    style: sections[i].$4,
                    subtitle: sections[i].$5,
                    autofocusFirst: i == firstNonEmpty,
                    onOpen: (g) => openGame(context, g),
                    onFocus: _onFocus,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Aviso no topo quando algo limita a biblioteca: sincronização com erro,
/// modo offline ou jogos adiados por falta de cota do GitHub.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.lib});
  final LibraryService lib;

  @override
  Widget build(BuildContext context) {
    final offline = lib.settings.offlineMode;
    final (IconData icon, Color color, String text, String? action, VoidCallback? onAction) = switch (lib) {
      _ when lib.refreshing => (Icons.sync_rounded, PH.accent, lib.refreshStatus, null, null),
      _ when offline => (
        Icons.cloud_off_rounded,
        PH.yellow,
        'Modo offline: mostrando só o que está em cache.',
        'Ficar online',
        () => lib.settings.offlineMode = false,
      ),
      _ when lib.lastError != null => (
        Icons.error_outline_rounded,
        PH.red,
        'A última sincronização teve problemas: ${lib.lastError}',
        'Tentar de novo',
        lib.refresh,
      ),
      _ when lib.deferredCount > 0 && lib.settings.githubToken.isEmpty => (
        Icons.hourglass_bottom_rounded,
        PH.yellow,
        '${lib.deferredCount} jogos com dados parciais: o GitHub limita 60 consultas/h sem token.',
        'Configurar token',
        () => openSettings(context),
      ),
      _ => (Icons.check, PH.green, '', null, null),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    final pad = PH.compact(context) ? 16.0 : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(PH.radius),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
            if (lib.refreshing)
              SizedBox(
                width: 120,
                child: PHProgress(value: lib.refreshProgress > 0 ? lib.refreshProgress : null, height: 4),
              )
            else if (action != null) ...[
              const SizedBox(width: 10),
              PHButton(label: action, dense: true, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final compact = PH.compact(context);
    final minH = MediaQuery.sizeOf(context).height * (compact ? 0.22 : 0.30);
    final pad = compact ? 16.0 : 48.0;
    final c = game.compatibility;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minH),
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 28, pad, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Row(
            key: ValueKey(game.id),
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        StatusChip(status: game.status),
                        const SizedBox(width: 10),
                        CompatBadge(result: c, showLabel: true, size: 11),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      game.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 26 : 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        game.author,
                        game.engine,
                        game.category,
                        if (game.version != null) game.version!,
                        formatBytes(game.size),
                      ].whereType<String>().where((s) => s.isNotEmpty && s != '—').join('  ·  '),
                      style: const TextStyle(color: PH.textDim, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (!compact && game.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(
                          game.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                    ],
                    if (c.level == CompatLevel.incompatible && c.blockingReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        c.blockingReason!,
                        style: const TextStyle(color: PH.red, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: GameArt(game: game, kind: ArtKind.icon),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.lib});
  final LibraryService lib;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore_rounded, size: 72, color: PH.accent),
            const SizedBox(height: 18),
            Text(
              lib.refreshing ? 'Montando sua biblioteca…' : 'Sua biblioteca está vazia',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              lib.refreshing
                  ? lib.refreshStatus
                  : (lib.lastError ?? 'Sincronize para buscar ports no GitHub e nos provedores habilitados.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: PH.textDim),
            ),
            const SizedBox(height: 24),
            if (lib.refreshing)
              SizedBox(width: 320, child: PHProgress(value: lib.refreshProgress > 0 ? lib.refreshProgress : null))
            else
              PHButton(
                label: 'Sincronizar agora',
                icon: Icons.sync_rounded,
                autofocus: true,
                gradient: PH.installGradient,
                onPressed: lib.refresh,
              ),
          ],
        ),
      ),
    );
  }
}
