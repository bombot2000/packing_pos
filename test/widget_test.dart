import 'package:flutter/material.dart' show FilledButton, Scrollable, TextField;
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

    final newTransactionButton = find.byType(FilledButton);
    expect(newTransactionButton, findsOneWidget);
    await tester.ensureVisible(newTransactionButton);
    await tester.tap(newTransactionButton);

    // Wait for the pushed route to finish building without waiting for
    // unrelated repeating animations on the destination screen.
    final destinationTitle = find.text('Buat nota packing');
    for (var i = 0; i < 10 && destinationTitle.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(destinationTitle, findsOneWidget);

    final customerField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'Nama pelanggan',
      description: 'TextField label Nama pelanggan',
    );
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


  testWidgets('back from add customer dialog does not crash', (tester) async {
    await tester.pumpWidget(const PackingPosApp());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Kelola master pelanggan'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Master pelanggan'), findsOneWidget);

    final addCustomer = find.text('Tambah pelanggan');
    for (var i = 0; i < 10 && addCustomer.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(addCustomer, findsOneWidget);
    await tester.tap(addCustomer);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nama pelanggan *'), findsOneWidget);

    tester.testTextInput.hide();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Master pelanggan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
