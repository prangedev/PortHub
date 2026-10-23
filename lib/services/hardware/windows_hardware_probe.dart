import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';
import '../../core/models/hardware_profile.dart';
import '../../core/platform_info.dart';

/// Windows: uma única chamada PowerShell (CIM/WMI) retorna CPU, GPUs, RAM, SO
/// e disco em JSON. DirectX e Vulkan são deduzidos pelas DLLs do sistema.
class WindowsHardwareProbe {
  static const _script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$c = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
$g = @(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterCompatibility,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate)
$cs = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory
$o = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='DRIVE'" | Select-Object FreeSpace,Size
@{ cpu = $c; gpu = $g; cs = $cs; os = $o; disk = $d } | ConvertTo-Json -Depth 4 -Compress
''';

  static Future<HardwareProfile> probe({required String storagePath, int? screenW, int? screenH, double? refresh}) async {
    final drive = storagePath.length >= 2 && storagePath[1] == ':' ? storagePath.substring(0, 2).toUpperCase() : 'C:';
    Map<String, dynamic> j = {};
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', _script.replaceAll('DRIVE', drive)],
      ).timeout(const Duration(seconds: 30));
      final out = r.stdout.toString().trim();
      if (out.isNotEmpty) j = (jsonDecode(out) as Map).cast<String, dynamic>();
    } catch (e) {
      appLog.w('HW', 'PowerShell/CIM falhou', e);
    }

    final cpu = (j['cpu'] as Map?)?.cast<String, dynamic>() ?? {};
    final cs = (j['cs'] as Map?)?.cast<String, dynamic>() ?? {};
    final os = (j['os'] as Map?)?.cast<String, dynamic>() ?? {};
    final disk = (j['disk'] as Map?)?.cast<String, dynamic>() ?? {};
    final gpus = ((j['gpu'] is List ? j['gpu'] : [j['gpu']]) as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

    // GPU principal: prefere dedicada (NVIDIA/AMD) e ignora adaptadores virtuais.
    Map<String, dynamic>? gpu;
    int rank(Map<String, dynamic> g) {
      final n = '${g['Name']}'.toLowerCase();
      if (n.contains('basic') || n.contains('virtual') || n.contains('remote') || n.contains('parsec')) return 0;
      if (n.contains('nvidia') || n.contains('geforce') || n.contains('rtx') || n.contains('radeon rx')) return 3;
      if (n.contains('radeon') || n.contains('arc')) return 2;
      return 1;
    }

    if (gpus.isNotEmpty) {
      gpus.sort((a, b) => rank(b).compareTo(rank(a)));
      gpu = gpus.first;
    }

    final sys32 = '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32';
    final dx = await File('$sys32\\d3d12.dll').exists()
        ? 12
        : await File('$sys32\\d3d11.dll').exists()
            ? 11
            : null;
    final vulkan = await File('$sys32\\vulkan-1.dll').exists();

    final rawArch = Platform.environment['PROCESSOR_ARCHITEW6432'] ?? Platform.environment['PROCESSOR_ARCHITECTURE'];
    final arch = normalizeArch(rawArch) ?? currentProcessArch();

    final ram = (cs['TotalPhysicalMemory'] as num?)?.toInt();
    final free = (disk['FreeSpace'] as num?)?.toInt();
    final total = (disk['Size'] as num?)?.toInt();

    return HardwareProfile(
      platform: 'windows',
      model: (cs['Model'] as String?)?.trim(),
      manufacturer: (cs['Manufacturer'] as String?)?.trim(),
      osName: (os['Caption'] as String?)?.replaceFirst('Microsoft ', '').trim() ?? 'Windows',
      osVersion: os['Version'] as String?,
      abis: [arch, if (arch == 'x86_64') 'x86', if (arch == 'arm64') ...['x86_64', 'x86']],
      ramMb: ram == null ? null : ram ~/ (1024 * 1024),
      cpuName: (cpu['Name'] as String?)?.trim(),
      cpuCores: (cpu['NumberOfCores'] as num?)?.toInt(),
      cpuThreads: (cpu['NumberOfLogicalProcessors'] as num?)?.toInt(),
      cpuMaxMhz: (cpu['MaxClockSpeed'] as num?)?.toInt(),
      gpuName: (gpu?['Name'] as String?)?.trim(),
      gpuVendor: gpu?['AdapterCompatibility'] as String?,
      gpuDriver: gpu?['DriverVersion'] as String?,
      vulkan: vulkan,
      directX: dx,
      // Drivers modernos de GPU no Windows expõem OpenGL 4.x; Basic Display não.
      openGlVersion: gpu == null || rank(gpu) == 0 ? null : 4.6,
      freeStorageMb: free == null ? null : free ~/ (1024 * 1024),
      totalStorageMb: total == null ? null : total ~/ (1024 * 1024),
      screenWidth: (gpu?['CurrentHorizontalResolution'] as num?)?.toInt() ?? screenW,
      screenHeight: (gpu?['CurrentVerticalResolution'] as num?)?.toInt() ?? screenH,
      refreshRate: (gpu?['CurrentRefreshRate'] as num?)?.toDouble() ?? refresh,
    );
  }
}
