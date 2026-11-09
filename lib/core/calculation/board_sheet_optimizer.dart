class BoardCutPiece {
  const BoardCutPiece({
    required this.label,
    required this.widthCm,
    required this.heightCm,
    required this.quantity,
    this.allowRotation = true,
  });

  final String label;
  final double widthCm;
  final double heightCm;
  final int quantity;
  final bool allowRotation;

  double get areaM2 => widthCm * heightCm / 10000;
}

class BoardPlacement {
  const BoardPlacement({
    required this.label,
    required this.xCm,
    required this.yCm,
    required this.widthCm,
    required this.heightCm,
    required this.rotated,
  });

  final String label;
  final double xCm;
  final double yCm;
  final double widthCm;
  final double heightCm;
  final bool rotated;
}

class BoardSheet {
  const BoardSheet({
    required this.number,
    required this.placements,
    required this.usedAreaM2,
  });

  final int number;
  final List<BoardPlacement> placements;
  final double usedAreaM2;
}

class BoardSheetPlan {
  const BoardSheetPlan({
    required this.sheetWidthCm,
    required this.sheetHeightCm,
    required this.kerfAllowanceCm,
    required this.sheets,
    required this.totalPieceAreaM2,
  });

  final double sheetWidthCm;
  final double sheetHeightCm;
  final double kerfAllowanceCm;
  final List<BoardSheet> sheets;
  final double totalPieceAreaM2;

  int get sheetCount => sheets.length;
  double get purchasedAreaM2 =>
      sheetCount * sheetWidthCm * sheetHeightCm / 10000;
  double get wasteAreaM2 => purchasedAreaM2 - totalPieceAreaM2;
  double get utilizationPercent =>
      purchasedAreaM2 == 0 ? 0 : totalPieceAreaM2 / purchasedAreaM2 * 100;
}

/// Guillotine-style best-short-side-fit sheet nesting. Kerf is conservatively
/// reserved on the right and top of each cut rectangle. This is a practical
/// estimate, not a guaranteed globally optimal cutting solution.
class BoardSheetOptimizer {
  static BoardSheetPlan optimize({
    required double sheetWidthCm,
    required double sheetHeightCm,
    required double kerfAllowanceCm,
    required List<BoardCutPiece> pieces,
  }) {
    if ([sheetWidthCm, sheetHeightCm].any((v) => !v.isFinite || v <= 0)) {
      throw ArgumentError('Ukuran lembar papan harus lebih dari nol.');
    }
    if (!kerfAllowanceCm.isFinite || kerfAllowanceCm < 0) {
      throw ArgumentError('Kerf papan tidak valid.');
    }

    final expanded = <BoardCutPiece>[];
    var totalArea = 0.0;
    for (final piece in pieces) {
      if (piece.label.trim().isEmpty ||
          !piece.widthCm.isFinite ||
          !piece.heightCm.isFinite ||
          piece.widthCm <= 0 ||
          piece.heightCm <= 0 ||
          piece.quantity < 0 ||
          piece.quantity > 10000) {
        throw ArgumentError('Data potongan papan tidak valid.');
      }
      final fitsNormal = piece.widthCm + kerfAllowanceCm <= sheetWidthCm &&
          piece.heightCm + kerfAllowanceCm <= sheetHeightCm;
      final fitsRotated = piece.allowRotation &&
          piece.heightCm + kerfAllowanceCm <= sheetWidthCm &&
          piece.widthCm + kerfAllowanceCm <= sheetHeightCm;
      if (!fitsNormal && !fitsRotated) {
        throw ArgumentError(
          'Potongan ${piece.label} tidak muat pada ukuran lembar papan.',
        );
      }
      for (var i = 0; i < piece.quantity; i++) {
        expanded.add(piece);
        totalArea += piece.areaM2;
      }
    }

    expanded.sort((a, b) =>
        (b.widthCm * b.heightCm).compareTo(a.widthCm * a.heightCm));
    final workSheets = <_WorkingSheet>[];

    for (final piece in expanded) {
      _PlacementChoice? best;
      for (var sheetIndex = 0; sheetIndex < workSheets.length; sheetIndex++) {
        final sheet = workSheets[sheetIndex];
        for (var freeIndex = 0; freeIndex < sheet.freeRects.length; freeIndex++) {
          final free = sheet.freeRects[freeIndex];
          best = _choose(
            best,
            sheetIndex,
            freeIndex,
            free,
            piece,
            rotated: false,
            kerf: kerfAllowanceCm,
          );
          if (piece.allowRotation) {
            best = _choose(
              best,
              sheetIndex,
              freeIndex,
              free,
              piece,
              rotated: true,
              kerf: kerfAllowanceCm,
            );
          }
        }
      }

      if (best == null) {
        final sheet = _WorkingSheet(sheetWidthCm, sheetHeightCm);
        workSheets.add(sheet);
        final free = sheet.freeRects.single;
        best = _choose(
          null,
          workSheets.length - 1,
          0,
          free,
          piece,
          rotated: false,
          kerf: kerfAllowanceCm,
        );
        if (best == null && piece.allowRotation) {
          best = _choose(
            null,
            workSheets.length - 1,
            0,
            free,
            piece,
            rotated: true,
            kerf: kerfAllowanceCm,
          );
        }
        if (best == null) {
          throw ArgumentError('Potongan papan tidak dapat ditempatkan.');
        }
      }

      final sheet = workSheets[best.sheetIndex];
      final free = sheet.freeRects.removeAt(best.freeIndex);
      final placedWidth = best.rotated ? piece.heightCm : piece.widthCm;
      final placedHeight = best.rotated ? piece.widthCm : piece.heightCm;
      final reservedWidth = placedWidth + kerfAllowanceCm;
      final reservedHeight = placedHeight + kerfAllowanceCm;
      sheet.placements.add(BoardPlacement(
        label: piece.label,
        xCm: free.x,
        yCm: free.y,
        widthCm: placedWidth,
        heightCm: placedHeight,
        rotated: best.rotated,
      ));
      sheet.usedAreaM2 += piece.areaM2;

      final remainingWidth = free.width - reservedWidth;
      final remainingHeight = free.height - reservedHeight;
      if (remainingWidth > 0 && remainingHeight > 0) {
        if (remainingWidth > remainingHeight) {
          sheet.freeRects.add(_FreeRect(
            free.x + reservedWidth,
            free.y,
            remainingWidth,
            free.height,
          ));
          sheet.freeRects.add(_FreeRect(
            free.x,
            free.y + reservedHeight,
            reservedWidth,
            remainingHeight,
          ));
        } else {
          sheet.freeRects.add(_FreeRect(
            free.x + reservedWidth,
            free.y,
            remainingWidth,
            reservedHeight,
          ));
          sheet.freeRects.add(_FreeRect(
            free.x,
            free.y + reservedHeight,
            free.width,
            remainingHeight,
          ));
        }
      } else if (remainingWidth > 0) {
        sheet.freeRects.add(_FreeRect(
          free.x + reservedWidth,
          free.y,
          remainingWidth,
          free.height,
        ));
      } else if (remainingHeight > 0) {
        sheet.freeRects.add(_FreeRect(
          free.x,
          free.y + reservedHeight,
          free.width,
          remainingHeight,
        ));
      }
      _prune(sheet.freeRects);
    }

    final result = workSheets.asMap().entries.map((entry) => BoardSheet(
      number: entry.key + 1,
      placements: List.unmodifiable(entry.value.placements),
      usedAreaM2: entry.value.usedAreaM2,
    )).toList();

    return BoardSheetPlan(
      sheetWidthCm: sheetWidthCm,
      sheetHeightCm: sheetHeightCm,
      kerfAllowanceCm: kerfAllowanceCm,
      sheets: List.unmodifiable(result),
      totalPieceAreaM2: totalArea,
    );
  }

