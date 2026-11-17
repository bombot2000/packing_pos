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
  static String paymentMethodLabel(Object? raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'cash':
        return 'Tunai';
      case 'transfer':
        return 'Transfer';
      case 'qris':
        return 'QRIS';
      case 'other':
        return 'Lainnya';
      default:
        return 'Metode lain';
    }
  }

  static const printerMacKey = 'packing_pos_printer_mac';
  static const paperWidthKey = 'packing_pos_printer_paper_width';
  static const printLogoKey = 'packing_pos_print_logo';
  static const textWeightKey = 'packing_pos_text_weight';
  static const defaultTextWeight = 1;

  static List<int> _textWeightCommands(int weight) => [
    // ESC M selects Font B for the lightest setting and Font A otherwise.
    0x1B, 0x4D, weight == 0 ? 1 : 0,
    // ESC E emphasis; ESC G double-strike for heavier output.
    0x1B, 0x45, weight >= 2 ? 1 : 0,
    0x1B, 0x47, weight >= 3 ? 1 : 0,
  ];

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
        // ESC J n feeds a precise 12-dot gap (about 1.5 mm at 203 dpi).
        0x1B, 0x4A, 12,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<int>> testPageBytes(int paperWidth) async {
    final prefs = await SharedPreferences.getInstance();
    final identity = await PackingIdentityRepository().getSettings();
    final generator = Generator(paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58, await CapabilityProfile.load());
    final weight = (prefs.getInt(textWeightKey) ?? defaultTextWeight).clamp(0, 4);
    return [
      ...generator.reset(),
      ..._textWeightCommands(weight),
      ...await _logoBytes(generator, paperWidth == 80 ? 220 : 160, prefs),
      ...generator.text(printable(identity['business_name'] ?? 'Packing POS'), styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...generator.text('TES CETAK', styles: const PosStyles(align: PosAlign.center)),
      ...generator.hr(),
      ...generator.text('Kertas $paperWidth mm'),
      ...generator.text('Logo: ${prefs.getBool(printLogoKey) == false ? 'nonaktif' : 'aktif'}'),
      ...generator.text('Bluetooth OK'),
      // Penggaris lebar: pastikan 32 (58 mm) atau 48 (80 mm) karakter tercetak penuh.
      ...generator.text('1234567890' * (paperWidth == 80 ? 4 : 3) + (paperWidth == 80 ? '12345678' : '12')),
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
    final weight = (preferences.getInt(textWeightKey) ?? defaultTextWeight).clamp(0, 4);
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
    bytes.addAll(_textWeightCommands(weight));
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

  /// Word-wraps [text] to [width] columns, breaking over-long words.
  static List<String> _wrap(String text, int width) {
    final lines = <String>[];
    if (width < 1) return [text];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (var word in paragraph.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        while (word.length > width) {
          if (line.isNotEmpty) {
            lines.add(line);
            line = '';
          }
          lines.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          lines.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }
    return lines;
  }

  static String _qty(Object? raw) {
    final v = (raw as num?)?.toDouble() ?? 0;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  /// Prints one combined receipt containing every job and a single payment summary.
  ///
  /// Layout rules for thermal paper: every line is wrapped by this method
  /// (never by the printer, which would cut words), amounts are right-aligned
  /// to the paper edge, and totals/payment status are the most prominent items.
  static Future<bool> printReceipt({
    required Map<String, Object?> receipt,
    required List<Map<String, Object?>> jobs,
    required Map<int, List<Map<String, Object?>>> materialsByJob,
    required List<Map<String, Object?>> payments,
    List<Map<String, Object?>> refunds = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(printerMacKey);
    if (mac == null || mac.trim().isEmpty) throw StateError('Pilih printer terlebih dahulu pada Pengaturan Printer.');
    if (!await PrintBluetoothThermal.connectionStatus && !await connect(mac)) {
      throw StateError('Tidak dapat terhubung ke printer Bluetooth.');
    }
    final identity = await PackingIdentityRepository().getSettings();
    final is80 = (prefs.getInt(paperWidthKey) ?? 58) == 80;
    final paper = is80 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paper, await CapabilityProfile.load());
    final weight = (prefs.getInt(textWeightKey) ?? defaultTextWeight).clamp(0, 4);
    // Font B (lightest setting) fits more characters per line.
    final cols = weight == 0 ? (is80 ? 64 : 42) : (is80 ? 48 : 32);
    final bytes = <int>[];

    String money(Object? raw) {
      final n = (raw as num?)?.toInt() ?? 0;
      final digits = n.abs().toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.');
      return '${n < 0 ? '-' : ''}Rp $digits';
    }

    String stamp(Object? raw) {
      final d = DateTime.tryParse(raw?.toString() ?? '');
      return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
    }

    void rule([String ch = '-']) => bytes.addAll(generator.text(ch * cols));

    void center(String s, {bool bold = false, PosTextSize height = PosTextSize.size1}) {
      for (final line in _wrap(printable(s), cols)) {
        bytes.addAll(generator.text(line, styles: PosStyles(align: PosAlign.center, bold: bold, height: height)));
      }
    }

    /// Left-aligned wrapped text; [first] prefixes line 1, [rest] the others.
    void wrapped(String s, {String first = '', String? rest, bool bold = false}) {
      final hang = rest ?? ' ' * first.length;
      final width = cols - (first.length > hang.length ? first.length : hang.length);
      final lines = _wrap(printable(s), width);
      for (var i = 0; i < lines.length; i++) {
        bytes.addAll(generator.text('${i == 0 ? first : hang}${lines[i]}', styles: PosStyles(bold: bold)));
      }
    }

    /// Label on the left, amount on the right edge. Long labels wrap above.
    void pair(String label, String value, {String indent = '', bool bold = false, PosTextSize height = PosTextSize.size1}) {
      final styles = PosStyles(bold: bold, height: height);
      final left = printable(label);
      final space = cols - indent.length - left.length - value.length;
      if (space >= 1) {
        bytes.addAll(generator.text('$indent$left${' ' * space}$value', styles: styles));
        return;
      }
      final room = cols - indent.length - value.length - 1;
      final lines = _wrap(left, room > 8 ? room : cols - indent.length);
      if (room > 8) {
        for (var i = 0; i < lines.length - 1; i++) {
          bytes.addAll(generator.text('$indent${lines[i]}', styles: styles));
        }
        final last = lines.isEmpty ? '' : lines.last;
        bytes.addAll(generator.text('$indent$last${' ' * (cols - indent.length - last.length - value.length)}$value', styles: styles));
      } else {
        for (final line in lines) {
          bytes.addAll(generator.text('$indent$line', styles: styles));
        }
        bytes.addAll(generator.text(value.padLeft(cols), styles: styles));
      }
    }

    final status = receipt['status']?.toString() ?? 'open';
    final cancelled = status == 'cancelled';

    // ---- Header: logo, business name, contact -------------------------
    bytes.addAll(generator.reset());
    bytes.addAll(_textWeightCommands(weight));
    bytes.addAll(await _logoBytes(generator, is80 ? 220 : 160, prefs));
    final businessName = printable(identity['business_name'] ?? 'Packing POS');
    final nameFitsDoubleWidth = businessName.length <= (cols ~/ 2);
    if (nameFitsDoubleWidth) {
      bytes.addAll(generator.text(
        businessName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      ));
    } else {
      center(businessName, bold: true, height: PosTextSize.size2);
    }
    final businessAddress = (identity['business_address'] ?? '').trim();
    final businessPhone = (identity['business_phone'] ?? '').trim();
    if (businessAddress.isNotEmpty) center(businessAddress);
    if (businessPhone.isNotEmpty) center('Telp. $businessPhone');
    rule('=');

    // ---- Receipt info ---------------------------------------------------
    if (cancelled) {
      center('*** NOTA DIBATALKAN ***', bold: true);
      rule();
    }
    pair('No. Nota', receipt['receipt_no']?.toString() ?? '-', bold: true);
    final created = stamp(receipt['created_at']);
    if (created.isNotEmpty) pair('Tanggal', created);
    final customer = (receipt['customer_name']?.toString() ?? '').trim();
    pair('Pelanggan', customer.isEmpty ? '-' : customer);
    rule();

    // ---- Jobs -------------------------------------------------------------
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      final desc = job['item_description']?.toString().trim() ?? '';
      final number = '${i + 1}. ';
      wrapped(desc.isEmpty ? 'Pekerjaan' : desc, first: number, bold: true);
      const indent = '   ';
      final size = dimensionsLabel(job['length_cm'], job['width_cm'], job['height_cm']);
      if (size != null) wrapped('Ukuran ${size.replaceAll('×', 'x')}', first: indent);
      final materials = materialsByJob[(job['id'] as num).toInt()] ?? const [];
      for (final m in materials) {
        wrapped(m['material_name_snapshot']?.toString() ?? 'Bahan', first: indent);
        pair('${_qty(m['actual_quantity'])} ${m['unit_snapshot'] ?? ''}', money(m['subtotal']), indent: '$indent  ');
      }
      final quantity = (job['quantity'] as num?)?.toInt() ?? 1;
      // selling_price adalah total baris (harga satuan x jumlah koli).
      final lineTotal = (job['selling_price'] as num?)?.toInt() ?? 0;
      final unitPrice = (job['unit_price'] as num?)?.toInt() ?? (quantity > 0 ? lineTotal ~/ quantity : lineTotal);
      pair('$quantity x ${money(unitPrice)}', money(lineTotal), indent: indent, bold: true);
      final jobNote = job['note']?.toString().trim() ?? '';
      if (jobNote.isNotEmpty) wrapped('Cat: $jobNote', first: indent);
      if (cancelled) {
        final reason = job['cancellation_reason']?.toString().trim() ?? '';
        if (reason.isNotEmpty) wrapped('Alasan batal: $reason', first: indent);
      }
      if (i != jobs.length - 1) bytes.addAll(generator.feed(1));
    }
    rule();

    // ---- Totals ----------------------------------------------------------
    final total = (receipt['total_amount'] as num?)?.toInt() ?? 0;
    final paid = (receipt['paid_amount'] as num?)?.toInt() ?? 0;
    final discount = (receipt['discount_amount'] as num?)?.toInt() ?? 0;
    if (discount > 0) {
      pair('Subtotal', money(total + discount));
      pair('Diskon', '-${money(discount)}');
    }
    pair('TOTAL', money(total), bold: true, height: PosTextSize.size2);
    if (!cancelled) {
      pair('Dibayar', money(paid));
      final remaining = total - paid;
      if (remaining > 0) {
        pair('SISA', money(remaining), bold: true);
      } else if (remaining < 0) {
        pair('Kelebihan bayar', money(-remaining));
      } else if (total > 0) {
        bytes.addAll(generator.feed(1));
        center('** LUNAS **', bold: true);
      }
    }

    // ---- Payments and refunds ----------------------------------------------
    rule();
    bytes.addAll(generator.text('PEMBAYARAN', styles: const PosStyles(bold: true)));
    if (payments.isEmpty) {
      bytes.addAll(generator.text('Belum ada pembayaran'));
    } else {
      for (final payment in payments) {
        pair(paymentMethodLabel(payment['payment_method']), money(payment['amount']));
        final when = stamp(payment['created_at']);
        if (when.isNotEmpty) wrapped(when, first: '  ');
        final paymentNote = payment['note']?.toString().trim() ?? '';
        if (paymentNote.isNotEmpty) wrapped(paymentNote, first: '  ');
      }
    }
    for (final refund in refunds) {
      pair('Refund ${paymentMethodLabel(refund['refund_method'])}', '-${money(refund['amount'])}');
      final when = stamp(refund['created_at']);
      if (when.isNotEmpty) wrapped(when, first: '  ');
      final reason = refund['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty) wrapped('Alasan: $reason', first: '  ');
    }

    // ---- Notes and footer -----------------------------------------------------
    final note = receipt['note']?.toString().trim() ?? '';
    if (note.isNotEmpty) {
      rule();
      wrapped('Catatan: $note');
    }
    rule('=');
    final thankYou = (identity['receipt_thank_you'] ?? 'Terima kasih').trim();
    final footer = cancelled ? 'ARSIP NOTA DIBATALKAN' : thankYou;
    if (footer.isNotEmpty) center(footer, bold: true);
    bytes.addAll(generator.feed(3));
    if (!await PrintBluetoothThermal.writeBytes(bytes)) throw StateError('Printer menolak data cetak.');
    return true;
  }

}