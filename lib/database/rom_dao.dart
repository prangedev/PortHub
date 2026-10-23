import 'package:sqflite/sqflite.dart';

import '../emulators/rom_game.dart';

/// Acesso à tabela `roms` (jogos importados para emuladores).
class RomDao {
  RomDao(this._db);
  final Database _db;

  Future<List<RomGame>> all() async => (await _db.query('roms')).map(RomGame.fromRow).toList();

  Future<void> upsert(RomGame g) => _db.insert('roms', g.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String id) => _db.delete('roms', where: 'id = ?', whereArgs: [id]);
}
