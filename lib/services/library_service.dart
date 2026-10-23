import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;

import '../compatibility/compatibility_engine.dart';
import '../core/app_config.dart';
import '../core/logger.dart';
import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../core/models/game_requirements.dart';
import '../core/models/release_info.dart';
import '../core/platform_info.dart';
import '../core/version_compare.dart';
import '../database/game_dao.dart';
import '../github/asset_detector.dart';
import '../github/github_client.dart';
import '../github/manifest_parser.dart';
import '../github/readme_parser.dart';
import 'artwork_service.dart';
import 'hardware/hardware_service.dart';
import 'notification_service.dart';
import 'providers/game_source_provider.dart';
import 'settings_service.dart';

/// Campo usado na pesquisa (estilo Steam).
enum SearchField { all, name, developer, category, engine, tag }

/// Serviço central da biblioteca: sincroniza provedores, enriquece com dados do
/// GitHub, calcula compatibilidade, detecta atualizações e expõe as seções da
/// tela inicial.
class LibraryService extends ChangeNotifier {
  LibraryService({
    required this.dao,
    required this.gh,
    required this.settings,
    required this.hardware,
    required this.providers,
    required this.notifications,
    this.artwork,
  }) {
    hardware.addListener(_onHardwareChanged);
  }

  final GameDao dao;
  final GitHubClient gh;
  final SettingsService settings;
  final HardwareService hardware;
  final List<GameSourceProvider> providers;
  final NotificationService notifications;

  /// Capas e capturas do jogo original para ports sem imagens (opcional nos testes).
  final ArtworkService? artwork;
  final _engine = const CompatibilityEngine();

  final Map<String, Game> _games = {};
  bool refreshing = false;
  String refreshStatus = '';
  double refreshProgress = 0;
  String? lastError;
  Timer? _autoTimer;
  DateTime? _lastHwScan;

  /// Jogos do catálogo, sem os emuladores.
  ///
  /// Repositórios achados pelos tópicos sem nenhuma release (bibliotecas,
  /// ferramentas, projetos parados) não têm o que instalar e ficam de fora.
  Iterable<Game> get _playable => _games.values.where((g) =>
      !g.isEmulator && (g.installed || g.releases.isNotEmpty || g.provider == 'community' || g.provider == 'portmaster'));

  List<Game> get emulators => _games.values.where((g) => g.isEmulator).toList();

