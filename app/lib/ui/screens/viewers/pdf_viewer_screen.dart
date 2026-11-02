import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import '../../../../core/design/app_dimensions.dart';
import '../../../../core/models/file_entry.dart';
import '../../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/download_to_view.dart';
import '../../widgets/nexa_components.dart';

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
  bool _loading = true;
  String? _error;

  /// Whether the platform can render PDFs at all. Resolved once per load.
  bool _supported = false;

  /// Opened exactly once. Creating these inside `build()` opened a fresh native
  /// pdfium document and a new controller on every frame, and nothing ever
  /// closed them — a slow native-memory leak while the viewer stayed open.
  PdfControllerPinch? _controller;
  Future<PdfDocument>? _document;
  String? _localPdfPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _closeDocument();
    super.dispose();
  }

  /// Closes the resolved document once. The open future may still be in flight
  /// at dispose time, so closure is chained onto it instead of assumed done.
  void _closeDocument() {
    final pending = _document;
    _document = null;
    if (pending == null) return;
    pending.then((document) async {
      if (!document.isClosed) await document.close();
      await _deleteLocalPdf();
    }).catchError((Object _) async {
      await _deleteLocalPdf();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    File? localFile;
    try {
      // Probe support before downloading, so unsupported platforms never
      // transfer a document they cannot render.
      final supported = await hasPdfSupport();
      if (!mounted) return;
      if (!supported) {
        setState(() {
          _supported = false;
          _loading = false;
        });
        return;
      }
      final directory = await getTemporaryDirectory();
      localFile = File(
        '${directory.path}/nexadrive-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      _localPdfPath = localFile.path;
      // The HTTP body is streamed to disk. pdfium opens that file directly,
      // avoiding a full Uint8List plus the renderer's native document copy.
      await widget.api.downloadToFile(widget.file.path, localFile.path);
      if (!mounted) {
        await _deleteLocalPdf();
        return;
      }
      final document = PdfDocument.openFile(localFile.path);
      _document = document;
      _controller = PdfControllerPinch(document: document, initialPage: 1);
      setState(() {
        _supported = true;
        _loading = false;
      });
      document.then((opened) {
        if (!mounted && !opened.isClosed) opened.close();
      }).catchError((Object _) {});
    } catch (e) {
      await _deleteLocalPdf();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteLocalPdf() async {
    final path = _localPdfPath;
    _localPdfPath = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // The OS removes the temporary file later if it is already gone/in use.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NexaPage(
          title: widget.file.name,
          subtitle:
              widget.file.size == null ? null : Format.bytes(widget.file.size),
          leading: const NexaBackButton(),
          headerAction: (_error == null && _supported)
              ? IconButton(
                  tooltip: 'Download',
                  onPressed: () => _fallback(context),
                  icon: const Icon(Icons.download_outlined),
                )
              : null,
          // The rendered page runs edge to edge; the header carries the
          // chrome and the page itself must not be inset.
          padding: EdgeInsets.zero,
          body: _buildBody(Theme.of(context).brightness),
        ),
      ),
    );
  }

  Widget _buildBody(Brightness brightness) {
    if (_loading) {
      return const NexaLoadingBlock();
    }
    if (_error != null) {
      return NexaEmptyState(
        centered: true,
        icon: Icons.picture_as_pdf_outlined,
        title: 'Can\'t open this PDF',
        hint: _error,
        actionLabel: 'Download instead',
        onAction: () => _fallback(context),
      );
    }
    if (!_supported) {
      return NexaEmptyState(
        centered: true,
        icon: Icons.picture_as_pdf_outlined,
        title: 'PDF reader coming to this device',
        hint: 'Download the file and open it with your PDF app.',
        actionLabel: 'Download',
        onAction: () => _fallback(context),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return NexaEmptyState(
        centered: true,
        icon: Icons.picture_as_pdf_outlined,
        title: 'Can\'t open this PDF',
        hint: 'The document could not be prepared for viewing.',
        actionLabel: 'Download instead',
        onAction: () => _fallback(context),
      );
    }
    return PdfViewPinch(
      controller: controller,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => const NexaLoadingBlock(),
        pageLoaderBuilder: (_) =>
            const NexaLoadingBlock(inset: AppDimens.space24),
        errorBuilder: (_, error) => NexaEmptyState(
          centered: true,
          icon: Icons.error_outline_rounded,
          title: 'Can\'t render this page',
          hint: error.toString(),
          actionLabel: 'Download instead',
          onAction: () => _fallback(context),
        ),
      ),
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
