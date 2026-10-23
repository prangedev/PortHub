import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/core/models/game_requirements.dart';
import 'package:porthub/core/models/release_info.dart';
import 'package:porthub/core/platform_info.dart';
import 'package:porthub/core/version_compare.dart';
import 'package:porthub/downloads/checksum.dart';
import 'package:porthub/github/asset_detector.dart';
import 'package:porthub/github/manifest_parser.dart';
import 'package:porthub/github/readme_parser.dart';
import 'package:porthub/services/providers/community_json_provider.dart';

ReleaseAsset a(String name) => AssetDetector.fromGitHub({'name': name, 'browser_download_url': 'https://x/$name', 'size': 1});

void main() {
  group('AssetDetector', () {
    test('tipos e plataformas (nomes reais de releases)', () {
      expect(a('luanti-5.17.0-arm64-v8a.apk').kind, AssetKind.apk);
      expect(a('luanti-5.17.0-arm64-v8a.apk').arch, 'arm64');
      expect(a('luanti-5.17.0-armeabi-v7a.apk').arch, 'armv7');
      expect(a('luanti-5.17.0-x86_64.apk').arch, 'x86_64');
      expect(a('devilutionx-linux-x86_64.appimage').kind, AssetKind.appImage);
      expect(a('devilutionx-linux-x86_64.tar.xz').platform, AssetPlatform.linux);
      expect(a('fheroes2_android.zip').platform, AssetPlatform.android);
      expect(a('fheroes2_windows_x64_SDL2.zip').platform, AssetPlatform.windows);
      expect(a('fheroes2_windows_x64_SDL2.zip').arch, 'x86_64');
      expect(a('OpenRA-release-20250330-x64-winportable.zip').platform, AssetPlatform.windows);
      expect(a('SuperTux-v0.7.0-win64.msi').kind, AssetKind.msi);
      expect(a('Unciv-signed.apk').arch, isNull);
      expect(a('SHA256SUMS').kind, AssetKind.checksum);
      expect(a('vkQuake-1.37.0_windows_arm64.zip').arch, 'arm64');
      // Cataclysm-DDA chama APKs ARM de x64/x32.
      expect(a('cdda-android-x64-2026-09-19-2324.apk').arch, 'arm64');
      expect(a('cdda-android-x32-2026-09-19-2324.apk').arch, 'armv7');
    });

    test('pickBest escolhe APK da ABI primária', () {
      final assets = [
        a('luanti-5.17.0-armeabi-v7a.apk'),
        a('luanti-5.17.0-arm64-v8a.apk'),
        a('luanti-5.17.0-win64.zip'),
        a('luanti-5.17.0-x86.apk'),
      ];
      expect(AssetDetector.pickBest(assets, HostPlatform.android, ['arm64', 'armv7'])!.name, 'luanti-5.17.0-arm64-v8a.apk');
      expect(AssetDetector.pickBest(assets, HostPlatform.android, ['armv7'])!.name, 'luanti-5.17.0-armeabi-v7a.apk');
      expect(AssetDetector.pickBest(assets, HostPlatform.windows, ['x86_64', 'x86'])!.name, 'luanti-5.17.0-win64.zip');
      expect(AssetDetector.pickBest(assets, HostPlatform.linux, ['x86_64']), isNull);
    });

    test('pickBest: android64/windows64 e build universal vs ABI secundária', () {
      final halo = [
        'chupathingyce-android-release.zip',
        'chupathingyce-android64-release.zip',
        'chupathingyce-windows-release.zip',
        'chupathingyce-windows64-release.zip',
      ].map(a).toList();
      expect(AssetDetector.pickBest(halo, HostPlatform.android, ['arm64', 'armv7'])!.name, 'chupathingyce-android64-release.zip');
      expect(AssetDetector.pickBest(halo, HostPlatform.android, ['armv7'])!.name, 'chupathingyce-android-release.zip');
      expect(AssetDetector.pickBest(halo, HostPlatform.windows, ['x86_64', 'x86'])!.name, 'chupathingyce-windows64-release.zip');

      final chaotix = ['ChaotixRecompiled-0.7.1-android-armeabi-v7a.apk', 'ChaotixRecompiled-0.7.1-android.apk'].map(a).toList();
      expect(AssetDetector.pickBest(chaotix, HostPlatform.android, ['arm64', 'armv7'])!.name, 'ChaotixRecompiled-0.7.1-android.apk');
      expect(AssetDetector.pickBest(chaotix, HostPlatform.android, ['armv7'])!.name, 'ChaotixRecompiled-0.7.1-android-armeabi-v7a.apk');
    });

    test('pickBest: ZIP sem plataforma não vale no Android se o projeto não fala em Android', () {
      final acfa = [a('ACFA-Port-0.7.2.zip')];
      const desc = 'ACFA-Port Unofficial native Windows port of ARMORED CORE for Answer (PS3)';
      expect(AssetDetector.pickBest(acfa, HostPlatform.android, ['arm64'], projectText: desc), isNull);
      expect(AssetDetector.pickBest(acfa, HostPlatform.windows, ['x86_64'], projectText: desc)!.name, 'ACFA-Port-0.7.2.zip');
      expect(AssetDetector.pickBest([a('game-1.0.zip')], HostPlatform.android, ['arm64'], projectText: 'Android port of X'),
          isNotNull);
    });

    test('pickBest no Linux prefere AppImage e ignora código-fonte', () {
      final assets = [a('SuperTuxKart-1.5-src.tar.gz'), a('SuperTuxKart-1.5-linux-x86_64.tar.gz'), a('Game-x86_64.AppImage')];
      expect(AssetDetector.pickBest(assets, HostPlatform.linux, ['x86_64'])!.name, 'Game-x86_64.AppImage');
    });
  });

  group('Requisitos', () {
    test('parse tolerante', () {
      final r = GameRequirements.fromMap({'ram': '4GB', 'architecture': 'arm64-v8a', 'android': '10+', 'vulkan': true, 'gpu': 'mid'});
      expect(r.minRamMb, 4096);
      expect(r.architectures, ['arm64']);
      expect(r.minAndroid, 10);
      expect(r.vulkan, isTrue);
      expect(r.gpuTier, 55);
      expect(GameRequirements.parseSizeMb('512 MB'), 512);
      expect(GameRequirements.parseSizeMb('1.5GB'), 1536);
    });

    test('porthub.yaml', () {
      final m = PortHubManifest.parse('''
name: Meu Port
category: [RPG, Ação]
engine: SDL2
android_package: org.exemplo.port
requirements:
  ram: 3GB
  architecture: [arm64-v8a, armeabi-v7a]
  gles: 3.2
''')!;
      expect(m.name, 'Meu Port');
      expect(m.categories, ['RPG', 'Ação']);
      expect(m.requirements!.minRamMb, 3072);
      expect(m.requirements!.architectures, containsAll(['arm64', 'armv7']));
      expect(m.requirements!.minGlEs, 3.2);
    });

    test('heurísticas do README', () {
      const md = '''
# Jogo
![badge](https://img.shields.io/badge/x.svg) ![shot](docs/screen.png)

Requires Android 8.0 or higher and at least 3 GB of RAM. Vulkan is required.
Uses OpenGL ES 3.0. Built with libGDX.
''';
      final r = ReadmeParser.requirements(md);
      expect(r.minAndroid, 8.0);
      expect(r.minRamMb, 3072);
      expect(r.vulkan, isTrue);
      expect(r.minGlEs, 3.0);
      expect(ReadmeParser.images(md, 'https://raw.githubusercontent.com/o/r/main/'),
          ['https://raw.githubusercontent.com/o/r/main/docs/screen.png']);
      expect(ReadmeParser.engine(const [], md, 'Java'), 'libGDX');
    });
  });

  test('versões', () {
    expect(isNewerVersion('v1.10.0', '1.9.2'), isTrue);
    expect(isNewerVersion('1.5', 'v1.5'), isFalse);
    expect(isNewerVersion('4.22.13', '4.22.13'), isFalse);
    expect(compareVersions('release-20250330', 'release-20240101'), greaterThan(0));
  });

  test('checksum sha256sum', () {
    const text = 'aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44  game.apk\n'
        '0000000000000000000000000000000000000000000000000000000000000000  other.zip';
    expect(Checksum.parse(text, 'game.apk'), 'aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44');
    expect(Checksum.parse(text, 'missing.apk'), isNull);
  });

  test('catálogo comunitário embarcado é válido', () async {
    final text = await File('assets/catalog/community.json').readAsString();
    final entries = CommunityJsonProvider.parse(text);
    expect(entries.length, greaterThanOrEqualTo(10));
    expect(entries.every((e) => e.hasGitHub), isTrue);
    expect(entries.map((e) => e.id).toSet().length, entries.length);
  });
}
