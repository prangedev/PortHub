import 'dart:convert';

import '../../core/app_config.dart';
import '../../core/models/game_requirements.dart';
import '../../core/models/release_info.dart';
import '../../core/platform_info.dart';
import '../../github/github_client.dart';
import 'game_source_provider.dart';

/// Adaptador do PortMaster (ports para handhelds Linux ARM).
///
/// Lê o `ports.json` publicado nas releases do PortsMaster/PortMaster-New. O
/// formato é tratado de forma defensiva, pois pode mudar entre versões.
class PortMasterProvider extends GameSourceProvider {
  PortMasterProvider(this._gh);
  final GitHubClient _gh;

  @override
  String get id => 'portmaster';
  @override
  String get displayName => 'PortMaster';
  @override
  String get description => 'Ports para handhelds Linux (aarch64) do projeto PortMaster.';
  @override
  bool get enabledByDefault => hostPlatform == HostPlatform.linux;

  static const _genreMap = {
    'rpg': 'RPG',
    'action': 'Ação',
    'adventure': 'Ação',
    'fps': 'FPS',
    'shooter': 'FPS',
    'racing': 'Corrida',
    'platformer': 'Plataforma',
    'strategy': 'Estratégia',
    'horror': 'Terror',
    'puzzle': 'Puzzle',
  };

  @override
  Future<List<CatalogEntry>> fetch() async {
    final text = await _gh.rawText(AppConfig.portMasterPortsJson, ttl: const Duration(hours: 12));
    final json = jsonDecode(text) as Map<String, dynamic>;
    final ports = (json['ports'] as Map?)?.cast<String, dynamic>() ?? const {};
    final out = <CatalogEntry>[];

    for (final e in ports.entries) {
      final p = (e.value as Map).cast<String, dynamic>();
      final attr = (p['attr'] as Map?)?.cast<String, dynamic>() ?? const {};
      final source = (p['source'] as Map?)?.cast<String, dynamic>() ?? const {};
      final url = source['url'] as String?;
      if (url == null) continue;

      final slug = e.key.replaceAll(RegExp(r'\.zip$'), '');
      final genres = ((attr['genres'] as List?) ?? const [])
          .map((g) => _genreMap['$g'.toLowerCase()])
          .whereType<String>()
          .toSet()
          .toList();
      final porters = ((attr['porter'] as List?) ?? const []).map((x) => '$x').toList();
      final rtr = attr['rtr'] == true;
      final archs = ((attr['arch'] as List?) ?? const ['aarch64']).map((a) => normalizeArch('$a')).whereType<String>().toList();

      String? screenshot;
      String? cover;
      final image = attr['image'];
      if (image is Map) {
        if (image['screenshot'] != null) screenshot = '${AppConfig.portMasterRaw}/$slug/${image['screenshot']}';
        final covers = image['covers'];
        if (covers is List && covers.isNotEmpty) cover = '${AppConfig.portMasterRaw}/$slug/${covers.first}';
      }
      final paid = attr['availability'] == 'paid';

      final md5 = source['md5'] as String?;
      out.add(CatalogEntry(
        id: 'pm:$slug',
        provider: id,
        name: attr['title'] as String? ?? slug,
        description: attr['desc'] as String?,
        author: porters.isEmpty ? 'PortMaster' : porters.join(', '),
        categories: genres,
        tags: [
          'PortMaster',
          if (!rtr) 'Requer arquivos do jogo',
          if (rtr) 'Pronto para jogar',
          if (paid) 'Jogo pago',
        ],
        requirements: GameRequirements(
          platforms: const ['linux'],
          architectures: archs.isEmpty ? const ['arm64'] : archs,
          sources: const ['PortMaster'],
        ),
        banner: screenshot,
        cover: cover ?? screenshot,
        homepage: 'https://portmaster.games/detail.html?name=$slug',
        directRelease: ReleaseInfo(
          tag: source['date_updated'] as String? ?? 'portmaster',
          name: attr['title'] as String? ?? slug,
          body: attr['inst'] as String? ?? '',
          publishedAt: DateTime.tryParse(source['date_updated'] as String? ?? ''),
          assets: [
            ReleaseAsset(
              name: e.key,
              url: url,
              size: (source['size'] as num?)?.toInt() ?? 0,
              kind: AssetKind.zip,
              platform: AssetPlatform.linux,
              arch: archs.isEmpty ? 'arm64' : archs.first,
              checksum: md5 == null ? null : 'md5:${md5.toLowerCase()}',
            ),
          ],
        ),
      ));
    }
    return out;
  }
}
