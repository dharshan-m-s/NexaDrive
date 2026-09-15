import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';

/// A draggable crop rectangle for scan page editing.
///
/// Operates in normalized (0..1) coordinates relative to the displayed image.
/// The image display box is computed with BoxFit.contain semantics so the
/// overlay tracks the picture pixel-for-pixel even when letterboxed.
class CropOverlay extends StatefulWidget {
  final Rect value;
  final double aspect;
  final ValueChanged<Rect> onChanged;

  const CropOverlay({
    super.key,
    required this.value,
    required this.aspect,
    required this.onChanged,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  _DragHandle? _handle;
  Rect? _dragStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = _fittedRect(constraints.biggest, widget.aspect);
        return ClipRect(
          child: SizedBox.expand(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _beginDrag(d.localPosition, box),
              onPanUpdate: (d) => _updateDrag(d.localPosition, box),
              onPanEnd: (_) => _handle = null,
              child: CustomPaint(
                painter: _CropPainter(
                  rect: _displayRect(box),
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _beginDrag(Offset pos, Rect box) {
    _handle = _cornerAt(pos, _displayRect(box));
    _dragStart = widget.value;
  }

  void _updateDrag(Offset pos, Rect box) {
    final r = _displayRect(box);
    final h = _handle;
    final start = _dragStart;
    if (h == null || start == null) return;

    final dx = ((pos.dx - r.left) / r.width).clamp(0.0, 1.0);
    final dy = ((pos.dy - r.top) / r.height).clamp(0.0, 1.0);
    var v = widget.value;
    const minSize = 0.06;

    switch (h) {
      case _DragHandle.nw:
        v = Rect.fromLTRB(
          dx.clamp(0, v.right - minSize),
          dy.clamp(0, v.bottom - minSize),
          v.right,
          v.bottom,
        );
      case _DragHandle.ne:
        v = Rect.fromLTRB(
          v.left,
          dy.clamp(0, v.bottom - minSize),
          dx.clamp(v.left + minSize, 1),
          v.bottom,
        );
      case _DragHandle.sw:
        v = Rect.fromLTRB(
          dx.clamp(0, v.right - minSize),
          v.top,
          v.right,
          dy.clamp(v.top + minSize, 1),
        );
      case _DragHandle.se:
        v = Rect.fromLTRB(
          v.left,
          v.top,
          dx.clamp(v.left + minSize, 1),
          dy.clamp(v.top + minSize, 1),
        );
      case _DragHandle.none:
        final size = widget.value.size;
        v = Rect.fromLTWH(
          (start.left + dx - start.left).clamp(0.0, 1 - size.width),
          (start.top + dy - start.top).clamp(0.0, 1 - size.height),
          size.width,
          size.height,
        );
    }
    if (v != widget.value) widget.onChanged(v);
  }

  _DragHandle _cornerAt(Offset pos, Rect r) {
    const halo = 44.0;
    if ((pos - r.topLeft).distance < halo) return _DragHandle.nw;
    if ((pos - Offset(r.right, r.top)).distance < halo) return _DragHandle.ne;
    if ((pos - Offset(r.left, r.bottom)).distance < halo) {
      return _DragHandle.sw;
    }
    if ((pos - r.bottomRight).distance < halo) return _DragHandle.se;
    if (r.contains(pos)) return _DragHandle.none;
    return _DragHandle.none;
  }

  Rect _displayRect(Rect box) {
    final v = widget.value;
    return Rect.fromLTRB(
      box.left + v.left * box.width,
      box.top + v.top * box.height,
      box.left + v.right * box.width,
      box.top + v.bottom * box.height,
    );
  }

  Rect _fittedRect(Size available, double aspect) {
    final availAspect = available.width / available.height;
    double w, h;
    if (availAspect > aspect) {
      h = available.height;
      w = h * aspect;
    } else {
      w = available.width;
      h = w / aspect;
    }
    return Rect.fromLTWH(
      (available.width - w) / 2,
      (available.height - h) / 2,
      w,
      h,
    );
  }
}

enum _DragHandle { nw, ne, sw, se, none }

class _CropPainter extends CustomPainter {
  final Rect rect;
  final Color color;

  const _CropPainter({required this.rect, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0x99000000);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, scrim);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawRect(rect, border);

    // Rule-of-thirds guide.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.45);
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    // Corner handles.
    final handlePaint = Paint()..color = color;
    const radius = 12.0;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    for (final c in corners) {
      canvas.drawCircle(c, radius, handlePaint);
      canvas.drawCircle(
        c,
        radius - 4,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}