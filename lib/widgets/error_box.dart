import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../ui/theme.dart';

/// Substitui a "tela cinza/vermelha" do Flutter quando um componente falha ao
/// desenhar: o resto do app continua usável e o erro vai para os logs.
Widget friendlyErrorWidget(FlutterErrorDetails details) {
  appLog.e('UI', 'Falha ao desenhar ${details.context ?? 'componente'}', details.exception, details.stack);
  return const _ErrorBox();
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox();

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: PH.surface,
            borderRadius: BorderRadius.circular(PH.radius),
            border: Border.all(color: PH.red.withValues(alpha: 0.4)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, color: PH.red, size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Esta parte não pôde ser exibida. Detalhes em Configurações › Logs.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: PH.textDim, fontSize: 12),
              ),
            ),
          ]),
        ),
      );
}
