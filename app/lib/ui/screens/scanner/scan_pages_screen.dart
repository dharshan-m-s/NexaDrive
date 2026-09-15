import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/scan_processor.dart';
import 'scan_edit_screen.dart';

/// Document pages organizer — reorder, edit, and export as PDF.
class ScanPagesScreen extends StatefulWidget {
  final Api api;
  final String folder;
  final List<ScanPage> pages;

  const ScanPagesScreen({
    super.key,
    required this.api,
    required this.folder,
    required this.pages,
  });

  @override
  State<ScanPagesScreen> createState() => _ScanPagesScreenState();
}

class _ScanPagesScreenState extends State<ScanPagesScreen> {
  bool _saving = false;

  Future<void> _editPage(int index) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanEditScreen(
          page: widget.pages[index],
          totalPages: widget.pages.length,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  void _removePage(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      widget.pages.removeAt(index);
      _renumber();
    });
  }

  void _movePage(int from, int to) {
    HapticFeedback.lightImpact();
    setState(() {
      final moved = widget.pages.removeAt(from);
      widget.pages.insert(to, moved);
      _renumber();
    });
  }

  void _renumber() {
    for (var i = 0; i < widget.pages.length; i++) {
      widget.pages[i].number = i + 1;
    }
  }

  Future<void> _saveAsPdf() async {
    if (_saving || widget.pages.isEmpty) return;
    setState(() => _saving = true);
    try {
      final rendered = <Uint8List>[];
      for (final page in widget.pages) {
        rendered.add(ScanProcessor.renderPage(page));
      }
      final pdf = await ScanProcessor.buildPdf(rendered);

      if (!mounted) return;
      final time = DateTime.now();
      final name = 'Scan_${time.year}${_pad(time.month)}${_pad(time.day)}_'
          '${_pad(time.hour)}${_pad(time.minute)}.pdf';

      await widget.api.uploadBytes(
        pdf,
        name,
        widget.folder,
        uploadId: const Uuid().v4(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$name saved')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF101417),
        foregroundColor: Colors.white,
        title: Text(
          '${widget.pages.length} ${widget.pages.length == 1 ? 'page' : 'pages'}',
          style: AppTextStyle.pageTitle.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          tooltip: 'Back to camera',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: widget.pages.isEmpty
          ? const Center(
              child: Text('No pages yet', style: TextStyle(color: Colors.white54)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(AppDimens.space12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: AppDimens.space12,
                crossAxisSpacing: AppDimens.space12,
                childAspectRatio: 0.72,
              ),
              itemCount: widget.pages.length,
              itemBuilder: (context, i) => _PageCard(
                page: widget.pages[i],
                onTap: () => _editPage(i),
                onDelete: () => _removePage(i),
                onMoveUp: i == 0 ? null : () => _movePage(i, i - 1),
                onMoveDown: i == widget.pages.length - 1
                    ? null
                    : () => _movePage(i, i + 1),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: const Color(0xFF1A1C1E),
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space12,
            AppDimens.pageMargin,
            AppDimens.space16,
          ),
          child: FilledButton.icon(
            onPressed: (_saving || widget.pages.isEmpty) ? null : _saveAsPdf,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
            label: Text(
              _saving ? 'Creating PDF…' : 'Save as PDF',
              style: AppTextStyle.rowTitle.copyWith(color: Colors.white),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(vertical: AppDimens.space16),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  final ScanPage page;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _PageCard({
    required this.page,
    required this.onTap,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    ScanProcessor.renderThumb(page),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${page.number}',
                        style: AppTextStyle.caption.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: 'Delete page',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: onMoveUp,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: onMoveUp != null
                          ? AppColors.textSecondaryFor(brightness)
                          : Colors.white12,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: onMoveDown,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: onMoveDown != null
                          ? AppColors.textSecondaryFor(brightness)
                          : Colors.white12,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.drag_handle_rounded,
                    color: AppColors.textTertiaryFor(brightness),
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}