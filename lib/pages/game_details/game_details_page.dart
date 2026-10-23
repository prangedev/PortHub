import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/models/compatibility_result.dart';
import '../../core/models/download_task.dart';
import '../../core/models/game.dart';
import '../../core/models/release_info.dart';
import '../../core/platform_info.dart';
import '../../downloads/download_manager.dart';
import '../../services/game_actions.dart';
import '../../services/hardware/hardware_service.dart';
import '../../services/library_service.dart';
import '../../ui/input/input_router.dart';
import '../../ui/theme.dart';
import '../../widgets/badges.dart';
import '../../widgets/focusable.dart';
import '../../widgets/game_art.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/ph_button.dart';
import '../navigation.dart';
import 'changelog_tab.dart';
import 'community_tab.dart';
import 'compatibility_tab.dart';
import 'gallery_tab.dart';
import 'overview_tab.dart';
import 'requirements_tab.dart';

/// Página do jogo: banner grande, ações (Instalar / Atualizar / Jogar), resumo
/// de compatibilidade e abas (LB/RB): Visão geral, Galeria, Changelog,
/// Requisitos, Compatibilidade e Comunidade.
class GameDetailsPage extends StatefulWidget {
  const GameDetailsPage({super.key, required this.gameId});
  final String gameId;

  @override
  State<GameDetailsPage> createState() => _GameDetailsPageState();
}

