import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/scan_processor.dart';
import 'crop_overlay.dart';

/// Per-page scan editor — rotate, filter, crop.
///
/// Edits are written back to the [ScanPage] object in-place.
class ScanEditScreen extends StatefulWidget {
  final ScanPage page;
  final int totalPages;

  const ScanEditScreen({super.key, required this.page, required this.totalPages});

  @override
  State<ScanEditScreen> createState() => _ScanEditScreenState();
}

class _ScanEditScreenState extends State<ScanEditScreen> {
  late int _turns;
  late ScanFilter _filter;
  Rect? _crop;
  double _aspect = 1;

  @override
  void initState() {
    super.initState();
    _turns = widget.page.rightTurns;
    _filter = widget.page.filter;
    _crop = widget.page.crop;
    _recomputeAspect();
  }

  void _recomputeAspect() {
    final src = ScanProcessor.decodeForAspect(widget.page.original);
    if (src == null) return;
    setState(() {
      _aspect = _turns.isOdd ? src.height / src.width : src.width / src.height;
    });
  }

  void _apply() {
    widget.page.rightTurns = _turns;
    widget.page.filter = _filter;
    widget.page.crop = _crop;
  }

  void _rotateRight() {
    setState(() {
      _turns = (_turns + 1) % 4;
      _aspect = 1 / _aspect;
    });
  }

  void _rotateLeft() {
    setState(() {
      _turns = (_turns + 3) % 4;
      _aspect = 1 / _aspect;
    });
  }

  void _autoCrop() {
    final page = widget.page;
    final origTurns = page.rightTurns;
    final origFilter = page.filter;
    final origCrop = page.crop;

    page.rightTurns = _turns;
    page.filter = _filter;
    page.crop = _crop;
    final detected = ScanProcessor.autoDetectCrop(page);

    page.rightTurns = origTurns;
    page.filter = origFilter;
    page.crop = origCrop;

    if (detected == null) {
      _toast('No border to crop');
      return;
    }
    setState(() => _crop = detected);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _preview()),
            _filterBar(brightness),
            _actionBar(brightness),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space8,
        vertical: AppDimens.space6,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          const SizedBox(width: AppDimens.space4),
          Text(
            'Page ${widget.page.number} of ${widget.totalPages}',
            style: AppTextStyle.rowTitle.copyWith(color: Colors.white),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _preview() {
    final bytes = ScanProcessor.renderPage(
      widget.page,
      applyCrop: false,
      maxEdge: 1200,
    );
    return Padding(
      padding: const EdgeInsets.all(AppDimens.space12),
      child: AspectRatio(
        aspectRatio: _aspect,
        child: _crop != null
            ? CropOverlay(
                value: _crop!,
                aspect: _aspect,
                onChanged: (r) => setState(() => _crop = r),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
              ),
      ),
    );
  }

  Widget _filterBar(Brightness brightness) {
    return Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _chip('Original', ScanFilter.color, brightness),
          _chip('Grayscale', ScanFilter.grayscale, brightness),
          _chip('B&W', ScanFilter.blackAndWhite, brightness),
        ],
      ),
    );
  }

  Widget _chip(String label, ScanFilter mode, Brightness brightness) {
    final selected = _filter == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: AppTextStyle.caption.copyWith(
        color: selected ? AppColors.accentDark : Colors.white70,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      selectedColor: AppColors.accentContainerDark,
      backgroundColor: Colors.white10,
      side: BorderSide.none,
      onSelected: (_) => setState(() => _filter = mode),
    );
  }

  Widget _actionBar(Brightness brightness) {
    return Container(
      color: AppColors.surfaceDark,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space12,
        0,
        AppDimens.space12,
        AppDimens.space16,
      ),
      child: Row(
        children: [
          _actionBtn(Icons.rotate_left_rounded, 'Rotate left', _rotateLeft),
          _actionBtn(Icons.rotate_right_rounded, 'Rotate right', _rotateRight),
          _actionBtn(Icons.center_focus_strong_rounded, 'Auto-crop', _autoCrop),
          if (_crop != null)
            _actionBtn(Icons.restart_alt_rounded, 'Reset crop', () => setState(() => _crop = null)),
          const Spacer(),
          FilledButton(
            onPressed: () {
              _apply();
              Navigator.of(context).pop(true);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: AppDimens.space8),
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white12,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}