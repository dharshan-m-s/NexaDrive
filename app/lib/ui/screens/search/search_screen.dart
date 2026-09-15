import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/file_kind.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_file_tile.dart';
import '../../widgets/one_ui_search_field.dart';
import '../media/audio_player_screen.dart';
import '../media/video_player_screen.dart';
import '../photos/photo_viewer.dart';
import '../viewers/pdf_viewer_screen.dart';
import '../viewers/text_viewer_screen.dart';

/// Focused One UI search mode.
///
/// The field takes the whole top of the viewing area; results stream in as the
/// query is typed. Tapping a result opens it in-place; folders show their
/// path so you always know where a result lives.
class SearchScreen extends StatefulWidget {
  final Api api;
  const SearchScreen({super.key, required this.api});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<FileEntry> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      _searched = q.isNotEmpty;
    });
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final raw = await widget.api.searchFiles(q);
      if (!mounted) return;
      setState(() {
        _results = raw.map(FileEntry.fromJson).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _open(FileEntry entry) {
    switch (entry.category) {
      case Category.image:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhotoViewer(
              photos: [entry.toJson()],
              initialIndex: 0,
              api: widget.api,
            ),
          ),
        );
      case Category.video:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.audio:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AudioPlayerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.pdf:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(file: entry, api: widget.api),
          ),
        );
      case Category.text:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextViewerScreen(file: entry, api: widget.api),
          ),
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget row(FileEntry e) => OneUiFileTile(
          entry: e,
          onTap: (v) => _open(v),
          showChevron: true,
          subtitle:
              '${e.isFolder ? 'Folder' : Format.bytes(e.size)} · ${e.path == e.name ? '/' : e.path}',
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space4, AppDimens.space8, AppDimens.space12, AppDimens.space8,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: AppDimens.space4),
                  Expanded(
                    child: OneUiSearchField(
                      controller: _controller,
                      hint: 'Search your files',
                      labelText: 'Search',
                      onChanged: _onChanged,
                      onSubmitted: _onChanged,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildResults(row)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(Widget Function(FileEntry) row) {
    final brightness = Theme.of(context).brightness;

    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 48,
              color: AppColors.textTertiaryFor(brightness),
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              'Search everything in your cloud',
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
          ],
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textTertiaryFor(brightness),
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              'No matches for “$_query”',
              style: AppTextStyle.rowSubtitle.copyWith(
                color: AppColors.textSecondaryFor(brightness),
              ),
            ),
          ],
        ),
      );
    }

    final folders = _results.where((e) => e.isFolder).toList();
    final files = _results.where((e) => !e.isFolder).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin, AppDimens.space4, AppDimens.pageMargin, AppDimens.space24,
      ),
      children: [
        if (folders.isNotEmpty) ...[
          const _SearchHeader('Folders'),
          for (final e in folders) row(e),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space8),
          const _SearchHeader('Files'),
          for (final e in files) row(e),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: AppDimens.space16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final String title;
  const _SearchHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4, AppDimens.space8, AppDimens.space4, AppDimens.space4,
      ),
      child: Text(
        title,
        style: AppTextStyle.sectionHeader.copyWith(
          color: AppColors.textSecondaryFor(brightness),
          fontSize: AppTextStyle.sectionHeader.fontSize! * 0.82,
        ),
      ),
    );
  }
}