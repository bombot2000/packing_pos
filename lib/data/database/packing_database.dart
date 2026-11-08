import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local database. Schema changes must use versioned migrations; never delete
/// the database on upgrade because it contains customer transactions.
class PackingDatabase {
  PackingDatabase._();
  static final PackingDatabase instance = PackingDatabase._();

  static const int schemaVersion = 1;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'packing_pos.db'),
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE packing_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_no TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL DEFAULT '',
        item_description TEXT NOT NULL DEFAULT '',
        length_cm REAL NOT NULL,
        width_cm REAL NOT NULL,
        height_cm REAL NOT NULL,
        calculation_snapshot TEXT NOT NULL,
        material_cost INTEGER NOT NULL DEFAULT 0,
        labor_cost INTEGER NOT NULL DEFAULT 0,
        overhead_cost INTEGER NOT NULL DEFAULT 0,
        selling_price INTEGER NOT NULL DEFAULT 0,
        paid_amount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open'
          CHECK(status IN ('open', 'completed', 'cancelled')),
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        material_id INTEGER,
        material_name_snapshot TEXT NOT NULL,
        unit_snapshot TEXT NOT NULL,
        calculated_quantity REAL NOT NULL,
        actual_quantity REAL NOT NULL,
        unit_price_snapshot INTEGER NOT NULL,
        subtotal INTEGER NOT NULL,
        adjustment_note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES packing_transactions(id)
          ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        amount INTEGER NOT NULL CHECK(amount > 0),
        payment_method TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES packing_transactions(id)
          ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        current_unit_price INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_transactions_created ON packing_transactions(created_at)');
    await db.execute('CREATE INDEX idx_transactions_status ON packing_transactions(status)');
    await db.execute('CREATE INDEX idx_material_usage_transaction ON transaction_materials(transaction_id)');
    await db.execute('CREATE INDEX idx_payments_transaction ON transaction_payments(transaction_id)');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // Add explicit migrations here when schemaVersion increases.
    // Deliberately no destructive fallback or drop-table behavior.
  }
}
