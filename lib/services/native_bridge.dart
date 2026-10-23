import 'package:flutter/services.dart';

import '../core/logger.dart';

/// Ponte com o código nativo Android (MainActivity.kt). No desktop todos os
/// métodos retornam valores neutros.
class NativeBridge {
  static const _ch = MethodChannel('porthub/native');

  static Future<Map<String, dynamic>> hardwareInfo() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('getHardwareInfo');
    return r ?? {};
  }

  /// Instala um ou mais APKs (APK dividido = vários) via PackageInstaller.
  /// Retorna `null` em caso de sucesso ou a mensagem de erro.
  static Future<String?> installApks(List<String> paths) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('installApks', {'paths': paths});
      if (r?['success'] == true) return null;
      return r?['message'] as String? ?? 'Instalação cancelada';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  static Future<bool> canInstallPackages() async =>
      await _ch.invokeMethod<bool>('canRequestPackageInstalls') ?? false;

  static Future<void> openInstallPermissionSettings() => _ch.invokeMethod('openInstallPermissionSettings');

  /// Lê package name / versão de um APK baixado.
  static Future<Map<String, dynamic>?> apkInfo(String path) =>
      _ch.invokeMapMethod<String, dynamic>('getApkInfo', {'path': path});

  static Future<String?> installedVersion(String package) =>
      _ch.invokeMethod<String>('getInstalledVersion', {'package': package});

  static Future<bool> launchPackage(String package) async =>
      await _ch.invokeMethod<bool>('launchPackage', {'package': package}) ?? false;

  static Future<void> uninstallPackage(String package) => _ch.invokeMethod('uninstallPackage', {'package': package});

  /// Apps instalados pelo usuário: [{package, label, version}].
  static Future<List<Map<String, dynamic>>> installedPackages() async {
    final r = await _ch.invokeListMethod<Map>('listInstalledPackages');
    return r?.map((e) => e.cast<String, dynamic>()).toList() ?? const [];
  }

  /// Serviço em primeiro plano que mantém os downloads ativos com o app em segundo plano.
  static Future<void> setDownloadService(bool running, {String text = ''}) async {
    try {
      await _ch.invokeMethod('downloadService', {'running': running, 'text': text});
    } catch (e) {
      appLog.w('Native', 'downloadService falhou', e);
    }
  }

  // --- Arquivos de emuladores (Storage Access Framework) ----------------------

  /// Seletor do sistema (vários arquivos). Retorna [{uri, name, size}].
  static Future<List<Map<String, dynamic>>> pickRomFiles() async {
    final r = await _ch.invokeListMethod<Map>('pickRomFiles');
    return r?.map((e) => e.cast<String, dynamic>()).toList() ?? const [];
  }

  /// Escolhe uma pasta e lista (até 4 níveis) os arquivos com [extensions].
  static Future<List<Map<String, dynamic>>> pickRomFolder(List<String> extensions) async {
    final r = await _ch.invokeListMethod<Map>('pickRomFolder', {'extensions': extensions});
    return r?.map((e) => e.cast<String, dynamic>()).toList() ?? const [];
  }

  static Future<Uint8List> readUri(String uri, int offset, int length) async =>
      await _ch.invokeMethod<Uint8List>('readUri', {'uri': uri, 'offset': offset, 'length': length}) ??
      Uint8List(0);

  static Future<int?> uriSize(String uri) => _ch.invokeMethod<int>('uriSize', {'uri': uri});

  static Future<bool> canReadUri(String uri) async =>
      await _ch.invokeMethod<bool>('canReadUri', {'uri': uri}) ?? false;

  static Future<void> releaseUri(String uri) => _ch.invokeMethod('releaseUri', {'uri': uri});

  /// Abre [uri] direto no emulador. Retorna `null` ou a mensagem de erro.
  static Future<String?> launchEmulatorGame({
    required String package,
    required String activity,
    required String uri,
    String? action,
  }) =>
      _ch.invokeMethod<String>('launchEmulatorGame', {
        'package': package,
        'activity': activity,
        'uri': uri,
        'action': ?action,
      });

  static Future<void> notify(String title, String body, {int id = 1}) async {
    try {
      await _ch.invokeMethod('notify', {'title': title, 'body': body, 'id': id});
    } catch (e) {
      appLog.w('Native', 'notify falhou', e);
    }
  }

  static Future<void> requestNotificationPermission() async {
    try {
      await _ch.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }
}
