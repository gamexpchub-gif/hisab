import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud.dart';
import '../core/books.dart';
import '../core/plan.dart';
import '../ui/charts.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';
import 'plans.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

String _d(DateTime? d) => d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _ago(DateTime? d) {
  if (d == null) return 'kokhono na';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 2) return 'ekhoni';
  if (m < 60) return '$m min age';
  if (m < 60 * 24) return '${m ~/ 60} ghonta age';
  return '${m ~/ (60 * 24)} din age';
}

/// Hisab AI admin panel: every account, plans, requests and revenue.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<CloudAccount> accounts = [];
  List<PlanRequest> requests = [];
  String? error;
  bool loading = true;
  String tab = 'all'; // all | trial | paid | expired | blocked
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final a = await Accounts.listAccounts();
      List<PlanRequest> r = const [];
      try {
        r = await Accounts.listRequests();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        accounts = a;
        requests = r;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  CloudAccount? _acc(String uid) => accounts.where((a) => a.uid == uid).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final pending = requests.where((r) => r.status == 'pending').toList();
    final paid = accounts.where((a) => a.active && a.plan != 'trial').toList();
    final mrr = paid.fold<int>(0, (s, a) => s + a.price);
    final byPlan = <String, int>{
      for (final p in plans) p.name: accounts.where((a) => a.active && a.plan == p.id).length,
      'Trial': accounts.where((a) => a.active && a.plan == 'trial').length,
      'Expired': accounts.where((a) => !a.active && !a.blocked).length,
    }..removeWhere((k, v) => v == 0);
    final week = DateTime.now().subtract(const Duration(days: 7));
    final activeWeek = accounts.where((a) => a.lastSeen != null && a.lastSeen!.isAfter(week)).length;
    final ending = accounts.where((a) => a.active && a.until != null && a.until!.difference(DateTime.now()).inDays <= 5).toList();
    final shown = accounts.where((a) {
      final okTab = switch (tab) {
        'trial' => a.active && a.plan == 'trial',
        'paid' => a.active && a.plan != 'trial',
        'expired' => !a.active && !a.blocked,
        'blocked' => a.blocked,
        _ => true,
      };
      final s = q.toLowerCase();
      return okTab && (s.isEmpty || '${a.email} ${a.name} ${a.shop} ${a.phone}'.toLowerCase().contains(s));
    }).toList();

    return PageShell(
      title: 'Admin Panel',
      subtitle: 'Hisab AI · ${accounts.length} account',
      action: IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      children: [
        if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (error != null) _setupHelp(error!),
        if (!loading && error == null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [Color(0xFF0F1240), Color(0xFF2A1E8F), Color(0xFF6B35EE)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.shield_rounded, color: Color(0xFFFFE08A), size: 18),
                const SizedBox(width: 6),
                Text('Mashik ay (MRR)', style: _j(12.5, FontWeight.w600, const Color(0xD9FFFFFF))),
              ]),
              Text('₹$mrr', style: _j(32, FontWeight.w800, Colors.white)),
              Text('${paid.length} paid · bochore ~₹${mrr * 12}', style: _j(12, FontWeight.w600, const Color(0xD9FFFFFF))),
              const SizedBox(height: 14),
              Row(children: [
                _hs('Mot user', '${accounts.length}'),
                _hs('7 dine active', '$activeWeek'),
                _hs('Request', '${pending.length}', hot: pending.isNotEmpty),
              ]),
            ]),
          ),
          if (byPlan.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F2F9))),
              child: Row(children: [
                DonutChart(
                  parts: [for (final e in byPlan.entries) MapEntry(e.key, e.value * 100)],
                  colors: [
                    for (final k in byPlan.keys)
                      (planColors[k.toLowerCase()] ?? (k == 'Expired' ? planColors['none']! : planColors['trial']!)).last
                  ],
                  size: 110,
                  centerTop: '${accounts.length}',
                  centerBottom: 'user',
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final e in byPlan.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (planColors[e.key.toLowerCase()] ?? (e.key == 'Expired' ? planColors['none']! : planColors['trial']!)).last,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(child: Text(e.key, style: _j(12.5, FontWeight.w700, _ink))),
                          Text('${e.value}', style: _j(13, FontWeight.w800, _ink)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Plan request · ${pending.length}', style: _j(15, FontWeight.w800, _ink)),
            const SizedBox(height: 8),
            for (final r in pending) _requestCard(r),
          ],
          if (ending.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Shiggiri shesh hobe · ${ending.length}', style: _j(15, FontWeight.w800, _ink)),
            const SizedBox(height: 8),
            for (final a in ending.take(5)) _userCard(a),
          ],
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Email, naam, dokan, phone…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in const [('all', 'Shob'), ('paid', 'Paid'), ('trial', 'Trial'), ('expired', 'Expired'), ('blocked', 'Blocked')])
                GestureDetector(
                  onTap: () => setState(() => tab = t.$1),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: tab == t.$1 ? _ink : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tab == t.$1 ? _ink : _line),
                    ),
                    child: Text(t.$2, style: _j(12.5, FontWeight.w700, tab == t.$1 ? Colors.white : _ink)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty) const EmptyState('Kono account nei'),
          for (final a in shown) _userCard(a),
          const SizedBox(height: 40),
        ],
      ],
    );
  }

  Widget _hs(String l, String v, {bool hot = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: _j(11, FontWeight.w600, const Color(0xB3FFFFFF))),
          Text(v, style: _j(18, FontWeight.w800, hot ? const Color(0xFFFFE08A) : Colors.white)),
        ]),
      );

  Widget _requestCard(PlanRequest r) {
    final p = planById(r.plan);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFCE3B0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(gradient: LinearGradient(colors: planColors[r.plan] ?? planColors['premium']!), borderRadius: BorderRadius.circular(9)),
            child: Text('${p?.name ?? r.plan} × ${r.months}', style: _j(12, FontWeight.w800, Colors.white)),
          ),
          const Spacer(),
          Text('₹${r.amount}', style: _j(17, FontWeight.w800, _ink)),
        ]),
        const SizedBox(height: 8),
        Text(r.name.isEmpty ? r.email : '${r.name} · ${r.email}', style: _j(13.5, FontWeight.w700, _ink)),
        if (r.note.isNotEmpty) Text('UTR / note: ${r.note}', style: _j(12, FontWeight.w600, _muted)),
        Text(_ago(r.created), style: _j(11, FontWeight.w600, _muted)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                await Accounts.reject(r);
                _load();
              },
              child: const Text('Reject', style: TextStyle(color: _red)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () async {
                try {
                  await Accounts.approve(r, _acc(r.uid));
                  HapticFeedback.heavyImpact();
                  if (mounted) toast(context, '${r.email} — ${p?.name} ${r.months} mash chalu');
                } catch (e) {
                  if (mounted) toast(context, '$e', error: true);
                }
                _load();
              },
              child: const Text('Approve ✓'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _userCard(CloudAccount a) {
    final id = a.blocked ? 'none' : !a.active ? 'none' : a.plan;
    final left = a.until == null ? null : a.until!.difference(DateTime.now()).inDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF1F2F9))),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: planColors[id] ?? planColors['premium']!)),
          alignment: Alignment.center,
          child: Text((a.shop.isNotEmpty ? a.shop : a.email).substring(0, 1).toUpperCase(), style: _j(18, FontWeight.w800, Colors.white)),
        ),
        title: Text(a.shop.isNotEmpty ? a.shop : (a.name.isNotEmpty ? a.name : a.email), maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, _ink)),
        subtitle: Text('${a.email}\n${a.products} product · ${a.sales} bill · ${a.stores} store · ${_ago(a.lastSeen)}',
            style: _j(11.5, FontWeight.w600, _muted)),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(a.status, style: _j(12, FontWeight.w800, a.blocked || !a.active ? _red : (planColors[a.plan] ?? planColors['premium']!).last)),
          if (left != null && a.active) Text('$left din', style: _j(11, FontWeight.w700, left <= 5 ? _amber : _muted)),
        ]),
        onTap: () => _edit(a),
      ),
    );
  }

  Future<void> _edit(CloudAccount a) async {
    String plan = a.plan == 'none' ? 'basic' : a.plan;
    int months = 1;
    final note = TextEditingController(text: a.note);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text(a.shop.isNotEmpty ? a.shop : a.email, style: _j(18, FontWeight.w800, _ink)),
              Text('${a.name.isEmpty ? '' : '${a.name} · '}${a.email}', style: _j(12.5, FontWeight.w600, _muted)),
              const SizedBox(height: 4),
              Text('Ekhon: ${a.status} · shesh ${_d(a.until)} · join ${_d(a.created)}', style: _j(12, FontWeight.w700, _ink)),
              if (a.pending != null) Text('Request: ${a.pending}', style: _j(12, FontWeight.w800, _amber)),
              const SizedBox(height: 14),
              Text('Plan', style: _j(12.5, FontWeight.w700, _muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in [...plans.map((p) => (p.id, '${p.name} ₹${p.price}')), ('trial', 'Trial')])
                  ChoiceChip(label: Text(p.$2), selected: plan == p.$1, onSelected: (_) => set(() => plan = p.$1)),
              ]),
              const SizedBox(height: 10),
              Text('Koto din', style: _j(12.5, FontWeight.w700, _muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final m in const [1, 3, 6, 12, 24]) ChoiceChip(label: Text(plan == 'trial' ? '${m * 7} din' : '$m mash'), selected: months == m, onSelected: (_) => set(() => months = m)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Admin note (shudhu apni dekhben)')),
              const SizedBox(height: 14),
              Row(children: [
                if (a.phone.isNotEmpty)
                  IconButton.filledTonal(onPressed: () => Contact.call(a.phone), icon: const Icon(Icons.call_rounded)),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await Accounts.setBlocked(a.uid, !a.blocked);
                      _load();
                    },
                    child: Text(a.blocked ? 'Unblock' : 'Block', style: TextStyle(color: a.blocked ? _green : _red)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _purple),
                    onPressed: () async {
                      Navigator.pop(c);
                      try {
                        final start = a.active && a.plan == plan && a.until != null ? a.until! : DateTime.now();
                        final until = plan == 'trial' ? DateTime.now().add(Duration(days: 7 * months)) : addMonths(start, months);
                        await Accounts.setPlan(a.uid, plan, until);
                        if (note.text != a.note) await Accounts.setNote(a.uid, note.text);
                        if (mounted) toast(context, 'Plan set: ${planById(plan)?.name ?? 'Trial'} · ${_d(until)} porjonto');
                      } catch (e) {
                        if (mounted) toast(context, '$e', error: true);
                      }
                      _load();
                    },
                    child: const Text('Plan set korun'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _setupHelp(String e) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Admin access nei', style: _j(16, FontWeight.w800, _red)),
          const SizedBox(height: 6),
          Text('$e\n\nFirebase → Firestore → Rules-e Hisab AI-er rules paste korun, ADMIN_EMAIL-er jaygay apnar admin email din, Publish korun.',
              style: _j(12.5, FontWeight.w600, _ink)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: firestoreRules));
              if (mounted) toast(context, 'Rules copy hoyeche — Firebase-e paste korun');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Rules copy korun'),
          ),
        ]),
      );
}

