/// PortHub Compatibility Database — relatos comunitários (inspirado no ProtonDB).
enum CommunityRating { platinum, gold, silver, bronze, borked }

extension CommunityRatingText on CommunityRating {
  String get label => switch (this) {
        CommunityRating.platinum => 'Platina',
        CommunityRating.gold => 'Ouro',
        CommunityRating.silver => 'Prata',
        CommunityRating.bronze => 'Bronze',
        CommunityRating.borked => 'Quebrado',
      };

  String get performanceWord => switch (this) {
        CommunityRating.platinum => 'excelente',
        CommunityRating.gold => 'muito bom',
        CommunityRating.silver => 'razoável, com pequenos problemas',
        CommunityRating.bronze => 'fraco, com problemas frequentes',
        CommunityRating.borked => 'que o jogo não funciona',
      };

  /// Valor numérico para médias (platina = 5 ... quebrado = 1).
  int get value => 5 - index;
}

class CommunityReport {
  CommunityReport({
    required this.gameId,
    required this.platform,
    required this.deviceModel,
    required this.rating,
    this.soc,
    this.gpu,
    this.ramMb,
    this.osVersion,
    this.fps,
    this.issues = const [],
    this.notes = '',
    this.gameVersion,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String gameId;
  final String platform;
  final String deviceModel;
  final String? soc;
  final String? gpu;
  final int? ramMb;
  final String? osVersion;
  final CommunityRating rating;
  final double? fps;
  final List<String> issues;
  final String notes;
  final String? gameVersion;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'game_id': gameId,
        'platform': platform,
        'device_model': deviceModel,
        'soc': soc,
        'gpu': gpu,
        'ram_mb': ramMb,
        'os_version': osVersion,
        'rating': rating.name,
        'fps': fps,
        'issues': issues,
        'notes': notes,
        'game_version': gameVersion,
        'created_at': createdAt.toIso8601String(),
      };

  factory CommunityReport.fromJson(Map<String, dynamic> j) => CommunityReport(
        gameId: j['game_id'] as String? ?? '',
        platform: j['platform'] as String? ?? '',
        deviceModel: j['device_model'] as String? ?? 'Desconhecido',
        soc: j['soc'] as String?,
        gpu: j['gpu'] as String?,
        ramMb: (j['ram_mb'] as num?)?.toInt(),
        osVersion: j['os_version'] as String?,
        rating: CommunityRating.values.asNameMap()[j['rating']] ?? CommunityRating.silver,
        fps: (j['fps'] as num?)?.toDouble(),
        issues: (j['issues'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        notes: j['notes'] as String? ?? '',
        gameVersion: j['game_version'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}

/// Agregado exibido na tela do jogo.
class CommunitySummary {
  const CommunitySummary({
    required this.total,
    required this.similarCount,
    this.rating,
    this.averageFps,
    this.mostTestedDevice,
    this.knownIssues = const [],
    this.message = '',
  });

  static const empty = CommunitySummary(total: 0, similarCount: 0, message: 'Ainda não há relatos para este jogo.');

  final int total;
  final int similarCount;
  final CommunityRating? rating;
  final double? averageFps;
  final String? mostTestedDevice;
  final List<String> knownIssues;
  final String message;
}
