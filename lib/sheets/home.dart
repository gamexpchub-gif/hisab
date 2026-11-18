import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/widgets.dart';
import 'editor.dart';
import 'templates.dart';
import 'workbook.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c);

String _ago(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 1440) return '${m ~/ 60} h ago';
  if (m < 2880) return 'yesterday';
  return '${d.day}/${d.month}/${d.year}';
}

/// Hisab Sheets — the spreadsheet app inside Hisab AI: templates by
/// category, live data from the books, and every workbook you made.
class SheetsHome extends StatefulWidget {
  const SheetsHome({super.key});
  @override
  State<SheetsHome> createState() => _SheetsHomeState();
}

class _SheetsHomeState extends State<SheetsHome> {
  List<Workbook> books = [];
  bool loading = true, busy = false;
  String cat = 'All', q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var b = <Workbook>[];
    try {
      b = await SheetStore.list();
    } catch (_) {}
    if (mounted) {
      setState(() {
        books = b;
        loading = false;
      });
    }
  }

  Future<void> _openBook(Workbook w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SheetEditor(book: w)));
    _load();
  }

  Future<void> _create(Future<Workbook> Function() make) async {
    if (busy) return;
    setState(() => busy = true);
    HapticFeedback.mediumImpact();
    try {
      final w = await make();
      await SheetStore.save(w);
      if (!mounted) return;
      setState(() => busy = false);
      await _openBook(w);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, '$e', error: true);
      }
    }
  }

  Future<void> _bookMenu(Workbook w) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(ctx).padding.bottom),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(w.name, style: _j(16, FontWeight.w800, _ink)), subtitle: Text('${w.category} · ${w.sheets.length} sheets')),
          ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('Open'), onTap: () => Navigator.pop(ctx, 'open')),
          ListTile(leading: Icon(w.starred ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE08A00)), title: Text(w.starred ? 'Unstar' : 'Star'), onTap: () => Navigator.pop(ctx, 'star')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.copy_all_rounded), title: const Text('Duplicate'), onTap: () => Navigator.pop(ctx, 'dup')),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC4545)),
            title: const Text('Delete', style: TextStyle(color: Color(0xFFDC4545))),
            onTap: () => Navigator.pop(ctx, 'del'),
          ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'open':
        await _openBook(w);
      case 'star':
        w.starred = !w.starred;
        await SheetStore.save(w);
      case 'rename':
        final t = TextEditingController(text: w.name);
        final n = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rename'),
            content: TextField(controller: t, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('Save')),
            ],
          ),
        );
        if (n != null && n.trim().isNotEmpty) {
          w.name = n.trim();
          await SheetStore.save(w);
        }
      case 'dup':
        await SheetStore.duplicate(w);
      case 'del':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete "${w.name}"?'),
            content: const Text('This workbook will be removed from this phone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFDC4545)))),
            ],
          ),
        );
        if (ok == true) await SheetStore.delete(w.id);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = q.toLowerCase();
    final templates = sheetTemplates.where((t) => (cat == 'All' || t.category == cat) && (s.isEmpty || '${t.name} ${t.desc}'.toLowerCase().contains(s))).toList();
    final mine = books.where((b) => s.isEmpty || b.name.toLowerCase().contains(s)).toList()
      ..sort((a, b) => a.starred == b.starred ? b.updated.compareTo(a.updated) : (a.starred ? -1 : 1));
    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F1),
      body: Stack(children: [
        // soft background blobs for the glass to blur
        Positioned(top: -120, right: -80, child: _blob(320, const [Color(0x6621A366), Color(0x0021A366)])),
        Positioned(top: 260, left: -120, child: _blob(300, const [Color(0x445B2EE0), Color(0x005B2EE0)])),
        Positioned(bottom: -100, right: -60, child: _blob(280, const [Color(0x4422D3EE), Color(0x0022D3EE)])),
        CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _hero(mq.padding.top)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Row(children: [
                Text('Start something new', style: _j(17, FontWeight.w800, _ink)),
                const Spacer(),
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: _quickRow()),
          SliverToBoxAdapter(child: _categories()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 168, crossAxisSpacing: 12, mainAxisSpacing: 12),
              delegate: SliverChildBuilderDelegate((_, i) => _TemplateCard(templates[i], onTap: () => _create(templates[i].build)), childCount: templates.length),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(children: [
                Text('Your workbooks', style: _j(17, FontWeight.w800, _ink)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(8)),
                  child: Text('${books.length}', style: _j(12, FontWeight.w800, const Color(0xFF107C41))),
                ),
              ]),
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())))
          else if (mine.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _glass(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    const Icon(Icons.grid_on_rounded, size: 40, color: Color(0xFF107C41)),
                    const SizedBox(height: 8),
                    Text('No workbooks yet', style: _j(15, FontWeight.w800, _ink)),
                    Text('Pick a template above or start a blank sheet', style: _j(12.5, FontWeight.w500, _muted)),
                  ]),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverList.builder(
                itemCount: mine.length,
                itemBuilder: (_, i) => _BookTile(mine[i], onTap: () => _openBook(mine[i]), onMore: () => _bookMenu(mine[i])),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: 40 + mq.padding.bottom)),
        ]),
      ]),
    );
  }

  Widget _blob(double size, List<Color> colors) => IgnorePointer(
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: colors))),
      );

  Widget _hero(double top) => Container(
        padding: EdgeInsets.fromLTRB(16, top + 8, 16, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF063B1F), Color(0xFF107C41), Color(0xFF21A366)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Color(0x55107C41), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -10)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            const Spacer(),
            _glassChip(Icons.table_chart_rounded, '${sheetTemplates.length} templates'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFD7F5E3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 10), spreadRadius: -6),
                  BoxShadow(color: Colors.white, blurRadius: 0, offset: Offset(-1, -1)),
                ],
              ),
              child: const Icon(Icons.grid_on_rounded, color: Color(0xFF107C41), size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hisab Sheets', style: _j(26, FontWeight.w800, Colors.white)),
                Text('Spreadsheets with formulas, charts & your live shop data', style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => q = v),
                  style: _j(14.5, FontWeight.w600, Colors.white),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white),
                    hintText: 'Search templates and workbooks',
                    hintStyle: _j(13.5, FontWeight.w500, const Color(0xCCFFFFFF)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _glassChip(IconData icon, String text) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x44FFFFFF))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(text, style: _j(12, FontWeight.w800, Colors.white)),
            ]),
          ),
        ),
      );

  Widget _quickRow() {
    final quick = [
      ('Blank', 'Empty sheet', Icons.add_rounded, const [Color(0xFF21A366), Color(0xFF0B5A30)], () => blankWorkbook()),
      for (final id in ['live_sales', 'live_stock', 'invoice', 'emi'])
        () {
          final t = sheetTemplates.firstWhere((x) => x.id == id);
          return (t.name, t.category, t.icon, [Color(t.color).withAlpha(0xCC), Color(t.color)], t.build);
        }(),
    ];
    return SizedBox(
      height: 132,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final it in quick)
          GestureDetector(
            onTap: () => _create(it.$5),
            child: Container(
              width: 112,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: _glass(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _orb(it.$3, it.$4, size: 44),
                  const Spacer(),
                  Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(13.5, FontWeight.w800, _ink)),
                  Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w600, _muted)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _categories() => SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 6), children: [
          for (final (name, color, icon) in [('All', 0xFF0A0E26, Icons.apps_rounded), ...sheetCategories])
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => cat = name);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: cat == name ? LinearGradient(colors: [Color(color).withAlpha(0xDD), Color(color)]) : null,
                  color: cat == name ? null : const Color(0xCCFFFFFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cat == name ? Colors.transparent : const Color(0xFFE1E5EE)),
                  boxShadow: cat == name ? [BoxShadow(color: Color(color).withAlpha(0x55), blurRadius: 12, offset: const Offset(0, 5))] : null,
                ),
                child: Row(children: [
                  Icon(icon, size: 16, color: cat == name ? Colors.white : Color(color)),
                  const SizedBox(width: 6),
                  Text(name, style: _j(12.5, FontWeight.w800, cat == name ? Colors.white : _ink)),
                ]),
              ),
            ),
        ]),
      );
}

