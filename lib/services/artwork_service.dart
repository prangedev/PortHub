import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/logger.dart';
import '../database/cache_dao.dart';

/// O que procurar: nome do jogo original e, se souber, o console de origem.
class ArtQuery {
  const ArtQuery({required this.title, this.systems = const [], this.wikipedia, this.steamAppId});

  /// Nome do jogo original (ex.: "Need for Speed: Underground 2"), não do port.
  final String title;

  /// Pastas do acervo libretro (ex.: "Microsoft - Xbox", "Sony - PlayStation 2").
  final List<String> systems;

  /// Título exato do artigo na Wikipédia em inglês, quando o nome é ambíguo
  /// (ex.: "Black (video game)").
  final String? wikipedia;
  final int? steamAppId;

  String get cacheKey => 'porthub:art:v1:${ArtworkService.normalize(title)}|${systems.join(',')}|$wikipedia|$steamAppId';
}

class ArtResult {
  const ArtResult({this.cover, this.banner, this.screenshots = const [], this.source});
  final String? cover;
  final String? banner;
  final List<String> screenshots;
  final String? source;

  bool get isEmpty => cover == null && banner == null && screenshots.isEmpty;

  Map<String, dynamic> toJson() => {
        'cover': cover,
        'banner': banner,
        'screenshots': screenshots,
        'source': source,
      };

  factory ArtResult.fromJson(Map<String, dynamic> j) => ArtResult(
        cover: j['cover'] as String?,
        banner: j['banner'] as String?,
        screenshots: (j['screenshots'] as List?)?.cast<String>() ?? const [],
        source: j['source'] as String?,
      );
}

/// Busca capa e capturas de tela do jogo original para ports sem imagens.
///
/// Fontes públicas, sem chave de API, em ordem de preferência:
/// 1. Acervo de miniaturas do libretro — boxart + captura de tela + tela de título,
///    organizado por console (o mesmo usado pelo RetroArch).
/// 2. Steam — só com o app id informado no catálogo (a busca por nome confunde
///    remakes, ex.: Most Wanted 2005 x 2012).
/// 3. Wikipédia — imagem do artigo (normalmente a capa), com nome exato.
///
/// Só aceita resultados cujo nome normalizado bate exatamente com o procurado,
/// para não mostrar a capa de outro jogo.
class ArtworkService {
  ArtworkService(this._cache, {http.Client? client}) : _http = client ?? http.Client();
  final CacheDao _cache;
  final http.Client _http;

  static const libretroBase = 'https://thumbnails.libretro.com';
  static const _resultTtl = Duration(days: 14);
  static const _indexTtl = Duration(days: 7);

  /// Consoles tentados quando a origem do port é desconhecida.
  static const defaultSystems = [
    'Microsoft - Xbox',
    'Sony - PlayStation 2',
    'Nintendo - GameCube',
    'Nintendo - Wii',
    'Sony - PlayStation',
    'Nintendo - Nintendo 64',
  ];

  final _indexes = <String, Future<Map<String, String>>>{};

  Future<ArtResult> lookup(ArtQuery q) async {
    final cached = await _cache.get(q.cacheKey);
    if (cached != null && cached.isFresh(_resultTtl)) {
      return ArtResult.fromJson(jsonDecode(cached.body) as Map<String, dynamic>);
    }
    var result = const ArtResult();
    try {
      result = await _fromLibretro(q);
      if (result.cover == null && q.steamAppId != null) result = _merge(result, await _fromSteam(q.steamAppId!));
      if (result.cover == null) result = _merge(result, await _fromWikipedia(q));
    } catch (e) {
      appLog.w('Arte', 'Falha ao buscar arte de "${q.title}"', e);
      if (cached != null) return ArtResult.fromJson(jsonDecode(cached.body) as Map<String, dynamic>);
      return result;
    }
    await _cache.put(q.cacheKey, jsonEncode(result.toJson()));
    if (!result.isEmpty) appLog.i('Arte', '"${q.title}": capa de ${result.source}');
    return result;
  }

