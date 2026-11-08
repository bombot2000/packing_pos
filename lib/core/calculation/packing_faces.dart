import 'board_calculator.dart';
import 'slat_calculator.dart';
enum PackingFace { top, bottom, front, back, left, right }
enum FaceBuildType { openSlat, closedBoard, none }
class FaceBuildConfig {
  const FaceBuildConfig({required this.face,required this.buildType,this.slatWidthCm=0,this.gapCm=0,this.leftMarginCm=0,this.rightMarginCm=0,this.boardOverlapLengthCm=0,this.boardOverlapWidthCm=0});
  final PackingFace face; final FaceBuildType buildType;
  final double slatWidthCm,gapCm,leftMarginCm,rightMarginCm,boardOverlapLengthCm,boardOverlapWidthCm;
}
class PackingDimensions {
  const PackingDimensions({required this.lengthCm,required this.widthCm,required this.heightCm});
  final double lengthCm,widthCm,heightCm;
  void validate() { if([lengthCm,widthCm,heightCm].any((v)=>!v.isFinite||v<=0)) throw ArgumentError('Panjang, lebar, dan tinggi harus lebih dari 0.'); }
  ({double length,double width}) faceSize(PackingFace face) {
    validate();
    switch(face) {
      case PackingFace.top:
      case PackingFace.bottom: return (length:lengthCm,width:widthCm);
      case PackingFace.front:
      case PackingFace.back: return (length:lengthCm,width:heightCm);
      case PackingFace.left:
      case PackingFace.right: return (length:widthCm,width:heightCm);
    }
  }
}
class FaceCalculation {
  const FaceCalculation({required this.face,required this.buildType,this.slat,this.boardAreaM2});
  final PackingFace face; final FaceBuildType buildType; final SlatResult? slat; final double? boardAreaM2;
}
class PackingFacesResult {
  const PackingFacesResult({required this.faces,required this.totalSlatMeters,required this.totalBoardAreaM2});
  final List<FaceCalculation> faces; final double totalSlatMeters,totalBoardAreaM2;
}
class PackingFacesCalculator {
  static PackingFacesResult calculate({required PackingDimensions dimensions,required List<FaceBuildConfig> configs}) {
    dimensions.validate();
    final seen=<PackingFace>{}; final rows=<FaceCalculation>[]; var slatMeters=0.0; var boardArea=0.0;
    for(final c in configs) {
      if(!seen.add(c.face)) throw ArgumentError('Konfigurasi bidang ganda: '+c.face.name);
      final size=dimensions.faceSize(c.face);
      switch(c.buildType) {
        case FaceBuildType.none:
          rows.add(FaceCalculation(face:c.face,buildType:c.buildType));
          break;
        case FaceBuildType.openSlat:
          final slat=SlatCalculator.calculate(SlatInput(faceLengthCm:size.length,faceWidthCm:size.width,slatWidthCm:c.slatWidthCm,gapCm:c.gapCm,leftMarginCm:c.leftMarginCm,rightMarginCm:c.rightMarginCm));
          slatMeters+=slat.totalLinearMeters;
          rows.add(FaceCalculation(face:c.face,buildType:c.buildType,slat:slat));
          break;
        case FaceBuildType.closedBoard:
          final area=BoardCalculator.calculate([BoardFace(name:c.face.name,lengthCm:size.length,widthCm:size.width,overlapLengthCm:c.boardOverlapLengthCm,overlapWidthCm:c.boardOverlapWidthCm)]).totalM2;
          boardArea+=area;
          rows.add(FaceCalculation(face:c.face,buildType:c.buildType,boardAreaM2:area));
          break;
      }
    }
    return PackingFacesResult(faces:List.unmodifiable(rows),totalSlatMeters:slatMeters,totalBoardAreaM2:boardArea);
  }
}
