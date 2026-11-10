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

  Future<int> createInvoice({int total = 100000}) async {
    await repository.save(PackingTransactionDraft(
      customerName: 'Pelanggan uji',
      itemDescription: 'Barang uji',
      lengthCm: 100,
      widthCm: 80,
      heightCm: 60,
      calculationSnapshot: const {'mode': 'test'},
      sellingPrice: total,
    ));
    return (await repository.listRecent(limit: 1)).single['id'] as int;
  }

  group('PackingTransactionRepository.addPayment', () {
    test('records partial payment and keeps invoice open', () async {
      final id = await createInvoice();
      await repository.addPayment(transactionId: id, amount: 50000, paymentMethod: 'cash', note: 'DP');
      final invoice = await repository.findById(id);
      final payments = await repository.paymentsFor(id);
      expect(invoice!['paid_amount'], 50000);
      expect(invoice['status'], 'open');
      expect(payments, hasLength(1));
      expect(payments.single['amount'], 50000);
      expect(payments.single['note'], 'DP');
    });

    test('marks invoice completed after final payment', () async {
      final id = await createInvoice();
      await repository.addPayment(transactionId: id, amount: 50000, paymentMethod: 'transfer');
      await repository.addPayment(transactionId: id, amount: 50000, paymentMethod: 'qris');
      final invoice = await repository.findById(id);
      expect(invoice!['paid_amount'], 100000);
      expect(invoice['status'], 'completed');
      expect(await repository.paymentsFor(id), hasLength(2));
    });

    test('rejects overpayment without partial write', () async {
      final id = await createInvoice();
      await repository.addPayment(transactionId: id, amount: 75000, paymentMethod: 'cash');
      await expectLater(
        repository.addPayment(transactionId: id, amount: 25001, paymentMethod: 'cash'),
        throwsArgumentError,
      );
      expect((await repository.findById(id))!['paid_amount'], 75000);
      expect(await repository.paymentsFor(id), hasLength(1));
    });

    test('rejects zero and negative amounts', () async {
      final id = await createInvoice();
      for (final amount in [0, -1]) {
        await expectLater(
          repository.addPayment(transactionId: id, amount: amount, paymentMethod: 'cash'),
          throwsArgumentError,
        );
      }
      expect(await repository.paymentsFor(id), isEmpty);
    });

    test('rejects payments on cancelled invoices', () async {
      final id = await createInvoice();
      await repository.cancel(id, reason: 'Pesanan dibatalkan');
      await expectLater(
        repository.addPayment(transactionId: id, amount: 10000, paymentMethod: 'cash'),
        throwsStateError,
      );
      expect((await repository.findById(id))!['paid_amount'], 0);
      expect(await repository.paymentsFor(id), isEmpty);
    });

    test('rejects payments for unknown invoice IDs', () async {
      await expectLater(
        repository.addPayment(transactionId: 99999, amount: 10000, paymentMethod: 'cash'),
        throwsStateError,
      );
    });
  });
}
