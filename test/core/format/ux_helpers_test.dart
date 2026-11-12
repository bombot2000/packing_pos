import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/format/dimensions.dart';
import 'package:packing_pos/core/format/friendly_error.dart';
import 'package:packing_pos/core/format/money_input.dart';

void main() {
  group('Rupiah input helpers', () {
    test('parses formatted amounts', () {
      expect(parseRupiah('1.250.000'), 1250000);
      expect(parseRupiah('Rp 50000'), 50000);
      expect(parseRupiah(''), isNull);
      expect(parseRupiah('abc'), isNull);
    });

    test('formats while typing and limits length', () {
      final formatter = RupiahInputFormatter();
      TextEditingValue type(String value) => formatter.formatEditUpdate(
        TextEditingValue.empty, TextEditingValue(text: value));
      expect(type('1250000').text, '1.250.000');
      expect(type('007').text, '7');
      expect(type('').text, '');
      const old = TextEditingValue(text: '999.999.999.999');
      expect(formatter.formatEditUpdate(old,
        const TextEditingValue(text: '9999999999999')).text, old.text);
      expect(groupThousands(1500), '1.500');
    });
  });

  group('friendlyError', () {
    test('keeps useful messages and removes technical prefixes', () {
      expect(friendlyError(StateError('Nota sudah lunas.')), 'Nota sudah lunas.');
      expect(friendlyError(ArgumentError('Nominal tidak valid.')), 'Nominal tidak valid.');
      expect(friendlyError(const FormatException('Backup rusak.')), 'Backup rusak.');
      expect(friendlyError(Exception('Gagal')), 'Gagal');
    });

    test('hides database internals and handles empty text', () {
      expect(friendlyError(Exception('SqliteException(1): no such table')), contains('backup'));
      expect(friendlyError(StateError('')), 'Terjadi kesalahan. Silakan coba lagi.');
    });
  });

  group('dimensionsLabel', () {
    test('omits unrecorded dimensions', () {
      expect(dimensionsLabel(0, 0, 0), isNull);
      expect(dimensionsLabel(null, null, null), isNull);
      expect(dimensionsLabel(120, 80, 60), '120.0 × 80.0 × 60.0 cm');
    });
  });
}
