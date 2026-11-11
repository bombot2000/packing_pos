import 'dart:async';

import 'package:flutter/material.dart';
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
  String _method = 'cash';
  bool _busy = false;
  Map<String, Object?>? _receipt;
  List<Map<String, Object?>> _jobs = [];
  List<Map<String, Object?>> _payments = [];
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final receipt = await _repo.findReceiptById(widget.receiptId);
      if (receipt == null) throw StateError('Nota tidak ditemukan.');
      final jobs = await _repo.jobsForReceipt(widget.receiptId);
      final payments = await _repo.receiptPaymentsFor(widget.receiptId);
      if (!mounted) return;
      setState(() { _receipt = receipt; _jobs = jobs; _payments = payments; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }

  String _money(Object? value) {
    final n = (value as num?)?.toInt() ?? 0;
    return 'Rp ' + n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.');
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

  Future<void> _settle() async {
    if (_busy || _receipt == null) return;
    final total = (_receipt!['total_amount'] as num).toInt();
    final amount = int.tryParse(_amount.text.replaceAll('.', '').replaceAll(',', '').trim());
    if (amount == null || amount != total) {
      setState(() => _error = 'Pembayaran harus tepat sebesar total nota ${_money(total)}.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.settleReceipt(receiptId: widget.receiptId, amount: amount, paymentMethod: _method, note: _note.text.trim());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran nota berhasil disimpan.')));
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
      appBar: AppBar(title: const Text('Detail nota'), actions: [IconButton(tooltip: 'Cetak nota', onPressed: _busy ? null : _printReceipt, icon: const Icon(Icons.print))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(receipt['receipt_no'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Pelanggan: ${(receipt['customer_name'] as String).isEmpty ? '-' : receipt['customer_name']}'),
          Text('Tanggal: ${receipt['created_at']}'),
          Text('Status: ${status == 'completed' ? 'Lunas' : status == 'cancelled' ? 'Dibatalkan' : paid > 0 ? 'Pembayaran sebagian (nota lama)' : 'Belum dibayar'}'),
          if ((receipt['note'] as String).isNotEmpty) Text('Catatan: ${receipt['note']}'),
        ]))),
        Text('Rincian pekerjaan • ${_jobs.length}', style: Theme.of(context).textTheme.titleMedium),
        ...List.generate(_jobs.length, (i) {
          final job = _jobs[i];
          return Card(child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text((job['item_description'] as String).isEmpty ? 'Pekerjaan' : job['item_description'] as String),
            subtitle: Text('Ukuran: ${job['length_cm']} × ${job['width_cm']} × ${job['height_cm']} cm'),
            trailing: Text(_money(job['selling_price']), style: const TextStyle(fontWeight: FontWeight.bold)),
          ));
        }),
        Card(child: Column(children: [
          ListTile(title: const Text('Total nota'), trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ListTile(title: const Text('Pembayaran'), trailing: Text(_money(paid))),
          ListTile(title: const Text('Sisa'), trailing: Text(_money(total - paid), style: const TextStyle(fontWeight: FontWeight.bold))),
        ])),
        if (status == 'open' && total > 0 && paid == 0) ...[
          Text('Pembayaran satu kali untuk seluruh nota', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Nominal pembayaran', prefixText: 'Rp ', helperText: 'Isi tepat ${_money(total)}')),
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
          const SizedBox(height: 8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan pembayaran (opsional)')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _settle, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payments), label: Text(_busy ? 'Menyimpan...' : 'Bayar seluruh nota')),
        ],
        if (status == 'open' && paid > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nota ini berasal dari data lama dengan pembayaran bertahap. Riwayat tetap disimpan, tetapi pembayaran baru melalui alur satu kali tidak tersedia untuk nota ini.')),
        Text('Riwayat pembayaran', style: Theme.of(context).textTheme.titleMedium),
        Card(child: Column(children: _payments.isEmpty
          ? [const ListTile(title: Text('Belum ada pembayaran'))]
          : _payments.map((p) => ListTile(
              title: Text(_money(p['amount'])),
              subtitle: Text('${p['payment_method']} • ${p['created_at']}'),
            )).toList())),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
