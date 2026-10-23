import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/logger.dart';
import '../core/models/release_info.dart';
import '../database/cache_dao.dart';
import '../services/settings_service.dart';
import 'asset_detector.dart';

class GitHubException implements Exception {
  GitHubException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get isRateLimit => statusCode == 403 || statusCode == 429;
  bool get isNotFound => statusCode == 404;
  @override
  String toString() => 'GitHubException($statusCode): $message';
}

class OfflineException implements Exception {
  @override
  String toString() => 'Sem conexão e sem cache disponível';
}

/// Metadados de um repositório.
class GitHubRepo {
  GitHubRepo(Map<String, dynamic> j)
      : fullName = j['full_name'] as String,
        owner = (j['owner'] as Map)['login'] as String,
        name = j['name'] as String,
        description = j['description'] as String? ?? '',
        htmlUrl = j['html_url'] as String,
        ownerAvatar = (j['owner'] as Map)['avatar_url'] as String?,
        stars = j['stargazers_count'] as int? ?? 0,
        language = j['language'] as String?,
        license = (j['license'] as Map?)?['spdx_id'] as String?,
        topics = (j['topics'] as List?)?.cast<String>() ?? const [],
        pushedAt = DateTime.tryParse(j['pushed_at'] as String? ?? ''),
        defaultBranch = j['default_branch'] as String? ?? 'main',
        homepage = j['homepage'] as String?,
        archived = j['archived'] as bool? ?? false;

  final String fullName;
  final String owner;
  final String name;
  final String description;
  final String htmlUrl;
  final String? ownerAvatar;
  final int stars;
  final String? language;
  final String? license;
  final List<String> topics;
  final DateTime? pushedAt;
  final String defaultBranch;
  final String? homepage;
  final bool archived;
}

class ReadmeDoc {
  const ReadmeDoc(this.markdown, this.rawBaseUrl);
  final String markdown;

  /// Base para resolver imagens relativas (raw.githubusercontent.com/.../).
  final String rawBaseUrl;
}

/// Cliente da GitHub REST API (+ GraphQL para issues fixadas).
///
/// Toda resposta passa pelo `http_cache` com ETag:
/// - dentro do TTL → resposta local, sem rede;
/// - fora do TTL → requisição condicional (`If-None-Match`); 304 não gasta rate limit;
/// - offline / rate limit → devolve o cache, mesmo vencido.
class GitHubClient {
  GitHubClient({required this.cache, required this.settings, http.Client? client})
      : _http = client ?? http.Client();

  final CacheDao cache;
  final SettingsService settings;
  final http.Client _http;

  int? rateRemaining;
  DateTime? rateReset;

  static const _notFound = '__porthub_404__';

  /// Sem token e com poucas requisições restantes: etapas opcionais são adiadas.
  bool get budgetLow => settings.githubToken.isEmpty && rateRemaining != null && rateRemaining! < 15;

  /// Sem token, guarda algumas requisições para quando o usuário abrir um jogo:
  /// a sincronização em massa para aqui e o resto é carregado sob demanda.
  bool get syncBudgetSpent => settings.githubToken.isEmpty && rateRemaining != null && rateRemaining! < 8;

  /// Sem requisições restantes até [rateReset].
  bool get rateExhausted =>
      rateRemaining == 0 && rateReset != null && DateTime.now().isBefore(rateReset!);

  String get _base =>
      settings.cacheProxyUrl.isNotEmpty ? '${settings.cacheProxyUrl}/gh' : AppConfig.githubApi;

  Map<String, String> _headers({String accept = 'application/vnd.github+json'}) => {
        'Accept': accept,
        'User-Agent': AppConfig.userAgent,
        'X-GitHub-Api-Version': '2022-11-28',
        if (settings.githubToken.isNotEmpty) 'Authorization': 'Bearer ${settings.githubToken}',
      };

