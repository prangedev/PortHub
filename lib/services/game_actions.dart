import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/logger.dart';
import '../core/models/download_task.dart';
import '../core/models/game.dart';
import '../core/platform_info.dart';
import '../downloads/checksum.dart';
import '../downloads/download_manager.dart';
import '../github/github_client.dart';
import 'hardware/hardware_service.dart';
import 'install_service.dart';
import 'library_service.dart';
import 'native_bridge.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// Coordena as ações do usuário sobre um jogo: Instalar, Atualizar, Jogar,
/// Desinstalar, Abrir GitHub e Importar jogos já instalados.
class GameActions with WidgetsBindingObserver {
  GameActions({
    required this.library,
    required this.downloads,
    required this.installer,
    required this.hardware,
    required this.notifications,
    required this.settings,
    required this.gh,
  }) {
    _sub = downloads.completed.listen(_onDownloaded);
    WidgetsBinding.instance.addObserver(this);
  }

  final LibraryService library;
  final DownloadManager downloads;
  final InstallService installer;
  final HardwareService hardware;
  final NotificationService notifications;
  final SettingsService settings;
  final GitHubClient gh;
  late final StreamSubscription<DownloadTask> _sub;

  // Sessão de jogo em andamento no Android (medida pelo ciclo de vida do app).
  Game? _androidSession;
  DateTime? _androidSessionStart;

  /// Download pronto esperando a permissão "instalar apps desconhecidos":
  /// a instalação continua sozinha quando o usuário volta das configurações.
  DownloadTask? _awaitingInstallPermission;

  List<String> get _abis => hardware.profile?.abis.isNotEmpty == true ? hardware.profile!.abis : [currentProcessArch()];

  /// Instala ou atualiza: escolhe o melhor asset, resolve o checksum e enfileira.
  Future<String?> install(Game game) async {
    final asset = game.bestAsset;
    if (asset == null) return 'Nenhum arquivo compatível com este dispositivo na última release.';
    final release = game.latestRelease;
    final version = release?.tag ?? game.version ?? '?';
    // Já baixado e não instalado (ex.: faltou a permissão): instala sem baixar de novo.
    for (final t in downloads.tasks) {
      if (t.gameId == game.id && t.state == DownloadState.completed && t.version == version && File(t.filePath).existsSync()) {
        unawaited(installDownloaded(t));
        return null;
      }
    }
    final checksum = await Checksum.resolve(release, asset, gh).catchError((Object _) => null);
    await downloads.enqueue(game, asset, version: version, checksum: checksum);
    notifications.push(game.installed ? 'Atualizando' : 'Download iniciado', '${game.name} · ${asset.name}',
        icon: Icons.download_rounded, gameId: game.id);
    return null;
  }

  Future<void> _onDownloaded(DownloadTask task) async {
    if (!settings.autoInstall) return;
    await installDownloaded(task);
  }

  /// Instala um download concluído (automático ou pelo botão em Downloads).
  Future<void> installDownloaded(DownloadTask task) async {
    final game = library.byId(task.gameId);
    if (game == null) return;
    if (Platform.isAndroid && !await NativeBridge.canInstallPackages()) {
      _awaitingInstallPermission = task;
      await downloads.setState(task, DownloadState.completed, error: 'Aguardando permissão para instalar apps');
      notifications.push('Permissão necessária', 'Permita "Instalar apps desconhecidos" para o PortHub; a instalação continua ao voltar.',
          icon: Icons.lock_open_rounded, gameId: game.id);
      await NativeBridge.openInstallPermissionSettings();
      return;
    }
    await downloads.setState(task, DownloadState.installing);
    final r = await installer.install(game, task, _abis);
    if (!r.success) {
      await downloads.setState(task, DownloadState.completed, error: r.message);
      notifications.push('Falha na instalação', '${game.name}: ${r.message}', icon: Icons.error_outline_rounded, gameId: game.id, system: true);
      return;
    }
    await library.markInstalled(game, version: task.version, path: r.path, executable: r.executable, package: r.package);
    await downloads.setState(task, DownloadState.installed);
    if (settings.deleteAfterInstall && !r.external) {
      final f = File(task.filePath);
      if (await f.exists()) await f.delete();
    }
    notifications.push('Pronto para jogar', '${game.name} ${task.version} — ${r.message}',
        icon: Icons.check_circle_rounded, gameId: game.id, system: true);
  }

