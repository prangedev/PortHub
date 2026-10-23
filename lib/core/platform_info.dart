import 'dart:ffi' show Abi;
import 'dart:io';

/// Plataforma em que o PortHub está rodando.
enum HostPlatform { android, linux, windows, other }

HostPlatform get hostPlatform {
  if (Platform.isAndroid) return HostPlatform.android;
  if (Platform.isLinux) return HostPlatform.linux;
  if (Platform.isWindows) return HostPlatform.windows;
  return HostPlatform.other;
}

String platformLabel(String platform) => switch (platform) {
      'android' => 'Android',
      'linux' => 'Linux',
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => platform,
    };

/// Normaliza nomes de arquitetura para: arm64, armv7, x86_64, x86.
/// Retorna `null` quando não reconhece.
String? normalizeArch(String? raw) {
  if (raw == null) return null;
  final s = raw.toLowerCase().trim();
  if (s.isEmpty) return null;
  if (RegExp(r'(x86[_-]?64|amd64|x64|win64)').hasMatch(s)) return 'x86_64';
  if (RegExp(r'(arm64|aarch64|armv8|arm-v8)').hasMatch(s)) return 'arm64';
  if (RegExp(r'(armeabi|armv7|armhf|arm32|armel|^arm$)').hasMatch(s)) return 'armv7';
  if (RegExp(r'(^x86$|i[3-6]86|win32|^ia32$)').hasMatch(s)) return 'x86';
  return null;
}

String archLabel(String? arch) => switch (arch) {
      'arm64' => 'ARM64',
      'armv7' => 'ARMv7',
      'x86_64' => 'x86_64',
      'x86' => 'x86',
      null => 'Desconhecida',
      _ => arch,
    };

/// Arquitetura do processo atual (usada no desktop).
String currentProcessArch() {
  final abi = Abi.current();
  if (abi == Abi.windowsArm64 || abi == Abi.linuxArm64 || abi == Abi.androidArm64) return 'arm64';
  if (abi == Abi.linuxArm || abi == Abi.androidArm) return 'armv7';
  if (abi == Abi.windowsIA32 || abi == Abi.linuxIA32 || abi == Abi.androidIA32) return 'x86';
  return 'x86_64';
}
