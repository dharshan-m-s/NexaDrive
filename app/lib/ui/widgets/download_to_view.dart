import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_dimensions.dart';
import '../../core/design/app_typography.dart';
import '../../core/models/file_entry.dart';
import '../../core/utils/format.dart';
import 'nexa_file_glyph.dart';
import 'nexa_page.dart';

/// Responsive save/open fallback used when a platform viewer cannot render a
/// particular file. In-app PDF, audio and video viewers remain the primary path
/// where the platform supports them.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NexaPage(
      title: 'Download to open',
      subtitle: widget.file.name,
      headerIcon: widget.icon,
      scrollable: true,
      padding: const EdgeInsets.all(AppDimens.pageMargin),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NexaFileGlyph(name: widget.file.name, size: 40),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.title3.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        if (widget.file.size != null) ...[
                          const SizedBox(height: AppDimens.space4),
                          Text(
                            Format.bytes(widget.file.size),
                            style: AppTextStyle.caption.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.space20),
              Text(
                widget.subtitle,
                style: AppTextStyle.body.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDimens.space20),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: AppDimens.space20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? SizedBox(
                          width: AppDimens.iconSmall,
                          height: AppDimens.iconSmall,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_busy ? 'Downloading…' : 'Download file'),
                ),
              ),
              if (_done != null) ...[
                const SizedBox(height: AppDimens.space12),
                Semantics(
                  label: 'Save result',
                  child: Text(
                    _done!,
                    style: AppTextStyle.bodySmall.copyWith(
                      color: AppColors.successFor(scheme.brightness),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
