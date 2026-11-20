import 'dart:convert';

import 'books.dart';

/// Unfinished sales and purchases, saved when the screen is left or the app
/// goes to the background, and offered again the next time it is opened.
/// Kept in the store's own settings, so every store has its own draft.
class Drafts {
  static String _key(String kind) => 'draft_$kind';

  static Future<Map<String, dynamic>?> load(String kind) async {
    final s = (await Books.settings())[_key(kind)];
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return (m['lines'] as List?)?.isNotEmpty == true ? m : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String kind, Map<String, dynamic> data) async {
    try {
      await Books.setSetting(_key(kind), jsonEncode({...data, 'saved': DateTime.now().toIso8601String()}));
    } catch (_) {}
  }

  static Future<void> clear(String kind) async {
    try {
      final s = (await Books.settings())[_key(kind)];
      if (s != null && s.isNotEmpty) await Books.setSetting(_key(kind), '');
    } catch (_) {}
  }

  /// "3 items · 5 min ago"
  static String summary(Map<String, dynamic> d) {
    final n = (d['lines'] as List).length;
    final t = DateTime.tryParse('${d['saved'] ?? ''}');
    var ago = '';
    if (t != null) {
      final m = DateTime.now().difference(t).inMinutes;
      ago = m < 1 ? ' · just now' : m < 60 ? ' · $m min ago' : m < 1440 ? ' · ${m ~/ 60} h ago' : ' · ${m ~/ 1440} days ago';
    }
    return '$n item${n == 1 ? '' : 's'}$ago';
  }
}
