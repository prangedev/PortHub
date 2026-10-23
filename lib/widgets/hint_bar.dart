import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/gamepad_service.dart';
import '../ui/theme.dart';

enum PadGlyph { a, b, x, y, lb, rb, lt, rt, start }

/// Glifo do botão conforme o controle conectado (Xbox: A/B/X/Y; PlayStation: ✕/○/□/△).
class ButtonGlyph extends StatelessWidget {
  const ButtonGlyph(this.glyph, {super.key, this.size = 22});
  final PadGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = context.watch<GamepadService>().style;
    final ps = style == ControllerStyle.playstation;
    final keyboard = style == ControllerStyle.none;
    final (label, color) = switch (glyph) {
      PadGlyph.a => (keyboard ? 'Enter' : ps ? '✕' : 'A', ps ? const Color(0xFF7DA7FF) : PH.green),
      PadGlyph.b => (keyboard ? 'Esc' : ps ? '○' : 'B', ps ? const Color(0xFFFF6B7A) : PH.red),
      PadGlyph.x => (keyboard ? 'F' : ps ? '□' : 'X', ps ? const Color(0xFFE38BE0) : PH.accent),
      PadGlyph.y => (keyboard ? '/' : ps ? '△' : 'Y', ps ? const Color(0xFF52D8B0) : PH.yellow),
      PadGlyph.lb => (keyboard ? 'Q' : ps ? 'L1' : 'LB', PH.textDim),
      PadGlyph.rb => (keyboard ? 'E' : ps ? 'R1' : 'RB', PH.textDim),
      PadGlyph.lt => (keyboard ? 'PgUp' : ps ? 'L2' : 'LT', PH.textDim),
      PadGlyph.rt => (keyboard ? 'PgDn' : ps ? 'R2' : 'RT', PH.textDim),
      PadGlyph.start => (keyboard ? 'F1' : ps ? 'Options' : 'Menu', PH.textDim),
    };
    final round = !keyboard && glyph.index <= PadGlyph.y.index;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: round ? 0 : 6),
      decoration: BoxDecoration(
        color: round ? color : Colors.white12,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(5),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(label,
            style: TextStyle(
              fontSize: size * (label.length > 2 ? 0.42 : 0.55),
              fontWeight: FontWeight.w900,
              color: round ? Colors.black87 : PH.text,
            )),
      ),
    );
  }
}

/// Barra inferior com as dicas de controle (como na Big Picture).
class HintBar extends StatelessWidget {
  const HintBar({super.key, required this.hints, this.leading});
  final List<(PadGlyph, String)> hints;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final compact = PH.compact(context);
    return Container(
      height: compact ? 44 : 54,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 40),
      decoration: const BoxDecoration(
        color: Color(0xE60A0D12),
        border: Border(top: BorderSide(color: PH.stroke)),
      ),
      child: Row(children: [
        if (leading != null) Expanded(child: leading!) else const Spacer(),
        for (final (g, label) in compact ? hints.take(3) : hints) ...[
          ButtonGlyph(g),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: PH.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 22),
        ],
      ]),
    );
  }
}
