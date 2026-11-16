enum PackingFastener { nails, screws }

enum SlatCutAxis { length, width, height }

/// Counts stock lengths for one package using first-fit-decreasing cutting.
/// Each package gets an independent cutting plan; offcuts are never shared.
int _countLonjorForPackage(List<double> cuts, double stockLengthCm) {
  final sortedCuts = [...cuts]..sort((a, b) => b.compareTo(a));
  final usedLengths = <double>[];
  for (final cut in sortedCuts) {
    if (!cut.isFinite || cut <= 0 || cut > stockLengthCm) {
      throw ArgumentError('Ada potongan kayu yang melebihi panjang satu lonjor.');
    }
    final binIndex = usedLengths.indexWhere(
      (used) => used + cut <= stockLengthCm + 1e-9,
    );
    if (binIndex == -1) {
      usedLengths.add(cut);
    } else {
      usedLengths[binIndex] += cut;
    }
  }
  return usedLengths.length;
}

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
    this.topSlatAxis = SlatCutAxis.length,
    this.bottomSlatAxis = SlatCutAxis.length,
    this.frontSlatAxis = SlatCutAxis.length,
    this.backSlatAxis = SlatCutAxis.length,
    this.leftSlatAxis = SlatCutAxis.width,
    this.rightSlatAxis = SlatCutAxis.width,
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
  final SlatCutAxis topSlatAxis, bottomSlatAxis, frontSlatAxis, backSlatAxis, leftSlatAxis, rightSlatAxis;
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
    'topSlatAxis': topSlatAxis.name, 'bottomSlatAxis': bottomSlatAxis.name,
    'frontSlatAxis': frontSlatAxis.name, 'backSlatAxis': backSlatAxis.name,
    'leftSlatAxis': leftSlatAxis.name, 'rightSlatAxis': rightSlatAxis.name,
    'screwPerPiece': screwPerPiece, 'nailPerGram': nailPerGram,
    'nailsPerKg': nailsPerKg, 'laborPerPackage': laborPerPackage,
    'electricityPerPackage': electricityPerPackage, 'overheadPerPackage': overheadPerPackage,
    'fastenersPerPackage': fastenersPerPackage, 'boardSheetsPerPackage': boardSheetsPerPackage,
    'boardPricePerSheet': boardPricePerSheet, 'marginPercent': marginPercent,
  };

  /// Persists reusable tariffs only. Board quantity and price belong to
  /// an individual order and must start fresh for each estimate.
  Map<String, Object?> toSettingsJson() => {
    ...toJson(),
    'boardSheetsPerPackage': 0,
    'boardPricePerSheet': 0,
  };

  factory PackingRates.fromJson(Map<String, dynamic> json) {
    SlatCutAxis readAxis(
      String key,
      List<SlatCutAxis> allowed,
      SlatCutAxis fallback,
    ) {
      final stored = SlatCutAxis.values.where((axis) => axis.name == json[key]);
      final axis = stored.isEmpty ? fallback : stored.first;
      return allowed.contains(axis) ? axis : fallback;
    }

    return PackingRates(
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
    topSlatAxis: readAxis('topSlatAxis', const [SlatCutAxis.length, SlatCutAxis.width], SlatCutAxis.length),
    bottomSlatAxis: readAxis('bottomSlatAxis', const [SlatCutAxis.length, SlatCutAxis.width], SlatCutAxis.length),
    frontSlatAxis: readAxis('frontSlatAxis', const [SlatCutAxis.length, SlatCutAxis.height], SlatCutAxis.length),
    backSlatAxis: readAxis('backSlatAxis', const [SlatCutAxis.length, SlatCutAxis.height], SlatCutAxis.length),
    leftSlatAxis: readAxis('leftSlatAxis', const [SlatCutAxis.width, SlatCutAxis.height], SlatCutAxis.width),
    rightSlatAxis: readAxis('rightSlatAxis', const [SlatCutAxis.width, SlatCutAxis.height], SlatCutAxis.width),
    );
  }
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
      rates.overheadPerPackage, rates.marginPercent];
    // Board inputs are order-specific and must not invalidate an estimate
    // when the optional board is disabled.
    if (includeBoard) {
      values.add(rates.boardSheetsPerPackage);
      values.add(rates.boardPricePerSheet);
    }
    final slatCounts = [rates.topSlats, rates.bottomSlats, rates.frontSlats,
      rates.backSlats, rates.leftSlats, rates.rightSlats];
    bool axisAllowed(SlatCutAxis axis, List<SlatCutAxis> allowed) =>
        allowed.contains(axis);
    final validFaceAxes =
        axisAllowed(rates.topSlatAxis, const [SlatCutAxis.length, SlatCutAxis.width]) &&
        axisAllowed(rates.bottomSlatAxis, const [SlatCutAxis.length, SlatCutAxis.width]) &&
        axisAllowed(rates.frontSlatAxis, const [SlatCutAxis.length, SlatCutAxis.height]) &&
        axisAllowed(rates.backSlatAxis, const [SlatCutAxis.length, SlatCutAxis.height]) &&
        axisAllowed(rates.leftSlatAxis, const [SlatCutAxis.width, SlatCutAxis.height]) &&
        axisAllowed(rates.rightSlatAxis, const [SlatCutAxis.width, SlatCutAxis.height]);
    if (!validFaceAxes ||
        values.any((v) => !v.isFinite || v < 0) ||
        slatCounts.any((v) => v < 0) ||
        [rates.woodLengthMultiplier, rates.woodWidthMultiplier,
          rates.woodHeightMultiplier].any(
            (v) => v != v.roundToDouble(),
          ) ||
        lengthCm <= 0 || widthCm <= 0 || heightCm <= 0 ||
        packageCount <= 0 || rates.woodStickLengthCm <= 0 ||
        rates.nailsPerKg <= 0 || rates.fastenersPerPackage < 0 ||
        rates.marginPercent < 0 || rates.marginPercent >= 100) {
      throw ArgumentError('Ukuran, jumlah bilah, tarif, jumlah koli, atau margin tidak valid.');
    }
    final frame = rates.woodLengthMultiplier * lengthCm +
        rates.woodWidthMultiplier * widthCm +
        rates.woodHeightMultiplier * heightCm;
    final slatCount = slatCounts.fold<int>(0, (sum, count) => sum + count);
    double cutLength(SlatCutAxis axis) => switch (axis) {
      SlatCutAxis.length => lengthCm,
      SlatCutAxis.width => widthCm,
      SlatCutAxis.height => heightCm,
    };
    final slatLength = rates.topSlats * cutLength(rates.topSlatAxis) +
        rates.bottomSlats * cutLength(rates.bottomSlatAxis) +
        rates.frontSlats * cutLength(rates.frontSlatAxis) +
        rates.backSlats * cutLength(rates.backSlatAxis) +
        rates.leftSlats * cutLength(rates.leftSlatAxis) +
        rates.rightSlats * cutLength(rates.rightSlatAxis);
    // Build the actual cut list for one package using the same frame
    // multipliers as frameLengthCm. Defaults remain 4P + 4L + 4T.
    final cuts = <double>[
      ...List<double>.filled(rates.woodLengthMultiplier.toInt(), lengthCm),
      ...List<double>.filled(rates.woodWidthMultiplier.toInt(), widthCm),
      ...List<double>.filled(rates.woodHeightMultiplier.toInt(), heightCm),
      ...List<double>.filled(rates.topSlats, cutLength(rates.topSlatAxis)),
      ...List<double>.filled(rates.bottomSlats, cutLength(rates.bottomSlatAxis)),
      ...List<double>.filled(rates.frontSlats, cutLength(rates.frontSlatAxis)),
      ...List<double>.filled(rates.backSlats, cutLength(rates.backSlatAxis)),
      ...List<double>.filled(rates.leftSlats, cutLength(rates.leftSlatAxis)),
      ...List<double>.filled(rates.rightSlats, cutLength(rates.rightSlatAxis)),
    ];
    // Deliberately calculate each package separately: offcuts from one koli
    // cannot reduce the stock requirement of another koli.
    final sticks = _countLonjorForPackage(cuts, rates.woodStickLengthCm);
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
