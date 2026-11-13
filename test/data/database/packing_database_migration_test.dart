import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/data/database/packing_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('upgrade dari v3 ke v7 tidak menggandakan kolom dan menjaga data', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
        status TEXT NOT NULL DEFAULT 'open',
        note TEXT NOT NULL DEFAULT '',
        cancellation_reason TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.insert('packing_transactions', {
      'receipt_no': 'OLD-1',
      'customer_name': 'Pelanggan Lama',
      'length_cm': 10,
      'width_cm': 20,
      'height_cm': 30,
      'calculation_snapshot': '{}',
      'selling_price': 50000,
      'paid_amount': 20000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    await db.insert('transaction_payments', {
      'transaction_id': 1,
      'amount': 20000,
      'created_at': '2026-01-01T00:00:00Z',
    });

    await PackingDatabase.instance.upgradeForTesting(
      db,
      3,
      PackingDatabase.schemaVersion,
    );

    final receipts = await db.query('packing_receipts');
    expect(receipts, hasLength(1));
    expect(receipts.single['discount_amount'], 0);
    expect(receipts.single['paid_amount'], 20000);
    expect(receipts.single['total_amount'], 50000);

    final job = (await db.query('packing_transactions')).single;
    expect(job['quantity'], 1);
    expect(job['unit_price'], 50000);
    expect(job['receipt_id'], receipts.single['id']);
    expect(await db.query('receipt_payments'), hasLength(1));
    expect(await db.query('customers'), isEmpty);
    expect(await db.query('cash_sessions'), isEmpty);
    await db.close();
  });

  test('upgrade dari v7 ke v8 menambah tabel refund tanpa menghapus data lama', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await PackingDatabase.createForTesting(db);
    await db.insert('materials', {
      'name': 'Kayu lama',
      'unit': 'batang',
      'current_unit_price': 12000,
      'is_active': 1,
      'created_at': '2026-11-13T00:00:00.000Z',
      'updated_at': '2026-11-13T00:00:00.000Z',
    });

    await db.execute('DROP TABLE payment_refunds');
    await PackingDatabase.instance.upgradeForTesting(db, 7, 8);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'payment_refunds'",
    );
    expect(tables, hasLength(1));
    final materials = await db.query('materials');
    expect(materials, hasLength(1));
    expect(materials.single['name'], 'Kayu lama');
    expect(await db.query('payment_refunds'), isEmpty);
    await db.close();
  });


}
