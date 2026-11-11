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

    test('validates cash session and expense relationships in version 7 backups', () {
      final backup = validBackup(version: 7);
      backup['packing_receipts'] = [
        {'id': 1, 'receipt_no': 'RCP-1', 'customer_name': '', 'total_amount': 20000, 'discount_amount': 0, 'paid_amount': 0, 'status': 'open', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z', 'updated_at': '2026-11-09T00:00:00.000Z'},
      ];
      backup['packing_transactions']![0]['receipt_id'] = 1;
      backup['packing_transactions']![0]['quantity'] = 1;
      backup['packing_transactions']![0]['unit_price'] = 20000;
      backup['service_types'] = <Map<String, Object?>>[];
      backup['customers'] = <Map<String, Object?>>[];
      backup['receipt_payments'] = <Map<String, Object?>>[];
      backup['packing_receipts']![0]['total_amount'] = 20000;
      backup['cash_sessions'] = [
        {'id': 1, 'date_key': '2026-11-09', 'opening_balance': 10000, 'expected_balance': null, 'counted_balance': null, 'difference': null, 'status': 'open', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z', 'closed_at': null},
      ];
      backup['cash_expenses'] = [
        {'id': 1, 'session_id': 1, 'amount': 1000, 'category': 'Operasional', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z'},
      ];
      expect(PackingBackupValidator.validate(backup)['cash_expenses'], hasLength(1));
      backup['cash_expenses']![0]['session_id'] = 999;
      expect(() => PackingBackupValidator.validate(backup), throwsFormatException);
    });

    test('rejects impossible calendar dates for cash sessions', () {
      final backup = validBackup(version: 7);
      backup['packing_receipts'] = [
        {'id': 1, 'receipt_no': 'RCP-1', 'customer_name': '', 'total_amount': 20000, 'discount_amount': 0, 'paid_amount': 0, 'status': 'open', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z', 'updated_at': '2026-11-09T00:00:00.000Z'},
      ];
      backup['packing_transactions']![0]['receipt_id'] = 1;
      backup['packing_transactions']![0]['quantity'] = 1;
      backup['packing_transactions']![0]['unit_price'] = 20000;
      backup['service_types'] = <Map<String, Object?>>[];
      backup['customers'] = <Map<String, Object?>>[];
      backup['receipt_payments'] = <Map<String, Object?>>[];
      backup['cash_sessions'] = [
        {'id': 1, 'date_key': '2026-02-30', 'opening_balance': 1000, 'expected_balance': null, 'counted_balance': null, 'difference': null, 'status': 'open', 'note': '', 'created_at': '2026-02-28T00:00:00.000Z', 'closed_at': null},
      ];
      backup['cash_expenses'] = <Map<String, Object?>>[];

      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('accepts negative expected cash and validates signed difference', () {
      final backup = validBackup(version: 7);
      backup['packing_receipts'] = [
        {'id': 1, 'receipt_no': 'RCP-1', 'customer_name': '', 'total_amount': 20000, 'discount_amount': 0, 'paid_amount': 0, 'status': 'open', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z', 'updated_at': '2026-11-09T00:00:00.000Z'},
      ];
      backup['packing_transactions']![0]['receipt_id'] = 1;
      backup['packing_transactions']![0]['quantity'] = 1;
      backup['packing_transactions']![0]['unit_price'] = 20000;
      backup['service_types'] = <Map<String, Object?>>[];
      backup['customers'] = <Map<String, Object?>>[];
      backup['receipt_payments'] = <Map<String, Object?>>[];
      backup['cash_sessions'] = [
        {'id': 1, 'date_key': '2026-11-09', 'opening_balance': 1000, 'expected_balance': -5000, 'counted_balance': 0, 'difference': 5000, 'status': 'closed', 'note': '', 'created_at': '2026-11-09T00:00:00.000Z', 'closed_at': '2026-11-09T10:00:00.000Z'},
      ];
      backup['cash_expenses'] = <Map<String, Object?>>[];
      expect(PackingBackupValidator.validate(backup)['cash_sessions'], hasLength(1));

      backup['cash_sessions']![0]['difference'] = 4999;
      expect(() => PackingBackupValidator.validate(backup), throwsFormatException);
    });

    test('migrates version 1 legacy transaction into a receipt without losing paid balance', () {
      final backup = validBackup(version: 1);
      final data = PackingBackupValidator.validate(backup);
      final transaction = data['packing_transactions']!.single;
      final receipt = data['packing_receipts']!.single;

      expect(transaction['receipt_id'], transaction['id']);
      expect(transaction['quantity'], 1);
      expect(transaction['unit_price'], transaction['selling_price']);
      expect(receipt['total_amount'], 20000);
      expect(receipt['paid_amount'], 5000);
      expect(receipt['status'], 'open');
      expect(data['receipt_payments'], isEmpty);
    });

    test('migrates version 3 transaction payment rows into receipt payment history', () {
      final backup = validBackup(version: 3);
      backup['service_types'] = <Map<String, Object?>>[];
      backup['transaction_payments'] = [
        {
          'id': 1,
          'transaction_id': 1,
          'amount': 2000,
          'payment_method': 'cash',
          'note': 'DP',
          'created_at': '2026-11-09T01:00:00.000Z',
        },
        {
          'id': 2,
          'transaction_id': 1,
          'amount': 3000,
          'payment_method': 'transfer',
          'note': 'Pelunasan sebagian',
          'created_at': '2026-11-09T02:00:00.000Z',
        },
      ];
      final data = PackingBackupValidator.validate(backup);
      final receipt = data['packing_receipts']!.single;
      final payments = data['receipt_payments']!;

      expect(receipt['paid_amount'], 5000);
      expect(payments, hasLength(2));
      expect(payments.map((row) => row['amount']), [2000, 3000]);
      expect(payments.map((row) => row['note']), ['DP', 'Pelunasan sebagian']);
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
      backup['packing_transactions']![0]['quantity'] = 1;
      backup['packing_transactions']![0]['unit_price'] = 20000;
      backup['service_types'] = <Map<String, Object?>>[];
      backup['customers'] = <Map<String, Object?>>[];
      backup['receipt_payments'] = <Map<String, Object?>>[];
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

    test('rejects an open receipt whose balance is fully paid', () {
      final backup = validBackup(version: 7);
      backup['packing_transactions']![0]['receipt_id'] = 1;
      backup['packing_transactions']![0]['quantity'] = 1;
      backup['packing_transactions']![0]['unit_price'] = 20000;
      backup['service_types'] = <Map<String, Object?>>[];
      backup['customers'] = <Map<String, Object?>>[];
      backup['receipt_payments'] = [
        {
          'id': 1,
          'receipt_id': 1,
          'amount': 20000,
          'payment_method': 'cash',
          'note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      backup['packing_receipts'] = [
        {
          'id': 1,
          'receipt_no': 'RCP-20261109-000001',
          'customer_name': '',
          'total_amount': 20000,
          'discount_amount': 0,
          'paid_amount': 20000,
          'status': 'open',
          'note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
          'updated_at': '2026-11-09T00:00:00.000Z',
        },
      ];
      backup['cash_sessions'] = <Map<String, Object?>>[];
      backup['cash_expenses'] = <Map<String, Object?>>[];

      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
      );
    });

    test('validates material subtotal against actual quantity and snapshot price', () {
      final backup = validBackup();
      backup['transaction_materials'] = [
        {
          'id': 1,
          'transaction_id': 1,
          'material_name_snapshot': 'Kayu',
          'unit_snapshot': 'batang',
          'calculated_quantity': 2.5,
          'actual_quantity': 2.5,
          'unit_price_snapshot': 1000,
          'subtotal': 2500,
          'adjustment_note': '',
          'created_at': '2026-11-09T00:00:00.000Z',
        },
      ];

      expect(() => PackingBackupValidator.validate(backup), returnsNormally);

      backup['transaction_materials']![0]['subtotal'] = 2499;
      expect(
        () => PackingBackupValidator.validate(backup),
        throwsFormatException,
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

    test('rejects version 4 receipt with paid balance but no payment history', () {
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
      backup['receipt_payments'] = <Map<String, Object?>>[];

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
