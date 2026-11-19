import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/books.dart';
import '../core/staff.dart';
import '../ui/widgets.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _purple = Color(0xFF4318D2);
const _red = Color(0xFFE0245E);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

BoxDecoration _card() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x0F1B2163), blurRadius: 16, offset: Offset(0, 6))],
    );

Future<String?> _askPin(BuildContext context, String title, {String sub = '4–6 digits'}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(hintText: sub),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// Owner: staff list, roles, permissions, owner PIN, staff mode.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  bool ownerPin = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await Staff.load();
    ownerPin = await Staff.ownerPinSet();
    if (mounted) setState(() {});
  }

  Future<void> _setOwnerPin() async {
    final p = await _askPin(context, ownerPin ? 'New owner PIN' : 'Set the owner PIN');
    if (p == null || !mounted) return;
    try {
      await Staff.setOwnerPin(p);
      if (mounted) toast(context, 'Owner PIN saved');
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _edit([StaffMember? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final pin = TextEditingController();
    var role = s?.role ?? 'sales';
    var perms = {...?s?.perms};
    var active = s?.active ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(s == null ? 'Add staff' : 'Edit ${s.name}', style: _j(18, FontWeight.w800, _ink)),
              const SizedBox(height: 10),
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: s == null ? 'PIN (4–6 digits)' : 'New PIN (leave empty to keep)'),
              ),
              Text('Role', style: _j(13, FontWeight.w800, _ink)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final r in Staff.roles.entries)
                  ChoiceChip(
                    label: Text(r.value.$1),
                    selected: role == r.key,
                    onSelected: (_) => set(() {
                      role = r.key;
                      if (r.key != 'custom') perms = {...r.value.$2};
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              for (final p in Staff.perms.entries)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: perms.contains(p.key),
                  title: Text(p.value.$1, style: _j(13.5, FontWeight.w700, _ink)),
                  subtitle: Text(p.value.$2, style: _j(11.5, FontWeight.w500, _muted)),
                  onChanged: (v) => set(() {
                    v ? perms.add(p.key) : perms.remove(p.key);
                    role = 'custom';
                  }),
                ),
              if (s != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: const Text('Active'),
                  onChanged: (v) => set(() => active = v),
                ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: _purple),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (s == null) {
        await Staff.add(name.text, pin.text.trim(), role, perms);
      } else {
        await Staff.update(s, name: name.text, role: role, perms: perms, pin: pin.text.trim(), active: active);
      }
      if (mounted) toast(context, 'Saved');
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Staff.list;
    return PageShell(
      title: 'Staff & permissions',
      subtitle: 'Each person with a PIN · what they may do · who did what',
      fab: FloatingActionButton.extended(
        backgroundColor: _purple,
        onPressed: ownerPin ? () => _edit() : _setOwnerPin,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: Text(ownerPin ? 'Add staff' : 'Set owner PIN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.badge_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(Staff.modeOn ? 'Staff mode is ON' : 'Staff mode is off',
                    style: _j(17, FontWeight.w800, Colors.white)),
              ),
              Switch(
                value: Staff.modeOn,
                onChanged: (v) async {
                  try {
                    await Staff.setMode(v);
                    if (v) Staff.current.value = null; // the owner turned it on
                    await _refresh();
                  } catch (e) {
                    if (context.mounted) toast(context, '$e', error: true);
                  }
                },
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                Staff.modeOn
                    ? 'The app asks "who is working?" when it opens. Switch user from the menu.'
                    : 'Turn on to let salesmen use the app with their own PIN and limited rights.',
                style: _j(12, FontWeight.w500, const Color(0xD9FFFFFF))),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: _card(),
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings_rounded, color: _purple),
            title: Text(ownerPin ? 'Owner PIN is set' : 'Set the owner PIN first', style: _j(14, FontWeight.w800, _ink)),
            subtitle: Text('The owner can do everything and manages staff', style: _j(11.5, FontWeight.w500, _muted)),
            trailing: TextButton(onPressed: _setOwnerPin, child: Text(ownerPin ? 'Change' : 'Set')),
          ),
        ),
        for (final s in list)
          Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: _card(),
            child: ListTile(
              onTap: () => _edit(s),
              leading: CircleAvatar(
                backgroundColor: s.active ? const Color(0xFFEFEAFF) : const Color(0xFFF1F5F9),
                child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(), style: _j(16, FontWeight.w800, s.active ? _purple : _muted)),
              ),
              title: Text('${s.name}${s.active ? '' : ' (inactive)'}', style: _j(14, FontWeight.w800, _ink)),
              subtitle: Text(
                '${Staff.roles[s.role]?.$1 ?? s.role} · ${s.perms.isEmpty ? 'sales only' : s.perms.map((p) => Staff.perms[p]?.$1 ?? p).join(', ')}',
                style: _j(11.5, FontWeight.w500, _muted),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: _red),
                onPressed: () async {
                  final ok = await confirmDelete(context, 'Remove ${s.name}?', 'They can no longer sign in. Their past actions stay in the log.');
                  if (ok) {
                    await Staff.remove(s);
                    await _refresh();
                  }
                },
              ),
            ),
          ),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 24), child: EmptyState('No staff yet — set the owner PIN, then add a salesman')),
        const SizedBox(height: 80),
      ],
    );
  }
}

