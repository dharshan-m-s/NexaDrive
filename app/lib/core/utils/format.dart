/// Formatting helpers for bytes, dates and time spans.
abstract final class Format {
  /// Formats a byte count into a human-readable string.
  /// "125 B", "1.5 MB", "12.3 GB".
  static String bytes(num? value) {
    if (value == null) return '';
    final units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double n = value.toDouble();
    int i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    final digits = n >= 10 || i == 0 ? 0 : 1;
    return '${n.toStringAsFixed(digits)} ${units[i]}';
  }

  /// Formats an ISO-8601 timestamp into a readable relative string.
  static String relTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _shortDate(time);
  }

  static String _shortDate(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[time.month - 1]} ${time.day}';
    }
    return '${time.year}/${_two(time.month)}/${_two(time.day)}';
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// Formats a timestamp as a short date-time: "2026-09-10 14:30".
  static String shortDateTime(DateTime? time) {
    if (time == null) return '';
    return '${time.year}-${_two(time.month)}-${_two(time.day)} '
        '${_two(time.hour)}:${_two(time.minute)}';
  }

  /// Pluralizes a simple label.
  static String count(int n, String singular, [String? plural]) {
    if (n == 1) return '1 $singular';
    return '$n ${plural ?? '${singular}s'}';
  }

  /// Formats a Duration as "m:ss" or "h:mm:ss" when the hour part is non-zero.
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final sec = _two(seconds);
    if (hours > 0) {
      return '$hours:${_two(minutes)}:$sec';
    }
    return '$minutes:$sec';
  }
}