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

  Future<Map<String, Object?>> createReceipt({int total = 100000}) async {
    await repository.save(PackingTransactionDraft(
      customerName: 'Pelanggan uji',
      itemDescription: 'Barang uji',
      lengthCm: 100,
      widthCm: 80,
      heightCm: 60,
      calculationSnapshot: const {'mode': 'test'},
      sellingPrice: total,
    ));
    return (await repository.listReceipts(limit: 1)).single;
  }

  group('pembayaran tingkat nota', () {
    test('menolak pembayaran langsung pada pekerjaan', () async {
      final receipt = await createReceipt();
      final job = (await repository.jobsForReceipt(receipt['id'] as int)).single;
      await expectLater(
        repository.addPayment(
          transactionId: job['id'] as int,
          amount: 100000,
          paymentMethod: 'cash',
        ),
        throwsStateError,
      );
      expect(await repository.receiptPaymentsFor(receipt['id'] as int), isEmpty);
    });

    test('melunasi seluruh nota dengan satu pembayaran', () async {
      final receipt = await createReceipt();
      final receiptId = receipt['id'] as int;
      await repository.settleReceipt(
        receiptId: receiptId,
        amount: 100000,
        paymentMethod: 'transfer',
        note: 'Lunas',
      );
      final saved = await repository.findReceiptById(receiptId);
      final jobs = await repository.jobsForReceipt(receiptId);
      final payments = await repository.receiptPaymentsFor(receiptId);
      expect(saved!['paid_amount'], 100000);
      expect(saved['status'], 'completed');
      expect(jobs, hasLength(1));
      expect(jobs.single['status'], 'completed');
      expect(payments, hasLength(1));
      expect(payments.single['amount'], 100000);
      expect(payments.single['note'], 'Lunas');
    });

    test('menolak pembayaran kurang atau lebih dari total nota', () async {
      final receipt = await createReceipt();
      final receiptId = receipt['id'] as int;
      for (final amount in [99999, 100001]) {
        await expectLater(
          repository.settleReceipt(
            receiptId: receiptId,
            amount: amount,
            paymentMethod: 'cash',
          ),
          throwsArgumentError,
        );
      }
      expect((await repository.findReceiptById(receiptId))!['paid_amount'], 0);
      expect(await repository.receiptPaymentsFor(receiptId), isEmpty);
    });

    test('menolak nominal nol dan negatif', () async {
      final receipt = await createReceipt();
      for (final amount in [0, -1]) {
        await expectLater(
          repository.settleReceipt(
            receiptId: receipt['id'] as int,
            amount: amount,
            paymentMethod: 'cash',
          ),
          throwsArgumentError,
        );
      }
      expect(await repository.receiptPaymentsFor(receipt['id'] as int), isEmpty);
    });

    test('menolak pembayaran kedua pada nota yang sudah lunas', () async {
      final receipt = await createReceipt();
      final receiptId = receipt['id'] as int;
      await repository.settleReceipt(
        receiptId: receiptId,
        amount: 100000,
        paymentMethod: 'cash',
      );
      await expectLater(
        repository.settleReceipt(
          receiptId: receiptId,
          amount: 100000,
          paymentMethod: 'cash',
        ),
        throwsStateError,
      );
      expect(await repository.receiptPaymentsFor(receiptId), hasLength(1));
    });

    test('menolak pembatalan satu pekerjaan secara terpisah', () async {
      final receipt = await createReceipt();
      final job = (await repository.jobsForReceipt(receipt['id'] as int)).single;
      await expectLater(
        repository.cancel(job['id'] as int, reason: 'Pesanan dibatalkan'),
        throwsStateError,
      );
    });

    test('menggabungkan banyak pekerjaan dalam satu nota dan satu pembayaran', () async {
      final receiptNo = await repository.saveReceipt([
        PackingTransactionDraft(
          customerName: 'Pelanggan gabungan',
          itemDescription: 'Kardus A',
          lengthCm: 100,
          widthCm: 80,
          heightCm: 60,
          calculationSnapshot: const {'mode': 'test'},
          sellingPrice: 60000,
        ),
        PackingTransactionDraft(
          customerName: 'Pelanggan gabungan',
          itemDescription: 'Kardus B',
          lengthCm: 50,
          widthCm: 40,
          heightCm: 30,
          calculationSnapshot: const {'mode': 'test'},
          sellingPrice: 40000,
        ),
      ]);
      final receipts = await repository.listReceipts(limit: 10);
      final receipt = receipts.singleWhere((row) => row['receipt_no'] == receiptNo);
      final receiptId = receipt['id'] as int;
      expect(receiptNo, startsWith('RCP-'));
      expect(receipt['total_amount'], 100000);
      expect(await repository.jobsForReceipt(receiptId), hasLength(2));

      await repository.settleReceipt(
        receiptId: receiptId,
        amount: 100000,
        paymentMethod: 'qris',
      );

      expect(await repository.receiptPaymentsFor(receiptId), hasLength(1));
      final saved = await repository.findReceiptById(receiptId);
      expect(saved!['paid_amount'], 100000);
      expect(saved['status'], 'completed');
      final report = await repository.reportSummary();
      expect(report['totals']['receipt_count'], 1);
      expect(report['totals']['paid_total'], 100000);
      expect(report['totals']['sales_total'], 100000);
    });

    test('menolak pembayaran untuk ID pekerjaan yang tidak dikenal', () async {
      await expectLater(
        repository.addPayment(
          transactionId: 99999,
          amount: 10000,
          paymentMethod: 'cash',
        ),
        throwsStateError,
      );
    });
  });
}
