import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ações de navegação independentes do dispositivo (controle, teclado, toque).
enum PadAction {
  up,
  down,
  left,
  right,
  confirm, // A / ✕
  back, // B / ○
  secondary, // X / □  (favoritar)
  search, // Y / △
  prevSection, // LB / L1
  nextSection, // RB / R1
  fastBack, // LT / L2
  fastForward, // RT / R2
  menu, // Start / Options
}

/// Um handler retorna `true` quando consumiu a ação.
typedef PadHandler = bool Function(PadAction action);

/// Roteador global de entrada. Telas registram handlers (pilha: o mais recente
/// tem prioridade) para, por exemplo, trocar de aba com LB/RB. O que ninguém
/// tratar cai no comportamento padrão: mover o foco, ativar, voltar.
class InputRouter {
  InputRouter._();
  static final instance = InputRouter._();

  final navigatorKey = GlobalKey<NavigatorState>();
  final List<PadHandler> _stack = [];

  void push(PadHandler h) => _stack.add(h);
  void remove(PadHandler h) => _stack.remove(h);

  bool dispatch(PadAction a) {
    for (final h in _stack.reversed.toList()) {
      if (h(a)) return true;
    }
    return _default(a);
  }

  bool _default(PadAction a) {
    switch (a) {
      case PadAction.up:
        return moveFocus(TraversalDirection.up);
      case PadAction.down:
        return moveFocus(TraversalDirection.down);
      case PadAction.left:
        return moveFocus(TraversalDirection.left);
      case PadAction.right:
        return moveFocus(TraversalDirection.right);
      case PadAction.confirm:
        return activateFocused();
      case PadAction.back:
        navigatorKey.currentState?.maybePop();
        return true;
      case PadAction.fastBack:
        return fastScroll(forward: false);
      case PadAction.fastForward:
        return fastScroll(forward: true);
      default:
        return false;
    }
  }

  static bool moveFocus(TraversalDirection dir) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node.context == null || node == FocusManager.instance.rootScope) {
      FocusManager.instance.rootScope.nextFocus();
      return true;
    }
    if (!node.focusInDirection(dir)) {
      // Sem vizinho naquela direção: tenta a ordem de travessia.
      if (dir == TraversalDirection.down || dir == TraversalDirection.right) return false;
    }
    return true;
  }

  static bool activateFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    final r = Actions.maybeInvoke(ctx, const ActivateIntent());
    return r != null;
  }

  /// LT/RT: pula vários itens na direção do scroll que contém o foco.
  static bool fastScroll({required bool forward}) {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || ctx == null) return false;
    final scrollable = Scrollable.maybeOf(ctx);
    final axis = scrollable?.position.axis ?? Axis.vertical;
    final dir = axis == Axis.horizontal
        ? (forward ? TraversalDirection.right : TraversalDirection.left)
        : (forward ? TraversalDirection.down : TraversalDirection.up);
    for (var i = 0; i < 5; i++) {
      final current = FocusManager.instance.primaryFocus;
      if (current == null || !current.focusInDirection(dir)) break;
    }
    return true;
  }

  /// Usuário está digitando em um campo de texto?
  static bool get isEditingText {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Teclado físico → ações. Setas e Enter ficam com os atalhos padrão do Flutter.
  KeyEventResult handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final editing = isEditingText;
    PadAction? a;
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.gameButtonB || k == LogicalKeyboardKey.goBack) {
      a = PadAction.back;
    } else if (k == LogicalKeyboardKey.gameButtonLeft1 || (!editing && k == LogicalKeyboardKey.keyQ)) {
      a = PadAction.prevSection;
    } else if (k == LogicalKeyboardKey.gameButtonRight1 || (!editing && k == LogicalKeyboardKey.keyE)) {
      a = PadAction.nextSection;
    } else if (k == LogicalKeyboardKey.gameButtonLeft2 || k == LogicalKeyboardKey.pageUp) {
      a = PadAction.fastBack;
    } else if (k == LogicalKeyboardKey.gameButtonRight2 || k == LogicalKeyboardKey.pageDown) {
      a = PadAction.fastForward;
    } else if (k == LogicalKeyboardKey.gameButtonY || (!editing && k == LogicalKeyboardKey.slash) || k == LogicalKeyboardKey.f3) {
      a = PadAction.search;
    } else if (k == LogicalKeyboardKey.gameButtonX || (!editing && k == LogicalKeyboardKey.keyF)) {
      a = PadAction.secondary;
    } else if (k == LogicalKeyboardKey.gameButtonStart || k == LogicalKeyboardKey.f1) {
      a = PadAction.menu;
    } else if (k == LogicalKeyboardKey.gameButtonA) {
      a = PadAction.confirm;
    }
    if (a == null) return KeyEventResult.ignored;
    if (a == PadAction.back && editing) {
      // Esc no campo de texto: só tira o foco do campo.
      FocusManager.instance.primaryFocus?.unfocus();
      return KeyEventResult.handled;
    }
    return dispatch(a) ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}

/// Mixin para States que querem tratar ações de controle enquanto visíveis.
mixin PadHandlerMixin<T extends StatefulWidget> on State<T> {
  bool onPad(PadAction action);

  bool _handler(PadAction a) => mounted && (ModalRoute.of(context)?.isCurrent ?? true) && onPad(a);

  @override
  void initState() {
    super.initState();
    InputRouter.instance.push(_handler);
  }

  @override
  void dispose() {
    InputRouter.instance.remove(_handler);
    super.dispose();
  }
}
