import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/data/database/packing_database.dart';
import 'package:packing_pos/data/repositories/packing_transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  PackingTransactionDraft draft({double l = 0, double w = 0, double h = 0}) =>
      PackingTransactionDraft(
        itemDescription: 'Jasa tanpa ukuran',
        lengthCm: l, widthCm: w, heightCm: h,
        calculationSnapshot: const {'mode': 'test'},
        sellingPrice: 25000,
      );

  test('optional dimensions survive backup roundtrip', () async {
    await repository.saveReceipt([draft()]);
    final backup = await repository.exportBackup();
    await repository.restoreBackup(backup);
    final job = (await repository.listRecent(limit: 1)).single;
    expect(job['length_cm'], 0);
    expect(job['selling_price'], 25000);
  });

  test('negative and non-finite dimensions are rejected', () async {
    await expectLater(repository.saveReceipt([draft(l: -1)]), throwsArgumentError);
    await expectLater(repository.saveReceipt([draft(h: double.infinity)]), throwsArgumentError);
  });
}
