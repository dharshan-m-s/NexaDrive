import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/format.dart';
import '../../../services/api.dart';
import '../../widgets/nexa_components.dart';

/// A dedicated statistics view for the Home storage overview card.
///
/// Every visual is drawn from the authenticated server's filesystem walk:
/// file-type totals, size ranges, largest files and seven-day modification
/// counts. This screen deliberately does not invent upload history or trends.
class StorageInsightsScreen extends StatefulWidget {
  final Api api;

  const StorageInsightsScreen({super.key, required this.api});

  @override
  State<StorageInsightsScreen> createState() => _StorageInsightsScreenState();
}

class _StorageInsightsScreenState extends State<StorageInsightsScreen> {
  StorageInfo? _storage;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await widget.api.storageInsights();
      if (!mounted) return;
      setState(() {
        _storage = StorageInfo.fromJson(json);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Storage statistics could not be loaded.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NexaPage(
      title: 'Storage insights',
      subtitle: 'A live statistical view of your private cloud',
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      headerAction: IconButton(
        tooltip: 'Refresh storage statistics',
        onPressed: _loading ? null : load,
        icon: Icon(
          Icons.refresh_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      scrollable: true,
      body: _loading
          ? const Padding(
              padding: EdgeInsets.only(top: AppDimens.space48),
              child: NexaLoadingBlock(),
            )
          : _error != null
              ? NexaEmptyState(
                  icon: Icons.analytics_outlined,
                  title: 'Insights unavailable',
                  hint: _error!,
                  actionLabel: 'Try again',
                  onAction: load,
                )
              : _content(_storage!),
    );
  }

  Widget _content(StorageInfo storage) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuota = storage.quotaBytes != null;
    final average =
        storage.fileCount == 0 ? 0 : storage.usedBytes ~/ storage.fileCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CapacityPanel(storage: storage),
        const SizedBox(height: AppDimens.space16),
        Row(
          children: [
            Expanded(
              child: _MetricPanel(
                icon: Icons.folder_copy_outlined,
                label: 'Files',
                value: Format.count(storage.fileCount, 'file'),
                tint: scheme.primary,
              ),
            ),
            const SizedBox(width: AppDimens.space10),
            Expanded(
              child: _MetricPanel(
                icon: Icons.data_usage_rounded,
                label: 'Average file',
                value: Format.bytes(average),
                tint: scheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space24),
        _SectionHeading(
          title: 'Storage composition',
          subtitle: 'Where your used space is going',
          trailing: Format.bytes(storage.usedBytes),
        ),
        const SizedBox(height: AppDimens.space10),
        _CompositionPanel(storage: storage),
        const SizedBox(height: AppDimens.space24),
        _SectionHeading(
          title: 'File activity',
          subtitle: 'Files modified during the last seven days',
          trailing: Format.count(
            storage.activityLast7Days.fold<int>(
              0,
              (sum, day) => sum + day.count,
            ),
            'change',
          ),
        ),
        const SizedBox(height: AppDimens.space10),
        _ActivityPanel(days: storage.activityLast7Days),
        const SizedBox(height: AppDimens.space24),
        _SectionHeading(
          title: 'File size distribution',
          subtitle: 'How many files fall into each size range',
        ),
        const SizedBox(height: AppDimens.space10),
        _SizeDistributionPanel(
          bands: storage.sizeDistribution,
          totalFiles: storage.fileCount,
        ),
        const SizedBox(height: AppDimens.space24),
        _SectionHeading(
          title: 'Largest files',
          subtitle: 'The five biggest files in your storage',
        ),
        const SizedBox(height: AppDimens.space10),
        _LargestFilesPanel(files: storage.largestFiles),
        const SizedBox(height: AppDimens.space16),
        Text(
          hasQuota
              ? 'Statistics are calculated from files currently stored on the server. '
                  'Activity uses file modification dates; it is not an upload-history chart.'
              : 'This account has unlimited storage. Statistics are calculated from '
                  'files currently stored on the server. Activity uses file modification dates.',
          style: AppTextStyle.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppDimens.space24),
      ],
    );
  }
}

class _CapacityPanel extends StatelessWidget {
  final StorageInfo storage;

  const _CapacityPanel({required this.storage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuota = storage.quotaBytes != null;
    final percent = (storage.usageFraction * 100).round();

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your storage',
                      style: AppTextStyle.labelMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppDimens.space6),
                    Text(
                      Format.bytes(storage.usedBytes),
                      style: AppTextStyle.metricValue.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      hasQuota
                          ? 'of ${Format.bytes(storage.quotaBytes!)}'
                          : 'Unlimited capacity',
                      style: AppTextStyle.bodyMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(112),
                      painter: _CapacityRingPainter(
                        fraction: hasQuota ? storage.usageFraction : 0,
                        track: scheme.surfaceContainerHighest,
                        // Chart series are encoded in M3 roles, not raw hex.
                        progress: scheme.primary,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasQuota ? '$percent%' : '∞',
                          style: AppTextStyle.titleLarge.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          hasQuota ? 'used' : 'no limit',
                          style: AppTextStyle.labelSmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space20),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: LinearProgressIndicator(
              value: hasQuota ? storage.usageFraction : 0.0,
              minHeight: AppDimens.space8,
              color: scheme.primary,
              backgroundColor: scheme.primaryContainer,
              semanticsLabel: 'Storage capacity used',
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          Row(
            children: [
              Expanded(
                child: _CapacityValue(
                  label: 'Used',
                  value: Format.bytes(storage.usedBytes),
                  color: scheme.primary,
                ),
              ),
              Expanded(
                child: _CapacityValue(
                  label: 'Available',
                  value:
                      hasQuota ? Format.bytes(storage.freeBytes) : 'No limit',
                  color: scheme.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapacityRingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color progress;

  const _CapacityRingPainter({
    required this.fraction,
    required this.track,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 8;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    const stroke = 10.0;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(bounds, -math.pi / 2, math.pi * 2, false, trackPaint);

    final sweep = fraction.clamp(0.0, 1.0).toDouble() * math.pi * 2;
    if (sweep <= 0) return;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progress;
    canvas.drawArc(bounds, -math.pi / 2, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _CapacityRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.progress != progress;
}

class _CapacityValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CapacityValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: AppDimens.space8,
          height: AppDimens.space8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppDimens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyle.labelMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.titleMedium.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricPanel extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  const _MetricPanel({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppDimens.iconTile,
            height: AppDimens.iconTile,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
            ),
            child: Icon(icon, color: tint, size: AppDimens.iconMedium),
          ),
          const SizedBox(height: AppDimens.space12),
          Text(
            label,
            style: AppTextStyle.labelMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.titleLarge.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? trailing;

  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyle.titleMedium.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                subtitle,
                style: AppTextStyle.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppDimens.space8),
          Text(
            trailing!,
            style: AppTextStyle.labelMedium.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompositionPanel extends StatelessWidget {
  final StorageInfo storage;

  const _CompositionPanel({required this.storage});

  static const _glyphNames = <String, String>{
    'images': 'photo.jpg',
    'videos': 'clip.mp4',
    'audio': 'track.mp3',
    'documents': 'notes.docx',
    'archives': 'bundle.zip',
    'other': 'file',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = scheme.brightness;
    final colors = AppColors.analyticsPaletteFor(brightness);
    final entries = storage.typeBreakdown;
    final visible = entries.where((entry) => entry.bytes > 0).toList();
    final total = visible.fold<int>(0, (sum, entry) => sum + entry.bytes);

    if (storage.fileCount == 0) {
      return const _EmptyStatsPanel(
        message: 'No files stored yet. File composition will appear here as '
            'your cloud library grows.',
      );
    }
    if (entries.isEmpty) {
      return const _EmptyStatsPanel(
        message: 'File-type statistics are not available from this server.',
      );
    }

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 480;
              final diameter = compact ? 112.0 : 148.0;
              final donut = SizedBox(
                width: diameter,
                height: diameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(diameter),
                      painter: _DonutPainter(
                        values: [for (final entry in visible) entry.bytes],
                        colors: [
                          for (final entry in visible)
                            colors[entries.indexOf(entry) % colors.length],
                        ],
                        track: scheme.surfaceContainerHighest,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Format.bytes(total),
                          style: AppTextStyle.titleLarge.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'classified',
                          style: AppTextStyle.labelSmall.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final legend = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in visible.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.space4,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: AppDimens.space8,
                            height: AppDimens.space8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors[
                                  entries.indexOf(entry) % colors.length],
                            ),
                          ),
                          const SizedBox(width: AppDimens.space8),
                          Expanded(
                            child: Text(
                              entry.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.bodySmall.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            total == 0
                                ? '0%'
                                : '${(entry.bytes / total * 100).round()}%',
                            style: AppTextStyle.labelMedium.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: donut),
                    const SizedBox(height: AppDimens.space12),
                    legend,
                  ],
                );
              }

              return Row(
                children: [
                  donut,
                  const SizedBox(width: AppDimens.space16),
                  Expanded(child: legend),
                ],
              );
            },
          ),
          const SizedBox(height: AppDimens.space12),
          const Divider(),
          const SizedBox(height: AppDimens.space10),
          for (var i = 0; i < entries.length; i++)
            if (entries[i].count > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimens.space6,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: AppDimens.iconTile,
                      height: AppDimens.iconTile,
                      child: Center(
                        child: NexaFileGlyph(
                          name: _glyphNames[entries[i].key] ?? 'file',
                          size: AppDimens.iconTile,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimens.space10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].label,
                            style: AppTextStyle.titleMedium.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            Format.count(entries[i].count, 'file'),
                            style: AppTextStyle.labelSmall.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Format.bytes(entries[i].bytes),
                      style: AppTextStyle.bodyMedium.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;
  final Color track;

  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    const stroke = 17.0;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(bounds, -math.pi / 2, math.pi * 2, false, trackPaint);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = colors[i % colors.length];
      canvas.drawArc(bounds, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.colors != colors ||
      oldDelegate.track != track;
}

class _ActivityPanel extends StatelessWidget {
  final List<StorageDayStat> days;

  const _ActivityPanel({required this.days});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = days.fold<int>(0, (sum, day) => sum + day.count);
    if (days.isEmpty) {
      return const _EmptyStatsPanel(
          message: 'No recent activity data available.');
    }
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '$total changes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.titleLarge.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              Text(
                'Last 7 days',
                style: AppTextStyle.labelMedium.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.space16),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _ActivityPainter(
                days: days,
                // Data series resolved from M3 roles via the active scheme.
                bar: scheme.primary,
                empty: scheme.surfaceContainerHighest,
                text: scheme.onSurfaceVariant,
                grid: scheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
          Text(
            'A daily count based on each file’s last-modified timestamp.',
            style: AppTextStyle.labelSmall.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityPainter extends CustomPainter {
  final List<StorageDayStat> days;
  final Color bar;
  final Color empty;
  final Color text;
  final Color grid;

  const _ActivityPainter({
    required this.days,
    required this.bar,
    required this.empty,
    required this.text,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 6.0;
    const top = 10.0;
    const labelHeight = 22.0;
    final chartHeight = size.height - top - labelHeight;
    final baseline = top + chartHeight;
    final maxValue = days.fold<int>(0, (max, day) => math.max(max, day.count));
    final slot = (size.width - left * 2) / math.max(days.length, 1);
    final barWidth = math.min(22.0, slot * 0.52);

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + chartHeight * i / 2;
      canvas.drawLine(Offset(left, y), Offset(size.width - left, y), gridPaint);
    }

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final fraction = maxValue == 0 ? 0.0 : day.count / maxValue;
      final height = fraction * (chartHeight - 8);
      final x = left + slot * i + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline - height, barWidth, math.max(height, 2)),
        Radius.circular(AppDimens.radiusSmall),
      );
      final paint = Paint()..color = day.count > 0 ? bar : empty;
      canvas.drawRRect(rect, paint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: day.label,
          style: AppTextStyle.labelSmall.copyWith(color: text),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: slot);
      labelPainter.paint(
        canvas,
        Offset(left + slot * i + (slot - labelPainter.width) / 2, baseline + 7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.bar != bar ||
      oldDelegate.empty != empty ||
      oldDelegate.text != text ||
      oldDelegate.grid != grid;
}

class _SizeDistributionPanel extends StatelessWidget {
  final List<StorageSizeBand> bands;
  final int totalFiles;

  const _SizeDistributionPanel({
    required this.bands,
    required this.totalFiles,
  });

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) {
      return const _EmptyStatsPanel(
          message: 'File-size distribution is unavailable.');
    }

    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Column(
        children: [
          for (var i = 0; i < bands.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == bands.length - 1 ? 0 : AppDimens.space16,
              ),
              child: _SizeBandRow(
                band: bands[i],
                totalFiles: totalFiles,
                color: _bandColor(i, Theme.of(context).brightness),
              ),
            ),
        ],
      ),
    );
  }

  Color _bandColor(int index, Brightness brightness) {
    final colors = AppColors.analyticsPaletteFor(brightness);
    return colors[(index + 1) % colors.length];
  }
}

class _SizeBandRow extends StatelessWidget {
  final StorageSizeBand band;
  final int totalFiles;
  final Color color;

  const _SizeBandRow({
    required this.band,
    required this.totalFiles,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = totalFiles == 0
        ? 0.0
        : (band.count / totalFiles).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                band.label,
                style: AppTextStyle.titleMedium.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            Text(
              '${band.count} files · ${Format.bytes(band.bytes)}',
              style: AppTextStyle.labelMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: AppDimens.space8,
            // The band colour is a data series from the M3 analytics palette.
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
            semanticsLabel: '${band.label}: ${band.count} files',
          ),
        ),
      ],
    );
  }
}

class _LargestFilesPanel extends StatelessWidget {
  final List<StorageLargestFile> files;

  const _LargestFilesPanel({required this.files});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (files.isEmpty) {
      return const _EmptyStatsPanel(message: 'No files have been stored yet.');
    }
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      child: Column(
        children: [
          for (var i = 0; i < files.length; i++) ...[
            ListTile(
              leading: SizedBox(
                width: AppDimens.iconTile,
                height: AppDimens.iconTile,
                child: Center(
                  child: NexaFileGlyph(
                    name: files[i].name,
                    size: AppDimens.iconTile,
                  ),
                ),
              ),
              title: Text(
                files[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.titleMedium.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              subtitle: Text(
                files[i].path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.labelSmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: Text(
                Format.bytes(files[i].sizeBytes),
                style: AppTextStyle.titleMedium.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (i < files.length - 1)
              Divider(
                  indent: AppDimens.rowInset, endIndent: AppDimens.rowInset),
          ],
        ],
      ),
    );
  }
}

class _EmptyStatsPanel extends StatelessWidget {
  final String message;

  const _EmptyStatsPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusCard,
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppDimens.space10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
