import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import '../../services/packing_receipt_printer.dart';

class PackingReceiptDetailScreen extends StatefulWidget {
  const PackingReceiptDetailScreen({super.key, required this.receiptId});
  final int receiptId;
  @override
  State<PackingReceiptDetailScreen> createState() => _PackingReceiptDetailScreenState();
}

class _PackingReceiptDetailScreenState extends State<PackingReceiptDetailScreen> {
  final _repo = PackingTransactionRepository();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _received = TextEditingController();
  String _method = 'cash';
  bool _busy = false;
  Map<String, Object?>? _receipt;
  List<Map<String, Object?>> _jobs = [];
  List<Map<String, Object?>> _payments = [];
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _amount.dispose(); _note.dispose(); _received.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final receipt = await _repo.findReceiptById(widget.receiptId);
      if (receipt == null) throw StateError('Nota tidak ditemukan.');
      final jobs = await _repo.jobsForReceipt(widget.receiptId);
      final payments = await _repo.receiptPaymentsFor(widget.receiptId);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _jobs = jobs;
        _payments = payments;
        _error = null;
        final remaining = (receipt['total_amount'] as num).toInt() - (receipt['paid_amount'] as num).toInt();
        _amount.text = remaining > 0 ? remaining.toString() : '';
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }

  String _money(Object? value) {
    final n = (value as num?)?.toInt() ?? 0;
    return 'Rp ${n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
  }

  int? _parse(String text) => int.tryParse(
    text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '').trim(),
  );

  String _date(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    return date == null ? '-' : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  Future<void> _printReceipt() async {
    if (_receipt == null || _busy) return;
    setState(() => _busy = true);
    try {
      final materials = <int, List<Map<String, Object?>>>{};
      for (final job in _jobs) {
        final id = (job['id'] as num).toInt();
        materials[id] = await _repo.materialsFor(id);
      }
      await PackingReceiptPrinter.printReceipt(
        receipt: _receipt!,
        jobs: _jobs,
        materialsByJob: materials,
        payments: _payments,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nota dikirim ke printer.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    if (_busy || _receipt == null) return;
    final total = (_receipt!['total_amount'] as num).toInt();
    final remaining = total - (_receipt!['paid_amount'] as num).toInt();
    final amount = _parse(_amount.text);
    if (amount == null || amount <= 0) { setState(() => _error = 'Nominal pembayaran tidak valid.'); return; }
    if (amount > remaining) { setState(() => _error = 'Pembayaran melebihi sisa tagihan ${_money(remaining)}.'); return; }
    var note = _note.text.trim();
    int change = 0;
    if (_method == 'cash' && _received.text.trim().isNotEmpty) {
      final received = _parse(_received.text);
      if (received == null || received < amount) { setState(() => _error = 'Uang diterima kurang dari nominal pembayaran.'); return; }
      change = received - amount;
      final cashNote = 'Diterima ${_money(received)}, kembali ${_money(change)}';
      note = note.isEmpty ? cashNote : '$note • $cashNote';
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.addReceiptPayment(receiptId: widget.receiptId, amount: amount, paymentMethod: _method, note: note);
      _received.clear(); _note.clear();
      await _load();
      if (mounted) {
        final done = amount == remaining;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: Duration(seconds: change > 0 ? 10 : 4),
          content: Text('${done ? 'Nota lunas' : 'Pembayaran tersimpan'}${change > 0 ? ' • Kembalian ${_money(change)}' : ''}'),
        ));
      }
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _cancel() async {
    if (_busy || _receipt == null) return;
    final reason = TextEditingController();
    final paid = (_receipt!['paid_amount'] as num).toInt();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Batalkan nota?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(paid > 0
              ? 'Nota sudah dibayar ${_money(paid)}. Pengembalian uang harus dilakukan manual. Nota batal tidak dihitung di laporan.'
              : 'Nota batal tidak dihitung di laporan dan tidak dapat dipulihkan.'),
          const SizedBox(height: 12),
          TextField(controller: reason, autofocus: true, onChanged: (_) => setLocal(() {}),
            decoration: const InputDecoration(labelText: 'Alasan pembatalan (wajib)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Batalkan nota')),
        ],
      )),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.cancelReceipt(receiptId: widget.receiptId, reason: text);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nota dibatalkan.')));
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) return Scaffold(appBar: AppBar(title: const Text('Detail nota'), actions: [IconButton(tooltip: 'Cetak nota', onPressed: _busy ? null : _printReceipt, icon: const Icon(Icons.print))]), body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    final total = (receipt['total_amount'] as num).toInt();
    final paid = (receipt['paid_amount'] as num).toInt();
    final status = receipt['status'] as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail nota'), actions: [
        if (status == 'open') IconButton(tooltip: 'Batalkan nota', onPressed: _busy ? null : _cancel, icon: const Icon(Icons.cancel_outlined)),
        IconButton(tooltip: 'Cetak nota', onPressed: _busy ? null : _printReceipt, icon: const Icon(Icons.print)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(receipt['receipt_no'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Pelanggan: ${(receipt['customer_name'] as String).isEmpty ? '-' : receipt['customer_name']}'),
          Text('Tanggal: ${_date(receipt['created_at'])}'),
          Text('Status: ${status == 'completed' ? 'Lunas' : status == 'cancelled' ? 'Dibatalkan' : paid > 0 ? 'Dibayar sebagian' : 'Belum dibayar'}'),
          if (((receipt['discount_amount'] as num?)?.toInt() ?? 0) > 0) Text('Diskon nota: ${_money(receipt['discount_amount'])}'),
          if ((receipt['note'] as String).isNotEmpty) Text('Catatan: ${receipt['note']}'),
        ]))),
        Text('Rincian pekerjaan • ${_jobs.length}', style: Theme.of(context).textTheme.titleMedium),
        ...List.generate(_jobs.length, (i) {
          final job = _jobs[i];
          return Card(child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text((job['item_description'] as String).isEmpty ? 'Pekerjaan' : job['item_description'] as String),
            subtitle: Text('Qty ${job['quantity'] ?? 1} • Ukuran: ${job['length_cm']} × ${job['width_cm']} × ${job['height_cm']} cm • Harga satuan ${_money(job['unit_price'] ?? job['selling_price'])}'),
            trailing: Text(_money(job['selling_price']), style: const TextStyle(fontWeight: FontWeight.bold)),
          ));
        }),
        Card(child: Column(children: [
          if (((receipt['discount_amount'] as num?)?.toInt() ?? 0) > 0) ListTile(title: const Text('Subtotal setelah diskon'), trailing: Text(_money(total + ((receipt['discount_amount'] as num?)?.toInt() ?? 0)))),
          ListTile(title: const Text('Total nota'), trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ListTile(title: const Text('Pembayaran'), trailing: Text(_money(paid))),
          ListTile(title: const Text('Sisa'), trailing: Text(_money(total - paid), style: const TextStyle(fontWeight: FontWeight.bold))),
        ])),
        if (status == 'open' && total - paid > 0) ...[
          Text(paid > 0 ? 'Pelunasan / pembayaran berikutnya' : 'Pembayaran (penuh atau DP)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: _amount, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(
            labelText: 'Nominal pembayaran', prefixText: 'Rp ', border: const OutlineInputBorder(),
            helperText: 'Sisa tagihan ${_money(total - paid)}',
            suffixIcon: TextButton(onPressed: () => setState(() => _amount.text = (total - paid).toString()), child: const Text('Lunas')),
          )),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Metode pembayaran', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Tunai')),
              DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
              DropdownMenuItem(value: 'qris', child: Text('QRIS')),
              DropdownMenuItem(value: 'other', child: Text('Lainnya')),
            ],
            onChanged: (v) { if (v != null) setState(() => _method = v); },
          ),
          if (_method == 'cash') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _received,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Uang diterima (opsional)',
                prefixText: 'Rp ',
                border: const OutlineInputBorder(),
                helperText: () {
                  final received = _parse(_received.text);
                  final amount = _parse(_amount.text);
                  return received != null && amount != null && received >= amount
                      ? 'Kembalian ${_money(received - amount)}'
                      : null;
                }(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan pembayaran (opsional)')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _pay, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payments), label: Text(_busy ? 'Menyimpan...' : 'Simpan pembayaran')),
        ],
        Text('Riwayat pembayaran', style: Theme.of(context).textTheme.titleMedium),
        Card(child: Column(children: _payments.isEmpty
          ? [const ListTile(title: Text('Belum ada pembayaran'))]
          : _payments.map((p) => ListTile(
              title: Text(_money(p['amount'])),
              subtitle: Text('${p['payment_method']} • ${_date(p['created_at'])}${(p['note'] ?? '').toString().isEmpty ? '' : '\n${p['note']}'}'),
            )).toList())),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
