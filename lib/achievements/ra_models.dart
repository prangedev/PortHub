/// Modelos da Web API do RetroAchievements (https://api-docs.retroachievements.org).
library;

const raSite = 'https://retroachievements.org';
const raMedia = 'https://media.retroachievements.org';

/// Datas da API vêm como "2026-10-10 01:12:33" (UTC) ou ISO 8601.
DateTime? raDate(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final iso = s.contains('T') ? s : '${s.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(iso)?.toLocal();
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

String raBadgeUrl(String badgeName, {bool locked = false}) => '$raMedia/Badge/$badgeName${locked ? '_lock' : ''}.png';

String? raImageUrl(Object? path) {
  final p = '${path ?? ''}';
  if (p.isEmpty || p == 'null') return null;
  return p.startsWith('http') ? p : '$raMedia$p';
}

class RaProfile {
  const RaProfile({
    required this.user,
    required this.ulid,
    required this.userPic,
    required this.points,
    required this.softcorePoints,
    required this.truePoints,
    this.motto = '',
    this.richPresence = '',
    this.lastGameId,
    this.memberSince,
    this.rank,
  });

  final String user;
  final String ulid;
  final String userPic;
  final int points;
  final int softcorePoints;
  final int truePoints;
  final String motto;
  final String richPresence;
  final int? lastGameId;
  final DateTime? memberSince;
  final int? rank;

  factory RaProfile.fromJson(Map<String, dynamic> j) => RaProfile(
        user: '${j['User']}',
        ulid: '${j['ULID'] ?? ''}',
        userPic: raImageUrl(j['UserPic']) ?? '$raMedia/UserPic/${j['User']}.png',
        points: _int(j['TotalPoints']),
        softcorePoints: _int(j['TotalSoftcorePoints']),
        truePoints: _int(j['TotalTruePoints']),
        motto: '${j['Motto'] ?? ''}',
        richPresence: '${j['RichPresenceMsg'] ?? ''}',
        lastGameId: j['LastGameID'] == null ? null : _int(j['LastGameID']),
        memberSince: raDate(j['MemberSince']),
        rank: j['Rank'] == null ? null : _int(j['Rank']),
      );
}

/// Uma conquista desbloqueada (conquistas recentes do usuário).
class RaUnlock {
  const RaUnlock({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.badgeName,
    required this.gameId,
    required this.gameTitle,
    required this.consoleName,
    required this.date,
    this.hardcore = false,
    this.trueRatio = 0,
    this.gameIcon,
  });

  final int id;
  final String title;
  final String description;
  final int points;
  final int trueRatio;
  final String badgeName;
  final int gameId;
  final String gameTitle;
  final String? gameIcon;
  final String consoleName;
  final DateTime? date;
  final bool hardcore;

  String get badgeUrl => raBadgeUrl(badgeName);
  String get key => '$id:${hardcore ? 'h' : 's'}';

  factory RaUnlock.fromJson(Map<String, dynamic> j) => RaUnlock(
        id: _int(j['AchievementID']),
        title: '${j['Title']}',
        description: '${j['Description'] ?? ''}',
        points: _int(j['Points']),
        trueRatio: _int(j['TrueRatio']),
        badgeName: '${j['BadgeName']}',
        gameId: _int(j['GameID']),
        gameTitle: '${j['GameTitle'] ?? ''}',
        gameIcon: raImageUrl(j['GameIcon']),
        consoleName: '${j['ConsoleName'] ?? ''}',
        date: raDate(j['Date']),
        hardcore: _int(j['HardcoreMode']) == 1,
      );
}

/// Jogo jogado recentemente, com o progresso resumido.
class RaRecentGame {
  const RaRecentGame({
    required this.id,
    required this.title,
    required this.consoleName,
    required this.total,
    required this.earned,
    required this.earnedHardcore,
    required this.possibleScore,
    required this.scoreEarned,
    this.icon,
    this.boxArt,
    this.lastPlayed,
  });

  final int id;
  final String title;
  final String consoleName;
  final String? icon;
  final String? boxArt;
  final DateTime? lastPlayed;
  final int total;
  final int earned;
  final int earnedHardcore;
  final int possibleScore;
  final int scoreEarned;

  double get completion => total == 0 ? 0 : earned / total;

  factory RaRecentGame.fromJson(Map<String, dynamic> j) => RaRecentGame(
        id: _int(j['GameID']),
        title: '${j['Title']}',
        consoleName: '${j['ConsoleName'] ?? ''}',
        icon: raImageUrl(j['ImageIcon']),
        boxArt: raImageUrl(j['ImageBoxArt']),
        lastPlayed: raDate(j['LastPlayed']),
        total: _int(j['AchievementsTotal'] ?? j['NumPossibleAchievements']),
        earned: _int(j['NumAchieved']),
        earnedHardcore: _int(j['NumAchievedHardcore']),
        possibleScore: _int(j['PossibleScore']),
        scoreEarned: _int(j['ScoreAchieved']),
      );
}

/// Conquista dentro do progresso de um jogo.
class RaGameAchievement {
  const RaGameAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.badgeName,
    required this.displayOrder,
    required this.numAwarded,
    this.type,
    this.earned,
    this.earnedHardcore,
  });

  final int id;
  final String title;
  final String description;
  final int points;
  final String badgeName;
  final int displayOrder;
  final int numAwarded;
  final String? type;
  final DateTime? earned;
  final DateTime? earnedHardcore;

  bool get unlocked => earned != null || earnedHardcore != null;
  String badgeUrl() => raBadgeUrl(badgeName, locked: !unlocked);

  factory RaGameAchievement.fromJson(Map<String, dynamic> j) => RaGameAchievement(
        id: _int(j['ID']),
        title: '${j['Title']}',
        description: '${j['Description'] ?? ''}',
        points: _int(j['Points']),
        badgeName: '${j['BadgeName']}',
        displayOrder: _int(j['DisplayOrder']),
        numAwarded: _int(j['NumAwarded']),
        type: j['Type'] as String?,
        earned: raDate(j['DateEarned']),
        earnedHardcore: raDate(j['DateEarnedHardcore']),
      );
}

