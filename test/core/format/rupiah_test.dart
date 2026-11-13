import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/format/rupiah.dart';

void main() {
  test('formatRupiah memakai titik ribuan', () {
    expect(formatRupiah(0), 'Rp 0');
    expect(formatRupiah(999), 'Rp 999');
    expect(formatRupiah(1000), 'Rp 1.000');
    expect(formatRupiah(150000), 'Rp 150.000');
    expect(formatRupiah(1250000), 'Rp 1.250.000');
    expect(formatRupiah(null), 'Rp 0');
  });
}
