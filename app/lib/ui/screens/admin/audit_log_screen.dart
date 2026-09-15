import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/one_ui_empty_state.dart';

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

  String _initial(String? username) {
    final name = username ?? '?';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _entries.isEmpty
              ? const OneUiEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No audit entries',
                  hint: 'Security events will be listed here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageMargin, AppDimens.space8, AppDimens.pageMargin, AppDimens.space24,
                  ),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.dividerFor(brightness)),
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
                    final action = entry['action']?.toString() ?? '';
                    return ListTile(
                      minVerticalPadding: AppDimens.space12,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.accentFor(brightness).withValues(alpha: 0.14),
                        child: Text(
                          _initial(entry['username']?.toString()),
                          style: AppTextStyle.micro.copyWith(
                            color: AppColors.accentFor(brightness),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        '$action ${entry['path']?.toString() ?? ''}'.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.rowTitle.copyWith(
                          color: AppColors.textPrimaryFor(brightness),
                        ),
                      ),
                      subtitle: Text(
                        '${entry['username'] ?? 'unknown'} · '
                        '${Format.shortDateTime(DateTime.tryParse(entry['created_at']?.toString() ?? ''))}',
                        style: AppTextStyle.caption.copyWith(
                          color: AppColors.textSecondaryFor(brightness),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}