/// GST rules used by billing, the invoice and the returns:
///  · GSTIN check (format + check digit) and its state
///  · intra-state (CGST + SGST) or inter-state (IGST) for each bill
///  · a bill discount lowers the taxable value, so GST is charged after it
library;

import 'money.dart';

class Gst {
  /// GST state codes.
  static const states = {
    '01': 'Jammu & Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra & Nagar Haveli and Daman & Diu',
    '27': 'Maharashtra',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
  };

  static const _chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Null when [gstin] is a valid GSTIN, else what is wrong with it.
  static String? check(String gstin) {
    final g = gstin.trim().toUpperCase();
    if (g.length != 15) return 'GSTIN must have 15 characters';
    if (!RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(g)) return 'GSTIN format is not right (e.g. 19ABCDE1234F1Z5)';
    if (!states.containsKey(g.substring(0, 2))) return 'GSTIN state code ${g.substring(0, 2)} is not valid';
    if (g[14] != checkDigit(g.substring(0, 14))) return 'GSTIN check digit is wrong — check for a typo';
    return null;
  }

  static bool valid(String? gstin) => gstin != null && check(gstin) == null;

  /// The 15th character of a GSTIN.
  static String checkDigit(String first14) {
    var sum = 0;
    for (var i = 0; i < 14; i++) {
      final v = _chars.indexOf(first14[i]) * (i.isOdd ? 2 : 1);
      sum += v ~/ 36 + v % 36;
    }
    return _chars[(36 - sum % 36) % 36];
  }

  /// State code of a GSTIN ('19'), or null.
  static String? stateOf(String? gstin) {
    final g = (gstin ?? '').trim();
    if (g.length < 2) return null;
    final c = g.substring(0, 2);
    return states.containsKey(c) ? c : null;
  }

  /// The shop's state code: from its GSTIN, else the State in settings.
  static String shopState(Map<String, String> settings) {
    final fromGstin = stateOf(settings['gstin']);
    if (fromGstin != null) return fromGstin;
    final code = (settings['state_code'] ?? '').trim();
    if (states.containsKey(code)) return code;
    final name = (settings['state'] ?? '').trim().toLowerCase();
    for (final e in states.entries) {
      if (e.value.toLowerCase() == name) return e.key;
    }
    return '19';
  }

  /// Place of supply for a bill: the registered customer's state, else the
  /// shop's (an over-the-counter sale is supplied where the shop is).
  static String placeOfSupply(Map<String, String> settings, String? customerGstin) => stateOf(customerGstin) ?? shopState(settings);

  /// IGST (inter-state) when the customer is registered in another state.
  static bool interState(Map<String, String> settings, String? customerGstin) {
    final c = stateOf(customerGstin);
    return c != null && c != shopState(settings);
  }

  static String stateName(String code) => '${states[code] ?? 'State'} ($code)';

  /// A bill discount ([offBill] = money off the final bill, GST included)
  /// spread over the lines in proportion to their value, with GST charged on
  /// what is left. [lines] are (amount before GST, GST rate in basis points).
  /// Returns the discount before GST and the GST of each line after it.
  static (int, List<int>) afterDiscount(List<(int, int)> lines, int offBill) {
    final subtotal = lines.fold<int>(0, (a, l) => a + l.$1);
    final full = [for (final l in lines) Money.percent(l.$1, l.$2)];
    final fullTax = full.fold<int>(0, (a, t) => a + t);
    if (offBill <= 0 || subtotal <= 0) return (0, full);
    final d = offBill.clamp(0, subtotal + fullTax);
    final ex = (d * subtotal / (subtotal + fullTax)).round();
    final taxes = [
      for (final l in lines) Money.percent(l.$1 - share(ex, l.$1, subtotal), l.$2),
    ];
    return (ex, taxes);
  }

  /// One line's part of a bill discount (before GST) — the same everywhere
  /// (invoice, returns, GST report).
  static int share(int discount, int amount, int subtotal) => subtotal == 0 ? 0 : (discount * amount / subtotal).round();
}
