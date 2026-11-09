import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/packing_database.dart';

class MaterialUsageDraft {
  const MaterialUsageDraft({
    this.materialId,
    required this.name,
    required this.unit,
    required this.calculatedQuantity,
    double? actualQuantity,
    required this.unitPrice,
    this.adjustmentNote = '',
  }) : actualQuantity = actualQuantity ?? calculatedQuantity;

  final int? materialId;
  final String name;
  final String unit;
  final double calculatedQuantity;
  final double actualQuantity;
  final int unitPrice;
  final String adjustmentNote;

  int get subtotal => (actualQuantity * unitPrice).round();
}

class PackingTransactionDraft {
  const PackingTransactionDraft({
    this.customerName = '',
    this.itemDescription = '',
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.calculationSnapshot,
    this.materialCost = 0,
    this.laborCost = 0,
    this.overheadCost = 0,
    this.sellingPrice = 0,
    this.note = '',
    this.materials = const [],
  });

  final String customerName;
  final String itemDescription;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  /// Immutable JSON snapshot of face settings and calculation output.
  final Map<String, Object?> calculationSnapshot;
  final int materialCost;
  final int laborCost;
  final int overheadCost;
  final int sellingPrice;
  final String note;
  final List<MaterialUsageDraft> materials;
}

class PackingTransactionRepository {
  PackingTransactionRepository({PackingDatabase? database})
      : _database = database ?? PackingDatabase.instance;

  final PackingDatabase _database;


