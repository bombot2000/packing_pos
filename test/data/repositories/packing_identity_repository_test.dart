import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packing_pos/data/database/packing_database.dart';
import 'package:packing_pos/data/repositories/packing_identity_repository.dart';

void main() {
  late Database database;
  late PackingIdentityRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final packingDatabase = await PackingDatabase.createForTesting(database);
    repository = PackingIdentityRepository(database: packingDatabase);
  });

  tearDown(() async => database.close());

  test('identity settings load defaults and persist custom values', () async {
    expect((await repository.getSettings())['business_name'], 'Packing POS');
    await repository.saveSettings(
      businessName: 'BOMBOT PACKING',
      address: 'Malang',
      phone: '08123456789',
    );
    final saved = await repository.getSettings();
    expect(saved['business_name'], 'BOMBOT PACKING');
    expect(saved['business_address'], 'Malang');
    expect(saved['business_phone'], '08123456789');
  });

  test('identity settings reject blank business name', () async {
    await expectLater(
      repository.saveSettings(businessName: '  '),
      throwsArgumentError,
    );
  });
}
