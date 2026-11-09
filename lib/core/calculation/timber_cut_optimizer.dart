class TimberCutPiece {
  const TimberCutPiece({
    required this.label,
    required this.lengthCm,
    required this.quantity,
  });

  final String label;
  final double lengthCm;
  final int quantity;
}

class TimberCutPlacement {
  const TimberCutPlacement({
    required this.label,
    required this.lengthCm,
  });

  final String label;
  final double lengthCm;
}

class TimberCutBin {
  const TimberCutBin({
    required this.number,
    required this.cuts,
    required this.usedLengthCm,
    required this.remainingLengthCm,
  });

  final int number;
  final List<TimberCutPlacement> cuts;
  /// Includes saw kerf between cuts, but not after the final cut.
  final double usedLengthCm;
  final double remainingLengthCm;
}

class TimberCutPlan {
  const TimberCutPlan({
    required this.stockLengthCm,
    required this.kerfCm,
    required this.bins,
    required this.totalPieceLengthCm,
    required this.totalKerfCm,
  });

  final double stockLengthCm;
  final double kerfCm;
  final List<TimberCutBin> bins;
  final double totalPieceLengthCm;
  final double totalKerfCm;

  int get stockCount => bins.length;
  double get purchasedLengthMeters => stockCount * stockLengthCm / 100;
  double get leftoverLengthCm =>
      stockCount * stockLengthCm - totalPieceLengthCm - totalKerfCm;
}

/// First-fit decreasing heuristic. This is a practical cutting estimate, not
/// a mathematically guaranteed minimum-stock solution.
class TimberCutOptimizer {
  static TimberCutPlan optimize({
    required double stockLengthCm,
    required double kerfCm,
    required List<TimberCutPiece> pieces,
  }) {
    if (!stockLengthCm.isFinite || stockLengthCm <= 0) {
      throw ArgumentError('Panjang stok kayu harus lebih dari nol.');
    }
    if (!kerfCm.isFinite || kerfCm < 0) {
      throw ArgumentError('Lebar mata gergaji tidak valid.');
    }

    final expanded = <TimberCutPlacement>[];
    var totalLength = 0.0;
    for (final piece in pieces) {
      if (piece.label.trim().isEmpty ||
          !piece.lengthCm.isFinite ||
          piece.lengthCm <= 0 ||
          piece.quantity < 0 ||
          piece.quantity > 10000) {
        throw ArgumentError('Data potongan kayu tidak valid.');
      }
      if (piece.lengthCm > stockLengthCm) {
        throw ArgumentError(
          'Potongan ${piece.label} (${piece.lengthCm} cm) melebihi panjang stok ${stockLengthCm} cm.',
        );
      }
      for (var i = 0; i < piece.quantity; i++) {
        expanded.add(TimberCutPlacement(
          label: piece.label,
          lengthCm: piece.lengthCm,
        ));
        totalLength += piece.lengthCm;
      }
    }

    expanded.sort((a, b) => b.lengthCm.compareTo(a.lengthCm));
    final bins = <_WorkingBin>[];
    for (final cut in expanded) {
      _WorkingBin? target;
      for (final bin in bins) {
        final required = cut.lengthCm + (bin.cuts.isEmpty ? 0 : kerfCm);
        if (bin.usedLengthCm + required <= stockLengthCm + 0.000001) {
          target = bin;
          break;
        }
      }
      if (target == null) {
        target = _WorkingBin();
        bins.add(target);
      }
      if (target.cuts.isNotEmpty) target.usedLengthCm += kerfCm;
      target.cuts.add(cut);
      target.usedLengthCm += cut.lengthCm;
    }

    final result = bins.asMap().entries.map((entry) => TimberCutBin(
      number: entry.key + 1,
      cuts: List.unmodifiable(entry.value.cuts),
      usedLengthCm: entry.value.usedLengthCm,
      remainingLengthCm: (stockLengthCm - entry.value.usedLengthCm).clamp(0, stockLengthCm),
    )).toList();

    final totalKerf = result.fold<double>(
      0,
      (sum, bin) => sum + (bin.cuts.length > 1 ? (bin.cuts.length - 1) * kerfCm : 0),
    );
    return TimberCutPlan(
      stockLengthCm: stockLengthCm,
      kerfCm: kerfCm,
      bins: List.unmodifiable(result),
      totalPieceLengthCm: totalLength,
      totalKerfCm: totalKerf,
    );
  }
}

class _WorkingBin {
  final List<TimberCutPlacement> cuts = [];
  double usedLengthCm = 0;
}
