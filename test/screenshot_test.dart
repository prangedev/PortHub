import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:porthub/achievements/achievement_service.dart';
import 'package:porthub/core/models/game.dart';
import 'package:porthub/core/models/game_requirements.dart';
import 'package:porthub/core/models/hardware_profile.dart';
import 'package:porthub/core/models/release_info.dart';
import 'package:porthub/database/app_database.dart';
import 'package:porthub/database/cache_dao.dart';
import 'package:porthub/database/download_dao.dart';
import 'package:porthub/database/game_dao.dart';
import 'package:porthub/database/hardware_dao.dart';
import 'package:porthub/database/rom_dao.dart';
import 'package:porthub/database/settings_dao.dart';
import 'package:porthub/downloads/download_manager.dart';
import 'package:porthub/emulators/rom_library_service.dart';
import 'package:porthub/emulators/xbox/xbox_unity.dart';
import 'package:porthub/github/asset_detector.dart';
import 'package:porthub/github/github_client.dart';
import 'package:porthub/pages/game_details/game_details_page.dart';
import 'package:porthub/services/community_service.dart';
import 'package:porthub/services/game_actions.dart';
import 'package:porthub/services/gamepad_service.dart';
import 'package:porthub/services/hardware/hardware_service.dart';
import 'package:porthub/services/install_service.dart';
import 'package:porthub/services/library_service.dart';
import 'package:porthub/services/notification_service.dart';
import 'package:porthub/services/providers/game_source_provider.dart';
import 'package:porthub/services/self_update_service.dart';
import 'package:porthub/services/settings_service.dart';
import 'package:porthub/services/summarizer_service.dart';
import 'package:porthub/ui/app_shell.dart';
import 'package:porthub/ui/input/input_router.dart';
import 'package:porthub/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renderiza as telas reais com dados de exemplo e salva PNGs em build/screenshots/.
/// Também falha se houver overflow de layout. Rode: flutter test test/screenshot_test.dart
Future<void> _loadFonts() async {
  // Fontes Material do SDK em uso. O executável de teste fica em
  // `bin/cache/artifacts/engine/<plataforma>/flutter_tester`.
  final candidates = [
    if (Platform.environment['FLUTTER_ROOT'] case final sdk?) '$sdk/bin/cache/artifacts/material_fonts',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  final root = candidates.where((c) => File('$c/roboto-regular.ttf').existsSync()).firstOrNull;
  if (root == null) {
    // Sem as fontes as telas saem com a fonte de teste (blocos), mas a checagem de overflow continua valendo.
    debugPrint('Fontes Material não encontradas em $candidates; usando a fonte padrão de teste.');
    return;
  }
  Future<ByteData> f(String n) async => ByteData.sublistView(await File('$root/$n').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'));
  await icons.load();
}

ReleaseInfo _release(String tag, List<String> names, {String body = '', int size = 80}) => ReleaseInfo(
      tag: tag,
      name: tag,
      body: body,
      publishedAt: DateTime.now().subtract(const Duration(days: 12)),
      assets: [
        for (final n in names)
          AssetDetector.fromGitHub({'name': n, 'browser_download_url': 'https://x/$n', 'size': size * 1024 * 1024}),
      ],
    );

List<Game> _games() => [
      Game(
        id: 'gh:diasurgical/devilutionx',
        name: 'DevilutionX (Diablo)',
        provider: 'community',
        author: 'diasurgical',
        githubUrl: 'https://github.com/diasurgical/devilutionX',
        description: 'Diablo build for modern operating systems. Jogue o clássico com suporte a controles, widescreen e multiplayer.',
        categories: ['RPG', 'Ação'],
        engine: 'SDL2',
        tags: ['Offline', 'Multiplayer', 'Open Source'],
        stars: 9100,
        version: '1.5.5',
        license: 'NOASSERTION',
        language: 'C++',
        requirements: GameRequirements.fromMap({'ram': '1GB', 'android': '6+', 'gles': '2.0', 'cpu': 'low', 'gpu': 'low'}),
        releases: [
          _release('1.5.5', ['devilutionx-android.apk', 'devilutionx-windows-x86_64.zip', 'devilutionx-linux-x86_64.appimage'],
              body: '## Novidades\n- Suporte a DualSense\n- Correções de áudio\n- Melhorias no multiplayer'),
        ],
        installed: true,
        installedVersion: '1.5.4',
        lastPlayed: DateTime.now().subtract(const Duration(hours: 3)),
        playTimeSeconds: 5 * 3600,
        favorite: true,
      ),
      Game(
        id: 'gh:luanti-org/luanti',
        name: 'Luanti (Minetest)',
        provider: 'community',
        author: 'luanti-org',
        description: 'Motor de jogo voxel open source com milhares de mods e servidores multiplayer.',
        categories: ['Ação'],
        engine: 'Irrlicht',
        tags: ['Offline', 'Multiplayer', 'Open Source'],
        stars: 11000,
        version: '5.17.0',
        requirements: GameRequirements.fromMap({'ram': '2GB', 'gles': '2.0', 'cpu': 'mid'}),
        releases: [_release('5.17.0', ['luanti-5.17.0-arm64-v8a.apk', 'luanti-5.17.0-win64.zip', 'luanti-5.17.0-win32.zip'])],
      ),
      Game(
        id: 'gh:novum/vkquake',
        name: 'vkQuake',
        provider: 'community',
        author: 'Novum',
        description: 'Port de Quake com renderizador Vulkan.',
        categories: ['FPS', 'Terror'],
        engine: 'Quake Engine (Vulkan)',
        tags: ['Offline', 'Open Source'],
        version: '1.37.0',
        requirements: GameRequirements.fromMap({'ram': '2GB', 'vulkan': true, 'gpu': 'mid', 'platforms': ['linux', 'windows']}),
        releases: [_release('1.37.0', ['vkQuake-1.37.0_windows_x64.zip', 'vkQuake-1.37.0-x86_64.AppImage'], size: 12)],
      ),
      Game(
        id: 'gh:chrisboyle/sgtpuzzles',
        name: "Simon Tatham's Puzzles",
        provider: 'community',
        author: 'chrisboyle',
        description: 'Coleção de quebra-cabeças para Android.',
        categories: ['Puzzle'],
        tags: ['Offline', 'Open Source'],
        requirements: GameRequirements.fromMap({'platforms': ['android']}),
        releases: [_release('2025-09-12', ['SGTPuzzles-2025-09-12.apk'], size: 4)],
      ),
      Game(
        id: 'gh:supertuxkart/stk-code',
        name: 'SuperTuxKart',
        provider: 'community',
        author: 'supertuxkart',
        description: 'Corrida de kart 3D com modos online.',
        categories: ['Corrida'],
        engine: 'Antarctica (STK)',
        tags: ['Multiplayer', 'Open Source'],
        stars: 5200,
        version: '1.5',
        requirements: GameRequirements.fromMap({'ram': '3GB', 'gpu': 'mid', 'cpu': 'mid', 'opengl': '3.1'}),
        releases: [_release('1.5', ['SuperTuxKart-1.5-win.zip', 'SuperTuxKart-1.5-linux-x86_64.tar.gz', 'SuperTuxKart-1.5.apk'], size: 700)],
        wishlist: true,
      ),
      Game(
        id: 'gh:ihhub/fheroes2',
        name: 'fheroes2',
        provider: 'community',
        author: 'ihhub',
        description: 'Recriação do Heroes of Might and Magic II.',
        categories: ['Estratégia'],
        engine: 'SDL2',
        tags: ['Offline', 'Open Source'],
        version: '1.1.17',
        releases: [_release('1.1.17', ['fheroes2_windows_x64_SDL2.zip', 'fheroes2_android.zip'], size: 9)],
        installed: true,
        installedVersion: '1.1.17',
        lastPlayed: DateTime.now().subtract(const Duration(days: 2)),
        playTimeSeconds: 1800,
      ),
    ];

final _hw = HardwareProfile(
  platform: 'windows',
  model: 'B450M Steel Legend',
  osName: 'Windows 11',
  osVersion: '10.0.26100',
  abis: const ['x86_64', 'x86'],
  ramMb: 32125,
  cpuName: 'AMD Ryzen 5 5600G with Radeon Graphics',
  cpuCores: 6,
  cpuThreads: 12,
  gpuName: 'AMD Radeon RX 580 2048SP',
  vulkan: true,
  openGlVersion: 4.6,
  directX: 12,
  freeStorageMb: 149000,
  screenWidth: 1920,
  screenHeight: 1080,
  refreshRate: 180,
);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screenshots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots das telas principais', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Widget app;
    late LibraryService library;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await AppDatabase.createSchema(db);
      final settings = SettingsService(SettingsDao(db));
      await settings.load();
      settings.firstRunDone = true;
      final cache = CacheDao(db);
      final gh = GitHubClient(cache: cache, settings: settings);
      final hardware = HardwareService(HardwareDao(db));
      await HardwareDao(db).save(_hw);
      await hardware.loadCached();
      final notifications = NotificationService();
      await GameDao(db).upsertAll(_games());
      library = LibraryService(
        dao: GameDao(db),
        gh: gh,
        settings: settings,
        hardware: hardware,
        providers: const <GameSourceProvider>[],
        notifications: notifications,
      );
      await library.load();
      final downloads = DownloadManager(DownloadDao(db), settings);
      final installer = InstallService(settings);
      final actions = GameActions(
        library: library,
        downloads: downloads,
        installer: installer,
        hardware: hardware,
        notifications: notifications,
        settings: settings,
        gh: gh,
      );
      app = MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: hardware),
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: downloads),
          ChangeNotifierProvider.value(value: notifications),
          ChangeNotifierProvider.value(value: SelfUpdateService(settings, notifications)),
          ChangeNotifierProvider.value(value: AchievementService(settings, notifications)),
          ChangeNotifierProvider.value(value: RomLibraryService(RomDao(db), XboxUnity(cache))),
          ChangeNotifierProvider.value(value: GamepadService(InputRouter.instance)),
          Provider.value(value: actions),
          Provider.value(value: installer),
          Provider.value(value: gh),
          Provider.value(value: const <GameSourceProvider>[]),
          Provider.value(value: CommunityService(settings, cache)),
          Provider.value(value: SummarizerService(settings)),
          Provider.value(value: cache),
        ],
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            navigatorKey: InputRouter.instance.navigatorKey,
            builder: (context, child) => Focus(
              canRequestFocus: false,
              onKeyEvent: (_, e) => InputRouter.instance.handleKey(e),
              child: child!,
            ),
            home: const AppShell(),
          ),
        ),
      );
    });

    await tester.pumpWidget(app);
    await _shot(tester, '1_inicio');

    // D-pad: desce para a próxima prateleira e anda para a direita.
    InputRouter.instance.dispatch(PadAction.down);
    await tester.pumpAndSettle();
    InputRouter.instance.dispatch(PadAction.down);
    await tester.pumpAndSettle();
    InputRouter.instance.dispatch(PadAction.right);
    await _shot(tester, '1b_inicio_navegando');
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.context, isNotNull, reason: 'o D-pad deve manter um item focado');

    // Navegação por controle: RB troca de seção.
    InputRouter.instance.dispatch(PadAction.nextSection);
    await _shot(tester, '2_biblioteca');

    InputRouter.instance.dispatch(PadAction.nextSection);
    InputRouter.instance.dispatch(PadAction.nextSection);
    InputRouter.instance.dispatch(PadAction.nextSection);
    await _shot(tester, '3_dispositivo');

    InputRouter.instance.dispatch(PadAction.nextSection);
    await _shot(tester, '4_configuracoes');

    // Página do jogo (instalado, com atualização disponível).
    final g = library.byId('gh:diasurgical/devilutionx')!;
    expect(g.updateAvailable, isTrue);
    InputRouter.instance.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => GameDetailsPage(gameId: g.id)));
    await _shot(tester, '5_jogo');

    // LB/RB dentro do jogo trocam as abas → Compatibilidade.
    for (var i = 0; i < 4; i++) {
      InputRouter.instance.dispatch(PadAction.nextSection);
    }
    await _shot(tester, '6_jogo_compatibilidade');

    // Jogo incompatível (só Android) mostra o motivo.
    InputRouter.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    final puzzles = library.byId('gh:chrisboyle/sgtpuzzles')!;
    expect(puzzles.compatibility.blockingReason, isNotNull);
    InputRouter.instance.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => GameDetailsPage(gameId: puzzles.id)));
    await _shot(tester, '7_jogo_incompativel');
  });
}
