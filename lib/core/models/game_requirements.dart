import '../platform_info.dart';

/// Requisitos de um jogo. Podem vir de três fontes (em ordem de prioridade):
/// 1. `porthub.yaml` na raiz do repositório (declaração oficial do porter);
/// 2. o catálogo/provedor (ex.: lista JSON comunitária);
/// 3. heurísticas sobre o README.
class GameRequirements {
  const GameRequirements({
    this.minRamMb,
    this.recommendedRamMb,
    this.architectures = const [],
    this.platforms = const [],
    this.minAndroid,
    this.vulkan,
    this.minGlEs,
    this.minOpenGl,
    this.minDirectX,
    this.minStorageMb,
    this.cpuTier,
    this.gpuTier,
    this.sources = const [],
  });

  final int? minRamMb;
  final int? recommendedRamMb;

  /// Arquiteturas aceitas (normalizadas: arm64, armv7, x86_64, x86). Vazio = qualquer.
  final List<String> architectures;

  /// Plataformas suportadas (android, linux, windows). Vazio = deduzido pelos assets.
  final List<String> platforms;

  /// Versão mínima do Android (ex.: 10.0).
  final double? minAndroid;

  /// `true` = Vulkan obrigatório, `false` = não usa, `null` = não declarado.
  final bool? vulkan;
  final double? minGlEs;
  final double? minOpenGl;
  final int? minDirectX;
  final int? minStorageMb;

  /// Nível mínimo de desempenho esperado (0–100). Ver `hardware_tiers.dart`.
  final int? cpuTier;
  final int? gpuTier;

  /// De onde os dados vieram (porthub.yaml, catálogo, README...).
  final List<String> sources;

  bool get isEmpty =>
      minRamMb == null &&
      architectures.isEmpty &&
      platforms.isEmpty &&
      minAndroid == null &&
      vulkan == null &&
      minGlEs == null &&
      minOpenGl == null &&
      minDirectX == null &&
      minStorageMb == null &&
      cpuTier == null &&
      gpuTier == null;

