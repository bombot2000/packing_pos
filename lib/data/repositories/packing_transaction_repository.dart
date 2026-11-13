import 'dart:convert';

import '../database/packing_database.dart';
import 'packing_backup_validator.dart';

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
    this.quantity = 1,
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
  final int quantity;
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

  /// Customer master; historical receipt snapshots remain unchanged.
  Future<List<Map<String, Object?>>> listCustomers({bool activeOnly = true, String query = ''}) async {
    final db = await _database.database;
    final clean = query.trim();
    return db.query(
      'customers',
      where: activeOnly
          ? (clean.isEmpty ? 'is_active = 1' : 'is_active = 1 AND name LIKE ?')
          : (clean.isEmpty ? null : 'name LIKE ?'),
      whereArgs: clean.isEmpty ? null : ['%$clean%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> saveCustomer({
    int? id,
    required String name,
    String phone = '',
    String address = '',
    String note = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pelanggan wajib diisi.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'name': cleanName,
      'phone': phone.trim(),
      'address': address.trim(),
      'note': note.trim(),
      'is_active': 1,
      'updated_at': now,
    };
    try {
      if (id == null) {
        return await db.insert('customers', {...values, 'created_at': now});
      }
      final changed = await db.update('customers', values, where: 'id = ?', whereArgs: [id]);
      if (changed == 0) throw StateError('Pelanggan tidak ditemukan.');
      return id;
    } on Exception catch (error) {
      if (error.toString().toLowerCase().contains('unique')) {
        throw ArgumentError('Nama pelanggan sudah terdaftar.');
      }
      rethrow;
    }
  }

  Future<void> deactivateCustomer(int id) async {
    final db = await _database.database;
    final changed = await db.update('customers', {
      'is_active': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ? AND is_active = 1', whereArgs: [id]);
    if (changed == 0) throw StateError('Pelanggan tidak ditemukan atau sudah nonaktif.');
  }

  /// Master catalog of packing service types and their default prices.
  Future<List<Map<String, Object?>>> listServiceTypes({bool activeOnly = true}) async {
    final db = await _database.database;
    return db.query('service_types',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> saveServiceType({
    int? id,
    required String name,
    required int defaultPrice,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pekerjaan wajib diisi.');
    if (defaultPrice < 0) throw ArgumentError('Harga standar tidak boleh negatif.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      if (id == null) {
        return await db.insert('service_types', {
          'name': cleanName, 'default_price': defaultPrice, 'is_active': 1,
          'created_at': now, 'updated_at': now,
        });
      }
      final changed = await db.update('service_types', {
        'name': cleanName, 'default_price': defaultPrice, 'updated_at': now,
      }, where: 'id = ?', whereArgs: [id]);
      if (changed == 0) throw StateError('Jenis pekerjaan tidak ditemukan.');
      return id;
    } catch (error) {
      if (error.toString().toLowerCase().contains('unique')) {
        throw ArgumentError('Nama jenis pekerjaan sudah digunakan.');
      }
      rethrow;
    }
  }

  Future<void> setServiceTypeActive(int id, bool active) async {
    final db = await _database.database;
    final changed = await db.update('service_types', {
      'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    if (changed == 0) throw StateError('Jenis pekerjaan tidak ditemukan.');
  }



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

  /// Saves one receipt header and all of its packing jobs atomically.
  /// Each legacy transaction row remains a job detail; payment belongs to the
  /// receipt header and is recorded only once for the combined total.
  Future<String> saveReceipt(
    List<PackingTransactionDraft> drafts, {
    String customerName = '',
    String note = '',
    int discountAmount = 0,
  }) async {
    if (drafts.isEmpty) throw ArgumentError('Nota harus memiliki minimal satu pekerjaan.');
    for (final draft in drafts) {
      _validate(draft);
    }
    final subtotal = drafts.fold<int>(0, (sum, item) => sum + item.sellingPrice * item.quantity);
    if (discountAmount < 0 || discountAmount > subtotal) {
      throw ArgumentError('Diskon nota tidak boleh melebihi subtotal pekerjaan.');
    }
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final receiptId = await txn.insert('packing_receipts', {
        'receipt_no': 'PENDING-${DateTime.now().microsecondsSinceEpoch}',
        'customer_name': customerName.trim().isNotEmpty
            ? customerName.trim()
            : drafts.first.customerName.trim(),
        'total_amount': subtotal - discountAmount,
        'discount_amount': discountAmount,
        'paid_amount': 0,
        'status': 'open',
        'note': note.trim(),
        'created_at': now,
        'updated_at': now,
      });
      final date = DateTime.now();
      final receiptNo = 'RCP-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${receiptId.toString().padLeft(6, '0')}';
      await txn.update('packing_receipts', {'receipt_no': receiptNo},
          where: 'id = ?', whereArgs: [receiptId]);

      for (final draft in drafts) {
        final id = await txn.insert('packing_transactions', {
          'receipt_no': 'PENDING-${DateTime.now().microsecondsSinceEpoch}-${drafts.indexOf(draft)}',
          'receipt_id': receiptId,
          'customer_name': customerName.trim().isNotEmpty ? customerName.trim() : draft.customerName.trim(),
          'item_description': draft.itemDescription.trim(),
          'quantity': draft.quantity,
          'unit_price': draft.sellingPrice,
          'length_cm': draft.lengthCm,
          'width_cm': draft.widthCm,
          'height_cm': draft.heightCm,
          'calculation_snapshot': jsonEncode(draft.calculationSnapshot),
          'material_cost': draft.materialCost,
          'labor_cost': draft.laborCost,
          'overhead_cost': draft.overheadCost,
          'selling_price': draft.sellingPrice * draft.quantity,
          'paid_amount': 0,
          'status': 'open',
          'note': draft.note.trim(),
          'created_at': now,
          'updated_at': now,
        });
        final jobNo = 'PKG-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${id.toString().padLeft(6, '0')}';
        await txn.update('packing_transactions', {'receipt_no': jobNo},
            where: 'id = ?', whereArgs: [id]);
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
      }
      return receiptNo;
    });
  }

  /// Replaces all jobs and invoice values while preserving the receipt identity.
  /// Editing is allowed only before the first payment; the guard is enforced
  /// inside the same SQLite transaction as the replacement.
  Future<void> updateUnpaidReceipt(
    int receiptId,
    List<PackingTransactionDraft> drafts, {
    String customerName = '',
    String note = '',
    int discountAmount = 0,
  }) async {
    if (drafts.isEmpty) throw ArgumentError('Nota harus memiliki minimal satu pekerjaan.');
    for (final draft in drafts) { _validate(draft); }
    final subtotal = drafts.fold<int>(0, (sum, item) => sum + item.sellingPrice * item.quantity);
    if (discountAmount < 0 || discountAmount > subtotal) {
      throw ArgumentError('Diskon nota tidak boleh melebihi subtotal pekerjaan.');
    }
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('packing_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw StateError('Nota tidak ditemukan.');
      final receipt = rows.first;
      if (receipt['status'] != 'open' || (receipt['paid_amount'] as num).toInt() != 0) {
        throw StateError('Nota hanya dapat diedit sebelum pembayaran pertama.');
      }
      final receiptPayments = await txn.query('receipt_payments', where: 'receipt_id = ?', whereArgs: [receiptId], limit: 1);
      final transactionPayments = await txn.rawQuery(
        'SELECT tp.id FROM transaction_payments tp INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id WHERE pt.receipt_id = ? LIMIT 1',
        [receiptId],
      );
      if (receiptPayments.isNotEmpty || transactionPayments.isNotEmpty) {
        throw StateError('Nota sudah memiliki riwayat pembayaran dan tidak dapat diedit.');
      }
      final oldJobs = await txn.query('packing_transactions', columns: ['id'], where: 'receipt_id = ?', whereArgs: [receiptId]);
      for (final job in oldJobs) {
        await txn.delete('transaction_materials', where: 'transaction_id = ?', whereArgs: [job['id']]);
      }
      await txn.delete('packing_transactions', where: 'receipt_id = ?', whereArgs: [receiptId]);
      await txn.update('packing_receipts', {
        'customer_name': customerName.trim().isNotEmpty ? customerName.trim() : drafts.first.customerName.trim(),
        'total_amount': subtotal - discountAmount,
        'discount_amount': discountAmount,
        'note': note.trim(),
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [receiptId]);
      final date = DateTime.now();
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        final id = await txn.insert('packing_transactions', {
          'receipt_no': 'PENDING-${DateTime.now().microsecondsSinceEpoch}-$index',
          'receipt_id': receiptId,
          'customer_name': customerName.trim().isNotEmpty ? customerName.trim() : draft.customerName.trim(),
          'item_description': draft.itemDescription.trim(),
          'quantity': draft.quantity,
          'unit_price': draft.sellingPrice,
          'length_cm': draft.lengthCm,
          'width_cm': draft.widthCm,
          'height_cm': draft.heightCm,
          'calculation_snapshot': jsonEncode(draft.calculationSnapshot),
          'material_cost': draft.materialCost,
          'labor_cost': draft.laborCost,
          'overhead_cost': draft.overheadCost,
          'selling_price': draft.sellingPrice * draft.quantity,
          'paid_amount': 0,
          'status': 'open',
          'note': draft.note.trim(),
          'created_at': now,
          'updated_at': now,
        });
        final jobNo = 'PKG-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-${id.toString().padLeft(6, '0')}';
        await txn.update('packing_transactions', {'receipt_no': jobNo}, where: 'id = ?', whereArgs: [id]);
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
      }
    });
  }

  /// Backward-compatible single-job save; it now creates a one-job receipt.
  Future<String> save(PackingTransactionDraft draft) =>
      saveReceipt([draft], customerName: draft.customerName, note: draft.note);

  /// Returns a filtered page of receipts and the matching total row count.
  /// Date bounds are interpreted in the device's local timezone; endDate is inclusive.
  Future<Map<String, Object?>> searchReceipts({
    String query = '',
    String status = 'all',
    DateTime? startDate,
    DateTime? endDate,
    int limit = 30,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Harus antara 1 dan 100.');
    }
    if (offset < 0) throw ArgumentError.value(offset, 'offset', 'Tidak boleh negatif.');
    const allowedStatuses = {'all', 'unpaid', 'partial', 'completed', 'cancelled'};
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Filter status tidak dikenal.');
    }
    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      throw ArgumentError('Tanggal awal tidak boleh melewati tanggal akhir.');
    }

    final conditions = <String>[];
    final args = <Object?>[];
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isNotEmpty) {
      conditions.add("""(
        LOWER(receipt_no) LIKE ? ESCAPE '\\'
        OR LOWER(customer_name) LIKE ? ESCAPE '\\'
        OR EXISTS (
          SELECT 1 FROM packing_transactions AS jobs
          WHERE jobs.receipt_id = packing_receipts.id
            AND (
              LOWER(jobs.receipt_no) LIKE ? ESCAPE '\\'
              OR LOWER(jobs.item_description) LIKE ? ESCAPE '\\'
            )
        )
      )""");
      final escapedQuery = cleanQuery
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      final pattern = '%$escapedQuery%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    switch (status) {
      case 'unpaid':
        conditions.add("status = 'open' AND paid_amount = 0");
        break;
      case 'partial':
        conditions.add("status = 'open' AND paid_amount > 0");
        break;
      case 'completed':
        conditions.add("status = 'completed'");
        break;
      case 'cancelled':
        conditions.add("status = 'cancelled'");
        break;
    }
    if (startDate != null) {
      conditions.add('created_at >= ?');
      args.add(DateTime(startDate.year, startDate.month, startDate.day)
          .toUtc().toIso8601String());
    }
    if (endDate != null) {
      final exclusiveEnd = DateTime(endDate.year, endDate.month, endDate.day + 1);
      conditions.add('created_at < ?');
      args.add(exclusiveEnd.toUtc().toIso8601String());
    }
    final where = conditions.isEmpty ? '' : ' WHERE ${conditions.join(' AND ')}';
    final db = await _database.database;
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM packing_receipts$where',
      args,
    );
    final rows = await db.rawQuery(
      '''SELECT packing_receipts.*,
        (SELECT COUNT(*) FROM packing_transactions
         WHERE packing_transactions.receipt_id = packing_receipts.id) AS job_count
        FROM packing_receipts$where
        ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?''',
      [...args, limit, offset],
    );
    return {
      'rows': rows,
      'total': (countRows.first['total'] as num).toInt(),
    };
  }

  /// Outstanding invoices ordered oldest first for collection follow-up.
  Future<List<Map<String, Object?>>> listReceivables() async {
    final db = await _database.database;
    return db.rawQuery("""
      SELECT id, receipt_no, customer_name, total_amount, paid_amount,
        (total_amount - paid_amount) AS remaining_amount, created_at,
        (SELECT COALESCE(SUM(r2.total_amount - r2.paid_amount), 0)
         FROM packing_receipts r2
         WHERE r2.status != 'cancelled'
           AND LOWER(TRIM(r2.customer_name)) = LOWER(TRIM(r.customer_name))
        ) AS customer_outstanding
      FROM packing_receipts r
      WHERE status != 'cancelled' AND total_amount > paid_amount
      ORDER BY created_at ASC, id ASC
    """);
  }

  Future<List<Map<String, Object?>>> listReceipts({int limit = 100}) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Harus antara 1 dan 500.');
    }
    final db = await _database.database;
    return db.query('packing_receipts', orderBy: 'id DESC', limit: limit);
  }

  Future<Map<String, Object?>?> findReceiptById(int id) async {
    final db = await _database.database;
    final rows = await db.query('packing_receipts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findReceiptByNo(String receiptNo) async {
    final db = await _database.database;
    final rows = await db.query('packing_receipts', where: 'receipt_no = ?', whereArgs: [receiptNo], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Cancels a whole receipt and all of its jobs atomically. History and
  /// payment rows are kept; cancelled receipts are excluded from reports.
  Future<void> cancelReceipt({required int receiptId, required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw ArgumentError('Alasan pembatalan wajib diisi.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('packing_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw StateError('Nota tidak ditemukan.');
      final receipt = rows.first;
      if (receipt['status'] == 'cancelled') throw StateError('Nota sudah dibatalkan.');
      final paidAmount = (receipt['paid_amount'] as num).toInt();
      final legacyPayments = await txn.rawQuery(
        'SELECT tp.id FROM transaction_payments tp '
        'INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id '
        'WHERE pt.receipt_id = ? LIMIT 1',
        [receiptId],
      );
      final grossRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM receipt_payments WHERE receipt_id = ?',
        [receiptId],
      );
      final refundRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE receipt_id = ?',
        [receiptId],
      );
      final grossPaid = (grossRows.first['total'] as num).toInt();
      final refunded = (refundRows.first['total'] as num).toInt();
      if (paidAmount > 0 || grossPaid != refunded || legacyPayments.isNotEmpty) {
        throw StateError(
          'Nota sudah memiliki pembayaran. Catat pengembalian dana melalui prosedur refund sebelum pembatalan.',
        );
      }
      await txn.update('packing_receipts', {'status': 'cancelled', 'updated_at': now},
          where: 'id = ?', whereArgs: [receiptId]);
      await txn.update('packing_transactions', {
        'status': 'cancelled', 'cancellation_reason': cleanReason, 'updated_at': now,
      }, where: 'receipt_id = ?', whereArgs: [receiptId]);
    });
  }

  Future<List<Map<String, Object?>>> jobsForReceipt(int receiptId) async {
    final db = await _database.database;
    return db.query('packing_transactions', where: 'receipt_id = ?', whereArgs: [receiptId], orderBy: 'id ASC');
  }

  Future<List<Map<String, Object?>>> receiptPaymentsFor(int receiptId) async {
    final db = await _database.database;
    return db.query('receipt_payments', where: 'receipt_id = ?', whereArgs: [receiptId], orderBy: 'id DESC');
  }


  Future<List<Map<String, Object?>>> receiptRefundsFor(int receiptId) async {
    final db = await _database.database;
    return db.query(
      'payment_refunds',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  /// Refunds a specific payment source without mutating the original payment row.
  /// The net paid balance is recalculated in the same SQLite transaction.
  Future<void> addReceiptRefund({
    required int receiptId,
    required int receiptPaymentId,
    required int amount,
    required String refundMethod,
    required String reason,
    String note = '',
  }) async {
    if (amount <= 0) throw ArgumentError('Nominal refund harus lebih dari nol.');
    final method = refundMethod.trim().toLowerCase();
    if (!['cash', 'transfer', 'qris', 'other'].contains(method)) {
      throw ArgumentError('Metode pengembalian dana tidak valid.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw ArgumentError('Alasan refund wajib diisi.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final receipts = await txn.query(
        'packing_receipts',
        where: 'id = ?',
        whereArgs: [receiptId],
        limit: 1,
      );
      if (receipts.isEmpty) throw StateError('Nota tidak ditemukan.');
      final receipt = receipts.first;
      if (receipt['status'] == 'cancelled') {
        throw StateError('Nota yang dibatalkan tidak dapat direfund lagi.');
      }
      final paymentRows = await txn.query(
        'receipt_payments',
        where: 'id = ? AND receipt_id = ?',
        whereArgs: [receiptPaymentId, receiptId],
        limit: 1,
      );
      if (paymentRows.isEmpty) {
        throw StateError('Pembayaran sumber tidak ditemukan pada nota ini.');
      }
      final sourceAmount = (paymentRows.first['amount'] as num).toInt();
      final previousRefunds = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE receipt_payment_id = ?',
        [receiptPaymentId],
      );
      final grossRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM receipt_payments WHERE receipt_id = ?',
        [receiptId],
      );
      final refundRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE receipt_id = ?',
        [receiptId],
      );
      final grossPaid = (grossRows.first['total'] as num).toInt();
      final refundedBefore = (refundRows.first['total'] as num).toInt();
      final netBefore = grossPaid - refundedBefore;
      if (netBefore != (receipt['paid_amount'] as num).toInt()) {
        throw StateError('Saldo pembayaran nota tidak sinkron. Refund ditahan agar riwayat tidak rusak.');
      }
      final refundable = sourceAmount - (previousRefunds.first['total'] as num).toInt();
      if (refundable <= 0) {
        throw StateError('Pembayaran sumber sudah dikembalikan seluruhnya.');
      }
      if (amount > refundable) {
        throw ArgumentError('Refund melebihi sisa pembayaran sumber ($refundable).');
      }
      if (method == 'cash') {
        final sessions = await txn.query(
          'cash_sessions',
          columns: ['status'],
          where: 'date_key = ?',
          whereArgs: [_cashDateKey(DateTime.now())],
          limit: 1,
        );
        if (sessions.isNotEmpty && sessions.first['status'] == 'closed') {
          throw StateError('Kas hari ini sudah ditutup; refund tunai baru tidak dapat dicatat.');
        }
      }
      await txn.insert('payment_refunds', {
        'receipt_id': receiptId,
        'receipt_payment_id': receiptPaymentId,
        'amount': amount,
        'refund_method': method,
        'reason': cleanReason,
        'note': note.trim(),
        'created_at': now,
      });
      final netPaid = netBefore - amount;
      if (netPaid < 0) throw StateError('Total refund melebihi pembayaran nota.');
      final total = (receipt['total_amount'] as num).toInt();
      final isSettled = netPaid >= total;
      await txn.update('packing_receipts', {
        'paid_amount': netPaid,
        'status': isSettled ? 'completed' : 'open',
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [receiptId]);
      await txn.update(
        'packing_transactions',
        {
          'status': isSettled ? 'completed' : 'open',
          'updated_at': now,
        },
        where: 'receipt_id = ? AND status != ?',
        whereArgs: [receiptId, 'cancelled'],
      );
    });
  }

  /// Records one full settlement for the entire receipt, never per job.
  Future<void> settleReceipt({
    required int receiptId,
    required int amount,
    required String paymentMethod,
    String note = '',
  }) async {
    if (amount <= 0) throw ArgumentError('Nominal pembayaran harus lebih dari nol.');
    if (paymentMethod.trim().isEmpty) throw ArgumentError('Metode pembayaran wajib dipilih.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('packing_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw StateError('Nota tidak ditemukan.');
      final receipt = rows.first;
      if (receipt['status'] == 'cancelled') throw StateError('Nota yang dibatalkan tidak dapat dibayar.');
      final total = (receipt['total_amount'] as num).toInt();
      final paid = (receipt['paid_amount'] as num).toInt();
      final receiptLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM receipt_payments WHERE receipt_id = ?',
        [receiptId],
      );
      final legacyLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(tp.amount), 0) AS total FROM transaction_payments tp '
        'INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id '
        'WHERE pt.receipt_id = ?',
        [receiptId],
      );
      final ledgerPaid = (receiptLedger.first['total'] as num).toInt();
      final legacyPaid = (legacyLedger.first['total'] as num).toInt();
      final refundLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE receipt_id = ?',
        [receiptId],
      );
      final refunded = (refundLedger.first['total'] as num).toInt();
      if (legacyPaid > 0 || ledgerPaid - refunded != paid) {
        throw StateError(
          'Riwayat pembayaran nota tidak sinkron. Pembayaran baru ditahan agar tidak terjadi pencatatan ganda.',
        );
      }
      if (paid > 0) throw StateError('Nota ini sudah memiliki pembayaran.');
      if (amount != total) throw ArgumentError('Pembayaran harus sama dengan total nota ($total).');
      if (paymentMethod.trim().toLowerCase() == 'cash') {
        final sessions = await txn.query('cash_sessions', columns: ['status'], where: 'date_key = ?', whereArgs: [_cashDateKey(DateTime.now())], limit: 1);
        if (sessions.isNotEmpty && sessions.first['status'] == 'closed') {
          throw StateError('Kas hari ini sudah ditutup; pembayaran tunai baru tidak dapat dicatat.');
        }
      }
      await txn.insert('receipt_payments', {
        'receipt_id': receiptId, 'amount': amount,
        'payment_method': paymentMethod.trim().toLowerCase(), 'note': note.trim(), 'created_at': now,
      });
      await txn.update('packing_receipts', {
        'paid_amount': amount, 'status': 'completed', 'updated_at': now,
      }, where: 'id = ?', whereArgs: [receiptId]);
      await txn.update('packing_transactions', {
        'paid_amount': 0, 'status': 'completed', 'updated_at': now,
      }, where: 'receipt_id = ?', whereArgs: [receiptId]);
    });
  }

  /// Records a partial or final payment for one receipt atomically.
  Future<void> addReceiptPayment({
    required int receiptId,
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
        'packing_receipts',
        where: 'id = ?',
        whereArgs: [receiptId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Nota tidak ditemukan.');
      final receipt = rows.first;
      if (receipt['status'] == 'cancelled') {
        throw StateError('Nota yang dibatalkan tidak dapat dibayar.');
      }
      final total = (receipt['total_amount'] as num).toInt();
      final paid = (receipt['paid_amount'] as num).toInt();
      final receiptLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM receipt_payments WHERE receipt_id = ?',
        [receiptId],
      );
      final legacyLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(tp.amount), 0) AS total FROM transaction_payments tp '
        'INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id '
        'WHERE pt.receipt_id = ?',
        [receiptId],
      );
      final ledgerPaid = (receiptLedger.first['total'] as num).toInt();
      final legacyPaid = (legacyLedger.first['total'] as num).toInt();
      final refundLedger = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE receipt_id = ?',
        [receiptId],
      );
      final refunded = (refundLedger.first['total'] as num).toInt();
      if (legacyPaid > 0 || ledgerPaid - refunded != paid) {
        throw StateError(
          'Riwayat pembayaran dan refund nota tidak sinkron. Pembayaran baru ditahan agar saldo tidak keliru.',
        );
      }
      final remaining = total - paid;
      if (remaining <= 0) throw StateError('Nota sudah lunas.');
      if (amount > remaining) {
        throw ArgumentError('Pembayaran melebihi sisa tagihan ($remaining).');
      }
      if (paymentMethod.trim().toLowerCase() == 'cash') {
        final sessions = await txn.query('cash_sessions', columns: ['status'], where: 'date_key = ?', whereArgs: [_cashDateKey(DateTime.now())], limit: 1);
        if (sessions.isNotEmpty && sessions.first['status'] == 'closed') {
          throw StateError('Kas hari ini sudah ditutup; pembayaran tunai baru tidak dapat dicatat.');
        }
      }
      await txn.insert('receipt_payments', {
        'receipt_id': receiptId,
        'amount': amount,
        'payment_method': paymentMethod.trim().toLowerCase(),
        'note': note.trim(),
        'created_at': now,
      });
      final newPaid = paid + amount;
      final isSettled = newPaid == total;
      await txn.update('packing_receipts', {
        'paid_amount': newPaid,
        'status': isSettled ? 'completed' : 'open',
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [receiptId]);
      if (isSettled) {
        await txn.update('packing_transactions', {
          'status': 'completed',
          'updated_at': now,
        }, where: 'receipt_id = ?', whereArgs: [receiptId]);
      }
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

  Future<Map<String, Object?>?> findById(int id) async {
    final db = await _database.database;
    final rows = await db.query(
      'packing_transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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
      if (transaction['receipt_id'] != null) throw StateError('Pembayaran dilakukan pada tingkat nota, bukan pekerjaan.');
      if (transaction['status'] == 'cancelled') {
        throw StateError('Transaksi yang dibatalkan tidak dapat menerima pembayaran.');
      }
      final paid = (transaction['paid_amount'] as num).toInt();
      final total = (transaction['selling_price'] as num).toInt();
      if (amount > total - paid) {
        throw ArgumentError('Pembayaran melebihi sisa tagihan.');
      }
      if (paymentMethod.trim().toLowerCase() == 'cash') {
        final sessions = await txn.query(
          'cash_sessions',
          columns: ['status'],
          where: 'date_key = ?',
          whereArgs: [_cashDateKey(DateTime.now())],
          limit: 1,
        );
        if (sessions.isNotEmpty && sessions.first['status'] == 'closed') {
          throw StateError('Kas hari ini sudah ditutup; pembayaran tunai baru tidak dapat dicatat.');
        }
      }
      await txn.insert('transaction_payments', {
        'transaction_id': transactionId,
        'amount': amount,
        'payment_method': paymentMethod.trim().toLowerCase(),
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
    final found = await db.query('packing_transactions', columns: ['receipt_id'], where: 'id = ?', whereArgs: [transactionId], limit: 1);
    if (found.isEmpty) throw StateError('Transaksi tidak ditemukan.');
    if (found.first['receipt_id'] != null) throw StateError('Batalkan nota secara keseluruhan, bukan satu pekerjaan.');
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await db.update(
      'packing_transactions',
      {
        'status': 'cancelled',
        'cancellation_reason': reason.trim().isEmpty ? 'Tidak disebutkan' : reason.trim(),
        'updated_at': now,
      },
      where: "id = ? AND status != 'cancelled'",
      whereArgs: [transactionId],
    );
    if (changed == 0) throw StateError('Transaksi tidak ditemukan atau sudah dibatalkan.');
  }


  String _cashDateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Map<String, Object?>?> findCashSession(DateTime date) async {
    final db = await _database.database;
    final rows = await db.query('cash_sessions', where: 'date_key = ?', whereArgs: [_cashDateKey(date)], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listCashSessions({int limit = 30}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Harus antara 1 dan 100.');
    }
    final db = await _database.database;
    return db.query(
      'cash_sessions',
      orderBy: 'date_key DESC, id DESC',
      limit: limit,
    );
  }

  Future<int> startCashSession({required DateTime date, required int openingBalance}) async {
    if (openingBalance < 0) throw ArgumentError('Saldo awal tidak boleh negatif.');
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      return await db.insert('cash_sessions', {
        'date_key': _cashDateKey(date), 'opening_balance': openingBalance,
        'status': 'open', 'note': '', 'created_at': now,
      });
    } catch (error) {
      if (error.toString().toLowerCase().contains('unique')) {
        throw StateError('Sesi kas untuk tanggal ini sudah dibuat.');
      }
      rethrow;
    }
  }

  Future<void> addCashExpense({required int sessionId, required int amount, required String category, String note = ''}) async {
    if (amount <= 0) throw ArgumentError('Pengeluaran harus lebih dari nol.');
    if (category.trim().isEmpty) throw ArgumentError('Kategori pengeluaran wajib diisi.');
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('cash_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (rows.isEmpty) throw StateError('Sesi kas tidak ditemukan.');
      if (rows.first['status'] != 'open') throw StateError('Sesi kas sudah ditutup.');
      await txn.insert('cash_expenses', {
        'session_id': sessionId, 'amount': amount, 'category': category.trim(),
        'note': note.trim(), 'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<Map<String, Object?>> cashSessionSummary(int sessionId) async {
    final db = await _database.database;
    final rows = await db.query('cash_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (rows.isEmpty) throw StateError('Sesi kas tidak ditemukan.');
    final session = rows.first;
    final date = DateTime.parse(session['date_key'] as String);
    final start = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final end = DateTime(date.year, date.month, date.day + 1).toUtc().toIso8601String();
    final payments = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(rp.amount)
          FROM receipt_payments rp INNER JOIN packing_receipts pr ON pr.id = rp.receipt_id
          WHERE LOWER(TRIM(rp.payment_method)) = 'cash'
            AND rp.created_at >= ? AND rp.created_at < ?), 0)
        + COALESCE((SELECT SUM(tp.amount)
          FROM transaction_payments tp
          INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id
          WHERE pt.receipt_id IS NULL AND pt.status != 'cancelled'
            AND LOWER(TRIM(tp.payment_method)) = 'cash'
            AND tp.created_at >= ? AND tp.created_at < ?), 0) AS total
    ''', [start, end, start, end]);
    final refunds = await db.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE LOWER(TRIM(refund_method)) = 'cash' AND created_at >= ? AND created_at < ?",
      [start, end],
    );
    final expenses = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS total FROM cash_expenses WHERE session_id = ?', [sessionId]);
    final expenseRows = await db.query('cash_expenses', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id DESC');
    final opening = (session['opening_balance'] as num).toInt();
    final cashIn = (payments.first['total'] as num).toInt();
    final cashRefunded = (refunds.first['total'] as num).toInt();
    final expenseTotal = (expenses.first['total'] as num).toInt();
    final expected = opening + cashIn - cashRefunded - expenseTotal;
    return {
      'session': session, 'cash_received': cashIn, 'cash_refunded': cashRefunded, 'expense_total': expenseTotal,
      'expected_balance': expected, 'expenses': expenseRows,
    };
  }

  Future<void> closeCashSession({required int sessionId, required int countedBalance, String note = ''}) async {
    if (countedBalance < 0) throw ArgumentError('Uang fisik tidak boleh negatif.');
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('cash_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (rows.isEmpty) throw StateError('Sesi kas tidak ditemukan.');
      final session = rows.first;
      if (session['status'] != 'open') throw StateError('Sesi kas sudah ditutup.');
      final date = DateTime.parse(session['date_key'] as String);
      final start = DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
      final end = DateTime(date.year, date.month, date.day + 1).toUtc().toIso8601String();
      final payments = await txn.rawQuery('''
        SELECT
          COALESCE((SELECT SUM(rp.amount) FROM receipt_payments rp
            INNER JOIN packing_receipts pr ON pr.id = rp.receipt_id
            WHERE LOWER(TRIM(rp.payment_method)) = 'cash'
              AND rp.created_at >= ? AND rp.created_at < ?), 0)
          + COALESCE((SELECT SUM(tp.amount) FROM transaction_payments tp
            INNER JOIN packing_transactions pt ON pt.id = tp.transaction_id
            WHERE pt.receipt_id IS NULL AND pt.status != 'cancelled'
              AND LOWER(TRIM(tp.payment_method)) = 'cash'
              AND tp.created_at >= ? AND tp.created_at < ?), 0) AS total
      ''', [start, end, start, end]);
      final refunds = await txn.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) AS total FROM payment_refunds WHERE LOWER(TRIM(refund_method)) = 'cash' AND created_at >= ? AND created_at < ?",
        [start, end],
      );
      final expenses = await txn.rawQuery('SELECT COALESCE(SUM(amount), 0) AS total FROM cash_expenses WHERE session_id = ?', [sessionId]);
      final expected = (session['opening_balance'] as num).toInt()
          + (payments.first['total'] as num).toInt()
          - (refunds.first['total'] as num).toInt()
          - (expenses.first['total'] as num).toInt();
      await txn.update('cash_sessions', {
        'expected_balance': expected, 'counted_balance': countedBalance,
        'difference': countedBalance - expected, 'status': 'closed',
        'note': note.trim(), 'closed_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  /// Ringkasan laporan lintas transaksi. Transaksi batal tidak dihitung sebagai
  /// penjualan, tetapi tetap tersimpan pada riwayat.
  Future<Map<String, Object?>> reportSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _database.database;
    final conditions = <String>[];
    final args = <Object?>[];
    if (startDate != null) {
      conditions.add('created_at >= ?');
      args.add(startDate.toUtc().toIso8601String());
    }
    if (endDate != null) {
      conditions.add('created_at < ?');
      args.add(endDate.toUtc().toIso8601String());
    }
    final dateFilter = conditions.isEmpty ? '' : ' AND ${conditions.join(' AND ')}';
    final paymentDateFilter = dateFilter.replaceAll('created_at', 'receipt_payments.created_at');
    final refundDateFilter = dateFilter.replaceAll('created_at', 'payment_refunds.created_at');
    final materialDateConditions = <String>[];
    if (startDate != null) materialDateConditions.add('packing_transactions.created_at >= ?');
    if (endDate != null) materialDateConditions.add('packing_transactions.created_at < ?');
    final materialDateFilter = materialDateConditions.isEmpty
        ? ''
        : ' AND ${materialDateConditions.join(' AND ')}';
    final totals = await db.rawQuery('''
      SELECT COUNT(*) AS transaction_count,
        (SELECT COUNT(*) FROM packing_receipts WHERE status != 'cancelled'$dateFilter) AS receipt_count,
        (SELECT COALESCE(SUM(total_amount), 0) FROM packing_receipts WHERE status != 'cancelled'$dateFilter) AS sales_total,
        COALESCE(SUM(material_cost), 0) AS material_cost_total,
        COALESCE(SUM(labor_cost), 0) AS labor_cost_total,
        COALESCE(SUM(overhead_cost), 0) AS overhead_cost_total,
        (SELECT COALESCE(SUM(total_amount), 0) FROM packing_receipts WHERE status != 'cancelled'$dateFilter) - COALESCE(SUM(material_cost + labor_cost + overhead_cost), 0) AS gross_profit,
        (SELECT COALESCE(SUM(receipt_payments.amount), 0) FROM receipt_payments INNER JOIN packing_receipts ON packing_receipts.id = receipt_payments.receipt_id WHERE 1 = 1$paymentDateFilter) AS paid_total,
        (SELECT COALESCE(SUM(receipt_payments.amount), 0) FROM receipt_payments INNER JOIN packing_receipts ON packing_receipts.id = receipt_payments.receipt_id WHERE LOWER(TRIM(receipt_payments.payment_method)) = 'cash'$paymentDateFilter) AS cash_received_total,
        (SELECT COALESCE(SUM(receipt_payments.amount), 0) FROM receipt_payments INNER JOIN packing_receipts ON packing_receipts.id = receipt_payments.receipt_id WHERE LOWER(TRIM(receipt_payments.payment_method)) != 'cash'$paymentDateFilter) AS non_cash_received_total,
        (SELECT COALESCE(SUM(total_amount - paid_amount), 0) FROM packing_receipts WHERE status != 'cancelled'$dateFilter) AS receivable_total,
        (SELECT COUNT(*) FROM packing_receipts WHERE status = 'completed'$dateFilter) AS completed_count,
        (SELECT COUNT(*) FROM packing_receipts WHERE status = 'open'$dateFilter) AS open_count,
        (SELECT COUNT(*) FROM packing_receipts WHERE status = 'cancelled'$dateFilter) AS cancelled_count
      FROM packing_transactions WHERE status != 'cancelled'$dateFilter
    ''', [...args, ...args, ...args, ...args, ...args, ...args, ...args, ...args, ...args, ...args, ...args]);
    final materials = await db.rawQuery('''
      SELECT material_name_snapshot AS name, unit_snapshot AS unit,
        COALESCE(SUM(actual_quantity), 0) AS quantity,
        COALESCE(SUM(subtotal), 0) AS cost
      FROM transaction_materials
      INNER JOIN packing_transactions
        ON packing_transactions.id = transaction_materials.transaction_id
      WHERE packing_transactions.status != 'cancelled'$materialDateFilter
      GROUP BY material_name_snapshot, unit_snapshot
      ORDER BY cost DESC, name COLLATE NOCASE
    ''', args);
    final refundRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total,
        COALESCE(SUM(CASE WHEN LOWER(TRIM(refund_method)) = 'cash' THEN amount ELSE 0 END), 0) AS cash_total
      FROM payment_refunds WHERE 1 = 1$refundDateFilter
    ''', args);
    final summary = Map<String, Object?>.from(totals.first);
    final refundTotal = (refundRows.first['total'] as num).toInt();
    final cashRefundTotal = (refundRows.first['cash_total'] as num).toInt();
    final paidTotal = (summary['paid_total'] as num).toInt();
    final cashReceived = (summary['cash_received_total'] as num).toInt();
    final nonCashReceived = (summary['non_cash_received_total'] as num).toInt();
    summary['refund_total'] = refundTotal;
    summary['cash_refunded_total'] = cashRefundTotal;
    summary['non_cash_refunded_total'] = refundTotal - cashRefundTotal;
    summary['paid_total'] = paidTotal - refundTotal;
    summary['cash_received_total'] = cashReceived - cashRefundTotal;
    summary['non_cash_received_total'] = nonCashReceived - (refundTotal - cashRefundTotal);
    final paymentMethods = await db.rawQuery('''
      SELECT receipt_payments.payment_method AS payment_method,
        COALESCE(SUM(receipt_payments.amount), 0) AS amount,
        COUNT(*) AS payment_count
      FROM receipt_payments
      INNER JOIN packing_receipts
        ON packing_receipts.id = receipt_payments.receipt_id
      WHERE packing_receipts.status != 'cancelled'$paymentDateFilter
      GROUP BY receipt_payments.payment_method
      ORDER BY amount DESC, payment_method ASC
    ''', args);
    return {
      'totals': summary,
      'materials': materials,
      'payment_methods': paymentMethods,
    };
  }

  /// Portable JSON backup. IDs and historical price snapshots are preserved.
  Future<Map<String, Object?>> exportBackup() async {
    final db = await _database.database;
    // Read every table from one SQLite transaction so a concurrent payment or
    // edit cannot produce a backup with mismatched parent/child snapshots.
    return db.transaction((txn) async {
      Future<List<Map<String, Object?>>> rows(String table) =>
          txn.query(table, orderBy: 'id');
      return {
        'format': 'packing_pos_backup',
        'version': 8,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'packing_transactions': await rows('packing_transactions'),
        'packing_receipts': await rows('packing_receipts'),
        'receipt_payments': await rows('receipt_payments'),
        'payment_refunds': await rows('payment_refunds'),
        'transaction_materials': await rows('transaction_materials'),
        'transaction_payments': await rows('transaction_payments'),
        'materials': await rows('materials'),
        'service_types': await rows('service_types'),
        'customers': await rows('customers'),
        'app_settings': await txn.query('app_settings', orderBy: 'key'),
        'cash_sessions': await rows('cash_sessions'),
        'cash_expenses': await rows('cash_expenses'),
      };
    });
  }

  /// Replaces local data only after validating the backup envelope. All table
  /// changes run in one SQLite transaction; invalid files roll back entirely.
  Future<void> restoreBackup(Map<String, dynamic> backup) async {
    final data = PackingBackupValidator.validate(backup);

    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete('cash_expenses');
      await txn.delete('cash_sessions');
      await txn.delete('payment_refunds');
      await txn.delete('receipt_payments');
      await txn.delete('transaction_payments');
      await txn.delete('transaction_materials');
      await txn.delete('packing_transactions');
      await txn.delete('packing_receipts');
      await txn.delete('materials');
      await txn.delete('customers');
      if (data.containsKey('service_types')) await txn.delete('service_types');
      await txn.delete('app_settings');

      for (final row in data['materials']!) {
        await txn.insert('materials', row);
      }
      for (final row in data['service_types'] ?? const <Map<String, Object?>>[]) {
        await txn.insert('service_types', row);
      }
      for (final row in data['customers'] ?? const <Map<String, Object?>>[]) {
        await txn.insert('customers', row);
      }
      for (final row in data['packing_receipts']!) { await txn.insert('packing_receipts', row); }
      for (final row in data['packing_transactions']!) {
        await txn.insert('packing_transactions', row);
      }
      for (final row in data['receipt_payments']!) { await txn.insert('receipt_payments', row); }
      for (final row in data['payment_refunds'] ?? const <Map<String, Object?>>[]) { await txn.insert('payment_refunds', row); }
      for (final row in data['transaction_materials']!) {
        await txn.insert('transaction_materials', row);
      }
      for (final row in data['transaction_payments']!) {
        await txn.insert('transaction_payments', row);
      }
      for (final row in data['app_settings']!) {
        await txn.insert('app_settings', row);
      }
      for (final row in data['cash_sessions'] ?? const <Map<String, Object?>>[]) { await txn.insert('cash_sessions', row); }
      for (final row in data['cash_expenses'] ?? const <Map<String, Object?>>[]) { await txn.insert('cash_expenses', row); }
    });
  }

  void _validate(PackingTransactionDraft draft) {
    if (draft.quantity < 1) {
      throw ArgumentError('Qty pekerjaan minimal 1.');
    }
    if (![draft.lengthCm, draft.widthCm, draft.heightCm]
        .every((v) => v.isFinite && v >= 0)) {
      // 0 means "size not recorded"; negative or non-finite values are invalid.
      throw ArgumentError('Ukuran tidak boleh negatif.');
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
