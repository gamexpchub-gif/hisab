/// Money is stored as integer paise (₹1 = 100) — never floating point.
class Money {
  static int parse(String? input) {
    var s = (input ?? '').trim().replaceAll(',', '').replaceAll('₹', '');
    if (s.isEmpty) return 0;
    final neg = s.startsWith('-');
    if (neg) s = s.substring(1);
    final parts = s.split('.');
    if (parts.length > 2) throw const FormatException('Invalid amount');
    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null) throw const FormatException('Invalid amount');
    var frac = 0;
    if (parts.length == 2) {
      var f = parts[1];
      if (f.length > 2) f = f.substring(0, 2);
      final parsed = int.tryParse(f.padRight(2, '0'));
      if (parsed == null) throw const FormatException('Invalid amount');
      frac = parsed;
    }
    final v = whole * 100 + frac;
    return neg ? -v : v;
  }

  /// Indian digit grouping: 12,34,567 — decimals shown only when non-zero.
  static String inr(int paise, {bool decimals = false}) {
    final neg = paise < 0;
    final a = paise.abs();
    final whole = (a ~/ 100).toString();
    final frac = (a % 100).toString().padLeft(2, '0');
    String grouped = whole;
    if (whole.length > 3) {
      var head = whole.substring(0, whole.length - 3);
      final tail = whole.substring(whole.length - 3);
      final groups = <String>[];
      while (head.length > 2) {
        groups.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      if (head.isNotEmpty) groups.insert(0, head);
      grouped = '${groups.join(',')},$tail';
    }
    final out = (decimals || frac != '00') ? '$grouped.$frac' : grouped;
    return neg ? '-$out' : out;
  }

  static String rs(int paise) => '₹${inr(paise)}';

  /// Plain editable text (e.g. "1250.50").
  static String edit(int paise) {
    final s = '${paise.abs() ~/ 100}.${(paise.abs() % 100).toString().padLeft(2, '0')}';
    return paise < 0 ? '-$s' : s;
  }

  /// amount × basis points / 10000, rounded half up (1800 bp = 18%).
  static int percent(int amount, int basisPoints) {
    final p = amount * basisPoints;
    return p >= 0 ? (p + 5000) ~/ 10000 : -((-p + 5000) ~/ 10000);
  }
}

String two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';

DateTime parseYmd(String s) => DateTime.parse(s);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String monthName(int m) => _months[m - 1];

String prettyDate(String s) {
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return '${two(d.day)} ${_months[d.month - 1]} ${d.year}';
}

String timeAgo(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final secs = DateTime.now().difference(d).inSeconds;
  if (secs < 60) return 'Just now';
  if (secs < 3600) return '${secs ~/ 60} min ago';
  if (secs < 86400) return '${secs ~/ 3600} hr ago';
  final days = secs ~/ 86400;
  return days == 1 ? 'Yesterday' : '$days days ago';
}
