import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/format.dart';
import 'nexa_page.dart';
import 'nexa_surface.dart';

/// One UI "Download to open externally" fallback used for formats NexaDrive
/// can't render in-app yet (PDF pages, video, audio).
class DownloadToViewScreen extends StatefulWidget {
  final FileEntry file;
  final Future<void> Function(String path, String outPath) downloader;
  final IconData icon;
  final String subtitle;

  const DownloadToViewScreen({
    super.key,
    required this.file,
    required this.downloader,
    required this.icon,
    required this.subtitle,
  });

  @override
  State<DownloadToViewScreen> createState() => _DownloadToViewScreenState();
}

class _DownloadToViewScreenState extends State<DownloadToViewScreen> {
  bool _busy = false;
  String? _done;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _done = null;
    });
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save ${widget.file.name}',
        fileName: widget.file.name,
        bytes: Uint8List(0),
      );
      final outPath = uri?.toFilePath();
      if (outPath == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await widget.downloader(widget.file.path, outPath);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = 'Saved to $outPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.labelSecondaryFor(brightness);

    return NexaPage(
      title: 'Download to open',
      subtitle: widget.file.name,
      headerIcon: widget.icon,
      scrollable: false,
      padding: const EdgeInsets.all(AppDimens.pageMargin),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: NexaSurface(
            level: NexaSurfaceLevel.surface,
            radius: AppDimens.radiusXLarge,
            padding: const EdgeInsets.all(AppDimens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.accentContainerFor(brightness),
                      borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Icon(widget.icon, size: 42, color: AppColors.accentTextFor(brightness)),
                  ),
                ),
                const SizedBox(height: AppDimens.space20),
                Text(
                  widget.file.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.title2.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.body.copyWith(color: secondary),
                ),
                if (widget.file.size != null) ...[
                  const SizedBox(height: AppDimens.space16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space12,
                      vertical: AppDimens.space10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.fillFor(brightness),
                      borderRadius: BorderRadius.circular(AppDimens.radiusMedium),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.insert_drive_file_outlined, size: 16, color: secondary),
                        const SizedBox(width: AppDimens.space8),
                        Text(
                          Format.bytes(widget.file.size),
                          style: AppTextStyle.caption1.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppDimens.space24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_busy ? 'Downloading…' : 'Download file'),
                  ),
                ),
                if (_done != null) ...[
                  const SizedBox(height: AppDimens.space12),
                  Text(
                    _done!,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.caption.copyWith(color: AppColors.successFor(brightness)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
