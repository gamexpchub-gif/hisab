import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud.dart';
import '../core/ai_command.dart';
import '../core/books.dart';
import '../core/brain.dart';
import '../core/drafts.dart';
import '../core/money.dart';
import '../ui/voice.dart';
import '../ui/widgets.dart';
import 'products.dart' show ProductThumb;
import 'sale_pos.dart';
import 'sale_view.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _brand = Color(0xFF4318D2);
const _green = Color(0xFF0BA360);
const _red = Color(0xFFE0245E);
const _line = Color(0xFFECEEF6);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.3);

BoxDecoration _card({Color? border}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: border ?? const Color(0xFFF0F1F8)),
      boxShadow: const [BoxShadow(color: Color(0x141B2163), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -6)],
    );

/// One message in the conversation.
class _Msg {
  final String text;
  final bool mine;
  final Widget? card; // the assistant's answer
  final DateTime at = DateTime.now();
  _Msg(this.text, {this.mine = false, this.card});
}

/// Hisab AI assistant: one sentence (typed or spoken) makes a bill and the
/// customer, records money received, adds a customer — or answers a question.
class AiAssistant extends StatefulWidget {
  const AiAssistant({super.key});
  @override
  State<AiAssistant> createState() => _AiAssistantState();
}

class _AiAssistantState extends State<AiAssistant> {
  final input = TextEditingController();
  final focus = FocusNode();
  final msgs = <_Msg>[];
  bool thinking = false;