  /// Abre o jogo e contabiliza o tempo jogado.
  Future<String?> play(Game game) async {
    if (!game.installed) return 'Jogo não instalado';
    if (Platform.isAndroid) {
      final pkg = game.androidPackage;
      if (pkg == null) return 'Pacote Android desconhecido. Reinstale o jogo.';
      final ok = await NativeBridge.launchPackage(pkg);
      if (!ok) return 'Não foi possível abrir $pkg (foi desinstalado?)';
      _androidSession = game;
      _androidSessionStart = DateTime.now();
      return null;
    }
    final exe = game.executablePath;
    if (exe == null || !await File(exe).exists()) {
      return 'Executável não encontrado. Ele foi instalado por um instalador externo? Abra pelo menu do sistema.';
    }
    final started = DateTime.now();
    try {
      final proc = await Process.start(exe, const [], workingDirectory: p.dirname(exe), runInShell: false);
      unawaited(proc.stdout.drain<void>());
      unawaited(proc.stderr.drain<void>());
      appLog.i('Play', 'Iniciado ${game.name} (pid ${proc.pid})');
      // Marca como jogado já na abertura (aparece em "Recentemente jogados").
      game.lastPlayed = started;
      await library.save(game);
      unawaited(proc.exitCode.then((code) {
        appLog.i('Play', '${game.name} encerrou com código $code');
        library.recordPlay(game, DateTime.now().difference(started));
      }));
      return null;
    } catch (e) {
      appLog.e('Play', 'Falha ao iniciar ${game.name}', e);
      return 'Falha ao iniciar: $e';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final pending = _awaitingInstallPermission;
    if (state == AppLifecycleState.resumed && pending != null) {
      _awaitingInstallPermission = null;
      NativeBridge.canInstallPackages().then((ok) {
        if (ok) {
          appLog.i('Install', 'Permissão concedida; retomando ${pending.gameName}');
          installDownloaded(pending);
        }
      });
    }
    if (state == AppLifecycleState.resumed && _androidSession != null && _androidSessionStart != null) {
      final played = DateTime.now().difference(_androidSessionStart!);
      library.recordPlay(_androidSession!, played);
      _androidSession = null;
      _androidSessionStart = null;
      _syncAndroidInstalls();
    }
  }

  Future<void> uninstall(Game game) async {
    if (Platform.isAndroid && game.androidPackage != null) {
      await NativeBridge.uninstallPackage(game.androidPackage!);
      // O resultado é confirmado ao voltar para o app (_syncAndroidInstalls).
      return;
    }
    await installer.removeFiles(game);
    await library.markUninstalled(game);
    notifications.push('Desinstalado', game.name, icon: Icons.delete_outline_rounded, gameId: game.id);
  }

  /// Confere se jogos marcados como instalados ainda existem no Android.
  Future<void> _syncAndroidInstalls() async {
    for (final g in library.installedGames) {
      if (g.androidPackage == null) continue;
      final v = await NativeBridge.installedVersion(g.androidPackage!);
      if (v == null) await library.markUninstalled(g);
    }
  }

  Future<void> openGitHub(Game game) async {
    final url = game.githubUrl.isNotEmpty ? game.githubUrl : null;
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Importação de jogos já instalados:
  /// - Android: compara os apps instalados com o pacote/nome dos jogos;
  /// - Desktop: lê os marcadores `.porthub.json` da pasta de jogos.
  Future<int> importInstalled() async {
    var count = 0;
    if (Platform.isAndroid) {
      final pkgs = await NativeBridge.installedPackages();
      for (final g in library.games.where((g) => !g.installed)) {
        Map<String, dynamic>? match;
        for (final pk in pkgs) {
          final label = (pk['label'] as String? ?? '').toLowerCase();
          if ((g.androidPackage != null && pk['package'] == g.androidPackage) ||
              (label.length > 3 && (label == g.name.toLowerCase() || g.name.toLowerCase().startsWith(label)))) {
            match = pk;
            break;
          }
        }
        if (match != null) {
          await library.markInstalled(g, version: match['version'] as String? ?? '?', package: match['package'] as String?);
          count++;
        }
      }
    } else {
      for (final m in await installer.scanMarkers()) {
        final g = library.byId(m['id'] as String? ?? '');
        if (g == null || g.installed) continue;
        await library.markInstalled(g,
            version: m['version'] as String? ?? '?', path: m['path'] as String?, executable: m['executable'] as String?);
        count++;
      }
    }
    appLog.i('Import', '$count jogos importados');
    notifications.push('Importação concluída', count == 0 ? 'Nenhum jogo novo encontrado' : '$count jogo(s) importado(s)',
        icon: Icons.playlist_add_check_rounded);
    return count;
  }

  void dispose() {
    _sub.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
