import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/packing_faces.dart';
void main() {
  test('six closed faces total 2.8 square meters for 100x60x50 cm', () {
    const d=PackingDimensions(lengthCm:100,widthCm:60,heightCm:50);
    final r=PackingFacesCalculator.calculate(dimensions:d,configs:const [
      FaceBuildConfig(face:PackingFace.top,buildType:FaceBuildType.closedBoard),
      FaceBuildConfig(face:PackingFace.bottom,buildType:FaceBuildType.closedBoard),
      FaceBuildConfig(face:PackingFace.front,buildType:FaceBuildType.closedBoard),
      FaceBuildConfig(face:PackingFace.back,buildType:FaceBuildType.closedBoard),
      FaceBuildConfig(face:PackingFace.left,buildType:FaceBuildType.closedBoard),
      FaceBuildConfig(face:PackingFace.right,buildType:FaceBuildType.closedBoard),
    ]);
    expect(r.totalBoardAreaM2,closeTo(2.8,0.000001));
  });
  test('duplicate face configuration is rejected', () {
    expect(()=>PackingFacesCalculator.calculate(dimensions:const PackingDimensions(lengthCm:10,widthCm:10,heightCm:10),configs:const [
      FaceBuildConfig(face:PackingFace.top,buildType:FaceBuildType.none),
      FaceBuildConfig(face:PackingFace.top,buildType:FaceBuildType.none),
    ]),throwsArgumentError);
  });
}
