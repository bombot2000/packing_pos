enum PackingFastener { nails, screws }

class PackingRates {
  const PackingRates({
    this.woodPerLonjor = 3500,
    this.woodStickLengthCm = 200,
    this.woodLengthMultiplier = 4,
    this.woodWidthMultiplier = 4,
    this.woodHeightMultiplier = 4,
    this.topSlats = 1,
    this.bottomSlats = 1,
    this.frontSlats = 1,
    this.backSlats = 1,
    this.leftSlats = 1,
    this.rightSlats = 1,
    this.screwPerPiece = 320,
    this.nailPerGram = 25,
    this.nailsPerKg = 430,
    this.laborPerPackage = 15000,
    this.electricityPerPackage = 1500,
    this.overheadPerPackage = 5000,
    this.fastenersPerPackage = 68,
    this.boardSheetsPerPackage = 0,
    this.boardPricePerSheet = 0,
    this.marginPercent = 25,
  });

  final double woodPerLonjor, woodStickLengthCm;
  final double woodLengthMultiplier, woodWidthMultiplier, woodHeightMultiplier;
  // Number of extra slats on each face; 1 slat divides a face into 2 sections.
  final int topSlats, bottomSlats, frontSlats, backSlats, leftSlats, rightSlats;
  final double screwPerPiece, nailPerGram;
  final int nailsPerKg, fastenersPerPackage;
  final double laborPerPackage, electricityPerPackage, overheadPerPackage;
  final double boardSheetsPerPackage, boardPricePerSheet, marginPercent;

  Map<String, Object?> toJson() => {
    'woodPerLonjor': woodPerLonjor, 'woodStickLengthCm': woodStickLengthCm,
    'woodLengthMultiplier': woodLengthMultiplier, 'woodWidthMultiplier': woodWidthMultiplier,
    'woodHeightMultiplier': woodHeightMultiplier,
    'topSlats': topSlats, 'bottomSlats': bottomSlats, 'frontSlats': frontSlats,
    'backSlats': backSlats, 'leftSlats': leftSlats, 'rightSlats': rightSlats,
    'screwPerPiece': screwPerPiece, 'nailPerGram': nailPerGram,
    'nailsPerKg': nailsPerKg, 'laborPerPackage': laborPerPackage,
    'electricityPerPackage': electricityPerPackage, 'overheadPerPackage': overheadPerPackage,
    'fastenersPerPackage': fastenersPerPackage, 'boardSheetsPerPackage': boardSheetsPerPackage,
    'boardPricePerSheet': boardPricePerSheet, 'marginPercent': marginPercent,
  };

  factory PackingRates.fromJson(Map<String, dynamic> json) => PackingRates(
    woodPerLonjor: (json['woodPerLonjor'] as num?)?.toDouble() ?? 3500,
    woodStickLengthCm: (json['woodStickLengthCm'] as num?)?.toDouble() ?? 200,
    woodLengthMultiplier: (json['woodLengthMultiplier'] as num?)?.toDouble() ?? 4,
    woodWidthMultiplier: (json['woodWidthMultiplier'] as num?)?.toDouble() ?? 4,
    woodHeightMultiplier: (json['woodHeightMultiplier'] as num?)?.toDouble() ?? 4,
    topSlats: (json['topSlats'] as num?)?.toInt() ?? 1,
    bottomSlats: (json['bottomSlats'] as num?)?.toInt() ?? 1,
    frontSlats: (json['frontSlats'] as num?)?.toInt() ?? 1,
    backSlats: (json['backSlats'] as num?)?.toInt() ?? 1,
    leftSlats: (json['leftSlats'] as num?)?.toInt() ?? 1,
    rightSlats: (json['rightSlats'] as num?)?.toInt() ?? 1,
    screwPerPiece: (json['screwPerPiece'] as num?)?.toDouble() ?? 320,
    nailPerGram: (json['nailPerGram'] as num?)?.toDouble() ?? 25,
    nailsPerKg: (json['nailsPerKg'] as num?)?.toInt() ?? 430,
    laborPerPackage: (json['laborPerPackage'] as num?)?.toDouble() ?? 15000,
    electricityPerPackage: (json['electricityPerPackage'] as num?)?.toDouble() ?? 1500,
    overheadPerPackage: (json['overheadPerPackage'] as num?)?.toDouble() ?? 5000,
    fastenersPerPackage: (json['fastenersPerPackage'] as num?)?.toInt() ?? 68,
    boardSheetsPerPackage: (json['boardSheetsPerPackage'] as num?)?.toDouble() ?? 0,
    boardPricePerSheet: (json['boardPricePerSheet'] as num?)?.toDouble() ?? 0,
    marginPercent: (json['marginPercent'] as num?)?.toDouble() ?? 25,
  );
}

