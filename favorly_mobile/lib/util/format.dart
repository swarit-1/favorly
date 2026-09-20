/// Small formatting helpers. No intl dependency: the demo is US English.
library;

String money(double value) => '\$${value.toStringAsFixed(2)}';

/// "$40" for whole dollars, "$4.50" otherwise. Used for caps and estimates.
String moneyShort(double value) =>
    value == value.roundToDouble() ? '\$${value.toInt()}' : money(value);

String clock(DateTime t) {
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String dayLabel(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return _weekdays[t.weekday - 1];
  if (diff < -1 && diff > -7) return 'Last ${_weekdays[t.weekday - 1]}';
  return '${_months[t.month - 1]} ${t.day}';
}

/// "Today · 3:00 PM"
String whenLabel(DateTime t, {DateTime? now}) =>
    '${dayLabel(t, now: now)} · ${clock(t)}';

/// "Leaves in 2h 10m", "Leaves in 25 min", "Leaving now", "Left at 3:00 PM"
String leavesLabel(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = t.difference(ref);
  if (diff.inMinutes <= -30) return 'Left at ${clock(t)}';
  if (diff.inMinutes < 5) return 'Leaving now';
  if (diff.inMinutes < 60) return 'Leaves in ${diff.inMinutes} min';
  if (diff.inHours < 12) {
    final mins = diff.inMinutes % 60;
    return mins == 0
        ? 'Leaves in ${diff.inHours}h'
        : 'Leaves in ${diff.inHours}h ${mins}m';
  }
  return 'Leaves ${dayLabel(t, now: ref).toLowerCase()} · ${clock(t)}';
}

/// "just now" / "20m ago" / "3h ago" / "2d ago". Matches how Trellis words
/// the `posted` field, so a locally timed label sits next to a server one
/// without looking like a different app wrote it.
String agoLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String greeting(DateTime now) {
  if (now.hour < 5) return 'Up late';
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String joinNames(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}

/// "2:41" for a countdown.
String countdown(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
