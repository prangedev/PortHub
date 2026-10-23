import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/core/models/release_info.dart';
import 'package:porthub/database/cache_dao.dart';
import 'package:porthub/database/settings_dao.dart';
import 'package:porthub/github/github_client.dart';
import 'package:porthub/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Trecho real de github.com/rfandango/XenDroid/releases/expanded_assets/XenDroid-0b11201 (SVGs removidos).
const _html = '''
<div class="Box Box--condensed tmp-mt-3"><ul>
<li class="Box-row d-flex flex-column flex-md-row"><div><span class="d-flex flex-items-start">
<a href="/rfandango/XenDroid/releases/download/XenDroid-0b11201/XenDroid_Release_0b11201.apk" rel="nofollow" data-turbo="false" class="wb-break-all">
<span class="text-bold">XenDroid_Release_0b11201.apk</span></a></span></div><div><div>
<span class="Truncate text-mono text-small color-fg-muted"><span class="Truncate-text">sha256:9948e467af8193952a2a90c918996c015b3d15c6936616ea2b14dc5ccaca3d73</span></span>
</div>          <span style="white-space: nowrap;" class="color-fg-muted text-right">13 MB</span>
<span class="color-fg-muted text-right"><relative-time datetime="2026-08-14T16:33:53Z" class="no-wrap" prefix="">2026-08-14T16:33:53Z</relative-time></span>
</div></li>
<li class="Box-row d-flex flex-column flex-md-row"><div><span class="d-flex flex-items-start">
<a href="/rfandango/XenDroid/archive/refs/tags/XenDroid-0b11201.zip" rel="nofollow" class="wb-break-all">
<span class="text-bold">Source code</span> (zip)</a></span></div>
<div><span class="color-fg-muted text-right"><relative-time datetime="2026-08-14T16:23:41Z">x</relative-time></span></div></li>
</ul></div>
''';

void main() {
  test('lê a release pela página expanded_assets', () {
    final r = GitHubClient.parseExpandedAssets(_html, owner: 'rfandango', repo: 'XenDroid', tag: 'XenDroid-0b11201');
    expect(r.tag, 'XenDroid-0b11201');
    expect(r.assets, hasLength(1)); // "Source code" fica de fora
    final apk = r.assets.single;
    expect(apk.name, 'XenDroid_Release_0b11201.apk');
    expect(apk.kind, AssetKind.apk);
    expect(apk.url, 'https://github.com/rfandango/XenDroid/releases/download/XenDroid-0b11201/XenDroid_Release_0b11201.apk');
    expect(apk.checksum, 'sha256:9948e467af8193952a2a90c918996c015b3d15c6936616ea2b14dc5ccaca3d73');
    expect(apk.size, 13 * 1024 * 1024);
    expect(r.publishedAt, DateTime.utc(2026, 8, 14, 16, 33, 53));
  });

  test('plano B ao vivo: release sem API (não gasta cota)', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE IF NOT EXISTS http_cache (url TEXT PRIMARY KEY, etag TEXT, body TEXT NOT NULL, buscado_em INTEGER NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
    final settings = SettingsService(SettingsDao(db));
    await settings.load();
    final gh = GitHubClient(cache: CacheDao(db), settings: settings);
    final xen = await gh.latestReleaseFromWeb('rfandango', 'XenDroid');
    expect(xen!.assets.where((a) => a.kind == AssetKind.apk), isNotEmpty);
    final ug2 = await gh.latestReleaseFromWeb('codepdbh', 'nfsu2-recompiled');
    expect(ug2!.assets.map((a) => a.name), contains(matches(RegExp(r'arm64\.apk$'))));
  }, skip: Platform.environment['PORTHUB_LIVE'] != '1', timeout: const Timeout(Duration(minutes: 1)));
}
