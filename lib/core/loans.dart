part of 'books.dart';

const loanCode = '2500', capitalCode = '3000', interestCode = '6100';

/// One row of a loan's repayment schedule.
class LoanRow {
  final int n;
  final String date;
  final int emi, interest, principal, balance;
  const LoanRow(this.n, this.date, this.emi, this.interest, this.principal, this.balance);
}

/// Loans and investments: money brought into the business from a bank,
/// NBFC, a person or family (loans, repaid with interest) or the owner /
/// a partner (capital). Each is posted in double entry:
///   loan received       Dr Cash/Bank       Cr Loans & Borrowings
///   investment received Dr Cash/Bank       Cr Owner Capital
///   repayment           Dr Loans (principal) + Dr Loan Interest   Cr Cash/Bank
class Loans {
  static const sources = <String, String>{
    'bank': 'Bank',
    'nbfc': 'NBFC / Finance',
    'person': 'Person / Friend',
    'family': 'Family',
    'supplier': 'Supplier credit',
    'investor': 'Investor / Partner',
    'owner': 'Owner (own money)',
    'other': 'Other',
  };

  /// Monthly instalment. Reducing balance uses the standard EMI formula;
  /// flat adds the whole interest up front; none splits the principal.
  static int emi(int principal, int rateBp, int months, String type) {
    if (months <= 0) return 0;
    final r = rateBp / 10000 / 12;
    if (type == 'none' || rateBp == 0) return (principal / months).ceil();
    if (type == 'flat') return ((principal + principal * rateBp / 10000 * months / 12) / months).round();
    final f = math.pow(1 + r, months);
    return (principal * r * f / (f - 1)).round();
  }

  /// The full schedule from the loan's terms (not from what was paid).
  static List<LoanRow> schedule(Rec l) {
    final p = asInt(l['principal']), months = asInt(l['months']), bp = asInt(l['rate_bp']);
    final type = '${l['interest_type']}';
    if (months <= 0 || '${l['kind']}' != 'loan') return const [];
    final e = asInt(l['emi']) > 0 ? asInt(l['emi']) : emi(p, bp, months, type);
    final first = DateTime.parse('${l['first_due'] ?? l['start_date']}');
    final out = <LoanRow>[];
    var bal = p;
    final flatInt = type == 'flat' ? (p * bp / 10000 * months / 12 / months).round() : 0;
    for (var n = 1; n <= months; n++) {
      final interest = type == 'reducing' && bp > 0 ? (bal * bp / 10000 / 12).round() : flatInt;
      var principal = e - interest;
      if (n == months || principal > bal) principal = bal;
      bal -= principal;
      out.add(LoanRow(n, ymd(addMonths(first, n - 1)), principal + interest, interest, principal, bal));
    }
    return out;
  }

  /// Loans with what is paid, outstanding and the next instalment.
  static Future<List<Rec>> list({int? id}) async {
    final rows = await Books.query(
        'SELECT l.*, a.name AS account, '
        '(SELECT IFNULL(SUM(principal),0) FROM loan_payments p WHERE p.loan_id = l.id) AS paid_principal, '
        '(SELECT IFNULL(SUM(interest),0) FROM loan_payments p WHERE p.loan_id = l.id) AS paid_interest, '
        '(SELECT COUNT(*) FROM loan_payments p WHERE p.loan_id = l.id) AS paid_n, '
        '(SELECT MAX(date) FROM loan_payments p WHERE p.loan_id = l.id) AS last_paid '
        'FROM loans l LEFT JOIN accounts a ON a.id = l.account_id '
        '${id == null ? '' : 'WHERE l.id = ? '}ORDER BY l.status, l.start_date DESC, l.id DESC',
        id == null ? null : [id]);
    return [
      for (final r in rows)
        () {
          final m = Map<String, Object?>.from(r);
          final out = asInt(r['principal']) - asInt(r['paid_principal']);
          m['outstanding'] = out < 0 ? 0 : out;
          if (r['kind'] == 'loan' && r['status'] == 'active' && asInt(r['months']) > 0) {
            final s = schedule(r);
            final paid = asInt(r['paid_n']);
            if (paid < s.length) {
              m['next_due'] = s[paid].date;
              m['next_emi'] = s[paid].emi;
            }
          }
          return m;
        }(),
    ];
  }

  static Future<Rec?> get(int id) async {
    final l = await list(id: id);
    return l.isEmpty ? null : l.first;
  }

  static Future<List<Rec>> payments(int loanId) => Books.query(
      'SELECT p.*, a.name AS account FROM loan_payments p JOIN accounts a ON a.id = p.account_id WHERE p.loan_id = ? ORDER BY p.date DESC, p.id DESC',
      [loanId]);

  /// Suggested split of the next payment into principal and interest.
  static (int, int) suggest(Rec l) {
    final out = asInt(l['outstanding']);
    if (l['kind'] != 'loan' || asInt(l['months']) <= 0) return (out, 0);
    final s = schedule(l);
    final n = asInt(l['paid_n']);
    if (n >= s.length) return (out, 0);
    final bp = asInt(l['rate_bp']);
    final interest = l['interest_type'] == 'reducing' && bp > 0 ? (out * bp / 10000 / 12).round() : s[n].interest;
    var principal = s[n].emi - interest;
    if (principal > out || n == s.length - 1) principal = out;
    if (principal < 0) principal = 0;
    return (principal, interest);
  }