class RaGameProgress {
  const RaGameProgress({
    required this.id,
    required this.title,
    required this.consoleName,
    required this.achievements,
    required this.players,
    this.icon,
    this.boxArt,
    this.ingame,
    this.developer,
    this.genre,
    this.released,
  });

  final int id;
  final String title;
  final String consoleName;
  final String? icon;
  final String? boxArt;
  final String? ingame;
  final String? developer;
  final String? genre;
  final String? released;
  final int players;
  final List<RaGameAchievement> achievements;

  int get earned => achievements.where((a) => a.unlocked).length;
  int get earnedHardcore => achievements.where((a) => a.earnedHardcore != null).length;
  int get totalPoints => achievements.fold(0, (s, a) => s + a.points);
  int get earnedPoints => achievements.where((a) => a.unlocked).fold(0, (s, a) => s + a.points);
  double get completion => achievements.isEmpty ? 0 : earned / achievements.length;

  factory RaGameProgress.fromJson(Map<String, dynamic> j) {
    final raw = j['Achievements'];
    final list = raw is Map ? raw.values : (raw is List ? raw : const []);
    final achievements = [
      for (final a in list) RaGameAchievement.fromJson((a as Map).cast<String, dynamic>()),
    ]..sort((a, b) {
        // Desbloqueadas primeiro (mais recentes antes), depois a ordem do jogo.
        if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
        if (a.unlocked) {
          final da = a.earnedHardcore ?? a.earned!;
          final db = b.earnedHardcore ?? b.earned!;
          return db.compareTo(da);
        }
        return a.displayOrder.compareTo(b.displayOrder);
      });
    return RaGameProgress(
      id: _int(j['ID']),
      title: '${j['Title']}',
      consoleName: '${j['ConsoleName'] ?? ''}',
      icon: raImageUrl(j['ImageIcon']),
      boxArt: raImageUrl(j['ImageBoxArt']),
      ingame: raImageUrl(j['ImageIngame']),
      developer: j['Developer'] as String?,
      genre: j['Genre'] as String?,
      released: j['Released'] as String?,
      players: _int(j['NumDistinctPlayers']),
      achievements: achievements,
    );
  }
}

/// Conquista da semana (evento do site).
class RaAchievementOfWeek {
  const RaAchievementOfWeek({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.badgeName,
    required this.gameId,
    required this.gameTitle,
    required this.consoleName,
    required this.totalPlayers,
    required this.unlocks,
    required this.unlockedBy,
    this.startAt,
  });

  final int id;
  final String title;
  final String description;
  final int points;
  final String badgeName;
  final int gameId;
  final String gameTitle;
  final String consoleName;
  final int totalPlayers;
  final int unlocks;

  /// Usuários que desbloquearam (a API devolve os últimos 500).
  final Set<String> unlockedBy;
  final DateTime? startAt;

  String get badgeUrl => raBadgeUrl(badgeName);

  factory RaAchievementOfWeek.fromJson(Map<String, dynamic> j) {
    final a = (j['Achievement'] as Map?)?.cast<String, dynamic>() ?? const {};
    final g = (j['Game'] as Map?)?.cast<String, dynamic>() ?? const {};
    final c = (j['Console'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RaAchievementOfWeek(
      id: _int(a['ID']),
      title: '${a['Title'] ?? ''}',
      description: '${a['Description'] ?? ''}',
      points: _int(a['Points']),
      badgeName: '${a['BadgeName'] ?? ''}',
      gameId: _int(g['ID']),
      gameTitle: '${g['Title'] ?? ''}',
      consoleName: '${c['Title'] ?? ''}',
      totalPlayers: _int(j['TotalPlayers']),
      unlocks: _int(j['UnlocksCount']),
      unlockedBy: {
        for (final u in ((j['Unlocks'] as List?) ?? const []).cast<Map>()) '${u['User']}'.toLowerCase(),
      },
      startAt: raDate(j['StartAt']),
    );
  }
}
