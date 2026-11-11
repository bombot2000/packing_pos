/// Formats a whole-Rupiah amount with dot thousands separators, e.g. Rp 1.250.000.
String formatRupiah(Object? value) {
  final n = (value as num?)?.toInt() ?? 0;
  final digits = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}Rp $buffer';
}
