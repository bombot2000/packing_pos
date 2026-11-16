import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/features/packing/packing_cost_engine.dart';

void main() {
  test('base frame and custom default slats are calculated separately', () {
    final result = PackingCostResult.calculate(
      lengthCm: 110, widthCm: 55, heightCm: 56,
    );
    expect(result.frameLengthCm, 884);
    // One extra slat on each face: 4 slats run along length, 2 along width.
    expect(result.slatCountPerPackage, 6);
    expect(result.slatLengthCm, 550);
    expect(result.woodSticksPerPackage, 9);
    expect(result.woodCost, 31500);
    expect(result.fastenerQuantity, closeTo(158.1395, 0.001));
    expect(result.fastenerCost, closeTo(3953.488, 0.01));
    expect(result.totalCost, closeTo(56953.488, 0.01));
    expect(result.roundedPrice, 76000);
    expect(result.boardCost, 0);
  });

  test('one slat divides a face into two and two slats into three', () {
    const rates = PackingRates(
      topSlats: 1, bottomSlats: 2, frontSlats: 0,
      backSlats: 3, leftSlats: 0, rightSlats: 1,
    );
    final result = PackingCostResult.calculate(
      lengthCm: 110, widthCm: 55, heightCm: 56, rates: rates,
    );
    expect(result.slatCountPerPackage, 7);
    expect(result.slatLengthCm, 6 * 110 + 1 * 55);
  });

  test('slat cut length follows the selected dimension independently per face', () {
    const rates = PackingRates(
      topSlats: 1, topSlatAxis: SlatCutAxis.width,
      bottomSlats: 2, bottomSlatAxis: SlatCutAxis.length,
      frontSlats: 1, frontSlatAxis: SlatCutAxis.height,
      backSlats: 1, backSlatAxis: SlatCutAxis.height,
      leftSlats: 1, leftSlatAxis: SlatCutAxis.height,
      rightSlats: 1, rightSlatAxis: SlatCutAxis.width,
    );
    final result = PackingCostResult.calculate(
      lengthCm: 110, widthCm: 55, heightCm: 56, rates: rates,
    );
    expect(result.slatLengthCm, 55 + 2 * 110 + 3 * 56 + 55);
  });

  test('rejects a cut longer than one stock lonjor', () {
    expect(
      () => PackingCostResult.calculate(
        lengthCm: 201, widthCm: 43, heightCm: 45,
      ),
      throwsArgumentError,
    );
  });

  test('quantity multiplies wood and per-package operating costs', () {
    final result = PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45, packageCount: 3,
    );
    expect(result.woodSticksPerPackage, 5);
    expect(result.woodCost, 52500);
    expect(result.laborCost, 45000);
    expect(result.electricityCost, 4500);
    expect(result.overheadCost, 15000);
  });

  test('screw mode and optional board are calculated separately', () {
    final result = PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45,
      fastener: PackingFastener.screws,
      includeBoard: true,
      rates: const PackingRates(boardSheetsPerPackage: 2, boardPricePerSheet: 12000),
    );
    expect(result.fastenerQuantity, 68);
    expect(result.fastenerCost, 21760);
    expect(result.boardQuantity, 2);
    expect(result.boardCost, 24000);
  });

  test('unused invalid board inputs do not affect estimates when board is off', () {
    final result = PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45,
      rates: const PackingRates(
        boardSheetsPerPackage: -2,
        boardPricePerSheet: -12000,
      ),
      includeBoard: false,
    );
    expect(result.boardQuantity, 0);
    expect(result.boardCost, 0);
    expect(result.totalCost, greaterThan(0));
  });

  test('invalid board inputs are rejected when optional board is enabled', () {
    expect(
      () => PackingCostResult.calculate(
        lengthCm: 54, widthCm: 43, heightCm: 45,
        rates: const PackingRates(boardSheetsPerPackage: -1),
        includeBoard: true,
      ),
      throwsArgumentError,
    );
  });

  test('rejects invalid dimensions, negative slats and invalid margin', () {
    expect(() => PackingCostResult.calculate(
      lengthCm: 0, widthCm: 43, heightCm: 45,
    ), throwsArgumentError);
    expect(() => PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45,
      rates: const PackingRates(topSlats: -1),
    ), throwsArgumentError);
    expect(() => PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45,
      rates: const PackingRates(marginPercent: 100),
    ), throwsArgumentError);
    expect(() => PackingCostResult.calculate(
      lengthCm: 54, widthCm: 43, heightCm: 45,
      rates: const PackingRates(topSlatAxis: SlatCutAxis.height),
    ), throwsArgumentError);
  });

  test('saved reusable rates reset order-specific board values', () {
    const rates = PackingRates(
      woodPerLonjor: 5200,
      boardSheetsPerPackage: 3,
      boardPricePerSheet: 25000,
      marginPercent: 28,
    );

    final saved = rates.toSettingsJson();
    final restored = PackingRates.fromJson(saved);

    expect(restored.woodPerLonjor, 5200);
    expect(restored.marginPercent, 28);
    expect(restored.boardSheetsPerPackage, 0);
    expect(restored.boardPricePerSheet, 0);
  });

  test('legacy saved axes are normalized to valid face dimensions', () {
    final restored = PackingRates.fromJson({
      'topSlatAxis': 'height',
      'bottomSlatAxis': 'height',
      'frontSlatAxis': 'width',
      'backSlatAxis': 'length',
      'leftSlatAxis': 'length',
      'rightSlatAxis': 'height',
    });
    expect(restored.topSlatAxis, SlatCutAxis.length);
    expect(restored.bottomSlatAxis, SlatCutAxis.length);
    expect(restored.frontSlatAxis, SlatCutAxis.length);
    expect(restored.backSlatAxis, SlatCutAxis.length);
    expect(restored.leftSlatAxis, SlatCutAxis.width);
    expect(restored.rightSlatAxis, SlatCutAxis.height);
    expect(() => PackingCostResult.calculate(
      lengthCm: 100, widthCm: 50, heightCm: 40, rates: restored,
    ), returnsNormally);
  });

  test('custom rates and six face slat counts survive JSON round trip', () {
    const rates = PackingRates(
      woodPerLonjor: 5000, woodStickLengthCm: 250,
      screwPerPiece: 400, nailPerGram: 30, nailsPerKg: 500,
      fastenersPerPackage: 44, laborPerPackage: 20000,
      electricityPerPackage: 2500, overheadPerPackage: 6000,
      boardSheetsPerPackage: 1.5, boardPricePerSheet: 18000,
      marginPercent: 30, topSlats: 2, bottomSlats: 0,
      frontSlats: 3, backSlats: 1, leftSlats: 4, rightSlats: 2,
      topSlatAxis: SlatCutAxis.width, bottomSlatAxis: SlatCutAxis.length,
      frontSlatAxis: SlatCutAxis.height, backSlatAxis: SlatCutAxis.height,
      leftSlatAxis: SlatCutAxis.height, rightSlatAxis: SlatCutAxis.width,
    );
    final restored = PackingRates.fromJson(rates.toJson());
    expect(restored.woodPerLonjor, 5000);
    expect(restored.woodStickLengthCm, 250);
    expect(restored.fastenersPerPackage, 44);
    expect(restored.boardSheetsPerPackage, 1.5);
    expect(restored.marginPercent, 30);
    expect(restored.topSlats, 2);
    expect(restored.bottomSlats, 0);
    expect(restored.frontSlats, 3);
    expect(restored.backSlats, 1);
    expect(restored.leftSlats, 4);
    expect(restored.rightSlats, 2);
    expect(restored.topSlatAxis, SlatCutAxis.width);
    expect(restored.bottomSlatAxis, SlatCutAxis.length);
    expect(restored.frontSlatAxis, SlatCutAxis.height);
    expect(restored.backSlatAxis, SlatCutAxis.height);
    expect(restored.leftSlatAxis, SlatCutAxis.height);
    expect(restored.rightSlatAxis, SlatCutAxis.width);
  });
}