  /// GET com cache. Retorna o corpo como String.
  Future<String> _get(String path, {Duration ttl = AppConfig.repoCacheTtl, String? accept}) async {
    final url = path.startsWith('http') ? path : '$_base$path';
    final cached = await cache.get(url);

    String fromCache(CachedResponse c) {
      if (c.body == _notFound) throw GitHubException('Não encontrado', statusCode: 404);
      return c.body;
    }

    if (settings.offlineMode) {
      if (cached != null) return fromCache(cached);
      throw OfflineException();
    }
    if (cached != null && cached.isFresh(ttl)) return fromCache(cached);

    // Cota esgotada: não adianta chamar a API até o reset.
    if (rateExhausted) {
      if (cached != null) return fromCache(cached);
      throw GitHubException('Limite da API do GitHub esgotado. Configure um token nas Configurações.', statusCode: 403);
    }

    try {
      final headers = _headers(accept: accept ?? 'application/vnd.github+json');
      if (cached?.etag != null) headers['If-None-Match'] = cached!.etag!;
      final res = await _http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 20));
      _readRateLimit(res);

      if (res.statusCode == 304 && cached != null) {
        await cache.touch(url);
        return fromCache(cached);
      }
      if (res.statusCode == 404) {
        // 404 também é cacheado (ex.: repositório sem porthub.yaml) para não gastar rate limit.
        await cache.put(url, _notFound);
        throw GitHubException('Não encontrado', statusCode: 404);
      }
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        await cache.put(url, body, etag: res.headers['etag']);
        return body;
      }
      if (cached != null && (res.statusCode == 403 || res.statusCode == 429 || res.statusCode >= 500)) {
        appLog.w('GitHub', 'HTTP ${res.statusCode} em $path — usando cache');
        return fromCache(cached);
      }
      throw GitHubException(_errorMessage(res), statusCode: res.statusCode);
    } on GitHubException {
      rethrow;
    } catch (e) {
      // Falha de rede: usa cache vencido se existir.
      if (cached != null) {
        appLog.w('GitHub', 'Rede indisponível para $path — usando cache', e);
        return fromCache(cached);
      }
      throw OfflineException();
    }
  }

  void _readRateLimit(http.Response res) {
    final rem = int.tryParse(res.headers['x-ratelimit-remaining'] ?? '');
    final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
    final before = rateRemaining;
    if (rem != null) rateRemaining = rem;
    if (reset != null) rateReset = DateTime.fromMillisecondsSinceEpoch(reset * 1000);
    // Avisa uma vez ao cruzar o limite, não a cada resposta.
    if (rem != null && rem < 5 && (before == null || before >= 5)) {
      appLog.w('GitHub', 'Rate limit quase esgotado ($rem restantes). Configure um token nas Configurações.');
    }
  }

  String _errorMessage(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map)['message'] as String? ?? 'HTTP ${res.statusCode}';
    } catch (_) {
      return 'HTTP ${res.statusCode}';
    }
  }

  // ---------------------------------------------------------------------------

  Future<GitHubRepo> repo(String owner, String repo) async {
    final body = await _get('/repos/$owner/$repo');
    return GitHubRepo((jsonDecode(body) as Map).cast<String, dynamic>());
  }

  /// Releases (mais recentes primeiro), já com assets classificados.
  Future<List<ReleaseInfo>> releases(String owner, String repo, {int perPage = 10, bool prereleases = false}) async {
    final body = await _get('/repos/$owner/$repo/releases?per_page=$perPage');
    final list = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    return list
        .where((r) => r['draft'] != true && (prereleases || r['prerelease'] != true))
        .map((r) => ReleaseInfo(
              tag: r['tag_name'] as String? ?? '',
              name: (r['name'] as String?)?.trim().isNotEmpty == true ? r['name'] as String : r['tag_name'] as String? ?? '',
              body: r['body'] as String? ?? '',
              publishedAt: DateTime.tryParse(r['published_at'] as String? ?? ''),
              prerelease: r['prerelease'] as bool? ?? false,
              htmlUrl: r['html_url'] as String?,
              assets: ((r['assets'] as List?) ?? const [])
                  .map((a) => AssetDetector.fromGitHub((a as Map).cast<String, dynamic>()))
                  .toList(),
            ))
        .toList();
  }

  /// Última release lida pela página pública do GitHub, sem usar a API.
  ///
  /// Plano B para quando a cota anônima (60/h) acaba: `/releases/latest`
  /// redireciona para a tag e `/releases/expanded_assets/<tag>` lista os
  /// arquivos com SHA256, tamanho e data. Não traz o changelog.
  Future<ReleaseInfo?> latestReleaseFromWeb(String owner, String repo) async {
    final key = 'web:releases/$owner/$repo';
    final cached = await cache.get(key);
    if (cached != null && cached.isFresh(AppConfig.repoCacheTtl)) {
      return cached.body.isEmpty ? null : ReleaseInfo.fromJson((jsonDecode(cached.body) as Map).cast<String, dynamic>());
    }
    if (settings.offlineMode) return null;
    try {
      final req = http.Request('GET', Uri.parse('https://github.com/$owner/$repo/releases/latest'))
        ..followRedirects = false
        ..headers['User-Agent'] = AppConfig.userAgent;
      final res = await _http.send(req).timeout(const Duration(seconds: 20));
      await res.stream.drain<void>();
      final location = res.headers['location'] ?? '';
      final tagAt = location.indexOf('/releases/tag/');
      if (tagAt < 0) {
        await cache.put(key, ''); // sem releases
        return null;
      }
      final tag = Uri.decodeComponent(location.substring(tagAt + '/releases/tag/'.length));
      final assetsRes = await _http.get(
        Uri.parse('https://github.com/$owner/$repo/releases/expanded_assets/${Uri.encodeComponent(tag)}'),
        headers: {'User-Agent': AppConfig.userAgent},
      ).timeout(const Duration(seconds: 20));
      if (assetsRes.statusCode != 200) return null;
      final release = parseExpandedAssets(utf8.decode(assetsRes.bodyBytes), owner: owner, repo: repo, tag: tag);
      await cache.put(key, jsonEncode(release.toJson()));
      appLog.i('GitHub', 'Release de $owner/$repo lida pela página (sem cota da API): $tag');
      return release;
    } catch (e) {
      appLog.w('GitHub', 'Página de releases de $owner/$repo indisponível', e);
      if (cached != null && cached.body.isNotEmpty) {
        return ReleaseInfo.fromJson((jsonDecode(cached.body) as Map).cast<String, dynamic>());
      }
      return null;
    }
  }

  static ReleaseInfo parseExpandedAssets(String html, {required String owner, required String repo, required String tag}) {
    final assets = <ReleaseAsset>[];
    DateTime? newest;
    for (final item in html.split('<li ').skip(1)) {
      final link = RegExp('href="(/[^"]+/releases/download/[^"]+)"').firstMatch(item);
      if (link == null) continue; // "Source code" e atestados
      final path = link.group(1)!;
      final name = Uri.decodeComponent(path.substring(path.lastIndexOf('/') + 1));
      final digest = RegExp(r'sha256:[0-9a-f]{64}').firstMatch(item)?.group(0);
      final size = RegExp(r'>\s*([\d.,]+)\s*(Bytes|KB|MB|GB)\s*<').firstMatch(item);
      final date = DateTime.tryParse(RegExp(r'datetime="([^"]+)"').firstMatch(item)?.group(1) ?? '');
      if (date != null && (newest == null || date.isAfter(newest))) newest = date;
      assets.add(AssetDetector.fromGitHub({
        'name': name,
        'browser_download_url': 'https://github.com$path',
        'size': size == null ? 0 : _approxBytes(size.group(1)!, size.group(2)!),
        'digest': ?digest,
      }));
    }
    return ReleaseInfo(
      tag: tag,
      name: tag,
      body: '',
      publishedAt: newest,
      assets: assets,
      htmlUrl: 'https://github.com/$owner/$repo/releases/tag/$tag',
    );
  }

  static int _approxBytes(String number, String unit) {
    final v = double.tryParse(number.replaceAll(',', '')) ?? 0;
    final mult = switch (unit) { 'GB' => 1 << 30, 'MB' => 1 << 20, 'KB' => 1 << 10, _ => 1 };
    return (v * mult).round();
  }

  Future<ReadmeDoc?> readme(String owner, String repo) async {
    try {
      final body = await _get('/repos/$owner/$repo/readme', ttl: AppConfig.readmeCacheTtl);
      final j = (jsonDecode(body) as Map).cast<String, dynamic>();
      final content = utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')), allowMalformed: true);
      final downloadUrl = j['download_url'] as String? ?? '';
      final base = downloadUrl.isEmpty ? '' : downloadUrl.substring(0, downloadUrl.lastIndexOf('/') + 1);
      return ReadmeDoc(content, base);
    } on GitHubException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// Lê um arquivo de texto do repositório (ex.: `porthub.yaml`). Null se não existir.
  Future<String?> fileContent(String owner, String repo, String path) async {
    try {
      final body = await _get('/repos/$owner/$repo/contents/$path', ttl: AppConfig.readmeCacheTtl);
      final j = jsonDecode(body);
      if (j is! Map || j['content'] == null) return null;
      return utf8.decode(base64.decode((j['content'] as String).replaceAll('\n', '')), allowMalformed: true);
    } on GitHubException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// Baixa um texto qualquer (checksums, catálogo) com cache.
  Future<String> rawText(String url, {Duration ttl = const Duration(hours: 1)}) =>
      _get(url, ttl: ttl, accept: '*/*');

  /// Busca de repositórios (`/search/repositories`).
  Future<List<GitHubRepo>> searchRepos(String query, {int perPage = 30, String sort = 'stars'}) async {
    final q = Uri.encodeQueryComponent(query);
    final body = await _get('/search/repositories?q=$q&sort=$sort&per_page=$perPage');
    final items = ((jsonDecode(body) as Map)['items'] as List?) ?? const [];
    return items.map((e) => GitHubRepo((e as Map).cast<String, dynamic>())).toList();
  }

  /// Issues fixadas. A REST API não expõe "pinned issues"; usamos GraphQL,
  /// que exige token. Sem token, retorna lista vazia.
  Future<List<PinnedIssue>> pinnedIssues(String owner, String repo) async {
    if (settings.githubToken.isEmpty || settings.offlineMode) return const [];
    final cacheKey = 'graphql:pinned:$owner/$repo';
    final cached = await cache.get(cacheKey);
    if (cached != null && cached.isFresh(AppConfig.readmeCacheTtl)) return _parsePinned(cached.body);
    try {
      final res = await _http
          .post(
            Uri.parse(AppConfig.githubGraphQL),
            headers: {..._headers(), 'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': 'query(\$o:String!,\$r:String!){repository(owner:\$o,name:\$r){'
                  'pinnedIssues(first:3){nodes{issue{title url body}}}}}',
              'variables': {'o': owner, 'r': repo},
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return cached == null ? const [] : _parsePinned(cached.body);
      final body = utf8.decode(res.bodyBytes);
      await cache.put(cacheKey, body);
      return _parsePinned(body);
    } catch (e) {
      appLog.w('GitHub', 'Falha ao buscar issues fixadas de $owner/$repo', e);
      return cached == null ? const [] : _parsePinned(cached.body);
    }
  }

  List<PinnedIssue> _parsePinned(String body) {
    try {
      final nodes = (((jsonDecode(body) as Map)['data'] as Map?)?['repository'] as Map?)?['pinnedIssues']?['nodes']
              as List? ??
          const [];
      return nodes.map((n) {
        final i = ((n as Map)['issue'] as Map).cast<String, dynamic>();
        return PinnedIssue(title: i['title'] as String? ?? '', url: i['url'] as String? ?? '', body: i['body'] as String? ?? '');
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
