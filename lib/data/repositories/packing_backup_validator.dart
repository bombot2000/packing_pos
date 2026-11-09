import 'dart:convert';

/// Validates backup structure and cross-table relationships before restore.
/// SQLite constraints remain the final guard and roll back failed inserts.
class PackingBackupValidator {
  PackingBackupValidator._();

  static const tables = [
    'packing_transactions',
    'transaction_materials',
    'transaction_payments',
    'materials',
    'app_settings',
  ];

  static Map<String, List<Map<String, Object?>>> validate(
    Map<String, dynamic> backup,
  ) {
    final version = backup['version'];
    if (backup['format'] != 'packing_pos_backup' ||
        (version != 1 && version != 2)) {
      throw const FormatException('Format atau versi backup tidak didukung.');
    }

    final data = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final raw = backup[table];
      if (raw is! List) {
        throw FormatException('Data tabel $table tidak ditemukan pada backup.');
      }
      data[table] = raw.map((row) {
        if (row is! Map) {
          throw FormatException('Baris tabel $table tidak valid.');
        }
        return Map<String, Object?>.from(row);
      }).toList(growable: false);
    }

    final transactions = <int, Map<String, Object?>>{};
    final receipts = <String>{};
    for (final row in data['packing_transactions']!) {
      final id = _positiveInt(row['id'], 'ID transaksi');
      final receipt = _text(row['receipt_no'], 'Nomor nota');
      if (!receipts.add(receipt)) {
        throw FormatException('Nomor nota duplikat: $receipt.');
      }
      if (transactions.containsKey(id)) {
        throw FormatException('ID transaksi duplikat: $id.');
      }
      for (final field in ['length_cm', 'width_cm', 'height_cm']) {
        _positiveNumber(row[field], field);
      }
      final snapshot = _text(row['calculation_snapshot'], 'Snapshot perhitungan');
      try {
        if (jsonDecode(snapshot) is! Map) throw const FormatException();
      } on FormatException {
        throw FormatException('Snapshot perhitungan transaksi $id tidak valid.');
      }
      for (final field in [
        'material_cost',
        'labor_cost',
        'overhead_cost',
        'selling_price',
        'paid_amount',
      ]) {
        _nonNegativeInt(row[field], field);
      }
      final status = _text(row['status'], 'Status transaksi');
      if (!['open', 'completed', 'cancelled'].contains(status)) {
        throw FormatException('Status transaksi $id tidak dikenal.');
      }
      if (_int(row['paid_amount'], 'paid_amount') >
          _int(row['selling_price'], 'selling_price')) {
        throw FormatException('Pembayaran transaksi $id melebihi total tagihan.');
      }
      _text(row['created_at'], 'Tanggal transaksi');
      _text(row['updated_at'], 'Tanggal pembaruan');
      transactions[id] = row;
    }

    final paymentIds = <int>{};
    final paymentTotals = <int, int>{};
    for (final row in data['transaction_payments']!) {
      final id = _positiveInt(row['id'], 'ID pembayaran');
      if (!paymentIds.add(id)) throw FormatException('ID pembayaran duplikat: $id.');
      final transactionId = _positiveInt(row['transaction_id'], 'ID transaksi pembayaran');
      final transaction = transactions[transactionId];
      if (transaction == null) {
        throw FormatException('Pembayaran $id merujuk transaksi yang tidak ada.');
      }
      final amount = _positiveInt(row['amount'], 'Nominal pembayaran');
      _text(row['payment_method'], 'Metode pembayaran');
      _text(row['created_at'], 'Tanggal pembayaran');
      final sum = (paymentTotals[transactionId] ?? 0) + amount;
      if (sum > _int(transaction['selling_price'], 'selling_price')) {
        throw FormatException('Total pembayaran transaksi $transactionId melebihi tagihan.');
      }
      paymentTotals[transactionId] = sum;
    }

    final materialIds = <int>{};
    for (final row in data['materials']!) {
      final id = _positiveInt(row['id'], 'ID master bahan');
      if (!materialIds.add(id)) throw FormatException('ID master bahan duplikat: $id.');
      _text(row['name'], 'Nama bahan');
      _text(row['unit'], 'Satuan bahan');
      _nonNegativeInt(row['current_unit_price'], 'Harga bahan');
      final active = _nonNegativeInt(row['is_active'], 'Status bahan');
      if (active > 1) throw const FormatException('Status bahan tidak valid.');
      _text(row['created_at'], 'Tanggal bahan');
      _text(row['updated_at'], 'Tanggal pembaruan bahan');
    }

    final materialRowIds = <int>{};
    for (final row in data['transaction_materials']!) {
      final id = _positiveInt(row['id'], 'ID rincian bahan');
      if (!materialRowIds.add(id)) throw FormatException('ID rincian bahan duplikat: $id.');
      final transactionId = _positiveInt(row['transaction_id'], 'ID transaksi rincian bahan');
      if (!transactions.containsKey(transactionId)) {
        throw FormatException('Rincian bahan $id merujuk transaksi yang tidak ada.');
      }
      _text(row['material_name_snapshot'], 'Nama snapshot bahan');
      _text(row['unit_snapshot'], 'Satuan snapshot bahan');
      _nonNegativeNumber(row['calculated_quantity'], 'Jumlah hasil hitung');
      _nonNegativeNumber(row['actual_quantity'], 'Jumlah aktual');
      _nonNegativeInt(row['unit_price_snapshot'], 'Harga snapshot bahan');
      _nonNegativeInt(row['subtotal'], 'Subtotal bahan');
      _text(row['created_at'], 'Tanggal rincian bahan');
    }

    final settingKeys = <String>{};
    for (final row in data['app_settings']!) {
      final key = _text(row['key'], 'Kunci pengaturan');
      if (!settingKeys.add(key)) throw FormatException('Kunci pengaturan duplikat: $key.');
      _string(row['value'], 'Nilai pengaturan');
      _text(row['updated_at'], 'Tanggal pengaturan');
    }
    return data;
  }

  static String _string(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field harus berupa teks.');
    }
    return value;
  }

  static String _text(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field wajib berupa teks dan tidak boleh kosong.');
    }
    return value;
  }

  static int _int(Object? value, String field) {
    if (value is! num || !value.isFinite || value < 0 || value != value.round()) {
      throw FormatException('$field harus berupa bilangan bulat nonnegatif.');
    }
    return value.toInt();
  }

  static int _positiveInt(Object? value, String field) {
    final result = _int(value, field);
    if (result <= 0) throw FormatException('$field harus lebih dari nol.');
    return result;
  }

  static int _nonNegativeInt(Object? value, String field) => _int(value, field);

  static double _number(Object? value, String field) {
    if (value is! num || !value.isFinite) {
      throw FormatException('$field harus berupa angka yang valid.');
    }
    return value.toDouble();
  }

  static double _positiveNumber(Object? value, String field) {
    final result = _number(value, field);
    if (result <= 0) throw FormatException('$field harus lebih dari nol.');
    return result;
  }

  static double _nonNegativeNumber(Object? value, String field) {
    final result = _number(value, field);
    if (result < 0) throw FormatException('$field tidak boleh negatif.');
    return result;
  }
}
