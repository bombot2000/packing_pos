import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/timber_cut_optimizer.dart';

void main() {
  test('first-fit decreasing groups frame cuts into stock sticks', () {
    final plan = TimberCutOptimizer.optimize(
      stockLengthCm: 400,
      kerfCm: 0.3,
      pieces: const [
        TimberCutPiece(label: 'Tiang', lengthCm: 200, quantity: 2),
        TimberCutPiece(label: 'Rel', lengthCm: 150, quantity: 2),
        TimberCutPiece(label: 'Bilah', lengthCm: 100, quantity: 1),
      ],
    );

    expect(plan.stockCount, 2);
    expect(plan.totalPieceLengthCm, closeTo(800, 0.000001));
    expect(plan.totalKerfCm, closeTo(0.9, 0.000001));
    expect(plan.leftoverLengthCm, closeTo(0.9, 0.000001));
  });

  test('rejects a cut longer than available stock', () {
    expect(
      () => TimberCutOptimizer.optimize(
        stockLengthCm: 300,
        kerfCm: 0.3,
        pieces: const [
          TimberCutPiece(label: 'Rel panjang', lengthCm: 301, quantity: 1),
        ],
      ),
      throwsArgumentError,
    );
  });
}
