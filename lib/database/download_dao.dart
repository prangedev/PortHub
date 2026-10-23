import 'package:sqflite/sqflite.dart';

import '../core/models/download_task.dart';
import '../core/models/release_info.dart';

/// Acesso à tabela `downloads`.
class DownloadDao {
  DownloadDao(this._db);
  final Database _db;

  Future<List<DownloadTask>> all() async {
    final rows = await _db.query('downloads', orderBy: 'criado_em DESC');
    return rows.map(_fromRow).toList();
  }

  Future<int> insert(DownloadTask t) => _db.insert('downloads', _toRow(t)..remove('id'));

  Future<void> update(DownloadTask t) =>
      _db.update('downloads', _toRow(t), where: 'id = ?', whereArgs: [t.id]);

  Future<void> delete(int id) => _db.delete('downloads', where: 'id = ?', whereArgs: [id]);

  Map<String, Object?> _toRow(DownloadTask t) => {
        'id': t.id,
        'jogo_id': t.gameId,
        'jogo_nome': t.gameName,
        'url': t.url,
        'arquivo': t.fileName,
        'caminho': t.filePath,
        'versao': t.version,
        'tipo': t.kind.name,
        'total': t.totalBytes,
        'recebido': t.receivedBytes,
        'estado': t.state.name,
        'checksum': t.checksum,
        'erro': t.error,
        'criado_em': t.createdAt.millisecondsSinceEpoch,
      };

  DownloadTask _fromRow(Map<String, Object?> r) => DownloadTask(
        id: r['id'] as int,
        gameId: r['jogo_id'] as String,
        gameName: r['jogo_nome'] as String? ?? '',
        url: r['url'] as String,
        fileName: r['arquivo'] as String,
        filePath: r['caminho'] as String,
        version: r['versao'] as String? ?? '',
        kind: AssetKind.values.asNameMap()[r['tipo']] ?? AssetKind.other,
        totalBytes: r['total'] as int? ?? 0,
        receivedBytes: r['recebido'] as int? ?? 0,
        state: DownloadState.values.asNameMap()[r['estado']] ?? DownloadState.failed,
        checksum: r['checksum'] as String?,
        error: r['erro'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['criado_em'] as int),
      );
}
