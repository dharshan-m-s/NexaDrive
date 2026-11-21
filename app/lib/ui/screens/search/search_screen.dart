import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';
import '../../navigation/file_opener.dart';

enum _SearchFilter { all, folders, files }

/// Focused, full-screen cloud search. Queries are debounced and request
/// generations prevent a slow earlier response from replacing a newer query.
/// Recent queries are kept locally so an empty search still has a quiet point
/// of departure.
class SearchScreen extends StatefulWidget {
  final Api api;
  final String initialQuery;
  const SearchScreen({super.key, required this.api, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'nexadrive.search.recent_queries';
  static const _recentLimit = 6;

  final SearchController _controller = SearchController();
  Timer? _debounce;
  List<FileEntry> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String _query = '';
  String? _error;
  int _requestGeneration = 0;
  _SearchFilter _filter = _SearchFilter.all;
  List<String> _recents = const [];
  int _recentsRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecents());
    if (widget.initialQuery.trim().isNotEmpty) {
      _controller.text = widget.initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onChanged(widget.initialQuery);
      });
    }
  }

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
      final entries = raw.map(FileEntry.fromJson).toList(growable: false);
      setState(() {
        _results = entries;
        _loading = false;
        _error = null;
      });
      unawaited(_rememberRecent(query));
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

  // ------------------------------------------------------------- recents

  /// Case-insensitive de-duplication, newest first, with a hard cap. Keeps the
  /// most recent spelling of a query and drops blank entries entirely.
  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (!seen.add(value.toLowerCase())) continue;
      result.add(value);
      if (result.length == _recentLimit) break;
    }
    return List<String>.unmodifiable(result);
  }

  Future<void> _loadRecents() async {
    final revision = _recentsRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_recentKey) ?? const <String>[];
      if (!mounted || revision != _recentsRevision) return;
      setState(() => _recents = _dedupe(stored));
    } catch (_) {
      // Recents are a convenience; a storage failure must not break search.
    }
  }

  Future<void> _rememberRecent(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    final updated = _dedupe(<String>[value, ..._recents]);
    _recentsRevision++;
    if (mounted) setState(() => _recents = updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, updated);
    } catch (_) {
      // Keep the in-memory list usable even if persistence is unavailable.
    }
  }

  Future<void> _clearRecents() async {
    _recentsRevision++;
    setState(() => _recents = const []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) {
      // The visible list is already cleared.
    }
  }

  void _useRecent(String query) {
    if (query.trim().isEmpty) return;
    _controller.text = query;
    _onChanged(query);
  }

  // -------------------------------------------------------------- filters

  void _selectFilter(_SearchFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
  }

  String _filterName(_SearchFilter filter) => switch (filter) {
        _SearchFilter.all => 'All',
        _SearchFilter.folders => 'Folders',
        _SearchFilter.files => 'Files',
      };

  int _filterCount(_SearchFilter filter) => switch (filter) {
        _SearchFilter.all => _results.length,
        _SearchFilter.folders => _folderCount,
        _SearchFilter.files => _fileCount,
      };

  /// Counts appear once results settle, so a loading search never shows zeros.
  String _filterLabel(_SearchFilter filter) {
    if (_loading || _results.isEmpty) return _filterName(filter);
    return '${_filterName(filter)} ${_filterCount(filter)}';
  }

  String _filterSemantics(_SearchFilter filter) {
    final count = _filterCount(filter);
    return '${_filterName(filter)} filter, $count ${count == 1 ? 'item' : 'items'}';
  }

  // ------------------------------------------------------------------ build

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
                AppDimens.pageMargin,
                AppDimens.space8,
                AppDimens.pageMargin,
                AppDimens.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(
                    builder: (context) {
                      final scheme = Theme.of(context).colorScheme;
                      return SearchBar(
                        controller: _controller,
                        hintText: 'Search your files',
                        leading: const NexaBackButton(),
                        trailing: [
                          IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clear,
                            icon: Icon(
                              Icons.close_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        onChanged: _onChanged,
                        onSubmitted: _onChanged,
                      );
                    },
                  ),
                  if (_query.isNotEmpty && _error == null) ...[
                    const SizedBox(height: AppDimens.space8),
                    _buildFilters(),
                  ],
                ],
              ),
            ),
            Expanded(
              child: NexaStateSwitcher(
                stateKey: ValueKey(_stateKey),
                child: _buildResults(row),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One of the five explicit states used by [NexaStateSwitcher].
  String get _stateKey {
    if (!_searched || _query.isEmpty) return 'idle';
    if (_error != null) return 'error';
    if (_loading) return 'loading';
    if (_results.isEmpty || _visibleResults.isEmpty) return 'empty';
    return 'content';
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: AppDimens.space8,
      runSpacing: AppDimens.space4,
      children: [
        for (final filter in _SearchFilter.values)
          Semantics(
            button: true,
            selected: _filter == filter,
            label: _filterSemantics(filter),
            onTap: () => _selectFilter(filter),
            child: ExcludeSemantics(
              child: SizedBox(
                height: AppDimens.touchTarget,
                child: NexaChip(
                  label: _filterLabel(filter),
                  selected: _filter == filter,
                  onTap: () => _selectFilter(filter),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResults(Widget Function(FileEntry) row) {
    switch (_stateKey) {
      case 'idle':
        return _buildIdle();
      case 'loading':
        return const NexaLoadingState(label: 'Searching your files…');
      case 'error':
        return _QuietState(
          icon: Icons.cloud_off_rounded,
          title: "Search didn't finish — try again",
          message: '“$_query” · $_error',
          actionLabel: 'Retry',
          onAction: _retry,
          primaryAction: true,
        );
      case 'empty':
        return _buildEmpty();
      default:
        return _buildContent(row);
    }
  }

  Widget _buildIdle() {
    if (_recents.isEmpty) {
      return const _QuietState(
        icon: Icons.search_rounded,
        title: 'Nothing here yet',
        message: 'Start typing to find files and folders. Recent searches will '
            'settle here.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space4,
        AppDimens.pageMargin,
        AppDimens.space24,
      ),
      children: [
        Row(
          children: [
            Text(
              'Recent searches',
              style: AppTextStyle.labelMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: AppDimens.touchTarget,
              child: NexaTextButton(
                onPressed: _clearRecents,
                child: const Text('Clear recent'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          runSpacing: AppDimens.space8,
          children: [
            for (final recent in _recents)
              Semantics(
                button: true,
                label: 'Recent search: $recent',
                hint: 'Runs this search again',
                onTap: () => _useRecent(recent),
                child: ExcludeSemantics(
                  child: NexaChip.outlined(
                    label: recent,
                    leadingIcon: Icons.history_rounded,
                    onTap: () => _useRecent(recent),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    if (_results.isEmpty) {
      return _QuietState(
        icon: Icons.search_off_rounded,
        title: 'No matches for “$_query”',
        message: 'Try a shorter name or a different word.',
        actionLabel: 'Clear search',
        actionIcon: Icons.close_rounded,
        onAction: _clear,
      );
    }

    final noun = _filter == _SearchFilter.folders ? 'folders' : 'files';
    return _QuietState(
      icon: Icons.filter_list_off_rounded,
      title: 'No $noun found',
      message: 'Switch the filter to see other matching items.',
      actionLabel: 'Show all results',
      onAction: () => _selectFilter(_SearchFilter.all),
    );
  }

  Widget _buildContent(Widget Function(FileEntry) row) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleResults;
    final folders = visible.where((entry) => entry.isFolder).toList();
    final files = visible.where((entry) => !entry.isFolder).toList();
    final countLabel =
        '${visible.length} matching ${visible.length == 1 ? 'item' : 'items'}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageMargin,
        AppDimens.space4,
        AppDimens.pageMargin,
        AppDimens.space24,
      ),
      children: [
        Semantics(
          label: countLabel,
          container: true,
          child: ExcludeSemantics(
            child: Text(
              countLabel,
              style: AppTextStyle.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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

/// Quiet, text-first state: a small tonal icon, human copy and one next step.
/// No layered artwork or decorative containers — search stays focused.
class _QuietState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool primaryAction;

  const _QuietState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.primaryAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAction = actionLabel != null && onAction != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageMargin,
          AppDimens.space24,
          AppDimens.pageMargin,
          AppDimens.space32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: AppDimens.iconMedium,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDimens.space12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.title3.copyWith(color: scheme.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: AppDimens.space8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyle.bodyMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasAction) ...[
              const SizedBox(height: AppDimens.space20),
              SizedBox(
                height: AppDimens.touchTarget,
                child: primaryAction
                    ? NexaFilledButton(
                        onPressed: onAction,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: AppDimens.iconSmall,
                        ),
                        child: Text(actionLabel!),
                      )
                    : NexaTextButton(
                        onPressed: onAction,
                        icon: actionIcon == null
                            ? null
                            : Icon(actionIcon!, size: AppDimens.iconSmall),
                        child: Text(actionLabel!),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final String title;
  const _SearchHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space4,
        AppDimens.space8,
        AppDimens.space4,
        AppDimens.space4,
      ),
      child: Text(
        title,
        style: AppTextStyle.labelMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
