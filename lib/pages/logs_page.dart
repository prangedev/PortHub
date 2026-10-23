import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/logger.dart';
import '../ui/theme.dart';
import '../widgets/ph_button.dart';

/// Visualizador do sistema de logs (memória + arquivo porthub.log).
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogLevel _min = LogLevel.info;
  late final StreamSubscription<LogEntry> _sub;

  @override
  void initState() {
    super.initState();
    _sub = appLog.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = appLog.entries.where((e) => e.level.index >= _min.index).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PH.bg2,
        title: const Text('Logs'),
        actions: [
          for (final l in LogLevel.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PHChip(label: l.name.toUpperCase(), selected: _min == l, onTap: () => setState(() => _min = l)),
            ),
          const SizedBox(width: 8),
          PHIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copiar',
            onPressed: () => Clipboard.setData(ClipboardData(text: entries.reversed.join('\n'))),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(children: [
        if (appLog.logFile != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: PH.surface,
            child: Text('Arquivo: ${appLog.logFile!.path}', style: const TextStyle(color: PH.textDim, fontSize: 12)),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              final color = switch (e.level) {
                LogLevel.error => PH.red,
                LogLevel.warn => PH.yellow,
                LogLevel.info => PH.text,
                LogLevel.debug => PH.textFaint,
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(e.toString(), style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: color)),
              );
            },
          ),
        ),
      ]),
    );
  }
}