  static Future<int> create({
    required String kind, // loan | investment
    required String source,
    required String lender,
    String? phone,
    required int principal,
    required int accountId,
    int rateBp = 0,
    String interestType = 'reducing',
    int months = 0,
    int emi = 0,
    String? date,
    String? firstDue,
    String? purpose,
    String? note,
  }) {
    return Books._write((x) async {
      if (lender.trim().isEmpty) throw AccountingError('Kar kach theke taka elo — naam likhun');
      if (principal <= 0) throw AccountingError('Amount must be greater than zero');
      if (rateBp < 0 || rateBp > 10000) throw AccountingError('Interest rate must be between 0% and 100%');
      final when = date ?? ymd(DateTime.now());
      final isLoan = kind == 'loan';
      final number = await Books._nextNumber(x, 'loans', isLoan ? 'LN' : 'INV');
      final e = isLoan && months > 0 ? (emi > 0 ? emi : Loans.emi(principal, rateBp, months, interestType)) : 0;
      final id = await x.insert('loans', {
        'number': number,
        'kind': kind,
        'source': source,
        'lender': lender.trim(),
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'principal': principal,
        'rate_bp': isLoan ? rateBp : 0,
        'interest_type': isLoan ? interestType : 'none',
        'months': isLoan ? months : 0,
        'emi': e,
        'start_date': when,
        'first_due': isLoan && months > 0 ? (firstDue ?? ymd(addMonths(DateTime.parse(when), 1))) : null,
        'account_id': accountId,
        'purpose': (purpose ?? '').trim().isEmpty ? null : purpose!.trim(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'status': 'active',
        'created_at': Books._now(),
      });
      final credit = await Books.accountId_(x, isLoan ? loanCode : capitalCode);
      await Books.post(x, 'loan', id, when, isLoan ? 'Loan received from ${lender.trim()}' : 'Capital invested by ${lender.trim()}',
          [JL(accountId, principal, 0), JL(credit, 0, principal)]);
      await Books._log(x, 'receipt', isLoan ? 'Loan from ${lender.trim()}' : 'Investment by ${lender.trim()}', number, principal);
      return id;
    });
  }

  /// Repays a loan (principal + interest) or returns investment capital.
  static Future<int> pay(int loanId, {required int principal, int interest = 0, required int accountId, String? date, String? note}) {
    return Books._write((x) async {
      final l = await x.query('loans', where: 'id = ?', whereArgs: [loanId]);
      if (l.isEmpty) throw AccountingError('Loan not found');
      final loan = l.first;
      final paid = asInt((await x.rawQuery('SELECT IFNULL(SUM(principal),0) AS v FROM loan_payments WHERE loan_id = ?', [loanId])).first['v']);
      final out = asInt(loan['principal']) - paid;
      if (principal < 0 || interest < 0 || principal + interest <= 0) throw AccountingError('Amount must be greater than zero');
      if (principal > out) throw AccountingError('Principal is more than the outstanding ${Money.rs(out)}');
      final isLoan = loan['kind'] == 'loan';
      if (!isLoan && interest > 0) throw AccountingError('Investment-e interest hoy na — profit share ta expense hisebe likhun');
      final when = date ?? ymd(DateTime.now());
      final number = await Books._nextNumber(x, 'loan_payments', 'LP');
      final id = await x.insert('loan_payments', {
        'loan_id': loanId,
        'number': number,
        'date': when,
        'principal': principal,
        'interest': interest,
        'account_id': accountId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'created_at': Books._now(),
      });
      final lender = '${loan['lender']}';
      await Books.post(x, 'loan_pay', id, when, isLoan ? 'Loan repayment to $lender' : 'Capital returned to $lender', [
        JL(await Books.accountId_(x, isLoan ? loanCode : capitalCode), principal, 0),
        JL(await Books.accountId_(x, interestCode), interest, 0),
        JL(accountId, 0, principal + interest),
      ]);
      if (principal == out) await x.update('loans', {'status': 'closed'}, where: 'id = ?', whereArgs: [loanId]);
      await Books._log(x, 'payment', isLoan ? 'Loan EMI to $lender' : 'Capital returned to $lender', number, principal + interest);
      return id;
    });
  }

  static Future<void> deletePayment(int id) => Books._write((x) async {
        final p = await x.query('loan_payments', where: 'id = ?', whereArgs: [id]);
        if (p.isEmpty) return;
        await Books._unpost(x, 'loan_pay', id);
        await x.delete('loan_payments', where: 'id = ?', whereArgs: [id]);
        await x.update('loans', {'status': 'active'}, where: 'id = ?', whereArgs: [p.first['loan_id']]);
      });

  static Future<void> delete(int id) => Books._write((x) async {
        for (final p in await x.query('loan_payments', columns: ['id'], where: 'loan_id = ?', whereArgs: [id])) {
          await Books._unpost(x, 'loan_pay', asInt(p['id']));
        }
        await x.delete('loan_payments', where: 'loan_id = ?', whereArgs: [id]);
        await Books._unpost(x, 'loan', id);
        await x.delete('loans', where: 'id = ?', whereArgs: [id]);
        await Books._log(x, 'payment', 'Loan deleted', null, null);
      });

  static Future<void> setStatus(int id, String status) =>
      Books._write((x) => x.update('loans', {'status': status}, where: 'id = ?', whereArgs: [id]));
}
