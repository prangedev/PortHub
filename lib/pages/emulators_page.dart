import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models/download_task.dart';
import '../core/models/game.dart';
import '../downloads/download_manager.dart';
import '../emulators/emulator_def.dart';
import '../emulators/rom_game.dart';
import '../emulators/rom_library_service.dart';
import '../emulators/xbox/xbox_unity.dart';
import '../services/game_actions.dart';
import '../services/library_service.dart';
import '../ui/input/input_router.dart';
import '../ui/theme.dart';
import '../widgets/badges.dart';
import '../widgets/focusable.dart';
import '../widgets/game_art.dart';
import '../widgets/hint_bar.dart';
import '../widgets/ph_button.dart';
import 'navigation.dart';

/// Aba Emuladores: um painel por console (emulador + jogos importados).
class EmulatorsPage extends StatefulWidget {
  const EmulatorsPage({super.key});

  @override
  State<EmulatorsPage> createState() => _EmulatorsPageState();
}

class _EmulatorsPageState extends State<EmulatorsPage> with PadHandlerMixin {
  RomGame? _focused;

  @override
  bool onPad(PadAction a) {
    if (a == PadAction.secondary && _focused != null) {
      _showOptions(xbox360, _focused!);
      return true;
    }
    return false;
  }

  Future<void> _import(EmulatorDef emu, {required bool folder}) async {
    final roms = context.read<RomLibraryService>();
    try {
      final report = await roms.pickAndImport(emu, folder: folder);
      if (!mounted) return;
      if (report.added == 0 && report.duplicates == 0 && report.failures.isEmpty) return; // seletor cancelado
      showMessage(context, report.summary, error: report.added == 0 && report.failures.isNotEmpty);
    } catch (e) {
      if (mounted) showMessage(context, 'Falha ao importar: $e', error: true);
    }
  }

  Future<void> _play(EmulatorDef emu, RomGame rom) async {
    final err = await context.read<RomLibraryService>().launch(emu, rom);
    if (err != null && mounted) showMessage(context, err, error: true);
  }

  Future<void> _showOptions(EmulatorDef emu, RomGame rom) async {
    final roms = context.read<RomLibraryService>();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: PH.surface,
        title: Text(rom.name),
        children: [
          _option(ctx, 'play', Icons.play_arrow_rounded, 'Jogar no ${emu.name}', autofocus: true),
          if (rom.titleId != null) _option(ctx, 'cover', Icons.image_search_rounded, 'Trocar capa'),
          _option(ctx, 'identify', Icons.refresh_rounded, 'Identificar de novo'),
          _option(ctx, 'remove', Icons.delete_outline_rounded, 'Remover da biblioteca'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              [
                rom.fileName,
                if (rom.titleId != null) 'Title ID ${rom.titleId}',
                if (rom.discLabel.isNotEmpty) rom.discLabel,
                if (rom.size != null) formatBytes(rom.size!),
              ].join(' · '),
              style: const TextStyle(color: PH.textFaint, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'play':
        await _play(emu, rom);
      case 'cover':
        await showDialog<void>(context: context, builder: (_) => CoverPickerDialog(rom: rom));
      case 'identify':
        try {
          await roms.reidentify(rom);
          if (mounted) showMessage(context, rom.titleId == null ? 'Jogo não reconhecido pelo XboxUnity.' : 'Identificado: ${rom.name}');
        } catch (e) {
          if (mounted) showMessage(context, 'Não foi possível ler o disco: $e', error: true);
        }
      case 'remove':
        await roms.remove(rom);
        _focused = null;
        if (mounted) showMessage(context, '${rom.name} removido (o arquivo continua no aparelho).');
    }
  }

  Widget _option(BuildContext ctx, String value, IconData icon, String label, {bool autofocus = false}) =>
      SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, value),
        child: Focusable(
          autofocus: autofocus,
          glow: false,
          focusScale: 1.0,
          onActivate: () => Navigator.pop(ctx, value),
          builder: (_, focused) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: focused ? PH.accent.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(icon, size: 20, color: focused ? PH.accent : PH.textDim),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pad = PH.compact(context) ? 16.0 : 48.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 32),
      children: [
        for (final emu in emulators)
          _SystemSection(
            emu: emu,
            onImport: (folder) => _import(emu, folder: folder),
            onPlay: (rom) => _play(emu, rom),
            onOptions: (rom) => _showOptions(emu, rom),
            onFocusRom: (rom) => _focused = rom,
          ),
      ],
    );
  }
}

