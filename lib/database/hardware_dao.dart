import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/models/hardware_profile.dart';

/// Acesso à tabela `hardware_cache`. Mantém o histórico de análises; a mais
/// recente é a usada pelo motor de compatibilidade.
class HardwareDao {
  HardwareDao(this._db);
  final Database _db;

  Future<HardwareProfile?> latest() async {
    final rows = await _db.query('hardware_cache', orderBy: 'criado_em DESC', limit: 1);
    if (rows.isEmpty) return null;
    return HardwareProfile.fromJson((jsonDecode(rows.first['dados'] as String) as Map).cast<String, dynamic>());
  }

  Future<void> save(HardwareProfile hw) async {
    await _db.insert('hardware_cache', {
      'plataforma': hw.platform,
      'dados': jsonEncode(hw.toJson()),
      'criado_em': hw.scannedAt.millisecondsSinceEpoch,
    });
    // Mantém apenas as 10 últimas análises.
    await _db.execute(
        'DELETE FROM hardware_cache WHERE id NOT IN (SELECT id FROM hardware_cache ORDER BY criado_em DESC LIMIT 10)');
  }
}
