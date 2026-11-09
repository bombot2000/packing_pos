class FrameCut {
  const FrameCut({
    required this.label,
    required this.count,
    required this.lengthCm,
  });

  final String label;
  final int count;
  final double lengthCm;

  double get totalMeters => count * lengthCm / 100;
}

class FrameEstimate {
  const FrameEstimate({
    required this.postCount,
    required this.postLengthCm,
    required this.lengthRailCount,
    required this.lengthRailCutCm,
    required this.widthRailCount,
    required this.widthRailCutCm,
    this.extraSupportMeters = 0,
  });

  final int postCount;
  final int lengthRailCount;
  final int widthRailCount;
  final double postLengthCm;
  final double lengthRailCutCm;
  final double widthRailCutCm;
  final double extraSupportMeters;

  double get postMeters => postCount * postLengthCm / 100;
  double get lengthRailMeters => lengthRailCount * lengthRailCutCm / 100;
  double get widthRailMeters => widthRailCount * widthRailCutCm / 100;
  double get totalMeters =>
      postMeters + lengthRailMeters + widthRailMeters + extraSupportMeters;

  List<FrameCut> get cutList => List.unmodifiable([
        FrameCut(label: 'Tiang sudut', count: postCount, lengthCm: postLengthCm),
        FrameCut(
          label: 'Rel arah panjang (atas/bawah)',
          count: lengthRailCount,
          lengthCm: lengthRailCutCm,
        ),
        FrameCut(
          label: 'Rel arah lebar (atas/bawah)',
          count: widthRailCount,
          lengthCm: widthRailCutCm,
        ),
      ]);

  factory FrameEstimate.eightCorner({
    required double postHeightCm,
    required double lengthRailCutCm,
    required double widthRailCutCm,
    double extraSupportMeters = 0,
  }) {
    if ([postHeightCm, lengthRailCutCm, widthRailCutCm]
            .any((v) => !v.isFinite || v <= 0) ||
        !extraSupportMeters.isFinite ||
        extraSupportMeters < 0) {
      throw ArgumentError('Ukuran rangka tidak valid.');
    }
    return FrameEstimate(
      postCount: 4,
      postLengthCm: postHeightCm,
      lengthRailCount: 4,
      lengthRailCutCm: lengthRailCutCm,
      widthRailCount: 4,
      widthRailCutCm: widthRailCutCm,
      extraSupportMeters: extraSupportMeters,
    );
  }
}