Widget _glass({required Widget child, EdgeInsets padding = EdgeInsets.zero}) => ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xE6FFFFFF), Color(0xB3FFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xCCFFFFFF), width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x1A0F2A1E), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -6)],
          ),
          child: child,
        ),
      ),
    );

Widget _orb(IconData icon, List<Color> colors, {double size = 46}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: colors.last.withAlpha(0x66), blurRadius: 12, offset: const Offset(0, 6), spreadRadius: -3),
        ],
      ),
      child: Stack(children: [
        // glossy top highlight for a 3D look
        Positioned(
          left: 4,
          right: 4,
          top: 3,
          height: size * .38,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .25),
              gradient: const LinearGradient(colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
          ),
        ),
        Center(child: Icon(icon, color: Colors.white, size: size * .5)),
      ]),
    );

class _TemplateCard extends StatelessWidget {
  final SheetTemplate t;
  final VoidCallback onTap;
  const _TemplateCard(this.t, {required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: _glass(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _orb(t.icon, [Color(t.color).withAlpha(0xBB), Color(t.color)]),
              const Spacer(),
              if (t.category == 'Live data')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF16A36A), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('LIVE', style: _j(9.5, FontWeight.w800, const Color(0xFF107C41))),
                  ]),
                ),
            ]),
            const Spacer(),
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14, FontWeight.w800, _ink)),
            const SizedBox(height: 2),
            Text(t.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w500, _muted)),
          ]),
        ),
      );
}

class _BookTile extends StatelessWidget {
  final Workbook w;
  final VoidCallback onTap, onMore;
  const _BookTile(this.w, {required this.onTap, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final s = w.sheets.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onMore,
        child: _glass(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // mini preview of the first cells
            Container(
              width: 64,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDDE5E0)),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 3))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Row(children: [
                      for (var j = 0; j < 3; j++)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: s.at(i, j)?.fill != null ? Color(s.at(i, j)!.fill!) : (i == 0 ? Color(w.color).withAlpha(0x22) : null),
                              border: const Border(right: BorderSide(color: Color(0xFFE8ECEA), width: .6), bottom: BorderSide(color: Color(0xFFE8ECEA), width: .6)),
                            ),
                            child: s.input(i, j).isEmpty
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.all(2.5),
                                    child: Container(color: Color(w.color).withAlpha(i == 0 ? 0xAA : 0x44)),
                                  ),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (w.starred) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFE08A00))),
                  Expanded(child: Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(14.5, FontWeight.w800, _ink))),
                ]),
                const SizedBox(height: 2),
                Text('${w.category} · ${w.sheets.length} sheet${w.sheets.length == 1 ? '' : 's'} · ${_ago(w.updated)}',
                    style: _j(11.5, FontWeight.w600, _muted)),
              ]),
            ),
            IconButton(onPressed: onMore, icon: const Icon(Icons.more_horiz_rounded, color: _muted)),
          ]),
        ),
      ),
    );
  }
}
