import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/logger.dart';
import 'database/app_database.dart';
import 'database/cache_dao.dart';
import 'database/download_dao.dart';
import 'database/game_dao.dart';
import 'database/hardware_dao.dart';
import 'database/settings_dao.dart';
import 'downloads/download_manager.dart';
import 'github/github_client.dart';
import 'services/community_service.dart';
import 'services/game_actions.dart';
import 'services/gamepad_service.dart';
import 'services/hardware/hardware_service.dart';
import 'services/install_service.dart';
import 'services/library_service.dart';
import 'services/artwork_service.dart';
import 'services/self_update_service.dart';
import 'achievements/achievement_service.dart';
import 'emulators/rom_library_service.dart';
import 'emulators/xbox/xbox_unity.dart';
import 'database/rom_dao.dart';
import 'services/native_bridge.dart';
import 'services/notification_service.dart';
import 'services/providers/community_json_provider.dart';
import 'services/providers/game_source_provider.dart';
import 'services/providers/github_topic_provider.dart';
import 'services/providers/portmaster_provider.dart';
import 'services/settings_service.dart';
import 'services/summarizer_service.dart';
import 'ui/input/input_router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Logs em arquivo + captura de erros não tratados.
  await appLog.init(await getApplicationSupportDirectory());
  FlutterError.onError = (d) {
    appLog.e('Flutter', d.exceptionAsString(), d.exception, d.stack);
    FlutterError.presentError(d);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    appLog.e('Dart', 'Erro não tratado', e, s);
    return true;
  };

  // Banco e serviços (injeção de dependências manual, sem mágica).
  final db = await AppDatabase.open();
  final settings = SettingsService(SettingsDao(db));
  await settings.load();
  final cache = CacheDao(db);
  final gh = GitHubClient(cache: cache, settings: settings);
  final notifications = NotificationService();
  final hardware = HardwareService(HardwareDao(db));
  await hardware.loadCached();

  final providers = <GameSourceProvider>[
    CommunityJsonProvider(gh, settings),
    GitHubTopicProvider(gh),
    PortMasterProvider(gh),
    OpenSourceProvider(gh),
  ];
  final library = LibraryService(
    dao: GameDao(db),
    gh: gh,
    settings: settings,
    hardware: hardware,
    providers: providers,
    notifications: notifications,
    artwork: ArtworkService(cache),
  );
  await library.load();
  final roms = RomLibraryService(RomDao(db), XboxUnity(cache));
  await roms.load();
  final selfUpdate = SelfUpdateService(settings, notifications)..start();
  final achievements = AchievementService(settings, notifications)..start();

  final downloads = DownloadManager(DownloadDao(db), settings);
  await downloads.init();
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
  final gamepad = GamepadService(InputRouter.instance);
  unawaited(gamepad.init());

  await _setupWindow(settings);

  if (settings.firstRunDone) {
    // Reanalisa em segundo plano se não houver perfil salvo (ex.: banco limpo).
    if (hardware.profile == null) unawaited(hardware.scan());
    library.startAutoRefresh();
  }

  appLog.i('App', 'PortHub iniciado em ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: hardware),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: gamepad),
        ChangeNotifierProvider.value(value: roms),
        ChangeNotifierProvider.value(value: selfUpdate),
        ChangeNotifierProvider.value(value: achievements),
        Provider.value(value: actions),
        Provider.value(value: installer),
        Provider.value(value: gh),
        Provider.value(value: providers),
        Provider.value(value: CommunityService(settings, cache)),
        Provider.value(value: SummarizerService(settings)),
        Provider.value(value: cache),
      ],
      child: const PortHubApp(),
    ),
  );
}

/// Launcher em tela cheia: janela sem bordas no desktop e modo imersivo no Android.
Future<void> _setupWindow(SettingsService settings) async {
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      title: 'PortHub',
      size: const Size(1600, 900),
      minimumSize: const Size(960, 600),
      center: true,
      backgroundColor: PH.bg,
      fullScreen: settings.fullscreen,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } else if (Platform.isAndroid) {
    if (settings.fullscreen) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await NativeBridge.requestNotificationPermission();
  }
}
