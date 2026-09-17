import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';

/// One created share link.
class _ShareLink {
  const _ShareLink({
    required this.fileName,
    required this.url,
    required this.id,
    this.isLink = true,
  });

  final String fileName;
  final String url;
  final String id;

  /// False for a direct share with another account (no URL to copy).
  final bool isLink;
}

/// One UI "Share" sheet.
///
/// ## Honesty contract
///
/// Selecting four files creates four real share links — one per file. The
/// sheet never claims to share more than it actually shared, and it reports
/// per-file failures instead of hiding them.
class FileShareSheet extends StatefulWidget {
  final Api api;
  final List<FileEntry> files;
  const FileShareSheet({super.key, required this.api, required this.files});

  @override
  State<FileShareSheet> createState() => _FileShareSheetState();
}

class _FileShareSheetState extends State<FileShareSheet> {
  String _permission = 'view';
  bool _busy = false;
  int _createdCount = 0;
  final List<_ShareLink> _links = <_ShareLink>[];
  final Map<String, String> _failures = <String, String>{};
  String? _error;

  /// `link` shares with anyone holding the URL; `person` shares with another
  /// NexaDrive account. Folders can only use `person`, because a public link
  /// resolves to a single file download.
  late String _mode = _hasFolder ? 'person' : 'link';
  final TextEditingController _recipient = TextEditingController();

  bool get _hasFolder => widget.files.any((f) => f.isFolder);

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  String get _baseUrl =>
      (widget.api.session.serverUrl ?? '').replaceAll(RegExp(r'/+$'), '');