class _SystemSection extends StatelessWidget {
  const _SystemSection({
    required this.emu,
    required this.onImport,
    required this.onPlay,
    required this.onOptions,
    required this.onFocusRom,
  });
  final EmulatorDef emu;
  final void Function(bool folder) onImport;
  final void Function(RomGame) onPlay;
  final void Function(RomGame) onOptions;
  final void Function(RomGame?) onFocusRom;

  @override
  Widget build(BuildContext context) {
    final roms = context.watch<RomLibraryService>();
    final list = roms.bySystem(emu.system);
    final s = PH.scale(context);

    final header = Row(children: [
      Icon(emu.icon, color: emu.accent, size: 22),
      const SizedBox(width: 10),
      Text('MEUS JOGOS DE ${emu.systemName.toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.6, fontSize: 15)),
      const SizedBox(width: 10),
      Text('${list.length}', style: const TextStyle(color: PH.textFaint, fontWeight: FontWeight.w700)),
      const Spacer(),
      if (list.isNotEmpty) ...[
        const ButtonGlyph(PadGlyph.x, size: 20),
        const SizedBox(width: 6),
        const Text('Opções', style: TextStyle(color: PH.textDim, fontSize: 13)),
      ],
    ]);
    final games = list.isEmpty
        ? _EmptyRoms(emu: emu)
        : SizedBox(
            height: 150 * s / emu.coverAspect + 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, i) => _RomCard(
                rom: list[i],
                emu: emu,
                width: 150 * s,
                autofocus: i == 0,
                onPlay: () => onPlay(list[i]),
                onOptions: () => onOptions(list[i]),
                onFocus: (f) => onFocusRom(f ? list[i] : null),
              ),
            ),
          );
    final progress = [
      if (roms.importing) ...[
        const SizedBox(height: 14),
        Text(roms.importStatus, style: const TextStyle(color: PH.textDim, fontSize: 13)),
        const SizedBox(height: 6),
        PHProgress(value: roms.importProgress),
      ],
    ];
    final panel = _EmulatorPanel(emu: emu, onImport: onImport, takeFocus: list.isEmpty);

    // Com jogos importados, eles vêm primeiro (no celular deitado cabem sem rolar).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.isEmpty
          ? [panel, ...progress, const SizedBox(height: 24), header, const SizedBox(height: 14), games]
          : [header, const SizedBox(height: 14), games, ...progress, const SizedBox(height: 28), panel],
    );
  }
}

/// Cartão do emulador: estado da instalação, compatibilidade e importação.
class _EmulatorPanel extends StatelessWidget {
  const _EmulatorPanel({required this.emu, required this.onImport, this.takeFocus = true});
  final EmulatorDef emu;
  final void Function(bool folder) onImport;

  /// Recebe o foco inicial (quando ainda não há jogos importados).
  final bool takeFocus;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final game = lib.byId(emu.catalogId);
    final task = context.watch<DownloadManager>().taskFor(emu.catalogId);
    final actions = context.read<GameActions>();
    final busy = task != null && !task.state.isFinished;
    final canImport = RomLibraryService.canImport;

    Future<void> run(Future<String?> Function() f) async {
      final err = await f();
      if (err != null && context.mounted) showMessage(context, err, error: true);
    }

