import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';
import '../../services/packing_receipt_printer.dart';

class _PaymentInput {
  const _PaymentInput({
    required this.amount,
    required this.method,
    required this.note,
  });

  final int amount;
  final String method;
  final String note;
}

/// Dialog owns its controllers and validation state. Keeping the payment form
/// out of a nested Form/GlobalKey + StatefulBuilder avoids inherited-element
/// lifecycle assertions when the dialog route is dismissed on Android.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.maxAmount});

  final int maxAmount;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _method = 'cash';
  String? _error;
  bool _paymentInProgress = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int? _parseAmount(String value) {
    final normalized = value.replaceAll('.', '').replaceAll(',', '').trim();
    return int.tryParse(normalized);
  }

  void _submit() {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Masukkan nominal pembayaran yang valid.');
      return;
    }
    if (amount > widget.maxAmount) {
      setState(() => _error = 'Melebihi sisa tagihan (' + widget.maxAmount.toString() + ').');
      return;
    }
    Navigator.of(context).pop(_PaymentInput(
      amount: amount,
      method: _method,
      note: _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tambah pembayaran'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nominal pembayaran',
              prefixText: 'Rp ',
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Metode'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _method,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Tunai')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                  DropdownMenuItem(value: 'qris', child: Text('QRIS')),
                  DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _method = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Simpan'),
      ),
    ],
  );
}

class PackingTransactionDetailScreen extends StatefulWidget {
  const PackingTransactionDetailScreen({super.key, required this.transactionId});
  final int transactionId;

  @override
  State<PackingTransactionDetailScreen> createState() => _PackingTransactionDetailScreenState();
}

