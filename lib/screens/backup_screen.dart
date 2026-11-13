import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/backup.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/widgets.dart';

// =============================================================================
// Backup & Restore — one-tap full backup (database + photos) shared to Google
// Drive / WhatsApp / email, automatic daily backups kept on the phone, and
// restore from any backup file with a preview and a safety copy.
// =============================================================================

const _bg = Color(0xFFF6F7FC);
const _ink = Color(0xFF0A0E26);
const _navy = Color(0xFF0B0F5E);
const _muted = Color(0xFF6B7094);
const _green = Color(0xFF16A36A);
const _red = Color(0xFFDC4545);

TextStyle _j(double size, FontWeight w, Color c) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
    );

BoxDecoration _card({double r = 22}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: const Color(0xFFEEF0F8)),
      boxShadow: const [BoxShadow(color: Color(0x1A2A2F7A), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6)],
    );

String _ago(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  if (m < 60 * 24) return '${m ~/ 60} h ago';
  return '${m ~/ (60 * 24)} days ago';
}

String _when(DateTime d) => '${prettyDate(ymd(d))} · ${two(d.hour)}:${two(d.minute)}';

class _Data {
  final List<BackupFile> files;
  final Map<String, String> settings;
  final Map<String, int> counts;
  _Data(this.files, this.settings, this.counts);
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  String? busyText;
  int version = 0;

  Future<_Data> _load() async {
    final counts = <String, int>{};
    for (final t in ['sales', 'purchases', 'products', 'customers', 'suppliers', 'expenses']) {
      counts[t] = asInt((await Books.query('SELECT COUNT(*) AS c FROM $t')).first['c']);
    }
    List<BackupFile> files;
    try {
      files = await Backup.list();
    } catch (_) {
      files = const [];
    }
    return _Data(files, await Books.settings(), counts);
  }

