import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format/dimensions.dart';

import '../data/repositories/packing_identity_repository.dart';

class PackingReceiptPrinter {
  static const printerMacKey = 'packing_pos_printer_mac';
  static const paperWidthKey = 'packing_pos_printer_paper_width';
  static const printLogoKey = 'packing_pos_print_logo';

  // Replace characters unsupported by common ESC/POS code pages.
  static String printable(Object? raw) {
    var text = raw?.toString() ?? '';
    const replacements = <String, String>{
      '•': '-',
      '‘': "'",
      '’': "'",
      '“': '"',
      '”': '"',
      '–': '-',
      '—': '-',
      '…': '...',
      '×': 'x',
    };
    replacements.forEach((from, to) => text = text.replaceAll(from, to));
    // Emoji and other supplementary-plane characters cannot be printed.
    return text.replaceAll(RegExp('[\\u{10000}-\\u{10FFFF}]', unicode: true), '');
  }

  /// Builds the centered logo bytes. Returns an empty list when the logo
  /// cannot be loaded so a logo problem never blocks printing the receipt.
  static Future<List<int>> _logoBytes(Generator generator, int targetWidth, SharedPreferences prefs) async {
    if (prefs.getBool(printLogoKey) == false) return const [];
    try {
      final logoData = await rootBundle.load('assets/packing_pos_logo_line.png');
      final logo = img.decodeImage(logoData.buffer.asUint8List());
      if (logo == null) return const [];
      final scaledLogo = img.copyResize(
        logo,
        width: targetWidth,
        interpolation: img.Interpolation.average,
      );
      return [
        ...generator.image(scaledLogo, align: PosAlign.center),
        ...generator.feed(1),
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<int> _pair(Generator generator, int cols, String left, String right, {PosStyles styles = const PosStyles()}) {
    final space = cols - left.length - right.length;
    if (space >= 1) return generator.text('$left${' ' * space}$right', styles: styles);
    return [...generator.text(left, styles: styles), ...generator.text(right.padLeft(cols), styles: styles)];
  }

  static Future<List<int>> testPageBytes(int paperWidth) async {
    final prefs = await SharedPreferences.getInstance();
    final identity = await PackingIdentityRepository().getSettings();
    final generator = Generator(paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58, await CapabilityProfile.load());
    return [
      ...generator.reset(),
      ...await _logoBytes(generator, paperWidth == 80 ? 220 : 160, prefs),
      ...generator.text(printable(identity['business_name'] ?? 'Packing POS'), styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...generator.text('TES CETAK', styles: const PosStyles(align: PosAlign.center)),
      ...generator.hr(),
      ...generator.text('Kertas $paperWidth mm'),
      ...generator.text('Logo: ${prefs.getBool(printLogoKey) == false ? 'nonaktif' : 'aktif'}'),
      ...generator.text('Bluetooth OK'),
      ...generator.feed(3),
    ];
  }

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
      if (!connected) {
        throw StateError('Tidak dapat terhubung ke printer Bluetooth.');
      }
    }

    final identity = await PackingIdentityRepository().getSettings();
    final paperWidth = preferences.getInt(paperWidthKey) ?? 58;
    final paper = paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    final bytes = <int>[];

    String money(Object? raw) {
      final amount = (raw as num?)?.toInt() ?? 0;
      return 'Rp ${amount.toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
        (_) => '.',
      )}';
    }

    Map? snapshot;
    try {
      snapshot = jsonDecode(
        transaction['calculation_snapshot']?.toString() ?? '{}',
      ) as Map;
    } catch (_) {
      snapshot = null;
    }
    final jobType = snapshot?['jobType']?.toString() ?? '';
    final isManualService = snapshot?['mode'] == 'manual_service_charge';

    bytes.addAll(generator.reset());
    bytes.addAll(await _logoBytes(generator, paperWidth == 80 ? 220 : 160, preferences));
    bytes.addAll(generator.text(
      identity['business_name'] ?? 'Packing POS',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
      linesAfter: 1,
    ));
    final businessAddress = identity['business_address'] ?? '';
    final businessPhone = identity['business_phone'] ?? '';
    if (businessAddress.isNotEmpty) bytes.addAll(generator.text(printable(businessAddress), styles: const PosStyles(align: PosAlign.center)));
    if (businessPhone.isNotEmpty) bytes.addAll(generator.text('Telp. ${printable(businessPhone)}', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(
      transaction['receipt_no']?.toString() ?? '',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.hr());

    final createdAt = DateTime.tryParse(
      transaction['created_at']?.toString() ?? '',
    );
    if (createdAt != null) {
      bytes.addAll(generator.text(
        'Tanggal: ${DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal())}',
      ));
    }
    bytes.addAll(generator.text(
      'Pelanggan: ${transaction['customer_name']?.toString() ?? '-'}',
    ));
    if (jobType.isNotEmpty) {
      bytes.addAll(generator.text('Jenis pekerjaan: $jobType'));
    }
    bytes.addAll(generator.text(
      'Barang: ${transaction['item_description']?.toString() ?? '-'}',
    ));
    bytes.addAll(generator.text(
      'Ukuran: ${transaction['length_cm']?.toString() ?? '-'} x '
      '${transaction['width_cm']?.toString() ?? '-'} x '
      '${transaction['height_cm']?.toString() ?? ''} cm',
    ));

    final note = transaction['note']?.toString() ?? '';
    if (note.trim().isNotEmpty) {
      bytes.addAll(generator.text('Catatan: ${printable(note)}'));
    }
    final cancellationReason =
        transaction['cancellation_reason']?.toString() ?? '';
    if (cancellationReason.trim().isNotEmpty) {
      bytes.addAll(generator.text('Alasan batal: $cancellationReason'));
    }

    bytes.addAll(generator.hr());
    if (isManualService) {
      bytes.addAll(generator.text(
        'Ongkos pekerjaan: ${money(transaction['selling_price'])}',
        styles: const PosStyles(bold: true),
      ));
    }

    if (materials.isNotEmpty) {
      bytes.addAll(generator.text(
        'RINCIAN BAHAN',
        styles: const PosStyles(bold: true),
      ));
    }
    for (final material in materials) {
      final name = material['material_name_snapshot']?.toString() ?? 'Bahan';
      final quantity =
          (material['actual_quantity'] as num?)?.toDouble() ?? 0;
      final unit = material['unit_snapshot']?.toString() ?? '';
      bytes.addAll(generator.text(name));
      bytes.addAll(generator.text(
        '${quantity.toStringAsFixed(3)} $unit x '
        '${money(material['unit_price_snapshot'])} = '
        '${money(material['subtotal'])}',
      ));
    }

    bytes.addAll(generator.hr());
    final materialCost =
        (transaction['material_cost'] as num?)?.toInt() ?? 0;
    final laborCost = (transaction['labor_cost'] as num?)?.toInt() ?? 0;
    final overheadCost =
        (transaction['overhead_cost'] as num?)?.toInt() ?? 0;
    if (materials.isNotEmpty || materialCost > 0) {
      bytes.addAll(generator.text('Biaya bahan: ${money(materialCost)}'));
    }
    if (materials.isNotEmpty || laborCost > 0) {
      bytes.addAll(generator.text('Jasa: ${money(laborCost)}'));
    }
    if (overheadCost != 0) {
      bytes.addAll(generator.text('Tambahan: ${money(overheadCost)}'));
    }

    bytes.addAll(generator.text(
      'TOTAL: ${money(transaction['selling_price'])}',
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
      ),
    ));
    bytes.addAll(generator.text(
      'Dibayar: ${money(transaction['paid_amount'])}',
    ));
    final total = (transaction['selling_price'] as num?)?.toInt() ?? 0;
    final paid = (transaction['paid_amount'] as num?)?.toInt() ?? 0;
    bytes.addAll(generator.text('Sisa: ${money(total - paid)}'));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(
      'Terima kasih',
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(generator.feed(3));

    final printed = await PrintBluetoothThermal.writeBytes(bytes);
    if (!printed) {
      throw StateError('Printer menolak data cetak.');
    }
    return true;
  }

  /// Prints one combined receipt containing every job and a single payment summary.
  static Future<bool> printReceipt({
    required Map<String, Object?> receipt,
    required List<Map<String, Object?>> jobs,
    required Map<int, List<Map<String, Object?>>> materialsByJob,
    required List<Map<String, Object?>> payments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(printerMacKey);
    if (mac == null || mac.trim().isEmpty) throw StateError('Pilih printer terlebih dahulu pada Pengaturan Printer.');
    if (!await PrintBluetoothThermal.connectionStatus && !await connect(mac)) {
      throw StateError('Tidak dapat terhubung ke printer Bluetooth.');
    }
    final identity = await PackingIdentityRepository().getSettings();
    final paper = (prefs.getInt(paperWidthKey) ?? 58) == 80 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paper, await CapabilityProfile.load());
    final cols = paper == PaperSize.mm80 ? 48 : 32;
    final bytes = <int>[];
    String money(Object? raw) {
      final n = (raw as num?)?.toInt() ?? 0;
      return 'Rp ${n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
    }
    bytes.addAll(generator.reset());
    bytes.addAll(await _logoBytes(generator, paper == PaperSize.mm80 ? 220 : 160, prefs));
    final businessName = printable(identity['business_name'] ?? 'Packing POS');
    final nameFitsDoubleWidth = businessName.length <= cols ~/ 2;
    bytes.addAll(generator.text(businessName, styles: PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: nameFitsDoubleWidth ? PosTextSize.size2 : PosTextSize.size1), linesAfter: 1));
    final businessAddress = identity['business_address'] ?? '';
    final businessPhone = identity['business_phone'] ?? '';
    if (businessAddress.isNotEmpty) bytes.addAll(generator.text(printable(businessAddress), styles: const PosStyles(align: PosAlign.center)));
    if (businessPhone.isNotEmpty) bytes.addAll(generator.text('Telp. ${printable(businessPhone)}', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(receipt['receipt_no']?.toString() ?? '-', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.hr());
    final created = DateTime.tryParse(receipt['created_at']?.toString() ?? '');
    if (created != null) bytes.addAll(generator.text('Tanggal: ${DateFormat('dd/MM/yyyy HH:mm').format(created.toLocal())}'));
    bytes.addAll(generator.text('Pelanggan: ${printable(receipt['customer_name'] ?? '-')}'));
    bytes.addAll(generator.hr());
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      final desc = job['item_description']?.toString().trim();
      bytes.addAll(generator.text('${i + 1}. ${desc == null || desc.isEmpty ? 'Pekerjaan' : printable(desc)}', styles: const PosStyles(bold: true)));
      final size = dimensionsLabel(job['length_cm'], job['width_cm'], job['height_cm']);
      if (size != null) bytes.addAll(generator.text('Ukuran: ${size.replaceAll('×', 'x')}'));
      final materials = materialsByJob[(job['id'] as num).toInt()] ?? const [];
      for (final m in materials) {
        bytes.addAll(generator.text('  ${m['material_name_snapshot']}: ${m['actual_quantity']} ${m['unit_snapshot']} = ${money(m['subtotal'])}'));
      }
      final quantity = (job['quantity'] as num?)?.toInt() ?? 1;
      final unitPrice = job['unit_price'] ?? job['selling_price'];
      bytes.addAll(generator.text('  Qty: $quantity x ${money(unitPrice)}'));
      bytes.addAll(_pair(generator, cols, '  Subtotal pekerjaan', money(job['selling_price'])));
      final jobNote = job['note']?.toString().trim() ?? '';
      if (jobNote.isNotEmpty) {
        bytes.addAll(generator.text('  Catatan pekerjaan: ${printable(jobNote)}'));
      }
      if (receipt['status']?.toString() == 'cancelled') {
        final cancellationReason =
            job['cancellation_reason']?.toString().trim() ?? '';
        if (cancellationReason.isNotEmpty) {
          bytes.addAll(generator.text('  Alasan pembatalan: ${printable(cancellationReason)}'));
        }
      }
      if (i != jobs.length - 1) bytes.addAll(generator.hr(ch: '-'));
    }
    bytes.addAll(generator.hr());
    final total = (receipt['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (receipt['paid_amount'] as num?)?.toInt() ?? 0;
    final discount = (receipt['discount_amount'] as num?)?.toInt() ?? 0;
    if (discount > 0) {
      bytes.addAll(_pair(generator, cols, 'Subtotal', money(total + discount)));
      bytes.addAll(_pair(generator, cols, 'Diskon nota', '-${money(discount)}'));
    }
    bytes.addAll(_pair(generator, cols, 'TOTAL NOTA', money(total), styles: const PosStyles(bold: true, height: PosTextSize.size2)));
    bytes.addAll(_pair(generator, cols, 'Dibayar', money(paid)));
    bytes.addAll(generator.text('Sisa: ${money(total - paid)}'));

    final receiptStatus = receipt['status']?.toString() ?? 'open';
    // Derive the payment label from the amounts so a stale status value
    // cannot print a partially paid receipt as fully settled.
    final statusLabel = receiptStatus == 'cancelled'
        ? 'DIBATALKAN'
        : total > 0 && paid >= total
            ? 'LUNAS'
            : paid > 0
                ? 'DIBAYAR SEBAGIAN'
                : 'BELUM DIBAYAR';
    bytes.addAll(generator.text(
      'STATUS: $statusLabel',
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
      ),
      linesAfter: 1,
    ));

    // Print every staged payment in chronological order. The repository
    // returns newest-first, so use a copy and reverse it without mutating
    // the caller's payment list.
    if (payments.isNotEmpty) {
      bytes.addAll(generator.hr(ch: '-'));
      bytes.addAll(generator.text(
        'RIWAYAT PEMBAYARAN',
        styles: const PosStyles(bold: true),
      ));
      for (final payment in payments.reversed) {
        final paymentDate = DateTime.tryParse(
          payment['created_at']?.toString() ?? '',
        );
        final dateLabel = paymentDate == null
            ? '-'
            : DateFormat('dd/MM/yy HH:mm').format(paymentDate.toLocal());
        final method = payment['payment_method']?.toString().trim();
        bytes.addAll(generator.text(
          '$dateLabel - ${method == null || method.isEmpty ? 'Lainnya' : method.toUpperCase()}',
        ));
        bytes.addAll(generator.text(
          '  ${money(payment['amount'])}',
          styles: const PosStyles(bold: true),
        ));
        final paymentNote = payment['note']?.toString().trim() ?? '';
        if (paymentNote.isNotEmpty) {
          bytes.addAll(generator.text('  Catatan: ${printable(paymentNote)}'));
        }
      }
    }

    final note = receipt['note']?.toString() ?? '';
    if (note.trim().isNotEmpty) bytes.addAll(generator.text('Catatan: ${printable(note)}'));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(
      receiptStatus == 'cancelled' ? 'ARSIP NOTA DIBATALKAN' : 'Terima kasih',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.feed(3));
    if (!await PrintBluetoothThermal.writeBytes(bytes)) throw StateError('Printer menolak data cetak.');
    return true;
  }

}
