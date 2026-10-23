import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_service.dart';
import '../ui/theme.dart';
import '../widgets/game_card.dart';
import '../widgets/ph_button.dart';
import 'navigation.dart';

/// Pesquisa estilo Steam: por nome, desenvolvedor, categoria, engine ou tag,
/// com resultados ao vivo.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  SearchField _field = SearchField.all;

  static const _fields = [
    (SearchField.all, 'Tudo'),
    (SearchField.name, 'Nome'),
    (SearchField.developer, 'Desenvolvedor'),
    (SearchField.category, 'Categoria'),
    (SearchField.engine, 'Engine'),
    (SearchField.tag, 'Tag'),
  ];

  @override
  void initState() {
    super.initState();
    // No desktop o campo já abre focado; no Android (controle/toque) o usuário escolhe.
    if (!Platform.isAndroid) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryService>();
    final results = lib.search(_ctrl.text, field: _field);
    final pad = PH.compact(context) ? 16.0 : 48.0;
    final s = PH.scale(context);

    // Sugestões rápidas: engines e categorias existentes.
    final suggestions = {...lib.allEngines, ...lib.allCategories}.take(14).toList();

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 28, pad, 8),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Pesquisar jogos, desenvolvedores, engines…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 28),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(_ctrl.clear),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (f, label) in _fields) PHChip(label: label, selected: _field == f, onTap: () => setState(() => _field = f)),
            ]),
            if (_ctrl.text.isEmpty && suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('SUGESTÕES', style: TextStyle(color: PH.textFaint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final sug in suggestions)
                  PHChip(
                    label: sug,
                    icon: Icons.north_east_rounded,
                    selected: false,
                    onTap: () => setState(() => _ctrl.text = sug),
                  ),
              ]),
            ],
            const SizedBox(height: 20),
            Text(
              _ctrl.text.isEmpty ? 'Todos os jogos (${results.length})' : '${results.length} resultado(s) para "${_ctrl.text}"',
              style: const TextStyle(color: PH.textDim, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 40),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 190 * s,
            mainAxisSpacing: 22,
            crossAxisSpacing: 20,
            childAspectRatio: 0.56,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => LayoutBuilder(
              builder: (context, c) => GameCard(game: results[i], width: c.maxWidth, onOpen: () => openGame(context, results[i])),
            ),
            childCount: results.length,
          ),
        ),
      ),
    ]);
  }
}
