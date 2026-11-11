import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hisab/ui/art.dart';
import 'package:hisab/ui/widgets.dart';

void main() {
  testWidgets('illustrations and logo render without errors', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          const LogoTile(),
          for (final k in ArtKind.values) Art(k, width: 80),
          const Kpi('Today', 123456, accent: true),
        ]),
      ),
    ));
    expect(find.text('GameX'), findsOneWidget);
    expect(find.text('₹1,234.56'), findsOneWidget);
  });
}
