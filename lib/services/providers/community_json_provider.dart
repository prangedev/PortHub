import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/logger.dart';
import '../../core/models/game.dart';
import '../../core/models/game_requirements.dart';
import '../../github/github_client.dart';
import '../settings_service.dart';
import 'game_source_provider.dart';

/// Lista JSON comunitária: arquivo curado com repositórios de ports, categorias,
/// engine e requisitos estimados. Formato documentado no README.
///
/// Usa a URL configurada (fork/espelho da comunidade) e, se falhar, a cópia
/// embarcada em assets.
class CommunityJsonProvider extends GameSourceProvider {
  CommunityJsonProvider(this._gh, this._settings);
  final GitHubClient _gh;
  final SettingsService _settings;

  @override
  String get id => 'community';
  @override
  String get displayName => 'Lista JSON comunitária';
  @override
  String get description => 'Catálogo curado pela comunidade (assets/catalog/community.json ou URL própria).';
  @override
  bool get enabledByDefault => true;

  @override
  Future<List<CatalogEntry>> fetch() async {
    String? text;
    final url = _settings.communityCatalogUrl;
    if (url.isNotEmpty) {
      try {
        text = await _gh.rawText(url, ttl: const Duration(hours: 6));
      } catch (e) {
        appLog.w('Catalog', 'Catálogo remoto indisponível, usando o embarcado', e);
      }
    }
    text ??= await rootBundle.loadString(AppConfig.bundledCatalogAsset);
    return parse(text, providerId: id);
  }

  static List<CatalogEntry> parse(String text, {String providerId = 'community'}) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final games = (json['games'] as List?) ?? const [];
    final result = <CatalogEntry>[];
    for (final raw in games) {
      final g = (raw as Map).cast<String, dynamic>();
      final repoFull = g['repo'] as String?;
      String? owner;
      String? repo;
      if (repoFull != null && repoFull.contains('/')) {
        final parts = repoFull.split('/');
        owner = parts[0];
        repo = parts[1];
      }
      final slug = repoFull ?? g['id'] as String? ?? g['name'] as String?;
      if (slug == null) continue;
      List<String> list(String k) => (g[k] as List?)?.map((e) => '$e').toList() ?? const [];
      result.add(CatalogEntry(
        id: 'gh:${slug.toLowerCase()}',
        provider: providerId,
        name: g['name'] as String?,
        owner: owner,
        repo: repo,
        description: g['description'] as String?,
        author: g['author'] as String?,
        categories: list('categories'),
        tags: list('tags'),
        engine: g['engine'] as String?,
        requirements: g['requirements'] is Map
            ? GameRequirements.fromMap(g['requirements'] as Map, source: 'catálogo comunitário')
            : null,
        cover: g['cover'] as String?,
        banner: g['banner'] as String?,
        icon: g['icon'] as String?,
        gallery: list('gallery'),
        androidPackage: g['android_package'] as String?,
        prereleases: g['prereleases'] == true,
        origin: GameOrigin.fromJson(g['original']),
        gameDataNote: g['game_data'] as String?,
      ));
    }
    return result;
  }
}
