import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../../widgets/download_to_view.dart';
import '../../widgets/one_ui_empty_state.dart';

/// One UI PDF viewer.
///
/// A real in-app renderer (pdfium) with pinch to zoom and a page scroller on
/// platforms with native PDF support (Android/iOS/Windows/macOS/web). Where
/// rendering is unavailable (Linux desktop) it degrades to a download-and-open
/// flow so the entry point is never a dead screen.
class PdfViewerScreen extends StatefulWidget {
  final FileEntry file;
  final Api api;
  const PdfViewerScreen({super.key, required this.file, required this.api});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.download(widget.file.path);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_error == null && _bytes != null)
            IconButton(
              tooltip: 'Download',
              onPressed: () => _fallback(context),
              icon: Icon(
                Icons.download_outlined,
                color: AppColors.accentTextFor(brightness),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(brightness)),
    );
  }

  Widget _buildBody(Brightness brightness) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return OneUiEmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Can\'t open this PDF',
        hint: _error,
        actionLabel: 'Download instead',
        onAction: () => _fallback(context),
      );
    }
    return FutureBuilder<bool>(
      future: hasPdfSupport(),
      builder: (context, snapshot) {
        final supported = snapshot.data == true;
        if (!supported) {
          return OneUiEmptyState(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF reader coming to this device',
            hint: 'Download the file and open it with your PDF app.',
            actionLabel: 'Download',
            onAction: () => _fallback(context),
          );
        }
        try {
          final document = PdfDocument.openData(_bytes!);
          return PdfViewPinch(
            controller: PdfControllerPinch(
              document: document,
              initialPage: 1,
            ),
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              pageLoaderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              errorBuilder: (_, error) => OneUiEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Can\'t render this page',
                hint: error.toString(),
                actionLabel: 'Download instead',
                onAction: () => _fallback(context),
              ),
            ),
          );
        } catch (e) {
          return OneUiEmptyState(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Can\'t open this PDF',
            hint: e.toString(),
            actionLabel: 'Download instead',
            onAction: () => _fallback(context),
          );
        }
      },
    );
  }

  void _fallback(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadToViewScreen(
          file: widget.file,
          icon: Icons.picture_as_pdf_rounded,
          subtitle: 'PDF files open best in a dedicated PDF reader.',
          downloader: widget.api.downloadToFile,
        ),
      ),
    );
  }
}