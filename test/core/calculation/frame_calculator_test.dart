import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/core/calculation/frame_calculator.dart';

void main() {
  test('eight-corner frame exposes explicit cut list and total length', () {
    final frame = FrameEstimate.eightCorner(
      postHeightCm: 50,
      lengthRailCutCm: 100,
      widthRailCutCm: 60,
    );

    expect(frame.postCount, 4);
    expect(frame.lengthRailCount, 4);
    expect(frame.widthRailCount, 4);
    expect(frame.cutList.length, 3);
    expect(frame.cutList[0].totalMeters, closeTo(2.0, 0.000001));
    expect(frame.cutList[1].totalMeters, closeTo(4.0, 0.000001));
    expect(frame.cutList[2].totalMeters, closeTo(2.4, 0.000001));
    expect(frame.totalMeters, closeTo(8.4, 0.000001));
  });

  test('invalid frame cut length is rejected', () {
    expect(
      () => FrameEstimate.eightCorner(
        postHeightCm: 0,
        lengthRailCutCm: 100,
        widthRailCutCm: 60,
      ),
      throwsArgumentError,
    );
  });
}