  static const _examples = [
    (Icons.receipt_long_rounded, 'Karim 9830012345 ke Vivo T3 ekta 18 hajar cash'),
    (Icons.payments_rounded, 'Rahim 5000 joma'),
    (Icons.person_add_alt_1_rounded, 'New customer Bablu 9830077777'),
    (Icons.today_rounded, 'Aj koto bikri?'),
    (Icons.trending_up_rounded, 'Gato mash-e Vivo-te koto labh?'),
    (Icons.sell_rounded, 'Dokan vara 8000 khoroch'),
    (Icons.inventory_rounded, 'Kon product kom ache?'),
    (Icons.account_balance_wallet_rounded, 'Who owes me the most?'),
  ];

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? said]) async {
    final text = (said ?? input.text).trim();
    if (text.isEmpty || thinking) return;
    HapticFeedback.selectionClick();
    input.clear();
    setState(() {
      msgs.insert(0, _Msg(text, mine: true)); // newest exchange first, question above its answer
      thinking = true;
    });
    Widget card;
    String reply;
    try {
      // 1 · Claude on your server: any language, any wording
      (String, List<Object>)? cloud;
      String? cloudError;
      try {
        cloud = await CloudAi.ask(text, [for (final m in msgs.skip(1).take(6)) (m.mine, m.text)]);
      } catch (e) {
        cloudError = '$e';
      }
      if (cloud != null) {
        final (said, actions) = cloud;
        reply = said.isEmpty ? 'Done' : said;
        final cards = <Widget>[];
        for (final a in actions) {
          cards.add(await _cardFor(a));
        }
        card = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (said.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: _AnswerCard(Answer(said), via: 'Claude AI')),
          for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
          if (said.isEmpty && cards.isEmpty) _AnswerCard(const Answer('I could not find what to do — try naming the product or customer'), via: 'Claude AI'),
        ]);
      } else {
        // 2 · the phone's own engine (offline)
        final products = await Books.query('SELECT p.*, c.name AS category FROM products p LEFT JOIN categories c ON c.id = p.category_id');
        final customers = await Books.query('SELECT * FROM customers');
        final cmd = AiCommands.parse(text, products, customers);
        reply = switch (cmd) { BillCommand() => 'Bill ready — check and save', null => '', _ => 'Confirm' };
        card = await _cardFor(cmd ?? AskBooks(text), offlineNote: cloudError);
      }
    } catch (e) {
      reply = 'Sorry, something went wrong';
      card = _AnswerCard(Answer('Sorry — $e'));
    }
    if (!mounted) return;
    setState(() {
      msgs.insert(1, _Msg(reply, card: card));
      thinking = false;
    });
  }

  /// The card for one command (bill, payment, customer, expense, question).
  Future<Widget> _cardFor(Object cmd, {String? offlineNote}) async {
    switch (cmd) {
      case BillCommand c:
        return _BillCard(cmd: c, key: UniqueKey());
      case ReceiptCommand r:
        return _ReceiptCard(cmd: r, key: UniqueKey());
      case ExpenseCommand x:
        return _ExpenseCard(cmd: x, key: UniqueKey());
      case CustomerCommand c:
        return _CustomerCard(cmd: c, key: UniqueKey());
      case AskBooks q:
        final a = await Brain.ask(q.question);
        await Brain.remember(q.question);
        return _AnswerCard(a, onAsk: _send, via: offlineNote == null ? null : 'Offline AI');
    }
    return _AnswerCard(const Answer('…'));
  }

  Future<void> _voice() async {
    final t = await VoiceSheet.listen(context, title: 'Tell Hisab AI', hint: 'e.g. Karim 98300… ke Vivo T3 ekta 18 hajar cash');
    if (t != null) await _send(t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ------------------------------------------------ the prompt
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFF12164A), Color(0xFF3B1CC8), Color(0xFF7B3FF2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: const [BoxShadow(color: Color(0x664318D2), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -12)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFFFE08A), Color(0xFFFFB84D)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFFD27A).withAlpha(0x88), blurRadius: 14)],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF3B1CC8), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hisab AI', style: _j(17, FontWeight.w800, Colors.white)),
                Text('Bills, customers, payments — or any question', style: _j(11.5, FontWeight.w600, const Color(0xCCFFFFFF))),
              ]),
            ),
            const _AiMode(),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: _j(14.5, FontWeight.w700, Colors.white),
                  cursorColor: const Color(0xFFFFE08A),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Type a bill, a payment or a question…',
                    hintStyle: _j(13, FontWeight.w500, Colors.white54),
                  ),
                ),
              ),
              _round(Icons.mic_rounded, _voice, const [Color(0xFFFF6B8B), Color(0xFFE0245E)]),
              const SizedBox(width: 6),
              _round(thinking ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded, thinking ? null : () => _send(),
                  const [Color(0xFFFFFFFF), Color(0xFFEDE7FF)], dark: true),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (msgs.isEmpty) ...[
        _Briefing(onAsk: _send),
        Text('  Try', style: _j(12.5, FontWeight.w800, _muted)),
        const SizedBox(height: 6),
        for (final (icon, e) in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _send(e),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: const Color(0xFFEFEAFF), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, size: 18, color: _brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e, style: _j(13, FontWeight.w700, _ink))),
                    const Icon(Icons.north_east_rounded, size: 16, color: _muted),
                  ]),
                ),
              ),
            ),
          ),
      ],
      for (var i = 0; i < msgs.length; i++) ...[
        if (i > 0 && msgs[i].mine) const Padding(padding: EdgeInsets.only(top: 14), child: Divider(height: 1, color: _line)),
        msgs[i].mine ? _mine(msgs[i]) : _answer(msgs[i]),
        if (i == 0 && thinking) const _Typing(),
      ],
      const SizedBox(height: 30),
    ]);
  }

  Widget _round(IconData i, VoidCallback? onTap, List<Color> colors, {bool dark = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: colors)),
          child: Icon(i, color: dark ? _brand : Colors.white, size: 21),
        ),
      );

  Widget _mine(_Msg m) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)),
          ),
          child: Text(m.text, style: _j(13.5, FontWeight.w700, Colors.white)),
        ),
      );

  Widget _answer(_Msg m) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF7B3FF2), Color(0xFF12164A)])),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFE08A), size: 16),
          ),
          Expanded(child: m.card ?? _AnswerCard(Answer(m.text))),
        ]),
      );
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, left: 38),
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) => Row(children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.only(right: 5),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _brand.withAlpha((80 + 175 * (((c.value * 3 - i) % 3) < 1 ? 1 : 0)).toInt()),
                ),
              ),
            Text('  Hisab AI is working…', style: _j(12, FontWeight.w600, _muted)),
          ]),
        ),
      );
}

