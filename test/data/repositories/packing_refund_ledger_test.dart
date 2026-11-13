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
    repository = PackingTransactionRepository(
      database: await PackingDatabase.createForTesting(database),
    );
  });

  tearDown(() async => database.close());

  Future<int> createReceipt() async {
    final number = await repository.saveReceipt([
      const PackingTransactionDraft(
        customerName: 'Pelanggan refund',
        itemDescription: 'Packing refund',
        lengthCm: 100,
        widthCm: 80,
        heightCm: 60,
        calculationSnapshot: {'mode': 'test'},
        sellingPrice: 100000,
      ),
    ]);
    return (await repository.findReceiptByNo(number))!['id'] as int;
  }

  test('refund bersamaan tidak dapat mengembalikan melebihi pembayaran sumber', () async {
    final receiptId = await createReceipt();
    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 100000,
      paymentMethod: 'transfer',
    );
    final source = (await repository.receiptPaymentsFor(receiptId)).single;
    final paymentId = (source['id'] as num).toInt();

    final results = await Future.wait([
      repository.addReceiptRefund(
        receiptId: receiptId,
        receiptPaymentId: paymentId,
        amount: 60000,
        refundMethod: 'transfer',
        reason: 'Pengembalian pertama',
      ).then((_) => true, onError: (_) => false),
      repository.addReceiptRefund(
        receiptId: receiptId,
        receiptPaymentId: paymentId,
        amount: 60000,
        refundMethod: 'transfer',
        reason: 'Pengembalian kedua',
      ).then((_) => true, onError: (_) => false),
    ]);

    expect(results.where((success) => success), hasLength(1));
    final refunds = await repository.receiptRefundsFor(receiptId);
    expect(refunds, hasLength(1));
    expect(refunds.fold<int>(0, (sum, row) => sum + (row['amount'] as num).toInt()), 60000);
    expect((await repository.findReceiptById(receiptId))!['paid_amount'], 40000);
  });

  test('backup dan restore mempertahankan refund serta saldo bersih nota', () async {
    final receiptId = await createReceipt();
    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 75000,
      paymentMethod: 'cash',
    );
    final source = (await repository.receiptPaymentsFor(receiptId)).single;
    await repository.addReceiptRefund(
      receiptId: receiptId,
      receiptPaymentId: (source['id'] as num).toInt(),
      amount: 25000,
      refundMethod: 'cash',
      reason: 'Perubahan lingkup pekerjaan',
    );

    final backup = await repository.exportBackup();
    expect(backup['version'], 8);
    expect(backup['payment_refunds'], hasLength(1));

    await repository.restoreBackup(backup);
    final receipt = (await repository.findReceiptById(receiptId))!;
    expect(receipt['paid_amount'], 50000);
    expect(await repository.receiptRefundsFor(receiptId), hasLength(1));
  });

  test('laporan menampilkan penerimaan bersih setelah refund', () async {
    final receiptId = await createReceipt();
    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 50000,
      paymentMethod: 'cash',
    );
    final source = (await repository.receiptPaymentsFor(receiptId)).single;
    await repository.addReceiptRefund(
      receiptId: receiptId,
      receiptPaymentId: (source['id'] as num).toInt(),
      amount: 10000,
      refundMethod: 'cash',
      reason: 'Penyesuaian',
    );

    final report = await repository.reportSummary();
    final totals = Map<String, Object?>.from(report['totals'] as Map);
    expect(totals['refund_total'], 10000);
    expect(totals['cash_refunded_total'], 10000);
    expect(totals['paid_total'], 40000);
    expect(totals['cash_received_total'], 40000);
  });
}
