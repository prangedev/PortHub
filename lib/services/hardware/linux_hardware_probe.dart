import 'dart:io';

import '../../core/logger.dart';
import '../../core/models/hardware_profile.dart';
import '../../core/platform_info.dart';

/// Linux: /proc, /etc/os-release, /sys/class/drm, glxinfo, vulkaninfo, lspci, df.
/// Todas as ferramentas externas são opcionais — se faltarem, o campo fica null.
class LinuxHardwareProbe {
  static Future<HardwareProfile> probe({required String storagePath, int? screenW, int? screenH, double? refresh}) async {
    final cpuinfo = await _read('/proc/cpuinfo');
    final meminfo = await _read('/proc/meminfo');
    final osRelease = await _read('/etc/os-release');
    final kernel = (await _read('/proc/sys/kernel/osrelease'))?.trim();

    // CPU
    String? cpuName = _field(cpuinfo, 'model name') ?? _field(cpuinfo, 'Hardware') ?? _field(cpuinfo, 'Model');
    final threads = RegExp(r'^processor\s*:', multiLine: true).allMatches(cpuinfo ?? '').length;
    final cores = int.tryParse(_field(cpuinfo, 'cpu cores') ?? '');
    final maxMhz = int.tryParse((await _read('/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq'))?.trim() ?? '');

    // RAM
    final memKb = int.tryParse(RegExp(r'MemTotal:\s*(\d+)').firstMatch(meminfo ?? '')?.group(1) ?? '');

    // Distribuição
    final distro = RegExp(r'^PRETTY_NAME="?([^"\n]+)"?', multiLine: true).firstMatch(osRelease ?? '')?.group(1);

    // GPU / OpenGL (glxinfo -B, do pacote mesa-utils)
    String? gpu;
    String? driver;
    double? gl;
    final glx = await _run('glxinfo', ['-B']);
    if (glx != null) {
      gpu = RegExp(r'OpenGL renderer string:\s*(.+)').firstMatch(glx)?.group(1)?.trim();
      final ver = RegExp(r'OpenGL (?:core profile )?version string:\s*(\d+\.\d+)\S*\s*(.*)').firstMatch(glx);
      gl = double.tryParse(ver?.group(1) ?? '');
      driver = ver?.group(2)?.trim();
      final maxVer = RegExp(r'Max (?:core profile )?version:?\s*[:=]?\s*(\d+\.\d+)').firstMatch(glx);
      final maxGl = double.tryParse(maxVer?.group(1) ?? '');
      if (maxGl != null && (gl == null || maxGl > gl)) gl = maxGl;
    }
    gpu ??= await _gpuFromLspci();
    String? vendor = await _gpuVendorFromSysfs();

    // Vulkan
    var vulkan = false;
    String? vkVersion;
    final vk = await _run('vulkaninfo', ['--summary']);
    if (vk != null) {
      final api = RegExp(r'apiVersion\s*=\s*(\d+\.\d+(?:\.\d+)?)').firstMatch(vk);
      if (api != null) {
        vulkan = true;
        vkVersion = api.group(1);
      }
      gpu ??= RegExp(r'deviceName\s*=\s*(.+)').firstMatch(vk)?.group(1)?.trim();
      driver ??= RegExp(r'driverName\s*=\s*(.+)').firstMatch(vk)?.group(1)?.trim();
    } else {
      // Sem vulkaninfo: procura ICDs instalados.
      for (final dir in ['/usr/share/vulkan/icd.d', '/etc/vulkan/icd.d']) {
        final d = Directory(dir);
        if (await d.exists() && (await d.list().toList()).isNotEmpty) vulkan = true;
      }
    }

    // Disco
    int? freeMb;
    int? totalMb;
    final df = await _run('df', ['-Pk', storagePath]);
    if (df != null) {
      final line = df.trim().split('\n').last.split(RegExp(r'\s+'));
      if (line.length >= 4) {
        totalMb = (int.tryParse(line[1]) ?? 0) ~/ 1024;
        freeMb = (int.tryParse(line[3]) ?? 0) ~/ 1024;
      }
    }

    final arch = normalizeArch((await _run('uname', ['-m']))?.trim()) ?? currentProcessArch();
    return HardwareProfile(
      platform: 'linux',
      model: (await _read('/sys/devices/virtual/dmi/id/product_name'))?.trim() ??
          (await _read('/proc/device-tree/model'))?.replaceAll('\u0000', '').trim(),
      manufacturer: (await _read('/sys/devices/virtual/dmi/id/sys_vendor'))?.trim(),
      osName: 'Linux',
      osVersion: kernel,
      kernel: kernel,
      distro: distro,
      abis: [arch, if (arch == 'x86_64') 'x86', if (arch == 'arm64') 'armv7'],
      ramMb: memKb == null ? null : memKb ~/ 1024,
      cpuName: cpuName,
      cpuCores: cores ?? threads,
      cpuThreads: threads == 0 ? null : threads,
      cpuMaxMhz: maxMhz == null ? null : maxMhz ~/ 1000,
      gpuName: gpu,
      gpuVendor: vendor,
      gpuDriver: driver,
      vulkan: vulkan,
      vulkanVersion: vkVersion,
      openGlVersion: gl,
      freeStorageMb: freeMb,
      totalStorageMb: totalMb,
      screenWidth: screenW,
      screenHeight: screenH,
      refreshRate: refresh,
    );
  }

  static String? _field(String? text, String key) =>
      RegExp('^${RegExp.escape(key)}\\s*:\\s*(.+)\$', multiLine: true).firstMatch(text ?? '')?.group(1)?.trim();

  static Future<String?> _read(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _run(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args).timeout(const Duration(seconds: 8));
      if (r.exitCode != 0) return null;
      return r.stdout.toString();
    } catch (e) {
      appLog.d('HW', '$cmd indisponível');
      return null;
    }
  }

  static Future<String?> _gpuFromLspci() async {
    final out = await _run('lspci', []);
    if (out == null) return null;
    final line = out.split('\n').firstWhere(
          (l) => RegExp(r'(VGA compatible controller|3D controller|Display controller)').hasMatch(l),
          orElse: () => '',
        );
    if (line.isEmpty) return null;
    return line.split(': ').skip(1).join(': ').trim();
  }

  static Future<String?> _gpuVendorFromSysfs() async {
    try {
      final drm = Directory('/sys/class/drm');
      if (!await drm.exists()) return null;
      await for (final e in drm.list()) {
        final vendor = await _read('${e.path}/device/vendor');
        if (vendor == null) continue;
        return switch (vendor.trim()) {
          '0x10de' => 'NVIDIA',
          '0x1002' => 'AMD',
          '0x8086' => 'Intel',
          '0x5143' => 'Qualcomm',
          _ => vendor.trim(),
        };
      }
    } catch (_) {}
    return null;
  }
}
