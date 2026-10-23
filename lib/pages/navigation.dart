import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../services/game_actions.dart';
import 'game_details/game_details_page.dart';

/// Abre a página do jogo com transição de zoom + fade.
Future<void> openGame(BuildContext context, Game game) {
  return Navigator.of(context).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => GameDetailsPage(gameId: game.id),
    transitionsBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(curved), child: child),
      );
    },
  ));
}

/// Snackbar padrão.
void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFF5A1D22) : null,
      width: 520,
    ));
}

/// Instala (ou atualiza) pedindo confirmação quando o jogo é incompatível.
/// O foco começa em "Cancelar" para um duplo A no controle não instalar sem querer.
Future<void> installWithConfirmation(BuildContext context, Game game) async {
  final actions = context.read<GameActions>();
  if (game.compatibility.level == CompatLevel.incompatible) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(game.isEmulator ? 'Emulador incompatível' : 'Jogo incompatível'),
        content: Text('${game.compatibility.blockingReason ?? game.compatibility.message}\n\nDeseja instalar mesmo assim?'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Instalar mesmo assim')),
        ],
      ),
    );
    if (ok != true) return;
  }
  final err = await actions.install(game);
  if (err != null && context.mounted) showMessage(context, err, error: true);
}
