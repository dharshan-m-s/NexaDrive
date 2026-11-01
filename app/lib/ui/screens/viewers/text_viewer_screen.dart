import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/format.dart';
import '../../../../services/api.dart';
import '../../widgets/nexa_components.dart';

/// In-app text reader for .txt/.md/.log/.json and source files.
/// Downloads the file and renders it as wrapped monospace text.
class TextViewerScreen extends StatefulWidget {
  final FileEntry file;
  final Api api;
  const TextViewerScreen({super.key, required this.file, required this.api});

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  static const int _maxPreviewBytes = 8 * 1024 * 1024;
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    File? temporary;
    try {
      if ((widget.file.size ?? 0) > _maxPreviewBytes) {
        throw StateError(
          'This file is larger than the 8 MB in-app text preview limit. '
          'Download it to open with a dedicated editor.',
        );
      }
      final directory = await getTemporaryDirectory();
      temporary = File(
        '${directory.path}/nexadrive-text-${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      // Stream the response to disk first so a unexpectedly large file cannot
      // fill the Dart heap before its actual size is checked.
      await widget.api.downloadToFile(widget.file.path, temporary.path);
      final length = await temporary.length();
      if (length > _maxPreviewBytes) {
        throw StateError(
          'This file is larger than the 8 MB in-app text preview limit. '
          'Download it to open with a dedicated editor.',
        );
      }
      final bytes = await temporary.readAsBytes();
      final decoded =
          utf8.decode(bytes, allowMalformed: true).replaceAll('\uFFFD', '');
      if (!mounted) return;
      setState(() => _text = decoded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      try {
        await temporary?.delete();
      } catch (_) {}
    }
  }

  Future<void> _copyText() async {
    final value = _text;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Text copied')));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: widget.file.name,
          subtitle:
              widget.file.size == null ? null : Format.bytes(widget.file.size),
          leading: const NexaBackButton(),
          headerAction: _text == null
              ? null
              : IconButton(
                  tooltip: 'Copy all text',
                  onPressed: _copyText,
                  icon: const Icon(Icons.copy_all_outlined),
                ),
          body: switch ((_text, _error)) {
            (null, null) => const NexaLoadingBlock(),
            (_, final String error) => NexaEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not read this file',
                hint: error,
                actionLabel: 'Retry',
                actionIcon: Icons.refresh_rounded,
                onAction: () {
                  setState(() {
                    _text = null;
                    _error = null;
                  });
                  _load();
                },
              ),
            (final String text, _) => Container(
                width: double.infinity,
                color: brightness == Brightness.dark
                    ? AppColors.surfaceDark
                    : AppColors.surfaceLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimens.pageMargin,
                        AppDimens.space12,
                        AppDimens.pageMargin,
                        AppDimens.space8,
                      ),
                      child: Text(
                        '${text.isEmpty ? 0 : '\n'.allMatches(text).length + 1} lines · '
                        '${text.length} characters',
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.pageMargin,
                          AppDimens.space8,
                          AppDimens.pageMargin,
                          AppDimens.pageMargin,
                        ),
                        child: SelectableText(
                          text,
                          style: AppTextStyle.code.copyWith(
                            color: AppColors.textPrimaryFor(brightness),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          },
        ),
      ),
    );
  }
}
