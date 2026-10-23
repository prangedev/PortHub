import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/database/cache_dao.dart';
import 'package:porthub/emulators/xbox/xbox_unity.dart';
import 'package:porthub/services/artwork_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fontes de arte reais (libretro, Wikipédia, XboxUnity). Não usa o GitHub.
/// Rode com: PORTHUB_LIVE=1 flutter test test/live
void main() {
  final live = Platform.environment['PORTHUB_LIVE'] == '1';

  Future<CacheDao> cache() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE IF NOT EXISTS http_cache (url TEXT PRIMARY KEY, etag TEXT, body TEXT NOT NULL, buscado_em INTEGER NOT NULL)');
    return CacheDao(db);
  }

  test('capas e capturas dos ports novos', () async {
    final art = ArtworkService(await cache());
    final black = await art.lookup(const ArtQuery(title: 'Black', systems: ['Microsoft - Xbox']));
    expect(black.cover, contains('Named_Boxarts/Black%20(USA).png'));
    expect(black.banner, contains('Named_Snaps'));

    final ug2 = await art.lookup(const ArtQuery(title: 'Need for Speed: Underground 2', systems: ['Sony - PlayStation 2']));
    expect(ug2.cover, isNotNull);
    expect(ug2.screenshots, isNotEmpty);

    // Sem console conhecido: cai na Wikipédia com nome exato.
    final riders = await art.lookup(const ArtQuery(title: 'Sonic Free Riders', systems: ['Sega - 32X']));
    expect(riders.cover, contains('wikimedia.org'));

    for (final r in [black, ug2, riders]) {
      for (final url in [r.cover, ...r.screenshots].whereType<String>()) {
        final req = await HttpClient().headUrl(Uri.parse(url));
        req.headers.set('User-Agent', 'PortHub-test');
        final res = await req.close();
        expect(res.statusCode, 200, reason: url);
      }
    }
  }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));

  test('XboxUnity: nome e capas pelo Title ID (estilo Aurora)', () async {
    final xu = XboxUnity(await cache());
    expect(await xu.titleName('4D5307E6'), 'Halo 3');
    final covers = await xu.covers('4D5307E6');
    expect(covers, isNotEmpty);
    expect(covers.first.official, isTrue);
  }, skip: !live, timeout: const Timeout(Duration(minutes: 1)));
}