  /// Daftar master bahan. Secara default hanya bahan aktif yang ditampilkan.
  Future<List<Map<String, Object?>>> listMaterials({bool activeOnly = true}) async {
    final db = await _database.database;
    return db.query('materials',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name COLLATE NOCASE ASC');
  }

  /// Simpan master bahan tanpa mengubah snapshot transaksi yang sudah ada.
  Future<int> saveMaterial({
    int? id,
    required String name,
    required String unit,
    required int currentUnitPrice,
  }) async {
    final cleanName = name.trim();
    final cleanUnit = unit.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama bahan wajib diisi.');
    if (cleanUnit.isEmpty) throw ArgumentError('Satuan bahan wajib diisi.');
    if (currentUnitPrice < 0) throw ArgumentError('Harga tidak boleh negatif.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    if (id == null) {
      return db.insert('materials', {
        'name': cleanName, 'unit': cleanUnit,
        'current_unit_price': currentUnitPrice, 'is_active': 1,
        'created_at': now, 'updated_at': now,
      });
    }
    final changed = await db.update('materials', {
      'name': cleanName, 'unit': cleanUnit,
      'current_unit_price': currentUnitPrice, 'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
    if (changed == 0) throw StateError('Bahan tidak ditemukan.');
    return id;
  }

  /// Nonaktifkan secara lunak; bahan dan transaksi historis tidak dihapus.
  Future<void> deactivateMaterial(int id) async {
    final db = await _database.database;
    final changed = await db.update('materials', {
      'is_active': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ? AND is_active = 1', whereArgs: [id]);
    if (changed == 0) {
      throw StateError('Bahan tidak ditemukan atau sudah nonaktif.');
    }
  }

  /// Saves header and material snapshots atomically. A failure rolls back all
  /// rows, so an incomplete receipt is never left in the local database.
  Future<String> save(PackingTransactionDraft draft) async {
    _validate(draft);
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.transaction((txn) async {
      final temporaryReceipt = 'PENDING-${DateTime.now().microsecondsSinceEpoch}';
      final id = await txn.insert('packing_transactions', {
        'receipt_no': temporaryReceipt,
        'customer_name': draft.customerName.trim(),
        'item_description': draft.itemDescription.trim(),
        'length_cm': draft.lengthCm,
        'width_cm': draft.widthCm,
        'height_cm': draft.heightCm,
        'calculation_snapshot': jsonEncode(draft.calculationSnapshot),
        'material_cost': draft.materialCost,
        'labor_cost': draft.laborCost,
        'overhead_cost': draft.overheadCost,
        'selling_price': draft.sellingPrice,
        'paid_amount': 0,
        'status': 'open',
        'note': draft.note.trim(),
        'created_at': now,
        'updated_at': now,
      });

      final date = DateTime.now();
      final receipt = 'PKG-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${id.toString().padLeft(6, '0')}';
      await txn.update(
        'packing_transactions',
        {'receipt_no': receipt, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );

      for (final material in draft.materials) {
        await txn.insert('transaction_materials', {
          'transaction_id': id,
          'material_id': material.materialId,
          'material_name_snapshot': material.name.trim(),
          'unit_snapshot': material.unit.trim(),
          'calculated_quantity': material.calculatedQuantity,
          'actual_quantity': material.actualQuantity,
          'unit_price_snapshot': material.unitPrice,
          'subtotal': material.subtotal,
          'adjustment_note': material.adjustmentNote.trim(),
          'created_at': now,
        });
      }
      return receipt;
    });
  }

  Future<List<Map<String, Object?>>> listRecent({int limit = 100}) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Harus antara 1 dan 500.');
    }
    final db = await _database.database;
    return db.query(
      'packing_transactions',
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> findByReceipt(String receiptNo) async {
    final db = await _database.database;
    final rows = await db.query(
      'packing_transactions',
      where: 'receipt_no = ?',
      whereArgs: [receiptNo],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> materialsFor(int transactionId) async {
    final db = await _database.database;
    return db.query(
      'transaction_materials',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'id',
    );
  }


  /// Records a payment and refreshes the cached paid balance atomically.
  /// Overpayments and payments on cancelled transactions are rejected.
  Future<void> addPayment({
    required int transactionId,
    required int amount,
    required String paymentMethod,
    String note = '',
  }) async {
    if (amount <= 0) throw ArgumentError('Nominal pembayaran harus lebih dari nol.');
    if (paymentMethod.trim().isEmpty) throw ArgumentError('Metode pembayaran wajib dipilih.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'packing_transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Transaksi tidak ditemukan.');
      final transaction = rows.first;
      if (transaction['status'] == 'cancelled') {
        throw StateError('Transaksi yang dibatalkan tidak dapat menerima pembayaran.');
      }
      final paid = (transaction['paid_amount'] as num).toInt();
      final total = (transaction['selling_price'] as num).toInt();
      if (amount > total - paid) {
        throw ArgumentError('Pembayaran melebihi sisa tagihan.');
      }
      await txn.insert('transaction_payments', {
        'transaction_id': transactionId,
        'amount': amount,
        'payment_method': paymentMethod.trim(),
        'note': note.trim(),
        'created_at': now,
      });
      final newPaid = paid + amount;
      await txn.update(
        'packing_transactions',
        {
          'paid_amount': newPaid,
          'status': newPaid >= total ? 'completed' : 'open',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    });
  }

  Future<List<Map<String, Object?>>> paymentsFor(int transactionId) async {
    final db = await _database.database;
    return db.query(
      'transaction_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'id DESC',
    );
  }

  Future<void> cancel(int transactionId, {String reason = ''}) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await db.update(
      'packing_transactions',
      {
        'status': 'cancelled',
        'note': reason.trim().isEmpty ? 'Transaksi dibatalkan' : reason.trim(),
        'updated_at': now,
      },
      where: "id = ? AND status != 'cancelled'",
      whereArgs: [transactionId],
    );
    if (changed == 0) throw StateError('Transaksi tidak ditemukan atau sudah dibatalkan.');
  }


  /// Ringkasan laporan lintas transaksi. Transaksi batal tidak dihitung sebagai
  /// penjualan, tetapi tetap tersimpan pada riwayat.
  Future<Map<String, Object?>> reportSummary() async {
    final db = await _database.database;
    final totals = await db.rawQuery('''
      SELECT
        COUNT(*) AS transaction_count,
        COALESCE(SUM(selling_price), 0) AS sales_total,
        COALESCE(SUM(paid_amount), 0) AS paid_total,
        COALESCE(SUM(selling_price - paid_amount), 0) AS receivable_total,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
        SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) AS open_count,
        (SELECT COUNT(*) FROM packing_transactions WHERE status = 'cancelled') AS cancelled_count
      FROM packing_transactions
      WHERE status != 'cancelled'
    ''');
    final materials = await db.rawQuery('''
      SELECT material_name_snapshot AS name, unit_snapshot AS unit,
        COALESCE(SUM(actual_quantity), 0) AS quantity,
        COALESCE(SUM(subtotal), 0) AS cost
      FROM transaction_materials
      INNER JOIN packing_transactions
        ON packing_transactions.id = transaction_materials.transaction_id
      WHERE packing_transactions.status != 'cancelled'
      GROUP BY material_name_snapshot, unit_snapshot
      ORDER BY cost DESC, name COLLATE NOCASE
    ''');
    return {
      'totals': totals.first,
      'materials': materials,
    };
  }

  /// Portable JSON backup. IDs and historical price snapshots are preserved.
  Future<Map<String, Object?>> exportBackup() async {
    final db = await _database.database;
    Future<List<Map<String, Object?>>> rows(String table) =>
        db.query(table, orderBy: 'id');
    return {
      'format': 'packing_pos_backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'packing_transactions': await rows('packing_transactions'),
      'transaction_materials': await rows('transaction_materials'),
      'transaction_payments': await rows('transaction_payments'),
      'materials': await rows('materials'),
      'app_settings': await db.query('app_settings', orderBy: 'key'),
    };
  }

  /// Replaces local data only after validating the backup envelope. All table
  /// changes run in one SQLite transaction; invalid files roll back entirely.
  Future<void> restoreBackup(Map<String, dynamic> backup) async {
    if (backup['format'] != 'packing_pos_backup' || backup['version'] != 1) {
      throw const FormatException('Format atau versi backup tidak didukung.');
    }
    const tables = [
      'packing_transactions',
      'transaction_materials',
      'transaction_payments',
      'materials',
      'app_settings',
    ];
    final data = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final raw = backup[table];
      if (raw is! List) {
        throw FormatException('Data tabel $table tidak ditemukan pada backup.');
      }
      data[table] = raw.map((row) {
        if (row is! Map) {
          throw FormatException('Baris tabel $table tidak valid.');
        }
        return Map<String, Object?>.from(row);
      }).toList();
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete('transaction_payments');
      await txn.delete('transaction_materials');
      await txn.delete('packing_transactions');
      await txn.delete('materials');
      await txn.delete('app_settings');

      for (final row in data['materials']!) {
        await txn.insert('materials', row);
      }
      for (final row in data['packing_transactions']!) {
        await txn.insert('packing_transactions', row);
      }
      for (final row in data['transaction_materials']!) {
        await txn.insert('transaction_materials', row);
      }
      for (final row in data['transaction_payments']!) {
        await txn.insert('transaction_payments', row);
      }
      for (final row in data['app_settings']!) {
        await txn.insert('app_settings', row);
      }
    });
  }

  void _validate(PackingTransactionDraft draft) {
    if (![draft.lengthCm, draft.widthCm, draft.heightCm]
        .every((v) => v.isFinite && v > 0)) {
      throw ArgumentError('Dimensi harus berupa angka lebih dari nol.');
    }
    if ([draft.materialCost, draft.laborCost, draft.overheadCost, draft.sellingPrice]
        .any((v) => v < 0)) {
      throw ArgumentError('Nilai biaya dan harga tidak boleh negatif.');
    }
    for (final item in draft.materials) {
      if (item.name.trim().isEmpty || item.unit.trim().isEmpty ||
          !item.calculatedQuantity.isFinite || item.calculatedQuantity < 0 ||
          !item.actualQuantity.isFinite || item.actualQuantity < 0 ||
          item.unitPrice < 0) {
        throw ArgumentError('Data pemakaian bahan tidak valid.');
      }
      if (item.actualQuantity != item.calculatedQuantity &&
          item.adjustmentNote.trim().isEmpty) {
        throw ArgumentError('Alasan perubahan jumlah bahan wajib diisi.');
      }
    }
  }
}
