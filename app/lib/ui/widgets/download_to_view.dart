import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/format.dart';

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
    final secondary = AppColors.textSecondaryFor(brightness);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: brightness == Brightness.dark
                        ? accent.withValues(alpha: 0.16)
                        : accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                  ),
                  child: Icon(widget.icon, size: 44, color: accent),
                ),
              ),
              const SizedBox(height: AppDimens.space24),
              Text(
                widget.file.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.sectionHeader.copyWith(
                  color: AppColors.textPrimaryFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppDimens.space8),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: AppTextStyle.rowSubtitle.copyWith(color: secondary),
              ),
              if (widget.file.size != null) ...[
                const SizedBox(height: AppDimens.space16),
                Text(
                  '${Format.bytes(widget.file.size)} · '
                  '${Format.shortDateTime(widget.file.modified?.toLocal())}',
                  textAlign: TextAlign.center,
                  style: AppTextStyle.caption.copyWith(color: secondary),
                ),
              ],
              const SizedBox(height: AppDimens.space32),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_busy ? 'Downloading…' : 'Download'),
                ),
              ),
              if (_done != null) ...[
                const SizedBox(height: AppDimens.space12),
                Text(
                  _done!,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.caption
                      .copyWith(color: AppColors.successFor(brightness)),
                ),
              ],
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}