// =============================================================================
// Answer to a question
// =============================================================================
class _AnswerCard extends StatelessWidget {
  final Answer a;
  final void Function(String)? onAsk;
  final String? via; // "Claude AI" / "Offline AI"
  const _AnswerCard(this.a, {this.onAsk, this.via});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (via != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(via == 'Claude AI' ? Icons.cloud_done_rounded : Icons.phone_android_rounded, size: 13, color: _muted),
                const SizedBox(width: 4),
                Text(via!, style: _j(10.5, FontWeight.w800, _muted)),
              ]),
            ),
          Text(a.text, style: _j(15, FontWeight.w800, _ink)),
          if (a.detail != null) ...[const SizedBox(height: 4), Text(a.detail!, style: _j(12, FontWeight.w600, _muted))],
          if (a.rows.isNotEmpty) ...[
            const Divider(height: 18),
            for (final (l, v) in a.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12.5, FontWeight.w600, _ink))),
                  Text(v, style: _j(12.5, FontWeight.w800, _ink)),
                ]),
              ),
          ],
          if (a.next.isNotEmpty && onAsk != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in a.next)
                ActionChip(
                  avatar: const Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: _brand),
                  label: Text(n, style: _j(11.5, FontWeight.w700, _brand)),
                  backgroundColor: const Color(0xFFF2EEFF),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onPressed: () => onAsk!(n),
                ),
            ]),
          ],
        ]),
      );
}

/// Today at a glance — tap a tile to ask about it.
class _Briefing extends StatelessWidget {
  final void Function(String) onAsk;
  const _Briefing({required this.onAsk});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Brief>>(
      future: Brain.briefing(),
      builder: (context, s) {
        final items = s.data ?? const <Brief>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final h = DateTime.now().hour;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('  ${h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'} · today at a glance', style: _j(12.5, FontWeight.w800, _muted)),
            const SizedBox(height: 6),
            SizedBox(
              height: 86,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final b in items)
                  GestureDetector(
                    onTap: () => onAsk(b.ask),
                    child: Container(
                      width: 148,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: _card(
                          border: switch (b.tone) {
                        'good' => const Color(0xFFCDEFE0),
                        'bad' => const Color(0xFFF8CCD8),
                        'warn' => const Color(0xFFFFE2BF),
                        _ => null,
                      }),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.label, style: _j(11, FontWeight.w700, _muted)),
                        const Spacer(),
                        Text(b.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _j(15, FontWeight.w800, switch (b.tone) {
                              'good' => _green,
                              'bad' => _red,
                              'warn' => const Color(0xFFF97316),
                              _ => _ink,
                            })),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// =============================================================================
// Expense
// =============================================================================
class _ExpenseCard extends StatefulWidget {
  final ExpenseCommand cmd;
  const _ExpenseCard({super.key, required this.cmd});
  @override
  State<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends State<_ExpenseCard> {
  late String pay = widget.cmd.pay ?? 'cash';
  bool done = false, saving = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cmd;
    if (done) return _AnswerCard(Answer('✓ ${Money.rs(c.amount)} expense saved · ${c.head}'));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(border: const Color(0xFFF8CCD8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.sell_rounded, color: _red),
          const SizedBox(width: 8),
          Expanded(child: Text('Expense · ${c.head}', style: _j(15, FontWeight.w800, _ink))),
          Text(Money.rs(c.amount), style: _j(18, FontWeight.w800, _red)),
        ]),
        if (c.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.note, style: _j(12, FontWeight.w600, _muted))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final (k, l) in const [('cash', 'Cash'), ('upi', 'UPI'), ('card', 'Card')])
            ChoiceChip(label: Text(l), selected: pay == k, onSelected: (_) => setState(() => pay = k)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: _red),
          onPressed: saving
              ? null
              : () async {
                  setState(() => saving = true);
                  try {
                    await AiActions.saveExpense(c, pay: pay);
                    HapticFeedback.mediumImpact();
                    if (mounted) setState(() => done = true);
                  } catch (e) {
                    if (mounted) {
                      setState(() => saving = false);
                      toast(context, '$e', error: true);
                    }
                  }
                },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Save expense'),
        ),
      ]),
    );
  }
}

