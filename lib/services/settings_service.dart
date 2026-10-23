import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../database/settings_dao.dart';

/// Configurações persistentes (tabela `settings`). Cada getter tem um padrão
/// sensato; os setters gravam no banco e notificam a interface.
class SettingsService extends ChangeNotifier {
  SettingsService(this._dao);
  final SettingsDao _dao;
  Map<String, String> _values = {};

  Future<void> load() async {
    _values = await _dao.all();
  }

  String _s(String k, String def) => _values[k] ?? def;
  bool _b(String k, bool def) => _values.containsKey(k) ? _values[k] == '1' : def;
  int _i(String k, int def) => int.tryParse(_values[k] ?? '') ?? def;

  Future<void> _set(String k, String v) async {
    _values[k] = v;
    notifyListeners();
    await _dao.set(k, v);
  }

  // --- Primeira execução -----------------------------------------------------
  bool get firstRunDone => _b('first_run_done', false);
  set firstRunDone(bool v) => _set('first_run_done', v ? '1' : '0');

  // --- GitHub ----------------------------------------------------------------
  /// Token pessoal (opcional). Aumenta o limite de 60 para 5000 req/h e
  /// habilita a leitura de issues fixadas (GraphQL).
  String get githubToken => _s('github_token', '');
  set githubToken(String v) => _set('github_token', v.trim());

  /// URL do backend opcional de cache (ver /backend). Vazio = acesso direto.
  String get cacheProxyUrl => _s('cache_proxy_url', '');
  set cacheProxyUrl(String v) => _set('cache_proxy_url', v.trim().replaceAll(RegExp(r'/+$'), ''));

  // --- Biblioteca ------------------------------------------------------------
  bool get offlineMode => _b('offline_mode', false);
  set offlineMode(bool v) => _set('offline_mode', v ? '1' : '0');

  bool get autoRefresh => _b('auto_refresh', true);
  set autoRefresh(bool v) => _set('auto_refresh', v ? '1' : '0');

  int get refreshIntervalHours => _i('refresh_interval_h', 6);
  set refreshIntervalHours(int v) => _set('refresh_interval_h', '${v.clamp(1, 168)}');

  DateTime? get lastLibraryRefresh {
    final ms = int.tryParse(_values['last_refresh'] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastLibraryRefresh(DateTime? d) => _set('last_refresh', '${d?.millisecondsSinceEpoch ?? ''}');

  bool get includePrereleases => _b('include_prereleases', false);
  set includePrereleases(bool v) => _set('include_prereleases', v ? '1' : '0');

  bool get showIncompatible => _b('show_incompatible', true);
  set showIncompatible(bool v) => _set('show_incompatible', v ? '1' : '0');

  // --- Provedores ------------------------------------------------------------
  bool providerEnabled(String id, {required bool byDefault}) => _b('provider_$id', byDefault);
  Future<void> setProviderEnabled(String id, bool v) => _set('provider_$id', v ? '1' : '0');

  String get communityCatalogUrl => _s('community_catalog_url', AppConfig.defaultCommunityCatalogUrl);
  set communityCatalogUrl(String v) => _set('community_catalog_url', v.trim());

  // --- Comunidade (PortHub Compatibility Database) ---------------------------
  String get communityDbUrl => _s('community_db_url', '');
  set communityDbUrl(String v) => _set('community_db_url', v.trim().replaceAll(RegExp(r'/+$'), ''));

  // --- Downloads -------------------------------------------------------------
  int get maxConcurrentDownloads => _i('max_downloads', 2);
  set maxConcurrentDownloads(int v) => _set('max_downloads', '${v.clamp(1, 6)}');

  bool get verifyChecksums => _b('verify_checksums', true);
  set verifyChecksums(bool v) => _set('verify_checksums', v ? '1' : '0');

  bool get autoInstall => _b('auto_install', true);
  set autoInstall(bool v) => _set('auto_install', v ? '1' : '0');

  bool get deleteAfterInstall => _b('delete_after_install', true);
  set deleteAfterInstall(bool v) => _set('delete_after_install', v ? '1' : '0');

  /// Pasta de jogos no desktop (vazio = padrão dentro do diretório do app).
  String get installDir => _s('install_dir', '');
  set installDir(String v) => _set('install_dir', v.trim());

  // --- Notificações ----------------------------------------------------------
  bool get notifyUpdates => _b('notify_updates', true);
  set notifyUpdates(bool v) => _set('notify_updates', v ? '1' : '0');

  // --- Atualização do próprio PortHub -----------------------------------------
  /// Procura versões novas do PortHub nas releases do repositório do app.
  bool get selfUpdateCheck => _b('self_update_check', true);
  set selfUpdateCheck(bool v) => _set('self_update_check', v ? '1' : '0');

  /// Último build já avisado (para não repetir a notificação).
  int get selfUpdateNotifiedBuild => int.tryParse(_values['self_update_notified'] ?? '') ?? 0;
  set selfUpdateNotifiedBuild(int v) => _set('self_update_notified', '$v');

  // --- IA local (opcional) ---------------------------------------------------
  bool get aiSummaries => _b('ai_summaries', false);
  set aiSummaries(bool v) => _set('ai_summaries', v ? '1' : '0');

  String get ollamaUrl => _s('ollama_url', 'http://localhost:11434');
  set ollamaUrl(String v) => _set('ollama_url', v.trim().replaceAll(RegExp(r'/+$'), ''));

  String get ollamaModel => _s('ollama_model', 'llama3.2');
  set ollamaModel(String v) => _set('ollama_model', v.trim());

  // --- Interface -------------------------------------------------------------
  bool get fullscreen => _b('fullscreen', true);
  set fullscreen(bool v) => _set('fullscreen', v ? '1' : '0');

  bool get reduceMotion => _b('reduce_motion', false);
  set reduceMotion(bool v) => _set('reduce_motion', v ? '1' : '0');

  bool get verboseLogs => _b('verbose_logs', false);
  set verboseLogs(bool v) => _set('verbose_logs', v ? '1' : '0');
}
