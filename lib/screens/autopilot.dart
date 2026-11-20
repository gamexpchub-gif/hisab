import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/autopilot.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';
import 'party_profile.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

BoxDecoration _card() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

/// AI Autopilot: today's reminders and follow-ups (one tap to WhatsApp),
/// the re-order list per supplier and the end-of-day cash check.
class AutopilotScreen extends StatefulWidget {
  final int tab;
  const AutopilotScreen({super.key, this.tab = 0});
  @override
  State<AutopilotScreen> createState() => _AutopilotScreenState();
}

class _AutopilotScreenState extends State<AutopilotScreen> {
  late int tab = widget.tab;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'AI Autopilot',
      subtitle: 'Reminders, follow-ups, re-orders and cash — prepared for you every day',
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _tab(0, Icons.campaign_rounded, 'Today'),
            _tab(1, Icons.local_shipping_rounded, 'Re-order'),
            _tab(2, Icons.account_balance_wallet_rounded, 'Cash close'),
          ]),
        ),
        const SizedBox(height: 12),
        switch (tab) { 0 => const _TodayTab(), 1 => const _ReorderTab(), _ => const _CashTab() },
      ],
    );
  }

  Widget _tab(int i, IconData icon, String label) {
    final on = tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => tab = i);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: on ? Colors.white : _muted),
            const SizedBox(width: 6),
            Text(label, style: _j(12.5, FontWeight.w800, on ? Colors.white : _muted)),
          ]),
        ),
      ),
    );
  }
}

// =============================================================================
// Today: reminders and follow-ups
// =============================================================================
class _TodayTab extends StatefulWidget {
  const _TodayTab();
  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  int _reload = 0;

  (IconData, List<Color>, String) _look(AutoTask t) => switch (t.kind) {
        'due' => (
            Icons.currency_rupee_rounded,
            t.level == 3
                ? const [Color(0xFFFF6B8B), Color(0xFFE0245E)]
                : t.level == 2
                    ? const [Color(0xFFFFB84D), Color(0xFFF97316)]
                    : const [Color(0xFF6AA5FF), Color(0xFF1A47C8)],
            'Payment'
          ),
        'emi' => (Icons.calendar_month_rounded, const [Color(0xFF8B5CF6), Color(0xFF6D28D9)], 'EMI'),
        'warranty' => (Icons.verified_user_rounded, const [Color(0xFF38BDF8), Color(0xFF0E7490)], 'Warranty'),
        'follow7' => (Icons.sentiment_satisfied_alt_rounded, const [Color(0xFF34D399), Color(0xFF0BA360)], 'Follow-up'),
        _ => (Icons.card_giftcard_rounded, const [Color(0xFFF472B6), Color(0xFFDB2777)], 'Offer'),
      };

  Future<void> _send(AutoTask t) async {
    HapticFeedback.mediumImpact();
    final ok = await Contact.whatsapp(t.phone, t.message ?? '');
    if (!ok) {
      if (mounted) toast(context, 'No WhatsApp number for this customer', error: true);
      return;
    }
    await Autopilot.markSent(t.key);
    if (mounted) setState(() => _reload++);
  }

