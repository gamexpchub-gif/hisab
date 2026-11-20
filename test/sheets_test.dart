import 'package:flutter_test/flutter_test.dart';

import 'package:hisab/sheets/editor.dart' show showValue;
import 'package:hisab/sheets/formula.dart';
import 'package:hisab/sheets/workbook.dart';

void main() {
  GridSheet sheet(Map<String, String> cells) {
    final s = GridSheet('T');
    cells.forEach((ref, v) {
      final p = parseRef(ref)!;
      s.put(p.$1, p.$2, v);
    });
    return s;
  }

  Object? v(GridSheet s, String ref) {
    final p = parseRef(ref)!;
    return s.value(p.$1, p.$2);
  }

  test('references and names', () {
    expect(colName(0), 'A');
    expect(colName(25), 'Z');
    expect(colName(26), 'AA');
    expect(colIndex('AB'), 27);
    expect(parseRef('C12'), (11, 2));
    expect(parseRef(r'$B$3'), (2, 1));
    expect(parseRef('12'), isNull);
  });

  test('arithmetic, precedence, percent, text', () {
    final s = sheet({'A1': '10', 'A2': '₹2,500', 'A3': '18%', 'B1': '=A1+A2*2', 'B2': '=(A1+A2)*2', 'B3': '=2^3^2', 'B4': '=A2*A3', 'B5': '="Total: "&A1', 'B6': '=-A1+5', 'B7': '=10/4'});
    expect(v(s, 'A2'), 2500);
    expect(v(s, 'A3'), closeTo(.18, 1e-9));
    expect(v(s, 'B1'), 5010);
    expect(v(s, 'B2'), 5020);
    expect(v(s, 'B3'), 512);
    expect(v(s, 'B4'), closeTo(450, 1e-9));
    expect(v(s, 'B5'), 'Total: 10');
    expect(v(s, 'B6'), -5);
    expect(v(s, 'B7'), 2.5);
  });

  test('functions', () {
    final s = sheet({
      'A1': 'Rent', 'B1': '15000',
      'A2': 'Salary', 'B2': '20000',
      'A3': 'Rent', 'B3': '5000',
      'A4': 'Tea', 'B4': '',
      'C1': '=SUM(B1:B4)',
      'C2': '=AVERAGE(B1:B3)',
      'C3': '=MAX(B1:B3)-MIN(B1:B3)',
      'C4': '=COUNT(B1:B4)',
      'C5': '=COUNTA(A1:A4)',
      'C6': '=SUMIF(A1:A3,"Rent",B1:B3)',
      'C7': '=COUNTIF(B1:B3,">10000")',
      'C8': '=IF(C1>30000,"High","Low")',
      'C9': '=VLOOKUP("Salary",A1:B4,2,FALSE)',
      'C10': '=ROUND(10/3,2)',
      'C11': '=IFERROR(1/0,"none")',
      'C12': '=UPPER(LEFT(A2,3))',
      'C13': '=EMI(100000,12,12)',
      'C14': '=GST(1000,18)',
      'C15': '=MARGIN(1200,900)',
      'C16': '=AND(B1>0,B2>0)',
      'C17': '=MATCH("Tea",A1:A4,0)',
      'C18': '=INDEX(B1:B4,2)',
      'C19': '=LARGE(B1:B3,2)',
      'C20': '=CONCAT(A1,"-",A2)',
    });
    expect(v(s, 'C1'), 40000);
    expect(v(s, 'C2'), closeTo(13333.33, .01));
    expect(v(s, 'C3'), 15000);
    expect(v(s, 'C4'), 3);
    expect(v(s, 'C5'), 4);
    expect(v(s, 'C6'), 20000);
    expect(v(s, 'C7'), 2);
    expect(v(s, 'C8'), 'High');
    expect(v(s, 'C9'), 20000);
    expect(v(s, 'C10'), 3.33);
    expect(v(s, 'C11'), 'none');
    expect(v(s, 'C12'), 'SAL');
    expect(v(s, 'C13'), closeTo(8884.88, .01));
    expect(v(s, 'C14'), 180);
    expect(v(s, 'C15'), closeTo(.25, 1e-9));
    expect(v(s, 'C16'), true);
    expect(v(s, 'C17'), 4);
    expect(v(s, 'C18'), 20000);
    expect(v(s, 'C19'), 15000);
    expect(v(s, 'C20'), 'Rent-Salary');
  });

  test('errors and cycles', () {
    final s = sheet({'A1': '=1/0', 'A2': '=A3+1', 'A3': '=A2+1', 'A4': '=NOPE(1)', 'A5': '="a"*2', 'A6': '=A1+1'});
    expect(v(s, 'A1'), errDiv0);
    expect(v(s, 'A2'), isA<CellError>());
    expect(v(s, 'A4'), errName);
    expect(v(s, 'A5'), errValue);
    expect(v(s, 'A6'), errDiv0);
  });

  test('recalculates after edits, rows and columns keep references', () {
    final s = sheet({'A1': '1', 'A2': '2', 'A3': '=SUM(A1:A2)', 'B3': '=A3*10'});
    expect(v(s, 'B3'), 30);
    s.put(0, 0, '5');
    expect(v(s, 'A3'), 7);
    s.insertRow(0); // everything moves down one row
    expect(s.input(3, 0), '=SUM(A2:A3)');
    expect(v(s, 'B4'), 70);
    s.insertCol(0);
    expect(s.input(3, 2), '=B4*10');
    expect(v(s, 'C4'), 70);
    expect(GridSheet.offsetFormula(r'=A1+$B$1+B$2', 2, 1), r'=B3+$B$1+C$2');
  });

  test('sort keeps rows together', () {
    final s = sheet({'A1': 'Name', 'B1': 'Qty', 'A2': 'Pen', 'B2': '5', 'A3': 'Box', 'B3': '12', 'A4': 'Cup', 'B4': '1'});
    s.sortRows(1, 3, 1, asc: false);
    expect([s.input(1, 0), s.input(2, 0), s.input(3, 0)], ['Box', 'Pen', 'Cup']);
    expect(s.input(1, 1), '12');
  });

  test('display formats', () {
    expect(showValue(1234567.0, null), '12,34,567');
    expect(showValue(2.5, null), '2.5');
    expect(showValue(.25, Cell('', fmt: 'pct')), '25%');
    expect(showValue(1500.0, Cell('', fmt: 'inr')), '₹1,500.00');
    expect(showValue(true, null), 'TRUE');
  });

  test('workbook JSON round trip', () {
    final w = Workbook('x', 'Test');
    w.sheets.first.put(2, 3, '=1+1');
    w.sheets.first.style(2, 3).bold = true;
    final back = Workbook.from(w.toJson().map((k, v) => MapEntry(k, v)));
    expect(back.sheets.first.input(2, 3), '=1+1');
    expect(back.sheets.first.at(2, 3)!.bold, isTrue);
    expect(back.sheets.first.value(2, 3), 2);
  });
}
