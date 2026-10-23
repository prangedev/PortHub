import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/compatibility/compatibility_engine.dart';
import 'package:porthub/compatibility/hardware_tiers.dart';
import 'package:porthub/core/models/compatibility_result.dart';
import 'package:porthub/core/models/game_requirements.dart';
import 'package:porthub/core/models/hardware_profile.dart';
import 'package:porthub/core/models/release_info.dart';

/// Aparelho do exemplo da especificação: Snapdragon 778G / Adreno 642L / 8 GB / Android 13.
HardwareProfile phone778g({List<String> abis = const ['arm64', 'armv7']}) => HardwareProfile(
      platform: 'android',
      model: 'Galaxy A73',
      manufacturer: 'Samsung',
      osVersion: '13',
      abis: abis,
      ramMb: 7600,
      cpuName: 'Qualcomm Snapdragon 778G',
      socModel: 'SM7325',
      gpuName: 'Adreno (TM) 642L',
      vulkan: true,
      vulkanVersion: '1.1',
      glEsVersion: 3.2,
      freeStorageMb: 40000,
    );

const apkArm64 = ReleaseAsset(
  name: 'game-arm64-v8a.apk',
  url: 'https://example/a.apk',
  size: 150 * 1024 * 1024,
  kind: AssetKind.apk,
  platform: AssetPlatform.android,
  arch: 'arm64',
);

void main() {
  const engine = CompatibilityEngine();

  test('exemplo da especificação: compatível com score alto', () {
    final req = GameRequirements.fromMap({'ram': '4GB', 'architecture': 'arm64-v8a', 'android': '10+', 'vulkan': true});
    final r = engine.evaluate(req: req, hw: phone778g(), assets: const [apkArm64], bestAsset: apkArm64);
    expect(r.level, CompatLevel.compatible);
    expect(r.score, greaterThanOrEqualTo(85));
    expect(r.checks.where((c) => c.status == CheckStatus.pass).map((c) => c.label), containsAll(['RAM', 'Vulkan', 'Arquitetura', 'Android']));
  });

  test('ARM64 exigido em aparelho ARMv7 mostra o motivo exato', () {
    final req = GameRequirements.fromMap({'architecture': 'arm64-v8a'});
    final r = engine.evaluate(req: req, hw: phone778g(abis: const ['armv7']), assets: const [apkArm64]);
    expect(r.level, CompatLevel.incompatible);
    expect(r.blockingReason, 'Requer ARM64 e seu aparelho é ARMv7.');
    expect(r.score, lessThanOrEqualTo(35));
  });

  test('Android abaixo do mínimo é incompatível', () {
    final hw = HardwareProfile(platform: 'android', osVersion: '9', abis: const ['arm64'], ramMb: 8000);
    final r = engine.evaluate(req: GameRequirements.fromMap({'android': '10+'}), hw: hw);
    expect(r.level, CompatLevel.incompatible);
    expect(r.blockingReason, contains('Android 10+'));
  });

  test('RAM um pouco abaixo vira parcialmente compatível', () {
    final low = HardwareProfile.fromJson({...phone778g().toJson(), 'ram_mb': 3000});
    final r = engine.evaluate(req: GameRequirements.fromMap({'ram': '4GB'}), hw: low);
    expect(r.level, CompatLevel.partial);
  });

  test('Vulkan obrigatório sem suporte', () {
    final hw = HardwareProfile.fromJson({...phone778g().toJson(), 'vulkan': false});
    final r = engine.evaluate(req: GameRequirements.fromMap({'vulkan': 'required'}), hw: hw);
    expect(r.level, CompatLevel.incompatible);
    expect(r.blockingReason, startsWith('Requer Vulkan'));
  });

  test('release sem arquivo para a plataforma', () {
    const exe = ReleaseAsset(name: 'game-win64.zip', url: '', size: 1, kind: AssetKind.zip, platform: AssetPlatform.windows, arch: 'x86_64');
    final r = engine.evaluate(req: const GameRequirements(), hw: phone778g(), assets: const [exe]);
    expect(r.level, CompatLevel.incompatible);
    expect(r.blockingReason, contains('Android'));
  });

  test('tiers reconhecem Snapdragon 778G e Adreno 642L', () {
    final (cpu, cpuKnown) = HardwareTiers.cpuTier(phone778g());
    final (gpu, gpuKnown) = HardwareTiers.gpuTier(phone778g());
    expect(cpuKnown && gpuKnown, isTrue);
    expect(cpu, inInclusiveRange(60, 80));
    expect(gpu, inInclusiveRange(60, 80));
  });

  test('tiers desktop', () {
    final (rtx, _) = HardwareTiers.gpuTier(HardwareProfile(platform: 'windows', gpuName: 'NVIDIA GeForce RTX 4070'));
    final (igpu, _) = HardwareTiers.gpuTier(HardwareProfile(platform: 'windows', gpuName: 'Intel(R) UHD Graphics 620'));
    final (i5, _) = HardwareTiers.cpuTier(HardwareProfile(platform: 'windows', cpuName: 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz'));
    expect(rtx, greaterThan(igpu));
    expect(i5, inInclusiveRange(40, 75));
  });

  test('sem release e sem plataforma declarada fica não avaliado', () {
    final r = engine.evaluate(req: const GameRequirements(), hw: phone778g());
    expect(r.level, CompatLevel.unknown);
  });
}
