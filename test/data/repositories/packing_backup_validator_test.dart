import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/data/repositories/packing_backup_validator.dart';

Map<String, dynamic> validBackup({int version = 2}) => {
  'format': 'packing_pos_backup',
  'version': version,
  'packing_transactions': [
    {
      'id': 1,
      'receipt_no': 'PKG-20261109-000001',
      'length_cm': 100.0,
      'width_cm': 80.0,
      'height_cm': 60.0,
      'calculation_snapshot': '{"dimensionsCm":{"length":100}}',
      'material_cost': 10000,
      'labor_cost': 2000,
      'overhead_cost': 1000,
      'selling_price': 20000,
      'paid_amount': 5000,
      'status': 'open',
      'created_at': '2026-11-09T00:00:00.000Z',
      'updated_at': '2026-11-09T00:00:00.000Z',
    },
  ],
  'transaction_materials': <Map<String, Object?>>[],
  'transaction_payments': <Map<String, Object?>>[],
  'materials': <Map<String, Object?>>[],
  'app_settings': <Map<String, Object?>>[],
};

void main() {
  group('PackingBackupValidator', () {
    test('accepts a valid current backup', () {
      final data = PackingBackupValidator.validate(validBackup());
      expect(data['packing_transactions'], hasLength(1));
      expect(data['transaction_payments'], isEmpty);
    });

    test('accepts version 1 backups without the cancellation reason column', () {
      expect(
        () => PackingBackupValidator.validate(validBackup(version: 1)),
        returnsNormally,
      );
    });

    test('rejects malformed calculation snapshots before restore', () {
      final backup = validBackup();
      backup['packing_transactions']![0]['calculation_snapshot'] = '{broken';
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('rejects payment rows that reference a missing transaction', () {
      final backup = validBackup();
      backup['transaction_payments'] = [
        {
          'id': 1,
          'transaction_id': 999,
          'amount': 1000,
          'payment_method': 'cash',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('rejects duplicate receipt numbers', () {
      final backup = validBackup();
      backup['packing_transactions']!.add({
        ...backup['packing_transactions']![0],
        'id': 2,
      });
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('rejects payments exceeding the invoice total', () {
      final backup = validBackup();
      backup['transaction_payments'] = [
        {
          'id': 1,
          'transaction_id': 1,
          'amount': 25000,
          'payment_method': 'cash',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });
  });
}
