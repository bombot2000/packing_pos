import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/format/dimensions.dart';
import '../../core/format/friendly_error.dart';
import '../../core/format/money_input.dart';
import '../../core/format/rupiah.dart';
import 'packing_calculator_screen.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import '../../services/packing_receipt_printer.dart';
import '../../data/repositories/packing_identity_repository.dart';

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
  Map<String, String> _identity = PackingIdentityRepository.defaults;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _amount.dispose(); _note.dispose(); _received.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final identity = await PackingIdentityRepository().getSettings();
      final receipt = await _repo.findReceiptById(widget.receiptId);
      if (receipt == null) throw StateError('Nota tidak ditemukan.');
      final jobs = await _repo.jobsForReceipt(widget.receiptId);
      final payments = await _repo.receiptPaymentsFor(widget.receiptId);
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _receipt = receipt;
        _jobs = jobs;
        _payments = payments;
        _error = null;
        final remaining = (receipt['total_amount'] as num).toInt() - (receipt['paid_amount'] as num).toInt();
        _amount.text = remaining > 0 ? groupThousands(remaining) : '';
      });
    } catch (e) { if (mounted) setState(() => _error = friendlyError(e)); }
  }

  String _money(Object? value) => formatRupiah(value);
  int? _parse(String text) => parseRupiah(text);

  String _date(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    return date == null ? '-' : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  Future<void> _editReceipt() async {
    if (_busy || _receipt == null) return;
    final paid = (_receipt!['paid_amount'] as num).toInt();
    if (_receipt!['status'] != 'open' || paid > 0 || _payments.isNotEmpty) {
      setState(() => _error = 'Nota hanya dapat diedit sebelum pembayaran pertama.');
      return;
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PackingCalculatorScreen(editReceiptId: widget.receiptId),
    ));
    if (changed == true) await _load();
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
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _receiptText() {
    final r = _receipt!;
    final total = (r['total_amount'] as num).toInt();
    final paid = (r['paid_amount'] as num).toInt();
    final discount = (r['discount_amount'] as num?)?.toInt() ?? 0;
    final b = StringBuffer()
      ..writeln(_identity['business_name'] ?? 'Packing POS')
      ..writeln('Nota ${r['receipt_no']}')
      ..writeln('Tanggal: ${_date(r['created_at'])}');
    final customer = (r['customer_name'] as String?) ?? '';
    if (customer.isNotEmpty) b.writeln('Pelanggan: $customer');
    b.writeln();
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      final desc = (job['item_description'] as String? ?? '').replaceAll('•', '-');
      b.writeln('${i + 1}. ${desc.isEmpty ? 'Pekerjaan' : desc}');
      b.writeln('   ${job['quantity'] ?? 1} x ${_money(job['unit_price'] ?? job['selling_price'])} = ${_money(job['selling_price'])}');
    }
    b.writeln();
    if (discount > 0) { b.writeln('Subtotal: ${_money(total + discount)}'); b.writeln('Diskon: -${_money(discount)}'); }
    b.writeln('TOTAL: ${_money(total)}');
    b.writeln('Dibayar: ${_money(paid)}');
    if (total - paid > 0) b.writeln('Sisa: ${_money(total - paid)}');
    b.writeln('Status: ${r['status'] == 'cancelled' ? 'DIBATALKAN' : total > 0 && paid >= total ? 'LUNAS' : paid > 0 ? 'DIBAYAR SEBAGIAN' : 'BELUM DIBAYAR'}');
    b.writeln(); b.write('Terima kasih');
    return b.toString();
  }

  Future<void> _shareReceipt() async {
    if (_receipt == null) return;
    try { await Share.share(_receiptText(), subject: 'Nota ${_receipt!['receipt_no']}'); }
    catch (e) { if (mounted) setState(() => _error = friendlyError(e)); }
  }

  Future<void> _showPaymentSuccess({required bool done, required int amount, required int change}) async {
    final color = Theme.of(context).colorScheme.primary;
    final action = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 56, color: color), const SizedBox(height: 8),
          Text(done ? 'Nota lunas' : 'Pembayaran tersimpan', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text('Diterima ${_money(amount)}'),
          if (change > 0) ...[const SizedBox(height: 12), const Text('Kembalian'), Text(_money(change), style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color))],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'print'), icon: const Icon(Icons.print), label: const Text('Cetak struk'))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'share'), icon: const Icon(Icons.share), label: const Text('Bagikan ke WhatsApp / aplikasi lain'))),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('Nota baru'))),
            Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, 'done'), child: const Text('Selesai'))),
          ]),
        ]),
      )));
    if (!mounted) return;
    if (action == 'print') {
      await _printReceipt();
    } else if (action == 'share') {
      await _shareReceipt();
    } else if (action == 'new') {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PackingCalculatorScreen()),
      );
    }
  }

  Widget _methodChips() {
    const methods = {'cash': 'Tunai', 'transfer': 'Transfer', 'qris': 'QRIS', 'other': 'Lainnya'};
    return Wrap(spacing: 8, children: methods.entries.map((e) => ChoiceChip(
      label: Text(e.value), selected: _method == e.key, onSelected: (_) => setState(() => _method = e.key),
    )).toList());
  }

  List<int> _cashSuggestions(int amount) {
    if (amount <= 0) return const [];
    int roundUp(int step) => ((amount + step - 1) ~/ step) * step;
    final values = <int>{amount, roundUp(10000), roundUp(50000), roundUp(100000)}.toList()..sort();
    return values.take(4).toList();
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
      note = note.isEmpty ? cashNote : '$note - $cashNote';
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.addReceiptPayment(receiptId: widget.receiptId, amount: amount, paymentMethod: _method, note: note);
      _received.clear(); _note.clear();
      await _load();
      if (mounted) {
        setState(() => _busy = false);
        await _showPaymentSuccess(done: amount == remaining, amount: amount, change: change);
      }
    } catch (e) { if (mounted) setState(() => _error = friendlyError(e)); }
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
    // Keep the controller alive until the dialog route has fully closed.
    if (confirmed != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.cancelReceipt(receiptId: widget.receiptId, reason: text);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nota dibatalkan.')));
    } catch (e) { if (mounted) setState(() => _error = friendlyError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) return Scaffold(appBar: AppBar(title: const Text('Detail nota')), body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    final total = (receipt['total_amount'] as num).toInt();
    final paid = (receipt['paid_amount'] as num).toInt();
    final status = receipt['status'] as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail nota'), actions: [
        IconButton(tooltip: 'Bagikan nota', onPressed: _busy ? null : _shareReceipt, icon: const Icon(Icons.share_outlined)),
        if (status == 'open' && paid == 0 && _payments.isEmpty)
          IconButton(tooltip: 'Edit nota', onPressed: _busy ? null : _editReceipt, icon: const Icon(Icons.edit_outlined)),
        if (status == 'open' && paid == 0 && _payments.isEmpty)
          IconButton(tooltip: 'Batalkan nota', onPressed: _busy ? null : _cancel, icon: const Icon(Icons.cancel_outlined)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Column(children: [
            Text(_identity['business_name'] ?? 'Packing POS', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            if ((_identity['business_address'] ?? '').isNotEmpty) Text(_identity['business_address']!, textAlign: TextAlign.center),
            if ((_identity['business_phone'] ?? '').isNotEmpty) Text('Telp. ${_identity['business_phone']}', textAlign: TextAlign.center),
          ])),
          const Divider(height: 24),
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
            subtitle: Text('${job['quantity'] ?? 1} koli x ${_money(job['unit_price'] ?? job['selling_price'])}${dimensionsLabel(job['length_cm'], job['width_cm'], job['height_cm']) == null ? '' : '\nUkuran: ${dimensionsLabel(job['length_cm'], job['width_cm'], job['height_cm'])}'}'),
            trailing: Text(_money(job['selling_price']), style: const TextStyle(fontWeight: FontWeight.bold)),
          ));
        }),
        Card(child: Column(children: [
          if (((receipt['discount_amount'] as num?)?.toInt() ?? 0) > 0) ...[
            ListTile(title: const Text('Subtotal pekerjaan'), trailing: Text(_money(total + ((receipt['discount_amount'] as num?)?.toInt() ?? 0)))),
            ListTile(title: const Text('Diskon nota'), trailing: Text('- ${_money(receipt['discount_amount'])}')),
          ],
          ListTile(title: const Text('Total nota'), trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ListTile(title: const Text('Pembayaran'), trailing: Text(_money(paid))),
          ListTile(title: const Text('Sisa'), trailing: Text(_money(total - paid), style: const TextStyle(fontWeight: FontWeight.bold))),
        ])),
        if (status == 'open' && total - paid > 0) ...[
          Text(paid > 0 ? 'Pelunasan / pembayaran berikutnya' : 'Pembayaran (penuh atau DP)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(controller: _amount, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], onChanged: (_) => setState(() {}), decoration: InputDecoration(
            labelText: 'Nominal pembayaran', prefixText: 'Rp ', border: const OutlineInputBorder(),
            helperText: 'Sisa tagihan ${_money(total - paid)}',
            suffixIcon: TextButton(onPressed: () => setState(() => _amount.text = (total - paid).toString()), child: const Text('Lunas')),
          )),
          const SizedBox(height: 8),
          const Text('Metode pembayaran'),
          const SizedBox(height: 4),
          _methodChips(),
          if (_method == 'cash') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _received,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
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
            Builder(builder: (context) {
              final amount = _parse(_amount.text);
              if (amount == null || amount <= 0) return const SizedBox.shrink();
              return Wrap(spacing: 6, children: _cashSuggestions(amount).map((value) =>
                ActionChip(label: Text(_money(value)), onPressed: () => setState(() => _received.text = groupThousands(value)),
              )).toList());
            }),
          ],
          const SizedBox(height: 8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan pembayaran (opsional)')),
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'open' && total - paid > 0)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pay,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.payments),
                  label: Text(_busy ? 'Menyimpan pembayaran...' : 'Simpan pembayaran'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            if (status == 'open' && total - paid > 0) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _printReceipt,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print),
                label: const Text('Cetak nota'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
