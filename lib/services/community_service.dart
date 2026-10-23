import 'dart:convert';

import 'package:http/http.dart' as http;

import '../compatibility/hardware_tiers.dart';
import '../core/app_config.dart';
import '../core/logger.dart';
import '../core/models/community_report.dart';
import '../core/models/hardware_profile.dart';
import '../database/cache_dao.dart';
import 'settings_service.dart';

/// PortHub Compatibility Database — cliente da base comunitária de relatos
/// (servidor de referência em /backend). Inspirado no ProtonDB: além dos
/// requisitos declarados, mostra como o jogo roda em aparelhos reais.
class CommunityService {
  CommunityService(this._settings, this._cache, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsService _settings;
  final CacheDao _cache;
  final http.Client _http;

  bool get configured => _settings.communityDbUrl.isNotEmpty;

  Future<List<CommunityReport>> reports(String gameId) async {
    if (!configured) return const [];
    final url = '${_settings.communityDbUrl}/api/reports?game=${Uri.encodeQueryComponent(gameId)}';
    final cached = await _cache.get(url);
    if (_settings.offlineMode || (cached != null && cached.isFresh(const Duration(minutes: 30)))) {
      return cached == null ? const [] : _parse(cached.body);
    }
    try {
      final res = await _http.get(Uri.parse(url), headers: {'User-Agent': AppConfig.userAgent}).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        await _cache.put(url, body);
        return _parse(body);
      }
    } catch (e) {
      appLog.w('Community', 'Base comunitária indisponível', e);
    }
    return cached == null ? const [] : _parse(cached.body);
  }

  List<CommunityReport> _parse(String body) {
    final j = jsonDecode(body);
    final list = j is Map ? (j['reports'] as List? ?? const []) : (j as List);
    return list.map((e) => CommunityReport.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<String?> submit(CommunityReport r) async {
    if (!configured) return 'Configure a URL da PortHub Compatibility Database nas Configurações.';
    try {
      final res = await _http
          .post(
            Uri.parse('${_settings.communityDbUrl}/api/reports'),
            headers: {'Content-Type': 'application/json', 'User-Agent': AppConfig.userAgent},
            body: jsonEncode(r.toJson()),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) return null;
      return 'Servidor respondeu ${res.statusCode}';
    } catch (e) {
      return '$e';
    }
  }

  /// "Hardware semelhante": mesma plataforma e GPU/CPU com desempenho próximo
  /// (±12 pontos na tabela de tiers) ou mesmo SoC/GPU pelo nome.
  static bool isSimilar(CommunityReport r, HardwareProfile hw) {
    if (r.platform != hw.platform) return false;
    final rhw = HardwareProfile(platform: r.platform, cpuName: r.soc, gpuName: r.gpu, ramMb: r.ramMb);
    final sameGpu = r.gpu != null && hw.gpuName != null && r.gpu!.toLowerCase() == hw.gpuName!.toLowerCase();
    final sameSoc = r.soc != null && (r.soc == hw.cpuName || r.soc == hw.socModel);
    if (sameGpu || sameSoc) return true;
    final (rg, _) = HardwareTiers.gpuTier(rhw);
    final (hg, _) = HardwareTiers.gpuTier(hw);
    final (rc, _) = HardwareTiers.cpuTier(rhw);
    final (hc, _) = HardwareTiers.cpuTier(hw);
    return (rg - hg).abs() <= 12 && (rc - hc).abs() <= 12;
  }

  static CommunitySummary summarize(List<CommunityReport> reports, HardwareProfile? hw) {
    if (reports.isEmpty) return CommunitySummary.empty;
    final similar = hw == null ? <CommunityReport>[] : reports.where((r) => isSimilar(r, hw)).toList();
    final base = similar.isNotEmpty ? similar : reports;

    // Classificação dominante: moda, desempatando pela média.
    final counts = <CommunityRating, int>{};
    for (final r in base) {
      counts[r.rating] = (counts[r.rating] ?? 0) + 1;
    }
    final dominant = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final fpsList = base.map((r) => r.fps).whereType<double>().toList();
    final avgFps = fpsList.isEmpty ? null : fpsList.reduce((a, b) => a + b) / fpsList.length;

    final devices = <String, int>{};
    for (final r in base) {
      final key = r.soc ?? r.deviceModel;
      devices[key] = (devices[key] ?? 0) + 1;
    }
    final topDevice = devices.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final issues = <String, int>{};
    for (final r in base) {
      for (final i in r.issues) {
        final k = i.trim();
        if (k.isNotEmpty) issues[k] = (issues[k] ?? 0) + 1;
      }
    }
    final known = (issues.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => e.key).toList();

    final message = similar.isNotEmpty
        ? 'Este jogo foi testado por ${similar.length} usuário${similar.length == 1 ? '' : 's'} com hardware semelhante ao seu. '
            'A maioria relatou desempenho ${dominant.performanceWord}.'
        : '${reports.length} relato${reports.length == 1 ? '' : 's'} da comunidade, nenhum com hardware semelhante ao seu ainda. '
            'A maioria relatou desempenho ${dominant.performanceWord}.';

    return CommunitySummary(
      total: reports.length,
      similarCount: similar.length,
      rating: dominant,
      averageFps: avgFps,
      mostTestedDevice: topDevice,
      knownIssues: known,
      message: message,
    );
  }
}
