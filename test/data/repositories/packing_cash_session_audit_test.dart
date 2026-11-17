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

  test('tutup buka kembali dan tutup ulang mempertahankan audit serta pengeluaran', () async {
    final sessionId = await repository.startCashSession(
      date: DateTime.now(),
      openingBalance: 1000,
    );
    await repository.addCashExpense(
      sessionId: sessionId,
      amount: 200,
      category: 'Operasional',
      note: 'Parkir',
    );
    await repository.closeCashSession(
      sessionId: sessionId,
      countedBalance: 800,
      note: 'Penutupan pertama',
    );

    await expectLater(
      repository.reopenCashSession(sessionId: sessionId, reason: '  '),
      throwsArgumentError,
    );
    final firstEvents = await repository.cashSessionEvents(sessionId);
    expect(firstEvents, hasLength(1));
    expect(firstEvents.single['event_type'], 'closed');

    await repository.reopenCashSession(
      sessionId: sessionId,
      reason: 'Ada koreksi pencatatan',
    );
    final reopened = await repository.findCashSession(DateTime.now());
    expect(reopened!['status'], 'open');
    expect(reopened['expected_balance'], isNull);
    expect(reopened['counted_balance'], isNull);
    expect(await database.query('cash_expenses', where: 'session_id = ?', whereArgs: [sessionId]), hasLength(1));

    await repository.closeCashSession(
      sessionId: sessionId,
      countedBalance: 700,
      note: 'Penutupan kedua',
    );
    final events = await repository.cashSessionEvents(sessionId);
    expect(events.map((event) => event['event_type']).toList(), ['closed', 'reopened', 'closed']);
    expect(events[1]['reason'], 'Ada koreksi pencatatan');
    expect(events[1]['snapshot_json'], contains('"expected_balance":800'));
    expect(events[1]['snapshot_json'], contains('"counted_balance":800'));
    expect(events[1]['snapshot_json'], contains('"difference":0'));

    final backup = await repository.exportBackup();
    expect(backup['version'], 9);
    expect(backup['cash_session_events'], hasLength(3));
    await repository.restoreBackup(backup);
    final restored = await repository.findCashSession(DateTime.now());
    expect(restored!['status'], 'closed');
    expect(restored['counted_balance'], 700);
    expect(await repository.cashSessionEvents(sessionId), hasLength(3));
    expect(await database.query('cash_expenses', where: 'session_id = ?', whereArgs: [sessionId]), hasLength(1));
  });
}
