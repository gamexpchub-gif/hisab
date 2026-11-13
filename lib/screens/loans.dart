import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarms.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/charts.dart';
import '../ui/contact.dart';
import '../ui/widgets.dart';

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _line = Color(0xFFE9EAF5);
const _purple = Color(0xFF5B2EE0);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);
const _amber = Color(0xFFE39A0F);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

const _sourceIcon = <String, IconData>{
  'bank': Icons.account_balance_rounded,
  'nbfc': Icons.business_rounded,
  'person': Icons.person_rounded,
  'family': Icons.family_restroom_rounded,
  'supplier': Icons.local_shipping_rounded,
  'investor': Icons.handshake_rounded,
  'owner': Icons.workspace_premium_rounded,
  'other': Icons.savings_rounded,
};

const _sourceColors = <String, List<Color>>{
  'bank': [Color(0xFF6AA5FF), Color(0xFF1A47C8)],
  'nbfc': [Color(0xFF818CF8), Color(0xFF4338CA)],
  'person': [Color(0xFFFFB547), Color(0xFFE38A0B)],
  'family': [Color(0xFFFF7A9A), Color(0xFFD81E4A)],
  'supplier': [Color(0xFFFFA24A), Color(0xFFF06A1A)],
  'investor': [Color(0xFF3EE08F), Color(0xFF0E9F5E)],
  'owner': [Color(0xFF8B5CF6), Color(0xFF5B2EE0)],
  'other': [Color(0xFF94A3B8), Color(0xFF475569)],
};

String _pct(int bp) => '${(bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 2)}%';

Widget _orb(String source, {double size = 46}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(colors: _sourceColors[source] ?? _sourceColors['other']!),
      ),
      child: Icon(_sourceIcon[source] ?? Icons.savings_rounded, color: Colors.white, size: size * .5),
    );

Future<void> _scheduleLoanAlarm(Rec l) async {
  final next = l['next_due'] as String?;
  if (next == null) return;
  await Alarms.scheduleDue(
    dueId: 700000 + asInt(l['id']),
    dueDate: DateTime.parse(next),
    title: 'Loan EMI ${Money.rs(asInt(l['next_emi']))} — ${l['lender']}',
    body: '${l['number']} · due ${prettyDate(next)} · GameX Hisab',
  );
}

