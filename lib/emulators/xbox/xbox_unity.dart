import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_config.dart';
import '../../core/logger.dart';
import '../../database/cache_dao.dart';

/// Uma capa enviada pela comunidade do XboxUnity.
class XboxCover {
  const XboxCover({required this.id, this.official = false, this.rating, this.user, this.uploadedAt});
  final String id;
  final bool official;
  final int? rating;
  final String? user;
  final DateTime? uploadedAt;

  /// Capa completa (verso + lombada + frente, ~900x600). A frente fica à direita.
  String get largeUrl => '${XboxUnity.base}/Cover.php?size=large&cid=$id';
  String get smallUrl => '${XboxUnity.base}/Cover.php?size=small&cid=$id';
}

class XboxTitle {
  const XboxTitle(this.titleId, this.name, {this.coverCount = 0});
  final String titleId;
  final String name;
  final int coverCount;
}

/// API pública do XboxUnity — a mesma base de capas que o dashboard Aurora usa
/// em consoles RGH/JTAG. Busca pelo Title ID lido do `default.xex`.
class XboxUnity {
  XboxUnity(this._cache, {http.Client? client}) : _http = client ?? http.Client();
  final CacheDao _cache;
  final http.Client _http;

  static const base = 'https://xboxunity.net/Resources/Lib';
  static const _ttl = Duration(days: 30);

  /// Boxart oficial do marketplace da Microsoft (só a frente, 219x300). Só há
  /// HTTP; o domínio é liberado em `network_security_config.xml`.
  static String marketplaceBoxart(String titleId) =>
      'http://download.xbox.com/content/images/66acd000-77fe-1000-9115-d802${titleId.toLowerCase()}/1033/boxartlg.jpg';

  Future<Map<String, dynamic>?> _json(String url) async {
    final cached = await _cache.get(url);
    if (cached != null && cached.isFresh(_ttl)) return jsonDecode(cached.body) as Map<String, dynamic>;
    try {
      final res = await _http
          .get(Uri.parse(url), headers: {'User-Agent': AppConfig.userAgent})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      await _cache.put(url, body);
      return decoded;
    } catch (e) {
      appLog.w('XboxUnity', 'Falha em $url', e);
      if (cached != null) return jsonDecode(cached.body) as Map<String, dynamic>;
      return null;
    }
  }

  Future<List<XboxTitle>> search(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final j = await _json('$base/TitleList.php?page=0&count=12&search=$q&sort=3&direction=1&category=0&filter=0');
    final items = (j?['Items'] as List?) ?? const [];
    return [
      for (final raw in items.cast<Map>())
        if ((raw['TitleType'] ?? '360') == '360')
          XboxTitle('${raw['TitleID']}'.toUpperCase(), '${raw['Name']}',
              coverCount: int.tryParse('${raw['Covers']}') ?? 0),
    ];
  }

  /// Nome oficial do jogo pelo Title ID.
  Future<String?> titleName(String titleId) async {
    final hits = await search(titleId);
    for (final t in hits) {
      if (t.titleId == titleId.toUpperCase()) return t.name;
    }
    return null;
  }

  /// Capas disponíveis, melhores primeiro: oficiais, depois as mais bem avaliadas.
  Future<List<XboxCover>> covers(String titleId) async {
    final j = await _json('$base/CoverInfo.php?titleid=${titleId.toUpperCase()}');
    final list = [
      for (final c in ((j?['Covers'] as List?) ?? const []).cast<Map>())
        XboxCover(
          id: '${c['CoverID']}',
          official: '${c['Official']}' == '1',
          rating: int.tryParse('${c['Rating']}'),
          user: c['Username'] as String?,
          uploadedAt: DateTime.tryParse('${c['UploadedDate']}'),
        ),
    ];
    list.sort((a, b) {
      if (a.official != b.official) return a.official ? -1 : 1;
      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });
    return list;
  }
}
