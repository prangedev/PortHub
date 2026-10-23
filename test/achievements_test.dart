import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/achievements/achievement_service.dart';
import 'package:porthub/achievements/ra_client.dart';
import 'package:porthub/achievements/ra_models.dart';
import 'package:porthub/database/settings_dao.dart';
import 'package:porthub/services/notification_service.dart';
import 'package:porthub/services/settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

RaUnlock unlock(int id, {bool hc = true}) => RaUnlock.fromJson({
      'AchievementID': id,
      'Title': 'Conquista $id',
      'Description': 'teste',
      'Points': 10,
      'BadgeName': '$id',
      'GameID': 1,
      'GameTitle': 'Jogo',
      'ConsoleName': 'SNES',
      'Date': '2026-10-23 12:00:00',
      'HardcoreMode': hc ? 1 : 0,
    });

/// API simulada: devolve o que o teste colocar em [unlocks].
class FakeRaClient extends RaClient {
  FakeRaClient() : super(apiKey: 'k');
  List<RaUnlock> unlocks = [];

  @override
  Future<RaProfile> profile(String user) async => RaProfile.fromJson({'User': user, 'TotalPoints': 100});
  @override
  Future<int?> rank(String user) async => 42;
  @override
  Future<List<RaUnlock>> recentUnlocks(String user, {int minutes = 60}) async => unlocks;
  @override
  Future<List<RaRecentGame>> recentGames(String user, {int count = 12}) async => const [];
  @override
  Future<RaAchievementOfWeek> achievementOfTheWeek() async => RaAchievementOfWeek.fromJson(const {});
}

void main() {
  late SettingsService settings;

  setUp(() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.delete('settings');
    settings = SettingsService(SettingsDao(db));
    await settings.load();
  });

  test('datas da API (UTC sem fuso e ISO) viram horário local', () {
    expect(raDate('2026-10-10 01:12:33'), DateTime.utc(2026, 10, 10, 1, 12, 33).toLocal());
    expect(raDate('2026-10-19T00:00:00.000000Z'), DateTime.utc(2026, 10, 19).toLocal());
    expect(raDate(null), isNull);
  });

  test('progresso do jogo: desbloqueadas primeiro e badge cinza nas bloqueadas', () {
    final p = RaGameProgress.fromJson({
      'ID': 1,
      'Title': 'Jogo',
      'Achievements': {
        '1': {'ID': 1, 'Title': 'A', 'Points': 5, 'BadgeName': '100', 'DisplayOrder': 1},
        '2': {'ID': 2, 'Title': 'B', 'Points': 10, 'BadgeName': '200', 'DisplayOrder': 2, 'DateEarned': '2026-10-01 10:00:00'},
      },
    });
    expect(p.achievements.first.title, 'B');
    expect(p.earned, 1);
    expect(p.earnedPoints, 10);
    expect(p.totalPoints, 15);
    expect(p.achievements.last.badgeUrl(), endsWith('/Badge/100_lock.png'));
  });

  test('tempo real: avisa só desbloqueios novos, com o badge', () async {
    final fake = FakeRaClient()..unlocks = [unlock(1)];
    final notifications = NotificationService();
    final svc = AchievementService(settings, notifications, clientFactory: (_) => fake);

    expect(await svc.login('jogador', 'chave'), isNull);
    expect(svc.profile!.rank, 42);
    expect(notifications.items, isEmpty, reason: 'o que já existia no login não gera aviso');

    await svc.poll();
    expect(notifications.items, isEmpty);

    fake.unlocks = [unlock(2), unlock(1)];
    await svc.poll();
    expect(notifications.items, hasLength(1));
    expect(notifications.items.single.body, contains('Conquista 2'));
    expect(notifications.items.single.imageUrl, endsWith('/Badge/2.png'));

    await svc.poll();
    expect(notifications.items, hasLength(1), reason: 'não repete o mesmo desbloqueio');
    svc.logout();
    expect(settings.raApiKey, isEmpty);
  });

  // Rode com: RA_USER=<usuario> RA_KEY=<chave> flutter test test/achievements_test.dart
  test('API real do RetroAchievements', () async {
    final client = RaClient(apiKey: Platform.environment['RA_KEY']!);
    final user = Platform.environment['RA_USER'] ?? 'MaxMilyin';
    final p = await client.profile(user);
    expect(p.points, greaterThan(0));
    final games = await client.recentGames(user, count: 3);
    expect(games, isNotEmpty);
    final progress = await client.gameProgress(games.first.id, user);
    expect(progress.achievements, isNotEmpty);
    expect(progress.earned, games.first.earned);
    final aotw = await client.achievementOfTheWeek();
    expect(aotw.title, isNotEmpty);
    await expectLater(RaClient(apiKey: 'chave-invalida').profile(user), throwsA(isA<RaException>().having((e) => e.unauthorized, 'unauthorized', true)));
  }, skip: Platform.environment['RA_KEY'] == null, timeout: const Timeout(Duration(minutes: 1)));
}