// =============================================================================
/// Loans & investments: every rupee brought into the business, what is owed,
/// the EMIs and the interest cost.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});
  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  String tab = 'active'; // active | loan | investment | closed

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      load: () => Loans.list(),
      builder: (context, all) {
        final loans = all.where((l) => l['kind'] == 'loan').toList();
        final inv = all.where((l) => l['kind'] == 'investment').toList();
        final owed = loans.where((l) => l['status'] == 'active').fold<int>(0, (a, l) => a + asInt(l['outstanding']));
        final borrowed = loans.fold<int>(0, (a, l) => a + asInt(l['principal']));
        final repaid = loans.fold<int>(0, (a, l) => a + asInt(l['paid_principal']));
        final interest = loans.fold<int>(0, (a, l) => a + asInt(l['paid_interest']));
        final capital = inv.fold<int>(0, (a, l) => a + asInt(l['outstanding']));
        final monthly = loans.where((l) => l['status'] == 'active').fold<int>(0, (a, l) => a + asInt(l['emi']));
        final next = loans.where((l) => l['next_due'] != null).toList()..sort((a, b) => '${a['next_due']}'.compareTo('${b['next_due']}'));
        final bySource = <String, int>{};
        for (final l in all.where((l) => l['status'] == 'active')) {
          bySource[Loans.sources[l['source']] ?? 'Other'] = (bySource[Loans.sources[l['source']] ?? 'Other'] ?? 0) + asInt(l['outstanding']);
        }
        final shown = switch (tab) {
          'loan' => loans,
          'investment' => inv,
          'closed' => all.where((l) => l['status'] != 'active').toList(),
          _ => all.where((l) => l['status'] == 'active').toList(),
        };
        final today = ymd(DateTime.now());
        return PageShell(
          title: 'Loans & Investment',
          subtitle: 'Business-e kotha theke taka elo, koto shodh baki',
          fab: FloatingActionButton.extended(
            backgroundColor: _purple,
            onPressed: () => open(context, const LoanForm()),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text('New loan / investment', style: _j(14, FontWeight.w800, Colors.white)),
          ),
          children: [
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F1240), Color(0xFF2A1E8F), Color(0xFF6B35EE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [BoxShadow(color: Color(0x404318D2), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -8)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Mot loan baki', style: _j(13, FontWeight.w600, const Color(0xD9FFFFFF))),
                  const Spacer(),
                  if (monthly > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
                      child: Text('EMI ${Money.compact(monthly)}/mash', style: _j(11.5, FontWeight.w800, Colors.white)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(Money.rs(owed), style: _j(32, FontWeight.w800, Colors.white)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: borrowed == 0 ? 0 : repaid / borrowed,
                    backgroundColor: const Color(0x33FFFFFF),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF3EE08F)),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${Money.compact(repaid)} shodh · ${borrowed == 0 ? 0 : (repaid * 100 / borrowed).round()}% · mot newa ${Money.compact(borrowed)}',
                    style: _j(11.5, FontWeight.w600, const Color(0xD9FFFFFF))),
                const SizedBox(height: 14),
                Row(children: [
                  _heroStat('Investment', Money.compact(capital), const Color(0xFF3EE08F)),
                  _heroStat('Sud dewa', Money.compact(interest), const Color(0xFFFFB5C2)),
                  _heroStat('Next EMI', next.isEmpty ? '—' : prettyDate('${next.first['next_due']}').substring(0, 6),
                      next.isNotEmpty && '${next.first['next_due']}'.compareTo(today) <= 0 ? const Color(0xFFFFB5C2) : Colors.white),
                ]),
              ]),
            ),
            if (bySource.length > 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F2F9))),
                child: Row(children: [
                  DonutChart(
                    parts: bySource.entries.toList(),
                    colors: const [Color(0xFF2F6BFF), Color(0xFF16A36A), Color(0xFFF08A24), Color(0xFFD81E4A), Color(0xFF8B5CF6), Color(0xFF0D9488)],
                    size: 120,
                    centerTop: Money.compact(bySource.values.fold(0, (a, b) => a + b)),
                    centerBottom: 'taka elo',
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Kotha theke', style: _j(14, FontWeight.w800, _ink)),
                      const SizedBox(height: 6),
                      for (final (i, e) in bySource.entries.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const [Color(0xFF2F6BFF), Color(0xFF16A36A), Color(0xFFF08A24), Color(0xFFD81E4A), Color(0xFF8B5CF6), Color(0xFF0D9488)][i % 6],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w600, _muted))),
                            Text(Money.compact(e.value), style: _j(12, FontWeight.w800, _ink)),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in const [('active', 'Cholche'), ('loan', 'Loan'), ('investment', 'Investment'), ('closed', 'Shodh hoye geche')])
                  GestureDetector(
                    onTap: () => setState(() => tab = t.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: tab == t.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                        color: tab == t.$1 ? null : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: tab == t.$1 ? null : Border.all(color: _line),
                      ),
                      child: Text(t.$2, style: _j(12.5, FontWeight.w700, tab == t.$1 ? Colors.white : _ink)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty)
              const EmptyState('Kono loan ba investment nei — niche button chepe jog korun')
            else
              for (final l in shown) _LoanCard(l),
            const SizedBox(height: 90),
          ],
        );
      },
    );
  }

  Widget _heroStat(String label, String v, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _j(11, FontWeight.w600, const Color(0xB3FFFFFF))),
          Text(v, style: _j(15, FontWeight.w800, c)),
        ]),
      );
}

class _LoanCard extends StatelessWidget {
  final Rec l;
  const _LoanCard(this.l);

