import 'package:flutter/material.dart';

import '../core/books.dart';
import '../core/money.dart';
import '../ui/widgets.dart';
import 'home.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Rec>>(
      load: () => Books.activity(300),
      builder: (context, rows) => PageShell(
        title: 'Recent Activity',
        subtitle: 'Audit trail of every action',
        children: [
          CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: rows.isEmpty
                ? const EmptyState('No activity yet')
                : Divided([
                    for (final a in rows)
                      Builder(builder: (context) {
                        final st = activityStyle[a['kind']] ?? activityStyle['sale']!;
                        return ListRow(
                          leading: Orb(icon: st.$1, colors: st.$2.icon, bg: st.$2.bg, size: 42),
                          title: a['message'] as String,
                          subtitle: '${a['ref'] ?? ''}  ${timeAgo(a['created_at'] as String)}',
                          trailing: a['amount'] == null ? null : Money.rs(asInt(a['amount'])),
                        );
                      }),
                  ]),
          ),
        ],
      ),
    );
  }
}