/// "Who is working?" — shown on top of the app while staff mode waits for a PIN.
class StaffGate extends StatelessWidget {
  final Widget child;
  const StaffGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Staff.picking,
      builder: (context, picking, _) => picking ? const _WhoIsWorking() : child,
    );
  }
}

class _WhoIsWorking extends StatefulWidget {
  const _WhoIsWorking();
  @override
  State<_WhoIsWorking> createState() => _WhoIsWorkingState();
}

class _WhoIsWorkingState extends State<_WhoIsWorking> {
  String pin = '';
  String? error;
  String? who; // name tapped (hint only — the PIN decides)

  Future<void> _tap(String d) async {
    HapticFeedback.selectionClick();
    if (d == '⌫') {
      setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1));
      return;
    }
    if (d == '✓') {
      await _submit();
      return;
    }
    if (pin.length >= 6) return;
    setState(() {
      pin += d;
      error = null;
    });
    // a full 6-digit PIN signs in by itself; shorter PINs with ✓ (so a PIN
    // that starts like someone else's never signs in the wrong person)
    if (pin.length == 6) await _submit();
  }

  Future<void> _submit() async {
    if (pin.length < 4) {
      setState(() => error = 'Enter your 4–6 digit PIN');
      return;
    }
    try {
      await Staff.signIn(pin);
    } on AccountingError {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        error = 'Wrong PIN';
        pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = Staff.list.where((s) => s.active).toList();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1B1F6B), Color(0xFF4318D2)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 26),
            const Icon(Icons.badge_rounded, color: Colors.white, size: 42),
            const SizedBox(height: 8),
            Text('Who is working?', style: _j(22, FontWeight.w800, Colors.white)),
            Text(who == null ? 'Tap your name and enter your PIN' : 'Hi $who — enter your PIN', style: _j(13, FontWeight.w500, Colors.white70)),
            const SizedBox(height: 16),
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                _person('Owner', Icons.admin_panel_settings_rounded),
                for (final s in people) _person(s.name, null),
              ]),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 6; i++)
                Container(
                  margin: const EdgeInsets.all(6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < pin.length ? Colors.white : Colors.white24,
                  ),
                ),
            ]),
            SizedBox(height: 22, child: Text(error ?? '', style: _j(13, FontWeight.w800, const Color(0xFFFFB4C4)))),
            const Spacer(),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['⌫', '0', '✓'],
            ])
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final d in row)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: InkWell(
                            borderRadius: BorderRadius.circular(36),
                            onTap: () => _tap(d),
                            child: Container(
                              width: 72,
                              height: 72,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: d == '✓' ? const Color(0xFF0BA360) : const Color(0x26FFFFFF)),
                              child: Text(d, style: _j(26, FontWeight.w700, Colors.white)),
                            ),
                          ),
                  ),
              ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _person(String name, IconData? icon) {
    final on = who == name;
    return GestureDetector(
      onTap: () => setState(() {
        who = name;
        pin = '';
        error = null;
      }),
      child: Container(
        width: 76,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? Colors.white : const Color(0x33FFFFFF),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: on ? _purple : Colors.white)
                : Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: _j(22, FontWeight.w800, on ? _purple : Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(12, FontWeight.w700, Colors.white)),
        ]),
      ),
    );
  }
}