  @override
  Widget build(BuildContext context) {
    final isLoan = l['kind'] == 'loan';
    final p = asInt(l['principal']), out = asInt(l['outstanding']);
    final done = p == 0 ? 0.0 : (p - out) / p;
    final next = l['next_due'] as String?;
    final late = next != null && next.compareTo(ymd(DateTime.now())) < 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: late ? const Color(0xFFFFC9D2) : const Color(0xFFF1F2F9)),
        boxShadow: const [BoxShadow(color: Color(0x142A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -6)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => open(context, LoanView(id: asInt(l['id']))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                _orb('${l['source']}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${l['lender']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(15, FontWeight.w800, _ink)),
                    Text(
                      [
                        isLoan ? 'Loan' : 'Investment',
                        Loans.sources[l['source']] ?? '',
                        if (isLoan && asInt(l['rate_bp']) > 0) '${_pct(asInt(l['rate_bp']))} ${l['interest_type'] == 'flat' ? 'flat' : ''}'.trim(),
                        if (isLoan && asInt(l['rate_bp']) == 0) 'bina sud',
                      ].join(' · '),
                      style: _j(11.5, FontWeight.w600, _muted),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(Money.rs(out), style: _j(16, FontWeight.w800, isLoan ? (out > 0 ? _red : _green) : _green)),
                  Text(isLoan ? (out > 0 ? 'baki' : 'shodh ✓') : 'capital', style: _j(10.5, FontWeight.w700, _muted)),
                ]),
              ]),
              if (isLoan) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: done.clamp(0, 1).toDouble(),
                    backgroundColor: const Color(0xFFEEF0F8),
                    valueColor: const AlwaysStoppedAnimation(_green),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('${(done * 100).round()}% shodh · ${l['paid_n']}/${l['months']} kisti', style: _j(11, FontWeight.w600, _muted)),
                  const Spacer(),
                  if (next != null)
                    Text('${late ? 'Late · ' : ''}EMI ${Money.compact(asInt(l['next_emi']))} · ${prettyDate(next)}',
                        style: _j(11, FontWeight.w800, late ? _red : _purple)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
class LoanForm extends StatefulWidget {
  const LoanForm({super.key});
  @override
  State<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<LoanForm> {
  String kind = 'loan', source = 'bank', type = 'reducing';
  final lender = TextEditingController(), phone = TextEditingController(), amount = TextEditingController();
  final rate = TextEditingController(text: '12'), months = TextEditingController(text: '12'), purpose = TextEditingController();
  String date = ymd(DateTime.now());
  String? firstDue;
  int? account;
  List<Rec> accounts = [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts().then((a) {
      if (mounted) setState(() {
        accounts = a;
        account = a.isEmpty ? null : asInt(a.first['id']);
      });
    });
  }

  int get p => Money.parse(amount.text);
  int get bp => ((double.tryParse(rate.text.trim()) ?? 0) * 100).round();
  int get n => int.tryParse(months.text.trim()) ?? 0;
  String get due => firstDue ?? ymd(addMonths(DateTime.parse(date), 1));

  Rec get preview => {
        'kind': 'loan',
        'principal': p,
        'rate_bp': bp,
        'interest_type': type,
        'months': n,
        'emi': 0,
        'start_date': date,
        'first_due': due,
      };

  Future<void> _save() async {
    if (account == null) return toast(context, 'Taka kon account-e elo — select korun', error: true);
    setState(() => saving = true);
    try {
      final id = await Loans.create(
        kind: kind,
        source: source,
        lender: lender.text,
        phone: phone.text,
        principal: p,
        accountId: account!,
        rateBp: kind == 'loan' ? bp : 0,
        interestType: kind == 'loan' ? (bp == 0 ? 'none' : type) : 'none',
        months: kind == 'loan' ? n : 0,
        date: date,
        firstDue: kind == 'loan' ? due : null,
        purpose: purpose.text,
      );
      final l = await Loans.get(id);
      if (l != null) await _scheduleLoanAlarm(l);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      toast(context, kind == 'loan' ? 'Loan saved · ${Money.rs(p)} account-e jog holo' : 'Investment saved');
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoanView(id: id)));
    } catch (e) {
      toast(context, '$e', error: true);
      setState(() => saving = false);
    }
  }

  Widget _chip(String l, bool on, VoidCallback tap, {IconData? icon}) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(tap);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: on ? null : Border.all(color: _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: on ? Colors.white : _muted), const SizedBox(width: 5)],
            Text(l, style: _j(12.5, FontWeight.w700, on ? Colors.white : _ink)),
          ]),
        ),
      );

  Widget _field(TextEditingController c, String label, {TextInputType? kb, String? prefix, String? suffix, ValueChanged<String>? onChanged}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: kb,
          onChanged: onChanged ?? (_) => setState(() {}),
          style: _j(15, FontWeight.w700, _ink),
          decoration: InputDecoration(
            labelText: label,
            prefixText: prefix,
            suffixText: suffix,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          ),
        ),
      );

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFBFBFE), borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _j(13.5, FontWeight.w800, _ink)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isLoan = kind == 'loan';
    final emi = isLoan && p > 0 && n > 0 ? Loans.emi(p, bp, n, bp == 0 ? 'none' : type) : 0;
    final sched = isLoan && p > 0 && n > 0 ? Loans.schedule({...preview, 'interest_type': bp == 0 ? 'none' : type}) : const <LoanRow>[];
    final totalInt = sched.fold<int>(0, (a, r) => a + r.interest);
    final sources = isLoan
        ? ['bank', 'nbfc', 'person', 'family', 'supplier', 'other']
        : ['owner', 'investor', 'family', 'other'];
    if (!sources.contains(source)) source = sources.first;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(isLoan ? 'New loan' : 'New investment', style: _j(19, FontWeight.w800, _ink)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
          child: Row(children: [
            for (final k in const [('loan', 'Loan / Udhar', Icons.request_quote_rounded), ('investment', 'Investment / Capital', Icons.savings_rounded)])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => kind = k.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: kind == k.$1 ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(k.$3, size: 18, color: kind == k.$1 ? Colors.white : _muted),
                      const SizedBox(width: 6),
                      Text(k.$2, style: _j(13, FontWeight.w800, kind == k.$1 ? Colors.white : _ink)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            isLoan
                ? 'Bank, finance ba karo kach theke udhar — fert dite hobe (sud soho ba bina sude).'
                : 'Nijer ba partner-er taka business-e lagano — eta capital, loan na.',
            style: _j(12, FontWeight.w500, _muted),
          ),
        ),
        _card(isLoan ? 'Kar kach theke' : 'Ke taka dilo', [
          Wrap(children: [
            for (final s in sources) _chip(Loans.sources[s]!, source == s, () => source = s, icon: _sourceIcon[s]),
          ]),
          const SizedBox(height: 6),
          _field(lender, isLoan ? (source == 'bank' || source == 'nbfc' ? 'Bank / finance-er naam' : 'Naam') : 'Naam (owner / partner)'),
          _field(phone, 'Phone (optional)', kb: TextInputType.phone),
        ]),
        _card('Taka', [
          _field(amount, isLoan ? 'Loan amount' : 'Investment amount', kb: const TextInputType.numberWithOptions(decimal: true), prefix: '₹ '),
          Text('Kon account-e elo', style: _j(12, FontWeight.w700, _muted)),
          const SizedBox(height: 6),
          Wrap(children: [
            for (final a in accounts) _chip('${a['name']}', account == asInt(a['id']), () => account = asInt(a['id'])),
          ]),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2015), lastDate: DateTime.now());
              if (d != null) setState(() => date = ymd(d));
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.event_rounded, size: 18, color: _purple),
                const SizedBox(width: 6),
                Text('Tarikh: ${prettyDate(date)}', style: _j(13, FontWeight.w700, _purple)),
              ]),
            ),
          ),
        ]),
        if (isLoan)
          _card('Sud ar kisti', [
            Row(children: [
              Expanded(child: _field(rate, 'Sud (bochore)', kb: const TextInputType.numberWithOptions(decimal: true), suffix: '%')),
              const SizedBox(width: 10),
              Expanded(child: _field(months, 'Koto mash', kb: TextInputType.number, suffix: 'mash')),
            ]),
            Wrap(children: [
              for (final m in const [6, 12, 18, 24, 36, 60]) _chip('$m mash', n == m, () => months.text = '$m'),
            ]),
            const SizedBox(height: 4),
            Wrap(children: [
              _chip('Reducing (bank)', type == 'reducing', () => type = 'reducing'),
              _chip('Flat', type == 'flat', () => type = 'flat'),
              _chip('Bina sud', bp == 0, () => rate.text = '0'),
            ]),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.parse(due), firstDate: DateTime.parse(date), lastDate: DateTime(2100));
                if (d != null) setState(() => firstDue = ymd(d));
              },
              child: Row(children: [
                const Icon(Icons.alarm_rounded, size: 18, color: _amber),
                const SizedBox(width: 6),
                Text('Prothom EMI: ${prettyDate(due)}', style: _j(13, FontWeight.w700, _amber)),
                const SizedBox(width: 6),
                Text('(bodlan)', style: _j(12, FontWeight.w600, _muted)),
              ]),
            ),
          ]),
        if (isLoan && emi > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFF0F1240), Color(0xFF4318D2)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calculate_rounded, color: Color(0xFFFFE08A)),
                const SizedBox(width: 8),
                Text('EMI calculator', style: _j(13, FontWeight.w700, const Color(0xD9FFFFFF))),
              ]),
              const SizedBox(height: 6),
              Text('${Money.rs(emi)} / mash', style: _j(26, FontWeight.w800, Colors.white)),
              const SizedBox(height: 10),
              Row(children: [
                _calc('Mot sud', Money.compact(totalInt), const Color(0xFFFFB5C2)),
                _calc('Mot fert', Money.compact(p + totalInt), Colors.white),
                _calc('Shesh EMI', sched.isEmpty ? '—' : prettyDate(sched.last.date).substring(3), Colors.white),
              ]),
              if (p > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Row(children: [
                    Expanded(flex: math.max(1, p ~/ 100), child: Container(height: 8, color: const Color(0xFF3EE08F))),
                    Expanded(flex: math.max(1, totalInt ~/ 100), child: Container(height: 8, color: const Color(0xFFFF7A9A))),
                  ]),
                ),
                const SizedBox(height: 4),
                Text('Sobuj = asol ${(p * 100 / (p + totalInt)).round()}% · golapi = sud ${(totalInt * 100 / (p + totalInt)).round()}%',
                    style: _j(11, FontWeight.w600, const Color(0xCCFFFFFF))),
              ],
            ]),
          ),
        _field(purpose, 'Kiser jonno (stock, dokan, machine…)'),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: SizedBox(
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))),
              onPressed: saving || p <= 0 || lender.text.trim().isEmpty ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save · ${Money.rs(p)}', style: _j(15, FontWeight.w800, Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _calc(String l, String v, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: _j(11, FontWeight.w600, const Color(0xB3FFFFFF))),
          Text(v, style: _j(14, FontWeight.w800, c)),
        ]),
      );
}

