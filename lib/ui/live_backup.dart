import 'package:flutter/material.dart';

import '../core/backup.dart';
import '../core/books.dart';

/// Live backup status: a pulsing dot and "Saved to cloud 4:12 PM", with an
/// on / off switch.
class LiveBackupCard extends StatefulWidget {
  const LiveBackupCard({super.key});
  @override
  State<LiveBackupCard> createState() => _LiveBackupCardState();
}

class _LiveBackupCardState extends State<LiveBackupCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  bool on = true;

  @override
  void initState() {
    super.initState();
    Books.settings().then((s) {
      if (mounted) setState(() => on = s['live_backup'] != '0');
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final today = DateUtils.isSameDay(t, DateTime.now());
    return '${today ? '' : '${t.day}/${t.month} '}$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveState>(
      valueListenable: Backup.live,
      builder: (context, st, _) {
        final color = !on
            ? const Color(0xFF94A3B8)
            : switch (st.kind) {
                'cloud' => const Color(0xFF0BA360),
                'phone' => const Color(0xFF2563EB),
                'sending' => const Color(0xFF7B3FF2),
                'waiting' => const Color(0xFFF97316),
                _ => const Color(0xFF0BA360),
              };
        final text = !on
            ? 'Live backup is off'
            : st.at == null
                ? 'Live backup on · every change goes to the cloud in about 2 seconds'
                : '${st.text} · ${_time(st.at!)}${st.pending > 0 && st.kind == 'waiting' ? ' · ${st.pending} change${st.pending == 1 ? '' : 's'} waiting' : ''}';
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: color.withAlpha(0x14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(0x40)),
          ),
          child: Row(children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: on ? [BoxShadow(color: color.withAlpha(0x88), blurRadius: 4 + 6 * _pulse.value, spreadRadius: 2 * _pulse.value)] : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Live backup', style: TextStyle(fontFamily: 'Jakarta', fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
                Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Jakarta', fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF3A4155))),
              ]),
            ),
            if (on)
              IconButton(
                tooltip: 'Back up now',
                onPressed: st.kind == 'sending' ? null : () => Backup.liveNow(),
                icon: st.kind == 'sending'
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(Icons.cloud_upload_rounded, color: color),
              ),
            Switch(
              value: on,
              onChanged: (v) async {
                setState(() => on = v);
                await Books.setSetting('live_backup', v ? '1' : '0');
                if (v) await Backup.liveNow();
              },
            ),
          ]),
        );
      },
    );
  }
}
