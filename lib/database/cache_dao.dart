import 'package:sqflite/sqflite.dart';

class CachedResponse {
  const CachedResponse({required this.body, required this.fetchedAt, this.etag});
  final String body;
  final String? etag;
  final DateTime fetchedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(fetchedAt) < ttl;
}

/// Cache HTTP (respostas do GitHub, catálogo, relatos). Guarda ETag para
/// requisições condicionais — respostas 304 não consomem o rate limit do GitHub.
class CacheDao {
  CacheDao(this._db);
  final Database _db;

  Future<CachedResponse?> get(String url) async {
    final rows = await _db.query('http_cache', where: 'url = ?', whereArgs: [url], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CachedResponse(
      body: r['body'] as String,
      etag: r['etag'] as String?,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(r['buscado_em'] as int),
    );
  }

  Future<void> put(String url, String body, {String? etag}) => _db.insert(
        'http_cache',
        {'url': url, 'etag': etag, 'body': body, 'buscado_em': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> touch(String url) => _db.update(
        'http_cache',
        {'buscado_em': DateTime.now().millisecondsSinceEpoch},
        where: 'url = ?',
        whereArgs: [url],
      );

  Future<int> clear() => _db.delete('http_cache');

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM http_cache')) ?? 0;
}