  ArtResult _merge(ArtResult a, ArtResult b) => ArtResult(
        cover: a.cover ?? b.cover,
        banner: a.banner ?? b.banner,
        screenshots: [...a.screenshots, ...b.screenshots],
        source: a.source ?? b.source,
      );

  // --- Nomes -------------------------------------------------------------------

  /// "Need for Speed - Underground 2 (USA)" e "Need for Speed™: Underground 2"
  /// viram "need for speed underground 2".
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"['’™®©]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Preferência de região/versão do acervo libretro (menor = melhor).
  static int regionRank(String fileName) {
    final f = fileName.toLowerCase();
    if (RegExp(r'\((beta|proto|demo|sample|kiosk|preview)').hasMatch(f)) return 99;
    if (f.contains('(usa)')) return 0;
    if (f.contains('(usa,')) return 1;
    if (f.contains('(world)')) return 2;
    if (f.contains('(europe)')) return 3;
    if (f.contains('europe')) return 4;
    return 10;
  }

  /// Escolhe o arquivo do índice cujo nome bate com [title].
  static String? bestMatch(Iterable<String> files, String title) {
    final want = normalize(title);
    String? best;
    var bestRank = 1 << 30;
    for (final f in files) {
      if (normalize(f.replaceAll(RegExp(r'\.png$'), '')) != want) continue;
      final rank = regionRank(f);
      if (rank < bestRank) {
        best = f;
        bestRank = rank;
      }
    }
    return bestRank >= 99 ? null : best;
  }

