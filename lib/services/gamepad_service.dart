import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';

import '../core/logger.dart';
import '../ui/input/input_router.dart';

enum ControllerStyle { xbox, playstation, generic, none }

/// Leitura de controles (Xbox, DualSense, DualShock e Bluetooth genérico) via
/// eventos normalizados do plugin `gamepads`, convertidos em [PadAction].
///
/// - D-pad e analógico esquerdo movem o foco (com repetição ao segurar);
/// - A confirma, B volta, X favorita, Y pesquisa;
/// - LB/RB trocam de seção, LT/RT fazem rolagem rápida; Start abre o menu.
class GamepadService extends ChangeNotifier {
  GamepadService(this._router);
  final InputRouter _router;

  StreamSubscription<NormalizedGamepadEvent>? _sub;
  StreamSubscription<GamepadConnectionEvent>? _conn;
  final Map<String, String> _connected = {};

  final Map<PadAction, Timer> _repeat = {};
  final Map<PadAction, DateTime> _lastFire = {};
  double _stickX = 0, _stickY = 0, _lt = 0, _rt = 0;

  ControllerStyle get style {
    if (_connected.isEmpty) return ControllerStyle.none;
    final n = _connected.values.last.toLowerCase();
    if (n.contains('dualsense') || n.contains('dualshock') || n.contains('playstation') || n.contains('ps4') ||
        n.contains('ps5') || n.contains('sony') || n.contains('wireless controller')) {
      return ControllerStyle.playstation;
    }
    if (n.contains('xbox') || n.contains('xinput') || n.contains('microsoft')) return ControllerStyle.xbox;
    return ControllerStyle.generic;
  }

  String? get controllerName => _connected.isEmpty ? null : _connected.values.last;

  Future<void> init() async {
    try {
      for (final g in await Gamepads.list()) {
        _connected[g.id] = g.name;
      }
      _conn = Gamepads.connectionEvents.listen((e) {
        if (e.type == GamepadConnectionEventType.connected) {
          _connected[e.gamepadId] = e.name;
          appLog.i('Gamepad', 'Conectado: ${e.name}');
        } else {
          _connected.remove(e.gamepadId);
          appLog.i('Gamepad', 'Desconectado: ${e.name}');
        }
        notifyListeners();
      });
      _sub = Gamepads.normalizedEvents.listen(_onEvent);
      notifyListeners();
    } catch (e) {
      appLog.w('Gamepad', 'Suporte a controles indisponível nesta plataforma', e);
    }
  }

  void _onEvent(NormalizedGamepadEvent e) {
    if (!_connected.containsKey(e.gamepadId)) {
      _connected[e.gamepadId] = 'Controle';
      notifyListeners();
    }
    final b = e.button;
    if (b != null) {
      final action = switch (b) {
        GamepadButton.dpadUp => PadAction.up,
        GamepadButton.dpadDown => PadAction.down,
        GamepadButton.dpadLeft => PadAction.left,
        GamepadButton.dpadRight => PadAction.right,
        GamepadButton.a => PadAction.confirm,
        GamepadButton.b => PadAction.back,
        GamepadButton.x => PadAction.secondary,
        GamepadButton.y => PadAction.search,
        GamepadButton.leftBumper => PadAction.prevSection,
        GamepadButton.rightBumper => PadAction.nextSection,
        GamepadButton.leftTrigger => PadAction.fastBack,
        GamepadButton.rightTrigger => PadAction.fastForward,
        GamepadButton.start || GamepadButton.home => PadAction.menu,
        _ => null,
      };
      if (action == null) return;
      final repeatable = action.index <= PadAction.right.index || action == PadAction.fastBack || action == PadAction.fastForward;
      _setPressed(action, e.value > 0.5, repeatable: repeatable);
      return;
    }

    switch (e.axis) {
      case GamepadAxis.leftStickX:
        _stickX = e.value;
        _setPressed(PadAction.right, _stickX > 0.6 || (_held.contains(PadAction.right) && _stickX > 0.3));
        _setPressed(PadAction.left, _stickX < -0.6 || (_held.contains(PadAction.left) && _stickX < -0.3));
      case GamepadAxis.leftStickY:
        _stickY = e.value; // +1 = para cima
        _setPressed(PadAction.up, _stickY > 0.6 || (_held.contains(PadAction.up) && _stickY > 0.3));
        _setPressed(PadAction.down, _stickY < -0.6 || (_held.contains(PadAction.down) && _stickY < -0.3));
      case GamepadAxis.leftTrigger:
        _lt = e.value;
        _setPressed(PadAction.fastBack, _lt > 0.6);
      case GamepadAxis.rightTrigger:
        _rt = e.value;
        _setPressed(PadAction.fastForward, _rt > 0.6);
      default:
        break;
    }
  }

  void _setPressed(PadAction a, bool pressed, {bool repeatable = true}) {
    if (pressed) {
      if (_held.contains(a)) return;
      _held.add(a);
      _fire(a);
      if (repeatable) {
        // Repetição ao segurar: 380 ms de atraso e depois a cada 110 ms.
        _repeat[a] = Timer(const Duration(milliseconds: 380), () {
          if (_held.contains(a)) _repeat[a] = Timer.periodic(const Duration(milliseconds: 110), (_) => _fire(a));
        });
      }
    } else if (_held.remove(a)) {
      _repeat.remove(a)?.cancel();
    }
  }

  final Set<PadAction> _held = {};

  void _fire(PadAction a) {
    final now = DateTime.now();
    // Evita eventos duplicados (botão + eixo do mesmo gatilho).
    final last = _lastFire[a];
    if (last != null && now.difference(last) < const Duration(milliseconds: 60)) return;
    _lastFire[a] = now;
    _router.dispatch(a);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _conn?.cancel();
    for (final t in _repeat.values) {
      t.cancel();
    }
    super.dispose();
  }
}