// =============================================================================
// Bill
// =============================================================================
class _BillCard extends StatefulWidget {
  final BillCommand cmd;
  const _BillCard({super.key, required this.cmd});
  @override
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  late final lines = widget.cmd.lines;
  late String pay = widget.cmd.pay ?? 'cash';
  late final name = TextEditingController(text: widget.cmd.customer?['name'] as String? ?? widget.cmd.newName ?? '');
  late final phone = TextEditingController(text: widget.cmd.customer?['phone'] as String? ?? widget.cmd.newPhone ?? '');
  late final advance = TextEditingController(text: widget.cmd.paidNow == null ? '' : Money.edit(widget.cmd.paidNow!));
  bool saving = false;
  (int, String, int, int)? saved;

  bool get existing => widget.cmd.customer != null;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    advance.dispose();
    super.dispose();
  }

  BillCommand _cmd() => BillCommand(lines,
      customer: widget.cmd.customer,
      newName: existing ? null : name.text.trim(),
      newPhone: existing ? null : phone.text.replaceAll(RegExp(r'\D'), ''),
      pay: pay);

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final adv = Money.tryParse(advance.text);
      final r = await AiActions.saveBill(_cmd(), pay: pay, paidNow: pay == 'due' ? (adv ?? 0) : null);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => saved = r);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, '$e', error: true);
      }
    }
  }

  /// Opens the full billing screen with this bill filled in.
  Future<void> _edit() async {
    try {
      int? cid = existing ? asInt(widget.cmd.customer!['id']) : null;
      if (cid == null && (name.text.trim().isNotEmpty || phone.text.trim().isNotEmpty)) {
        cid = await AiActions.customer(name.text, phone.text.replaceAll(RegExp(r'\D'), ''));
      }
      await Drafts.save('sale', {
        'customer': cid,
        'payMode': pay == 'due' ? 'due' : 'full',
        'account': await AiActions.account(pay == 'due' ? 'cash' : pay),
        'lines': [
          for (final l in lines) {'p': asInt(l.product['id']), 'qty': l.qty, 'rate': AiActions.rate(l), 'serial': '', 'opp': ''},
        ],
      });
      if (mounted) open(context, const SaleForm());
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _editPrice(CmdLine l) async {
    final c = TextEditingController(text: Money.edit(l.rate ?? AiActions.listPrice(l.product)));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Price · ${l.product['name']}'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    final p = Money.tryParse(v);
    if (p != null && p > 0) setState(() => l.rate = p);
  }

  @override
  Widget build(BuildContext context) {
    final total = AiActions.total(lines);
    if (saved != null) return _done(saved!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(border: const Color(0xFFE4DCFF)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.receipt_long_rounded, color: _brand, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text('New bill', style: _j(15.5, FontWeight.w800, _ink))),
          Text(Money.rs(total), style: _j(18, FontWeight.w800, _brand)),
        ]),
        const SizedBox(height: 10),
        // customer
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF7F5FF), borderRadius: BorderRadius.circular(16)),
          child: existing
              ? Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _brand,
                    child: Text('${widget.cmd.customer!['name']}'.isEmpty ? '?' : '${widget.cmd.customer!['name']}'[0].toUpperCase(),
                        style: _j(15, FontWeight.w800, Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${widget.cmd.customer!['name']}', style: _j(14, FontWeight.w800, _ink)),
                      Text('${widget.cmd.customer!['phone'] ?? ''}', style: _j(11.5, FontWeight.w600, _muted)),
                    ]),
                  ),
                  _pill('Existing', _green),
                ])
              : Column(children: [
                  Row(children: [
                    const Icon(Icons.person_add_alt_1_rounded, color: _brand, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(name.text.isEmpty && phone.text.isEmpty ? 'Walk-in customer' : 'New customer — will be saved',
                            style: _j(12.5, FontWeight.w800, _brand))),
                    if (name.text.isNotEmpty || phone.text.isNotEmpty) _pill('New', _brand),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _input(name, 'Name', onChanged: () => setState(() {}))),
                    const SizedBox(width: 8),
                    Expanded(child: _input(phone, 'Mobile', number: true, onChanged: () => setState(() {}))),
                  ]),
                ]),
        ),
        const SizedBox(height: 10),
        // items
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              ProductThumb(l.product, width: 40, height: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l.product['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                  GestureDetector(
                    onTap: () => _editPrice(l),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${Money.rs(l.rate ?? AiActions.listPrice(l.product))} each', style: _j(11.5, FontWeight.w700, _brand)),
                      const SizedBox(width: 3),
                      const Icon(Icons.edit_rounded, size: 12, color: _brand),
                      if (asInt(l.product['stock']) < l.qty) Text('  · only ${l.product['stock']} in stock', style: _j(11, FontWeight.w700, _red)),
                    ]),
                  ),
                ]),
              ),
              _qty(l),
            ]),
          ),
        if (widget.cmd.unknown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Not found: ${widget.cmd.unknown.join(', ')} — add it in billing', style: _j(11.5, FontWeight.w700, _red)),
          ),
        const Divider(height: 18),
        // payment
        Row(children: [
          for (final (k, label, icon) in const [
            ('cash', 'Cash', Icons.payments_rounded),
            ('upi', 'UPI', Icons.qr_code_2_rounded),
            ('card', 'Card', Icons.credit_card_rounded),
            ('due', 'Credit', Icons.schedule_rounded),
          ])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => pay = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: pay == k ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]) : null,
                    color: pay == k ? null : const Color(0xFFF4F5FB),
                  ),
                  child: Column(children: [
                    Icon(icon, size: 18, color: pay == k ? Colors.white : _muted),
                    Text(label, style: _j(11, FontWeight.w800, pay == k ? Colors.white : _muted)),
                  ]),
                ),
              ),
            ),
        ]),
        if (pay == 'due') ...[
          const SizedBox(height: 8),
          _input(advance, 'Advance paid now (optional)', number: true, prefix: '₹ ', onChanged: () => setState(() {})),
          const SizedBox(height: 4),
          Text('On credit: ${Money.rs(total - (Money.tryParse(advance.text) ?? 0).clamp(0, total))}', style: _j(12, FontWeight.w700, _red)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: saving ? null : _edit,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Edit'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48), backgroundColor: _green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: saving || lines.isEmpty ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
              label: Text(saving ? 'Saving…' : 'Save bill'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _qty(CmdLine l) => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: () => setState(() {
              if (l.qty > 1) {
                l.qty--;
              } else {
                lines.remove(l);
              }
            }),
            child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.remove_rounded, size: 16)),
          ),
          Text('${l.qty}', style: _j(13.5, FontWeight.w800, _ink)),
          InkWell(
            onTap: () => setState(() => l.qty++),
            child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.add_rounded, size: 16)),
          ),
        ]),
      );

  Widget _done((int, String, int, int) r) {
    final (id, number, total, paid) = r;
    final due = total - paid;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF0BA360), Color(0xFF0E7490)]),
        boxShadow: const [BoxShadow(color: Color(0x550BA360), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('Bill $number saved', style: _j(16, FontWeight.w800, Colors.white))),
        ]),
        const SizedBox(height: 6),
        Text('${Money.rs(total)} · ${due > 0 ? 'paid ${Money.rs(paid)}, due ${Money.rs(due)}' : 'paid in full'}'
            '${name.text.isNotEmpty ? ' · ${name.text}' : ''}',
            style: _j(12.5, FontWeight.w600, const Color(0xE6FFFFFF))),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B7A55), minimumSize: const Size.fromHeight(44)),
          onPressed: () => open(context, SaleView(id: id)),
          icon: const Icon(Icons.receipt_rounded),
          label: const Text('Open bill · print · WhatsApp'),
        ),
      ]),
    );
  }
}

