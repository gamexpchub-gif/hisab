import 'package:flutter/material.dart';

import '../core/books.dart';
import '../ui/widgets.dart';
import 'parties.dart';
import 'products.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Live<List<Alert>>(
      load: Books.notifications,
      builder: (context, items) => PageShell(
        title: 'Notifications',
        subtitle: items.isEmpty ? 'All caught up' : '${items.length} alerts need attention',
        children: [
          CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: items.isEmpty
                ? const EmptyState("You're all caught up")
                : Divided([
                    for (final n in items)
                      ListRow(
                        leading: Orb(
                          icon: n.kind == 'stock'
                              ? Icons.inventory_2_rounded
                              : n.kind == 'due'
                                  ? Icons.currency_rupee_rounded
                                  : Icons.local_shipping_rounded,
                          colors: (n.kind == 'stock' ? Palette.red : n.kind == 'due' ? Palette.amber : Palette.purple).icon,
                          bg: (n.kind == 'stock' ? Palette.red : n.kind == 'due' ? Palette.amber : Palette.purple).bg,
                          size: 44,
                        ),
                        title: n.title,
                        subtitle: n.text,
                        onTap: () => open(
                            context,
                            n.kind == 'stock'
                                ? ProductView(id: n.targetId)
                                : PartyView(type: n.kind == 'due' ? 'customer' : 'supplier', id: n.targetId)),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }
}
