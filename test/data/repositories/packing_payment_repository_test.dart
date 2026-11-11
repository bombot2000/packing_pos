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
      calculationSnapshot: {'mode': 'test'},
      sellingPrice: total,
    ));
    return (await repository.listReceipts(limit: 1)).single;
  }

  group('qty dan diskon nota', () {
    test('mengalikan harga satuan dengan qty lalu mengurangi diskon nota', () async {
      final receiptNo = await repository.saveReceipt(
        const [
          PackingTransactionDraft(
            customerName: 'Pelanggan qty',
            itemDescription: 'Kardus ukuran sama',
            quantity: 3,
            lengthCm: 100,
            widthCm: 80,
            heightCm: 60,
            calculationSnapshot: {'mode': 'test'},
            sellingPrice: 20000,
          ),
        ],
        discountAmount: 5000,
      );

      final receipt = (await repository.findReceiptByNo(receiptNo))!;
      final job = (await repository.jobsForReceipt(receipt['id'] as int)).single;
      expect(job['quantity'], 3);
      expect(job['unit_price'], 20000);
      expect(job['selling_price'], 60000);
      expect(receipt['discount_amount'], 5000);
      expect(receipt['total_amount'], 55000);
      final report = await repository.reportSummary();
      final totals = report['totals'] as Map<String, Object?>;
      expect(totals['sales_total'], 55000);
      final backup = await repository.exportBackup();
      expect(backup['version'], 7);
      await repository.restoreBackup(backup);
      final restored = (await repository.findReceiptByNo(receiptNo))!;
      expect(restored['total_amount'], 55000);
      expect((await repository.jobsForReceipt(restored['id'] as int)).single['quantity'], 3);
    });

    test('menolak qty nol dan diskon melebihi subtotal', () async {
      const invalidQty = PackingTransactionDraft(
        lengthCm: 10,
        widthCm: 10,
        heightCm: 10,
        quantity: 0,
        calculationSnapshot: {'mode': 'test'},
        sellingPrice: 10000,
      );
      await expectLater(repository.saveReceipt([invalidQty]), throwsArgumentError);

      const validJob = PackingTransactionDraft(
        lengthCm: 10,
        widthCm: 10,
        heightCm: 10,
        quantity: 2,
        calculationSnapshot: {'mode': 'test'},
        sellingPrice: 10000,
      );
      await expectLater(
        repository.saveReceipt([validJob], discountAmount: 20001),
        throwsArgumentError,
      );
    });
  });

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
        const PackingTransactionDraft(
          customerName: 'Pelanggan gabungan',
          itemDescription: 'Kardus A',
          lengthCm: 100,
          widthCm: 80,
          heightCm: 60,
          calculationSnapshot: {'mode': 'test'},
          sellingPrice: 60000,
        ),
        const PackingTransactionDraft(
          customerName: 'Pelanggan gabungan',
          itemDescription: 'Kardus B',
          lengthCm: 50,
          widthCm: 40,
          heightCm: 30,
          calculationSnapshot: {'mode': 'test'},
          sellingPrice: 40000,
        ),
        const PackingTransactionDraft(
          customerName: 'Pelanggan gabungan',
          itemDescription: 'Peti C',
          lengthCm: 70,
          widthCm: 60,
          heightCm: 50,
          calculationSnapshot: {'mode': 'test'},
          sellingPrice: 25000,
        ),
      ]);
      final receipts = await repository.listReceipts(limit: 10);
      final receipt = receipts.singleWhere((row) => row['receipt_no'] == receiptNo);
      final receiptId = receipt['id'] as int;
      expect(receiptNo, startsWith('RCP-'));
      expect(receipt['total_amount'], 125000);
      final jobs = await repository.jobsForReceipt(receiptId);
      expect(jobs, hasLength(3));
      expect(
        jobs.map((job) => job['item_description']).toSet(),
        {'Kardus A', 'Kardus B', 'Peti C'},
      );

      await repository.settleReceipt(
        receiptId: receiptId,
        amount: 125000,
        paymentMethod: 'qris',
      );

      expect(await repository.receiptPaymentsFor(receiptId), hasLength(1));
      final saved = await repository.findReceiptById(receiptId);
      expect(saved!['paid_amount'], 125000);
      expect(saved['status'], 'completed');
      final report = await repository.reportSummary();
      final totals = report['totals'] as Map<String, Object?>;
      expect(totals['receipt_count'], 1);
      expect(totals['paid_total'], 125000);
      expect(totals['sales_total'], 125000);
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

  group('edit nota sebelum pembayaran', () {
    test('mengubah pekerjaan dan total tanpa mengganti identitas nota', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      final receiptNo = receipt['receipt_no'] as String;
      await repository.updateUnpaidReceipt(
        id,
        const [PackingTransactionDraft(
          customerName: 'Pelanggan baru', itemDescription: 'Barang direvisi',
          quantity: 2, lengthCm: 120, widthCm: 90, heightCm: 70,
          calculationSnapshot: {'mode': 'edited'}, sellingPrice: 75000,
        )],
        customerName: 'Pelanggan baru', note: 'Catatan revisi', discountAmount: 5000,
      );
      final saved = (await repository.findReceiptById(id))!;
      expect(saved['receipt_no'], receiptNo);
      expect(saved['customer_name'], 'Pelanggan baru');
      expect(saved['total_amount'], 145000);
      expect(saved['discount_amount'], 5000);
      expect(saved['note'], 'Catatan revisi');
      final jobs = await repository.jobsForReceipt(id);
      expect(jobs, hasLength(1));
      expect(jobs.single['item_description'], 'Barang direvisi');
      expect(jobs.single['selling_price'], 150000);
    });

    test('menolak edit setelah pembayaran sebagian dan mempertahankan data', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.addReceiptPayment(receiptId: id, amount: 10000, paymentMethod: 'cash');
      await expectLater(
        repository.updateUnpaidReceipt(id, const [PackingTransactionDraft(
          itemDescription: 'Tidak boleh berubah', lengthCm: 10, widthCm: 10, heightCm: 10,
          calculationSnapshot: {'mode': 'test'}, sellingPrice: 1,
        )]),
        throwsStateError,
      );
      expect((await repository.findReceiptById(id))!['total_amount'], 100000);
      expect((await repository.jobsForReceipt(id)).single['item_description'], 'Barang uji');
      expect(await repository.receiptPaymentsFor(id), hasLength(1));
    });
  });

  group('pembatalan nota', () {
    test('membatalkan nota beserta seluruh pekerjaannya dan menolak pembayaran', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.cancelReceipt(receiptId: id, reason: 'Salah input');
      expect((await repository.findReceiptById(id))!['status'], 'cancelled');
      final jobs = await repository.jobsForReceipt(id);
      expect(jobs.every((j) => j['status'] == 'cancelled'), isTrue);
      expect(jobs.first['cancellation_reason'], 'Salah input');
      await expectLater(
        repository.settleReceipt(receiptId: id, amount: 100000, paymentMethod: 'cash'),
        throwsStateError,
      );
      final report = await repository.reportSummary();
      expect((report['totals'] as Map)['sales_total'], 0);
      expect((report['totals'] as Map)['cancelled_count'], 1);
    });

    test('alasan wajib dan nota tidak dapat dibatalkan dua kali', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await expectLater(repository.cancelReceipt(receiptId: id, reason: '  '), throwsArgumentError);
      await repository.cancelReceipt(receiptId: id, reason: 'Batal');
      await expectLater(repository.cancelReceipt(receiptId: id, reason: 'Lagi'), throwsStateError);
    });
  });

  group('tutup kas harian', () {
    test('menghitung saldo awal ditambah tunai dikurangi pengeluaran dan mencatat selisih', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.addReceiptPayment(receiptId: id, amount: 30000, paymentMethod: 'cash');
      final sessionId = await repository.startCashSession(date: DateTime.now(), openingBalance: 20000);
      await repository.addCashExpense(sessionId: sessionId, amount: 5000, category: 'Operasional', note: 'Parkir');
      var summary = await repository.cashSessionSummary(sessionId);
      expect(summary['cash_received'], 30000);
      expect(summary['expense_total'], 5000);
      expect(summary['expected_balance'], 45000);
      expect((summary['expenses'] as List), hasLength(1));
      await repository.closeCashSession(sessionId: sessionId, countedBalance: 44000, note: 'Selisih hitung');
      summary = await repository.cashSessionSummary(sessionId);
      final session = summary['session'] as Map;
      expect(session['status'], 'closed');
      expect(session['expected_balance'], 45000);
      expect(session['counted_balance'], 44000);
      expect(session['difference'], -1000);
      await expectLater(repository.addCashExpense(sessionId: sessionId, amount: 1000, category: 'Tambahan'), throwsStateError);
      await expectLater(repository.closeCashSession(sessionId: sessionId, countedBalance: 45000), throwsStateError);
    });

    test('menghitung dan mengunci pembayaran tunai transaksi legacy tanpa nota', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      final transactionId = await database.insert('packing_transactions', {
        'receipt_no': 'LEGACY-CASH-TEST',
        'receipt_id': null,
        'customer_name': 'Pelanggan lama',
        'item_description': 'Transaksi lama',
        'quantity': 1,
        'unit_price': 20000,
        'length_cm': 10,
        'width_cm': 10,
        'height_cm': 10,
        'calculation_snapshot': '{"mode":"legacy-test"}',
        'material_cost': 0,
        'labor_cost': 0,
        'overhead_cost': 0,
        'selling_price': 20000,
        'paid_amount': 0,
        'status': 'open',
        'note': '',
        'created_at': now,
        'updated_at': now,
      });
      final sessionId = await repository.startCashSession(
        date: DateTime.now(),
        openingBalance: 5000,
      );
      await repository.addPayment(
        transactionId: transactionId,
        amount: 7000,
        paymentMethod: 'cash',
      );
      final summary = await repository.cashSessionSummary(sessionId);
      expect(summary['cash_received'], 7000);
      expect(summary['expected_balance'], 12000);

      await repository.closeCashSession(
        sessionId: sessionId,
        countedBalance: 12000,
      );
      await expectLater(
        repository.addPayment(
          transactionId: transactionId,
          amount: 13000,
          paymentMethod: 'cash',
        ),
        throwsStateError,
      );
      expect(await repository.paymentsFor(transactionId), hasLength(1));
    });

    test('menampilkan riwayat sesi kas terbaru lebih dahulu', () async {
      final older = DateTime(2026, 10, 1);
      final newer = DateTime(2026, 10, 2);
      await repository.startCashSession(date: older, openingBalance: 10000);
      final newerId = await repository.startCashSession(
        date: newer,
        openingBalance: 20000,
      );
      await repository.closeCashSession(
        sessionId: newerId,
        countedBalance: 20000,
      );

      final history = await repository.listCashSessions();
      expect(history, hasLength(2));
      expect(history.first['date_key'], '2026-10-02');
      expect(history.first['status'], 'closed');
      expect(history.last['date_key'], '2026-10-01');
      expect(history.last['status'], 'open');
    });

    test('menolak pembayaran tunai setelah sesi kas ditutup', () async {
      final receipt = await createReceipt();
      final sessionId = await repository.startCashSession(date: DateTime.now(), openingBalance: 0);
      await repository.closeCashSession(sessionId: sessionId, countedBalance: 0);
      await expectLater(
        repository.addReceiptPayment(receiptId: receipt['id'] as int, amount: 10000, paymentMethod: 'cash'),
        throwsStateError,
      );
      expect(await repository.receiptPaymentsFor(receipt['id'] as int), isEmpty);
    });

    test('mencegah sesi kas ganda dan nominal awal atau pengeluaran tidak valid', () async {
      await expectLater(repository.startCashSession(date: DateTime.now(), openingBalance: -1), throwsArgumentError);
      final id = await repository.startCashSession(date: DateTime.now(), openingBalance: 0);
      await expectLater(repository.startCashSession(date: DateTime.now(), openingBalance: 100), throwsStateError);
      await expectLater(repository.addCashExpense(sessionId: id, amount: 0, category: 'Lainnya'), throwsArgumentError);
    });
  });

  group('pembayaran bertahap nota', () {
    test('DP lalu pelunasan mengubah status hanya saat sisa nol', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.addReceiptPayment(receiptId: id, amount: 40000, paymentMethod: 'cash');
      var saved = (await repository.findReceiptById(id))!;
      expect(saved['paid_amount'], 40000);
      expect(saved['status'], 'open');
      expect((await repository.jobsForReceipt(id)).single['status'], 'open');
      await repository.addReceiptPayment(receiptId: id, amount: 60000, paymentMethod: 'transfer');
      saved = (await repository.findReceiptById(id))!;
      expect(saved['paid_amount'], 100000);
      expect(saved['status'], 'completed');
      expect((await repository.jobsForReceipt(id)).single['status'], 'completed');
      expect(await repository.receiptPaymentsFor(id), hasLength(2));
    });

    test('menolak nominal nol, melebihi sisa, atau nota lunas', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await expectLater(repository.addReceiptPayment(receiptId: id, amount: 0, paymentMethod: 'cash'), throwsArgumentError);
      await expectLater(repository.addReceiptPayment(receiptId: id, amount: 100001, paymentMethod: 'cash'), throwsArgumentError);
      await repository.addReceiptPayment(receiptId: id, amount: 100000, paymentMethod: 'cash');
      await expectLater(repository.addReceiptPayment(receiptId: id, amount: 1, paymentMethod: 'cash'), throwsStateError);
    });

    test('laporan merinci penerimaan menurut metode pembayaran', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.addReceiptPayment(
        receiptId: id,
        amount: 30000,
        paymentMethod: 'cash',
      );
      await repository.addReceiptPayment(
        receiptId: id,
        amount: 20000,
        paymentMethod: 'transfer',
      );

      final report = await repository.reportSummary();
      final methods = (report['payment_methods'] as List)
          .cast<Map<String, Object?>>();
      expect(methods, hasLength(2));
      final cash = methods.firstWhere((row) => row['payment_method'] == 'cash');
      final transfer = methods.firstWhere((row) => row['payment_method'] == 'transfer');
      expect(cash['amount'], 30000);
      expect(cash['payment_count'], 1);
      expect(transfer['amount'], 20000);
      expect(transfer['payment_count'], 1);
      final totals = report['totals'] as Map<String, Object?>;
      expect(totals['paid_total'], 50000);
      expect(totals['cash_received_total'], 30000);
      expect(totals['non_cash_received_total'], 20000);

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final future = await repository.reportSummary(
        startDate: tomorrow,
        endDate: tomorrow.add(const Duration(days: 1)),
      );
      expect(future['payment_methods'], isEmpty);
    });

    test('laporan menghitung uang masuk dari tanggal pembayaran dan menghitung nota', () async {
      final receipt = await createReceipt();
      final id = receipt['id'] as int;
      await repository.addReceiptPayment(receiptId: id, amount: 30000, paymentMethod: 'cash');
      final all = (await repository.reportSummary())['totals'] as Map;
      expect(all['paid_total'], 30000);
      expect(all['receivable_total'], 70000);
      expect(all['open_count'], 1);
      expect(all['completed_count'], 0);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final future = (await repository.reportSummary(
        startDate: tomorrow, endDate: tomorrow.add(const Duration(days: 1)),
      ))['totals'] as Map;
      expect(future['paid_total'], 0);
    });
  });
}
