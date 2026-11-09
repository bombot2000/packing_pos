import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/board_sheet_optimizer.dart';

void main() {
  test('nests two perpendicular rectangles on one sheet', () {
    final plan = BoardSheetOptimizer.optimize(
      sheetWidthCm: 100,
      sheetHeightCm: 100,
      kerfAllowanceCm: 0,
      pieces: const [
        BoardCutPiece(label: 'Panel A', widthCm: 60, heightCm: 40, quantity: 1),
        BoardCutPiece(label: 'Panel B', widthCm: 40, heightCm: 60, quantity: 1),
      ],
    );

    expect(plan.sheetCount, 1);
    expect(plan.totalPieceAreaM2, closeTo(0.48, 0.000001));
    expect(plan.utilizationPercent, closeTo(48, 0.000001));
    expect(plan.sheets.single.placements.length, 2);
  });

  test('rotates a panel when only the rotated orientation fits', () {
    final plan = BoardSheetOptimizer.optimize(
      sheetWidthCm: 100,
      sheetHeightCm: 50,
      kerfAllowanceCm: 0,
      pieces: const [
        BoardCutPiece(label: 'Panel', widthCm: 50, heightCm: 100, quantity: 1),
      ],
    );
    expect(plan.sheetCount, 1);
    expect(plan.sheets.single.placements.single.rotated, isTrue);
  });

  test('rejects a panel larger than a sheet', () {
    expect(
      () => BoardSheetOptimizer.optimize(
        sheetWidthCm: 100,
        sheetHeightCm: 50,
        kerfAllowanceCm: 0,
        pieces: const [
          BoardCutPiece(label: 'Panel', widthCm: 101, heightCm: 60, quantity: 1),
        ],
      ),
      throwsArgumentError,
    );
  });
}
