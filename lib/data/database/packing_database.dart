import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local database. Schema changes use migrations; existing transactions remain intact.
class PackingDatabase {
  PackingDatabase._();

  /// Creates an isolated in-memory database for repository regression tests.
  static Future<PackingDatabase> createForTesting(Database database) async {
    final instance = PackingDatabase._();
    await instance._createSchema(database, schemaVersion);
    await database.execute('PRAGMA foreign_keys = ON');
    instance._database = database;
    return instance;
  }
  static final PackingDatabase instance = PackingDatabase._();
  static const int schemaVersion = 7;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'packing_pos.db'),
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE packing_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_no TEXT NOT NULL UNIQUE, receipt_id INTEGER,
        customer_name TEXT NOT NULL DEFAULT '', item_description TEXT NOT NULL DEFAULT '',
        quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0), unit_price INTEGER NOT NULL DEFAULT 0 CHECK(unit_price >= 0),
        length_cm REAL NOT NULL, width_cm REAL NOT NULL, height_cm REAL NOT NULL,
        calculation_snapshot TEXT NOT NULL, material_cost INTEGER NOT NULL DEFAULT 0,
        labor_cost INTEGER NOT NULL DEFAULT 0, overhead_cost INTEGER NOT NULL DEFAULT 0,
        selling_price INTEGER NOT NULL DEFAULT 0, paid_amount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'completed', 'cancelled')),
        note TEXT NOT NULL DEFAULT '', cancellation_reason TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER NOT NULL,
        material_id INTEGER, material_name_snapshot TEXT NOT NULL, unit_snapshot TEXT NOT NULL,
        calculated_quantity REAL NOT NULL, actual_quantity REAL NOT NULL,
        unit_price_snapshot INTEGER NOT NULL, subtotal INTEGER NOT NULL,
        adjustment_note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES packing_transactions(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0), payment_method TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES packing_transactions(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, unit TEXT NOT NULL,
        current_unit_price INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await _createServiceTypes(db);
    await _createReceiptTables(db);
    await _createCustomers(db);
    await _createCashTables(db);
    await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await _createIndexes(db);
  }

  Future<void> _createServiceTypes(Database db) async {
    await db.execute('''
      CREATE TABLE service_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        default_price INTEGER NOT NULL DEFAULT 0 CHECK(default_price >= 0),
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_service_types_active ON service_types(is_active, name)');
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('service_types', {
      'name': 'Packing Kayu', 'default_price': 0, 'is_active': 1,
      'created_at': now, 'updated_at': now,
    });
  }

  Future<void> _createCustomers(Database db) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_active_name ON customers(is_active, name)');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_created ON packing_transactions(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_receipt ON packing_transactions(receipt_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receipt_payments_receipt ON receipt_payments(receipt_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_status ON packing_transactions(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_material_usage_transaction ON transaction_materials(transaction_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_transaction ON transaction_payments(transaction_id)');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE packing_transactions ADD COLUMN cancellation_reason TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 3) await _createServiceTypes(db);
    if (oldVersion < 4) await _upgradeToReceiptHeaders(db);
    if (oldVersion < 5) {
      // Upgrades from v<4 create packing_receipts during v4 migration,
      // where discount_amount already exists. Guard each ALTER for that path.
      if (!await _hasColumn(db, 'packing_transactions', 'quantity')) {
        await db.execute('ALTER TABLE packing_transactions ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0)');
      }
      if (!await _hasColumn(db, 'packing_transactions', 'unit_price')) {
        await db.execute('ALTER TABLE packing_transactions ADD COLUMN unit_price INTEGER NOT NULL DEFAULT 0 CHECK(unit_price >= 0)');
        await db.execute('UPDATE packing_transactions SET unit_price = selling_price');
      }
      if (!await _hasColumn(db, 'packing_receipts', 'discount_amount')) {
        await db.execute('ALTER TABLE packing_receipts ADD COLUMN discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(discount_amount >= 0)');
      }
    }
    if (oldVersion < 6) await _createCustomers(db);
    if (oldVersion < 7) await _createCashTables(db);
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  /// Exposes the migration path to regression tests.
  Future<void> upgradeForTesting(Database db, int oldVersion, int newVersion) =>
      _upgrade(db, oldVersion, newVersion);

  Future<void> _createCashTables(Database db) async {
    await db.execute('''
      CREATE TABLE cash_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date_key TEXT NOT NULL UNIQUE,
        opening_balance INTEGER NOT NULL CHECK(opening_balance >= 0),
        expected_balance INTEGER,
        counted_balance INTEGER,
        difference INTEGER,
        status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'closed')),
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        closed_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        category TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES cash_sessions(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_expenses_session ON cash_expenses(session_id)');
  }

  Future<void> _createReceiptTables(Database db) async {
    await db.execute('''
      CREATE TABLE packing_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_no TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL DEFAULT '',
        total_amount INTEGER NOT NULL DEFAULT 0 CHECK(total_amount >= 0),
        discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(discount_amount >= 0),
        paid_amount INTEGER NOT NULL DEFAULT 0 CHECK(paid_amount >= 0),
        status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'completed', 'cancelled')),
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE receipt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        payment_method TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(receipt_id) REFERENCES packing_receipts(id) ON DELETE RESTRICT
      )
    ''');
  }

  Future<void> _upgradeToReceiptHeaders(Database db) async {
    await db.execute('ALTER TABLE packing_transactions ADD COLUMN receipt_id INTEGER REFERENCES packing_receipts(id)');
    await _createReceiptTables(db);
    final rows = await db.query('packing_transactions', orderBy: 'id ASC');
    for (final row in rows) {
      final transactionId = (row['id'] as num).toInt();
      final now = (row['created_at'] as String?) ?? DateTime.now().toUtc().toIso8601String();
      final paid = (row['paid_amount'] as num?)?.toInt() ?? 0;
      final total = (row['selling_price'] as num?)?.toInt() ?? 0;
      final receiptId = await db.insert('packing_receipts', {
        'receipt_no': row['receipt_no'],
        'customer_name': row['customer_name'] ?? '',
        'total_amount': total,
        'paid_amount': paid,
        'status': row['status'] == 'cancelled' ? 'cancelled' : (paid >= total ? 'completed' : 'open'),
        'note': row['note'] ?? '',
        'created_at': now,
        'updated_at': row['updated_at'] ?? now,
      });
      await db.update('packing_transactions', {'receipt_id': receiptId},
          where: 'id = ?', whereArgs: [transactionId]);
      final oldPayments = await db.query('transaction_payments',
          where: 'transaction_id = ?', whereArgs: [transactionId], orderBy: 'id ASC');
      for (final payment in oldPayments) {
        await db.insert('receipt_payments', {
          'receipt_id': receiptId,
          'amount': payment['amount'],
          'payment_method': payment['payment_method'],
          'note': payment['note'] ?? '',
          'created_at': payment['created_at'] ?? now,
        });
      }
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_receipt ON packing_transactions(receipt_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receipt_payments_receipt ON receipt_payments(receipt_id)');
  }
}
