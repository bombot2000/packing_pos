import 'package:flutter/services.dart';

import 'rupiah.dart';

/// Parses whole Rupiah amounts from digits with optional visual separators.
int? parseRupiah(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

/// Formats a value for an editable Rupiah field without the currency prefix.
String groupThousands(int value) => formatRupiah(value).replaceFirst('Rp ', '');

/// Adds thousands separators while the user types.
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    if (digits.length > 12) return oldValue;
    final text = groupThousands(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
