import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../core/logger.dart';
import '../core/models/download_task.dart';
import '../core/models/game.dart';
import '../core/models/release_info.dart';
import '../database/download_dao.dart';
import '../services/native_bridge.dart';
import '../services/settings_service.dart';
import 'checksum.dart';

/// Estado interno de um download em andamento.
class _Active {
  _Active(this.client);
  final http.Client client;
  StreamSubscription<List<int>>? sub;
  IOSink? sink;
  Completer<void>? done;
  final samples = <(DateTime, int)>[];
  bool stopping = false;
}

/// Download Manager próprio:
/// - fila com N downloads simultâneos (configurável);
/// - pausar/continuar com HTTP Range (arquivo `.part`);
/// - velocidade (janela móvel de 3 s) e ETA;
/// - verificação SHA256/MD5 ao final;
/// - estado persistido no SQLite (sobrevive ao fechamento do app);
/// - no Android, um serviço em primeiro plano mantém o processo vivo em segundo plano.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._dao, this._settings);
  final DownloadDao _dao;
  final SettingsService _settings;

  final List<DownloadTask> tasks = [];
  final Map<int, _Active> _active = {};
  final _completed = StreamController<DownloadTask>.broadcast();
  late Directory _dir;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

  /// Emite quando um download termina e passou na verificação.
  Stream<DownloadTask> get completed => _completed.stream;

  int get activeCount => tasks.where((t) => t.state.isActive).length;
  double get totalSpeed => tasks.fold(0.0, (s, t) => s + (t.state == DownloadState.downloading ? t.speedBps : 0));

  DownloadTask? taskFor(String gameId) {
    for (final t in tasks) {
      if (t.gameId == gameId && !t.state.isFinished && t.state != DownloadState.failed) return t;
    }
    return null;
  }

  Future<void> init() async {
    _dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'downloads'));
    await _dir.create(recursive: true);
    tasks.addAll(await _dao.all());
    // Downloads interrompidos pelo fechamento do app voltam como "pausado".
    for (final t in tasks) {
      if (t.state == DownloadState.downloading || t.state == DownloadState.verifying) {
        t.state = DownloadState.paused;
        await _dao.update(t);
      }
      final part = File(t.partPath);
      if (t.state == DownloadState.paused && await part.exists()) t.receivedBytes = await part.length();
    }
    notifyListeners();
  }

  /// Enfileira o download de [asset] para [game].
  Future<DownloadTask> enqueue(Game game, ReleaseAsset asset, {required String version, String? checksum}) async {
    final existing = taskFor(game.id);
    if (existing != null) return existing;
    final safeName = asset.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final gameDir = Directory(p.join(_dir.path, game.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')));
    await gameDir.create(recursive: true);
    final task = DownloadTask(
      gameId: game.id,
      gameName: game.name,
      url: asset.url,
      fileName: safeName,
      filePath: p.join(gameDir.path, safeName),
      version: version,
      kind: asset.kind,
      totalBytes: asset.size,
      checksum: checksum ?? asset.checksum,
    );
    task.id = await _dao.insert(task);
    tasks.insert(0, task);
    appLog.i('Download', 'Na fila: ${game.name} → ${asset.name} (${formatBytes(asset.size)})');
    notifyListeners();
    _pump();
    return task;
  }

  void pause(DownloadTask t) {
    if (t.state == DownloadState.queued) {
      t.state = DownloadState.paused;
      _dao.update(t);
      notifyListeners();
      return;
    }
    if (t.state != DownloadState.downloading) return;
    _stop(t, DownloadState.paused);
  }

  void resume(DownloadTask t) {
    if (t.state != DownloadState.paused && t.state != DownloadState.failed) return;
    t
      ..state = DownloadState.queued
      ..error = null;
    _dao.update(t);
    notifyListeners();
    _pump();
  }

  Future<void> cancel(DownloadTask t) async {
    if (t.state == DownloadState.downloading) await _stop(t, DownloadState.canceled);
    t.state = DownloadState.canceled;
    for (final path in [t.partPath, t.filePath]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await _dao.update(t);
    notifyListeners();
    _pump();
  }

  Future<void> remove(DownloadTask t) async {
    if (!t.state.isFinished && t.state != DownloadState.failed) await cancel(t);
    tasks.remove(t);
    if (t.id != null) await _dao.delete(t.id!);
    notifyListeners();
  }

  Future<void> clearFinished() async {
    for (final t in tasks.where((t) => t.state.isFinished).toList()) {
      tasks.remove(t);
      if (t.id != null) await _dao.delete(t.id!);
    }
    notifyListeners();
  }

  /// Atualiza o estado (usado pelo instalador) e persiste.
  Future<void> setState(DownloadTask t, DownloadState s, {String? error}) async {
    t
      ..state = s
      ..error = error;
    await _dao.update(t);
    notifyListeners();
  }

  void _pump() {
    final max = _settings.maxConcurrentDownloads;
    final running = tasks.where((t) => t.state == DownloadState.downloading).length;
    var slots = max - running;
    for (final t in tasks.reversed) {
      if (slots <= 0) break;
      if (t.state == DownloadState.queued) {
        slots--;
        _run(t);
      }
    }
    _updateBackgroundService();
  }

  Future<void> _stop(DownloadTask t, DownloadState newState) async {
    final a = _active.remove(t.id);
    if (a != null) {
      a.stopping = true;
      await a.sub?.cancel();
      if (a.done != null && !a.done!.isCompleted) a.done!.complete();
      await a.sink?.flush();
      await a.sink?.close();
      a.client.close();
    }
    t
      ..state = newState
      ..speedBps = 0
      ..eta = null;
    await _dao.update(t);
    notifyListeners();
    _pump();
  }

  Future<void> _run(DownloadTask t) async {
    t
      ..state = DownloadState.downloading
      ..error = null;
    notifyListeners();
    final client = http.Client();
    final active = _Active(client);
    _active[t.id!] = active;

    try {
      final part = File(t.partPath);
      var offset = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(t.url))..headers['User-Agent'] = AppConfig.userAgent;
      if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
      final res = await client.send(req).timeout(const Duration(seconds: 30));

      if (res.statusCode == 416 && offset > 0 && offset >= t.totalBytes && t.totalBytes > 0) {
        // Já estava completo.
        await res.stream.drain<void>();
        await _finish(t, active);
        return;
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      if (res.statusCode == 200 && offset > 0) {
        // Servidor não suporta Range: recomeça do zero.
        offset = 0;
        appLog.w('Download', 'Servidor sem suporte a Range; reiniciando ${t.fileName}');
      }
      final len = res.contentLength;
      if (len != null && len > 0) t.totalBytes = offset + len;
      t.receivedBytes = offset;

      final sink = part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
      active.sink = sink;
      final done = Completer<void>();
      active.done = done;
      active.sub = res.stream.listen(
        (chunk) {
          sink.add(chunk);
          t.receivedBytes += chunk.length;
          _sample(t, active);
        },
        onDone: () => done.isCompleted ? null : done.complete(),
        onError: (Object e) => done.isCompleted ? null : done.completeError(e),
        cancelOnError: true,
      );
      await done.future;
      if (active.stopping) return;
      await sink.flush();
      await sink.close();
      await _finish(t, active);
    } catch (e) {
      if (active.stopping) return;
      appLog.e('Download', 'Falha em ${t.fileName}', e);
      _active.remove(t.id);
      client.close();
      t
        ..state = DownloadState.failed
        ..error = '$e'
        ..speedBps = 0;
      await _dao.update(t);
      notifyListeners();
      _pump();
    }
  }

  void _sample(DownloadTask t, _Active a) {
    final now = DateTime.now();
    a.samples.add((now, t.receivedBytes));
    a.samples.removeWhere((s) => now.difference(s.$1) > const Duration(seconds: 3));
    if (a.samples.length >= 2) {
      final first = a.samples.first;
      final secs = now.difference(first.$1).inMilliseconds / 1000;
      if (secs > 0.2) t.speedBps = (t.receivedBytes - first.$2) / secs;
    }
    if (t.speedBps > 0 && t.totalBytes > 0) {
      t.eta = Duration(seconds: ((t.totalBytes - t.receivedBytes) / t.speedBps).round());
    }
    if (now.difference(_lastNotify) > const Duration(milliseconds: 250)) {
      _lastNotify = now;
      notifyListeners();
    }
    if (now.difference(_lastPersist) > const Duration(seconds: 2)) {
      _lastPersist = now;
      _dao.update(t);
      _updateBackgroundService();
    }
  }

  Future<void> _finish(DownloadTask t, _Active a) async {
    _active.remove(t.id);
    a.client.close();
    t
      ..speedBps = 0
      ..eta = null;

    final part = File(t.partPath);
    if (_settings.verifyChecksums && t.checksum != null) {
      t.state = DownloadState.verifying;
      notifyListeners();
      final ok = await Checksum.verify(part.path, t.checksum!);
      if (!ok) {
        await part.delete();
        t
          ..state = DownloadState.failed
          ..receivedBytes = 0
          ..error = 'Falha na verificação de integridade (${t.checksum!.split(':').first.toUpperCase()} não confere)';
        await _dao.update(t);
        notifyListeners();
        _pump();
        return;
      }
      t.checksumVerified = true;
    }

    final target = File(t.filePath);
    if (await target.exists()) await target.delete();
    await part.rename(t.filePath);
    t.state = DownloadState.completed;
    await _dao.update(t);
    appLog.i('Download', 'Concluído: ${t.fileName}${t.checksumVerified ? ' (integridade verificada)' : ''}');
    notifyListeners();
    _completed.add(t);
    _pump();
  }

  void _updateBackgroundService() {
    if (!Platform.isAndroid) return;
    final active = tasks.where((t) => t.state == DownloadState.downloading).toList();
    if (active.isEmpty) {
      NativeBridge.setDownloadService(false);
    } else {
      final pct = active.map((t) => (t.progress * 100).round()).join('% · ');
      NativeBridge.setDownloadService(true, text: '${active.length} download(s) · $pct% · ${formatSpeed(totalSpeed)}');
    }
  }
}
