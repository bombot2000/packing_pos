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

  test('customer master saves, searches, edits and deactivates without deleting', () async {
    final id = await repository.saveCustomer(
      name: 'PT Contoh',
      phone: '08123456789',
      address: 'Malang',
      note: 'Pelanggan tetap',
    );
    expect(await repository.listCustomers(), hasLength(1));
    expect((await repository.listCustomers(query: 'contoh')).single['id'], id);

    await repository.saveCustomer(
      id: id,
      name: 'PT Contoh Baru',
      phone: '08987654321',
      address: 'Batu',
    );
    final updated = (await repository.listCustomers()).single;
    expect(updated['name'], 'PT Contoh Baru');
    expect(updated['phone'], '08987654321');
    expect(updated['address'], 'Batu');

    await repository.deactivateCustomer(id);
    expect(await repository.listCustomers(), isEmpty);
    final all = await repository.listCustomers(activeOnly: false);
    expect(all, hasLength(1));
    expect(all.single['is_active'], 0);
  });

  test('customer master rejects blank and duplicate names', () async {
    await expectLater(
      repository.saveCustomer(name: '   '),
      throwsArgumentError,
    );
    await repository.saveCustomer(name: 'Nama Sama');
    await expectLater(
      repository.saveCustomer(name: 'nama sama'),
      throwsArgumentError,
    );
  });
}
