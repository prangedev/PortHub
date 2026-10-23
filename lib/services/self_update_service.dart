import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_config.dart';
import '../core/logger.dart';
import '../downloads/checksum.dart';
import 'native_bridge.dart';
import 'notification_service.dart';
import 'settings_service.dart';

enum SelfUpdateState { disabled, idle, checking, upToDate, available, downloading, installing, error }

class SelfUpdateRelease {
  const SelfUpdateRelease({
    required this.tag,
    required this.build,
    required this.notes,
    required this.assetApiUrl,
    required this.assetName,
    required this.size,
    this.sha256,
    this.publishedAt,
  });
  final String tag;
  final int build;
  final String notes;
  final String assetApiUrl;
  final String assetName;
  final int size;
  final String? sha256;
  final DateTime? publishedAt;
}

/// Mantém o próprio PortHub atualizado a partir das releases do repositório do
/// app (privado ou público), publicadas pelo GitHub Actions a cada push.
///
/// Repositório privado: os arquivos só baixam com um token que leia o repo
/// (o mesmo campo "Token pessoal do GitHub" das Configurações).
class SelfUpdateService extends ChangeNotifier with WidgetsBindingObserver {
  SelfUpdateService(this.settings, this.notifications, {http.Client? client}) : _http = client ?? http.Client();

  final SettingsService settings;
  final NotificationService notifications;
  final http.Client _http;

  static const checkInterval = Duration(hours: 6);

  SelfUpdateState status = SelfUpdateState.idle;
  SelfUpdateRelease? latest;
  double progress = 0;
  String? error;
  DateTime? lastCheck;
  Timer? _timer;

  bool get enabled => AppConfig.updateRepo.isNotEmpty && Platform.isAndroid;
  bool get updateAvailable => latest != null && latest!.build > AppConfig.buildNumber;
  /// Mesmo formato das tags publicadas pelo GitHub Actions (`v1.0.<build>`).
  String get currentLabel => AppConfig.buildNumber == 0 ? 'build local' : 'v1.0.${AppConfig.buildNumber}';

  void start() {
    if (!enabled) {
      status = SelfUpdateState.disabled;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(checkInterval, (_) => check());
    unawaited(check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar para o app (ex.: depois de dias em segundo plano), confere de novo.
    if (state == AppLifecycleState.resumed &&
        (lastCheck == null || DateTime.now().difference(lastCheck!) > const Duration(hours: 1))) {
      unawaited(check());
    }
  }

  Map<String, String> _headers({String accept = 'application/vnd.github+json'}) => {
        'Accept': accept,
        'User-Agent': AppConfig.userAgent,
        'X-GitHub-Api-Version': '2022-11-28',
        if (settings.githubToken.isNotEmpty) 'Authorization': 'Bearer ${settings.githubToken}',
      };

  /// "v1.0.42" / "build-42" → 42.
  static int buildFromTag(String tag) => int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;

  Future<void> check({bool manual = false}) async {
    if (!enabled || status == SelfUpdateState.downloading || status == SelfUpdateState.installing) return;
    if (!manual && !settings.selfUpdateCheck) return;
    status = SelfUpdateState.checking;
    error = null;
    notifyListeners();
    try {
      final res = await _http
          .get(Uri.parse('${AppConfig.githubApi}/repos/${AppConfig.updateRepo}/releases/latest'), headers: _headers())
          .timeout(const Duration(seconds: 20));
      lastCheck = DateTime.now();
      if (res.statusCode == 404) {
        throw Exception(settings.githubToken.isEmpty
            ? 'Repositório privado: configure um token com acesso a ${AppConfig.updateRepo}.'
            : 'Nenhuma release encontrada (ou o token não tem acesso a ${AppConfig.updateRepo}).');
      }
      if (res.statusCode != 200) throw Exception('GitHub respondeu HTTP ${res.statusCode}');
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final assets = ((j['assets'] as List?) ?? const []).cast<Map>();
      final apk = assets.firstWhere((a) => '${a['name']}'.toLowerCase().endsWith('.apk'), orElse: () => const {});
      if (apk.isEmpty) throw Exception('A release ${j['tag_name']} não tem APK.');
      final digest = apk['digest'] as String?;
      latest = SelfUpdateRelease(
        tag: '${j['tag_name']}',
        build: buildFromTag('${j['tag_name']}'),
        notes: j['body'] as String? ?? '',
        assetApiUrl: '${apk['url']}',
        assetName: '${apk['name']}',
        size: (apk['size'] as num?)?.toInt() ?? 0,
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7) : null,
        publishedAt: DateTime.tryParse('${j['published_at']}'),
      );
      status = updateAvailable ? SelfUpdateState.available : SelfUpdateState.upToDate;
      if (updateAvailable && settings.selfUpdateNotifiedBuild < latest!.build) {
        settings.selfUpdateNotifiedBuild = latest!.build;
        notifications.push('Nova versão do PortHub', '${latest!.tag} disponível — Configurações › Atualizações do PortHub.',
            icon: Icons.system_update_rounded, system: true);
      }
      appLog.i('Atualização', 'Atual: $currentLabel · última: ${latest!.tag}');
    } catch (e) {
      status = SelfUpdateState.error;
      error = '$e'.replaceFirst('Exception: ', '');
      appLog.w('Atualização', 'Falha ao verificar', e);
    }
    notifyListeners();
  }

  /// Baixa o APK da release (com o token, se o repositório for privado),
  /// confere o SHA256 e abre o instalador do Android por cima da versão atual.
  Future<String?> downloadAndInstall() async {
    final rel = latest;
    if (rel == null || !enabled) return 'Nenhuma atualização disponível.';
    if (!await NativeBridge.canInstallPackages()) {
      await NativeBridge.openInstallPermissionSettings();
      return 'Permita "Instalar apps desconhecidos" para o PortHub e toque em Atualizar de novo.';
    }
    status = SelfUpdateState.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'self_update'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, rel.assetName));
    try {
      // A API devolve 302 para um link temporário assinado; o token não pode
      // seguir para lá, então o redirecionamento é feito à mão.
      final req = http.Request('GET', Uri.parse(rel.assetApiUrl))
        ..followRedirects = false
        ..headers.addAll(_headers(accept: 'application/octet-stream'));
      var res = await _http.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode == 301 || res.statusCode == 302 || res.statusCode == 307) {
        final location = res.headers['location']!;
        await res.stream.drain<void>();
        res = await _http.send(http.Request('GET', Uri.parse(location))).timeout(const Duration(seconds: 30));
      }
      if (res.statusCode != 200) throw Exception('Download falhou (HTTP ${res.statusCode})');
      final total = res.contentLength ?? rel.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      final got = await Checksum.hashFile(file.path, 'sha256');
      if (rel.sha256 != null && got != rel.sha256) {
        await file.delete();
        throw Exception('Arquivo corrompido (SHA256 não confere). Tente de novo.');
      }
      status = SelfUpdateState.installing;
      notifyListeners();
      appLog.i('Atualização', 'Instalando ${rel.tag} (${rel.assetName}, sha256 ${got.substring(0, 12)}…)');
      final err = await NativeBridge.installApks([file.path]);
      if (err != null) throw Exception(err);
      // Se a instalação seguir, o Android reinicia o app na versão nova.
      status = SelfUpdateState.available;
      notifyListeners();
      return null;
    } catch (e) {
      status = SelfUpdateState.error;
      error = '$e'.replaceFirst('Exception: ', '');
      appLog.w('Atualização', 'Falha ao atualizar', e);
      notifyListeners();
      return error;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