  Future<void> _skip(AutoTask t) async {
    await Autopilot.markSent(t.key);
    if (mounted) {
      toast(context, 'Done — it won\'t be shown again');
      setState(() => _reload++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<List<AutoTask>>(
      reloadKey: _reload,
      load: Autopilot.today,
      builder: (context, tasks) {
        final money = tasks.where((t) => t.kind == 'due' || t.kind == 'emi').fold<int>(0, (a, t) => a + t.amount);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2), Color(0xFF7B3FF2)]),
            ),
            child: Row(children: [
              const Icon(Icons.smart_toy_rounded, color: Color(0xFFFFE08A), size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tasks.isEmpty ? 'All caught up 🎉' : '${tasks.length} message${tasks.length == 1 ? '' : 's'} ready',
                      style: _j(17, FontWeight.w800, Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      money > 0
                          ? '${Money.rs(money)} to collect — tap Send, WhatsApp opens with the message written'
                          : 'Payment reminders (3 · 7 · 15 days), EMI, warranty and after-sale follow-ups appear here',
                      style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          for (final t in tasks) _taskCard(t),
          if (tasks.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 30), child: EmptyState('Nothing to send today — new reminders appear automatically')),
        ]);
      },
    );
  }

  Widget _taskCard(AutoTask t) {
    final (icon, colors, label) = _look(t);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), gradient: LinearGradient(colors: colors)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: t.customerId == null ? null : () => open(context, PartyView(type: 'customer', id: t.customerId!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                const SizedBox(height: 2),
                Text('$label · ${t.sub}', style: _j(11.5, FontWeight.w600, colors.last)),
              ]),
            ),
          ),
        ]),
        if (t.message != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF4F5FB), borderRadius: BorderRadius.circular(12)),
            child: Text(t.message!, maxLines: 4, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, const Color(0xFF3A4155))),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: () => _skip(t), child: const Text('Mark done')),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: (t.phone ?? '').trim().isEmpty ? null : () => _send(t),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text((t.phone ?? '').trim().isEmpty ? 'No phone' : 'Send'),
          ),
        ]),
      ]),
    );
  }
}

// =============================================================================
// Re-order
// =============================================================================
class _ReorderTab extends StatefulWidget {
  const _ReorderTab();
  @override
  State<_ReorderTab> createState() => _ReorderTabState();
}

class _ReorderTabState extends State<_ReorderTab> {
  final qty = <int, int>{}; // product id → qty to order (edited)

  @override
  Widget build(BuildContext context) {
    return Live<(List<ReorderItem>, Map<String, String>)>(
      load: () async => (await Autopilot.reorder(), await Books.settings()),
      builder: (context, data) {
        final (items, settings) = data;
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 30),
            child: EmptyState('Stock is fine — products that will run out within 10 days appear here'),
          );
        }
        final groups = <String, List<ReorderItem>>{};
        for (final i in items) {
          groups.putIfAbsent(i.supplier ?? 'No supplier yet', () => []).add(i);
        }
        final value = items.fold<int>(0, (a, i) => a + (qty[asInt(i.product['id'])] ?? i.suggest) * i.lastRate);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF0E7490), Color(0xFF2563EB)]),
            ),
            child: Row(children: [
              const Icon(Icons.inventory_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${items.length} product${items.length == 1 ? '' : 's'} to order', style: _j(17, FontWeight.w800, Colors.white)),
                  const SizedBox(height: 4),
                  Text('About ${Money.rs(value)} · enough for 30 days at your current sales speed',
                      style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
                ]),
              ),
            ]),
          ),
          for (final g in groups.entries) _supplierCard(g.key, g.value, settings),
        ]);
      },
    );
  }

  Widget _supplierCard(String name, List<ReorderItem> list, Map<String, String> settings) {
    final phone = list.first.supplierPhone;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.storefront_rounded, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: _j(15, FontWeight.w800, _ink))),
          if (list.first.supplierId != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                final order = [
                  for (final i in list)
                    ReorderItem(i.product, i.stock, i.sold30, i.perDay, i.daysLeft, qty[asInt(i.product['id'])] ?? i.suggest, i.lastRate,
                        i.supplierId, i.supplier, i.supplierPhone),
                ];
                final ok = await Contact.whatsapp(phone, Autopilot.orderText(settings, name, order));
                if (!ok && mounted) toast(context, 'Add a phone number for $name first', error: true);
              },
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('Order'),
            ),
        ]),
        const Divider(height: 18),
        for (final i in list) _row(i),
      ]),
    );
  }

  Widget _row(ReorderItem i) {
    final id = asInt(i.product['id']);
    final q = qty[id] ?? i.suggest;
    final out = (i.daysLeft ?? 99) <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i.product['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
            Text(
              out
                  ? 'Out of stock · sells ${i.sold30}/month'
                  : 'Stock ${i.stock} · runs out in ~${i.daysLeft} day${i.daysLeft == 1 ? '' : 's'} · sells ${i.sold30}/month',
              style: _j(11, FontWeight.w600, out ? _red : const Color(0xFFF97316)),
            ),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: q > 1 ? () => setState(() => qty[id] = q - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(width: 28, child: Text('$q', textAlign: TextAlign.center, style: _j(15, FontWeight.w800, _ink))),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => qty[id] = q + 1),
          icon: const Icon(Icons.add_circle_outline_rounded, color: _green),
        ),
      ]),
    );
  }
}

