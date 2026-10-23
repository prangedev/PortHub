import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../downloads/download_manager.dart';
import '../services/library_service.dart';
import '../ui/theme.dart';
import '../widgets/game_card.dart';
import '../widgets/ph_button.dart';
import 'navigation.dart';

/// Filtros da biblioteca.
const kCategories = ['RPG', 'Ação', 'FPS', 'Corrida', 'Plataforma', 'Estratégia', 'Terror', 'Puzzle'];
const kSpecialTags = ['Offline', 'Multiplayer', 'Open Source'];

enum LibrarySort { name, recent, size, compat, stars }

/// Biblioteca completa em grade, com filtros por categoria, tags, status e
/// compatibilidade.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final Set<String> _categories = {};
  final Set<String> _tags = {};
  InstallStatus? _status;
  CompatLevel? _compat;
  LibrarySort _sort = LibrarySort.name;

  List<Game> _apply(List<Game> all) {
    final list = all.where((g) {
      if (_categories.isNotEmpty && !g.categories.any(_categories.contains)) return false;
      if (_tags.isNotEmpty && !_tags.every(g.tags.contains)) return false;
      if (_status != null && g.status != _status) return false;
      if (_compat != null && g.compatibility.level != _compat) return false;
      return true;
    }).toList();
    switch (_sort) {
      case LibrarySort.name:
        break;
      case LibrarySort.recent:
        list.sort((a, b) => (b.lastUpdate ?? DateTime(0)).compareTo(a.lastUpdate ?? DateTime(0)));
      case LibrarySort.size:
        list.sort((a, b) => (a.size ?? 1 << 40).compareTo(b.size ?? 1 << 40));
      case LibrarySort.compat:
        list.sort((a, b) => b.compatibility.score.compareTo(a.compatibility.score));
      case LibrarySort.stars:
        list.sort((a, b) => b.stars.compareTo(a.stars));
    }
    return list;
  }

  void _toggle<T>(Set<T> set, T v) => setState(() => set.contains(v) ? set.remove(v) : set.add(v));

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final dl = context.watch<DownloadManager>();
    final games = _apply(lib.games);
    final s = PH.scale(context);
    final pad = PH.compact(context) ? 16.0 : 48.0;
    final extraCategories = lib.allCategories.where((c) => !kCategories.contains(c)).toList()..sort();

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 24, pad, 8),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Biblioteca', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(width: 14),
              Text('${games.length} de ${lib.games.length}', style: const TextStyle(color: PH.textDim, fontSize: 16)),
            ]),
            const SizedBox(height: 16),
            _FilterRow(label: 'Categorias', children: [
              for (final c in [...kCategories, ...extraCategories])
                PHChip(label: c, selected: _categories.contains(c), onTap: () => _toggle(_categories, c)),
            ]),
            _FilterRow(label: 'Tipo', children: [
              for (final t in kSpecialTags)
                PHChip(
                  label: t,
                  icon: switch (t) {
                    'Offline' => Icons.wifi_off_rounded,
                    'Multiplayer' => Icons.groups_rounded,
                    _ => Icons.code_rounded,
                  },
                  selected: _tags.contains(t),
                  onTap: () => _toggle(_tags, t),
                ),
              const SizedBox(width: 12),
              for (final st in InstallStatus.values)
                PHChip(label: st.label, selected: _status == st, onTap: () => setState(() => _status = _status == st ? null : st)),
            ]),
            _FilterRow(label: 'Compatibilidade', children: [
              for (final c in [CompatLevel.compatible, CompatLevel.partial, CompatLevel.incompatible])
                PHChip(
                  label: c.label,
                  icon: Icons.circle,
                  selected: _compat == c,
                  onTap: () => setState(() => _compat = _compat == c ? null : c),
                ),
              const SizedBox(width: 12),
              for (final (sort, label) in const [
                (LibrarySort.name, 'A–Z'),
                (LibrarySort.recent, 'Mais recentes'),
                (LibrarySort.compat, 'Melhor compatibilidade'),
                (LibrarySort.stars, 'Mais populares'),
                (LibrarySort.size, 'Menores'),
              ])
                PHChip(label: label, icon: Icons.sort_rounded, selected: _sort == sort, onTap: () => setState(() => _sort = sort)),
            ]),
          ]),
        ),
      ),
      if (games.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('Nenhum jogo com esses filtros.', style: TextStyle(color: PH.textDim))),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 40),
          sliver: GameCardGrid(
            count: games.length,
            maxTileWidth: 190 * s,
            itemBuilder: (context, i, w) {
              final g = games[i];
              return GameCard(
                game: g,
                width: w,
                autofocus: i == 0,
                progress: dl.taskFor(g.id)?.progress,
                onOpen: () => openGame(context, g),
              );
            },
          ),
        ),
    ]);
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(
            width: PH.compact(context) ? 0 : 130,
            child: PH.compact(context)
                ? null
                : Text(label.toUpperCase(), style: const TextStyle(color: PH.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [for (final c in children) Padding(padding: const EdgeInsets.only(right: 8), child: c)]),
            ),
          ),
        ]),
      );
}
