/// Resultado do motor de compatibilidade.
enum CompatLevel { compatible, partial, incompatible, unknown }

enum CheckStatus { pass, warn, fail, unknown }

extension CompatLevelText on CompatLevel {
  String get label => switch (this) {
        CompatLevel.compatible => 'Compatível',
        CompatLevel.partial => 'Parcialmente compatível',
        CompatLevel.incompatible => 'Incompatível',
        CompatLevel.unknown => 'Não avaliado',
      };

  String get defaultMessage => switch (this) {
        CompatLevel.compatible => 'Funciona perfeitamente no seu aparelho.',
        CompatLevel.partial => 'Pode apresentar queda de desempenho.',
        CompatLevel.incompatible => 'Não é compatível com o seu aparelho.',
        CompatLevel.unknown => 'Ainda não avaliado.',
      };
}

/// Uma verificação individual (ex.: "RAM suficiente").
class CompatCheck {
  const CompatCheck(this.label, this.status, [this.detail = '']);
  final String label;
  final CheckStatus status;
  final String detail;

  Map<String, dynamic> toJson() => {'label': label, 'status': status.name, 'detail': detail};
  factory CompatCheck.fromJson(Map<String, dynamic> j) => CompatCheck(
        j['label'] as String? ?? '',
        CheckStatus.values.asNameMap()[j['status']] ?? CheckStatus.unknown,
        j['detail'] as String? ?? '',
      );
}

class CompatibilityResult {
  const CompatibilityResult({
    required this.level,
    required this.score,
    required this.message,
    this.checks = const [],
    this.breakdown = const {},
    this.blockingReason,
    this.estimated = false,
  });

  static const unknown = CompatibilityResult(level: CompatLevel.unknown, score: 0, message: 'Ainda não avaliado.');

  final CompatLevel level;

  /// Pontuação 0–100.
  final int score;
  final String message;
  final List<CompatCheck> checks;

  /// Pontos obtidos por componente: {'CPU': 18, 'GPU': 15, ...} (de [maxBreakdown]).
  final Map<String, int> breakdown;

  /// Motivo exato da incompatibilidade (ex.: "Requer ARM64 e seu aparelho é ARMv7.").
  final String? blockingReason;

  /// `true` quando o repositório não declarou requisitos e a avaliação é estimada.
  final bool estimated;

  static const maxBreakdown = {'CPU': 20, 'GPU': 20, 'RAM': 25, 'API gráfica': 15, 'Arquitetura': 20};

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'score': score,
        'message': message,
        'checks': checks.map((c) => c.toJson()).toList(),
        'breakdown': breakdown,
        'blocking': blockingReason,
        'estimated': estimated,
      };

  factory CompatibilityResult.fromJson(Map<String, dynamic> j) => CompatibilityResult(
        level: CompatLevel.values.asNameMap()[j['level']] ?? CompatLevel.unknown,
        score: (j['score'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
        checks: ((j['checks'] as List?) ?? const [])
            .map((e) => CompatCheck.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        breakdown: ((j['breakdown'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        blockingReason: j['blocking'] as String?,
        estimated: j['estimated'] as bool? ?? false,
      );
}
