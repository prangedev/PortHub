import 'package:sqflite/sqflite.dart';

/// Chave/valor simples para as configurações do app.
class SettingsDao {
  SettingsDao(this._db);
  final Database _db;

  Future<Map<String, String>> all() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''};
  }

  Future<void> set(String key, String value) => _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
