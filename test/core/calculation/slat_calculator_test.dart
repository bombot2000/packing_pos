import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/slat_calculator.dart';
void main() {
 test('fixed gap remains unchanged and edge remainder is reported', () {
  final r=SlatCalculator.calculate(const SlatInput(faceLengthCm:100,faceWidthCm:100,slatWidthCm:5,gapCm:5));
  expect(r.count,10); expect(r.occupiedWidthCm,95); expect(r.remainingWidthCm,5); expect(r.totalLinearMeters,10);
 });
 test('invalid dimensions are rejected', () {
  expect(()=>SlatCalculator.calculate(const SlatInput(faceLengthCm:0,faceWidthCm:50,slatWidthCm:4,gapCm:2)),throwsArgumentError);
 });
}
