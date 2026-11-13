import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud.dart';
import '../core/backup.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/widgets.dart';
import 'login.dart';

// =============================================================================
// Account & Cloud — who is signed in, cloud backup now / automatic, the list
// of cloud backups with restore, and sign out.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _red = Color(0xFFDC4545);

TextStyle _j(double size, FontWeight w, Color c) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
    );

BoxDecoration _card() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6)],
    );

String _when(DateTime d) => '${prettyDate(ymd(d))} · ${two(d.hour)}:${two(d.minute)}';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<CloudBackup>? backups;
  String? listError;
  double? progress;
  String? progressText;
  Map<String, String> settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Cloud.load();
    settings = await Books.settings();
    if (mounted) setState(() {});
    if (Cloud.user == null) return;
    try {
      final b = await Cloud.listBackups();
      if (!mounted) return;
      setState(() {
        backups = b;
        listError = null;
      });
    } catch (e) {
      if (mounted) setState(() => listError = '$e');
    }
  }

  Future<void> _job(String text, Future<void> Function() job) async {
    if (progress != null) return;
    setState(() {
      progress = 0;
      progressText = text;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => progress = null);
      await _load();
    }
  }

  Future<void> _backup() => _job('Uploading to cloud…', () async {
        final f = await Backup.create();
        await Cloud.uploadBackup(f, progress: (v) {
          if (mounted) setState(() => progress = v);
        });
        HapticFeedback.mediumImpact();
        if (mounted) toast(context, 'Backed up to cloud');
      });

  Future<void> _restore(CloudBackup b) async {
    final here = await Backup.localSummary();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF4318D2), size: 42),
        title: const Text('Restore from cloud?'),
        content: Text('Backup of ${_when(b.created)} — ${b.sales} sales, ${b.products} products, ${b.customers} customers.\n\n'
            '⚠️ This phone now has $here — all of it will be REPLACED by the backup.\n'
            'A safety copy of the current data is saved first (Backup & Restore → Automatic).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await _job('Downloading…', () async {
      final f = await Cloud.downloadBackup(b, progress: (v) {
        if (mounted) setState(() => progress = v);
      });
      await Backup.restore(f);
      HapticFeedback.heavyImpact();
      if (mounted) toast(context, 'Books restored from cloud');
    });
  }

  Future<void> _signOut() async {
    final ok = await confirmDelete(context, 'Sign out?',
        'Your books stay on this phone. Cloud backups stop until you sign in again.');
    if (!ok) return;
    await Cloud.signOut();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final u = Cloud.user;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x262A2F7A), blurRadius: 14, offset: Offset(0, 5), spreadRadius: -4)],
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: _ink),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Account & Cloud', style: _j(22, FontWeight.w800, _navy)),
                Text('Login · cloud backup · restore', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
              ]),
            ]),
            const SizedBox(height: 16),
            _profile(u),
            const SizedBox(height: 14),
            if (u == null)
              GradientButton(
                label: 'Sign in / create account',
                expand: true,
                fontSize: 16,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (ctx) => LoginScreen(fromSettings: true, onDone: () => Navigator.of(ctx).pop()),
                  ));
                  await _load();
                },
              )
            else ...[
              Row(children: [
                Expanded(
                  child: _bigBtn(Icons.cloud_upload_rounded, 'Backup now', 'Books + photos to cloud',
                      const [Color(0xFF6B35EE), Color(0xFF4318D2)], _backup),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _bigBtn(Icons.cloud_sync_rounded, 'Auto backup', settings['cloud_auto'] == '0' ? 'Off' : 'Daily · on',
                      const [Color(0xFF34D399), Color(0xFF0F8C58)], () async {
                    await Books.setSetting('cloud_auto', settings['cloud_auto'] == '0' ? '1' : '0');
                    await _load();
                  }),
                ),
              ]),
              const SizedBox(height: 14),
              _list(),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: _red,
                  side: const BorderSide(color: Color(0xFFFFC9C9)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ]),
          if (progress != null)
            Positioned.fill(
              child: Container(
                color: const Color(0x880A0E26),
                alignment: Alignment.center,
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(22),
                  decoration: _card(),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(progressText ?? 'Working…', style: _j(14.5, FontWeight.w800, _ink)),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text('${((progress ?? 0) * 100).round()}%', style: _j(12, FontWeight.w700, _muted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _profile(CloudUser? u) {
    final last = DateTime.tryParse(settings['last_cloud_backup_at'] ?? '');
    final name = (u?.name ?? '').trim();
    final initials = (name.isNotEmpty ? name : (u?.email ?? '?'))
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: u == null
              ? const [Color(0xFF94A3B8), Color(0xFF475569), Color(0xFF1E293B)]
              : const [Color(0xFF6A2FF0), Color(0xFF4B22D8), Color(0xFF2F55E8)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x554A17C9), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -10)],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x33FFFFFF),
            border: Border.all(color: const Color(0x80FFFFFF), width: 2),
          ),
          child: u == null
              ? const Icon(Icons.person_off_rounded, color: Colors.white, size: 30)
              : Text(initials, style: _j(22, FontWeight.w800, Colors.white)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u == null ? 'Not signed in' : (name.isEmpty ? 'My account' : name), style: _j(18, FontWeight.w800, Colors.white)),
            Text(u == null ? 'Books are only on this phone' : u.email, style: _j(12.5, FontWeight.w600, const Color(0xDDFFFFFF))),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(u == null ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text(
                  u == null
                      ? (Cloud.configured ? 'Cloud ready — sign in' : 'Cloud not set up')
                      : last == null
                          ? 'No cloud backup yet'
                          : 'Last cloud backup ${_when(last)}',
                  style: _j(11, FontWeight.w700, Colors.white),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bigBtn(IconData i, String t, String s, List<Color> c, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 96,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: c.last.withAlpha(0x66), blurRadius: 16, offset: const Offset(0, 8), spreadRadius: -8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(t, style: _j(14, FontWeight.w800, Colors.white)),
            Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(10.5, FontWeight.w600, const Color(0xDDFFFFFF))),
          ]),
        ),
      );

  Widget _list() => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cloud backups', style: _j(15, FontWeight.w800, _ink)),
          const SizedBox(height: 6),
          if (listError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(listError!, style: _j(12.5, FontWeight.w600, _red)),
            )
          else if (backups == null)
            const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
          else if (backups!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No cloud backup yet — tap Backup now', style: _j(12.5, FontWeight.w600, _muted)),
            ),
          for (final b in backups ?? const <CloudBackup>[])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.cloud_rounded, color: Color(0xFF5B2EE0), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_when(b.created), style: _j(13, FontWeight.w700, _ink)),
                    Text('${b.sales} sales · ${b.products} products · ${Backup.size(b.bytes)}${b.device.isEmpty ? '' : ' · ${b.device}'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _j(11, FontWeight.w500, _muted)),
                  ]),
                ),
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (v) async {
                    if (v == 'restore') await _restore(b);
                    if (v == 'delete') {
                      await runDelete(context,
                          title: 'Delete this cloud backup?',
                          message: 'The backup of ${_when(b.created)} is removed from the cloud.',
                          action: () => Cloud.deleteBackup(b),
                          popAfter: false);
                      await _load();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'restore', child: Text('Restore this backup')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _red))),
                  ],
                ),
              ]),
            ),
        ]),
      );
}
