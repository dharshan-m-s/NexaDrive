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
    final brightness = Theme.of(context).brightness;
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
          color: AppColors.accentTextFor(brightness),
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
                label: 'FILES',
                value: Format.count(storage.fileCount, 'file'),
                tint: AppColors.accentFor(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(width: AppDimens.space10),
            Expanded(
              child: _MetricPanel(
                icon: Icons.data_usage_rounded,
                label: 'AVERAGE FILE',
                value: Format.bytes(average),
                tint: AppColors.infoFor(Theme.of(context).brightness),
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
          style: AppTextStyle.caption1.copyWith(
            color: AppColors.labelSecondaryFor(Theme.of(context).brightness),
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
    final brightness = Theme.of(context).brightness;
    final hasQuota = storage.quotaBytes != null;
    final percent = (storage.usageFraction * 100).round();

    return NexaSurface(
      level: NexaSurfaceLevel.floating,
      radius: AppDimens.radiusXLarge,
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
                      'YOUR STORAGE',
                      style: AppTextStyle.caption2.copyWith(
                        color: AppColors.labelSecondaryFor(brightness),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: AppDimens.space6),
                    Text(
                      Format.bytes(storage.usedBytes),
                      style: AppTextStyle.heroTitle.copyWith(
                        color: AppColors.labelPrimaryFor(brightness),
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.1,
                      ),
                    ),
                    Text(
                      hasQuota
                          ? 'of ${Format.bytes(storage.quotaBytes!)}'
                          : 'Unlimited capacity',
                      style: AppTextStyle.subheadline.copyWith(
                        color: AppColors.labelSecondaryFor(brightness),
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
                        track: AppColors.fillTertiaryFor(brightness),
                        progress: AppColors.accentFor(brightness),
                        secondary: AppColors.infoFor(brightness),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasQuota ? '$percent%' : '∞',
                          style: AppTextStyle.headline.copyWith(
                            color: AppColors.labelPrimaryFor(brightness),
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          hasQuota ? 'used' : 'no limit',
                          style: AppTextStyle.caption2.copyWith(
                            color: AppColors.labelSecondaryFor(brightness),
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
            child: SizedBox(
              height: 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.fillFor(brightness)),
                  if (hasQuota)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: storage.usageFraction,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accentFor(brightness),
                                AppColors.infoFor(brightness),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space12),
          Row(
            children: [
              Expanded(
                child: _CapacityValue(
                  label: 'USED',
                  value: Format.bytes(storage.usedBytes),
                  color: AppColors.accentFor(brightness),
                ),
              ),
              Expanded(
                child: _CapacityValue(
                  label: 'AVAILABLE',
                  value:
                      hasQuota ? Format.bytes(storage.freeBytes) : 'No limit',
                  color: AppColors.infoFor(brightness),
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
  final Color secondary;

  const _CapacityRingPainter({
    required this.fraction,
    required this.track,
    required this.progress,
    required this.secondary,
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
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [progress, secondary],
      ).createShader(bounds);
    canvas.drawArc(bounds, -math.pi / 2, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _CapacityRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.progress != progress ||
      oldDelegate.secondary != secondary;
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
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppDimens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyle.caption2.copyWith(
                  color: AppColors.labelSecondaryFor(brightness),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.subheadline.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                  fontWeight: FontWeight.w700,
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
    final brightness = Theme.of(context).brightness;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusLarge,
      padding: const EdgeInsets.all(AppDimens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 21),
          const SizedBox(height: AppDimens.space12),
          Text(
            label,
            style: AppTextStyle.caption2.copyWith(
              color: AppColors.labelSecondaryFor(brightness),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: AppDimens.space4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.headline.copyWith(
              color: AppColors.labelPrimaryFor(brightness),
            ),
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
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyle.sectionHeader.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              Text(
                subtitle,
                style: AppTextStyle.caption1.copyWith(
                  color: AppColors.labelSecondaryFor(brightness),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppDimens.space8),
          Text(
            trailing!,
            style: AppTextStyle.caption1.copyWith(
              color: AppColors.labelSecondaryFor(brightness),
              fontWeight: FontWeight.w700,
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

  static const _icons = <String, IconData>{
    'images': Icons.image_outlined,
    'videos': Icons.movie_outlined,
    'audio': Icons.audio_file_outlined,
    'documents': Icons.description_outlined,
    'archives': Icons.archive_outlined,
    'other': Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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
      radius: AppDimens.radiusLarge,
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
                        track: AppColors.fillFor(brightness),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Format.bytes(total),
                          style: AppTextStyle.headline.copyWith(
                            color: AppColors.labelPrimaryFor(brightness),
                            fontSize: compact ? 15 : 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'classified',
                          style: AppTextStyle.caption2.copyWith(
                            color: AppColors.labelSecondaryFor(brightness),
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
                            width: 8,
                            height: 8,
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
                              style: AppTextStyle.caption1.copyWith(
                                color: AppColors.labelSecondaryFor(brightness),
                              ),
                            ),
                          ),
                          Text(
                            total == 0
                                ? '0%'
                                : '${(entry.bytes / total * 100).round()}%',
                            style: AppTextStyle.caption1.copyWith(
                              color: AppColors.labelPrimaryFor(brightness),
                              fontWeight: FontWeight.w700,
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
          const Divider(height: 1),
          const SizedBox(height: AppDimens.space10),
          for (var i = 0; i < entries.length; i++)
            if (entries[i].count > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimens.space6,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length].withValues(
                          alpha: brightness == Brightness.dark ? 0.20 : 0.12,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusSmall),
                      ),
                      child: Icon(
                        _icons[entries[i].key] ??
                            Icons.insert_drive_file_outlined,
                        color: colors[i % colors.length],
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppDimens.space10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].label,
                            style: AppTextStyle.bodyEmphasized.copyWith(
                              color: AppColors.labelPrimaryFor(brightness),
                            ),
                          ),
                          Text(
                            Format.count(entries[i].count, 'file'),
                            style: AppTextStyle.caption2.copyWith(
                              color: AppColors.labelSecondaryFor(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Format.bytes(entries[i].bytes),
                      style: AppTextStyle.subheadline.copyWith(
                        color: AppColors.labelPrimaryFor(brightness),
                        fontWeight: FontWeight.w600,
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
    final brightness = Theme.of(context).brightness;
    final total = days.fold<int>(0, (sum, day) => sum + day.count);
    if (days.isEmpty) {
      return const _EmptyStatsPanel(
          message: 'No recent activity data available.');
    }
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusLarge,
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
                  style: AppTextStyle.headline.copyWith(
                    color: AppColors.labelPrimaryFor(brightness),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.space8),
              Text(
                '7 DAYS',
                style: AppTextStyle.caption2.copyWith(
                  color: AppColors.labelSecondaryFor(brightness),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
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
                bar: AppColors.accentFor(brightness),
                empty: AppColors.fillTertiaryFor(brightness),
                text: AppColors.labelSecondaryFor(brightness),
                grid: AppColors.separatorFor(brightness),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.space8),
          Text(
            'A daily count based on each file’s last-modified timestamp.',
            style: AppTextStyle.caption2.copyWith(
              color: AppColors.labelSecondaryFor(brightness),
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
        const Radius.circular(7),
      );
      final paint = Paint()..color = day.count > 0 ? bar : empty;
      canvas.drawRRect(rect, paint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: day.label,
          style: TextStyle(
            color: text,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
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
      radius: AppDimens.radiusLarge,
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
    final brightness = Theme.of(context).brightness;
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
                style: AppTextStyle.bodyEmphasized.copyWith(
                  color: AppColors.labelPrimaryFor(brightness),
                ),
              ),
            ),
            Text(
              '${band.count} files · ${Format.bytes(band.bytes)}',
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          child: SizedBox(
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.fillFor(brightness)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                ),
              ],
            ),
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
    final brightness = Theme.of(context).brightness;
    if (files.isEmpty) {
      return const _EmptyStatsPanel(message: 'No files have been stored yet.');
    }
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusLarge,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space4,
      ),
      child: Column(
        children: [
          for (var i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.space10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accentContainerFor(brightness),
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusSmall),
                    ),
                    child: Icon(
                      _fileIcon(files[i].name),
                      color: AppColors.accentTextFor(brightness),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: AppDimens.space10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          files[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.bodyEmphasized.copyWith(
                            color: AppColors.labelPrimaryFor(brightness),
                          ),
                        ),
                        Text(
                          files[i].path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption2.copyWith(
                            color: AppColors.labelSecondaryFor(brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  Text(
                    Format.bytes(files[i].sizeBytes),
                    style: AppTextStyle.subheadline.copyWith(
                      color: AppColors.labelPrimaryFor(brightness),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'avif'}
        .contains(extension)) {
      return Icons.image_outlined;
    }
    if (const {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'}.contains(extension)) {
      return Icons.movie_outlined;
    }
    if (const {'mp3', 'm4a', 'wav', 'flac', 'ogg'}.contains(extension)) {
      return Icons.audio_file_outlined;
    }
    if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _EmptyStatsPanel extends StatelessWidget {
  final String message;

  const _EmptyStatsPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return NexaSurface(
      level: NexaSurfaceLevel.grouped,
      radius: AppDimens.radiusLarge,
      padding: const EdgeInsets.all(AppDimens.space20),
      child: Row(
        children: [
          Icon(
            Icons.insights_outlined,
            color: AppColors.labelTertiaryFor(brightness),
          ),
          const SizedBox(width: AppDimens.space10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
