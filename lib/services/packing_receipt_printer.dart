import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PackingReceiptPrinter {
  static const printerMacKey = 'packing_pos_printer_mac';
  static const paperWidthKey = 'packing_pos_printer_paper_width';

  static Future<List<BluetoothInfo>> pairedDevices() =>
      PrintBluetoothThermal.pairedBluetooths;

  static Future<bool> connect(String macAddress) =>
      PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

  static Future<bool> disconnect() => PrintBluetoothThermal.disconnect;

  static Future<bool> printTransaction({
    required Map<String, Object?> transaction,
    required List<Map<String, Object?>> materials,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final mac = preferences.getString(printerMacKey);
    if (mac == null || mac.trim().isEmpty) {
      throw StateError('Pilih printer terlebih dahulu pada Pengaturan Printer.');
    }
    if (!await PrintBluetoothThermal.connectionStatus) {
      final connected = await connect(mac);
      if (!connected) throw StateError('Tidak dapat terhubung ke printer Bluetooth.');
    }

    final paperWidth = preferences.getInt(paperWidthKey) ?? 58;
    final paper = paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    final bytes = <int>[];
    String money(Object? raw) {
      final amount = (raw as num?)?.toInt() ?? 0;
      return 'Rp ' + amount.toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );
    }

    bytes.addAll(generator.reset());
    bytes.addAll(generator.text(
      'PACKING POS',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    ));
    bytes.addAll(generator.text(
      transaction['receipt_no']?.toString() ?? '',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Pelanggan: ' + (transaction['customer_name']?.toString() ?? '-')));
    bytes.addAll(generator.text('Barang: ' + (transaction['item_description']?.toString() ?? '-')));
    bytes.addAll(generator.text(
      'Ukuran: ' + (transaction['length_cm']?.toString() ?? '-') +
      ' x ' + (transaction['width_cm']?.toString() ?? '-') +
      ' x ' + (transaction['height_cm']?.toString() ?? '') + ' cm',
    ));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('RINCIAN BAHAN', styles: const PosStyles(bold: true)));
    for (final material in materials) {
      final name = material['material_name_snapshot']?.toString() ?? 'Bahan';
      final qty = (material['actual_quantity'] as num?)?.toDouble() ?? 0;
      final unit = material['unit_snapshot']?.toString() ?? '';
      bytes.addAll(generator.text(name));
      bytes.addAll(generator.text(
        qty.toStringAsFixed(3) + ' ' + unit + ' x ' +
        money(material['unit_price_snapshot']) + ' = ' + money(material['subtotal']),
      ));
    }
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Biaya bahan: ' + money(transaction['material_cost'])));
    bytes.addAll(generator.text('Jasa: ' + money(transaction['labor_cost'])));
    bytes.addAll(generator.text('Tambahan: ' + money(transaction['overhead_cost'])));
    bytes.addAll(generator.text('TOTAL: ' + money(transaction['selling_price']),
      styles: const PosStyles(bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text('Dibayar: ' + money(transaction['paid_amount'])));
    final total = (transaction['selling_price'] as num?)?.toInt() ?? 0;
    final paid = (transaction['paid_amount'] as num?)?.toInt() ?? 0;
    bytes.addAll(generator.text('Sisa: ' + money(total - paid)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('Terima kasih', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(3));

    final printed = await PrintBluetoothThermal.writeBytes(bytes);
    if (!printed) throw StateError('Printer menolak data cetak.');
    return true;
  }
}
