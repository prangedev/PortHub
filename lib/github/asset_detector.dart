import '../core/models/release_info.dart';
import '../core/platform_info.dart';

/// Detecta automaticamente tipo (APK, ZIP, AppImage, EXE...), plataforma e
/// arquitetura de um asset de release a partir do nome do arquivo.
class AssetDetector {
  static ReleaseAsset fromGitHub(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    final kind = kindOf(name);
    // Desde 2025 a API de releases inclui `digest: "sha256:..."` em cada asset.
    final digest = j['digest'] as String?;
    return ReleaseAsset(
      name: name,
      url: j['browser_download_url'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      kind: kind,
      platform: platformOf(name, kind),
      arch: archOf(name, kind: kind),
      checksum: digest != null && digest.contains(':') ? digest.toLowerCase() : null,
      downloadCount: (j['download_count'] as num?)?.toInt() ?? 0,
    );
  }

  static AssetKind kindOf(String fileName) {
    final n = fileName.toLowerCase();
    if (RegExp(r'(sha256sums?|sha256|checksums?|md5sums?)(\.txt)?$').hasMatch(n) ||
        n.endsWith('.sha256') ||
        n.endsWith('.sha256sum') ||
        n.endsWith('.md5') ||
        n.endsWith('.sig') ||
        n.endsWith('.asc')) {
      return AssetKind.checksum;
    }
    if (n.endsWith('.apk')) return AssetKind.apk;
    if (n.endsWith('.apks') || n.endsWith('.xapk') || n.endsWith('.apkm')) return AssetKind.splitApk;
    if (n.endsWith('.appimage')) return AssetKind.appImage;
    if (n.endsWith('.exe')) return AssetKind.exe;
    if (n.endsWith('.msi')) return AssetKind.msi;
    if (n.endsWith('.deb')) return AssetKind.deb;
    if (n.endsWith('.zip')) return AssetKind.zip;
    if (RegExp(r'\.(tar\.gz|tgz|tar\.xz|txz|tar\.bz2|tar)$').hasMatch(n)) return AssetKind.tarball;
    if (_looksLikeLinuxBinary(n)) return AssetKind.appImage; // executável solto (.x86_64, .bin)
    return AssetKind.other;
  }

  static bool _looksLikeLinuxBinary(String n) => n.endsWith('.x86_64') || n.endsWith('.bin') || n.endsWith('.run');

  static List<String> _tokens(String n) => n.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();

  static AssetPlatform platformOf(String fileName, AssetKind kind) {
    switch (kind) {
      case AssetKind.apk:
      case AssetKind.splitApk:
        return AssetPlatform.android;
      case AssetKind.appImage:
      case AssetKind.deb:
        return AssetPlatform.linux;
      case AssetKind.exe:
      case AssetKind.msi:
        return AssetPlatform.windows;
      default:
        break;
    }
    final t = _tokens(fileName);
    bool any(List<String> words) => t.any((x) => words.contains(x) || words.any((w) => w.length > 4 && x.startsWith(w)));
    if (any(['android', 'apk'])) return AssetPlatform.android;
    // "win", "win64", "winportable"... (sem pegar palavras como "wing" ou "winter").
    const notWindows = ['wing', 'wings', 'wind', 'winds', 'winter', 'winner', 'wine'];
    if (t.any((x) => x.startsWith('win') && !notWindows.contains(x)) || any(['msvc', 'mingw', 'mingw64', 'msys'])) {
      return AssetPlatform.windows;
    }
    if (any(['mac', 'macos', 'osx', 'darwin', 'dmg', 'apple', 'universal2'])) return AssetPlatform.macos;
    if (any(['linux', 'ubuntu', 'debian', 'steamdeck', 'steamos', 'flatpak', 'gnu', 'linux64', 'portmaster'])) {
      return AssetPlatform.linux;
    }
    // Tarballs sem plataforma explícita normalmente são Linux.
    if (kind == AssetKind.tarball && !any(['src', 'source'])) return AssetPlatform.linux;
    return AssetPlatform.unknown;
  }

  static String? archOf(String fileName, {AssetKind? kind}) {
    final n = fileName.toLowerCase();
    if (RegExp(r'(universal|fat|multiarch|allabi|all-abi)').hasMatch(n)) return null;
    // Alguns projetos (ex.: Cataclysm-DDA) chamam APKs ARM de "x64"/"x32".
    if (kind == AssetKind.apk || kind == AssetKind.splitApk) {
      final t = _tokens(n);
      if (t.contains('x64') && !n.contains('x86')) return 'arm64';
      if (t.contains('x32') && !n.contains('x86')) return 'armv7';
    }
    if (RegExp(r'(x86[_-]?64|amd64|x64|win64|windows64|linux64)').hasMatch(n)) return 'x86_64';
    if (RegExp(r'(arm64|aarch64|armv8|android64)').hasMatch(n)) return 'arm64';
    if (RegExp(r'(armeabi|armv7|armhf|arm32)').hasMatch(n)) return 'armv7';
    final t = _tokens(n);
    if (t.any((x) => ['x86', 'i386', 'i686', 'win32', 'ia32', 'x32'].contains(x))) return 'x86';
    return null;
  }

  static bool _isSource(ReleaseAsset a) {
    final t = _tokens(a.name);
    return t.contains('src') || t.contains('source') || t.contains('sources') || t.contains('debug') || t.contains('symbols') || t.contains('pdb');
  }

  /// Escolhe o melhor asset para a plataforma/arquiteturas do dispositivo.
  /// [deviceArchs] em ordem de preferência (ABI primária primeiro).
  /// [projectText]: nome, descrição e tópicos do projeto. No Android, um ZIP
  /// sem plataforma no nome só vale se o projeto falar em Android (evita
  /// oferecer o ZIP de um port de Windows, ex.: "ACFA-Port-0.7.2.zip").
  static ReleaseAsset? pickBest(List<ReleaseAsset> assets, HostPlatform platform, List<String> deviceArchs,
      {String? projectText}) {
    final mentionsAndroid = projectText == null || projectText.toLowerCase().contains('android');
    final target = switch (platform) {
      HostPlatform.android => AssetPlatform.android,
      HostPlatform.linux => AssetPlatform.linux,
      HostPlatform.windows => AssetPlatform.windows,
      HostPlatform.other => AssetPlatform.unknown,
    };
    ReleaseAsset? best;
    var bestScore = -1 << 30;
    for (final a in assets) {
      if (!a.installable || _isSource(a)) continue;
      if (a.platform != target && a.platform != AssetPlatform.unknown) continue;
      if (a.platform == AssetPlatform.unknown && !(a.kind == AssetKind.zip || a.kind == AssetKind.tarball)) continue;
      if (a.platform == AssetPlatform.unknown && platform == HostPlatform.android && !mentionsAndroid) continue;

      var score = 0;
      score += a.platform == target ? 50 : -30;
      score += switch ((platform, a.kind)) {
        (HostPlatform.android, AssetKind.apk) => 100,
        (HostPlatform.android, AssetKind.splitApk) => 90,
        (HostPlatform.android, AssetKind.zip) => 40,
        (HostPlatform.linux, AssetKind.appImage) => 100,
        (HostPlatform.linux, AssetKind.tarball) => 75,
        (HostPlatform.linux, AssetKind.zip) => 65,
        (HostPlatform.linux, AssetKind.deb) => 10,
        (HostPlatform.windows, AssetKind.zip) => 90,
        (HostPlatform.windows, AssetKind.exe) => 80,
        (HostPlatform.windows, AssetKind.msi) => 70,
        _ => -1000,
      };
      if (a.arch == null) {
        // Sem arquitetura no nome: provavelmente universal. Perde para o build da
        // ABI principal, mas ganha de um build de ABI secundária (ex.: armv7 num arm64).
        score += 35;
      } else {
        final idx = deviceArchs.indexOf(a.arch!);
        if (idx < 0) continue; // arquitetura incompatível
        score += 40 - idx * 10;
      }
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best;
  }

  /// Existe algum asset para a plataforma (independente da arquitetura)?
  static bool hasAssetForPlatform(List<ReleaseAsset> assets, HostPlatform platform) {
    final target = switch (platform) {
      HostPlatform.android => AssetPlatform.android,
      HostPlatform.linux => AssetPlatform.linux,
      HostPlatform.windows => AssetPlatform.windows,
      HostPlatform.other => AssetPlatform.unknown,
    };
    return assets.any((a) => a.installable && !_isSource(a) && a.platform == target);
  }

  /// Arquiteturas oferecidas para a plataforma (para mensagens de incompatibilidade).
  static Set<String> archsForPlatform(List<ReleaseAsset> assets, HostPlatform platform) {
    final target = AssetPlatform.values.byName(platform == HostPlatform.other ? 'unknown' : platform.name);
    return assets.where((a) => a.platform == target && a.arch != null).map((a) => a.arch!).toSet();
  }
}
