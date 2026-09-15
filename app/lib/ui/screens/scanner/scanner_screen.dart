import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/scan_processor.dart';
import 'scan_edit_screen.dart';
import 'scan_pages_screen.dart';

/// Full-featured document scanner — Adobe-Scan style.
///
/// Captures one or more pages; each lands in a filmstrip at the bottom.
/// Tapping a page opens the edit screen; the "done" button opens the pages
/// organizer where pages can be reordered, deleted, and saved as PDF.
class ScannerScreen extends StatefulWidget {
  final Api api;
  final String folder;
  const ScannerScreen({super.key, required this.api, this.folder = ''});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _busy = false;
  bool _flashOn = false;
  String? _error;

  final List<ScanPage> _pages = [];
  int _pageCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) _disposeController();
    if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setNoCamera();
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _controller = ctrl;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      _setNoCamera(e);
    }
  }

  void _setNoCamera([Object? e]) {
    _error = e is CameraException ? e.description : e?.toString();
    setState(() {
      _initializing = false;
      _controller = null;
    });
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await ctrl.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      final prepared = ScanProcessor.prepareOriginal(bytes);
      final page = ScanPage(original: prepared, number: ++_pageCounter);
      setState(() {
        _pages.add(page);
        _busy = false;
      });
      _toast('Page ${page.number} captured');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast((e is CameraException ? e.description : null) ?? 'Capture failed');
      _disposeController();
      _initCamera();
    }
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _flashOn = !_flashOn);
    try {
      await ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
  }

  Future<void> _importGallery() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final f in files) {
        final bytes = f.path == null
            ? await f.readAsBytes()
            : await File(f.path!).readAsBytes();
        final prepared = ScanProcessor.prepareOriginal(bytes);
        _pages.add(ScanPage(original: prepared, number: ++_pageCounter));
      }
      setState(() => _busy = false);
      _toast('${files.length} page(s) imported');
    } catch (e) {
      setState(() => _busy = false);
      _toast('Import failed: $e');
    }
  }

  Future<void> _openPages() async {
    if (_pages.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanPagesScreen(
          api: widget.api,
          folder: widget.folder,
          pages: _pages,
        ),
      ),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _editPage(int index) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanEditScreen(
          page: _pages[index],
          totalPages: _pages.length,
        ),
      ),
    );
    if (edited == true && mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_controller == null) return _pickerFallback();
    return _cameraView();
  }

  // ── Camera view ────────────────────────────────────────────────────────

  Widget _cameraView() {
    final ctrl = _controller!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ctrl.value.isInitialized
            ? Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.previewSize!.height,
                      height: ctrl.value.previewSize!.width,
                      child: CameraPreview(ctrl),
                    ),
                  ),
                  _topBar(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_pages.isNotEmpty) _filmstrip(),
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppDimens.space8,
                            bottom: AppDimens.space16,
                          ),
                          child: _shutterRow(),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: AppDimens.space4,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.space8),
        child: Row(
          children: [
            _iconBtn(Icons.close_rounded, 'Close',
                () => Navigator.of(context).pop()),
            const Spacer(),
            if (_pages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: AppDimens.space8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pages.length} page(s)',
                    style: AppTextStyle.caption
                        .copyWith(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            _iconBtn(
              _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              'Toggle torch',
              _toggleFlash,
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback? onTap) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _filmstrip() {
    return SizedBox(
      height: 82,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: AppDimens.space12),
        itemCount: _pages.length,
        itemBuilder: (context, i) {
          final page = _pages[i];
          return GestureDetector(
            onTap: () => _editPage(i),
            child: Container(
              width: 60,
              margin:
                  const EdgeInsets.symmetric(horizontal: AppDimens.space4),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            ScanProcessor.renderThumb(page),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${page.number}',
                                style: AppTextStyle.caption.copyWith(
                                    color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _shutterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(Icons.photo_library_outlined, 'Import', _importGallery),
        Semantics(
          button: true,
          label: _busy ? 'Saving' : 'Take photo',
          child: InkWell(
            onTap: _busy ? null : _capture,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: _busy ? Colors.white24 : Colors.white,
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white),
                    )
                  : null,
            ),
          ),
        ),
        _reviewBtn(),
      ],
    );
  }

  Widget _circleBtn(
      IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _reviewBtn() {
    final count = _pages.length;
    final enabled = count > 0;
    return Semantics(
      button: true,
      label: count > 0 ? 'Review $count pages' : 'No pages',
      child: InkWell(
        onTap: enabled ? _openPages : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: enabled ? 28 : 22,
              ),
              if (count > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                      child: Text(
                      '$count',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Fallback (no camera) ─────────────────────────────────────────────

  Widget _pickerFallback() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: AppDimens.space12),
                    Text(
                      'Camera not available here',
                      style:
                          AppTextStyle.rowTitle.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: AppDimens.space6),
                    Text(
                      _error ?? 'Pick images from disk instead.',
                      style: AppTextStyle.caption
                          .copyWith(color: Colors.white54),
                    ),
                    const SizedBox(height: AppDimens.space24),
                    FilledButton.tonal(
                      onPressed: _importGallery,
                      child: const Text('Choose images'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}