import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/core/platform_info.dart';
import 'package:porthub/database/cache_dao.dart';
import 'package:porthub/database/settings_dao.dart';
import 'package:porthub/github/asset_detector.dart';
import 'package:porthub/github/github_client.dart';
import 'package:porthub/github/readme_parser.dart';
import 'package:porthub/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Teste contra a API real do GitHub (gasta ~4 requisições).
/// Rode com: PORTHUB_LIVE=1 flutter test test/live
void main() {
  final live = Platform.environment['PORTHUB_LIVE'] == '1';

  test('GitHub: releases, README, cache ETag e escolha de asset', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE http_cache (url TEXT PRIMARY KEY, etag TEXT, body TEXT NOT NULL, buscado_em INTEGER NOT NULL)');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    final settings = SettingsService(SettingsDao(db));
    await settings.load();
    final gh = GitHubClient(cache: CacheDao(db), settings: settings);

    final repo = await gh.repo('diasurgical', 'devilutionX');
    expect(repo.stars, greaterThan(1000));

    final releases = await gh.releases('diasurgical', 'devilutionX');
    expect(releases, isNotEmpty);
    final assets = releases.first.assets;
    final android = AssetDetector.pickBest(assets, HostPlatform.android, ['arm64', 'armv7']);
    final windows = AssetDetector.pickBest(assets, HostPlatform.windows, ['x86_64', 'x86']);
    final linux = AssetDetector.pickBest(assets, HostPlatform.linux, ['x86_64']);
    // ignore: avoid_print
    print('${releases.first.tag}: android=${android?.name} windows=${windows?.name} linux=${linux?.name} '
        'sha=${android?.checksum != null} rate=${gh.rateRemaining}');
    expect(android?.name, 'devilutionx-android.apk');
    expect(linux?.name, contains('x86_64'));
    expect(windows, isNotNull);

    final readme = await gh.readme('diasurgical', 'devilutionX');
    expect(readme, isNotNull);
    final images = ReadmeParser.images(readme!.markdown, readme.rawBaseUrl);
    // ignore: avoid_print
    print('README: ${readme.markdown.length} chars, ${images.length} imagens, engine=${ReadmeParser.engine(repo.topics, readme.markdown, repo.language)}');

    // Repositório sem porthub.yaml → null (e o 404 fica em cache).
    expect(await gh.fileContent('diasurgical', 'devilutionX', 'porthub.yaml'), isNull);
    final before = gh.rateRemaining;
    expect(await gh.fileContent('diasurgical', 'devilutionX', 'porthub.yaml'), isNull);
    expect(gh.rateRemaining, before, reason: 'segunda consulta deve vir do cache');

    // Segunda leitura dentro do TTL vem do cache, sem rede.
    final again = await gh.releases('diasurgical', 'devilutionX');
    expect(again.first.tag, releases.first.tag);
    await db.close();
  }, skip: !live, timeout: const Timeout(Duration(minutes: 2)));
}
