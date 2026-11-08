class FrameEstimate {
  const FrameEstimate({required this.postCount,required this.postLengthCm,required this.lengthRailCount,required this.lengthRailCutCm,required this.widthRailCount,required this.widthRailCutCm,this.extraSupportMeters=0});
  final int postCount,lengthRailCount,widthRailCount; final double postLengthCm,lengthRailCutCm,widthRailCutCm,extraSupportMeters;
  double get postMeters=>postCount*postLengthCm/100;
  double get lengthRailMeters=>lengthRailCount*lengthRailCutCm/100;
  double get widthRailMeters=>widthRailCount*widthRailCutCm/100;
  double get totalMeters=>postMeters+lengthRailMeters+widthRailMeters+extraSupportMeters;
  factory FrameEstimate.eightCorner({required double postHeightCm,required double lengthRailCutCm,required double widthRailCutCm,double extraSupportMeters=0}) {
    if([postHeightCm,lengthRailCutCm,widthRailCutCm].any((v)=>!v.isFinite||v<=0)||!extraSupportMeters.isFinite||extraSupportMeters<0) throw ArgumentError('Ukuran rangka tidak valid.');
    return FrameEstimate(postCount:4,postLengthCm:postHeightCm,lengthRailCount:4,lengthRailCutCm:lengthRailCutCm,widthRailCount:4,widthRailCutCm:widthRailCutCm,extraSupportMeters:extraSupportMeters);
  }
}