// =============================================================================
// Cash close
// =============================================================================
class _CashTab extends StatefulWidget {
  const _CashTab();
  @override
  State<_CashTab> createState() => _CashTabState();
}

class _CashTabState extends State<_CashTab> {
  final counted = TextEditingController();
  final note = TextEditingController();
  int _reload = 0;

  @override
  void dispose() {
    counted.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final v = Money.tryParse(counted.text);
    if (v == null) {
      toast(context, 'Count the cash in the drawer and enter it', error: true);
      return;
    }
    final c = await Autopilot.close(v, note: note.text);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    counted.clear();
    note.clear();
    setState(() => _reload++);
    toast(context, c.diff == 0 ? 'Cash matches exactly ✓' : 'Saved · ${c.diff > 0 ? 'extra' : 'short'} ${Money.rs(c.diff.abs())}', error: c.diff < 0);
  }

  @override
  Widget build(BuildContext context) {
    return Live<(int, List<CashClose>)>(
      reloadKey: _reload,
      load: () async => (await Autopilot.expectedCash(), await Autopilot.closes()),
      builder: (context, data) {
        final (expected, history) = data;
        final typed = Money.tryParse(counted.text);
        final diff = typed == null ? null : typed - expected;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF0BA360), Color(0xFF0E7490)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cash that should be in the drawer', style: _j(12.5, FontWeight.w600, const Color(0xD9FFFFFF))),
              const SizedBox(height: 4),
              Text(Money.rs(expected), style: _j(28, FontWeight.w800, Colors.white)),
              Text('From your books: cash sales, receipts, payments and expenses', style: _j(11, FontWeight.w500, const Color(0xB3FFFFFF))),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Count the cash and enter it', style: _j(14, FontWeight.w800, _ink)),
              const SizedBox(height: 10),
              TextField(
                controller: counted,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: _j(18, FontWeight.w800, _ink),
                decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Cash counted'),
              ),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              if (diff != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (diff == 0 ? _green : diff > 0 ? const Color(0xFF2563EB) : _red).withAlpha(0x1A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(diff == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                        color: diff == 0 ? _green : diff > 0 ? const Color(0xFF2563EB) : _red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        diff == 0
                            ? 'Matches exactly'
                            : diff > 0
                                ? '${Money.rs(diff)} extra — a sale or receipt may not be entered'
                                : '${Money.rs(-diff)} short — check expenses, change given and unentered payments',
                        style: _j(12.5, FontWeight.w700, diff == 0 ? _green : diff > 0 ? const Color(0xFF2563EB) : _red),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _close,
                icon: const Icon(Icons.lock_clock_rounded),
                label: const Text('Close today\'s cash'),
              ),
            ]),
          ),
          if (history.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('Recent days', style: _j(15, FontWeight.w800, _ink))),
            Container(
              decoration: _card(),
              child: Column(children: [
                for (final c in history.take(30))
                  ListTile(
                    dense: true,
                    title: Text(prettyDate(c.date), style: _j(13, FontWeight.w700, _ink)),
                    subtitle: Text('Expected ${Money.rs(c.expected)} · counted ${Money.rs(c.counted)}${c.note.isEmpty ? '' : ' · ${c.note}'}',
                        style: _j(11, FontWeight.w500, _muted)),
                    trailing: Text(
                      c.diff == 0 ? '✓' : '${c.diff > 0 ? '+' : '−'}${Money.rs(c.diff.abs())}',
                      style: _j(13, FontWeight.w800, c.diff == 0 ? _green : c.diff > 0 ? const Color(0xFF2563EB) : _red),
                    ),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
