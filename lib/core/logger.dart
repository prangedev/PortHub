import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Níveis de log usados pelo sistema de logs do PortHub.
enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry(this.level, this.tag, this.message) : time = DateTime.now();

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  @override
  String toString() {
    final t = time.toIso8601String().substring(11, 23);
    return '$t [${level.name.toUpperCase().padRight(5)}] $tag: $message';
  }
}

/// Logger simples: mantém as últimas entradas em memória (para a tela de logs)
/// e grava tudo em `porthub.log` no diretório de suporte do app.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const _maxEntries = 1500;
  static const _maxFileBytes = 2 * 1024 * 1024;

  final _buffer = ListQueue<LogEntry>();
  final _controller = StreamController<LogEntry>.broadcast();
  IOSink? _sink;
  File? logFile;

  Stream<LogEntry> get stream => _controller.stream;
  List<LogEntry> get entries => List.unmodifiable(_buffer);

  Future<void> init(Directory dir) async {
    try {
      final file = File(p.join(dir.path, 'porthub.log'));
      // Rotação simples: o log anterior vira porthub.old.log.
      if (await file.exists() && await file.length() > _maxFileBytes) {
        await file.rename(p.join(dir.path, 'porthub.old.log'));
      }
      logFile = file;
      _sink = file.openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('Logger: não foi possível abrir arquivo de log: $e');
    }
  }

  void log(LogLevel level, String tag, String message, [Object? error, StackTrace? stack]) {
    final full = error == null ? message : '$message | $error';
    final entry = LogEntry(level, tag, full);
    _buffer.addLast(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    _controller.add(entry);
    debugPrint(entry.toString());
    _sink?.writeln(entry.toString());
    if (stack != null && level == LogLevel.error) _sink?.writeln(stack.toString());
  }

  void d(String tag, String msg) => log(LogLevel.debug, tag, msg);
  void i(String tag, String msg) => log(LogLevel.info, tag, msg);
  void w(String tag, String msg, [Object? e]) => log(LogLevel.warn, tag, msg, e);
  void e(String tag, String msg, [Object? e, StackTrace? s]) => log(LogLevel.error, tag, msg, e, s);

  Future<void> flush() async => _sink?.flush();
}

/// Atalho global.
final appLog = AppLogger.instance;
