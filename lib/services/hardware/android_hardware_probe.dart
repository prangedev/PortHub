import '../../core/models/hardware_profile.dart';
import '../../core/platform_info.dart';
import '../native_bridge.dart';

/// Android: tudo vem do MainActivity.kt (Build, ActivityManager, EGL,
/// PackageManager features, StatFs, Display).
class AndroidHardwareProbe {
  static Future<HardwareProfile> probe() async {
    final m = await NativeBridge.hardwareInfo();
    final abis = ((m['abis'] as List?) ?? const [])
        .map((e) => normalizeArch(e.toString()))
        .whereType<String>()
        .toSet()
        .toList();
    final vkLevel = (m['vulkanVersion'] as String?);
    return HardwareProfile(
      platform: 'android',
      model: m['model'] as String?,
      manufacturer: _capitalize(m['manufacturer'] as String?),
      osName: 'Android',
      osVersion: m['release'] as String?,
      androidSdk: (m['sdk'] as num?)?.toInt(),
      kernel: m['kernel'] as String?,
      abis: abis,
      ramMb: (m['ramMb'] as num?)?.toInt(),
      cpuName: m['cpuName'] as String?,
      socModel: m['socModel'] as String?,
      cpuCores: (m['cores'] as num?)?.toInt(),
      cpuThreads: (m['cores'] as num?)?.toInt(),
      cpuMaxMhz: (m['maxFreqMhz'] as num?)?.toInt(),
      gpuName: m['gpuRenderer'] as String?,
      gpuVendor: m['gpuVendor'] as String?,
      gpuDriver: m['gpuVersion'] as String?,
      vulkan: m['vulkan'] == true,
      vulkanVersion: vkLevel,
      glEsVersion: (m['glEsVersion'] as num?)?.toDouble(),
      freeStorageMb: (m['freeStorageMb'] as num?)?.toInt(),
      totalStorageMb: (m['totalStorageMb'] as num?)?.toInt(),
      screenWidth: (m['screenWidth'] as num?)?.toInt(),
      screenHeight: (m['screenHeight'] as num?)?.toInt(),
      refreshRate: (m['refreshRate'] as num?)?.toDouble(),
    );
  }

  static String? _capitalize(String? s) =>
      s == null || s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