  /// Gera um nome de busca a partir do nome do repositório de um port
  /// ("nfsu2-recompiled" → "nfsu2", "Black-Android" → "Black").
  static String titleFromRepoName(String name) {
    const noise = {
      'port', 'ports', 'android', 'recomp', 'recompiled', 'recompilation', 'decomp', 'decompilation',
      'native', 'pc', 'mobile', 'arm64', 're', 'sdl', 'sdl2', 'evolved', 'androidevolved', 'remake',
      'reimplementation', 'source', 'engine', 'unofficial', 'switch', 'nx', 'vita', 'universal', '360',
    };
    final words = name
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'[-_\s.]+'))
        .where((w) => w.isNotEmpty && !noise.contains(w.toLowerCase()))
        .toList();
    return words.join(' ');
  }

  // --- libretro ------------------------------------------------------------------

  String _folderUrl(String system, String kind) =>
      '$libretroBase/${Uri.encodeComponent(system)}/$kind/';

  /// [href] é o link já codificado que o servidor publica no índice.
  String _fileUrl(String system, String kind, String href) => '${_folderUrl(system, kind)}$href';

  /// Índice de uma pasta (lista de arquivos .png), em cache por uma semana.
  Future<Map<String, String>> _index(String system, String kind) =>
      _indexes.putIfAbsent('$system/$kind', () async {
        final url = _folderUrl(system, kind);
        final cached = await _cache.get(url);
        String? html;
        if (cached != null && cached.isFresh(_indexTtl)) {
          html = cached.body;
        } else {
          try {
            final res = await _http
                .get(Uri.parse(url), headers: {'User-Agent': AppConfig.userAgent})
                .timeout(const Duration(seconds: 40));
            if (res.statusCode == 200) {
              html = utf8.decode(res.bodyBytes, allowMalformed: true);
              await _cache.put(url, html);
            }
          } catch (e) {
            appLog.w('Arte', 'Índice libretro indisponível: $system/$kind', e);
          }
          html ??= cached?.body;
        }
        if (html == null) return const <String, String>{};
        return parseIndex(html);
      });

  /// Extrai os nomes de arquivo de uma listagem HTML do servidor (Apache).
  static Map<String, String> parseIndex(String html) {
    final out = <String, String>{};
    for (final m in RegExp(r'href="([^"?/][^"]*\.png)"').allMatches(html)) {
      final raw = m.group(1)!;
      final name = Uri.decodeComponent(raw).replaceAll('&amp;', '&');
      out[name] = raw;
    }
    return out;
  }

  Future<ArtResult> _fromLibretro(ArtQuery q) async {
    final systems = q.systems.isEmpty ? defaultSystems : q.systems;
    for (final system in systems) {
      final boxes = await _index(system, 'Named_Boxarts');
      final snaps = await _index(system, 'Named_Snaps');
      final box = bestMatch(boxes.keys, q.title);
      final snap = bestMatch(snaps.keys, q.title);
      if (box == null && snap == null) continue;
      final titles = await _index(system, 'Named_Titles');
      final titleScreen = bestMatch(titles.keys, q.title);
      final shots = [
        if (snap != null) _fileUrl(system, 'Named_Snaps', snaps[snap]!),
        if (titleScreen != null) _fileUrl(system, 'Named_Titles', titles[titleScreen]!),
      ];
      return ArtResult(
        cover: box != null ? _fileUrl(system, 'Named_Boxarts', boxes[box]!) : null,
        banner: shots.isNotEmpty ? shots.first : null,
        screenshots: shots,
        source: 'libretro ($system)',
      );
    }
    return const ArtResult();
  }

  // --- Steam -----------------------------------------------------------------------

  Future<ArtResult> _fromSteam(int appId) async {
    const cdn = 'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps';
    final shots = <String>[];
    try {
      final url = 'https://store.steampowered.com/api/appdetails?appids=$appId&filters=screenshots';
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (j['$appId'] as Map?)?['data'] as Map?;
      for (final s in ((data?['screenshots'] as List?) ?? const []).cast<Map>().take(8)) {
        final full = s['path_full'] as String?;
        if (full != null) shots.add(full);
      }
    } catch (e) {
      appLog.d('Arte', 'Steam $appId sem capturas: $e');
    }
    return ArtResult(
      cover: '$cdn/$appId/library_600x900_2x.jpg',
      banner: shots.isNotEmpty ? shots.first : '$cdn/$appId/library_hero.jpg',
      screenshots: shots,
      source: 'Steam',
    );
  }

  // --- Wikipédia ---------------------------------------------------------------------

  Future<ArtResult> _fromWikipedia(ArtQuery q) async {
    final params = <String, String>{
      'action': 'query',
      'format': 'json',
      'prop': 'pageimages',
      'piprop': 'original',
      'pilicense': 'any',
      'redirects': '1',
    };
    if (q.wikipedia != null) {
      params['titles'] = q.wikipedia!;
    } else {
      params
        ..['generator'] = 'search'
        ..['gsrsearch'] = '${q.title} video game'
        ..['gsrlimit'] = '5';
    }
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', params);
    final cached = await _cache.get(uri.toString());
    String body;
    if (cached != null && cached.isFresh(_resultTtl)) {
      body = cached.body;
    } else {
      final res = await _http
          .get(uri, headers: {'User-Agent': '${AppConfig.userAgent} (https://github.com/porthub)'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const ArtResult();
      body = utf8.decode(res.bodyBytes);
      await _cache.put(uri.toString(), body);
    }
    final pages = ((jsonDecode(body) as Map)['query'] as Map?)?['pages'] as Map?;
    if (pages == null) return const ArtResult();
    final list = pages.values.cast<Map>().toList()
      ..sort((a, b) => ((a['index'] as int?) ?? 0).compareTo((b['index'] as int?) ?? 0));
    final want = normalize(q.title);
    for (final p in list) {
      final title = '${p['title']}';
      // "Black (video game)" conta como "Black"; com título exato no catálogo, aceita direto.
      if (q.wikipedia == null && normalize(title) != want) continue;
      final src = (p['original'] as Map?)?['source'] as String?;
      if (src == null) continue;
      final clean = src.split('?').first;
      return ArtResult(cover: clean, source: 'Wikipédia');
    }
    return const ArtResult();
  }
}
