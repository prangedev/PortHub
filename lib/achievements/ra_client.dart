import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import 'ra_models.dart';

class RaException implements Exception {
  RaException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Cliente da Web API do RetroAchievements. Autenticação = chave da Web API
/// (`y`), obtida em retroachievements.org › Settings › Keys. A API não tem
/// login por senha.
class RaClient {
  RaClient({required this.apiKey, http.Client? client}) : _http = client ?? http.Client();

  final String apiKey;
  final http.Client _http;

  static const _base = '$raSite/API';

  Future<Object?> _get(String endpoint, Map<String, String> params) async {
    final uri = Uri.parse('$_base/$endpoint').replace(queryParameters: {...params, 'y': apiKey});
    final http.Response res;
    try {
      res = await _http.get(uri, headers: {'User-Agent': AppConfig.userAgent}).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw RaException('Sem conexão com o RetroAchievements.');
    }
    if (res.statusCode == 401) throw RaException('Chave da Web API inválida.', statusCode: 401);
    if (res.statusCode == 404) throw RaException('Usuário ou jogo não encontrado.', statusCode: 404);
    if (res.statusCode == 429) throw RaException('Muitas consultas ao RetroAchievements; tente em instantes.', statusCode: 429);
    if (res.statusCode != 200) throw RaException('RetroAchievements respondeu HTTP ${res.statusCode}.', statusCode: res.statusCode);
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

  List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? [for (final e in v) if (e is Map) e.cast<String, dynamic>()] : const [];

  Future<RaProfile> profile(String user) async {
    final j = _map(await _get('API_GetUserProfile.php', {'u': user}));
    if (j['User'] == null) throw RaException('Usuário "$user" não encontrado.', statusCode: 404);
    return RaProfile.fromJson(j);
  }

  /// Resumo com o ranking (o perfil simples não traz a posição).
  Future<int?> rank(String user) async {
    final j = _map(await _get('API_GetUserSummary.php', {'u': user, 'g': '0', 'a': '0'}));
    final r = j['Rank'];
    return r is num ? r.toInt() : int.tryParse('$r');
  }

  /// Conquistas desbloqueadas nos últimos [minutes] minutos (mais recentes primeiro).
  Future<List<RaUnlock>> recentUnlocks(String user, {int minutes = 60}) async =>
      _list(await _get('API_GetUserRecentAchievements.php', {'u': user, 'm': '$minutes'})).map(RaUnlock.fromJson).toList();

  Future<List<RaRecentGame>> recentGames(String user, {int count = 12}) async =>
      _list(await _get('API_GetUserRecentlyPlayedGames.php', {'u': user, 'c': '$count'})).map(RaRecentGame.fromJson).toList();

  Future<RaGameProgress> gameProgress(int gameId, String user) async =>
      RaGameProgress.fromJson(_map(await _get('API_GetGameInfoAndUserProgress.php', {'g': '$gameId', 'u': user, 'a': '1'})));

  Future<RaAchievementOfWeek> achievementOfTheWeek() async =>
      RaAchievementOfWeek.fromJson(_map(await _get('API_GetAchievementOfTheWeek.php', const {})));
}
