import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All money columns are INTEGER paise.
class AppDb {
  static Database? _db;

  static Future<Database> get instance async => _db ??= await _open();

  /// Tests inject an in-memory database here.
  static void useDatabase(Database db) => _db = db;

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

  static const schemaVersion = 5;

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

  static const schema = <String>[
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
    '''CREATE TABLE accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      type TEXT NOT NULL, kind TEXT, is_system INTEGER NOT NULL DEFAULT 0)''',
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
      credit_limit INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''',
    '''CREATE TABLE suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, email TEXT,
      address TEXT, gstin TEXT, opening INTEGER NOT NULL DEFAULT 0,
      credit_limit INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''',
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
      unit_cost INTEGER NOT NULL, serial TEXT)''',
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
