class MaterialCostLine {
  const MaterialCostLine({required this.name,required this.quantity,required this.unitPrice});
  final String name; final double quantity; final int unitPrice;
  int get subtotal=>(quantity*unitPrice).round();
}
class PriceResult {
  const PriceResult({required this.materialCost,required this.laborCost,required this.overheadCost,required this.baseCost,required this.markupPercent,required this.sellingPrice});
  final int materialCost,laborCost,overheadCost,baseCost,sellingPrice; final double markupPercent;
  int get grossProfit=>sellingPrice-baseCost;
}
class PricingCalculator {
  static PriceResult calculate({required List<MaterialCostLine> materials,required int laborCost,required int overheadCost,required double markupPercent}) {
    if(laborCost<0||overheadCost<0||!markupPercent.isFinite||markupPercent<0) throw ArgumentError('Biaya atau markup tidak valid.');
    var material=0;
    for(final line in materials) {
      if(!line.quantity.isFinite||line.quantity<0||line.unitPrice<0) throw ArgumentError('Kuantitas dan harga bahan tidak boleh negatif.');
      material+=line.subtotal;
    }
    final base=material+laborCost+overheadCost;
    return PriceResult(materialCost:material,laborCost:laborCost,overheadCost:overheadCost,baseCost:base,markupPercent:markupPercent,sellingPrice:(base*(1+markupPercent/100)).round());
  }
  static int priceForMargin({required int baseCost,required double marginPercent}) {
    if(baseCost<0||!marginPercent.isFinite||marginPercent<0||marginPercent>=100) throw ArgumentError('Target margin harus 0 sampai kurang dari 100%.');
    return (baseCost/(1-marginPercent/100)).round();
  }
}
