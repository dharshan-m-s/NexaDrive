import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_typography.dart';
import '../../core/utils/file_kind.dart';

/// The single visual family for folders and file formats.
///
/// No Material file icons, emoji or mixed icon packs are used for content. The
/// silhouette, proportions and format mark are shared by list rows, grid
/// items, search, shared files and dashboard sections.
class NexaFileGlyph extends StatelessWidget {
  final String name;
  final String? type;
  final FileFormat? format;
  final double size;
  final bool showMark;
  final Color? color;

  const NexaFileGlyph({
    super.key,
    required this.name,
    this.type,
    this.format,
    this.size = 40,
    this.showMark = true,
    this.color,
  });

  const NexaFileGlyph.folder({
    super.key,
    this.name = '',
    this.size = 40,
    this.color,
  })  : type = 'folder',
        format = FileFormat.folder,
        showMark = false;

  @override
  Widget build(BuildContext context) {
    final resolved = format ?? FileKind.formatOf(name, type: type ?? 'file');
    final brightness = Theme.of(context).colorScheme.brightness;
    final tint = color ?? FileKind.formatTint(resolved, brightness);
    final mark = showMark ? FileKind.formatMark(resolved, name) : '';

    final semantics = resolved == FileFormat.folder
        ? 'Folder'
        : FileKind.label(FileKind.category(name: name, type: type ?? 'file'));

    return Semantics(
      label: semantics,
      child: SizedBox(
        width: size,
        height: size,
        child: resolved == FileFormat.folder
            ? CustomPaint(
                painter: _FolderPainter(tint: tint),
                size: Size.square(size),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DocumentPainter(
                        tint: tint,
                        archive: resolved == FileFormat.archive,
                      ),
                    ),
                  ),
                  if (mark.isNotEmpty)
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          size * 0.10,
                          size * 0.34,
                          size * 0.10,
                          size * 0.12,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            mark,
                            maxLines: 1,
                            style: AppTextStyle.caption.copyWith(
                              color: tint,
                              fontSize: size * 0.21,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FolderPainter extends CustomPainter {
  final Color tint;

  const _FolderPainter({required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dark = Color.lerp(tint, AppColors.inkLight, 0.22) ?? tint;

    final tab = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.04, h * 0.20, w * 0.48, h * 0.28),
      topLeft: Radius.circular(w * 0.14),
      topRight: Radius.circular(w * 0.14),
    );
    canvas.drawRRect(tab, Paint()..color = dark);

    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.04, h * 0.34, w * 0.92, h * 0.62),
      topLeft: Radius.circular(w * 0.10),
      topRight: Radius.circular(w * 0.10),
      bottomLeft: Radius.circular(w * 0.12),
      bottomRight: Radius.circular(w * 0.12),
    );
    canvas.drawRRect(body, Paint()..color = tint);

    canvas.drawLine(
      Offset(w * 0.10, h * 0.47),
      Offset(w * 0.90, h * 0.47),
      Paint()
        ..color = dark.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _FolderPainter oldDelegate) =>
      oldDelegate.tint != tint;
}

class _DocumentPainter extends CustomPainter {
  final Color tint;
  final bool archive;

  const _DocumentPainter({required this.tint, required this.archive});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fold = w * 0.24;
    final inset = w * 0.06;
    final radius = Radius.circular(w * 0.12);
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(inset, h * 0.04, w - inset * 2, h * 0.92),
      topLeft: radius,
      topRight: radius,
      bottomLeft: radius,
      bottomRight: radius,
    );

    canvas.drawRRect(
      body,
      Paint()..color = tint.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = tint
        ..strokeWidth = 1.4,
    );

    final foldPath = Path()
      ..moveTo(w - inset - fold, h * 0.045)
      ..lineTo(w - inset - 1, h * 0.045 + fold * 0.8)
      ..lineTo(w - inset - fold, h * 0.045 + fold * 0.8)
      ..close();
    canvas.drawPath(foldPath, Paint()..color = tint.withValues(alpha: 0.28));

    canvas.drawLine(
      Offset(w - inset - fold, h * 0.045),
      Offset(w - inset - fold, h * 0.045 + fold * 0.8),
      Paint()
        ..color = tint.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );

    if (archive) {
      for (final fraction in [0.24, 0.31]) {
        canvas.drawLine(
          Offset(w * 0.22, h * fraction),
          Offset(w * 0.62, h * fraction),
          Paint()
            ..color = tint.withValues(alpha: 0.45)
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentPainter oldDelegate) =>
      oldDelegate.tint != tint || oldDelegate.archive != archive;
}
