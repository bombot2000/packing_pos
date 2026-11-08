import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/data/repositories/packing_transaction_repository.dart';

void main() {
  group('MaterialUsageDraft', () {
    test('uses calculated quantity by default', () {
      const material = MaterialUsageDraft(
        name: 'Kayu rangka',
        unit: 'm',
        calculatedQuantity: 2.5,
        unitPrice: 12000,
      );
      expect(material.actualQuantity, 2.5);
      expect(material.subtotal, 30000);
    });

    test('manual quantity is retained and subtotal uses actual quantity', () {
      const material = MaterialUsageDraft(
        name: 'Papan',
        unit: 'm2',
        calculatedQuantity: 1.2,
        actualQuantity: 1.5,
        unitPrice: 20000,
        adjustmentNote: 'Tambahan potongan',
      );
      expect(material.calculatedQuantity, 1.2);
      expect(material.actualQuantity, 1.5);
      expect(material.subtotal, 30000);
    });
  });
}
