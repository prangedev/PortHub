import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../downloads/download_manager.dart';
import '../pages/downloads_page.dart';
import '../pages/emulators_page.dart';
import '../pages/hardware_page.dart';
import '../pages/home_page.dart';
import '../pages/library_page.dart';
import '../pages/navigation.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../services/gamepad_service.dart';
import '../services/library_service.dart';
import '../services/notification_service.dart';
import '../services/self_update_service.dart';
import '../widgets/focusable.dart';
import '../widgets/hint_bar.dart';
import 'input/input_router.dart';
import 'theme.dart';

/// Estrutura principal estilo Steam Big Picture: barra superior com seções
/// (LB/RB alternam), conteúdo em tela cheia e barra de dicas do controle.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with PadHandlerMixin {
  int _tab = 0;
  StreamSubscription<AppNotification>? _toastSub;
  final List<AppNotification> _toasts = [];

  static const _searchTab = 3;
  static const _downloadsTab = 4;
  static const _settingsTab = 6;

  static const _tabs = [
    ('Início', Icons.home_rounded),
    ('Biblioteca', Icons.grid_view_rounded),
    ('Emuladores', Icons.videogame_asset_rounded),
    ('Pesquisar', Icons.search_rounded),
    ('Downloads', Icons.download_rounded),
    ('Dispositivo', Icons.memory_rounded),
    ('Configurações', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _toastSub = context.read<NotificationService>().toasts.listen((n) {
      setState(() => _toasts.add(n));
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _toasts.remove(n));
      });
    });
  }

  @override
  void dispose() {
    _toastSub?.cancel();
    super.dispose();
  }

  void _go(int i) {
    // Solta o foco atual para que o autofocus da nova seção assuma.
    FocusManager.instance.primaryFocus?.unfocus(disposition: UnfocusDisposition.scope);
    setState(() => _tab = (i + _tabs.length) % _tabs.length);
  }

  @override
  bool onPad(PadAction a) {
    switch (a) {
      case PadAction.prevSection:
        _go(_tab - 1);
        return true;
      case PadAction.nextSection:
        _go(_tab + 1);
        return true;
      case PadAction.search:
        _go(_searchTab);
        return true;
      case PadAction.menu:
        _go(_settingsTab);
        return true;
      case PadAction.back:
        if (_tab != 0) {
          _go(0);
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  Widget _page() => switch (_tab) {
        0 => const HomePage(),
        1 => const LibraryPage(),
        2 => const EmulatorsPage(),
        _searchTab => const SearchPage(),
        _downloadsTab => const DownloadsPage(),
        5 => const HardwarePage(),
        _ => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PH.bg,
      body: Stack(children: [
        Column(children: [
          _TopBar(tabs: _tabs, current: _tab, onSelect: _go),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_tab), child: _page()),
            ),
          ),
          const HintBar(hints: [
            (PadGlyph.a, 'Selecionar'),
            (PadGlyph.b, 'Voltar'),
            (PadGlyph.y, 'Pesquisar'),
            (PadGlyph.lb, 'Seção anterior'),
            (PadGlyph.rb, 'Próxima seção'),
          ], leading: _ControllerStatus()),
        ]),
        Positioned(
          top: 76,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (final t in _toasts) _Toast(n: t)],
          ),
        ),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.tabs, required this.current, required this.onSelect});
  final List<(String, IconData)> tabs;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final compact = PH.compact(context);
    // Celulares deitados (~900pt) não comportam as seis abas com nome:
    // só a aba atual mostra o rótulo.
    final narrow = MediaQuery.sizeOf(context).width < 1200;
    final lib = context.watch<LibraryService>();
    final dl = context.watch<DownloadManager>();
    final selfUpdate = context.watch<SelfUpdateService>();
    return Container(
      height: compact ? 56 : 68,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0E1620), Color(0xFF0A0D12)]),
        border: Border(bottom: BorderSide(color: PH.stroke)),
      ),
      child: Row(children: [
        const Icon(Icons.hub_rounded, color: PH.accent, size: 28),
        if (!compact) ...[
          if (!narrow) ...[
            const SizedBox(width: 10),
            const Text('PORTHUB', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 18)),
          ],
          SizedBox(width: narrow ? 16 : 28),
          const ButtonGlyph(PadGlyph.lb, size: 20),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Focusable(
                    glow: false,
                    focusScale: 1.0,
                    borderRadius: 8,
                    onActivate: () => onSelect(i),
                    builder: (context, focused) => AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: i == current ? PH.accent.withValues(alpha: 0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(tabs[i].$2, size: 19, color: i == current ? PH.accent : PH.textDim),
                        if (!narrow || i == current) ...[
                          const SizedBox(width: 8),
                          Text(tabs[i].$1,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: i == current ? PH.text : PH.textDim,
                              )),
                        ],
                        if (i == _AppShellState._downloadsTab && dl.activeCount > 0) ...[
                          const SizedBox(width: 6),
                          _CountBadge(dl.activeCount),
                        ],
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        if (!compact) const ButtonGlyph(PadGlyph.rb, size: 20),
        const SizedBox(width: 20),
        if (lib.refreshing) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: lib.refreshProgress > 0 ? lib.refreshProgress : null),
          ),
          const SizedBox(width: 8),
          if (!narrow) const Text('Sincronizando', style: TextStyle(color: PH.textDim, fontSize: 13)),
          const SizedBox(width: 20),
        ],
        if (dl.activeCount > 0 && !narrow) ...[
          const Icon(Icons.downloading_rounded, size: 18, color: PH.accentSoft),
          const SizedBox(width: 6),
          Text(formatSpeed(dl.totalSpeed), style: const TextStyle(color: PH.textDim, fontSize: 13)),
          const SizedBox(width: 20),
        ],
        if (selfUpdate.updateAvailable) ...[
          Focusable(
            glow: false,
            focusScale: 1.0,
            borderRadius: 8,
            onActivate: () => onSelect(_AppShellState._settingsTab),
            builder: (context, focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: focused ? PH.yellow.withValues(alpha: 0.3) : PH.yellow.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.system_update_rounded, size: 16, color: PH.yellow),
                if (!narrow) ...[
                  const SizedBox(width: 6),
                  Text('PortHub ${selfUpdate.latest!.tag}', style: const TextStyle(color: PH.yellow, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 16),
        ],
        const _Clock(),
      ]),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: PH.accent, borderRadius: BorderRadius.circular(10)),
        child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Text('${two(now.hour)}:${two(now.minute)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
  }
}

class _ControllerStatus extends StatelessWidget {
  const _ControllerStatus();
  @override
  Widget build(BuildContext context) {
    final pad = context.watch<GamepadService>();
    final name = pad.controllerName;
    return Row(children: [
      Icon(name == null ? Icons.keyboard_rounded : Icons.sports_esports_rounded, size: 18, color: PH.textFaint),
      const SizedBox(width: 8),
      Flexible(
        child: Text(name ?? 'Teclado / toque', overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textFaint, fontSize: 12)),
      ),
    ]);
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final lib = context.read<LibraryService>();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset((1 - v) * 60, 0), child: child),
      ),
      child: GestureDetector(
        onTap: () {
          final g = n.gameId == null ? null : lib.byId(n.gameId!);
          if (g != null) openGame(context, g);
        },
        child: Container(
          width: 340,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PH.surfaceHi,
            borderRadius: BorderRadius.circular(PH.radius),
            border: Border.all(color: PH.stroke),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(n.icon, color: PH.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PH.textDim, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
