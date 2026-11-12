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
    'customers',
    'app_settings',
    'cash_sessions',
    'cash_expenses',
  ];

  static Map<String, List<Map<String, Object?>>> validate(
    Map<String, dynamic> backup,
  ) {
    final version = backup['version'];
    if (backup['format'] != 'packing_pos_backup' ||
        (version != 1 && version != 2 && version != 3 && version != 4 && version != 5 && version != 6 && version != 7)) {
      throw const FormatException('Format atau versi backup tidak didukung.');
    }

    final data = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      if ((table == 'service_types' && version < 3 && backup[table] == null) || (version < 4 && ['packing_receipts', 'receipt_payments'].contains(table)) || (table == 'customers' && version < 6) || (['cash_sessions', 'cash_expenses'].contains(table) && version < 7)) continue;
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

    if (version < 5) {
      for (final row in data['packing_transactions']!) {
        row['quantity'] = 1;
        row['unit_price'] = row['selling_price'];
      }
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
      final unitPrice = _nonNegativeInt(row['unit_price'], 'Harga satuan pekerjaan');
      final quantity = _positiveInt(row['quantity'], 'Qty pekerjaan');
      if (unitPrice * quantity != _int(row['selling_price'], 'selling_price')) {
        throw FormatException('Subtotal pekerjaan $id tidak cocok dengan qty dan harga satuan.');
      }
      for (final field in ['length_cm', 'width_cm', 'height_cm']) {
        _nonNegativeNumber(row[field], field);
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
    if (version < 5) {
      for (final row in data['packing_receipts']!) {
        row['discount_amount'] = 0;
      }
    }
    final headerIds = <int>{}; final headerNos = <String>{}; final headerMap = <int, Map<String, Object?>>{};
    for (final row in data['packing_receipts']!) {
      final id = _positiveInt(row['id'], 'ID nota'); final no = _text(row['receipt_no'], 'Nomor nota');
      if (!headerIds.add(id) || !headerNos.add(no)) throw FormatException('ID atau nomor nota duplikat: $no');
      final total = _nonNegativeInt(row['total_amount'], 'Total nota');
      _nonNegativeInt(row['discount_amount'], 'Diskon nota');
      final paid = _nonNegativeInt(row['paid_amount'], 'Pembayaran nota');
      if (paid > total) throw FormatException('Pembayaran nota melebihi total: $no');
      final status = _text(row['status'], 'Status nota');
      if (!['open', 'completed', 'cancelled'].contains(status)) throw FormatException('Status nota tidak dikenal: $no');
      _text(row['created_at'], 'Tanggal nota'); _text(row['updated_at'], 'Pembaruan nota'); headerMap[id] = row;
    }
    final sums = <int, int>{};
    for (final tx in data['packing_transactions']!) {
      final rid = _positiveInt(tx['receipt_id'], 'ID nota pekerjaan');
      if (!headerMap.containsKey(rid)) throw const FormatException('Pekerjaan merujuk nota yang tidak ada.');
      sums[rid] = (sums[rid] ?? 0) + _int(tx['selling_price'], 'Harga pekerjaan');
    }
    for (final e in headerMap.entries) {
      final gross = sums[e.key] ?? 0;
      final discount = _int(e.value['discount_amount'], 'Diskon nota');
      if (discount > gross) {
        throw const FormatException('Diskon nota melebihi subtotal pekerjaan.');
      }
      if (e.value['status'] != 'cancelled' &&
          gross - discount != _int(e.value['total_amount'], 'Total nota')) {
        throw const FormatException('Total pekerjaan tidak cocok dengan total nota.');
      }
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
      final total = _int(e.value['total_amount'], 'Total nota');
      if (e.value['status'] == 'completed' && paid != total) {
        throw const FormatException('Status lunas tidak cocok.');
      }
      if (e.value['status'] == 'open' && total > 0 && paid >= total) {
        throw const FormatException('Status nota terbuka tidak cocok dengan jumlah pembayaran.');
      }
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
      final actualQuantity = _nonNegativeNumber(row['actual_quantity'], 'Jumlah aktual');
      final unitPrice = _nonNegativeInt(row['unit_price_snapshot'], 'Harga snapshot bahan');
      final subtotal = _nonNegativeInt(row['subtotal'], 'Subtotal bahan');
      final expectedSubtotal = (actualQuantity * unitPrice).round();
      if (subtotal != expectedSubtotal) {
        throw FormatException(
          'Subtotal bahan pada rincian $id tidak cocok dengan jumlah aktual dan harga snapshot.',
        );
      }
      _text(row['created_at'], 'Tanggal rincian bahan');
    }

    final customerIds = <int>{};
    final customerNames = <String>{};
    for (final row in data['customers'] ?? const <Map<String, Object?>>[]) {
      final id = _positiveInt(row['id'], 'ID pelanggan');
      if (!customerIds.add(id)) throw FormatException('ID pelanggan duplikat: $id.');
      final name = _text(row['name'], 'Nama pelanggan');
      if (!customerNames.add(name.trim().toLowerCase())) {
        throw FormatException('Nama pelanggan duplikat: $name.');
      }
      _string(row['phone'], 'Telepon pelanggan');
      _string(row['address'], 'Alamat pelanggan');
      _string(row['note'], 'Catatan pelanggan');
      final active = _nonNegativeInt(row['is_active'], 'Status pelanggan');
      if (active > 1) throw const FormatException('Status pelanggan tidak valid.');
      _text(row['created_at'], 'Tanggal pelanggan');
      _text(row['updated_at'], 'Pembaruan pelanggan');
    }

    final cashSessionIds = <int>{};
    final cashDateKeys = <String>{};
    for (final row in data['cash_sessions'] ?? const <Map<String, Object?>>[]) {
      final id = _positiveInt(row['id'], 'ID sesi kas');
      if (!cashSessionIds.add(id)) {
        throw FormatException('ID sesi kas duplikat: $id.');
      }
      final dateKey = _text(row['date_key'], 'Tanggal sesi kas');
      final parsedDate = DateTime.tryParse(dateKey);
      final isRealCalendarDate = parsedDate != null &&
          '${parsedDate.year.toString().padLeft(4, '0')}-'
                  '${parsedDate.month.toString().padLeft(2, '0')}-'
                  '${parsedDate.day.toString().padLeft(2, '0')}' ==
              dateKey;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateKey) ||
          !isRealCalendarDate ||
          !cashDateKeys.add(dateKey)) {
        throw FormatException('Tanggal sesi kas tidak valid atau duplikat: $dateKey.');
      }
      _nonNegativeInt(row['opening_balance'], 'Saldo awal kas');
      final status = _text(row['status'], 'Status sesi kas');
      if (!['open', 'closed'].contains(status)) {
        throw const FormatException('Status sesi kas tidak valid.');
      }
      _string(row['note'], 'Catatan sesi kas');
      _text(row['created_at'], 'Tanggal pembuatan sesi kas');
      if (status == 'closed') {
        final expected = _signedInt(row['expected_balance'], 'Saldo kas seharusnya');
        final counted = _nonNegativeInt(row['counted_balance'], 'Saldo kas fisik');
        final difference = _signedInt(row['difference'], 'Selisih kas');
        if (difference != counted - expected) {
          throw const FormatException('Selisih kas tidak cocok dengan saldo fisik dan saldo seharusnya.');
        }
        _text(row['closed_at'], 'Tanggal tutup kas');
      }
    }

    final cashExpenseIds = <int>{};
    for (final row in data['cash_expenses'] ?? const <Map<String, Object?>>[]) {
      final id = _positiveInt(row['id'], 'ID pengeluaran kas');
      if (!cashExpenseIds.add(id)) {
        throw FormatException('ID pengeluaran kas duplikat: $id.');
      }
      final sessionId = _positiveInt(row['session_id'], 'ID sesi pengeluaran kas');
      if (!cashSessionIds.contains(sessionId)) {
        throw const FormatException('Pengeluaran kas merujuk sesi yang tidak ada.');
      }
      _positiveInt(row['amount'], 'Nominal pengeluaran kas');
      _text(row['category'], 'Kategori pengeluaran kas');
      _string(row['note'], 'Catatan pengeluaran kas');
      _text(row['created_at'], 'Tanggal pengeluaran kas');
    }

    // A closed cash session is a historical snapshot. Verify its expected
    // balance against the same date-scoped cash inflows and linked expenses
    // used by cashSessionSummary/closeCashSession.
    for (final row in data['cash_sessions'] ?? const <Map<String, Object?>>[]) {
      if (row['status'] != 'closed') continue;
      final sessionId = _positiveInt(row['id'], 'ID sesi kas');
      final dateKey = _text(row['date_key'], 'Tanggal sesi kas');
      final date = DateTime.parse(dateKey);
      final start = DateTime(date.year, date.month, date.day).toUtc();
      final end = DateTime(date.year, date.month, date.day + 1).toUtc();
      bool inSessionDate(Object? value) {
        final parsed = DateTime.tryParse(value is String ? value : '');
        if (parsed == null) return false;
        final utc = parsed.toUtc();
        return !utc.isBefore(start) && utc.isBefore(end);
      }

      var cashIn = 0;
      for (final payment in data['receipt_payments']!) {
        final receiptId = _positiveInt(payment['receipt_id'], 'ID nota pembayaran');
        final receipt = headerMap[receiptId];
        if (receipt != null &&
            receipt['status'] != 'cancelled' &&
            payment['payment_method'].toString().trim().toLowerCase() == 'cash' &&
            inSessionDate(payment['created_at'])) {
          cashIn += _positiveInt(payment['amount'], 'Nominal pembayaran nota');
        }
      }
      for (final payment in data['transaction_payments']!) {
        final transactionId = _positiveInt(payment['transaction_id'], 'ID transaksi pembayaran');
        final transaction = transactions[transactionId]!;
        if (transaction['receipt_id'] == null &&
            transaction['status'] != 'cancelled' &&
            payment['payment_method'].toString().trim().toLowerCase() == 'cash' &&
            inSessionDate(payment['created_at'])) {
          cashIn += _positiveInt(payment['amount'], 'Nominal pembayaran');
        }
      }
      var expenses = 0;
      for (final expense in data['cash_expenses']!) {
        if (_positiveInt(expense['session_id'], 'ID sesi pengeluaran kas') == sessionId) {
          expenses += _positiveInt(expense['amount'], 'Nominal pengeluaran kas');
        }
      }
      final expected = _nonNegativeInt(row['opening_balance'], 'Saldo awal kas') +
          cashIn - expenses;
      if (_signedInt(row['expected_balance'], 'Saldo kas seharusnya') != expected) {
        throw FormatException('Saldo kas seharusnya pada sesi $sessionId tidak cocok dengan transaksi dan pengeluaran.');
      }
    }

    final settingKeys = <String>{};
    for (final row in data['app_settings']!) {
      final key = _text(row['key'], 'Kunci pengaturan');
      if (!settingKeys.add(key)) {
        throw FormatException('Kunci pengaturan duplikat: $key.');
      }
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

  static int _signedInt(Object? value, String field) {
    if (value is! num || !value.isFinite || value != value.round()) {
      throw FormatException('$field harus berupa bilangan bulat.');
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

  static double _nonNegativeNumber(Object? value, String field) {
    final result = _number(value, field);
    if (result < 0) throw FormatException('$field tidak boleh negatif.');
    return result;
  }
}
