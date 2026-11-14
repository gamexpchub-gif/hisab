import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/plan.dart';
import '../core/stores.dart';
import '../ui/widgets.dart';
import 'plans.dart';

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);
const _purple = Color(0xFF5B2EE0);
const _red = Color(0xFFDC4545);

TextStyle _j(double s, FontWeight w, Color c) => TextStyle(fontFamily: 'Jakarta', fontSize: s, fontWeight: w, color: c, height: 1.25);

const _storeColors = [
  [Color(0xFF8B5CF6), Color(0xFF4318D2)],
  [Color(0xFF3EE08F), Color(0xFF0E9F5E)],
  [Color(0xFFFFB547), Color(0xFFE38A0B)],
  [Color(0xFF6AA5FF), Color(0xFF1A47C8)],
  [Color(0xFFFF7A9A), Color(0xFFD81E4A)],
  [Color(0xFF5EEAD4), Color(0xFF0D9488)],
];

/// Asks for a name and adds a store.
Future<void> addStoreFlow(BuildContext context) async {
  if (Stores.all.length >= Sub.storeLimit) {
    if (!Sub.can('multi_store')) {
      await showUpgrade(context, 'multi_store');
    } else {
      await showUpgrade(context, 'stores10');
    }
    return;
  }
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Notun store'),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Store / dokaner naam', hintText: 'e.g. GameX Mobile — Branch 2'),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Add')),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  try {
    await Stores.add(name);
    if (context.mounted) toast(context, '${name.trim()} chalu holo — ekhon ei store-er hisab');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

/// Bottom sheet to switch store quickly (from Home / Menu).
Future<void> showStoreSwitcher(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE9EAF5), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text('Store bachun', style: _j(18, FontWeight.w800, _ink)),
          const SizedBox(height: 8),
          for (final (i, s) in Stores.all.indexed)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: _avatar(s, i),
              title: Text(s.name, style: _j(14.5, FontWeight.w800, _ink)),
              trailing: s.id == Stores.current ? const Icon(Icons.check_circle_rounded, color: _purple) : null,
              onTap: () async {
                Navigator.pop(c);
                HapticFeedback.selectionClick();
                await Stores.switchTo(s.id);
                if (context.mounted) toast(context, '${s.name} khola holo');
              },
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            onPressed: () {
              Navigator.pop(c);
              open(context, const StoresScreen());
            },
            icon: const Icon(Icons.store_mall_directory_rounded),
            label: const Text('Store manage korun'),
          ),
        ]),
      ),
    );

Widget _avatar(Store s, int i, {double size = 44}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .3), gradient: LinearGradient(colors: _storeColors[i % _storeColors.length])),
      alignment: Alignment.center,
      child: Text(s.name.trim().isEmpty ? 'S' : s.name.trim()[0].toUpperCase(), style: _j(size * .42, FontWeight.w800, Colors.white)),
    );

/// Chip that shows the store in use and opens the switcher.
class StoreChip extends StatelessWidget {
  final bool dark;
  const StoreChip({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) {
    if (Stores.all.length < 2) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => showStoreSwitcher(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: dark ? const Color(0x26FFFFFF) : const Color(0xFFEEEBFF), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.storefront_rounded, size: 14, color: dark ? Colors.white : _purple),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(Stores.active.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11.5, FontWeight.w800, dark ? Colors.white : _purple)),
          ),
          Icon(Icons.expand_more_rounded, size: 16, color: dark ? Colors.white : _purple),
        ]),
      ),
    );
  }
}

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<Map<String, (int, int)>>(
      load: Stores.counts,
      builder: (context, counts) => PageShell(
        title: 'My Stores',
        subtitle: '${Stores.all.length} / ${Sub.storeLimit} store · ${Sub.label} plan',
        fab: FloatingActionButton.extended(
          backgroundColor: _purple,
          onPressed: () => addStoreFlow(context),
          icon: const Icon(Icons.add_business_rounded, color: Colors.white),
          label: Text('Notun store', style: _j(14, FontWeight.w800, Colors.white)),
        ),
        children: [
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF4F0FF), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: _purple),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Protita store-er hisab (product, bill, khata, cash) alada thake. Ek account-e shob store, ek tap-e bodlan.',
                    style: _j(12, FontWeight.w600, const Color(0xFF3B2E8F))),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final (i, s) in Stores.all.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: s.id == Stores.current ? _purple : const Color(0xFFF1F2F9), width: s.id == Stores.current ? 2 : 1),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                leading: _avatar(s, i, size: 48),
                title: Text(s.name, style: _j(15, FontWeight.w800, _ink)),
                subtitle: Text(
                  '${counts[s.id]?.$1 ?? 0} product · ${counts[s.id]?.$2 ?? 0} bill${s.id == Stores.current ? ' · ekhon cholche' : ''}',
                  style: _j(12, FontWeight.w600, s.id == Stores.current ? _purple : _muted),
                ),
                onTap: s.id == Stores.current
                    ? null
                    : () async {
                        await Stores.switchTo(s.id);
                        if (context.mounted) toast(context, '${s.name} khola holo');
                      },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'open') await Stores.switchTo(s.id);
                    if (v == 'rename' && context.mounted) {
                      final c = TextEditingController(text: s.name);
                      final n = await showDialog<String>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Naam bodlan'),
                          content: TextField(controller: c, autofocus: true),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (n != null) await Stores.rename(s.id, n);
                    }
                    if (v == 'delete' && context.mounted) {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: Text('${s.name} delete?'),
                          content: const Text('Ei store-er shob hisab (product, bill, khata) phone theke muche jabe. Age backup nin.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: _red))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          await Stores.remove(s.id);
                        } catch (e) {
                          if (context.mounted) toast(context, '$e', error: true);
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    if (s.id != Stores.current) const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (s.id != Stores.current) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _red))),
                  ],
                ),
              ),
            ),
          if (Stores.all.length >= Sub.storeLimit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                Sub.tier >= 3 ? 'Sorbochcho ${Sub.storeLimit} ta store.' : 'Aro store-er jonno ${Sub.tier < 2 ? 'Gold (3 store)' : 'Premium (10 store)'} plan nin.',
                textAlign: TextAlign.center,
                style: _j(12, FontWeight.w600, _muted),
              ),
            ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

