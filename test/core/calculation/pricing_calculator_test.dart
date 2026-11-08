import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/pricing_calculator.dart';
void main() {
  test('separates material labor overhead and markup', () {
    final r=PricingCalculator.calculate(materials:const [MaterialCostLine(name:'Kayu',quantity:2,unitPrice:50000)],laborCost:30000,overheadCost:10000,markupPercent:25);
    expect(r.materialCost,100000); expect(r.baseCost,140000); expect(r.sellingPrice,175000);
  });
  test('target margin is distinct from markup', () {
    expect(PricingCalculator.priceForMargin(baseCost:140000,marginPercent:20),175000);
  });
}
