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

    test('accepts empty optional app setting values', () {
      final backup = validBackup();
      backup['app_settings'] = [
        {
          'key': 'optional_printer_alias',
          'value': '',
          'updated_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      expect(() => PackingBackupValidator.validate(backup), returnsNormally);
    });


    test('accepts migrated version 4 receipts with historical partial payments', () {
      final backup = validBackup(version: 4);
      backup['service_types'] = <Map<String, Object?>>[];
      backup['packing_transactions']![0]['receipt_id'] = 1;
      backup['packing_receipts'] = [
        {
          'id': 1,
          'receipt_no': 'RCP-20261109-000001',
          'customer_name': 'Pelanggan uji',
          'total_amount': 20000,
          'paid_amount': 5000,
          'status': 'open',
          'note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
          'updated_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      backup['receipt_payments'] = [
        {
          'id': 1,
          'receipt_id': 1,
          'amount': 2000,
          'payment_method': 'cash',
          'note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
        {
          'id': 2,
          'receipt_id': 1,
          'amount': 3000,
          'payment_method': 'transfer',
          'note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];

      final data = PackingBackupValidator.validate(backup);
      expect(data['packing_receipts'], hasLength(1));
      expect(data['receipt_payments'], hasLength(2));
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
      final duplicate = Map<String, Object>.from(
        backup['packing_transactions']![0] as Map,
      );
      duplicate['id'] = 2;
      backup['packing_transactions']!.add(duplicate);
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('rejects payment history that does not match cached paid amount', () {
      final backup = validBackup();
      backup['transaction_payments'] = [
        {
          'id': 1,
          'transaction_id': 1,
          'amount': 4000,
          'payment_method': 'cash',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('rejects completed transaction with a partial payment history', () {
      final backup = validBackup();
      backup['packing_transactions']![0]['paid_amount'] = 10000;
      backup['packing_transactions']![0]['status'] = 'completed';
      backup['transaction_payments'] = [
        {
          'id': 1,
          'transaction_id': 1,
          'amount': 10000,
          'payment_method': 'cash',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];
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
