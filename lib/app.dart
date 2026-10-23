import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/first_run_page.dart';
import 'services/settings_service.dart';
import 'ui/app_shell.dart';
import 'ui/input/input_router.dart';
import 'ui/theme.dart';

class PortHubApp extends StatelessWidget {
  const PortHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final firstRunDone = context.read<SettingsService>().firstRunDone;
    return MaterialApp(
      title: 'PortHub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      navigatorKey: InputRouter.instance.navigatorKey,
      scrollBehavior: const PHScrollBehavior(),
      // Teclado físico / botões de controle que chegam como teclas → InputRouter.
      builder: (context, child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
            _toggleFullscreen(context);
            return KeyEventResult.handled;
          }
          return InputRouter.instance.handleKey(event);
        },
        child: child!,
      ),
      home: firstRunDone ? const AppShell() : const FirstRunPage(),
    );
  }

  static Future<void> _toggleFullscreen(BuildContext context) async {
    if (!(Platform.isWindows || Platform.isLinux)) return;
    final settings = context.read<SettingsService>();
    final fs = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(fs);
    settings.fullscreen = fs;
  }
}
