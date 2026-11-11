import 'package:flutter/material.dart';

import '../core/books.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final keys = const {
    'business_name': 'Business name',
    'tagline': 'Tagline',
    'owner_name': 'Your name (shown on Home)',
    'phone': 'Shop phone',
    'address': 'Shop address',
    'gstin': 'GSTIN',
  };
  final ctrls = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final k in keys.keys) {
      ctrls[k] = TextEditingController();
    }
    Books.settings().then((s) {
      for (final k in keys.keys) {
        ctrls[k]!.text = s[k] ?? '';
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(title: 'Settings', subtitle: 'Business profile', children: [
      CardBox(child: Column(children: [for (final e in keys.entries) field(ctrls[e.key]!, e.value)])),
      const SizedBox(height: 14),
      GradientButton(
        label: 'Save',
        expand: true,
        fontSize: 16,
        onTap: () async {
          for (final k in keys.keys) {
            await Books.setSetting(k, ctrls[k]!.text.trim());
          }
          if (!context.mounted) return;
          toast(context, 'Settings saved');
        },
      ),
      CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Demo data', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Load sample products, customers and transactions to explore the app. Only works on an empty book.',
              style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Load demo data'),
            onPressed: () async {
              try {
                await Books.loadDemo();
                if (!context.mounted) return;
                toast(context, 'Demo data loaded');
              } catch (e) {
                toast(context, '$e', error: true);
              }
            },
          ),
        ]),
      ),
      const SizedBox(height: 20),
      const Center(child: Text('GameX Hisab v1.0 · data stays on this phone', style: TextStyle(color: C.muted, fontSize: 12))),
    ]);
  }
}
