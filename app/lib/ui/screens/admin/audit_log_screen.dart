import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_controls.dart';
import '../../widgets/one_ui_empty_state.dart';
import '../../widgets/one_ui_grouped_list.dart';
import '../../widgets/one_ui_page.dart';

class AuditLogScreen extends StatefulWidget {
  final Api api;
  const AuditLogScreen({super.key, required this.api});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _loading = true);
    try {
      final entries = await widget.api.audit();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: OneUiPage(
          title: 'Audit log',
          subtitle: _entries.isEmpty
              ? null
              : '${_entries.length} event${_entries.length == 1 ? '' : 's'}',
          leading: const OneUiBackButton(),
          headerAction: IconButton(
            tooltip: 'Refresh',
            onPressed: load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          scrollable: true,
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageMargin,
            AppDimens.space8,
            AppDimens.pageMargin,
            AppDimens.space24,
          ),
          body: _loading
              ? const OneUiLoadingBlock()
              : _entries.isEmpty
                  ? const OneUiEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No audit entries',
                      hint: 'Security events will be listed here.',
                    )
                  : OneUiGroupedList(
                      withDividers: true,
                      children: [
                        for (final entry in _entries)
                          _AuditRow(
                            action: entry['action']?.toString() ?? '',
                            path: entry['path']?.toString() ?? '',
                            username: entry['username']?.toString(),
                            createdAt: entry['created_at']?.toString(),
                            brightness: brightness,
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

/// A single audit entry rendered as a standard One UI grouped row.
class _AuditRow extends StatelessWidget {
  final String action;
  final String path;
  final String? username;
  final String? createdAt;
  final Brightness brightness;

  const _AuditRow({
    required this.action,
    required this.path,
    required this.username,
    required this.createdAt,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final label = '$action $path'.trim();
    final who = (username == null || username!.isEmpty) ? 'unknown' : username!;

    return OneUiGroupTile(
      showChevron: false,
      onTap: null,
      leading: CircleAvatar(
        radius: AppDimens.space16,
        backgroundColor:
            AppColors.accentFor(brightness).withValues(alpha: 0.14),
        child: Text(
          _initialOf(who),
          style: AppTextStyle.micro.copyWith(
            color: AppColors.accentFor(brightness),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: label,
      subtitle:
          '$who · ${Format.shortDateTime(DateTime.tryParse(createdAt ?? ''))}',
    );
  }

  static String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