// =============================================================================
class LoanView extends StatelessWidget {
  final int id;
  const LoanView({super.key, required this.id});

  Future<(Rec?, List<Rec>)> _load() async => (await Loans.get(id), await Loans.payments(id));

  @override
  Widget build(BuildContext context) {
    return Live<(Rec?, List<Rec>)>(
      load: _load,
      builder: (context, d) {
        final (l, pays) = d;
        if (l == null) return const PageShell(title: 'Loan', children: [EmptyState('Not found')]);
        final isLoan = l['kind'] == 'loan';
        final p = asInt(l['principal']), out = asInt(l['outstanding']);
        final sched = Loans.schedule(l);
        final paidN = asInt(l['paid_n']);
        final totalInt = sched.fold<int>(0, (a, r) => a + r.interest);
        final active = l['status'] == 'active' && out > 0;
        return PageShell(
          title: '${l['lender']}',
          subtitle: '${l['number']} · ${isLoan ? 'Loan' : 'Investment'} · ${Loans.sources[l['source']] ?? ''}',
          action: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              if (v == 'call') await Contact.call(l['phone'] as String?);
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete?'),
                    content: Text('${l['lender']} — ei ${isLoan ? 'loan' : 'investment'} ar tar shob payment muche jabe.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: _red))),
                    ],
                  ),
                );
                if (ok == true) {
                  await Alarms.cancelDue(700000 + id);
                  await Loans.delete(id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              }
            },
            itemBuilder: (_) => [
              if ((l['phone'] ?? '').toString().isNotEmpty) const PopupMenuItem(value: 'call', child: Text('Call')),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _red))),
            ],
          ),
          children: [
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(colors: _sourceColors[l['source']] ?? _sourceColors['other']!),
              ),
              child: Row(children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(
                        value: p == 0 ? 0 : (p - out) / p,
                        strokeWidth: 9,
                        backgroundColor: const Color(0x40FFFFFF),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Text('${p == 0 ? 0 : ((p - out) * 100 / p).round()}%', style: _j(20, FontWeight.w800, Colors.white)),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isLoan ? 'Baki asol' : 'Capital in business', style: _j(12, FontWeight.w600, const Color(0xE6FFFFFF))),
                    Text(Money.rs(out), style: _j(26, FontWeight.w800, Colors.white)),
                    Text('Newa ${Money.rs(p)} · ${prettyDate('${l['start_date']}')}', style: _j(11.5, FontWeight.w600, const Color(0xE6FFFFFF))),
                    if (l['account'] != null) Text('Elo: ${l['account']}', style: _j(11.5, FontWeight.w600, const Color(0xE6FFFFFF))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (isLoan)
              Row(children: [
                _kpi('EMI', asInt(l['emi']) > 0 ? Money.compact(asInt(l['emi'])) : '—'),
                _kpi('Sud', asInt(l['rate_bp']) == 0 ? 'Nei' : '${_pct(asInt(l['rate_bp']))} ${l['interest_type'] == 'flat' ? 'flat' : ''}'),
                _kpi('Sud dewa', Money.compact(asInt(l['paid_interest']))),
                _kpi('Kisti', '$paidN/${l['months']}'),
              ]),
            if (isLoan && l['next_due'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFFF8EB), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFCE3B0))),
                child: Row(children: [
                  const Icon(Icons.alarm_rounded, color: _amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Porer EMI ${Money.rs(asInt(l['next_emi']))} · ${prettyDate('${l['next_due']}')}',
                        style: _j(13.5, FontWeight.w800, _ink)),
                  ),
                ]),
              ),
            ],
            if (active) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: isLoan ? _purple : _green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _PaySheet(l),
                  ),
                  icon: const Icon(Icons.payments_rounded, color: Colors.white),
                  label: Text(isLoan ? 'EMI / repayment dilam' : 'Capital ferot dilam', style: _j(14.5, FontWeight.w800, Colors.white)),
                ),
              ),
            ],
            if ((l['purpose'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Kiser jonno: ${l['purpose']}', style: _j(12.5, FontWeight.w600, _muted)),
            ],
            if (sched.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(children: [
                Text('Kisti-r talika', style: _j(15, FontWeight.w800, _ink)),
                const Spacer(),
                Text('Mot sud ${Money.compact(totalInt)}', style: _j(12, FontWeight.w700, _muted)),
              ]),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF1F2F9))),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 40,
                    columnSpacing: 16,
                    headingTextStyle: _j(11.5, FontWeight.w800, _muted),
                    dataTextStyle: _j(12.5, FontWeight.w600, _ink),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Tarikh')),
                      DataColumn(label: Text('EMI')),
                      DataColumn(label: Text('Asol')),
                      DataColumn(label: Text('Sud')),
                      DataColumn(label: Text('Baki')),
                    ],
                    rows: [
                      for (final r in sched)
                        DataRow(
                          color: WidgetStatePropertyAll(r.n <= paidN ? const Color(0xFFEFFAF4) : null),
                          cells: [
                            DataCell(Text(r.n <= paidN ? '✓' : '${r.n}', style: _j(12.5, FontWeight.w800, r.n <= paidN ? _green : _ink))),
                            DataCell(Text(prettyDate(r.date))),
                            DataCell(Text(Money.compact(r.emi))),
                            DataCell(Text(Money.compact(r.principal))),
                            DataCell(Text(Money.compact(r.interest))),
                            DataCell(Text(Money.compact(r.balance))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Payment history · ${pays.length}', style: _j(15, FontWeight.w800, _ink)),
            const SizedBox(height: 8),
            if (pays.isEmpty) Text('Ekhono kono payment nei', style: _j(12.5, FontWeight.w500, _muted)),
            for (final x in pays)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF1F2F9))),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: _green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Money.rs(asInt(x['principal']) + asInt(x['interest'])), style: _j(14, FontWeight.w800, _ink)),
                      Text(
                          '${prettyDate('${x['date']}')} · ${x['account']} · asol ${Money.compact(asInt(x['principal']))}${asInt(x['interest']) > 0 ? ' + sud ${Money.compact(asInt(x['interest']))}' : ''}',
                          style: _j(11.5, FontWeight.w600, _muted)),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: _muted),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Ei payment muchben?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: _red))),
                          ],
                        ),
                      );
                      if (ok == true) await Loans.deletePayment(asInt(x['id']));
                    },
                  ),
                ]),
              ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Widget _kpi(String l, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F2F9))),
          child: Column(children: [
            Text(l, style: _j(10.5, FontWeight.w600, _muted)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: _j(13.5, FontWeight.w800, _ink))),
          ]),
        ),
      );
}