  Future<void> _run(String text, Future<void> Function() job) async {
    if (busy) return;
    setState(() {
      busy = true;
      busyText = text;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          version++;
        });
      }
    }
  }

  Future<void> _share(File f) async {
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/zip')],
        subject: 'GameX Hisab backup', text: 'GameX Hisab backup — keep this file safe (Google Drive / email).');
  }

  Future<void> _backupNow({bool share = true}) => _run('Creating backup…', () async {
        final f = await Backup.create();
        HapticFeedback.mediumImpact();
        if (!mounted) return;
        toast(context, 'Backup saved · ${Backup.size(await f.length())}');
        if (share) await _share(f);
      });

  Future<void> _restore(File f) async {
    Map<String, dynamic> info;
    try {
      info = await Backup.inspect(f);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
      return;
    }
    if (!mounted) return;
    final created = DateTime.tryParse('${info['created'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        icon: const Icon(Icons.restore_rounded, color: Color(0xFFE0245E), size: 40),
        title: const Text('Restore this backup?'),
        content: Text(
          '${created == null ? '' : 'Made ${_when(created)}\n'}'
          '${info['sales'] ?? '?'} sales · ${info['products'] ?? '?'} products · ${info['customers'] ?? '?'} customers · '
          '${info['photos'] ?? 0} photos\n\n'
          'Everything on this phone will be replaced with the backup. A safety copy of the current data is saved first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE0245E)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Restoring…', () async {
      await Backup.restore(f);
      HapticFeedback.heavyImpact();
      if (mounted) toast(context, 'Backup restored');
    });
  }

  Future<void> _pickAndRestore() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = r?.files.single.path;
      if (path == null) return;
      await _restore(File(path));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(children: [
          Live<_Data>(
            reloadKey: version,
            load: _load,
            builder: (context, d) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              _header(),
              const SizedBox(height: 16),
              _hero(d),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _bigBtn(Icons.cloud_upload_rounded, 'Backup & share', 'Drive · WhatsApp · email',
                      const [Color(0xFF6B35EE), Color(0xFF4318D2)], () => _backupNow()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _bigBtn(Icons.settings_backup_restore_rounded, 'Restore', 'From a backup file',
                      const [Color(0xFFFF6B8B), Color(0xFFE0245E)], _pickAndRestore),
                ),
              ]),
              const SizedBox(height: 10),
              _autoCard(d),
              const SizedBox(height: 14),
              _list(d),
              const SizedBox(height: 12),
              Text(
                'Tip: share a backup to Google Drive once a week. Backups kept only on this phone are lost if the phone is lost or the app is uninstalled.',
                style: _j(11.5, FontWeight.w500, _muted),
              ),
            ]),
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                color: const Color(0x880A0E26),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: _card(r: 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(busyText ?? 'Working…', style: _j(14, FontWeight.w700, _ink)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _header() => Row(children: [
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
          Text('Backup & Restore', style: _j(22, FontWeight.w800, _navy)),
          Text('Database + all photos in one file', style: _j(12, FontWeight.w600, const Color(0xFF323B60))),
        ]),
      ]);

  Widget _hero(_Data d) {
    final last = DateTime.tryParse(d.settings['last_backup_at'] ?? '');
    final fresh = last != null && DateTime.now().difference(last).inDays < 2;
    final colors = fresh
        ? const [Color(0xFF0F9F6E), Color(0xFF0B7A55), Color(0xFF14532D)]
        : const [Color(0xFFFF8A3D), Color(0xFFF0601A), Color(0xFFB4320C)];
    Widget stat(String l, int v) => Expanded(
          child: Column(children: [
            Text('$v', style: _j(17, FontWeight.w800, Colors.white)),
            Text(l, style: _j(10.5, FontWeight.w600, const Color(0xCCFFFFFF))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: [BoxShadow(color: colors[1].withAlpha(0x66), blurRadius: 26, offset: const Offset(0, 12), spreadRadius: -10)],
      ),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(fresh ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: Colors.white, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fresh ? 'Your data is backed up' : 'Back up your data', style: _j(18, FontWeight.w800, Colors.white)),
                  Text(last == null ? 'No backup yet' : 'Last backup ${_ago(last)} · ${_when(last)}',
                      style: _j(12, FontWeight.w600, const Color(0xDDFFFFFF))),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                stat('Sales', d.counts['sales'] ?? 0),
                stat('Purchases', d.counts['purchases'] ?? 0),
                stat('Products', d.counts['products'] ?? 0),
                stat('Customers', d.counts['customers'] ?? 0),
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
            border: Border.all(color: const Color(0x55FFFFFF)),
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

  Widget _autoCard(_Data d) {
    final on = d.settings['auto_backup'] != '0';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: _card(),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _green.withAlpha(0x1A), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.autorenew_rounded, color: _green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Automatic daily backup', style: _j(14, FontWeight.w800, _ink)),
            Text('Once a day when the app opens · last ${Backup.keepAuto} kept', style: _j(11, FontWeight.w500, _muted)),
          ]),
        ),
        Switch(
          value: on,
          onChanged: (v) async {
            await Books.setSetting('auto_backup', v ? '1' : '0');
            setState(() => version++);
          },
        ),
      ]),
    );
  }

  Widget _list(_Data d) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Backups on this phone', style: _j(15, FontWeight.w800, _ink)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _backupNow(share: false),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Save now'),
            ),
          ]),
          if (d.files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No backups yet', style: _j(12.5, FontWeight.w600, _muted)),
            ),
          for (final f in d.files)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (f.auto ? const Color(0xFF2563EB) : const Color(0xFF5B2EE0)).withAlpha(0x14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(f.auto ? Icons.autorenew_rounded : Icons.inventory_2_rounded,
                      color: f.auto ? const Color(0xFF2563EB) : const Color(0xFF5B2EE0), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_when(f.when), style: _j(13, FontWeight.w700, _ink)),
                    Text('${f.auto ? 'Automatic' : 'Manual'} · ${Backup.size(f.bytes)}', style: _j(11, FontWeight.w500, _muted)),
                  ]),
                ),
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (v) async {
                    if (v == 'share') await _share(f.file);
                    if (v == 'restore') await _restore(f.file);
                    if (v == 'delete') {
                      await f.file.delete();
                      setState(() => version++);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share / save to Drive')),
                    PopupMenuItem(value: 'restore', child: Text('Restore this backup')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _red))),
                  ],
                ),
              ]),
            ),
        ]),
      );
}