class _GameDetailsPageState extends State<GameDetailsPage> with PadHandlerMixin {
  int _tab = 0;
  static const _tabs = ['Visão geral', 'Galeria', 'Changelog', 'Requisitos', 'Compatibilidade', 'Comunidade'];

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryService>();
    final g = lib.byId(widget.gameId);
    if (g != null) lib.ensureDetails(g);
  }

  @override
  bool onPad(PadAction a) {
    final g = context.read<LibraryService>().byId(widget.gameId);
    switch (a) {
      case PadAction.prevSection:
        setState(() => _tab = (_tab - 1 + _tabs.length) % _tabs.length);
        return true;
      case PadAction.nextSection:
        setState(() => _tab = (_tab + 1) % _tabs.length);
        return true;
      case PadAction.secondary:
        if (g != null) context.read<LibraryService>().toggleFavorite(g);
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final game = lib.byId(widget.gameId);
    if (game == null) {
      return const Scaffold(body: Center(child: Text('Jogo não encontrado')));
    }
    final compact = PH.compact(context);
    final pad = compact ? 16.0 : 48.0;
    final bannerH = MediaQuery.sizeOf(context).height * (compact ? 0.32 : 0.42);

    return Scaffold(
      backgroundColor: PH.bg,
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            BlurredBackdrop(game: game, opacity: 0.6),
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Banner(game: game, height: bannerH, pad: pad),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 18),
                    _ActionRow(game: game),
                    _DownloadPanel(game: game),
                    const SizedBox(height: 22),
                    _CompatSummary(game: game, onOpenReport: () => setState(() => _tab = 4)),
                    if (game.gameDataNote != null) _GameDataNotice(note: game.gameDataNote!),
                    const SizedBox(height: 26),
                    _Tabs(tabs: _tabs, current: _tab, onSelect: (i) => setState(() => _tab = i)),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: switch (_tab) {
                          0 => OverviewTab(game: game),
                          1 => GalleryTab(game: game),
                          2 => ChangelogTab(game: game),
                          3 => RequirementsTab(game: game),
                          4 => CompatibilityTab(game: game),
                          _ => CommunityTab(game: game),
                        },
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: PHIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Voltar', onPressed: () => Navigator.of(context).maybePop()),
              ),
            ),
          ]),
        ),
        const HintBar(hints: [
          (PadGlyph.a, 'Selecionar'),
          (PadGlyph.b, 'Voltar'),
          (PadGlyph.x, 'Favoritar'),
          (PadGlyph.lb, 'Aba anterior'),
          (PadGlyph.rb, 'Próxima aba'),
        ]),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.game, required this.height, required this.pad});
  final Game game;
  final double height;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final compact = PH.compact(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        GameArt(game: game, kind: ArtKind.banner, showTitleOnFallback: false),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x330A0D12), Color(0x000A0D12), Color(0xF20A0D12)],
              stops: [0, 0.35, 1],
            ),
          ),
        ),
        Positioned(
          left: pad,
          right: pad,
          bottom: 4,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: compact ? 64 : 96,
                height: compact ? 64 : 96,
                child: GameArt(game: game, kind: ArtKind.icon),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  game.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 28 : 46,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    height: 1.05,
                    shadows: const [Shadow(blurRadius: 18, color: Colors.black)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'por ${game.author}${game.engine != null ? '  ·  ${game.engine}' : ''}  ·  ${game.categories.isEmpty ? 'Sem categoria' : game.categories.join(', ')}',
                  style: const TextStyle(color: PH.textDim, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in game.tags.take(8)) TagPill(t),
                  if (game.license != null && game.license != 'NOASSERTION') TagPill(game.license!, icon: Icons.gavel_rounded),
                  if (game.language != null) TagPill(game.language!, icon: Icons.code_rounded),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.game});
  final Game game;

  Future<void> _install(BuildContext context) => installWithConfirmation(context, game);

  Future<void> _play(BuildContext context) async {
    final err = await context.read<GameActions>().play(game);
    if (err != null && context.mounted) showMessage(context, err, error: true);
  }

  Future<void> _uninstall(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desinstalar ${game.name}?'),
        content: const Text('Os arquivos do jogo serão removidos.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desinstalar')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<GameActions>().uninstall(game);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryService>();
    final actions = context.read<GameActions>();
    final task = context.watch<DownloadManager>().taskFor(game.id);
    final busy = task != null && task.state != DownloadState.completed;
    final asset = game.bestAsset;

    final List<Widget> primary;
    if (busy) {
      primary = [
        PHButton(
          label: task.state == DownloadState.paused ? 'Continuar download' : task.state.label,
          icon: task.state == DownloadState.paused ? Icons.play_arrow_rounded : Icons.downloading_rounded,
          gradient: PH.installGradient,
          autofocus: true,
          onPressed: task.state == DownloadState.paused ? () => context.read<DownloadManager>().resume(task) : null,
        ),
      ];
    } else if (game.installed) {
      primary = [
        PHButton(label: 'JOGAR', icon: Icons.play_arrow_rounded, gradient: PH.playGradient, autofocus: !game.updateAvailable, onPressed: () => _play(context)),
        if (game.updateAvailable) ...[
          const SizedBox(width: 12),
          PHButton(
            label: 'Atualizar para ${game.version}',
            icon: Icons.system_update_alt_rounded,
            gradient: PH.updateGradient,
            autofocus: true,
            onPressed: () => _install(context),
          ),
        ],
      ];
    } else if (asset != null) {
      primary = [
        PHButton(
          label: 'INSTALAR  ·  ${formatBytes(asset.size)}',
          icon: Icons.download_rounded,
          gradient: PH.installGradient,
          autofocus: true,
          onPressed: () => _install(context),
        ),
      ];
    } else {
      primary = [
        PHButton(
          label: 'Indisponível para ${platformLabel(hostPlatform.name)}',
          icon: Icons.block_rounded,
          autofocus: true,
          onPressed: null,
        ),
      ];
    }

    return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ...primary,
      PHIconButton(
        icon: game.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        tooltip: game.favorite ? 'Remover dos favoritos' : 'Favoritar',
        active: game.favorite,
        activeColor: PH.yellow,
        onPressed: () => lib.toggleFavorite(game),
      ),
      PHIconButton(
        icon: game.wishlist ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
        tooltip: game.wishlist ? 'Remover da lista de desejos' : 'Lista de desejos',
        active: game.wishlist,
        onPressed: () => lib.toggleWishlist(game),
      ),
      if (game.githubUrl.isNotEmpty) PHIconButton(icon: Icons.open_in_new_rounded, tooltip: 'Abrir GitHub', onPressed: () => actions.openGitHub(game)),
      if (game.installed) PHIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Desinstalar', onPressed: () => _uninstall(context)),
      const SizedBox(width: 12),
      _Meta('Versão', game.version ?? '—'),
      _Meta('Tamanho', formatBytes(game.size)),
      _Meta('Atualizado', formatDate(game.lastUpdate)),
      if (game.installed) _Meta('Instalado', game.installedVersion ?? '—'),
      if (game.stars > 0) _Meta('Estrelas', '${game.stars}'),
      if (game.playTimeSeconds > 0) _Meta('Tempo de jogo', formatPlayTime(game.playTimeSeconds)),
      if (asset != null) _Meta('Arquivo', '${asset.kind.label}${asset.arch != null ? ' · ${archLabel(asset.arch)}' : ''}'),
    ]);
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManager>();
    final t = dm.taskFor(game.id);
    if (t == null || t.state == DownloadState.completed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(color: PH.surface.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(PH.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(t.state.label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: Text(t.fileName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim))),
          if (t.state == DownloadState.downloading)
            PHIconButton(icon: Icons.pause_rounded, tooltip: 'Pausar', onPressed: () => dm.pause(t))
          else if (t.state == DownloadState.paused || t.state == DownloadState.failed)
            PHIconButton(icon: Icons.play_arrow_rounded, tooltip: 'Continuar', onPressed: () => dm.resume(t)),
          const SizedBox(width: 8),
          if (t.state != DownloadState.installing) PHIconButton(icon: Icons.close_rounded, tooltip: 'Cancelar', onPressed: () => dm.cancel(t)),
        ]),
        const SizedBox(height: 12),
        PHProgress(value: t.state == DownloadState.verifying || t.state == DownloadState.installing ? null : t.progress, height: 8),
        const SizedBox(height: 8),
        Row(children: [
          Text('${formatBytes(t.receivedBytes)} de ${formatBytes(t.totalBytes)}  ·  ${(t.progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: PH.textDim, fontSize: 13)),
          const Spacer(),
          if (t.state == DownloadState.downloading)
            Text('${formatSpeed(t.speedBps)}  ·  restam ${formatEta(t.eta)}', style: const TextStyle(color: PH.textDim, fontSize: 13)),
        ]),
        if (t.error != null) ...[
          const SizedBox(height: 8),
          Text(t.error!, style: const TextStyle(color: PH.red, fontSize: 13)),
        ],
      ]),
    );
  }
}

