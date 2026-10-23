import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'focusable.dart';

/// Botão grande navegável por controle (Jogar / Instalar / Atualizar...).
class PHButton extends StatelessWidget {
  const PHButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient,
    this.autofocus = false,
    this.focusNode,
    this.dense = false,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool dense;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Focusable(
        autofocus: autofocus,
        focusNode: focusNode,
        focusScale: 1.04,
        borderRadius: 8,
        onActivate: onPressed,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 22, vertical: dense ? 9 : 14),
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null ? (focused ? Colors.white : (color ?? PH.surfaceHi)) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 18 : 22, color: gradient == null && focused ? PH.bg : Colors.white),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 13.5 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: gradient == null && focused ? PH.bg : Colors.white,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Botão redondo só com ícone (favorito, GitHub...).
class PHIconButton extends StatelessWidget {
  const PHIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.active = false, this.activeColor});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final btn = Focusable(
      borderRadius: 24,
      focusScale: 1.1,
      onActivate: onPressed,
      builder: (context, focused) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: focused ? Colors.white : PH.surfaceHi, shape: BoxShape.circle),
        child: Icon(icon, color: focused ? PH.bg : (active ? (activeColor ?? PH.accent) : PH.text)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Chip de filtro selecionável.
class PHChip extends StatelessWidget {
  const PHChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Focusable(
        borderRadius: 20,
        focusScale: 1.05,
        glow: false,
        onActivate: onTap,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PH.accent : (focused ? PH.surfaceHi : PH.surface),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.white : PH.textDim), const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: selected ? Colors.white : PH.text)),
          ]),
        ),
      );
}
