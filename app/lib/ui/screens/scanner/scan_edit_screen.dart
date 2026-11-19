import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/scan_processor.dart';
import '../../widgets/nexa_components.dart';
import 'crop_overlay.dart';

/// Per-page scan editor — rotate, filter, crop.
///
/// Edits are written back to the [ScanPage] object in-place.
class ScanEditScreen extends StatefulWidget {
  final ScanPage page;
  final int totalPages;

  const ScanEditScreen(
      {super.key, required this.page, required this.totalPages});

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

  void setFilter(ScanFilter mode) => setState(() => _filter = mode);
  void rotateLeft() => _rotateLeft();
  void rotateRight() => _rotateRight();
  void autoCrop() => _autoCrop();
  void resetCrop() => setState(() => _crop = null);
  void apply() => _apply();

  ScanFilter get filter => _filter;
  Rect? get crop => _crop;

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
    // Immersive scan editor over the page image: one complete dark scheme.
    final darkTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: AppColors.scheme(Brightness.dark),
    );
    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(child: _preview()),
              const _FilterBar(),
              const _ActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space8,
        AppDimens.space6,
        AppDimens.pageMargin,
        AppDimens.space6,
      ),
      child: NexaSurface(
        level: NexaSurfaceLevel.floating,
        radius: AppDimens.radiusPill,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space4,
          vertical: AppDimens.space2,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: AppDimens.space4),
            Text(
              'Page ${widget.page.number} of ${widget.totalPages}',
              style: AppTextStyle.titleSmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
          ],
        ),
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
                borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
                child: Image.memory(bytes,
                    fit: BoxFit.contain, gaplessPlayback: true),
              ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.space16),
      child: NexaSurface(
        level: NexaSurfaceLevel.floating,
        radius: AppDimens.radiusXLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space8,
          vertical: AppDimens.space6,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _chip(context, 'Original', ScanFilter.color),
            _chip(context, 'Grayscale', ScanFilter.grayscale),
            _chip(context, 'B&W', ScanFilter.blackAndWhite),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, ScanFilter mode) {
    final state = context.findAncestorStateOfType<_ScanEditScreenState>()!;
    final scheme = Theme.of(context).colorScheme;
    final selected = state.filter == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: AppTextStyle.labelSmall.copyWith(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainerHigh,
      showCheckmark: false,
      side: BorderSide.none,
      onSelected: (_) => state.setFilter(mode),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_ScanEditScreenState>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space12,
        AppDimens.space8,
        AppDimens.space12,
        AppDimens.space12,
      ),
      child: NexaSurface(
        level: NexaSurfaceLevel.floating,
        radius: AppDimens.radiusXLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space8,
          vertical: AppDimens.space6,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _actionBtn(context, Icons.rotate_left_rounded, 'Rotate left',
                  state.rotateLeft),
              _actionBtn(context, Icons.rotate_right_rounded, 'Rotate right',
                  state.rotateRight),
              _actionBtn(context, Icons.center_focus_strong_rounded,
                  'Auto-crop', state.autoCrop),
              if (state.crop != null)
                _actionBtn(context, Icons.restart_alt_rounded, 'Reset crop',
                    state.resetCrop),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  state.apply();
                  Navigator.of(context).pop(true);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppDimens.space8),
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
