import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';

/// Elemento navegável por controle, teclado, mouse e toque.
///
/// - Foco (D-pad/setas/Tab): escala suave + borda azul brilhante, estilo Big Picture;
/// - A/Enter/Espaço/toque: [onActivate];
/// - Ao receber foco, rola o pai para deixar o item visível.
class Focusable extends StatefulWidget {
  const Focusable({
    super.key,
    required this.builder,
    this.onActivate,
    this.onFocusChange,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.focusScale = 1.06,
    this.borderRadius = PH.radius,
    this.glow = true,
    this.scrollAlignment = 0.5,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onActivate;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final double focusScale;
  final double borderRadius;
  final bool glow;

  /// Posição desejada no viewport ao rolar (0 = início, 0.5 = centro).
  final double scrollAlignment;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;
  bool _hover = false;

  void _onFocus(bool f) {
    setState(() => _focused = f);
    widget.onFocusChange?.call(f);
    if (f) _reveal();
  }

  /// Rola para mostrar o item: na lista horizontal mais próxima usa
  /// [Focusable.scrollAlignment]; nas listas verticais rola o mínimo necessário
  /// (assim o destaque do topo da Home não some ao focar a primeira prateleira).
  void _reveal() {
    final target = context.findRenderObject();
    if (target == null || !target.attached) return;
    var scrollable = Scrollable.maybeOf(context);
    RenderObject from = target;
    var inner = true;
    while (scrollable != null) {
      final viewport = RenderAbstractViewport.maybeOf(from);
      if (viewport == null) break;
      final pos = scrollable.position;
      double? to;
      if (inner && pos.axis == Axis.horizontal) {
        to = viewport.getOffsetToReveal(target, widget.scrollAlignment).offset;
      } else {
        final top = viewport.getOffsetToReveal(target, 0).offset - 72; // espaço para o título da seção
        final bottom = viewport.getOffsetToReveal(target, 1).offset + 24;
        if (pos.pixels > top) {
          to = top;
        } else if (pos.pixels < bottom) {
          to = bottom;
        }
      }
      if (to != null && pos.hasContentDimensions) {
        to = to.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((to - pos.pixels).abs() > 1) {
          pos.animateTo(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        }
      }
      final ro = scrollable.context.findRenderObject();
      if (ro == null) break;
      from = ro;
      scrollable = Scrollable.maybeOf(scrollable.context);
      inner = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocus,
      onShowHoverHighlight: (h) => setState(() => _hover = h),
      mouseCursor: widget.onActivate != null ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onActivate?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _focused ? widget.focusScale : (_hover ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius + 2),
              border: Border.all(
                color: _focused ? PH.accent : (active ? Colors.white24 : Colors.transparent),
                width: 2,
              ),
              boxShadow: _focused && widget.glow
                  ? [BoxShadow(color: PH.accent.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 1)]
                  : const [],
            ),
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}
