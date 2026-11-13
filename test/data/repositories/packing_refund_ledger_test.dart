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

  test('pembatalan setelah refund penuh tetap menjaga rekonsiliasi kas historis', () async {
    final sessionId = await repository.startCashSession(
      date: DateTime.now(),
      openingBalance: 10000,
    );
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
      amount: 50000,
      refundMethod: 'cash',
      reason: 'Nota dibatalkan setelah refund penuh',
    );

    expect((await repository.findReceiptById(receiptId))!['paid_amount'], 0);
    await repository.cancelReceipt(
      receiptId: receiptId,
      reason: 'Refund penuh telah diselesaikan',
    );

    final cash = await repository.cashSessionSummary(sessionId);
    expect(cash['cash_received'], 50000);
    expect(cash['cash_refunded'], 50000);
    expect(cash['expected_balance'], 10000);

    await repository.closeCashSession(
      sessionId: sessionId,
      countedBalance: 10000,
    );
    final closedCash = await repository.cashSessionSummary(sessionId);
    final closedSession = Map<String, Object?>.from(closedCash['session'] as Map);
    expect(closedSession['expected_balance'], 10000);
    expect(closedSession['difference'], 0);

    final report = await repository.reportSummary();
    final totals = Map<String, Object?>.from(report['totals'] as Map);
    expect(totals['paid_total'], 0);
    expect(totals['cash_received_total'], 0);
    expect(totals['refund_total'], 50000);
  });



  test('pembayaran berikutnya dapat dicatat setelah refund sebagian', () async {
    final receiptId = await createReceipt();
    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 60000,
      paymentMethod: 'cash',
    );
    final source = (await repository.receiptPaymentsFor(receiptId)).single;
    await repository.addReceiptRefund(
      receiptId: receiptId,
      receiptPaymentId: (source['id'] as num).toInt(),
      amount: 10000,
      refundMethod: 'transfer',
      reason: 'Penyesuaian pembayaran',
    );

    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 50000,
      paymentMethod: 'transfer',
      note: 'Pembayaran setelah refund',
    );

    final receipt = (await repository.findReceiptById(receiptId))!;
    expect(receipt['paid_amount'], 100000);
    expect(receipt['status'], 'completed');
    expect(await repository.receiptPaymentsFor(receiptId), hasLength(2));
    expect(await repository.receiptRefundsFor(receiptId), hasLength(1));
  });



  test('refund tunai ditolak setelah sesi kas hari itu ditutup', () async {
    final sessionId = await repository.startCashSession(
      date: DateTime.now(),
      openingBalance: 10000,
    );
    final receiptId = await createReceipt();
    await repository.addReceiptPayment(
      receiptId: receiptId,
      amount: 50000,
      paymentMethod: 'cash',
    );
    final source = (await repository.receiptPaymentsFor(receiptId)).single;
    await repository.closeCashSession(
      sessionId: sessionId,
      countedBalance: 60000,
    );

    await expectLater(
      repository.addReceiptRefund(
        receiptId: receiptId,
        receiptPaymentId: (source['id'] as num).toInt(),
        amount: 10000,
        refundMethod: 'cash',
        reason: 'Refund setelah kas ditutup',
      ),
      throwsStateError,
    );
    expect(await repository.receiptRefundsFor(receiptId), isEmpty);
  });


}
