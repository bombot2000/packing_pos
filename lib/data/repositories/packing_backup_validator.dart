import 'dart:convert';

/// Validates backup structure and cross-table relationships before restore.
/// SQLite constraints remain the final guard and roll back failed inserts.
class PackingBackupValidator {
  PackingBackupValidator._();

  static const tables = [
    'packing_transactions',
    'transaction_materials',
    'transaction_payments',
    'packing_receipts',
    'receipt_payments',
    'materials',
    'service_types',
    'app_settings',
  ];

  static Map<String, List<Map<String, Object?>>> validate(
    Map<String, dynamic> backup,
  ) {
    final version = backup['version'];
    if (backup['format'] != 'packing_pos_backup' ||
        (version != 1 && version != 2 && version != 3 && version != 4)) {
      throw const FormatException('Format atau versi backup tidak didukung.');
    }

    final data = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      if ((table == 'service_types' && version < 3 && backup[table] == null) || (version < 4 && ['packing_receipts', 'receipt_payments'].contains(table))) continue;
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

    // If payment detail rows exist, their sum must match the cached invoice
    // balance. Legacy backups without payment rows remain importable.
    for (final entry in paymentTotals.entries) {
      final transaction = transactions[entry.key]!;
      final paidAmount = _int(transaction['paid_amount'], 'paid_amount');
      if (entry.value != paidAmount) {
        throw FormatException(
          'Riwayat pembayaran transaksi ${entry.key} tidak cocok dengan paid_amount.',
        );
      }
      final status = transaction['status'];
      final total = _int(transaction['selling_price'], 'selling_price');
      if (status == 'completed' && paidAmount != total) {
        throw FormatException(
          'Status lunas transaksi ${entry.key} tidak cocok dengan jumlah pembayaran.',
        );
      }
      if (status == 'open' && paidAmount >= total) {
        throw FormatException(
          'Status transaksi ${entry.key} seharusnya lunas atau dibatalkan.',
        );
      }
    }


    if (version < 4) {
      final headers = <Map<String, Object?>>[];
      final receiptPayments = <Map<String, Object?>>[];
      for (final tx in data['packing_transactions']!) {
        final id = _positiveInt(tx['id'], 'ID transaksi');
        headers.add({'id': id, 'receipt_no': tx['receipt_no'], 'customer_name': tx['customer_name'] ?? '', 'total_amount': tx['selling_price'], 'paid_amount': tx['paid_amount'], 'status': tx['status'], 'note': tx['note'] ?? '', 'created_at': tx['created_at'], 'updated_at': tx['updated_at']});
        tx['receipt_id'] = id;
        for (final payment in data['transaction_payments']!) {
          if (payment['transaction_id'] == id) receiptPayments.add({'id': payment['id'], 'receipt_id': id, 'amount': payment['amount'], 'payment_method': payment['payment_method'], 'note': payment['note'] ?? '', 'created_at': payment['created_at']});
        }
      }
      data['packing_receipts'] = headers; data['receipt_payments'] = receiptPayments;
    }
    final headerIds = <int>{}; final headerNos = <String>{}; final headerMap = <int, Map<String, Object?>>{};
    for (final row in data['packing_receipts']!) {
      final id = _positiveInt(row['id'], 'ID nota'); final no = _text(row['receipt_no'], 'Nomor nota');
      if (!headerIds.add(id) || !headerNos.add(no)) throw FormatException('ID atau nomor nota duplikat: ' + no);
      final total = _nonNegativeInt(row['total_amount'], 'Total nota'); final paid = _nonNegativeInt(row['paid_amount'], 'Pembayaran nota');
      if (paid > total) throw FormatException('Pembayaran nota melebihi total: ' + no);
      final status = _text(row['status'], 'Status nota');
      if (!['open', 'completed', 'cancelled'].contains(status)) throw FormatException('Status nota tidak dikenal: ' + no);
      _text(row['created_at'], 'Tanggal nota'); _text(row['updated_at'], 'Pembaruan nota'); headerMap[id] = row;
    }
    final sums = <int, int>{};
    for (final tx in data['packing_transactions']!) {
      final rid = _positiveInt(tx['receipt_id'], 'ID nota pekerjaan');
      if (!headerMap.containsKey(rid)) throw const FormatException('Pekerjaan merujuk nota yang tidak ada.');
      if (tx['status'] != 'cancelled') sums[rid] = (sums[rid] ?? 0) + _int(tx['selling_price'], 'Harga pekerjaan');
    }
    for (final e in headerMap.entries) {
      if (e.value['status'] != 'cancelled' && (sums[e.key] ?? 0) != _int(e.value['total_amount'], 'Total nota')) throw const FormatException('Total pekerjaan tidak cocok dengan total nota.');
    }
    final payIds = <int>{}; final paidSums = <int, int>{};
    for (final row in data['receipt_payments']!) {
      final id = _positiveInt(row['id'], 'ID pembayaran nota'); if (!payIds.add(id)) throw const FormatException('ID pembayaran nota duplikat.');
      final rid = _positiveInt(row['receipt_id'], 'ID nota pembayaran'); if (!headerMap.containsKey(rid)) throw const FormatException('Pembayaran merujuk nota yang tidak ada.');
      final amount = _positiveInt(row['amount'], 'Nominal pembayaran nota'); _text(row['payment_method'], 'Metode pembayaran nota'); _text(row['created_at'], 'Tanggal pembayaran nota');
      paidSums[rid] = (paidSums[rid] ?? 0) + amount;
    }
    for (final e in headerMap.entries) {
      final paid = _int(e.value['paid_amount'], 'Pembayaran nota');
      if (version >= 4 ? (paidSums[e.key] ?? 0) != paid : ((paidSums[e.key] ?? 0) != 0 && paidSums[e.key] != paid)) throw const FormatException('Riwayat pembayaran nota tidak cocok.');
      if (e.value['status'] == 'completed' && paid != _int(e.value['total_amount'], 'Total nota')) throw const FormatException('Status lunas tidak cocok.');
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


    final serviceIds = <int>{};
    final serviceNames = <String>{};
    for (final row in data['service_types'] ?? const <Map<String, Object?>>[]) {
      final id = _positiveInt(row['id'], 'ID jenis pekerjaan');
      if (!serviceIds.add(id)) throw FormatException('ID jenis pekerjaan duplikat: $id.');
      final name = _text(row['name'], 'Nama jenis pekerjaan');
      if (!serviceNames.add(name.toLowerCase())) throw FormatException('Nama jenis pekerjaan duplikat: $name.');
      _nonNegativeInt(row['default_price'], 'Harga standar pekerjaan');
      final active = _nonNegativeInt(row['is_active'], 'Status jenis pekerjaan');
      if (active > 1) throw const FormatException('Status jenis pekerjaan tidak valid.');
      _text(row['created_at'], 'Tanggal jenis pekerjaan');
      _text(row['updated_at'], 'Tanggal pembaruan jenis pekerjaan');
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

  // Settings may intentionally store an empty string to clear an optional value.
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