    final primary = switch (game) {
      null => PHButton(
          label: lib.refreshing ? 'Sincronizando catálogo…' : 'Sincronizar catálogo',
          icon: Icons.sync_rounded,
          onPressed: lib.refreshing ? null : lib.refresh,
        ),
      Game _ when busy => PHButton(label: task.state.label, icon: Icons.downloading_rounded, onPressed: null),
      Game g when !g.installed => PHButton(
          label: 'Instalar ${emu.name}',
          icon: Icons.download_rounded,
          gradient: PH.installGradient,
          autofocus: takeFocus,
          onPressed: g.bestAsset == null ? null : () => installWithConfirmation(context, g),
        ),
      Game g when g.updateAvailable => PHButton(
          label: 'Atualizar ${emu.name}',
          icon: Icons.system_update_alt_rounded,
          gradient: PH.updateGradient,
          autofocus: takeFocus,
          onPressed: () => installWithConfirmation(context, g),
        ),
      Game g => PHButton(
          label: 'Abrir ${emu.name}',
          icon: Icons.play_arrow_rounded,
          gradient: PH.playGradient,
          autofocus: takeFocus,
          onPressed: () => run(() => actions.play(g)),
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PH.radiusLg),
        gradient: LinearGradient(colors: [emu.accent.withValues(alpha: 0.16), PH.surface]),
        border: Border.all(color: PH.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: game == null
                  ? ColoredBox(color: emu.accent, child: Icon(emu.icon, color: Colors.white, size: 36))
                  : GameArt(game: game, kind: ArtKind.icon),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
                Text(emu.systemName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                TagPill(emu.name, icon: Icons.memory_rounded),
                if (game != null) StatusChip(status: game.status, dense: true),
                if (game != null) CompatBadge(result: game.compatibility, showLabel: true),
                if (game?.version != null) TagPill(game!.version!, icon: Icons.sell_outlined),
              ]),
              const SizedBox(height: 8),
              Text(emu.description, style: const TextStyle(color: PH.textDim, height: 1.35)),
              if (game != null && game.compatibility.blockingReason != null) ...[
                const SizedBox(height: 6),
                Text(game.compatibility.blockingReason!, style: const TextStyle(color: PH.red, fontWeight: FontWeight.w700)),
              ],
              if (busy && task.state == DownloadState.downloading) ...[
                const SizedBox(height: 10),
                PHProgress(value: task.progress),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          primary,
          PHButton(
            label: 'Importar ISO',
            icon: Icons.album_rounded,
            autofocus: takeFocus && (game?.installed ?? false),
            onPressed: canImport ? () => onImport(false) : null,
          ),
          PHButton(
            label: 'Importar pasta',
            icon: Icons.folder_open_rounded,
            onPressed: canImport ? () => onImport(true) : null,
          ),
          if (game != null)
            PHButton(label: 'Detalhes', icon: Icons.info_outline_rounded, onPressed: () => openGame(context, game)),
        ]),
        if (!canImport) ...[
          const SizedBox(height: 10),
          Text('${emu.name} roda no Android. A importação de ISOs fica disponível no app para Android.',
              style: const TextStyle(color: PH.textFaint, fontSize: 13)),
        ],
      ]),
    );
  }
}

class _EmptyRoms extends StatelessWidget {
  const _EmptyRoms({required this.emu});
  final EmulatorDef emu;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PH.radiusLg),
          border: Border.all(color: PH.stroke),
        ),
        child: Column(children: [
          const Icon(Icons.album_rounded, size: 48, color: PH.textFaint),
          const SizedBox(height: 10),
          Text('Nenhum jogo de ${emu.systemName} importado.', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Importe os ISOs dos seus discos (${emu.extensions.join(', ')}). O PortHub não copia os arquivos: '
            'lê o Title ID do disco e busca a capa no XboxUnity.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: PH.textDim),
          ),
        ]),
      );
}

class _RomCard extends StatelessWidget {
  const _RomCard({
    required this.rom,
    required this.emu,
    required this.width,
    required this.onPlay,
    required this.onOptions,
    required this.onFocus,
    this.autofocus = false,
  });
  final RomGame rom;
  final EmulatorDef emu;
  final double width;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final ValueChanged<bool> onFocus;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final h = width / emu.coverAspect;
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Focusable(
          autofocus: autofocus,
          onActivate: onPlay,
          onLongPress: onOptions,
          onFocusChange: onFocus,
          scrollAlignment: 0.3,
          builder: (context, focused) => Container(
            width: width,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PH.radius),
              border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PH.radius - 2),
              child: Stack(fit: StackFit.expand, children: [
                RomCover(rom: rom),
                if (rom.discLabel.isNotEmpty)
                  Positioned(left: 6, top: 6, child: TagPill(rom.discLabel)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(rom.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          rom.lastPlayed != null ? 'Jogado ${timeAgo(rom.lastPlayed!)}' : (rom.titleId ?? 'Sem Title ID'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PH.textFaint, fontSize: 12),
        ),
      ]),
    );
  }
}

