import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All money columns are INTEGER paise.
class AppDb {
  static Database? _db;

  static Future<Database> get instance async => _db ??= await _open();

  /// Tests inject an in-memory database here.
  static void useDatabase(Database db) => _db = db;

  /// Path of the database file on the phone.
  static Future<String> path() async => p.join(await getDatabasesPath(), 'hisab.db');

  /// Closes the database (backup / restore); the next query reopens it.
  static Future<void> close() async {
    final d = _db;
    _db = null;
    await d?.close();
  }

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'hisab.db'),
      version: schemaVersion,
      onConfigure: configure,
      onCreate: create,
      onUpgrade: upgrade,
    );
  }

  static const schemaVersion = 11;

  static Future<void> upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN variant TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN mrp INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN image TEXT');
    }
    if (from < 3) {
      await db.execute('ALTER TABLE products ADD COLUMN warranty_months INTEGER NOT NULL DEFAULT 0');
    }
    if (from < 4) {
      await db.execute('ALTER TABLE purchases ADD COLUMN bill_image TEXT');
    }
    if (from < 5) {
      await db.execute('ALTER TABLE expenses ADD COLUMN image TEXT');
      await db.execute(_salePayments);
      await db.execute('INSERT INTO sale_payments (sale_id, account_id, amount) '
          'SELECT id, account_id, paid FROM sales WHERE paid > 0 AND account_id IS NOT NULL');
    }
    if (from < 6) {
      for (final t in ['customers', 'suppliers']) {
        for (final c in _partyColumns) {
          await db.execute('ALTER TABLE $t ADD COLUMN $c TEXT');
        }
      }
      await db.execute(_cashLends);
      await db.execute(_partyDues);
    }
    if (from < 7) {
      for (final c in ['bank_name TEXT', 'acc_no TEXT', 'holder TEXT', 'ifsc TEXT', 'card_type TEXT', 'network TEXT',
        'credit_limit INTEGER NOT NULL DEFAULT 0', 'color INTEGER', 'bill_days INTEGER NOT NULL DEFAULT 40']) {
        await db.execute('ALTER TABLE accounts ADD COLUMN $c');
      }
      await db.execute("UPDATE accounts SET bank_name = 'State Bank of India', card_type = 'savings' WHERE code = '1010'");
      await db.execute("UPDATE accounts SET card_type = 'cash' WHERE code = '1000'");
      await db.execute("UPDATE accounts SET card_type = 'upi' WHERE code = '1020'");
    }
    if (from < 8) {
      await db.execute(_saleReturns);
      await db.execute(_saleReturnItems);
      await db.execute("INSERT OR IGNORE INTO accounts (code, name, type, kind, is_system) VALUES ('4300', 'Sale Return Charges', 'income', NULL, 1)");
    }
    if (from < 9) {
      await db.execute('ALTER TABLE sale_items ADD COLUMN opp_id TEXT');
    }
    if (from < 10) {
      await db.execute(_emiPlans);
      await db.execute(_emiInstallments);
    }
    if (from < 11) {
      await db.execute(_imeiModels);
    }
  }

  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> create(Database db, int version) async {
    final batch = db.batch();
    for (final s in schema) {
      batch.execute(s);
    }
    await batch.commit(noResult: true);
    await seed(db);
  }

  static const _salePayments = '''CREATE TABLE sale_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL REFERENCES sales(id),
      account_id INTEGER NOT NULL REFERENCES accounts(id), amount INTEGER NOT NULL)''';

  static const _saleReturns = '''CREATE TABLE sale_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, date TEXT NOT NULL,
      sale_id INTEGER NOT NULL REFERENCES sales(id), customer_id INTEGER REFERENCES customers(id),
      value INTEGER NOT NULL, refund INTEGER NOT NULL, deduction INTEGER NOT NULL, cost INTEGER NOT NULL,
      account_id INTEGER REFERENCES accounts(id), restock INTEGER NOT NULL DEFAULT 1, reason TEXT,
      note TEXT, created_at TEXT NOT NULL)''';

  static const _saleReturnItems = '''CREATE TABLE sale_return_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, return_id INTEGER NOT NULL REFERENCES sale_returns(id),
      sale_item_id INTEGER NOT NULL REFERENCES sale_items(id), product_id INTEGER NOT NULL,
      name TEXT NOT NULL, qty INTEGER NOT NULL, value INTEGER NOT NULL, tax INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL, serial TEXT)''';

  static const _emiPlans = '''CREATE TABLE emi_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER REFERENCES sales(id),
      customer_id INTEGER NOT NULL REFERENCES customers(id), kind TEXT NOT NULL, financer TEXT,
      opp_id TEXT, loan_no TEXT, product TEXT, imei TEXT, price INTEGER NOT NULL DEFAULT 0,
      down_payment INTEGER NOT NULL DEFAULT 0, emi INTEGER NOT NULL, months INTEGER NOT NULL,
      start_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active', note TEXT, created_at TEXT NOT NULL)''';

  static const _emiInstallments = '''CREATE TABLE emi_installments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL REFERENCES emi_plans(id),
      n INTEGER NOT NULL, due_date TEXT NOT NULL, amount INTEGER NOT NULL,
      paid_amount INTEGER NOT NULL DEFAULT 0, paid_on TEXT, payment_id INTEGER, account_id INTEGER)''';

  /// Phone models learned from IMEIs (first 8 digits = TAC).
  static const _imeiModels = '''CREATE TABLE imei_models (
      tac TEXT PRIMARY KEY, product_id INTEGER, name TEXT, brand TEXT, source TEXT, updated_at TEXT)''';

  static const _cashLends = '''CREATE TABLE cash_lends (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
      party_type TEXT NOT NULL, party_id INTEGER NOT NULL, account_id INTEGER NOT NULL REFERENCES accounts(id),
      amount INTEGER NOT NULL, date TEXT NOT NULL, reason TEXT, created_at TEXT NOT NULL)''';

  static const _partyDues = '''CREATE TABLE party_dues (
      id INTEGER PRIMARY KEY AUTOINCREMENT, party_type TEXT NOT NULL, party_id INTEGER NOT NULL,
      amount INTEGER NOT NULL, due_date TEXT NOT NULL, note TEXT, status TEXT NOT NULL DEFAULT 'open',
      created_at TEXT NOT NULL)''';

  static const _partyColumns = ['photo', 'alt_phone', 'aadhaar', 'pan', 'aadhaar_img', 'pan_img', 'notes'];

  static const schema = <String>[
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
    '''CREATE TABLE accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      type TEXT NOT NULL, kind TEXT, is_system INTEGER NOT NULL DEFAULT 0,
      bank_name TEXT, acc_no TEXT, holder TEXT, ifsc TEXT, card_type TEXT, network TEXT,
      credit_limit INTEGER NOT NULL DEFAULT 0, color INTEGER, bill_days INTEGER NOT NULL DEFAULT 40)''',
    '''CREATE TABLE journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, ref TEXT NOT NULL UNIQUE,
      narration TEXT, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, created_at TEXT NOT NULL,
      UNIQUE (source_type, source_id))''',
    '''CREATE TABLE journal_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_id INTEGER NOT NULL REFERENCES journal_entries(id),
      account_id INTEGER NOT NULL REFERENCES accounts(id),
      debit INTEGER NOT NULL DEFAULT 0, credit INTEGER NOT NULL DEFAULT 0,
      party_type TEXT, party_id INTEGER)''',
    'CREATE INDEX ix_jl_account ON journal_lines(account_id)',
    'CREATE INDEX ix_jl_party ON journal_lines(party_type, party_id)',
    'CREATE INDEX ix_je_date ON journal_entries(date)',
    'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)',
    '''CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, brand TEXT,
      category_id INTEGER REFERENCES categories(id), sku TEXT UNIQUE, hsn TEXT,
      gst_bp INTEGER NOT NULL DEFAULT 1800, cost INTEGER NOT NULL DEFAULT 0,
      price INTEGER NOT NULL DEFAULT 0, stock INTEGER NOT NULL DEFAULT 0,
      low_stock INTEGER NOT NULL DEFAULT 2, condition TEXT NOT NULL DEFAULT 'new',
      created_at TEXT NOT NULL, variant TEXT, mrp INTEGER NOT NULL DEFAULT 0, image TEXT,
      warranty_months INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, email TEXT,
      address TEXT, gstin TEXT, opening INTEGER NOT NULL DEFAULT 0,
      credit_limit INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, photo TEXT, alt_phone TEXT, aadhaar TEXT, pan TEXT, aadhaar_img TEXT, pan_img TEXT, notes TEXT)''',
    '''CREATE TABLE suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, email TEXT,
      address TEXT, gstin TEXT, opening INTEGER NOT NULL DEFAULT 0,
      credit_limit INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, photo TEXT, alt_phone TEXT, aadhaar TEXT, pan TEXT, aadhaar_img TEXT, pan_img TEXT, notes TEXT)''',
    '''CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, date TEXT NOT NULL,
      customer_id INTEGER REFERENCES customers(id), subtotal INTEGER NOT NULL, discount INTEGER NOT NULL,
      tax INTEGER NOT NULL, total INTEGER NOT NULL, paid INTEGER NOT NULL, cogs INTEGER NOT NULL,
      account_id INTEGER REFERENCES accounts(id), note TEXT, created_at TEXT NOT NULL)''',
    'CREATE INDEX ix_sales_date ON sales(date)',
    '''CREATE TABLE sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL REFERENCES sales(id),
      product_id INTEGER NOT NULL REFERENCES products(id), name TEXT NOT NULL, qty INTEGER NOT NULL,
      rate INTEGER NOT NULL, gst_bp INTEGER NOT NULL, amount INTEGER NOT NULL, tax INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL, serial TEXT, opp_id TEXT)''',
    '''CREATE TABLE purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, bill_no TEXT, date TEXT NOT NULL,
      supplier_id INTEGER NOT NULL REFERENCES suppliers(id), subtotal INTEGER NOT NULL, tax INTEGER NOT NULL,
      total INTEGER NOT NULL, paid INTEGER NOT NULL, account_id INTEGER REFERENCES accounts(id),
      note TEXT, created_at TEXT NOT NULL, bill_image TEXT)''',
    'CREATE INDEX ix_purchases_date ON purchases(date)',
    '''CREATE TABLE purchase_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL REFERENCES purchases(id),
      product_id INTEGER NOT NULL REFERENCES products(id), name TEXT NOT NULL, qty INTEGER NOT NULL,
      rate INTEGER NOT NULL, gst_bp INTEGER NOT NULL, amount INTEGER NOT NULL, tax INTEGER NOT NULL,
      serial TEXT)''',
    '''CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
      date TEXT NOT NULL, party_type TEXT NOT NULL, party_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL REFERENCES accounts(id), amount INTEGER NOT NULL,
      reference TEXT, note TEXT, created_at TEXT NOT NULL)''',
    '''CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, date TEXT NOT NULL,
      head_id INTEGER NOT NULL REFERENCES accounts(id), account_id INTEGER NOT NULL REFERENCES accounts(id),
      amount INTEGER NOT NULL, note TEXT, created_at TEXT NOT NULL, image TEXT)''',
    _salePayments,
    _cashLends,
    _partyDues,
    _saleReturns,
    _saleReturnItems,
    _emiPlans,
    _emiInstallments,
    _imeiModels,
    '''CREATE TABLE transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT, number TEXT NOT NULL UNIQUE, date TEXT NOT NULL,
      from_id INTEGER NOT NULL REFERENCES accounts(id), to_id INTEGER NOT NULL REFERENCES accounts(id),
      amount INTEGER NOT NULL, note TEXT, created_at TEXT NOT NULL)''',
    '''CREATE TABLE audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, message TEXT NOT NULL, ref TEXT,
      amount INTEGER, created_at TEXT NOT NULL)''',
  ];

  /// Chart of accounts: code, name, type, kind.
  static const chart = <List<String?>>[
    ['1000', 'Cash in Hand', 'asset', 'cash'],
    ['1010', 'SBI Bank', 'asset', 'bank'],
    ['1020', 'UPI Collection', 'asset', 'upi'],
    ['1100', 'Accounts Receivable', 'asset', null],
    ['1200', 'Inventory', 'asset', null],
    ['1300', 'GST Input Credit', 'asset', null],
    ['2000', 'Accounts Payable', 'liability', null],
    ['2100', 'GST Output Payable', 'liability', null],
    ['3000', 'Owner Capital', 'equity', null],
    ['3100', 'Owner Drawings', 'equity', null],
    ['3900', 'Opening Balance Equity', 'equity', null],
    ['4000', 'Sales', 'income', null],
    ['4100', 'Service & Repair Income', 'income', null],
    ['4200', 'Other Income', 'income', null],
    ['4300', 'Sale Return Charges', 'income', null],
    ['5000', 'Cost of Goods Sold', 'expense', null],
    ['6000', 'Shop Rent', 'expense', 'expense'],
    ['6010', 'Electricity Bill', 'expense', 'expense'],
    ['6020', 'Staff Salary', 'expense', 'expense'],
    ['6030', 'Transport & Courier', 'expense', 'expense'],
    ['6040', 'Internet & Phone', 'expense', 'expense'],
    ['6050', 'Marketing & Ads', 'expense', 'expense'],
    ['6060', 'Repair & Maintenance', 'expense', 'expense'],
    ['6070', 'Bank Charges', 'expense', 'expense'],
    ['6080', 'Food & Refreshment', 'expense', 'expense'],
    ['6090', 'Miscellaneous Expense', 'expense', 'expense'],
  ];

  static Future<void> seed(DatabaseExecutor db) async {
    for (final a in chart) {
      await db.insert('accounts', {'code': a[0], 'name': a[1], 'type': a[2], 'kind': a[3], 'is_system': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.execute("UPDATE accounts SET bank_name = 'State Bank of India', card_type = 'savings' WHERE code = '1010' AND card_type IS NULL");
    await db.execute("UPDATE accounts SET card_type = 'cash' WHERE code = '1000' AND card_type IS NULL");
    await db.execute("UPDATE accounts SET card_type = 'upi' WHERE code = '1020' AND card_type IS NULL");
    for (final c in ['Mobile', 'Laptop', 'Accessories', 'Tablet', 'Desktop / PC']) {
      await db.insert('categories', {'name': c}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final kv in {
      'business_name': 'GAMEX PC Hub',
      'tagline': 'One Stop Mobile & Laptop',
      'owner_name': 'Super Admin',
    }.entries) {
      await db.insert('settings', {'key': kv.key, 'value': kv.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
