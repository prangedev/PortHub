import '../core/formatters.dart';
import '../core/models/compatibility_result.dart';
import '../core/models/game_requirements.dart';
import '../core/models/hardware_profile.dart';
import '../core/models/release_info.dart';
import '../core/platform_info.dart';
import 'hardware_tiers.dart';

/// Motor de compatibilidade.
///
/// Fluxo: hardware detectado + requisitos (porthub.yaml / catálogo / README)
/// + assets da última release → verificações individuais → score 0–100 → nível.
///
/// Pesos do score: CPU 20, GPU 20, RAM 25, API gráfica 15, Arquitetura 20.
/// Qualquer verificação "fail" torna o jogo Incompatível (score limitado a 35)
/// e o primeiro motivo é exibido exatamente ao usuário.
class CompatibilityEngine {
  const CompatibilityEngine();

  CompatibilityResult evaluate({
    required GameRequirements req,
    required HardwareProfile hw,
    List<ReleaseAsset> assets = const [],
    ReleaseAsset? bestAsset,
  }) {
    const noReleaseInfo = 'Sem informações de release para avaliar.';
    final checks = <CompatCheck>[];
    final points = <String, double>{};
    String? blocking;

    void fail(String label, String reason) {
      checks.add(CompatCheck(label, CheckStatus.fail, reason));
      blocking ??= reason;
    }

    final platform = hw.platform;
    final deviceArchs = hw.abis;
    final platformName = platformLabel(platform);

    // 1. Plataforma ------------------------------------------------------------
    final hasPlatformAsset = assets.any((a) => a.installable && a.platform.name == platform) ||
        (bestAsset != null && bestAsset.platform == AssetPlatform.unknown);
    if (req.platforms.isNotEmpty && !req.platforms.contains(platform)) {
      fail('Plataforma', 'Disponível apenas para ${req.platforms.map(platformLabel).join(', ')}.');
    } else if (assets.isNotEmpty && bestAsset == null && !hasPlatformAsset) {
      fail('Plataforma', 'A última release não tem arquivo para $platformName.');
    } else if (assets.isEmpty && req.platforms.isEmpty) {
      checks.add(const CompatCheck('Plataforma', CheckStatus.unknown, noReleaseInfo));
    } else {
      checks.add(CompatCheck('Plataforma', CheckStatus.pass, '$platformName suportado'));
    }

    // 2. Arquitetura (20) -----------------------------------------------------
    final assetArchs = assets
        .where((a) => a.platform.name == platform && a.arch != null && a.installable)
        .map((a) => a.arch!)
        .toSet();
    final requiredArchs = req.architectures.isNotEmpty ? req.architectures.toSet() : assetArchs;
    final deviceLabel = archLabel(hw.primaryArch);
    if (requiredArchs.isEmpty) {
      points['Arquitetura'] = 1;
      checks.add(CompatCheck('Arquitetura', CheckStatus.pass, '$deviceLabel compatível'));
    } else if (deviceArchs.isNotEmpty && requiredArchs.contains(deviceArchs.first)) {
      points['Arquitetura'] = 1;
      checks.add(CompatCheck('Arquitetura', CheckStatus.pass, '$deviceLabel compatível'));
    } else if (deviceArchs.any(requiredArchs.contains)) {
      // Ex.: aparelho ARM64 rodando build ARMv7 (32 bits) — funciona, mas não é o ideal.
      final used = deviceArchs.firstWhere(requiredArchs.contains);
      points['Arquitetura'] = 0.7;
      checks.add(CompatCheck('Arquitetura', CheckStatus.warn, 'Usará a build ${archLabel(used)} (modo compatível)'));
    } else if (platform == 'windows' && hw.primaryArch == 'arm64' && requiredArchs.contains('x86_64')) {
      points['Arquitetura'] = 0.5;
      checks.add(const CompatCheck('Arquitetura', CheckStatus.warn, 'Build x86_64 rodará via emulação no Windows ARM'));
    } else {
      points['Arquitetura'] = 0;
      final need = requiredArchs.map(archLabel).join(' ou ');
      fail('Arquitetura', 'Requer $need e seu aparelho é $deviceLabel.');
    }

    // 3. Versão do sistema -----------------------------------------------------
    if (platform == 'android' && req.minAndroid != null) {
      final current = hw.osVersionNumber;
      final need = _fmtVer(req.minAndroid!);
      if (current == null) {
        checks.add(CompatCheck('Android', CheckStatus.unknown, 'Requer Android $need+'));
      } else if (current + 0.001 >= req.minAndroid!) {
        checks.add(CompatCheck('Android', CheckStatus.pass, 'Android ${_fmtVer(current)} acima do mínimo ($need)'));
      } else {
        fail('Android', 'Requer Android $need+ e seu aparelho tem Android ${_fmtVer(current)}.');
      }
    }

    // 4. RAM (25) ---------------------------------------------------------------
    final ram = hw.ramMb;
    final minRam = req.minRamMb;
    if (minRam == null) {
      points['RAM'] = ram == null ? 0.8 : (ram >= 4096 ? 1 : ram >= 2048 ? 0.85 : 0.6);
      if (ram != null) checks.add(CompatCheck('RAM', CheckStatus.pass, '${formatRamMb(ram)} disponíveis'));
    } else if (ram == null) {
      points['RAM'] = 0.6;
      checks.add(CompatCheck('RAM', CheckStatus.unknown, 'Requer ${formatRamMb(minRam)}'));
    } else {
      // O sistema reporta um pouco menos que o valor comercial (8 GB → ~7,4 GB).
      final effective = ram * 1.1;
      final recommended = req.recommendedRamMb ?? (minRam * 1.5).round();
      if (effective >= recommended) {
        points['RAM'] = 1;
        checks.add(CompatCheck('RAM', CheckStatus.pass, 'RAM suficiente (${formatRamMb(ram)} / mín. ${formatRamMb(minRam)})'));
      } else if (effective >= minRam) {
        points['RAM'] = 0.8;
        checks.add(CompatCheck('RAM', CheckStatus.pass, 'RAM suficiente (${formatRamMb(ram)} / mín. ${formatRamMb(minRam)})'));
      } else if (effective >= minRam * 0.75) {
        points['RAM'] = 0.45;
        checks.add(CompatCheck('RAM', CheckStatus.warn,
            'RAM abaixo do recomendado (${formatRamMb(ram)} / mín. ${formatRamMb(minRam)}) — pode travar'));
      } else {
        points['RAM'] = 0;
        fail('RAM', 'Requer ${formatRamMb(minRam)} de RAM e seu aparelho tem ${formatRamMb(ram)}.');
      }
    }

    // 5. API gráfica (15): Vulkan / OpenGL ES / OpenGL / DirectX ----------------
    var api = 1.0;
    var apiDeclared = false;
    if (req.vulkan == true) {
      apiDeclared = true;
      if (hw.vulkan) {
        checks.add(CompatCheck('Vulkan', CheckStatus.pass, 'Vulkan suportado${hw.vulkanVersion != null ? ' (${hw.vulkanVersion})' : ''}'));
      } else {
        api = 0;
        fail('Vulkan', 'Requer Vulkan e sua GPU (${hw.gpuName ?? 'desconhecida'}) não oferece suporte.');
      }
    } else if (hw.vulkan) {
      checks.add(CompatCheck('Vulkan', CheckStatus.pass, 'Vulkan suportado${hw.vulkanVersion != null ? ' (${hw.vulkanVersion})' : ''}'));
    }
    if (req.minGlEs != null && platform == 'android') {
      apiDeclared = true;
      final have = hw.glEsVersion;
      if (have == null) {
        api *= 0.8;
        checks.add(CompatCheck('OpenGL ES', CheckStatus.unknown, 'Requer OpenGL ES ${_fmtVer(req.minGlEs!)}'));
      } else if (have + 0.001 >= req.minGlEs!) {
        checks.add(CompatCheck('OpenGL ES', CheckStatus.pass, 'OpenGL ES ${_fmtVer(have)} (mín. ${_fmtVer(req.minGlEs!)})'));
      } else {
        api = 0;
        fail('OpenGL ES', 'Requer OpenGL ES ${_fmtVer(req.minGlEs!)} e seu aparelho suporta ${_fmtVer(have)}.');
      }
    }
    if (req.minOpenGl != null && platform != 'android') {
      apiDeclared = true;
      final have = hw.openGlVersion;
      if (have == null) {
        api *= 0.8;
        checks.add(CompatCheck('OpenGL', CheckStatus.unknown, 'Requer OpenGL ${_fmtVer(req.minOpenGl!)}'));
      } else if (have + 0.001 >= req.minOpenGl!) {
        checks.add(CompatCheck('OpenGL', CheckStatus.pass, 'OpenGL ${_fmtVer(have)} (mín. ${_fmtVer(req.minOpenGl!)})'));
      } else {
        api = 0;
        fail('OpenGL', 'Requer OpenGL ${_fmtVer(req.minOpenGl!)} e sua GPU suporta ${_fmtVer(have)}.');
      }
    }
    if (req.minDirectX != null && platform == 'windows') {
      apiDeclared = true;
      final have = hw.directX;
      if (have != null && have < req.minDirectX!) {
        api = 0;
        fail('DirectX', 'Requer DirectX ${req.minDirectX} e seu sistema tem DirectX $have.');
      } else {
        checks.add(CompatCheck('DirectX', CheckStatus.pass, 'DirectX ${have ?? '?'} (mín. ${req.minDirectX})'));
      }
    }
    points['API gráfica'] = apiDeclared ? api : (hw.vulkan ? 1 : 0.85);

    // 6/7. CPU e GPU (20 + 20) ---------------------------------------------------
    final (cpu, cpuKnown) = HardwareTiers.cpuTier(hw);
    final (gpu, gpuKnown) = HardwareTiers.gpuTier(hw);
    final needCpu = req.cpuTier ?? 30;
    final needGpu = req.gpuTier ?? 30;
    points['CPU'] = _tierFactor(cpu, needCpu);
    points['GPU'] = _tierFactor(gpu, needGpu);
    checks.add(_tierCheck('CPU', hw.cpuName ?? hw.socModel, cpu, needCpu, cpuKnown));
    checks.add(_tierCheck('GPU', hw.gpuName, gpu, needGpu, gpuKnown));

    // 8. Armazenamento -----------------------------------------------------------
    final needStorage = req.minStorageMb ?? (bestAsset != null ? (bestAsset.size * 2.2 / (1024 * 1024)).ceil() : null);
    if (needStorage != null && hw.freeStorageMb != null) {
      if (hw.freeStorageMb! >= needStorage) {
        checks.add(CompatCheck('Armazenamento', CheckStatus.pass, '${formatRamMb(hw.freeStorageMb)} livres'));
      } else if (bestAsset != null && hw.freeStorageMb! * 1024 * 1024 < bestAsset.size) {
        fail('Armazenamento', 'Precisa de ${formatRamMb(needStorage)} livres e há apenas ${formatRamMb(hw.freeStorageMb)}.');
      } else {
        checks.add(CompatCheck('Armazenamento', CheckStatus.warn,
            'Espaço apertado: ${formatRamMb(hw.freeStorageMb)} livres (recomendado ${formatRamMb(needStorage)})'));
      }
    }

    // Score ----------------------------------------------------------------------
    final breakdown = <String, int>{};
    var score = 0;
    CompatibilityResult.maxBreakdown.forEach((key, max) {
      final v = ((points[key] ?? 0.8) * max).round();
      breakdown[key] = v;
      score += v;
    });

    final hasFail = checks.any((c) => c.status == CheckStatus.fail);
    final hasWarn = checks.any((c) => c.status == CheckStatus.warn);
    if (hasFail) score = score.clamp(0, 35);

    // Sem release e sem plataformas declaradas não há como afirmar compatibilidade.
    final noData = assets.isEmpty && req.platforms.isEmpty;
    final level = hasFail
        ? CompatLevel.incompatible
        : hasWarn
            ? CompatLevel.partial
            : noData
                ? CompatLevel.unknown
                : score < 75
                    ? CompatLevel.partial
                    : CompatLevel.compatible;

    return CompatibilityResult(
      level: level,
      score: score,
      message: hasFail ? blocking! : level == CompatLevel.unknown ? noReleaseInfo : level.defaultMessage,
      checks: checks,
      breakdown: breakdown,
      blockingReason: blocking,
      estimated: req.isEmpty,
    );
  }

  /// 1.0 quando o hardware atinge (ou supera) o nível pedido, caindo de forma
  /// linear abaixo disso.
  static double _tierFactor(int have, int need) {
    if (have >= need + 15) return 1;
    if (have >= need) return 0.85 + (have - need) / 100;
    return (0.85 - (need - have) / 40).clamp(0.0, 0.85);
  }

  static CompatCheck _tierCheck(String label, String? chip, int have, int need, bool known) {
    final name = chip ?? 'desconhecida';
    final est = known ? '' : ' (estimado)';
    if (have >= need) return CompatCheck(label, CheckStatus.pass, '$name — desempenho $have/100$est');
    if (have >= need - 20) {
      return CompatCheck(label, CheckStatus.warn, '$name abaixo do recomendado ($have/$need)$est — pode haver queda de FPS');
    }
    return CompatCheck(label, CheckStatus.warn, '$name bem abaixo do recomendado ($have/$need)$est');
  }

  static String _fmtVer(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
