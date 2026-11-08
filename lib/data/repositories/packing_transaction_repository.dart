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

  Future<void> _validate(PackingTransactionDraft draft) async {
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
