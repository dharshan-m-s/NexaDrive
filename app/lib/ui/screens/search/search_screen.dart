import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';
import '../../navigation/file_opener.dart';

enum _SearchFilter { all, folders, files }

/// Focused cloud search. Queries are debounced and request generations prevent
/// a slow earlier response from replacing the result of a newer query.
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
  String? _error;
  int _requestGeneration = 0;
  _SearchFilter _filter = _SearchFilter.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _requestGeneration++;
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    final generation = ++_requestGeneration;
    setState(() {
      _query = q;
      _searched = q.isNotEmpty;
      _results = const [];
      _loading = q.isNotEmpty;
      _error = null;
      _filter = _SearchFilter.all;
    });
    if (q.isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _run(q, generation),
    );
  }

  Future<void> _run(String query, int generation) async {
    try {
      final raw = await widget.api.searchFiles(query);
      if (!mounted || generation != _requestGeneration || query != _query) {
        return;
      }
      setState(() {
        _results = raw.map(FileEntry.fromJson).toList(growable: false);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration || query != _query) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Check your connection and try searching again.';
      });
    }
  }

  void _retry() {
    if (_query.isEmpty) return;
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    _run(_query, generation);
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  List<FileEntry> get _visibleResults => switch (_filter) {
        _SearchFilter.all => _results,
        _SearchFilter.folders =>
          _results.where((entry) => entry.isFolder).toList(growable: false),
        _SearchFilter.files =>
          _results.where((entry) => !entry.isFolder).toList(growable: false),
      };

  int get _folderCount => _results.where((entry) => entry.isFolder).length;
  int get _fileCount => _results.where((entry) => !entry.isFolder).length;

  void _open(FileEntry entry) {
    FileOpener.open(
      context,
      api: widget.api,
      entry: entry,
      siblings: _results,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget row(FileEntry entry) => NexaFileTile(
          entry: entry,
          onTap: _open,
          showChevron: true,
          subtitle: '${entry.isFolder ? 'Folder' : Format.bytes(entry.size)} · '
              '${entry.path == entry.name ? '/' : entry.path}',
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.space4,
                AppDimens.space8,
                AppDimens.pageMargin,
                AppDimens.space8,
              ),
              child: NexaLiquidGlass(
                padding: const EdgeInsets.all(AppDimens.space6),
                borderRadius: BorderRadius.circular(AppDimens.radiusXLarge),
                child: Row(
                  children: [
                    const NexaBackButton(),
                    Expanded(
                      child: NexaSearchField(
                        controller: _controller,
                        hint: 'Search your files',
                        filled: false,
                        onChanged: _onChanged,
                        onClear: _clear,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: NexaStateSwitcher(
                stateKey: ValueKey(_resultState),
                child: _buildResults(row),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _resultState {
    if (!_searched) return 'idle';
    if (_error != null) return 'error';
    if (_loading) return 'loading';
    if (_visibleResults.isEmpty) return 'empty:${_filter.name}';
    return 'content:${_filter.name}:${_visibleResults.length}';
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
            const SizedBox(height: AppDimens.space6),
            Text(
              'Find files and folders by name',
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.textTertiaryFor(brightness),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.pageMargin),
          child: NexaEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Search unavailable',
            hint: _error!,
            actionLabel: 'Try again',
            onAction: _retry,
          ),
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
            const SizedBox(height: AppDimens.space6),
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Clear search'),
            ),
          ],
        ),
      );
    }

    final visible = _visibleResults;
    if (visible.isEmpty) {
      final noun = _filter == _SearchFilter.folders ? 'folders' : 'files';
      return Center(
        child: NexaEmptyState(
          icon: Icons.filter_list_off_rounded,
          title: 'No $noun found',
          hint: 'Switch the filter to see other matching items.',
          actionLabel: 'Show all results',
          onAction: () => setState(() => _filter = _SearchFilter.all),
        ),
      );
    }

    final folders = visible.where((entry) => entry.isFolder).toList();
    final files = visible.where((entry) => !entry.isFolder).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space4,
        AppDimens.pageMargin,
        AppDimens.space24,
      ),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              NexaChip.tonal(
                label: 'All ${_results.length}',
                selected: _filter == _SearchFilter.all,
                onTap: () => setState(() => _filter = _SearchFilter.all),
              ),
              const SizedBox(width: AppDimens.space8),
              NexaChip.tonal(
                label: 'Folders $_folderCount',
                leadingIcon: Icons.folder_outlined,
                selected: _filter == _SearchFilter.folders,
                onTap: () => setState(() => _filter = _SearchFilter.folders),
              ),
              const SizedBox(width: AppDimens.space8),
              NexaChip.tonal(
                label: 'Files $_fileCount',
                leadingIcon: Icons.insert_drive_file_outlined,
                selected: _filter == _SearchFilter.files,
                onTap: () => setState(() => _filter = _SearchFilter.files),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.space4,
            AppDimens.space12,
            AppDimens.space4,
            AppDimens.space4,
          ),
          child: Text(
            '${visible.length} matching ${visible.length == 1 ? 'item' : 'items'}',
            style: AppTextStyle.caption1.copyWith(
              color: AppColors.textSecondaryFor(brightness),
            ),
          ),
        ),
        if (folders.isNotEmpty) ...[
          const _SearchHeader('Folders'),
          for (final entry in folders) row(entry),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: AppDimens.space8),
          const _SearchHeader('Files'),
          for (final entry in files) row(entry),
        ],
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
        AppDimens.space4,
        AppDimens.space8,
        AppDimens.space4,
        AppDimens.space4,
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
