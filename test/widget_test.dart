import 'package:flutter/material.dart' show Scrollable, TextField;
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
  testWidgets('typing a customer name then navigating back does not crash', (tester) async {
    await tester.pumpWidget(const PackingPosApp());
    // Avoid pumpAndSettle throughout this flow: either screen can contain
    // repeating animations, and a focused text field also blinks its caret.
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Transaksi packing baru'));
    await tester.pump(const Duration(milliseconds: 500));

    final customerField = find.widgetWithText(TextField, 'Nama pelanggan');
    expect(customerField, findsOneWidget);
    await tester.enterText(customerField, 'Pelanggan Uji');
    await tester.pump(const Duration(milliseconds: 100));

    tester.testTextInput.hide();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Packing POS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
