import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/logger.dart';
import '../core/models/download_task.dart';
import '../core/models/game.dart';
import '../core/models/release_info.dart';
import '../github/asset_detector.dart';
import 'native_bridge.dart';
import 'settings_service.dart';

class InstallResult {
  const InstallResult.ok(this.message, {this.path, this.executable, this.package, this.external = false}) : success = true;
  const InstallResult.fail(this.message)
      : success = false,
        path = null,
        executable = null,
        package = null,
        external = false;

  final bool success;
  final String message;
  final String? path;
  final String? executable;
  final String? package;

  /// Instalado por um instalador externo (EXE/MSI/DEB): o PortHub não gerencia o executável.
  final bool external;
}

/// Instala o arquivo baixado conforme o tipo detectado:
/// - Android: APK, APK dividido (.apks/.xapk/.apkm) e ZIP (com APKs ou dados);
/// - Linux: AppImage, executável solto, ZIP/TAR (procura o executável) e DEB (via sistema);
/// - Windows: ZIP portátil, EXE (portátil ou instalador) e MSI.
class InstallService {
  InstallService(this._settings);
  final SettingsService _settings;

  static const markerFile = '.porthub.json';

  Future<Directory> gamesDir() async {
    final custom = _settings.installDir;
    final dir = custom.isNotEmpty ? Directory(custom) : Directory(p.join((await getApplicationSupportDirectory()).path, 'games'));
    await dir.create(recursive: true);
    return dir;
  }