  List<Game> get games {
    final list = _playable.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!settings.showIncompatible) {
      list.removeWhere((g) => g.compatibility.level == CompatLevel.incompatible && !g.installed);
    }
    return list;
  }

  Game? byId(String id) => _games[id];
  bool get isEmpty => _games.isEmpty;

  bool isProviderEnabled(GameSourceProvider p) => settings.providerEnabled(p.id, byDefault: p.enabledByDefault);

  // ---------------------------------------------------------------------------
  // Carga, sincronização e enriquecimento
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    final all = await dao.all();
    _games
      ..clear()
      ..addEntries(all.map((g) => MapEntry(g.id, g)));
    for (final g in _games.values) {
      _evaluate(g);
    }
    appLog.i('Library', '${_games.length} jogos carregados do banco');
    notifyListeners();
  }

  void startAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (_refreshDue) refresh();
    });
    if (_refreshDue || _games.isEmpty) refresh();
  }

  bool get _refreshDue {
    if (!settings.autoRefresh || settings.offlineMode) return false;
    final last = settings.lastLibraryRefresh;
    return last == null || DateTime.now().difference(last) > Duration(hours: settings.refreshIntervalHours);
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    lastError = null;
    refreshProgress = 0;
    _status('Consultando provedores…');
    try {
      // 1. Coleta das entradas de todos os provedores habilitados.
      final entries = <String, CatalogEntry>{};
      for (final p in providers.where(isProviderEnabled)) {
        _status('Lendo ${p.displayName}…');
        try {
          final list = await p.fetch();
          for (final e in list) {
            entries.putIfAbsent(e.id, () => e); // o primeiro provedor (mais curado) vence
          }
          appLog.i('Library', '${p.displayName}: ${list.length} entradas');
        } catch (e) {
          appLog.w('Library', 'Provedor ${p.displayName} falhou', e);
          lastError = '${p.displayName}: $e';
        }
      }

      // 2. Enriquecimento (GitHub) com concorrência limitada. Sem token a cota
      // não cobre tudo: instalados e emuladores vão primeiro, depois o catálogo curado.
      int priority(CatalogEntry e) {
        if (_games[e.id]?.installed ?? false) return 0;
        if (e.categories.contains('Emulador')) return 1;
        return e.provider == 'community' ? 2 : 3;
      }

      final list = entries.values.toList()..sort((a, b) => priority(a).compareTo(priority(b)));
      var done = 0;
      var skipped = 0;
      final previousUpdates = _games.values.where((g) => g.updateAvailable).map((g) => g.id).toSet();
      await _pool(list, AppConfig.githubConcurrency, (entry) async {
        final old = _games[entry.id];
        if (gh.syncBudgetSpent && entry.hasGitHub) {
          // Sem cota para todos: mantém o que já existe, lê a release pela página
          // pública e completa o resto (README etc.) ao abrir o jogo.
          if (old == null || old.releases.isEmpty) {
            final minimal = await _fromEntryWithWebRelease(entry);
            if (old != null) minimal.adoptUserState(old);
            await _applyArtwork(minimal);
            _evaluate(minimal);
            _games[entry.id] = minimal;
          }
          skipped++;
          done++;
          refreshProgress = done / list.length;
          return;
        }
        try {
          final fresh = await _enrich(entry, old);
          if (old != null) fresh.adoptUserState(old);
          await _applyArtwork(fresh);
          _evaluate(fresh);
          _games[entry.id] = fresh;
        } catch (e) {
          appLog.w('Library', 'Falha ao sincronizar ${entry.id}', e);
          if (old == null) {
            final minimal = await _fromEntryWithWebRelease(entry);
            await _applyArtwork(minimal);
            _evaluate(minimal);
            _games[entry.id] = minimal;
          }
        }
        done++;
        refreshProgress = done / list.length;
        _status('Sincronizando ${entry.name ?? entry.repo ?? entry.id} ($done/${list.length})');
      });

      // 3. Remove jogos que sumiram dos provedores (exceto instalados/favoritos).
      _games.removeWhere((id, g) =>
          !entries.containsKey(id) && !g.installed && !g.favorite && !g.wishlist && entries.isNotEmpty);

      await dao.upsertAll(_games.values);
      // Com jogos pulados, a próxima abertura tenta de novo (respostas 304 não gastam cota).
      if (skipped == 0) settings.lastLibraryRefresh = DateTime.now();
      _notifyNewUpdates(previousUpdates);
      appLog.i('Library', 'Sincronização concluída: ${_games.length} jogos');
      if (skipped > 0) {
        appLog.w('Library', '$skipped jogos ficaram para depois (limite da API sem token); '
            'serão completados ao abrir cada um ou na próxima sincronização.');
      }
    } catch (e, s) {
      lastError = '$e';
      appLog.e('Library', 'Sincronização falhou', e, s);
    } finally {
      refreshing = false;
      refreshStatus = '';
      notifyListeners();
    }
  }

  void _status(String s) {
    refreshStatus = s;
    notifyListeners();
  }

  static Future<void> _pool<T>(List<T> items, int workers, Future<void> Function(T) task) async {
    var index = 0;
    Future<void> worker() async {
      while (index < items.length) {
        final item = items[index++];
        await task(item);
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Game _fromEntryOnly(CatalogEntry e) => Game(
        id: e.id,
        name: e.name ?? e.repo ?? e.id,
        provider: e.provider,
        description: e.description ?? '',
        author: e.author ?? e.owner ?? '',
        githubUrl: e.hasGitHub ? 'https://github.com/${e.owner}/${e.repo}' : (e.homepage ?? ''),
        owner: e.owner,
        repo: e.repo,
        categories: e.categories,
        engine: e.engine,
        tags: e.tags,
        coverUrl: e.cover,
        bannerUrl: e.banner,
        iconUrl: e.icon ?? (e.owner != null ? 'https://github.com/${e.owner}.png?size=128' : null),
        gallery: e.gallery,
        requirements: e.requirements ?? const GameRequirements(),
        releases: e.directRelease == null ? const [] : [e.directRelease!],
        version: e.directRelease?.tag,
        lastUpdate: e.directRelease?.publishedAt,
        androidPackage: e.androidPackage,
        origin: e.origin,
        gameDataNote: e.gameDataNote,
      );

  /// Dados do catálogo + última release lida pela página do GitHub (sem API).
  Future<Game> _fromEntryWithWebRelease(CatalogEntry e) async {
    final g = _fromEntryOnly(e);
    if (!e.hasGitHub || g.releases.isNotEmpty) return g;
    final rel = await gh.latestReleaseFromWeb(e.owner!, e.repo!);
    if (rel != null) {
      g
        ..releases = [rel]
        ..version = rel.tag
        ..lastUpdate = rel.publishedAt;
    }
    return g;
  }

  /// Busca no GitHub: repositório, releases, README, porthub.yaml e issues fixadas.
  /// Sem token, etapas opcionais são adiadas quando o rate limit está baixo
  /// (o README é carregado depois, ao abrir o jogo).
  Future<Game> _enrich(CatalogEntry e, Game? old) async {
    if (!e.hasGitHub) return _fromEntryOnly(e);
    final o = e.owner!;
    final r = e.repo!;

    final repo = e.prefetchedRepo ?? await gh.repo(o, r);
    final pre = e.prereleases || settings.includePrereleases;
    var releases = await gh.releases(o, r, prereleases: pre);
    if (releases.isEmpty && !pre) releases = await gh.releases(o, r, prereleases: true);

    // Sem token, o README fica para quando o jogo for aberto se a cota estiver curta.
    ReadmeDoc? readme;
    if (settings.githubToken.isNotEmpty || (gh.rateRemaining ?? 60) > 30) {
      readme = await gh.readme(o, r).catchError((Object err) {
        appLog.d('Library', 'README de $o/$r indisponível: $err');
        return null;
      });
    }

    PortHubManifest? manifest;
    if (settings.githubToken.isNotEmpty) {
      final text = await gh.fileContent(o, r, PortHubManifest.fileNames.first).catchError((Object _) => null);
      if (text != null) manifest = PortHubManifest.parse(text);
    }

    final pinned = await gh.pinnedIssues(o, r);
    return _buildGame(e, repo, releases, readme, manifest, pinned, old);
  }

  Game _buildGame(CatalogEntry e, GitHubRepo repo, List<ReleaseInfo> releases, ReadmeDoc? readme,
      PortHubManifest? manifest, List<PinnedIssue> pinned, Game? old) {
    final md = readme?.markdown ?? old?.readme ?? '';
    final images = readme != null ? ReadmeParser.images(md, readme.rawBaseUrl) : (old?.gallery ?? const <String>[]);
    final reqs = (manifest?.requirements ?? const GameRequirements())
        .mergeWith(e.requirements)
        .mergeWith(md.isEmpty ? null : ReadmeParser.requirements(md));

    final categories = <String>{...?manifest?.categories, ...e.categories};
    if (categories.isEmpty) categories.addAll(ReadmeParser.categories(repo.topics, '${repo.description} ${ReadmeParser.shortDescription(md)}'));

    final latest = releases.isEmpty ? null : releases.first;

    return Game(
      id: e.id,
      name: manifest?.name ?? e.name ?? _prettyName(repo.name),
      provider: e.provider,
      description: manifest?.description ??
          e.description ??
          (repo.description.isNotEmpty ? repo.description : ReadmeParser.shortDescription(md)),
      readme: md.isEmpty ? null : md,
      author: e.author ?? repo.owner,
      githubUrl: repo.htmlUrl,
      owner: repo.owner,
      repo: repo.name,
      version: latest?.tag,
      categories: categories.toList(),
      engine: manifest?.engine ?? e.engine ?? ReadmeParser.engine(repo.topics, md, repo.language),
      coverUrl: manifest?.cover ?? e.cover ?? (images.isNotEmpty ? images.first : null),
      bannerUrl: manifest?.banner ?? e.banner ?? (images.length > 1 ? images[1] : null),
      iconUrl: manifest?.icon ?? e.icon ?? repo.ownerAvatar,
      gallery: [...e.gallery, ...images],
      tags: <String>{
        ...e.tags,
        ...?manifest?.tags,
        ...ReadmeParser.tags(repo.topics, md, openSource: repo.license != null),
      }.toList(),
      language: repo.language,
      license: repo.license,
      stars: repo.stars,
      lastUpdate: latest?.publishedAt ?? repo.pushedAt,
      requirements: reqs,
      releases: releases,
      pinnedIssues: pinned,
      androidPackage: manifest?.androidPackage ?? e.androidPackage,
      origin: e.origin,
      gameDataNote: e.gameDataNote,
    );
  }

  static String _prettyName(String repo) => repo
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// Carrega README/requisitos sob demanda ao abrir o jogo (quando adiados).
  Future<void> ensureDetails(Game g) async {
    if (g.owner == null || settings.offlineMode) return;
    if (g.releases.isEmpty) await _loadReleases(g);
    if (g.readme != null) return;
    try {
      final readme = await gh.readme(g.owner!, g.repo!);
      if (readme == null) return;
      final images = ReadmeParser.images(readme.markdown, readme.rawBaseUrl);
      g
        ..readme = readme.markdown
        ..gallery = {...g.gallery, ...images}.toList()
        ..requirements = g.requirements.mergeWith(ReadmeParser.requirements(readme.markdown));
      g.coverUrl ??= images.isNotEmpty ? images.first : null;
      if (g.description.isEmpty) g.description = ReadmeParser.shortDescription(readme.markdown);
      _evaluate(g);
      await dao.upsert(g);
      notifyListeners();
    } catch (e) {
      appLog.w('Library', 'Não foi possível carregar detalhes de ${g.name}', e);
    }
  }

  /// Completa capa, banner e galeria com a arte do jogo original.
  ///
  /// Quando o catálogo diz qual é o jogo original, a boxart vence a imagem do
  /// README (que muitas vezes é um logo) — a do README vai para a galeria. Para
  /// ports descobertos automaticamente, só preenche o que estiver faltando.
  Future<void> _applyArtwork(Game g) async {
    final art = artwork;
    if (art == null || settings.offlineMode) return;
    final origin = g.origin;
    if (origin == null && g.coverUrl != null && g.bannerUrl != null) return;
    final title = origin?.title ?? ArtworkService.titleFromRepoName(g.repo ?? g.name);
    if (title.trim().length < 3) return;
    try {
      final r = await art.lookup(ArtQuery(
        title: title,
        systems: origin?.systems ?? const [],
        wikipedia: origin?.wikipedia,
        steamAppId: origin?.steamAppId,
      ));
      if (r.isEmpty) return;
      final own = [?g.coverUrl, ?g.bannerUrl];
      if (r.cover != null && (origin != null || g.coverUrl == null)) g.coverUrl = r.cover;
      if (r.banner != null && (origin != null || g.bannerUrl == null)) g.bannerUrl = r.banner;
      g.gallery = <String>{...r.screenshots, ...own, ...g.gallery}
          .where((u) => u != g.coverUrl)
          .toList();
      g.artSource = r.source;
    } catch (e) {
      appLog.d('Library', 'Sem arte para ${g.name}: $e');
    }
  }

  /// Releases de jogos que a sincronização pulou por falta de cota.
  Future<void> _loadReleases(Game g) async {
    try {
      var releases = <ReleaseInfo>[];
      if (gh.rateExhausted) {
        final rel = await gh.latestReleaseFromWeb(g.owner!, g.repo!);
        if (rel != null) releases = [rel];
      } else {
        final pre = settings.includePrereleases;
        releases = await gh.releases(g.owner!, g.repo!, prereleases: pre);
        if (releases.isEmpty && !pre) releases = await gh.releases(g.owner!, g.repo!, prereleases: true);
      }
      if (releases.isEmpty) return;
      g
        ..releases = releases
        ..version = releases.first.tag
        ..lastUpdate = releases.first.publishedAt ?? g.lastUpdate;
      _evaluate(g);
      await dao.upsert(g);
      notifyListeners();
    } catch (e) {
      appLog.w('Library', 'Não foi possível carregar releases de ${g.name}', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Compatibilidade e atualizações
  // ---------------------------------------------------------------------------

  void _onHardwareChanged() {
    final scannedAt = hardware.profile?.scannedAt;
    if (scannedAt == null || scannedAt == _lastHwScan) return;
    _lastHwScan = scannedAt;
    for (final g in _games.values) {
      _evaluate(g);
    }
    dao.upsertAll(_games.values);
    notifyListeners();
  }

  void _evaluate(Game g) {
    final hw = hardware.profile;
    final assets = g.latestRelease?.assets ?? const <ReleaseAsset>[];
    final archs = hw?.abis.isNotEmpty == true ? hw!.abis : [currentProcessArch()];
    g.bestAsset = AssetDetector.pickBest(assets, hostPlatform, archs,
        projectText: '${g.name} ${g.repo ?? ''} ${g.description} ${g.tags.join(' ')} ${g.categories.join(' ')}');
    g.size = g.bestAsset?.size ?? (assets.isEmpty ? null : assets.map((a) => a.size).reduce((a, b) => a > b ? a : b));
    if (hw != null) {
      g.compatibility = _engine.evaluate(req: g.requirements, hw: hw, assets: assets, bestAsset: g.bestAsset);
    }
    g.updateAvailable = g.installed &&
        isNewerVersion(g.version, g.installedVersion, publishedAt: g.latestRelease?.publishedAt, installedAt: g.installedAt);
  }

  void _notifyNewUpdates(Set<String> before) {
    final fresh = _games.values.where((g) => g.updateAvailable && !before.contains(g.id)).toList();
    if (fresh.isEmpty || !settings.notifyUpdates) return;
    for (final g in fresh) {
      notifications.push('Atualização disponível', '${g.name} ${g.version ?? ''} está disponível (instalado: ${g.installedVersion ?? '?'}).',
          icon: Icons.system_update_alt_rounded, gameId: g.id, system: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Estado do usuário
  // ---------------------------------------------------------------------------

  Future<void> save(Game g) async {
    _evaluate(g);
    await dao.upsert(g);
    notifyListeners();
  }

  Future<void> toggleFavorite(Game g) {
    g.favorite = !g.favorite;
    return save(g);
  }

  Future<void> toggleWishlist(Game g) {
    g.wishlist = !g.wishlist;
    return save(g);
  }

  Future<void> markInstalled(Game g, {required String version, String? path, String? executable, String? package}) {
    g
      ..installed = true
      ..installedVersion = version
      ..installedAt = DateTime.now()
      ..installPath = path ?? g.installPath
      ..executablePath = executable ?? g.executablePath
      ..androidPackage = package ?? g.androidPackage;
    return save(g);
  }

  Future<void> markUninstalled(Game g) {
    g
      ..installed = false
      ..installedVersion = null
      ..installedAt = null
      ..installPath = null
      ..executablePath = null;
    return save(g);
  }

  Future<void> recordPlay(Game g, Duration played) {
    g
      ..lastPlayed = DateTime.now()
      ..sessions += 1
      ..playTimeSeconds += played.inSeconds;
    return save(g);
  }

  // ---------------------------------------------------------------------------
  // Seções da tela inicial
  // ---------------------------------------------------------------------------

  List<Game> get recentlyPlayed =>
      (_playable.where((g) => g.lastPlayed != null).toList()..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!)))
          .take(12)
          .toList();

  List<Game> get continuePlaying {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return (_playable.where((g) => g.installed && g.lastPlayed != null && g.lastPlayed!.isAfter(cutoff)).toList()
          ..sort((a, b) => b.playTimeSeconds.compareTo(a.playTimeSeconds)))
        .take(12)
        .toList();
  }

  List<Game> get recommended {
    final list = _playable
        .where((g) => !g.installed && g.compatibility.level == CompatLevel.compatible && g.bestAsset != null)
        .toList()
      ..sort((a, b) => (b.compatibility.score * 1000 + b.stars.clamp(0, 999)).compareTo(a.compatibility.score * 1000 + a.stars.clamp(0, 999)));
    return list.take(15).toList();
  }

  List<Game> get compatible => games.where((g) => g.compatibility.level == CompatLevel.compatible).toList();
  List<Game> get partial => games.where((g) => g.compatibility.level == CompatLevel.partial).toList();
  List<Game> get incompatible =>
      _playable.where((g) => g.compatibility.level == CompatLevel.incompatible).toList()..sort((a, b) => a.name.compareTo(b.name));
  List<Game> get updates => _games.values.where((g) => g.updateAvailable).toList();
  List<Game> get installedGames => games.where((g) => g.installed).toList();
  List<Game> get favorites => games.where((g) => g.favorite).toList();
  List<Game> get wishlist => games.where((g) => g.wishlist).toList();

  Set<String> get allCategories => {for (final g in _playable) ...g.categories};
  Set<String> get allEngines => {for (final g in _games.values) if (g.engine != null) g.engine!};

  // ---------------------------------------------------------------------------
  // Pesquisa
  // ---------------------------------------------------------------------------

  List<Game> search(String query, {SearchField field = SearchField.all}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return games;
    final terms = q.split(RegExp(r'\s+'));
    final scored = <(Game, int)>[];
    for (final g in games) {
      final haystack = switch (field) {
        SearchField.all => g.searchBlob,
        SearchField.name => g.name.toLowerCase(),
        SearchField.developer => g.author.toLowerCase(),
        SearchField.category => g.categories.join(' ').toLowerCase(),
        SearchField.engine => (g.engine ?? '').toLowerCase(),
        SearchField.tag => g.tags.join(' ').toLowerCase(),
      };
      if (!terms.every(haystack.contains)) continue;
      var score = 0;
      final name = g.name.toLowerCase();
      if (name == q) score += 1000;
      if (name.startsWith(q)) score += 500;
      if (name.contains(q)) score += 200;
      score += g.stars.clamp(0, 100) ~/ 10;
      if (g.installed) score += 20;
      scored.add((g, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    hardware.removeListener(_onHardwareChanged);
    super.dispose();
  }
}