Widget _pill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(0x1F), borderRadius: BorderRadius.circular(10)),
      child: Text(t, style: _j(10.5, FontWeight.w800, c)),
    );

Widget _input(TextEditingController c, String label, {bool number = false, String? prefix, VoidCallback? onChanged}) => TextField(
      controller: c,
      keyboardType: number ? TextInputType.phone : TextInputType.name,
      textCapitalization: TextCapitalization.words,
      onChanged: onChanged == null ? null : (_) => onChanged(),
      style: _j(13.5, FontWeight.w700, _ink),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixText: prefix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
      ),
    );

// =============================================================================
// Money received
// =============================================================================
class _ReceiptCard extends StatefulWidget {
  final ReceiptCommand cmd;
  const _ReceiptCard({super.key, required this.cmd});
  @override
  State<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends State<_ReceiptCard> {
  late String pay = widget.cmd.pay ?? 'cash';
  int? due;
  bool done = false, saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.cmd.customer;
    if (c != null) {
      Books.partyBalances('customer').then((b) {
        if (mounted) setState(() => due = b[asInt(c['id'])] ?? 0);
      });
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await Books.createPayment(
          kind: 'receipt', partyId: asInt(widget.cmd.customer!['id']), amount: widget.cmd.amount, accountId: (await AiActions.account(pay))!);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => done = true);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cmd.customer;
    if (c == null) {
      return _AnswerCard(Answer('No customer "${widget.cmd.name ?? ''}" found', detail: 'Say the full name or the mobile number, e.g. "Rahim Sheikh 5000 joma"'));
    }
    if (done) {
      return _AnswerCard(Answer('✓ ${Money.rs(widget.cmd.amount)} received from ${c['name']}',
          detail: due == null ? null : 'Still due: ${Money.rs((due! - widget.cmd.amount).clamp(0, 1 << 40))}'));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(border: const Color(0xFFCDEFE0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.payments_rounded, color: _green),
          const SizedBox(width: 8),
          Expanded(child: Text('Money received', style: _j(15, FontWeight.w800, _ink))),
          Text(Money.rs(widget.cmd.amount), style: _j(18, FontWeight.w800, _green)),
        ]),
        const SizedBox(height: 6),
        Text('From ${c['name']}${due == null ? '' : ' · owes ${Money.rs(due!)}'}', style: _j(12.5, FontWeight.w700, _muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final (k, l) in const [('cash', 'Cash'), ('upi', 'UPI'), ('card', 'Card')])
            ChoiceChip(label: Text(l), selected: pay == k, onSelected: (_) => setState(() => pay = k)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: _green),
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Record payment'),
        ),
      ]),
    );
  }
}

