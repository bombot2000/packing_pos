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

  PackingTransactionDraft draft(String description, int price) =>
      PackingTransactionDraft(
        customerName: 'Pelanggan',
        itemDescription: description,
        lengthCm: 100,
        widthCm: 80,
        heightCm: 60,
        calculationSnapshot: const {'mode': 'test'},
        sellingPrice: price,
      );

  Future<int> save({
    required String customer,
    required String description,
    required int price,
  }) async {
    final receiptNo = await repository.saveReceipt(
      [draft(description, price)],
      customerName: customer,
    );
    final receipt = (await repository.listReceipts(limit: 20))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    return (receipt['id'] as num).toInt();
  }

  test('searchReceipts filters status and returns stable pages with total', () async {
    await save(customer: 'Andi', description: 'Nota satu', price: 100000);
    final partialId = await save(
      customer: 'Budi',
      description: 'Nota dua',
      price: 200000,
    );
    await repository.addReceiptPayment(
      receiptId: partialId,
      amount: 50000,
      paymentMethod: 'cash',
    );
    await save(customer: 'Citra', description: 'Nota tiga', price: 300000);

    final firstPage = await repository.searchReceipts(limit: 2, offset: 0);
    expect(firstPage['total'], 3);
    expect((firstPage['rows'] as List), hasLength(2));

    final secondPage = await repository.searchReceipts(limit: 2, offset: 2);
    expect(secondPage['total'], 3);
    expect((secondPage['rows'] as List), hasLength(1));

    final unpaid = await repository.searchReceipts(status: 'unpaid');
    expect(unpaid['total'], 2);
    final partial = await repository.searchReceipts(status: 'partial');
    expect(partial['total'], 1);
    final search = await repository.searchReceipts(query: 'bUdI');
    expect(search['total'], 1);
  });

  test('receivables are oldest first and include per-customer outstanding total', () async {
    final oldestId = await save(
      customer: 'Pelanggan A',
      description: 'Nota paling lama',
      price: 100000,
    );
    final otherCustomerId = await save(
      customer: 'Pelanggan B',
      description: 'Nota pelanggan B',
      price: 75000,
    );
    final newestId = await save(
      customer: 'pelanggan a',
      description: 'Nota terbaru',
      price: 50000,
    );

    await database.update(
      'packing_receipts',
      {'created_at': '2026-01-01T00:00:00.000Z'},
      where: 'id = ?',
      whereArgs: [oldestId],
    );
    await database.update(
      'packing_receipts',
      {'created_at': '2026-01-02T00:00:00.000Z'},
      where: 'id = ?',
      whereArgs: [otherCustomerId],
    );
    await database.update(
      'packing_receipts',
      {'created_at': '2026-01-03T00:00:00.000Z'},
      where: 'id = ?',
      whereArgs: [newestId],
    );

    await repository.addReceiptPayment(
      receiptId: oldestId,
      amount: 20000,
      paymentMethod: 'transfer',
    );

    final receivables = await repository.listReceivables();
    expect(
      receivables.map((row) => row['id']).toList(),
      [oldestId, otherCustomerId, newestId],
    );
    expect(receivables.first['remaining_amount'], 80000);
    expect(receivables.first['customer_outstanding'], 130000);
    expect(receivables.last['customer_outstanding'], 130000);
    expect(receivables[1]['customer_outstanding'], 75000);
  });
}
