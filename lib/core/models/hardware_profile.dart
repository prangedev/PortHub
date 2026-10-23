/// Perfil de hardware do dispositivo, coletado na primeira execução e salvo em
/// `hardware_cache`. Campos variam por plataforma; o que não for detectado fica null.
class HardwareProfile {
  HardwareProfile({
    required this.platform,
    this.model,
    this.manufacturer,
    this.osName,
    this.osVersion,
    this.androidSdk,
    this.kernel,
    this.distro,
    this.abis = const [],
    this.ramMb,
    this.cpuName,
    this.socModel,
    this.cpuCores,
    this.cpuThreads,
    this.cpuMaxMhz,
    this.gpuName,
    this.gpuVendor,
    this.gpuDriver,
    this.vulkan = false,
    this.vulkanVersion,
    this.glEsVersion,
    this.openGlVersion,
    this.directX,
    this.freeStorageMb,
    this.totalStorageMb,
    this.screenWidth,
    this.screenHeight,
    this.refreshRate,
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  /// android, linux ou windows.
  final String platform;
  final String? model;
  final String? manufacturer;
  final String? osName;
  final String? osVersion;
  final int? androidSdk;
  final String? kernel;
  final String? distro;

  /// ABIs/arquiteturas suportadas, normalizadas, em ordem de preferência.
  final List<String> abis;
  final int? ramMb;
  final String? cpuName;

  /// Código do SoC (Android 12+: `Build.SOC_MODEL`, ex.: SM7325).
  final String? socModel;
  final int? cpuCores;
  final int? cpuThreads;
  final int? cpuMaxMhz;
  final String? gpuName;
  final String? gpuVendor;
  final String? gpuDriver;
  final bool vulkan;
  final String? vulkanVersion;
  final double? glEsVersion;
  final double? openGlVersion;
  final int? directX;
  final int? freeStorageMb;
  final int? totalStorageMb;
  final int? screenWidth;
  final int? screenHeight;
  final double? refreshRate;
  final DateTime scannedAt;

  String? get primaryArch => abis.isEmpty ? null : abis.first;

  String get deviceLabel {
    final parts = [manufacturer, model].whereType<String>().where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      // Evita "Samsung Samsung Galaxy..."
      if (parts.length == 2 && parts[1].toLowerCase().startsWith(parts[0].toLowerCase())) return parts[1];
      return parts.join(' ');
    }
    return osName ?? platform;
  }

  /// Versão do SO como número (Android "13" → 13.0).
  double? get osVersionNumber {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(osVersion ?? '');
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'model': model,
        'manufacturer': manufacturer,
        'os_name': osName,
        'os_version': osVersion,
        'android_sdk': androidSdk,
        'kernel': kernel,
        'distro': distro,
        'abis': abis,
        'ram_mb': ramMb,
        'cpu_name': cpuName,
        'soc_model': socModel,
        'cpu_cores': cpuCores,
        'cpu_threads': cpuThreads,
        'cpu_max_mhz': cpuMaxMhz,
        'gpu_name': gpuName,
        'gpu_vendor': gpuVendor,
        'gpu_driver': gpuDriver,
        'vulkan': vulkan,
        'vulkan_version': vulkanVersion,
        'gles_version': glEsVersion,
        'opengl_version': openGlVersion,
        'directx': directX,
        'free_storage_mb': freeStorageMb,
        'total_storage_mb': totalStorageMb,
        'screen_width': screenWidth,
        'screen_height': screenHeight,
        'refresh_rate': refreshRate,
        'scanned_at': scannedAt.toIso8601String(),
      };

  factory HardwareProfile.fromJson(Map<String, dynamic> j) => HardwareProfile(
        platform: j['platform'] as String? ?? 'unknown',
        model: j['model'] as String?,
        manufacturer: j['manufacturer'] as String?,
        osName: j['os_name'] as String?,
        osVersion: j['os_version'] as String?,
        androidSdk: (j['android_sdk'] as num?)?.toInt(),
        kernel: j['kernel'] as String?,
        distro: j['distro'] as String?,
        abis: (j['abis'] as List?)?.cast<String>() ?? const [],
        ramMb: (j['ram_mb'] as num?)?.toInt(),
        cpuName: j['cpu_name'] as String?,
        socModel: j['soc_model'] as String?,
        cpuCores: (j['cpu_cores'] as num?)?.toInt(),
        cpuThreads: (j['cpu_threads'] as num?)?.toInt(),
        cpuMaxMhz: (j['cpu_max_mhz'] as num?)?.toInt(),
        gpuName: j['gpu_name'] as String?,
        gpuVendor: j['gpu_vendor'] as String?,
        gpuDriver: j['gpu_driver'] as String?,
        vulkan: j['vulkan'] as bool? ?? false,
        vulkanVersion: j['vulkan_version'] as String?,
        glEsVersion: (j['gles_version'] as num?)?.toDouble(),
        openGlVersion: (j['opengl_version'] as num?)?.toDouble(),
        directX: (j['directx'] as num?)?.toInt(),
        freeStorageMb: (j['free_storage_mb'] as num?)?.toInt(),
        totalStorageMb: (j['total_storage_mb'] as num?)?.toInt(),
        screenWidth: (j['screen_width'] as num?)?.toInt(),
        screenHeight: (j['screen_height'] as num?)?.toInt(),
        refreshRate: (j['refresh_rate'] as num?)?.toDouble(),
        scannedAt: DateTime.tryParse(j['scanned_at'] as String? ?? ''),
      );
}
