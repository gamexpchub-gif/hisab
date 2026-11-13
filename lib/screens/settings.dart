import 'package:flutter/material.dart';

import '../core/books.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'forms.dart';
import '../ui/photo.dart';
import 'account.dart';
import 'backup_screen.dart';
import 'sale_return.dart';
import 'security.dart';

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
    'upi_id': 'UPI ID for QR payments (e.g. shop@okaxis)',
    'phonepe': 'PhonePe number (bill)',
    'state': 'State (e.g. West Bengal)',
    'pin': 'PIN code',
    'bank_name': 'Bank name (bill)',
    'bank_branch': 'Bank branch (bill)',
    'bank_acc': 'Bank account number (bill)',
    'bank_ifsc': 'IFSC code (bill)',
    'invoice_banner': 'Bill banner line',
    'terms': 'Bill terms & conditions (one per line)',
  };
  final ctrls = <String, TextEditingController>{};
  String? photo;
  bool oppId = false;

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
      photo = s['owner_photo'];
      oppId = s['opp_id_enabled'] == '1';
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
      CardBox(
        onTap: () async {
          final r = await pickPhoto(context, folder: 'profile', allowRemove: (photo ?? '').isNotEmpty);
          if (r == null) return;
          await Books.setSetting('owner_photo', r);
          setState(() => photo = r);
        },
        child: Row(children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: storedImage(photo,
                  fallback: Container(
                    color: const Color(0xFFEAF0FF),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF2F6BFF), size: 38),
                  )),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Profile photo\nTap to change', style: TextStyle(color: C.muted, height: 1.4)),
          ),
          const Icon(Icons.photo_camera_rounded, color: C.purple2),
        ]),
      ),
      CardBox(
        onTap: () => open(context, const AccountScreen()),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF1B2163)]),
            ),
            child: const Icon(Icons.account_circle_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Account & Cloud', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('Login and keep your books in the cloud', style: TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
      CardBox(
        onTap: () => open(context, const BackupScreen()),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF0F8C58)]),
            ),
            child: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Backup & Restore', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('Database + photos · Google Drive · daily auto backup', style: TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
      CardBox(
        onTap: () => open(context, const SecurityScreen()),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF1B2163)]),
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Security', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('App lock with PIN and fingerprint', style: TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
      CardBox(
        onTap: () => open(context, const SaleReturnsScreen()),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFFFF6B8B), Color(0xFFE0245E)]),
              boxShadow: const [BoxShadow(color: Color(0x55E0245E), blurRadius: 12, offset: Offset(0, 5), spreadRadius: -4)],
            ),
            child: const Icon(Icons.assignment_return_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sale return', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('Take goods back · refund less & keep the charge as profit',
                  style: TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
      CardBox(
        child: Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: oppId,
          onChanged: (v) async {
            await Books.setSetting('opp_id_enabled', v ? '1' : '0');
            setState(() => oppId = v);
          },
          secondary: const Icon(Icons.badge_rounded, color: C.green),
          title: const Text('Opportunity ID on sales', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          subtitle: const Text('Adds a field under the IMEI in New sale and prints it on the bill',
              style: TextStyle(color: C.muted, fontSize: 12.5)),
        ),
        ),
      ),
      CardBox(child: Column(children: [for (final e in keys.entries) field(ctrls[e.key]!, e.value, maxLines: e.key == 'terms' ? 5 : 1)])),
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