/// Capa de um jogo importado. As do XboxUnity vêm abertas (verso, lombada e
/// frente); alinhando à direita, o recorte mostra só a frente — como o Aurora.
class RomCover extends StatelessWidget {
  const RomCover({super.key, required this.rom, this.url});
  final RomGame rom;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final src = url ?? rom.coverUrl;
    final fallback = _GeneratedRomArt(name: rom.name);
    if (src == null) return fallback;
    final wrap = src.contains('xboxunity.net');
    return CachedNetworkImage(
      imageUrl: src,
      fit: BoxFit.cover,
      alignment: wrap ? Alignment.centerRight : Alignment.center,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
      memCacheWidth: wrap ? 900 : 480,
    );
  }
}

class _GeneratedRomArt extends StatelessWidget {
  const _GeneratedRomArt({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E7D32), Color(0xFF0B1F0C)],
          ),
        ),
        // Monograma: o nome fica na legenda abaixo da capa.
        child: Center(
          child: Text(GeneratedArt.initials(name),
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, color: Colors.white.withValues(alpha: 0.9))),
        ),
      );
}

/// Seletor de capas do XboxUnity, como no Aurora: todas as capas enviadas
/// pela comunidade, oficiais primeiro, mais a boxart do marketplace.
class CoverPickerDialog extends StatelessWidget {
  const CoverPickerDialog({super.key, required this.rom});
  final RomGame rom;

  @override
  Widget build(BuildContext context) {
    final roms = context.read<RomLibraryService>();
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: PH.surface,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Capas de ${rom.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Fonte: XboxUnity (a mesma do Aurora) · marketplace do Xbox 360',
                style: TextStyle(color: PH.textDim, fontSize: 13)),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<XboxCover>>(
                future: roms.coverOptions(rom),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final covers = snap.data ?? const <XboxCover>[];
                  final tiles = <Widget>[
                    for (var i = 0; i < covers.length; i++)
                      _CoverTile(
                        url: covers[i].largeUrl,
                        rom: rom,
                        selected: covers[i].id == rom.coverId,
                        autofocus: covers[i].id == rom.coverId || (rom.coverId == null && i == 0),
                        label: covers[i].official ? 'Oficial' : (covers[i].user ?? ''),
                        rating: covers[i].rating,
                        onTap: () async {
                          await roms.setCover(rom, covers[i]);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    _CoverTile(
                      url: XboxUnity.marketplaceBoxart(rom.titleId!),
                      rom: rom,
                      selected: rom.coverId == null && (rom.coverUrl?.contains('download.xbox.com') ?? false),
                      label: 'Marketplace',
                      onTap: () async {
                        await roms.useMarketplaceCover(rom);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ];
                  return GridView.extent(
                    maxCrossAxisExtent: 170,
                    childAspectRatio: 0.62,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    padding: const EdgeInsets.all(6),
                    children: tiles,
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({
    required this.url,
    required this.rom,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.autofocus = false,
    this.rating,
  });
  final String url;
  final RomGame rom;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool autofocus;
  final int? rating;

  @override
  Widget build(BuildContext context) => Focusable(
        autofocus: autofocus,
        onActivate: onTap,
        builder: (context, focused) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PH.radius),
                border: Border.all(color: focused ? Colors.white : (selected ? PH.green : PH.stroke), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PH.radius - 2),
                child: RomCover(rom: rom, url: url),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            if (selected) const Icon(Icons.check_circle_rounded, color: PH.green, size: 14),
            if (selected) const SizedBox(width: 4),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: PH.textDim)),
            ),
            for (var i = 0; i < (rating ?? 0).clamp(0, 5); i++) const Icon(Icons.star_rounded, color: PH.yellow, size: 12),
          ]),
        ]),
      );
}
