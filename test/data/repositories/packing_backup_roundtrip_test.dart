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

  test('receipt history search matches job number and item description once per receipt', () async {
    final receiptNo = await repository.saveReceipt(
      [
        draft(description: 'Peti kayu ekspor', price: 60000),
        draft(description: 'Kardus mesin', price: 40000),
      ],
      customerName: 'Pelanggan pencarian',
    );
    final receipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    final receiptId = (receipt['id'] as num).toInt();
    final jobs = await repository.jobsForReceipt(receiptId);
    final jobNo = jobs.first['receipt_no'] as String;

    final byJobNumber = await repository.searchReceipts(query: jobNo);
    expect(byJobNumber['total'], 1);
    expect((byJobNumber['rows'] as List), hasLength(1));
    expect((byJobNumber['rows'] as List).single['id'], receiptId);

    final byDescription = await repository.searchReceipts(query: 'kayu ekspor');
    expect(byDescription['total'], 1);
    expect((byDescription['rows'] as List), hasLength(1));
    expect((byDescription['rows'] as List).single['id'], receiptId);
  });


  test('receipt history treats percent and underscore as literal search characters', () async {
    await repository.saveReceipt(
      [draft(description: 'Barang 100%_siap', price: 10000)],
      customerName: 'Pelanggan simbol',
    );
    await repository.saveReceipt(
      [draft(description: 'Barang 100Xasiap', price: 10000)],
      customerName: 'Pelanggan lain',
    );

    final result = await repository.searchReceipts(query: '100%_');
    expect(result['total'], 1);
    expect((result['rows'] as List), hasLength(1));
    expect((result['rows'] as List).single['customer_name'], 'Pelanggan simbol');
  });

  test('receipt history filters all supported statuses correctly', () async {
    Future<int> create(String description) async {
      final number = await repository.saveReceipt(
        [draft(description: description, price: 10000)],
        customerName: description,
      );
      final row = (await repository.listReceipts(limit: 20))
          .singleWhere((item) => item['receipt_no'] == number);
      return (row['id'] as num).toInt();
    }

    final unpaidId = await create('Belum bayar');
    final partialId = await create('DP');
    final completedId = await create('Lunas');
    final cancelledId = await create('Batal');

    await repository.addReceiptPayment(
      receiptId: partialId,
      amount: 2000,
      paymentMethod: 'cash',
    );
    await repository.settleReceipt(
      receiptId: completedId,
      amount: 10000,
      paymentMethod: 'cash',
    );
    await repository.cancelReceipt(
      receiptId: cancelledId,
      reason: 'Salah input',
    );

    Future<Set<int>> idsFor(String status) async {
      final result = await repository.searchReceipts(status: status);
      return (result['rows'] as List)
          .map((row) => (row['id'] as num).toInt())
          .toSet();
    }

    expect(await idsFor('all'),
        {unpaidId, partialId, completedId, cancelledId});
    expect(await idsFor('unpaid'), {unpaidId});
    expect(await idsFor('partial'), {partialId});
    expect(await idsFor('completed'), {completedId});
    expect(await idsFor('cancelled'), {cancelledId});
  });

  test('receipt history date range includes both local calendar boundary days', () async {
    Future<int> createAt(String description, DateTime createdAt) async {
      final number = await repository.saveReceipt(
        [draft(description: description, price: 10000)],
        customerName: description,
      );
      final row = (await repository.listReceipts(limit: 20))
          .singleWhere((item) => item['receipt_no'] == number);
      final id = (row['id'] as num).toInt();
      await database.update(
        'packing_receipts',
        {'created_at': createdAt.toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    final start = DateTime(2026, 5, 10);
    final end = DateTime(2026, 5, 12);
    final beforeId = await createAt('Sebelum rentang', DateTime(2026, 5, 9, 23, 59));
    final startId = await createAt('Hari awal', DateTime(2026, 5, 10, 0, 0));
    final endId = await createAt('Hari akhir', DateTime(2026, 5, 12, 23, 59));
    final afterId = await createAt('Sesudah rentang', DateTime(2026, 5, 13, 0, 0));

    final result = await repository.searchReceipts(
      startDate: start,
      endDate: end,
    );
    final ids = (result['rows'] as List)
        .map((row) => (row['id'] as num).toInt())
        .toSet();

    expect(result['total'], 2);
    expect(ids, {startId, endId});
    expect(ids, isNot(contains(beforeId)));
    expect(ids, isNot(contains(afterId)));
  });

  test('receipt history pagination returns stable newest-first pages and total', () async {
    final ids = <int>[];
    for (var index = 0; index < 5; index++) {
      final number = await repository.saveReceipt(
        [draft(description: 'Nota $index', price: 10000)],
        customerName: 'Pelanggan $index',
      );
      final row = (await repository.listReceipts(limit: 20))
          .singleWhere((item) => item['receipt_no'] == number);
      ids.add((row['id'] as num).toInt());
      await database.update(
        'packing_receipts',
        {'created_at': DateTime.utc(2026, 6, 1).toIso8601String()},
        where: 'id = ?',
        whereArgs: [ids.last],
      );
    }

    final first = await repository.searchReceipts(limit: 2, offset: 0);
    final second = await repository.searchReceipts(limit: 2, offset: 2);
    final firstIds = (first['rows'] as List)
        .map((row) => (row['id'] as num).toInt())
        .toList();
    final secondIds = (second['rows'] as List)
        .map((row) => (row['id'] as num).toInt())
        .toList();

    expect(first['total'], 5);
    expect(second['total'], 5);
    expect(firstIds, [ids[4], ids[3]]);
    expect(secondIds, [ids[2], ids[1]]);
    expect(firstIds.toSet().intersection(secondIds.toSet()), isEmpty);
  });

  test('receipt history escapes backslash together with SQL wildcard characters', () async {
    await repository.saveReceipt(
      [draft(description: r'Barang 100\\%_siap', price: 10000)],
      customerName: 'Pelanggan backslash',
    );
    await repository.saveReceipt(
      [draft(description: 'Barang 100XXsiap', price: 10000)],
      customerName: 'Pelanggan pembanding',
    );

    final result = await repository.searchReceipts(query: r'100\\%_');
    expect(result['total'], 1);
    expect((result['rows'] as List).single['customer_name'], 'Pelanggan backslash');
  });

  test('receipt history rejects invalid pagination and date ranges', () async {
    await expectLater(
      repository.searchReceipts(limit: 0),
      throwsArgumentError,
    );
    await expectLater(
      repository.searchReceipts(limit: 101),
      throwsArgumentError,
    );
    await expectLater(
      repository.searchReceipts(offset: -1),
      throwsArgumentError,
    );
    await expectLater(
      repository.searchReceipts(status: 'unknown'),
      throwsArgumentError,
    );
    await expectLater(
      repository.searchReceipts(
        startDate: DateTime(2026, 6, 2),
        endDate: DateTime(2026, 6, 1),
      ),
      throwsArgumentError,
    );
  });

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
    expect(restoredCashSession, isNotNull);
    final cashSession = restoredCashSession!;
    expect(cashSession['opening_balance'], 25000);
    final restoredCashSummary = await repository.cashSessionSummary((cashSession['id'] as num).toInt());
    expect(restoredCashSummary['expense_total'], 3000);
    expect(cashSession['status'], 'closed');
    expect(cashSession['expected_balance'], 122000);
    expect(cashSession['counted_balance'], 122000);
    expect(cashSession['difference'], 0);
    expect(cashSession['note'], 'Kas dihitung dan ditutup');
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

  test('export and restore preserves cancelled receipt and cancellation reason', () async {
    final receiptNo = await repository.saveReceipt(
      [draft(description: 'Peti dibatalkan', price: 7000)],
      customerName: 'Pelanggan backup',
      note: 'Nota untuk uji pembatalan',
    );
    final receipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    await repository.cancelReceipt(
      receiptId: (receipt['id'] as num).toInt(),
      reason: 'Salah input',
    );

    final backup = await repository.exportBackup();
    await repository.restoreBackup(backup);

    final restored = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    expect(restored['status'], 'cancelled');
    final jobs = await repository.jobsForReceipt((restored['id'] as num).toInt());
    expect(jobs, hasLength(1));
    expect(jobs.single['status'], 'cancelled');
    expect(jobs.single['cancellation_reason'], 'Salah input');
  });

  test('restore preserves sparse high IDs and allows new records afterward', () async {
    final receiptNo = await repository.saveReceipt(
      [draft(description: 'Peti ID lama', price: 12000)],
      customerName: 'Pelanggan ID',
    );
    final oldReceipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    final oldReceiptId = (oldReceipt['id'] as num).toInt();
    await repository.addReceiptPayment(
      receiptId: oldReceiptId,
      amount: 2000,
      paymentMethod: 'transfer',
      note: 'DP sebelum backup',
    );

    final oldCashSessionId = await repository.startCashSession(
      date: DateTime.now(),
      openingBalance: 5000,
    );
    await repository.addCashExpense(
      sessionId: oldCashSessionId,
      amount: 1000,
      category: 'Operasional',
    );

    final backup = Map<String, dynamic>.from(await repository.exportBackup());

    void moveIds(String table, {String? foreignKey}) {
      final rows = (backup[table] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      for (final row in rows) {
        row['id'] = (row['id'] as num).toInt() + 1000;
        if (foreignKey != null) {
          row[foreignKey] = (row[foreignKey] as num).toInt() + 1000;
        }
      }
      backup[table] = rows;
    }

    moveIds('packing_receipts');
    moveIds('packing_transactions', foreignKey: 'receipt_id');
    moveIds('transaction_materials', foreignKey: 'transaction_id');
    moveIds('receipt_payments', foreignKey: 'receipt_id');
    moveIds('cash_sessions');
    moveIds('cash_expenses', foreignKey: 'session_id');

    await repository.restoreBackup(backup);

    final restoredReceipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == receiptNo);
    final restoredReceiptId = (restoredReceipt['id'] as num).toInt();
    expect(restoredReceiptId, oldReceiptId + 1000);
    final restoredJobs = await repository.jobsForReceipt(restoredReceiptId);
    expect(restoredJobs, hasLength(1));
    final restoredJobId = (restoredJobs.single['id'] as num).toInt();
    expect(restoredJobId, greaterThan(1000));
    expect(await repository.materialsFor(restoredJobId), hasLength(1));
    final restoredPayments = await repository.receiptPaymentsFor(restoredReceiptId);
    expect(restoredPayments.single['id'], greaterThan(1000));

    final newReceiptNo = await repository.saveReceipt(
      [draft(description: 'Peti ID baru', price: 9000)],
      customerName: 'Pelanggan baru',
    );
    final newReceipt = (await repository.listReceipts(limit: 10))
        .singleWhere((row) => row['receipt_no'] == newReceiptNo);
    final newReceiptId = (newReceipt['id'] as num).toInt();
    expect(newReceiptId, greaterThan(restoredReceiptId));
    await repository.addReceiptPayment(
      receiptId: newReceiptId,
      amount: 1000,
      paymentMethod: 'transfer',
    );
    final newPayments = await repository.receiptPaymentsFor(newReceiptId);
    expect(newPayments.single['id'], greaterThan(restoredPayments.single['id'] as num));

    final nextCashDate = DateTime.now().add(const Duration(days: 1));
    final newCashSessionId = await repository.startCashSession(
      date: nextCashDate,
      openingBalance: 7000,
    );
    expect(newCashSessionId, greaterThan(oldCashSessionId + 1000));
    await repository.addCashExpense(
      sessionId: newCashSessionId,
      amount: 500,
      category: 'Transport',
    );
    final newCashSummary = await repository.cashSessionSummary(newCashSessionId);
    final newExpenses = (newCashSummary['expenses'] as List)
        .cast<Map<String, Object?>>();
    expect(newExpenses.single['id'], greaterThan(1000));
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