  static _PlacementChoice? _choose(
    _PlacementChoice? current,
    int sheetIndex,
    int freeIndex,
    _FreeRect free,
    BoardCutPiece piece, {
    required bool rotated,
    required double kerf,
  }) {
    final width = (rotated ? piece.heightCm : piece.widthCm) + kerf;
    final height = (rotated ? piece.widthCm : piece.heightCm) + kerf;
    if (width > free.width + 0.000001 ||
        height > free.height + 0.000001) {
      return current;
    }
    final leftoverW = free.width - width;
    final leftoverH = free.height - height;
    final shortSide = leftoverW < leftoverH ? leftoverW : leftoverH;
    final longSide = leftoverW > leftoverH ? leftoverW : leftoverH;
    if (current == null ||
        shortSide < current.shortSide ||
        (shortSide == current.shortSide && longSide < current.longSide)) {
      return _PlacementChoice(
        sheetIndex: sheetIndex,
        freeIndex: freeIndex,
        rotated: rotated,
        shortSide: shortSide,
        longSide: longSide,
      );
    }
    return current;
  }

  static void _prune(List<_FreeRect> rects) {
    for (var i = rects.length - 1; i >= 0; i--) {
      for (var j = 0; j < rects.length; j++) {
        if (i == j) continue;
        if (rects[j].contains(rects[i])) {
          rects.removeAt(i);
          break;
        }
      }
    }
  }
}

class _WorkingSheet {
  _WorkingSheet(double width, double height)
      : freeRects = [_FreeRect(0, 0, width, height)];

  final List<_FreeRect> freeRects;
  final List<BoardPlacement> placements = [];
  double usedAreaM2 = 0;
}

class _FreeRect {
  const _FreeRect(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;

  bool contains(_FreeRect other) =>
      other.x >= x &&
      other.y >= y &&
      other.x + other.width <= x + width &&
      other.y + other.height <= y + height;
}

class _PlacementChoice {
  const _PlacementChoice({
    required this.sheetIndex,
    required this.freeIndex,
    required this.rotated,
    required this.shortSide,
    required this.longSide,
  });

  final int sheetIndex;
  final int freeIndex;
  final bool rotated;
  final double shortSide;
  final double longSide;
}
