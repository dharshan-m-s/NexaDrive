import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../services/api.dart';

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
      appBar: AppBar(
        title: Text(widget.file.name),
      ),
      body: SafeArea(
        child: switch ((_text, _error)) {
          (null, null) => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          (_, final String error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.pageMargin),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.rowSubtitle.copyWith(
                    color: AppColors.errorFor(brightness),
                  ),
                ),
              ),
            ),
          (final String text, _) => Container(
              color: brightness == Brightness.dark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimens.pageMargin),
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textPrimaryFor(brightness),
                  ),
                ),
              ),
            ),
        },
      ),
    );
  }
}