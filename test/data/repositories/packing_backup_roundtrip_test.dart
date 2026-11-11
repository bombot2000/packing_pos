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
      customerName: 'Pelanggan backup',
      itemDescription: description,
      lengthCm: 100,
      widthCm: 80,
      heightCm: 60,
      calculationSnapshot: const {'mode': 'test', 'formulaVersion': 1},
      materialCost: 10000,
      laborCost: 5000,
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

  test('export and restore round-trip keeps multi-job receipt and settlement', () async {
    await repository.saveServiceType(name: 'Packing ekspor backup', defaultPrice: 15000);
    await repository.saveCustomer(
      name: 'Pelanggan backup',
      phone: '08123456789',
      address: 'Malang',
      note: 'Pelanggan tetap',
    );
    final receiptNo = await repository.saveReceipt(
      [
        draft(description: 'Kardus A', price: 60000),
        draft(description: 'Peti B', price: 40000),
      ],
      customerName: 'Pelanggan backup',
      note: 'Satu nota untuk dua pekerjaan',
    );
    final receipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    final receiptId = (receipt['id'] as num).toInt();

    await repository.settleReceipt(
      receiptId: receiptId,
      amount: 100000,
      paymentMethod: 'cash',
      note: 'Pembayaran gabungan',
    );

    final cashSessionId = await repository.startCashSession(date: DateTime.now(), openingBalance: 25000);
    await repository.addCashExpense(sessionId: cashSessionId, amount: 3000, category: 'Operasional', note: 'Parkir');
    await repository.closeCashSession(sessionId: cashSessionId, countedBalance: 122000, note: 'Kas dihitung dan ditutup');

    final backup = await repository.exportBackup();
    expect(backup['version'], 7);
    expect(backup['customers'], hasLength(1));
    expect(backup['cash_sessions'], hasLength(1));
    expect(backup['cash_expenses'], hasLength(1));
    final backupReceipts = backup['packing_receipts'] as List<dynamic>;
    expect(backupReceipts, hasLength(1));
    expect(backup['receipt_payments'], hasLength(1));
    expect(backup['packing_transactions'], hasLength(2));
    expect(backupReceipts.single['discount_amount'], 0);
    expect(
      (backup['packing_transactions'] as List)
          .every((job) => job['quantity'] == 1 && job['unit_price'] == job['selling_price']),
      isTrue,
    );

    await repository.save(draft(description: 'Data setelah backup', price: 9000));
    expect(await repository.listReceipts(limit: 10), hasLength(2));

    await repository.restoreBackup(backup);

    final restoredReceipts = await repository.listReceipts(limit: 10);
    expect(restoredReceipts, hasLength(1));
    final restoredCashSession = await repository.findCashSession(DateTime.now());
    expect(restoredCashSession?['opening_balance'], 25000);
    final restoredCashSummary = await repository.cashSessionSummary((restoredCashSession!['id'] as num).toInt());
    expect(restoredCashSummary['expense_total'], 3000);
    expect(restoredCashSession!['status'], 'closed');
    expect(restoredCashSession['expected_balance'], 22000);
    expect(restoredCashSession['counted_balance'], 122000);
    expect(restoredCashSession['difference'], 100000);
    expect(restoredCashSession['note'], 'Kas dihitung dan ditutup');
    final restoredReceipt = restoredReceipts.single;
    expect(restoredReceipt['receipt_no'], receiptNo);
    expect(restoredReceipt['total_amount'], 100000);
    expect(restoredReceipt['paid_amount'], 100000);
    expect(restoredReceipt['status'], 'completed');

    final restoredId = (restoredReceipt['id'] as num).toInt();
    final jobs = await repository.jobsForReceipt(restoredId);
    expect(jobs, hasLength(2));
    expect(
      jobs.map((job) => job['item_description']).toSet(),
      {'Kardus A', 'Peti B'},
    );
    expect(jobs.every((job) => job['status'] == 'completed'), isTrue);
    expect(jobs.every((job) => job['paid_amount'] == 0), isTrue);

    final payments = await repository.receiptPaymentsFor(restoredId);
    expect(payments, hasLength(1));
    expect(payments.single['amount'], 100000);
    expect(payments.single['payment_method'], 'cash');
    expect(payments.single['note'], 'Pembayaran gabungan');

    final restoredMaterials = await repository.materialsFor(
      (jobs.first['id'] as num).toInt(),
    );
    expect(restoredMaterials, hasLength(1));
    expect(restoredMaterials.single['material_name_snapshot'], 'Kayu');
    final customers = await repository.listCustomers();
    expect(customers, hasLength(1));
    expect(customers.single['name'], 'Pelanggan backup');
    expect(customers.single['phone'], '08123456789');
    final serviceTypes = await repository.listServiceTypes();
    expect(serviceTypes, hasLength(2));
    expect(
      serviceTypes.map((row) => row['name']),
      contains('Packing ekspor backup'),
    );
  });

  test('invalid restore leaves existing local records untouched', () async {
    await repository.save(draft(description: 'Data lokal', price: 25000));
    final before = await repository.listReceipts(limit: 10);
    final invalidBackup = <String, dynamic>{
      'format': 'not_a_packing_pos_backup',
      'version': 4,
    };

    await expectLater(
      repository.restoreBackup(invalidBackup),
      throwsFormatException,
    );

    final after = await repository.listReceipts(limit: 10);
    expect(after, hasLength(before.length));
    expect(after.single['receipt_no'], before.single['receipt_no']);
    expect(after.single['total_amount'], before.single['total_amount']);
  });
}
