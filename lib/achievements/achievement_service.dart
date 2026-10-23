import 'dart:async';

import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'ra_client.dart';
import 'ra_models.dart';

/// Conta do RetroAchievements: login (usuário + chave da Web API), painel de
/// conquistas e acompanhamento em tempo real dos desbloqueios.
///
/// "Tempo real" = consulta às conquistas recentes a cada [livePeriod] enquanto
/// o app está em primeiro plano; cada desbloqueio novo vira um aviso com o
/// badge, como no Steam. Em segundo plano a consulta pausa.
class AchievementService extends ChangeNotifier with WidgetsBindingObserver {
  AchievementService(this.settings, this.notifications, {RaClient Function(String key)? clientFactory})
      : _clientFactory = clientFactory ?? ((key) => RaClient(apiKey: key));

  final SettingsService settings;
  final NotificationService notifications;
  final RaClient Function(String key) _clientFactory;

  static const livePeriod = Duration(seconds: 60);

  RaClient? _client;
  RaProfile? profile;
  List<RaUnlock> recent = const [];
  List<RaRecentGame> recentGames = const [];
  RaAchievementOfWeek? achievementOfWeek;
  final _gameCache = <int, RaGameProgress>{};

  bool loading = false;
  String? error;
  DateTime? lastSync;
  Timer? _timer;
  bool _foreground = true;

  /// Desbloqueios já vistos (para avisar só os novos).
  final _seen = <String>{};
  bool _primed = false;

  bool get loggedIn => settings.raUser.isNotEmpty && settings.raApiKey.isNotEmpty;
  bool get live => loggedIn && settings.raLive && _timer != null;
  String get user => settings.raUser;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    if (loggedIn) {
      _client = _clientFactory(settings.raApiKey);
      unawaited(refresh());
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && loggedIn) {
      // Voltou ao app: confere logo (as conquistas podem ter saído no emulador).
      unawaited(poll());
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (loggedIn && settings.raLive && _foreground) {
      _timer = Timer.periodic(livePeriod, (_) => poll());
    }
    notifyListeners();
  }

  void setLive(bool v) {
    settings.raLive = v;
    _schedule();
  }

  /// Valida a conta consultando o perfil; só salva se der certo.
  Future<String?> login(String user, String apiKey) async {
    user = user.trim();
    apiKey = apiKey.trim();
    if (user.isEmpty || apiKey.isEmpty) return 'Informe o usuário e a chave da Web API.';
    loading = true;
    error = null;
    notifyListeners();
    try {
      final client = _clientFactory(apiKey);
      final p = await client.profile(user);
      settings
        ..raUser = p.user
        ..raApiKey = apiKey;
      _client = client;
      profile = p;
      _seen.clear();
      _primed = false;
      appLog.i('RA', 'Conectado como ${p.user} (${p.points} pontos)');
      await refresh();
      _schedule();
      return null;
    } on RaException catch (e) {
      return e.unauthorized ? 'Chave da Web API inválida. Copie a chave em retroachievements.org › Settings.' : e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void logout() {
    settings
      ..raUser = ''
      ..raApiKey = '';
    _client = null;
    profile = null;
    recent = const [];
    recentGames = const [];
    _gameCache.clear();
    _seen.clear();
    _primed = false;
    _schedule();
  }

  /// Atualiza o painel inteiro (perfil, conquistas recentes, jogos, semana).
  Future<void> refresh() async {
    final c = _client;
    if (c == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        c.profile(user),
        c.recentUnlocks(user, minutes: 60 * 24 * 30),
        c.recentGames(user, count: 15),
        c.rank(user).catchError((Object _) => null),
      ]);
      final p = results[0] as RaProfile;
      profile = RaProfile(
        user: p.user,
        ulid: p.ulid,
        userPic: p.userPic,
        points: p.points,
        softcorePoints: p.softcorePoints,
        truePoints: p.truePoints,
        motto: p.motto,
        richPresence: p.richPresence,
        lastGameId: p.lastGameId,
        memberSince: p.memberSince,
        rank: results[3] as int?,
      );
      recent = results[1] as List<RaUnlock>;
      recentGames = results[2] as List<RaRecentGame>;
      _markSeen(recent);
      lastSync = DateTime.now();
      if (achievementOfWeek == null) {
        try {
          achievementOfWeek = await c.achievementOfTheWeek();
        } on RaException catch (e) {
          appLog.d('RA', 'Conquista da semana indisponível: $e');
        }
      }
    } on RaException catch (e) {
      error = e.message;
      if (e.unauthorized) logout();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _markSeen(List<RaUnlock> list) {
    for (final u in list) {
      _seen.add(u.key);
    }
    _primed = true;
  }

  /// Consulta leve (última hora) para detectar desbloqueios novos.
  Future<void> poll() async {
    final c = _client;
    if (c == null || loading) return;
    try {
      final latest = await c.recentUnlocks(user, minutes: 60);
      lastSync = DateTime.now();
      if (!_primed) {
        _markSeen(latest);
        notifyListeners();
        return;
      }
      final fresh = latest.where((u) => !_seen.contains(u.key)).toList();
      if (fresh.isEmpty) {
        notifyListeners();
        return;
      }
      for (final u in fresh.reversed) {
        _seen.add(u.key);
        notifications.push(
          'Conquista desbloqueada!',
          '${u.title} · ${u.points} pts${u.hardcore ? ' (hardcore)' : ''}\n${u.gameTitle}',
          icon: Icons.emoji_events_rounded,
          imageUrl: u.badgeUrl,
          system: true,
        );
      }
      appLog.i('RA', '${fresh.length} conquista(s) nova(s)');
      // Pontos e progresso mudaram: atualiza o painel e o jogo afetado.
      for (final u in fresh) {
        _gameCache.remove(u.gameId);
      }
      await refresh();
    } on RaException catch (e) {
      error = e.message;
      if (e.unauthorized) logout();
      notifyListeners();
    }
  }

  Future<RaGameProgress> gameProgress(int gameId, {bool force = false}) async {
    final c = _client;
    if (c == null) throw RaException('Conecte sua conta do RetroAchievements.');
    if (!force && _gameCache[gameId] != null) return _gameCache[gameId]!;
    return _gameCache[gameId] = await c.gameProgress(gameId, user);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