class PackingCostResult {
  const PackingCostResult({
    required this.frameLengthCm, required this.slatLengthCm,
    required this.slatCountPerPackage, required this.woodSticksPerPackage,
    required this.woodCost, required this.fastenerQuantity, required this.fastenerUnit,
    required this.fastenerCost, required this.laborCost, required this.electricityCost,
    required this.overheadCost, required this.boardQuantity, required this.boardCost,
    required this.totalCost, required this.suggestedPrice, required this.roundedPrice,
  });
  final double frameLengthCm, slatLengthCm, woodCost, fastenerQuantity, fastenerCost;
  final int slatCountPerPackage, woodSticksPerPackage;
  final double laborCost, electricityCost, overheadCost, boardQuantity, boardCost;
  final double totalCost, suggestedPrice, roundedPrice;
  final String fastenerUnit;

  factory PackingCostResult.calculate({
    required double lengthCm, required double widthCm, required double heightCm,
    int packageCount = 1, PackingFastener fastener = PackingFastener.nails,
    PackingRates rates = const PackingRates(), bool includeBoard = false,
  }) {
    final values = [lengthCm, widthCm, heightCm, rates.woodPerLonjor,
      rates.woodStickLengthCm, rates.woodLengthMultiplier,
      rates.woodWidthMultiplier, rates.woodHeightMultiplier, rates.screwPerPiece,
      rates.nailPerGram, rates.laborPerPackage, rates.electricityPerPackage,
      rates.overheadPerPackage, rates.boardSheetsPerPackage,
      rates.boardPricePerSheet, rates.marginPercent];
    final slatCounts = [rates.topSlats, rates.bottomSlats, rates.frontSlats,
      rates.backSlats, rates.leftSlats, rates.rightSlats];
    if (values.any((v) => !v.isFinite || v < 0) ||
        slatCounts.any((v) => v < 0) ||
        lengthCm <= 0 || widthCm <= 0 || heightCm <= 0 ||
        packageCount <= 0 || rates.woodStickLengthCm <= 0 ||
        rates.nailsPerKg <= 0 || rates.fastenersPerPackage < 0 ||
        rates.marginPercent < 0 || rates.marginPercent >= 100) {
      throw ArgumentError('Ukuran, jumlah bilah, tarif, jumlah koli, atau margin tidak valid.');
    }
    final frame = rates.woodLengthMultiplier * lengthCm +
        rates.woodWidthMultiplier * widthCm +
        rates.woodHeightMultiplier * heightCm;
    // Slats on top/bottom and front/back run along the package length.
    // Slats on left/right run along its width.
    final slatCount = slatCounts.fold<int>(0, (sum, count) => sum + count);
    final slatLength = (rates.topSlats + rates.bottomSlats +
        rates.frontSlats + rates.backSlats) * lengthCm +
        (rates.leftSlats + rates.rightSlats) * widthCm;
    final sticks = ((frame + slatLength) / rates.woodStickLengthCm).ceil();
    final wood = sticks * rates.woodPerLonjor * packageCount;
    final count = rates.fastenersPerPackage * packageCount;
    final fastenerQty = fastener == PackingFastener.nails
        ? count * 1000 / rates.nailsPerKg : count.toDouble();
    final fastenerCost = fastener == PackingFastener.nails
        ? fastenerQty * rates.nailPerGram : fastenerQty * rates.screwPerPiece;
    final labor = rates.laborPerPackage * packageCount;
    final electricity = rates.electricityPerPackage * packageCount;
    final overhead = rates.overheadPerPackage * packageCount;
    final boardQty = includeBoard ? rates.boardSheetsPerPackage * packageCount : 0.0;
    final board = boardQty * rates.boardPricePerSheet;
    final total = wood + fastenerCost + labor + electricity + overhead + board;
    final suggested = total / (1 - rates.marginPercent / 100);
    return PackingCostResult(
      frameLengthCm: frame, slatLengthCm: slatLength,
      slatCountPerPackage: slatCount, woodSticksPerPackage: sticks,
      fastenerQuantity: fastenerQty,
      fastenerUnit: fastener == PackingFastener.nails ? 'gram' : 'buah',
      woodCost: wood, fastenerCost: fastenerCost, laborCost: labor,
      electricityCost: electricity, overheadCost: overhead,
      boardQuantity: boardQty, boardCost: board,
      totalCost: total, suggestedPrice: suggested,
      roundedPrice: (suggested / 1000).ceil() * 1000.0,
    );
  }
}
