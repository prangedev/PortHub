import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/game.dart';
import '../../ui/input/input_router.dart';
import '../../ui/theme.dart';
import '../../widgets/focusable.dart';

/// Galeria de imagens extraídas do README (sem badges).
class GalleryTab extends StatelessWidget {
  const GalleryTab({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final imgs = game.gallery;
    if (imgs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Este repositório não tem imagens no README.', style: TextStyle(color: PH.textDim)),
      );
    }
    final h = PH.compact(context) ? 180.0 : 300.0;
    return SizedBox(
      height: h + 24,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: imgs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) => Focusable(
          scrollAlignment: 0.3,
          onActivate: () => _open(context, i),
          builder: (context, focused) => ClipRRect(
            borderRadius: BorderRadius.circular(PH.radius),
            child: Container(
              color: PH.surface,
              height: h,
              constraints: BoxConstraints(minWidth: h * 0.8, maxWidth: h * 2),
              child: CachedNetworkImage(
                imageUrl: imgs[i],
                fit: BoxFit.cover,
                height: h,
                placeholder: (_, _) => SizedBox(width: h * 16 / 9, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: (_, _, _) => SizedBox(width: h, child: const Icon(Icons.broken_image_outlined, color: PH.textFaint)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, int start) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => _Viewer(images: game.gallery, start: start),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    ));
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.images, required this.start});
  final List<String> images;
  final int start;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> with PadHandlerMixin {
  late final _ctrl = PageController(initialPage: widget.start);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  bool onPad(PadAction a) {
    if (a == PadAction.left || a == PadAction.fastBack) {
      _step(-1);
      return true;
    }
    if (a == PadAction.right || a == PadAction.fastForward) {
      _step(1);
      return true;
    }
    return false;
  }

  void _step(int d) => _ctrl.animateToPage(
        ((_ctrl.page?.round() ?? 0) + d).clamp(0, widget.images.length - 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft) {
            _step(-1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            _step(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.images.length,
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(child: CachedNetworkImage(imageUrl: widget.images[i], fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 24,
            right: 24,
            child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ),
        ]),
      ),
    );
  }
}