class _PackingTransactionDetailScreenState extends State<PackingTransactionDetailScreen> {
  final _repository = PackingTransactionRepository();
  late Future<void> _load;
  Map<String, Object?>? _transaction;
  List<Map<String, Object?>> _materials = [];
  List<Map<String, Object?>> _payments = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load = _refresh();
  }

  Future<void> _refresh() async {
    try {
      final found = await _repository.findById(widget.transactionId);
      if (found == null) throw StateError('Transaksi tidak ditemukan.');
      final materials = await _repository.materialsFor(widget.transactionId);
      final payments = await _repository.paymentsFor(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _transaction = found;
        _materials = materials;
        _payments = payments;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return 'Rp ${amount.toString().replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (m) => '.',
    )}';
  }


  Future<void> _printReceipt() async {
    try {
      await PackingReceiptPrinter.printTransaction(
        transaction: _transaction!,
        materials: _materials,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nota berhasil dikirim ke printer.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal mencetak nota: $error');
    }
  }



  Widget _timberPlanCard(String title, Map<String, dynamic> plan) {
    final bins = plan['bins'] as List<dynamic>? ?? const [];
    return Card(child: Column(children: [
      ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text((plan['stockCount'] as num).toString()),
      ),
      ListTile(
        title: const Text('Panjang stok per batang'),
        trailing: Text((plan['stockLengthCm'] as num).toStringAsFixed(1) + ' cm'),
      ),
      ListTile(
        title: const Text('Sisa total'),
        trailing: Text((plan['leftoverLengthCm'] as num).toStringAsFixed(1) + ' cm'),
      ),
      ...bins.map((raw) {
        final bin = raw as Map<String, dynamic>;
        final cuts = (bin['cuts'] as List<dynamic>? ?? const []).map((rawCut) {
          final cut = rawCut as Map<String, dynamic>;
          return (cut['label']?.toString() ?? 'Potongan') + ' ' +
              (cut['lengthCm'] as num).toStringAsFixed(1) + ' cm';
        }).join(' • ');
        return ListTile(
          dense: true,
          title: Text(title + ' ' + bin['number'].toString()),
          subtitle: Text(cuts),
          trailing: Text('Sisa ' + (bin['remainingLengthCm'] as num).toStringAsFixed(1) + ' cm'),
        );
      }),
    ]));
  }

  String _faceLabel(String value) {
    switch (value) {
      case 'top': return 'Atas';
      case 'bottom': return 'Bawah';
      case 'front': return 'Depan';
      case 'back': return 'Belakang';
      case 'left': return 'Kiri';
      case 'right': return 'Kanan';
      default: return value;
    }
  }

  Future<void> _addPayment() async {
    // Prevent opening multiple payment dialogs from rapid taps.
    if (_paymentInProgress || _transaction == null) return;
    setState(() => _paymentInProgress = true);
    try {
      final total = (_transaction!['selling_price'] as num).toInt();
      final paid = (_transaction!['paid_amount'] as num).toInt();
      final payment = await showDialog<_PaymentInput>(
        context: context,
        builder: (_) => _PaymentDialog(maxAmount: total - paid),
      );
      if (payment == null || !mounted) return;

      await _repository.addPayment(
        transactionId: widget.transactionId,
        amount: payment.amount,
        paymentMethod: payment.method,
        note: payment.note,
      );
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pembayaran: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _paymentInProgress = false);
    }
  }

  Future<void> _cancelTransaction() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan transaksi?'),
        content: TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Alasan pembatalan')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kembali')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Batalkan')),
        ],
      ),
    );
    final note = reason.text;
    reason.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _repository.cancel(widget.transactionId, reason: note);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail nota')),
    body: FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _transaction == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_transaction == null) return Center(child: Text(_error ?? 'Transaksi tidak ditemukan.'));
        final tx = _transaction!;
        final total = (tx['selling_price'] as num).toInt();
        final paid = (tx['paid_amount'] as num).toInt();
        final balance = total - paid;
        final status = tx['status'] as String;
        final snapshotData = jsonDecode(tx['calculation_snapshot'] as String) as Map<String, dynamic>;
        final dimensions = snapshotData['dimensionsCm'] as Map<String, dynamic>? ?? {};
        final jobType = snapshotData['jobType']?.toString() ?? '';
        final isManualService = snapshotData['mode'] == 'manual_service_charge';
        final faceSettings = snapshotData['faceSettings'] as List<dynamic>? ?? const [];
        final frameData = snapshotData['frame'] as Map<String, dynamic>?;
        final timberPlans = snapshotData['timberCutPlans'] as Map<String, dynamic>?;
        final legacyTimberPlan = snapshotData['timberCutPlan'] as Map<String, dynamic>?;
        final frameTimberPlan = timberPlans?['frame'] as Map<String, dynamic>? ?? legacyTimberPlan;
        final slatTimberPlan = timberPlans?['slat'] as Map<String, dynamic>?;
        final boardPlan = snapshotData['boardSheetPlan'] as Map<String, dynamic>?;
        final boardSheets = boardPlan?['sheets'] as List<dynamic>? ?? const [];
        final frameCuts = frameData?['cuts'] as List<dynamic>? ?? const [];
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx['receipt_no'] as String, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Status: ${status == 'completed' ? 'Lunas' : status == 'cancelled' ? 'Dibatalkan' : 'Belum lunas'}'),
              Text('Pelanggan: ${(tx['customer_name'] as String).isEmpty ? '-' : tx['customer_name']}'),
              if (jobType.isNotEmpty) Text('Jenis pekerjaan: $jobType'),
              Text('Barang: ${(tx['item_description'] as String).isEmpty ? '-' : tx['item_description']}'),
              Text('Ukuran: ${dimensions['length'] ?? tx['length_cm']} × ${dimensions['width'] ?? tx['width_cm']} × ${dimensions['height'] ?? tx['height_cm']} cm'),
              Text('Tanggal: ${tx['created_at']}'),
              if ((tx['note'] as String).isNotEmpty) Text('Catatan: ${tx['note']}'),
              if ((tx['cancellation_reason'] as String? ?? '').isNotEmpty)
                Text('Alasan pembatalan: ${tx['cancellation_reason']}'),
            ]),
          )),
          if (isManualService) ...[
            Card(child: Column(children: [
              ListTile(title: const Text('Ongkos pekerjaan'), trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              const ListTile(title: Text('Perhitungan ukuran'), subtitle: Text('Panjang, lebar, dan tinggi hanya dicatat sebagai informasi. Harga diisi manual.')),
            ])),
          ],
          if (faceSettings.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Pengaturan keenam bidang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Card(child: Column(children: faceSettings.map((raw) {
              final setting = raw as Map<String, dynamic>;
              final face = setting['face']?.toString() ?? '';
              final mode = setting['buildType']?.toString() ?? '';
              final detail = mode == 'openSlat'
                  ? 'Margin kiri ${setting['leftMarginCm']} cm • kanan ${setting['rightMarginCm']} cm'
                  : mode == 'closedBoard'
                      ? 'Overlap panjang ${setting['boardOverlapLengthCm']} cm • lebar ${setting['boardOverlapWidthCm']} cm'
                      : 'Tidak menggunakan bidang';
              return ListTile(
                dense: true,
                title: Text(_faceLabel(face)),
                subtitle: Text(mode + ' • ' + detail),
              );
            }).toList())),
          ],
          if (boardPlan != null) ...[
            const SizedBox(height: 8),
            const Text('Rencana nesting lembar papan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Card(child: Column(children: [
              ListTile(title: const Text('Jumlah lembar'), trailing: Text((boardPlan['sheetCount'] as num).toString())),
              ListTile(title: const Text('Ukuran lembar'), trailing: Text((boardPlan['sheetWidthCm'] as num).toStringAsFixed(1) + ' × ' + (boardPlan['sheetHeightCm'] as num).toStringAsFixed(1) + ' cm')),
              ListTile(title: const Text('Utilisasi area'), trailing: Text((boardPlan['utilizationPercent'] as num).toStringAsFixed(1) + '%')),
              ...boardSheets.map((rawSheet) {
                final sheet = rawSheet as Map<String, dynamic>;
                final placements = (sheet['placements'] as List<dynamic>? ?? const []).map((rawPlacement) {
                  final placement = rawPlacement as Map<String, dynamic>;
                  return (placement['label']?.toString() ?? 'Panel') + ' ' +
                    (placement['widthCm'] as num).toStringAsFixed(1) + '×' +
                    (placement['heightCm'] as num).toStringAsFixed(1) + ' cm';
                }).join(' • ');
                return ListTile(
                  dense: true,
                  title: Text('Lembar ' + sheet['number'].toString()),
                  subtitle: Text(placements),
                );
              }),
            ])),
          ],
          if (frameTimberPlan != null) ...[
            const SizedBox(height: 8),
            _timberPlanCard('Batang rangka', frameTimberPlan),
          ],
          if (slatTimberPlan != null) ...[
            const SizedBox(height: 8),
            _timberPlanCard('Batang bilah', slatTimberPlan),
          ],
          if (frameData != null) ...[
            const SizedBox(height: 8),
            const Text('Rincian potongan rangka', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Card(child: Column(children: [
              ListTile(
                dense: true,
                title: const Text('Metode sambungan'),
                subtitle: Text(frameData['jointMethod']?.toString() ?? 'manual'),
              ),
              ...frameCuts.map((raw) {
                final cut = raw as Map<String, dynamic>;
                return ListTile(
                  dense: true,
                  title: Text(cut['label']?.toString() ?? 'Potongan rangka'),
                  subtitle: Text('${cut['count']} potong × ${(cut['cutLengthCm'] as num).toStringAsFixed(1)} cm'),
                  trailing: Text('${(cut['totalMeters'] as num).toStringAsFixed(2)} m'),
                );
              }),
              ListTile(
                title: const Text('Total rangka dihitung'),
                trailing: Text('${(frameData['calculatedMeters'] as num).toStringAsFixed(2)} m'),
              ),
              if (frameData['actualMeters'] != null)
                ListTile(
                  title: const Text('Pemakaian rangka aktual'),
                  subtitle: Text(frameData['adjustmentReason']?.toString() ?? ''),
                  trailing: Text('${(frameData['actualMeters'] as num).toStringAsFixed(2)} m'),
                ),
            ])),
          ],
          const SizedBox(height: 8),
          if (!isManualService) const Text('Snapshot kebutuhan bahan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          if (!isManualService) Card(child: Column(children: _materials.isEmpty
              ? [const ListTile(title: Text('Tidak ada rincian bahan tersimpan'))]
              : _materials.map((m) => ListTile(
                  title: Text(m['material_name_snapshot'] as String),
                  subtitle: Text('Hitung: ${(m['calculated_quantity'] as num).toStringAsFixed(3)} • Aktual: ${(m['actual_quantity'] as num).toStringAsFixed(3)} ${m['unit_snapshot']}\nHarga snapshot: ${_money(m['unit_price_snapshot'])}'),
                  isThreeLine: true,
                  trailing: Text(_money(m['subtotal'])),
                )).toList())),
          const SizedBox(height: 8),
          const Text('Ringkasan pembayaran', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Card(child: Column(children: [
            ListTile(title: const Text('Total tagihan'), trailing: Text(_money(total))),
            ListTile(title: const Text('Sudah dibayar'), trailing: Text(_money(paid))),
            ListTile(title: const Text('Sisa tagihan'), trailing: Text(_money(balance), style: const TextStyle(fontWeight: FontWeight.bold))),
          ])),
          const SizedBox(height: 8),
          const Text('Riwayat pembayaran', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Card(child: Column(children: _payments.isEmpty
              ? [const ListTile(title: Text('Belum ada pembayaran'))]
              : _payments.map((p) => ListTile(
                  title: Text(_money(p['amount'])),
                  subtitle: Text('${p['payment_method']} • ${p['created_at']}\n${p['note']}'),
                  isThreeLine: (p['note'] as String).isNotEmpty,
                )).toList())),
          if (_error != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          OutlinedButton.icon(
            onPressed: _printReceipt,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Cetak nota Bluetooth'),
          ),
          if (status != 'cancelled' && balance > 0)
            FilledButton.icon(onPressed: _paymentInProgress ? null : _addPayment, icon: const Icon(Icons.payments_outlined), label: Text(_paymentInProgress ? 'Memproses pembayaran…' : 'Tambah pembayaran')),
          if (status != 'cancelled')
            OutlinedButton.icon(onPressed: _cancelTransaction, icon: const Icon(Icons.cancel_outlined), label: const Text('Batalkan transaksi')),
          const SizedBox(height: 16),
        ]);
      },
    ),
  );
}