// =============================================================================
// New customer
// =============================================================================
class _CustomerCard extends StatefulWidget {
  final CustomerCommand cmd;
  const _CustomerCard({super.key, required this.cmd});
  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cmd;
    if (c.existing != null) {
      return _AnswerCard(Answer('Customer already added — ${c.existing!['name']} · ${c.existing!['phone'] ?? ''}'));
    }
    if (done) return _AnswerCard(Answer('✓ ${c.name} saved · ${c.phone}'));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(border: const Color(0xFFE4DCFF)),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: _brand, child: Text(c.name[0], style: _j(18, FontWeight.w800, Colors.white))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: _j(15, FontWeight.w800, _ink)),
            Text(c.phone, style: _j(12, FontWeight.w600, _muted)),
          ]),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await Books.saveParty('customer', {'name': c.name, 'phone': c.phone});
              HapticFeedback.mediumImpact();
              if (mounted) setState(() => done = true);
            } catch (e) {
              if (context.mounted) toast(context, '$e', error: true);
            }
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

/// "Claude AI" / "Offline AI" chip: tap to turn the cloud AI on or off.
class _AiMode extends StatefulWidget {
  const _AiMode();
  @override
  State<_AiMode> createState() => _AiModeState();
}

class _AiModeState extends State<_AiMode> {
  bool on = true, ready = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await CloudAi.enabled();
    final up = await Vps.available();
    if (mounted) {
      setState(() {
        on = enabled;
        ready = up && Vps.aiReady;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = on && ready;
    return GestureDetector(
      onTap: () async {
        await Books.setSetting('ai_cloud', on ? '0' : '1');
        await _check();
        if (context.mounted) {
          toast(context, !on ? 'Offline AI — works without internet' : ready ? 'Claude AI on' : 'Claude AI is not set up on your server yet');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: live ? const Color(0xFFFFE08A) : const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(live ? Icons.cloud_done_rounded : Icons.phone_android_rounded, size: 14, color: live ? const Color(0xFF3B1CC8) : Colors.white),
          const SizedBox(width: 4),
          Text(live ? 'Claude AI' : 'Offline', style: _j(11, FontWeight.w800, live ? const Color(0xFF3B1CC8) : Colors.white)),
        ]),
      ),
    );
  }
}
