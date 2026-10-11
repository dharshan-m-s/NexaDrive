import 'dart:convert';
import 'package:flutter/material.dart';
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
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.api.download(widget.file.path);
      final decoded =
          utf8.decode(bytes, allowMalformed: true).replaceAll('\uFFFD', '');
      if (!mounted) return;
      setState(() => _text = decoded);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
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
                padding: const EdgeInsets.all(AppDimens.pageMargin),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: AppTextStyle.code.copyWith(
                      color: AppColors.textPrimaryFor(brightness),
                    ),
                  ),
                ),
              ),
          },
        ),
      ),
    );
  }
}
