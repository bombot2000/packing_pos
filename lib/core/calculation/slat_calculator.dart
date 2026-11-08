class SlatInput {
  const SlatInput({required this.faceLengthCm, required this.faceWidthCm, required this.slatWidthCm, required this.gapCm, this.leftMarginCm=0, this.rightMarginCm=0, this.slatLengthCm});
  final double faceLengthCm, faceWidthCm, slatWidthCm, gapCm, leftMarginCm, rightMarginCm;
  final double? slatLengthCm;
}
class SlatResult {
  const SlatResult({required this.count, required this.occupiedWidthCm, required this.remainingWidthCm, required this.totalLinearMeters});
  final int count;
  final double occupiedWidthCm, remainingWidthCm, totalLinearMeters;
}
class SlatCalculator {
  /// Fixed gap is preserved; remaining width is reported at the edge.
  static SlatResult calculate(SlatInput x) {
    for (final v in [x.faceLengthCm,x.faceWidthCm,x.slatWidthCm]) {
      if (!v.isFinite || v<=0) throw ArgumentError('Dimensi harus lebih dari 0.');
    }
    for (final v in [x.gapCm,x.leftMarginCm,x.rightMarginCm]) {
      if (!v.isFinite || v<0) throw ArgumentError('Celah/margin tidak boleh negatif.');
    }
    final usable=x.faceWidthCm-x.leftMarginCm-x.rightMarginCm;
    if (usable<=0) throw ArgumentError('Margin melebihi bidang.');
    final n=((usable+x.gapCm)/(x.slatWidthCm+x.gapCm)).floor();
    final occupied=n==0?0.0:n*x.slatWidthCm+(n-1)*x.gapCm;
    final len=x.slatLengthCm??x.faceLengthCm;
    if (!len.isFinite || len<=0) throw ArgumentError('Panjang bilah tidak valid.');
    // Formula guarantees occupied <= usable; no rounding-up or gap expansion.
    return SlatResult(count:n,occupiedWidthCm:occupied,remainingWidthCm:usable-occupied,totalLinearMeters:n*len/100);
  }
}