  static String safeId(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  Future<InstallResult> install(Game game, DownloadTask task, List<String> deviceAbis) async {
    final file = File(task.filePath);
    if (!await file.exists()) return const InstallResult.fail('Arquivo baixado não encontrado');
    appLog.i('Install', 'Instalando ${game.name} (${task.kind.label}) a partir de ${task.fileName}');
    try {
      if (Platform.isAndroid) return await _android(game, task, deviceAbis);
      if (Platform.isLinux) return await _linux(game, task);
      if (Platform.isWindows) return await _windows(game, task);
      return const InstallResult.fail('Plataforma não suportada');
    } catch (e, s) {
      appLog.e('Install', 'Falha ao instalar ${game.name}', e, s);
      return InstallResult.fail('$e');
    }
  }

  // ---------------------------------------------------------------------------
  // Android
  // ---------------------------------------------------------------------------

  Future<InstallResult> _android(Game game, DownloadTask task, List<String> abis) async {
    if (!await NativeBridge.canInstallPackages()) {
      await NativeBridge.openInstallPermissionSettings();
      return const InstallResult.fail('Permita "Instalar apps desconhecidos" para o PortHub e tente novamente.');
    }
    switch (task.kind) {
      case AssetKind.apk:
        return _installApks(game, [task.filePath]);
      case AssetKind.splitApk:
      case AssetKind.zip:
        final out = Directory(p.join((await getApplicationSupportDirectory()).path, 'extract', safeId(game.id)));
        if (await out.exists()) await out.delete(recursive: true);
        await _extract(task.filePath, out.path, forceZip: true);
        final apks = await out
            .list(recursive: true)
            .where((e) => e is File && e.path.toLowerCase().endsWith('.apk'))
            .map((e) => e.path)
            .toList();
        if (apks.isEmpty) {
          // ZIP de dados (ex.: assets de um port): fica extraído para o jogo usar.
          final dataDir = Directory(p.join((await gamesDir()).path, safeId(game.id)));
          if (await dataDir.exists()) await dataDir.delete(recursive: true);
          await out.rename(dataDir.path);
          await _writeMarker(dataDir, game, task.version, null);
          return InstallResult.ok('Dados extraídos em ${dataDir.path}', path: dataDir.path);
        }
        final selected = _selectApks(apks, abis);
        final r = await _installApks(game, selected);
        await out.delete(recursive: true);
        return r;
      default:
        return InstallResult.fail('Tipo ${task.kind.label} não suportado no Android');
    }
  }

  /// Split APK (base + split_config.*) → instala todos juntos. Vários APKs
  /// independentes (um por ABI) → escolhe o melhor para o aparelho.
  List<String> _selectApks(List<String> apks, List<String> abis) {
    final names = apks.map((a) => p.basename(a).toLowerCase()).toList();
    final isSplit = names.any((n) => n == 'base.apk' || n.startsWith('split_') || n.contains('config.'));
    if (isSplit) {
      // Remove splits de ABI que não servem para o aparelho.
      return apks.where((a) {
        final arch = AssetDetector.archOf(p.basename(a), kind: AssetKind.apk);
        return arch == null || abis.contains(arch);
      }).toList();
    }
    if (apks.length == 1) return apks;
    String? best;
    var bestIdx = 1 << 20;
    for (final a in apks) {
      final arch = AssetDetector.archOf(p.basename(a), kind: AssetKind.apk);
      final idx = arch == null ? 50 : abis.indexOf(arch);
      if (idx >= 0 && idx < bestIdx) {
        bestIdx = idx;
        best = a;
      }
    }
    return [best ?? apks.first];
  }

  Future<InstallResult> _installApks(Game game, List<String> paths) async {
    final info = await NativeBridge.apkInfo(paths.firstWhere((p0) => p.basename(p0) == 'base.apk', orElse: () => paths.first));
    final error = await NativeBridge.installApks(paths);
    if (error != null) return InstallResult.fail(error);
    final pkg = info?['package'] as String? ?? game.androidPackage;
    return InstallResult.ok('Instalado com sucesso', package: pkg);
  }

  // ---------------------------------------------------------------------------
  // Linux
  // ---------------------------------------------------------------------------

  Future<InstallResult> _linux(Game game, DownloadTask task) async {
    final dir = Directory(p.join((await gamesDir()).path, safeId(game.id)));
    switch (task.kind) {
      case AssetKind.appImage:
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
        final dest = p.join(dir.path, task.fileName);
        await File(task.filePath).copy(dest);
        await _chmodX(dest);
        await _writeMarker(dir, game, task.version, dest);
        return InstallResult.ok('Instalado', path: dir.path, executable: dest);
      case AssetKind.zip:
      case AssetKind.tarball:
        if (await dir.exists()) await dir.delete(recursive: true);
        await _extract(task.filePath, dir.path);
        final exe = await findExecutable(dir, game, windows: false);
        if (exe != null) await _chmodX(exe);
        await _writeMarker(dir, game, task.version, exe);
        return InstallResult.ok(exe == null ? 'Extraído (executável não identificado)' : 'Instalado', path: dir.path, executable: exe);
      case AssetKind.deb:
        await Process.start('xdg-open', [task.filePath], mode: ProcessStartMode.detached);
        return const InstallResult.ok('Pacote .deb aberto no instalador do sistema', external: true);
      default:
        return InstallResult.fail('Tipo ${task.kind.label} não suportado no Linux');
    }
  }

  Future<void> _chmodX(String path) async {
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (e) {
      appLog.w('Install', 'chmod falhou em $path', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Windows
  // ---------------------------------------------------------------------------

  Future<InstallResult> _windows(Game game, DownloadTask task) async {
    final dir = Directory(p.join((await gamesDir()).path, safeId(game.id)));
    final lower = task.fileName.toLowerCase();
    switch (task.kind) {
      case AssetKind.zip:
        if (await dir.exists()) await dir.delete(recursive: true);
        await _extract(task.filePath, dir.path);
        final exe = await findExecutable(dir, game, windows: true);
        await _writeMarker(dir, game, task.version, exe);
        return InstallResult.ok(exe == null ? 'Extraído (executável não identificado)' : 'Instalado', path: dir.path, executable: exe);
      case AssetKind.exe:
        final isInstaller = RegExp(r'(setup|install|installer)').hasMatch(lower);
        if (isInstaller) {
          await Process.start(task.filePath, [], mode: ProcessStartMode.detached);
          return const InstallResult.ok('Instalador iniciado — conclua a instalação na janela que abriu', external: true);
        }
        await dir.create(recursive: true);
        final dest = p.join(dir.path, task.fileName);
        await File(task.filePath).copy(dest);
        await _writeMarker(dir, game, task.version, dest);
        return InstallResult.ok('Instalado (executável portátil)', path: dir.path, executable: dest);
      case AssetKind.msi:
        await Process.start('msiexec', ['/i', task.filePath], mode: ProcessStartMode.detached);
        return const InstallResult.ok('Instalador MSI iniciado', external: true);
      default:
        return InstallResult.fail('Tipo ${task.kind.label} não suportado no Windows');
    }
  }

  // ---------------------------------------------------------------------------
  // Utilitários
  // ---------------------------------------------------------------------------

  /// Extrai ZIP/TAR em um isolate. Pacotes com extensão própria (.apks, .xapk)
  /// são lidos como ZIP.
  Future<void> _extract(String archivePath, String outDir, {bool forceZip = false}) async {
    await Directory(outDir).create(recursive: true);
    await Isolate.run(() async {
      final lower = archivePath.toLowerCase();
      if (forceZip || lower.endsWith('.zip')) {
        final input = InputFileStream(archivePath);
        try {
          final archive = ZipDecoder().decodeStream(input);
          await extractArchiveToDisk(archive, outDir);
        } finally {
          await input.close();
        }
      } else {
        await extractFileToDisk(archivePath, outDir);
      }
    });
    await _flattenSingleFolder(Directory(outDir));
  }

  /// Se o arquivo tinha uma única pasta raiz, sobe o conteúdo um nível.
  Future<void> _flattenSingleFolder(Directory dir) async {
    final children = await dir.list().toList();
    if (children.length != 1 || children.first is! Directory) return;
    final inner = children.first as Directory;
    final tmp = Directory('${dir.path}__tmp');
    await inner.rename(tmp.path);
    await dir.delete(recursive: true);
    await tmp.rename(dir.path);
  }

  static const _windowsIgnore = [
    'unins', 'uninstall', 'setup', 'vc_redist', 'vcredist', 'dxsetup', 'dxwebsetup', 'crashhandler', 'crashpad',
    'crash_reporter', 'updater', 'helper', 'dotnet', 'oalinst', 'directx', 'redist',
  ];

  /// Procura o executável principal do jogo após extrair.
  Future<String?> findExecutable(Directory dir, Game game, {required bool windows}) async {
    final keys = {
      ...game.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
      ...(game.repo ?? '').toLowerCase().split(RegExp(r'[^a-z0-9]+')),
    }.where((k) => k.length >= 3).toSet();

    String? best;
    var bestScore = -1 << 20;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: dir.path);
      final depth = p.split(rel).length - 1;
      if (depth > 4) continue;
      final name = p.basename(e.path).toLowerCase();
      var score = 0;

      if (windows) {
        if (!name.endsWith('.exe')) continue;
        if (_windowsIgnore.any(name.contains)) continue;
      } else {
        if (name.endsWith('.so') || name.contains('.so.')) continue;
        if (name.endsWith('.appimage')) {
          score += 40;
        } else if (name.endsWith('.x86_64') || name.endsWith('.x86')) {
          score += 30;
        } else if (name.endsWith('.sh')) {
          score += 15;
        } else if (await _isElf(e)) {
          score += 25;
        } else {
          continue;
        }
      }
      for (final k in keys) {
        if (name.contains(k)) score += 50;
      }
      score -= depth * 12;
      score += ((await e.length()) / (1024 * 1024)).clamp(0, 30).round(); // executáveis maiores tendem a ser o jogo
      if (score > bestScore) {
        bestScore = score;
        best = e.path;
      }
    }
    return best;
  }

  Future<bool> _isElf(File f) async {
    try {
      final raf = await f.open();
      final head = await raf.read(4);
      await raf.close();
      return head.length == 4 && head[0] == 0x7f && head[1] == 0x45 && head[2] == 0x4c && head[3] == 0x46;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeMarker(Directory dir, Game game, String version, String? exe) async {
    await dir.create(recursive: true);
    await File(p.join(dir.path, markerFile)).writeAsString(jsonEncode({
      'id': game.id,
      'name': game.name,
      'version': version,
      'executable': exe,
      'installed_at': DateTime.now().toIso8601String(),
    }));
  }

  /// Lê os marcadores `.porthub.json` da pasta de jogos (importação no desktop).
  Future<List<Map<String, dynamic>>> scanMarkers() async {
    final dir = await gamesDir();
    final out = <Map<String, dynamic>>[];
    await for (final e in dir.list()) {
      if (e is! Directory) continue;
      final f = File(p.join(e.path, markerFile));
      if (!await f.exists()) continue;
      try {
        out.add({...(jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>(), 'path': e.path});
      } catch (_) {}
    }
    return out;
  }

  Future<void> removeFiles(Game game) async {
    final path = game.installPath;
    if (path == null) return;
    final dir = Directory(path);
    final root = await gamesDir();
    // Segurança: só apaga dentro da pasta de jogos do PortHub.
    if (await dir.exists() && p.isWithin(root.path, dir.path)) await dir.delete(recursive: true);
  }
}