  /// Completa os campos nulos com os de [fallback] (que tem prioridade menor).
  GameRequirements mergeWith(GameRequirements? fallback) {
    if (fallback == null) return this;
    return GameRequirements(
      minRamMb: minRamMb ?? fallback.minRamMb,
      recommendedRamMb: recommendedRamMb ?? fallback.recommendedRamMb,
      architectures: architectures.isNotEmpty ? architectures : fallback.architectures,
      platforms: platforms.isNotEmpty ? platforms : fallback.platforms,
      minAndroid: minAndroid ?? fallback.minAndroid,
      vulkan: vulkan ?? fallback.vulkan,
      minGlEs: minGlEs ?? fallback.minGlEs,
      minOpenGl: minOpenGl ?? fallback.minOpenGl,
      minDirectX: minDirectX ?? fallback.minDirectX,
      minStorageMb: minStorageMb ?? fallback.minStorageMb,
      cpuTier: cpuTier ?? fallback.cpuTier,
      gpuTier: gpuTier ?? fallback.gpuTier,
      sources: {...sources, ...fallback.sources}.toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Parsing tolerante: aceita "4GB", "512 MB", "10+", "arm64-v8a", [lista]...
  // ---------------------------------------------------------------------------

  /// Constrói a partir de um mapa vindo de YAML (`porthub.yaml`) ou JSON (catálogo).
  factory GameRequirements.fromMap(Map<dynamic, dynamic> m, {String source = 'catálogo'}) {
    return GameRequirements(
      minRamMb: parseSizeMb(m['ram'] ?? m['min_ram'] ?? m['memory']),
      recommendedRamMb: parseSizeMb(m['recommended_ram'] ?? m['ram_recommended']),
      architectures: _list(m['architecture'] ?? m['architectures'] ?? m['arch'] ?? m['abi'])
          .map(normalizeArch)
          .whereType<String>()
          .toSet()
          .toList(),
      platforms: _list(m['platform'] ?? m['platforms']).map((e) => e.toLowerCase()).toList(),
      minAndroid: parseVersion(m['android'] ?? m['min_android']),
      vulkan: _bool(m['vulkan']),
      minGlEs: parseVersion(m['gles'] ?? m['opengl_es'] ?? m['opengles']),
      minOpenGl: parseVersion(m['opengl'] ?? m['gl']),
      minDirectX: parseVersion(m['directx'] ?? m['dx'])?.floor(),
      minStorageMb: parseSizeMb(m['storage'] ?? m['disk']),
      cpuTier: parseTier(m['cpu'] ?? m['cpu_tier']),
      gpuTier: parseTier(m['gpu'] ?? m['gpu_tier']),
      sources: [source],
    );
  }

  Map<String, dynamic> toJson() => {
        if (minRamMb != null) 'ram_mb': minRamMb,
        if (recommendedRamMb != null) 'recommended_ram_mb': recommendedRamMb,
        if (architectures.isNotEmpty) 'architectures': architectures,
        if (platforms.isNotEmpty) 'platforms': platforms,
        if (minAndroid != null) 'android': minAndroid,
        if (vulkan != null) 'vulkan': vulkan,
        if (minGlEs != null) 'gles': minGlEs,
        if (minOpenGl != null) 'opengl': minOpenGl,
        if (minDirectX != null) 'directx': minDirectX,
        if (minStorageMb != null) 'storage_mb': minStorageMb,
        if (cpuTier != null) 'cpu_tier': cpuTier,
        if (gpuTier != null) 'gpu_tier': gpuTier,
        'sources': sources,
      };

  factory GameRequirements.fromJson(Map<String, dynamic> j) => GameRequirements(
        minRamMb: j['ram_mb'] as int?,
        recommendedRamMb: j['recommended_ram_mb'] as int?,
        architectures: (j['architectures'] as List?)?.cast<String>() ?? const [],
        platforms: (j['platforms'] as List?)?.cast<String>() ?? const [],
        minAndroid: (j['android'] as num?)?.toDouble(),
        vulkan: j['vulkan'] as bool?,
        minGlEs: (j['gles'] as num?)?.toDouble(),
        minOpenGl: (j['opengl'] as num?)?.toDouble(),
        minDirectX: j['directx'] as int?,
        minStorageMb: j['storage_mb'] as int?,
        cpuTier: j['cpu_tier'] as int?,
        gpuTier: j['gpu_tier'] as int?,
        sources: (j['sources'] as List?)?.cast<String>() ?? const [],
      );

  static List<String> _list(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return v.toString().split(RegExp(r'[,;/| ]+')).where((s) => s.isNotEmpty).toList();
  }

  static bool? _bool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (['true', 'yes', 'sim', 'required', 'obrigatorio', 'obrigatório', '1'].contains(s)) return true;
    if (['false', 'no', 'nao', 'não', 'optional', 'opcional', '0'].contains(s)) return false;
    return null;
  }

  /// "4GB" → 4096, "512 MB" → 512, 2 → 2048 (números puros são GB).
  static int? parseSizeMb(dynamic v) {
    if (v == null) return null;
    if (v is num) return (v * 1024).round();
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(t|g|m|k)?i?b?', caseSensitive: false).firstMatch(v.toString());
    if (m == null) return null;
    final n = double.parse(m.group(1)!.replaceAll(',', '.'));
    final unit = (m.group(2) ?? 'g').toLowerCase();
    return switch (unit) {
      't' => (n * 1024 * 1024).round(),
      'g' => (n * 1024).round(),
      'm' => n.round(),
      'k' => (n / 1024).ceil(),
      _ => (n * 1024).round(),
    };
  }

  /// "10+", "Android 8.0", 3.2 → número.
  static double? parseVersion(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(v.toString());
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// "low"/"mid"/"high" ou número 0–100.
  static int? parseTier(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.clamp(0, 100).toInt();
    return switch (v.toString().toLowerCase()) {
      'low' || 'baixo' || 'entry' => 30,
      'mid' || 'medio' || 'médio' || 'medium' => 55,
      'high' || 'alto' => 80,
      'ultra' => 92,
      final s => int.tryParse(s),
    };
  }
}
