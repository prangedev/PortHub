import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/compatibility_result.dart';
import '../core/models/game.dart';
import '../core/models/game_requirements.dart';
import '../core/models/release_info.dart';

/// Acesso à tabela `jogos`.
class GameDao {
  GameDao(this._db);
  final Database _db;

  Future<List<Game>> all() async {
    final rows = await _db.query('jogos');
    return rows.map(_fromRow).toList();
  }

  Future<void> upsert(Game g) =>
      _db.insert('jogos', _toRow(g), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> upsertAll(Iterable<Game> games) async {
    final batch = _db.batch();
    for (final g in games) {
      batch.insert('jogos', _toRow(g), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> delete(String id) => _db.delete('jogos', where: 'id = ?', whereArgs: [id]);

  static String? _enc(Object? v) => v == null ? null : jsonEncode(v);
  static List<String> _strList(Object? v) =>
      v == null ? const [] : (jsonDecode(v as String) as List).map((e) => e.toString()).toList();
  static DateTime? _date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

  Map<String, Object?> _toRow(Game g) => {
        'id': g.id,
        'nome': g.name,
        'descricao': g.description,
        'readme': g.readme,
        'autor': g.author,
        'github_url': g.githubUrl,
        'owner': g.owner,
        'repo': g.repo,
        'versao': g.version,
        'tamanho': g.size,
        'categoria': g.category,
        'categorias': _enc(g.categories),
        'engine': g.engine,
        'capa': g.coverUrl,
        'banner': g.bannerUrl,
        'icone': g.iconUrl,
        'galeria': _enc(g.gallery),
        'tags': _enc(g.tags),
        'linguagem': g.language,
        'licenca': g.license,
        'estrelas': g.stars,
        'ultima_atualizacao': g.lastUpdate?.millisecondsSinceEpoch,
        'requisitos': _enc(g.requirements.toJson()),
        'releases': _enc(g.releases.map((r) => r.toJson()).toList()),
        'issues_fixadas': _enc(g.pinnedIssues.map((i) => i.toJson()).toList()),
        'pacote_android': g.androidPackage,
        'resumo_ia': g.aiSummary,
        'provedor': g.provider,
        'instalado': g.installed ? 1 : 0,
        'versao_instalada': g.installedVersion,
        'instalado_em': g.installedAt?.millisecondsSinceEpoch,
        'caminho': g.installPath,
        'executavel': g.executablePath,
        'compatibilidade': g.compatibility.level.name,
        'compat_score': g.compatibility.score,
        'compat_json': _enc(g.compatibility.toJson()),
        'favorito': g.favorite ? 1 : 0,
        'desejado': g.wishlist ? 1 : 0,
        'ultimo_jogo': g.lastPlayed?.millisecondsSinceEpoch,
        'tempo_jogo': g.playTimeSeconds,
        'sessoes': g.sessions,
        'sincronizado_em': g.syncedAt.millisecondsSinceEpoch,
        'extras': jsonEncode({
          'origin': ?g.origin?.toJson(),
          'game_data': ?g.gameDataNote,
          'art_source': ?g.artSource,
        }),
      };

  Game _fromRow(Map<String, Object?> r) {
    CompatibilityResult compat = CompatibilityResult.unknown;
    if (r['compat_json'] != null) {
      compat = CompatibilityResult.fromJson((jsonDecode(r['compat_json'] as String) as Map).cast<String, dynamic>());
    }
    final extras = r['extras'] == null ? const <String, dynamic>{} : jsonDecode(r['extras'] as String) as Map;
    return Game(
      id: r['id'] as String,
      name: r['nome'] as String,
      provider: r['provedor'] as String? ?? 'desconhecido',
      description: r['descricao'] as String? ?? '',
      readme: r['readme'] as String?,
      author: r['autor'] as String? ?? '',
      githubUrl: r['github_url'] as String? ?? '',
      owner: r['owner'] as String?,
      repo: r['repo'] as String?,
      version: r['versao'] as String?,
      size: r['tamanho'] as int?,
      categories: _strList(r['categorias']),
      engine: r['engine'] as String?,
      coverUrl: r['capa'] as String?,
      bannerUrl: r['banner'] as String?,
      iconUrl: r['icone'] as String?,
      gallery: _strList(r['galeria']),
      tags: _strList(r['tags']),
      language: r['linguagem'] as String?,
      license: r['licenca'] as String?,
      stars: r['estrelas'] as int? ?? 0,
      lastUpdate: _date(r['ultima_atualizacao']),
      requirements: r['requisitos'] == null
          ? const GameRequirements()
          : GameRequirements.fromJson((jsonDecode(r['requisitos'] as String) as Map).cast<String, dynamic>()),
      releases: r['releases'] == null
          ? const []
          : (jsonDecode(r['releases'] as String) as List)
              .map((e) => ReleaseInfo.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
      pinnedIssues: r['issues_fixadas'] == null
          ? const []
          : (jsonDecode(r['issues_fixadas'] as String) as List)
              .map((e) => PinnedIssue.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
      androidPackage: r['pacote_android'] as String?,
      aiSummary: r['resumo_ia'] as String?,
      origin: GameOrigin.fromJson(extras['origin']),
      gameDataNote: extras['game_data'] as String?,
      artSource: extras['art_source'] as String?,
      installed: (r['instalado'] as int? ?? 0) == 1,
      installedVersion: r['versao_instalada'] as String?,
      installedAt: _date(r['instalado_em']),
      installPath: r['caminho'] as String?,
      executablePath: r['executavel'] as String?,
      compatibility: compat,
      favorite: (r['favorito'] as int? ?? 0) == 1,
      wishlist: (r['desejado'] as int? ?? 0) == 1,
      lastPlayed: _date(r['ultimo_jogo']),
      playTimeSeconds: r['tempo_jogo'] as int? ?? 0,
      sessions: r['sessoes'] as int? ?? 0,
      syncedAt: _date(r['sincronizado_em']),
    );
  }
}
