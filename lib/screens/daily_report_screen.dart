import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/daily_report.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

/// Daily AI report for any day, with the evening notification settings.
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});
  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime day = DateTime.now();

  Future<(DailyReport, Map<String, String>)> _load() async => (await DailyReport.load(day), await Books.settings());

  bool get isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  Widget _tile(String label, int v, List<Color> colors, IconData icon, {String? sub}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F2F9)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: colors)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: _j(11.5, FontWeight.w600, _muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Money.rs(v), style: _j(16, FontWeight.w800, _ink)),
              ),
              if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w600, _muted)),
            ]),
          ),
        ]),
      );

  Widget _section(String title, IconData icon, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF1F2F9))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: _ink),
            const SizedBox(width: 6),
            Text(title, style: _j(14.5, FontWeight.w800, _ink)),
          ]),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _line(String a, String b, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a, style: _j(13, FontWeight.w600, _ink))),
          Text(b, style: _j(13, FontWeight.w800, color ?? _ink)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Live<(DailyReport, Map<String, String>)>(
      key: ValueKey(ymd(day)),
      load: _load,
      builder: (context, data) {
        final (r, s) = data;
        final on = s['daily_report'] != '0';
        final at = s['daily_report_at'] ?? '21:00';
        final shop = (s['business_name'] ?? '').trim().isEmpty ? 'GameX Pc Hub' : s['business_name']!.trim();
        return PageShell(
          title: 'Daily AI Report',
          subtitle: isToday ? 'Today · ${prettyDate(r.day)}' : prettyDate(r.day),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2015), lastDate: DateTime.now());
                    if (d != null) setState(() => day = d);
                  },
                  child: Text(isToday ? 'Today' : prettyDate(r.day), textAlign: TextAlign.center, style: _j(15, FontWeight.w800, _ink)),
                ),
              ),
              IconButton(
                onPressed: isToday ? null : () => setState(() => day = day.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2), Color(0xFF7B3FF2)]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total sales', style: _j(12.5, FontWeight.w600, const Color(0xD9FFFFFF))),
                Text(Money.rs(r.sales), style: _j(30, FontWeight.w800, Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '${r.invoices} bills · ${r.items} items · ${r.prevSales > 0 || r.sales > 0 ? '${r.change >= 0 ? '▲' : '▼'} ${r.change.abs()}% vs the day before' : 'no sales the day before'}',
                  style: _j(12, FontWeight.w600, const Color(0xE6FFFFFF)),
                ),
                if (r.best != null) ...[
                  const SizedBox(height: 4),
                  Text('🔥 Best seller: ${r.best}', style: _j(12, FontWeight.w700, const Color(0xFFFFE08A))),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _tile('Profit', r.profit, const [Color(0xFF3EE08F), Color(0xFF0E9F5E)], Icons.trending_up_rounded, sub: 'Margin ${r.margin}%')),
              const SizedBox(width: 10),
              Expanded(child: _tile('Collected', r.collected, const [Color(0xFF6AA5FF), Color(0xFF1A47C8)], Icons.south_west_rounded)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _tile('Expenses', r.expenses, const [Color(0xFFFF7A7A), Color(0xFFDC4545)], Icons.sell_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _tile('New dues', r.newDue, const [Color(0xFFFFB547), Color(0xFFE38A0B)], Icons.schedule_rounded, sub: 'Total ${Money.compact(r.totalDue)}')),
            ]),
            if (r.cash.isNotEmpty)
              _section('Where the money is (now)', Icons.account_balance_wallet_rounded, [
                for (final e in r.cash.entries) _line(e.key, Money.rs(e.value), color: e.value < 0 ? _red : null),
              ]),
            _section('Due tomorrow', Icons.event_rounded, [
              if (r.tomorrow.isEmpty) Text('No payments due tomorrow', style: _j(12.5, FontWeight.w500, _muted)),
              for (final x in r.tomorrow)
                _line('${x['name']} · ${x['what']}${x['late'] == true ? ' (late)' : ''}', Money.rs(asInt(x['amount'])),
                    color: x['late'] == true ? _red : _green),
            ]),
            _section('To reorder', Icons.inventory_2_rounded, [
              if (r.reorder.isEmpty) Text('Nothing to reorder right now', style: _j(12.5, FontWeight.w500, _muted)),
              for (final x in r.reorder.take(10))
                _line('${x['name']} · stock ${x['stock']}${x['days'] == null ? '' : ' · ~${x['days']} days'}', '${x['need']} pcs'),
            ]),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                HapticFeedback.selectionClick();
                final ok = await Contact.whatsapp(null, r.text(shop));
                if (!ok && context.mounted) toast(context, 'Report copied');
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(27), color: const Color(0xFF25D366)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.chat_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text('Share report on WhatsApp', style: _j(14.5, FontWeight.w800, Colors.white)),
                ]),
              ),
            ),
            _section('Daily notification', Icons.notifications_active_rounded, [
              Row(children: [
                Expanded(child: Text('Evening AI report notification', style: _j(13, FontWeight.w600, _ink))),
                Switch.adaptive(
                  value: on,
                  onChanged: (v) async {
                    await Books.setSetting('daily_report', v ? '1' : '0');
                    await DailyReport.reschedule();
                  },
                ),
              ]),
              if (on)
                GestureDetector(
                  onTap: () async {
                    final p = at.split(':');
                    final t = await showTimePicker(
                        context: context, initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 21, minute: int.tryParse(p.last) ?? 0));
                    if (t == null) return;
                    await Books.setSetting('daily_report_at', '${two(t.hour)}:${two(t.minute)}');
                    await DailyReport.reschedule();
                  },
                  child: Row(children: [
                    Expanded(child: Text('Time', style: _j(13, FontWeight.w600, _muted))),
                    Text(at, style: _j(14, FontWeight.w800, const Color(0xFF5B2EE0))),
                    const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF5B2EE0)),
                  ]),
                ),
            ]),
          ],
        );
      },
    );
  }
}