class _CompatSummary extends StatelessWidget {
  const _CompatSummary({required this.game, required this.onOpenReport});
  final Game game;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final c = game.compatibility;
    final hw = context.watch<HardwareService>().profile;
    final color = PH.compat(c.level);
    return Focusable(
      onActivate: onOpenReport,
      glow: false,
      focusScale: 1.01,
      builder: (context, focused) => Container(
        padding: const EdgeInsets.all(18),
        constraints: const BoxConstraints(maxWidth: 980),
        decoration: BoxDecoration(
          color: PH.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(PH.radius),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(children: [
          ScoreRing(result: c, size: 84),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.level.label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 4),
              Text(c.message, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                hw == null
                    ? 'Analise o hardware em Dispositivo para avaliar.'
                    : 'Avaliado para ${hw.deviceLabel}${c.estimated ? ' · requisitos não declarados, avaliação estimada' : ''}',
                style: const TextStyle(color: PH.textDim, fontSize: 13),
              ),
            ]),
          ),
          if (!PH.compact(context)) const Text('Ver relatório  ›', style: TextStyle(color: PH.accentSoft, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tabs, required this.current, required this.onSelect});
  final List<String> tabs;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          const ButtonGlyph(PadGlyph.lb, size: 20),
          const SizedBox(width: 10),
          for (var i = 0; i < tabs.length; i++)
            Focusable(
              glow: false,
              focusScale: 1.0,
              borderRadius: 6,
              onActivate: () => onSelect(i),
              builder: (context, focused) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == current ? PH.accent : Colors.transparent, width: 3)),
                ),
                child: Text(tabs[i],
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: i == current ? PH.text : PH.textDim)),
              ),
            ),
          const SizedBox(width: 10),
          const ButtonGlyph(PadGlyph.rb, size: 20),
        ]),
      );
}

/// Linha "rótulo: valor" usada nas abas.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 200, child: Text(label, style: const TextStyle(color: PH.textDim, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

/// Painel padrão das abas.
/// Ports de recompilação não incluem o jogo: o usuário precisa da própria cópia.
class _GameDataNotice extends StatelessWidget {
  const _GameDataNotice({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 1100),
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PH.yellow.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(PH.radius),
          border: Border.all(color: PH.yellow.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.album_rounded, color: PH.yellow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Requer os arquivos do jogo original', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(note, style: const TextStyle(color: PH.textDim, height: 1.35)),
            ]),
          ),
        ]),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.maxWidth = 1100});
  final Widget child;
  final String? title;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: PH.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(PH.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Text(title!.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 12),
          ],
          child,
        ]),
      );
}

extension AssetSummary on ReleaseAsset {
  String get summary => '${kind.label}${arch != null ? ' · ${archLabel(arch)}' : ''} · ${formatBytes(size)}';
}
