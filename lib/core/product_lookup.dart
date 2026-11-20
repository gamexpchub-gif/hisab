import 'dart:convert';
import 'dart:io';

/// Name, brand and model found online for a box barcode (EAN / UPC).
class BarcodeInfo {
  final String title;
  final String? brand, model, color;
  const BarcodeInfo(this.title, {this.brand, this.model, this.color});
}

/// Looks up a product box barcode in the free UPCitemdb catalogue
/// (no key, ~100 lookups a day). Returns null when not found or offline.
class ProductLookup {
  static Future<BarcodeInfo?> barcode(String code) async {
    final c = code.trim();
    if (!RegExp(r'^\d{8,14}$').hasMatch(c)) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$c'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final items = data['items'] as List? ?? const [];
      if (items.isEmpty) return null;
      final it = items.first as Map<String, dynamic>;
      final title = '${it['title'] ?? ''}'.trim();
      if (title.isEmpty) return null;
      String? s(String k) => '${it[k] ?? ''}'.trim().isEmpty ? null : '${it[k]}'.trim();
      return BarcodeInfo(title, brand: s('brand'), model: s('model'), color: s('color'));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
