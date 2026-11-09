import 'package:flutter_test/flutter_test.dart';
import 'package:packing_pos/main.dart';

void main() {
  testWidgets('home screen shows Packing POS navigation', (tester) async {
    await tester.pumpWidget(const PackingPosApp());
    expect(find.text('Packing POS'), findsOneWidget);
    expect(find.text('Transaksi packing baru'), findsOneWidget);
    expect(find.text('Riwayat transaksi'), findsOneWidget);
    expect(find.text('Master bahan'), findsOneWidget);
  });
}
