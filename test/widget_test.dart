import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:packing_pos/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('home screen shows Packing POS navigation', (tester) async {
    await tester.pumpWidget(const PackingPosApp());
    await tester.pumpAndSettle();

    expect(find.text('Packing POS'), findsOneWidget);
    expect(find.text('Transaksi packing baru'), findsOneWidget);
    expect(find.text('Riwayat transaksi'), findsOneWidget);

    // Settings are below the dashboard shortcuts in the scrollable home page.
    final settings = find.text('Pengaturan & data');
    await tester.scrollUntilVisible(
      settings,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(find.text('Master bahan (arsip)'), findsOneWidget);
  });
}