  Future<void> _create() async {
    final recipient = _recipient.text.trim();
    if (_mode == 'link' && _baseUrl.isEmpty) {
      setState(() => _error = 'No server address is configured for this session.');
      return;
    }
    if (_mode == 'person' && recipient.isEmpty) {
      setState(() => _error = 'Enter the NexaDrive username to share with.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _createdCount = 0;
      _links.clear();
      _failures.clear();
    });

    final permission = _permission == 'view' ? 'read' : 'write';
    for (final file in widget.files) {
      try {
        final result = await widget.api.createShare(
          path: file.path,
          permission: permission,
          username: _mode == 'person' ? recipient : null,
        );
        final token = result['token']?.toString() ?? '';
        final id = result['id']?.toString() ?? '';
        if (_mode == 'person') {
          _links.add(
            _ShareLink(
              fileName: file.name,
              url: 'Shared with $recipient',
              id: id,
              isLink: false,
            ),
          );
        } else if (token.isEmpty) {
          _failures[file.name] = 'The server did not return a link token.';
        } else {
          _links.add(
            _ShareLink(
              fileName: file.name,
              url: '$_baseUrl/api/share/$token/download',
              id: id,
            ),
          );
        }
      } catch (e) {
        _failures[file.name] = e.toString();
      }
      if (!mounted) return;
      setState(() => _createdCount++);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (_links.isNotEmpty) _announceCreated();
  }

  void _announceCreated() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _links.length == 1
                ? 'Share link ready'
                : '${_links.length} share links ready',
          ),
        ),
      );
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  /// Revokes every link created by this sheet. A revoked link stops working
  /// immediately because the server deletes the row outright.
  Future<void> _removeAll() async {
    setState(() => _busy = true);
    final failed = <String>[];
    for (final link in List<_ShareLink>.of(_links)) {
      if (link.id.isEmpty) {
        failed.add(link.fileName);
        continue;
      }
      try {
        await widget.api.deleteShare(link.id);
        if (mounted) setState(() => _links.removeWhere((l) => l.id == link.id));
      } catch (e) {
        failed.add(link.fileName);
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failed.isNotEmpty) {
        _error = 'Some links could not be revoked: ${failed.join(', ')}';
      }
    });
    if (_links.isEmpty && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentFor(brightness);
    final secondary = AppColors.textSecondaryFor(brightness);
    final single = widget.files.length == 1;
    final anyLink = _links.any((l) => l.isLink);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageMargin,
          AppDimens.space16,
          AppDimens.pageMargin,
          AppDimens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_outlined, color: accent),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        single
                            ? 'Share "${widget.files.first.name}"'
                            : 'Share ${widget.files.length} items',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!single)
                        Text(
                          _mode == 'person'
                              ? 'Each file is shared with the same person'
                              : 'Each file gets its own link',
                          style: AppTextStyle.caption.copyWith(color: secondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),

            if (_links.isNotEmpty)
              _CreatedLinks(
                links: _links,
                onCopy: (link) => _copy(link.url, link.fileName),
                onCopyAll: () => _copy(
                  _links.where((l) => l.isLink).map((l) => l.url).join('\n'),
                  '${_links.where((l) => l.isLink).length} links',
                ),
              )
            else ...[
              if (!_hasFolder) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'link',
                      label: Text('Anyone with link'),
                      icon: Icon(Icons.link_rounded),
                    ),
                    ButtonSegment(
                      value: 'person',
                      label: Text('A person'),
                      icon: Icon(Icons.person_outline_rounded),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: AppDimens.space12),
              ],
              Text(
                _mode == 'link'
                    ? 'Anyone with the link can '
                        '${_permission == 'view' ? 'view' : 'download'} '
                        '${single ? 'this file' : 'these files'} until you revoke it.'
                    : 'Folders and files shared this way stay private to that '
                        'NexaDrive account.',
                style: AppTextStyle.caption.copyWith(color: secondary),
              ),
              const SizedBox(height: AppDimens.space12),
              if (_mode == 'person') ...[
                TextField(
                  controller: _recipient,
                  enabled: !_busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'NexaDrive username',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: AppDimens.space12),
              ],
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'view',
                    label: Text('View only'),
                    icon: Icon(Icons.visibility_outlined),
                  ),
                  ButtonSegment(
                    value: 'download',
                    label: Text('Download'),
                    icon: Icon(Icons.download_outlined),
                  ),
                ],
                selected: {_permission},
                onSelectionChanged:
                    _busy ? null : (s) => setState(() => _permission = s.first),
              ),
            ],

            if (_busy && _createdCount > 0) ...[
              const SizedBox(height: AppDimens.space16),
              LinearProgressIndicator(
                value: widget.files.isEmpty
                    ? null
                    : _createdCount / widget.files.length,
              ),
              const SizedBox(height: AppDimens.space8),
              Text(
                'Creating links… ($_createdCount of ${widget.files.length})',
                style: AppTextStyle.caption.copyWith(color: secondary),
              ),
            ],

            if (_failures.isNotEmpty && !_busy) ...[
              const SizedBox(height: AppDimens.space12),
              for (final entry in _failures.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.space4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: AppDimens.iconSmall,
                        color: AppColors.errorFor(brightness),
                      ),
                      const SizedBox(width: AppDimens.space8),
                      Expanded(
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: AppTextStyle.caption.copyWith(
                            color: AppColors.errorFor(brightness),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            if (_error != null) ...[
              const SizedBox(height: AppDimens.space12),
              Text(
                _error!,
                style: AppTextStyle.caption
                    .copyWith(color: AppColors.errorFor(brightness)),
              ),
            ],

            const SizedBox(height: AppDimens.space20),
            Row(
              children: [
                if (_links.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _removeAll,
                      icon: const Icon(Icons.link_off_rounded,
                          size: AppDimens.iconSmall),
                      label: Text(
                        anyLink
                            ? (_links.length == 1 ? 'Revoke link' : 'Revoke all')
                            : 'Remove access',
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _mode == 'person'
                                  ? Icons.person_add_alt_rounded
                                  : Icons.add_link_rounded,
                              size: AppDimens.iconSmall,
                            ),
                      label: Text(
                        _mode == 'person'
                            ? (single ? 'Share with person' : 'Share ${widget.files.length} files')
                            : (single
                                ? 'Create link'
                                : 'Create ${widget.files.length} links'),
                      ),
                    ),
                  ),
                const SizedBox(width: AppDimens.space12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reveals created links with a short, restrained entrance and offers copy.
class _CreatedLinks extends StatelessWidget {
  final List<_ShareLink> links;
  final ValueChanged<_ShareLink> onCopy;
  final VoidCallback onCopyAll;

  const _CreatedLinks({
    required this.links,
    required this.onCopy,
    required this.onCopyAll,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final secondary = AppColors.textSecondaryFor(brightness);
    final success = AppColors.successFor(brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: success, size: AppDimens.iconSmall),
            const SizedBox(width: AppDimens.space8),
            Expanded(
              child: Text(
                links.every((l) => !l.isLink)
                    ? 'Shared and ready'
                    : links.length == 1
                        ? 'Link ready to share'
                        : '${links.length} links ready to share',
                style: AppTextStyle.rowSubtitle.copyWith(
                  color: AppColors.textPrimaryFor(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (links.where((l) => l.isLink).length > 1)
              TextButton.icon(
                onPressed: onCopyAll,
                icon: const Icon(Icons.copy_all_rounded, size: AppDimens.iconSmall),
                label: const Text('Copy all'),
              ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.enter,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.34,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: links.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppDimens.space8),
              itemBuilder: (context, i) {
                final link = links[i];
                return Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.space12,
                    AppDimens.space8,
                    AppDimens.space4,
                    AppDimens.space8,
                  ),
                  decoration: BoxDecoration(
                    color: brightness == Brightness.dark
                        ? AppColors.surfaceAltDark
                        : AppColors.surfaceAltLight,
                    borderRadius: BorderRadius.circular(AppDimens.radiusInner),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              link.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.rowSubtitle.copyWith(
                                color: AppColors.textPrimaryFor(brightness),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              link.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.micro.copyWith(color: secondary),
                            ),
                          ],
                        ),
                      ),
                      if (link.isLink)
                        IconButton(
                          tooltip: 'Copy link for ${link.fileName}',
                          onPressed: () => onCopy(link),
                          icon: const Icon(Icons.copy_rounded,
                              size: AppDimens.iconSmall),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppDimens.space8),
                          child: Icon(Icons.lock_outline_rounded,
                              size: AppDimens.iconSmall),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
