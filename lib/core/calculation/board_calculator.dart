class BoardFace {
  const BoardFace({required this.name,required this.lengthCm,required this.widthCm,this.enabled=true,this.overlapLengthCm=0,this.overlapWidthCm=0});
  final String name; final double lengthCm,widthCm,overlapLengthCm,overlapWidthCm; final bool enabled;
}
class BoardFaceArea { const BoardFaceArea(this.name,this.areaM2); final String name; final double areaM2; }
class BoardAreaResult { const BoardAreaResult(this.faces,this.totalM2,this.purchaseM2); final List<BoardFaceArea> faces; final double totalM2,purchaseM2; }
class BoardCalculator {
  static BoardAreaResult calculate(List<BoardFace> faces,{double wastePercent=0}) {
    if (!wastePercent.isFinite || wastePercent<0) throw ArgumentError('Waste tidak valid.');
    final rows=<BoardFaceArea>[]; var total=0.0;
    for(final f in faces) { if(!f.enabled) continue;
      if([f.lengthCm,f.widthCm].any((v)=>!v.isFinite||v<=0)||[f.overlapLengthCm,f.overlapWidthCm].any((v)=>!v.isFinite||v<0)) throw ArgumentError('Dimensi/overlap papan tidak valid.');
      final area=(f.lengthCm+f.overlapLengthCm)*(f.widthCm+f.overlapWidthCm)/10000;
      rows.add(BoardFaceArea(f.name,area)); total+=area;
    }
    return BoardAreaResult(List.unmodifiable(rows),total,total*(1+wastePercent/100));
  }
}
