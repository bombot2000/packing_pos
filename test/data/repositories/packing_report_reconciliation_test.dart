import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packing_pos/data/database/packing_database.dart';
import 'package:packing_pos/data/repositories/packing_transaction_repository.dart';

void main() {
  late Database database;
  late PackingTransactionRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final packingDatabase = await PackingDatabase.createForTesting(database);
    repository = PackingTransactionRepository(database: packingDatabase);
  });

  tearDown(() async => database.close());

  PackingTransactionDraft draft({
    required String description,
    required int price,
  }) {
    return PackingTransactionDraft(
      customerName: 'Pelanggan laporan',
      itemDescription: description,
      lengthCm: 100,
      widthCm: 80,
      heightCm: 60,
      calculationSnapshot: const {'mode': 'test'},
      materialCost: 10000,
      laborCost: 5000,
      overheadCost: 5000,
      sellingPrice: price,
      materials: const [
        MaterialUsageDraft(
          name: 'Kayu',
          unit: 'batang',
          calculatedQuantity: 2,
          actualQuantity: 2,
          unitPrice: 5000,
        ),
      ],
    );
  }

  Future<int> receiptId(String receiptNo) async {
    final receipts = await repository.listReceipts(limit: 20);
    return (receipts.singleWhere((row) => row['receipt_no'] == receiptNo)['id'] as num).toInt();
  }

  test('report reconciles net payments, refund channels, cancelled receipts and receivables', () async {
    final activeNo = await repository.saveReceipt(
      [draft(description: 'Peti aktif', price: 100000)],
      customerName: 'Pelanggan aktif',
    );
    final activeId = await receiptId(activeNo);
    await repository.addReceiptPayment(
      receiptId: activeId,
      amount: 40000,
      paymentMethod: 'cash',
    );
    final activePayment = (await repository.receiptPaymentsFor(activeId)).single;
    await repository.addReceiptRefund(
      receiptId: activeId,
      receiptPaymentId: (activePayment['id'] as num).toInt(),
      amount: 10000,
      refundMethod: 'transfer',
      reason: 'Koreksi pembayaran',
    );

    final cancelledNo = await repository.saveReceipt(
      [draft(description: 'Peti batal', price: 5000)],
      customerName: 'Pelanggan batal',
    );
    final cancelledId = await receiptId(cancelledNo);
    await repository.addReceiptPayment(
      receiptId: cancelledId,
      amount: 5000,
      paymentMethod: 'cash',
    );
    final cancelledPayment = (await repository.receiptPaymentsFor(cancelledId)).single;
    await repository.addReceiptRefund(
      receiptId: cancelledId,
      receiptPaymentId: (cancelledPayment['id'] as num).toInt(),
      amount: 5000,
      refundMethod: 'transfer',
      reason: 'Nota dibatalkan',
    );
    await repository.cancelReceipt(
      receiptId: cancelledId,
      reason: 'Pesanan dibatalkan pelanggan',
    );

    final now = DateTime.now();
    final report = await repository.reportSummary(
      startDate: DateTime(now.year, now.month, now.day),
      endDate: DateTime(now.year, now.month, now.day + 1),
    );
    final totals = Map<String, Object?>.from(report['totals'] as Map);
    expect(totals['sales_total'], 100000);
    expect(totals['receipt_count'], 1);
    expect(totals['cancelled_count'], 1);
    expect(totals['paid_total'], 30000);
    expect(totals['refund_total'], 15000);
    expect(totals['cash_received_total'], 45000);
    expect(totals['non_cash_received_total'], -15000);
    expect(totals['receivable_total'], 70000);
    expect(totals['material_cost_total'], 10000);
    expect(totals['labor_cost_total'], 5000);
    expect(totals['overhead_cost_total'], 5000);
    expect(totals['gross_profit'], 80000);

    final methods = (report['payment_methods'] as List)
        .map((row) => Map<String, Object?>.from(row as Map));
    final byMethod = {for (final row in methods) row['payment_method']: row['amount']};
    expect(byMethod['cash'], 40000);
    expect(byMethod['transfer'], -10000);
  });
}