class _PaySheet extends StatefulWidget {
  final Rec l;
  const _PaySheet(this.l);
  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final (int, int) s = Loans.suggest(widget.l);
  late final principal = TextEditingController(text: Money.edit(s.$1));
  late final interest = TextEditingController(text: s.$2 == 0 ? '' : Money.edit(s.$2));
  int? account = asInt(widget.l['account_id']);
  List<Rec> accounts = [];
  String date = ymd(DateTime.now());
  bool saving = false;

  @override
  void initState() {
    super.initState();
    Books.moneyAccounts().then((a) {
      if (mounted) setState(() => accounts = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoan = widget.l['kind'] == 'loan';
    final total = Money.parse(principal.text) + Money.parse(interest.text);
    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 18),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Text(isLoan ? 'EMI / repayment' : 'Capital ferot', style: _j(18, FontWeight.w800, _ink)),
        Text('${widget.l['lender']} · baki ${Money.rs(asInt(widget.l['outstanding']))}', style: _j(12, FontWeight.w600, _muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: principal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Asol (principal)', prefixText: '₹ '),
            ),
          ),
          if (isLoan) ...[
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: interest,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Sud (interest)', prefixText: '₹ '),
              ),
            ),
          ],
        ]),
        if (isLoan && s.$2 > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('AI split: asol ${Money.rs(s.$1)} + sud ${Money.rs(s.$2)} (kisti ${asInt(widget.l['paid_n']) + 1})',
                style: _j(11.5, FontWeight.w600, _purple)),
          ),
        const SizedBox(height: 12),
        Text('Kon account theke dilen', style: _j(12, FontWeight.w700, _muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in accounts)
            ChoiceChip(
              label: Text('${a['name']}'),
              selected: account == asInt(a['id']),
              onSelected: (_) => setState(() => account = asInt(a['id'])),
            ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _purple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
            onPressed: saving || total <= 0 || account == null
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await Loans.pay(asInt(widget.l['id']),
                          principal: Money.parse(principal.text), interest: Money.parse(interest.text), accountId: account!, date: date);
                      final l = await Loans.get(asInt(widget.l['id']));
                      if (l != null && l['next_due'] != null) {
                        await _scheduleLoanAlarm(l);
                      } else {
                        await Alarms.cancelDue(700000 + asInt(widget.l['id']));
                      }
                      if (!context.mounted) return;
                      HapticFeedback.heavyImpact();
                      Navigator.of(context).pop();
                      toast(context, 'Payment saved · ${Money.rs(total)}');
                    } catch (e) {
                      setState(() => saving = false);
                      if (context.mounted) toast(context, '$e', error: true);
                    }
                  },
            child: Text('Save · ${Money.rs(total)}', style: _j(15, FontWeight.w800, Colors.white)),
          ),
        ),
      ]),
    );
  }
}
