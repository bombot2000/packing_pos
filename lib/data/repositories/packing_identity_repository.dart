import '../../data/database/packing_database.dart';

/// Local business identity shown in the app and on printed receipts.
class PackingIdentityRepository {
  PackingIdentityRepository({PackingDatabase? database})
      : _database = database ?? PackingDatabase.instance;

  final PackingDatabase _database;

  static const defaults = <String, String>{
    'business_name': 'Packing POS',
    'business_address': '',
    'business_phone': '',
  };

  Future<Map<String, String>> getSettings() async {
    final db = await _database.database;
    final rows = await db.query('app_settings',
        where: 'key IN (?, ?, ?)',
        whereArgs: defaults.keys.toList());
    final values = <String, String>{...defaults};
    for (final row in rows) {
      values[row['key'] as String] = row['value'] as String;
    }
    return values;
  }

  Future<void> saveSettings({
    required String businessName,
    String address = '',
    String phone = '',
  }) async {
    final name = businessName.trim();
    if (name.isEmpty) throw ArgumentError('Nama usaha tidak boleh kosong.');
    if (name.length > 60) throw ArgumentError('Nama usaha maksimal 60 karakter.');
    if (address.trim().length > 120) {
      throw ArgumentError('Alamat maksimal 120 karakter.');
    }
    if (phone.trim().length > 30) {
      throw ArgumentError('Nomor telepon maksimal 30 karakter.');
    }
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final values = <String, String>{
        'business_name': name,
        'business_address': address.trim(),
        'business_phone': phone.trim(),
      };
      for (final entry in values.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
