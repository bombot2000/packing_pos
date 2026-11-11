import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';

class PackingCashClosingScreen extends StatefulWidget {
  const PackingCashClosingScreen({super.key});

  @override
  State<PackingCashClosingScreen> createState() => _PackingCashClosingScreenState();
}

class _PackingCashClosingScreenState extends State<PackingCashClosingScreen> {
  final _repository = PackingTransactionRepository();
  final _opening = TextEditingController(text: '0');
  final _expenseAmount = TextEditingController();
  final _expenseCategory = TextEditingController();
  final _expenseNote = TextEditingController();
  final _counted = TextEditingController();
  Map<String, Object?>? _summary;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _opening.dispose();
    _expenseAmount.dispose();
    _expenseCategory.dispose();
    _expenseNote.dispose();
    _counted.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final session = await _repository.findCashSession(DateTime.now());
      final summary = session == null
          ? null
          : await _repository.cashSessionSummary((session['id'] as num).toInt());
      if (mounted) setState(() { _summary = summary; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return 'Rp ${amount.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final amount = int.tryParse(_opening.text.trim());
    if (amount == null || amount < 0) { setState(() => _error = 'Masukkan saldo awal berupa angka nol atau lebih.'); return; }
    await _run(() async { await _repository.startCashSession(date: DateTime.now(), openingBalance: amount); });
  }

  Future<void> _addExpense() async {
    final session = _summary?['session'] as Map<String, Object?>?;
    final amount = int.tryParse(_expenseAmount.text.trim());
    if (session == null || amount == null || amount <= 0 || _expenseCategory.text.trim().isEmpty) {
      setState(() => _error = 'Isi nominal dan kategori pengeluaran dengan benar.'); return;
    }
    await _run(() async {
      await _repository.addCashExpense(
        sessionId: (session['id'] as num).toInt(), amount: amount,
        category: _expenseCategory.text, note: _expenseNote.text,
      );
      _expenseAmount.clear(); _expenseCategory.clear(); _expenseNote.clear();
    });
  }

  Future<void> _close() async {
    final session = _summary?['session'] as Map<String, Object?>?;
    final amount = int.tryParse(_counted.text.trim());
    if (session == null || amount == null || amount < 0) { setState(() => _error = 'Masukkan jumlah uang fisik yang dihitung.'); return; }
    await _run(() async {
      await _repository.closeCashSession(sessionId: (session['id'] as num).toInt(), countedBalance: amount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final session = summary?['session'] as Map<String, Object?>?;
    final expenses = (summary?['expenses'] as List?)?.cast<Map<String, Object?>>() ?? const <Map<String, Object?>>[];
    final status = session?['status'];
    final expenseTiles = expenses.map<Widget>((item) => ListTile(
      title: Text(item['category'] as String),
      subtitle: Text(item['note'] as String? ?? ''),
      trailing: Text(_money(item['amount'])),
    )).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tutup kas harian'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tanggal: ${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
        if (summary == null || session == null) ...[
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Sesi kas hari ini belum dimulai. Masukkan uang tunai awal di laci sebelum transaksi berjalan.'))),
          TextField(controller: _opening, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Saldo awal / modal kas (Rp)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('Mulai sesi kas')),
        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(status == 'closed' ? 'Kas sudah ditutup' : 'Sesi kas sedang berjalan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _line('Saldo awal', _money(session['opening_balance'])),
            _line('Penerimaan tunai', _money(summary['cash_received'])),
            _line('Pengeluaran tunai', _money(summary['expense_total'])),
            const Divider(),
            _line('Saldo seharusnya', _money(status == 'closed' ? session['expected_balance'] : summary['expected_balance']), bold: true),
            if (status == 'closed') ...[
              _line('Uang fisik dihitung', _money(session['counted_balance'])),
              _line('Selisih kas', _money(session['difference']), bold: true),
              if ((session['note'] as String? ?? '').isNotEmpty) Text('Catatan: ${session['note']}'),
            ],
          ]))),
          const Text('Pengeluaran tunai', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Card(child: Column(children: expenses.isEmpty
              ? <Widget>[const ListTile(title: Text('Belum ada pengeluaran.'))]
              : expenseTiles)),
          if (status == 'open') ...[
            const SizedBox(height: 12),
            TextField(controller: _expenseAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal pengeluaran (Rp)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _expenseCategory, decoration: const InputDecoration(labelText: 'Kategori (contoh: makan, transport, operasional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _expenseNote, decoration: const InputDecoration(labelText: 'Keterangan (opsional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _addExpense, icon: const Icon(Icons.add), label: const Text('Catat pengeluaran')),
            const Divider(height: 28),
            TextField(controller: _counted, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Uang fisik hasil hitung (Rp)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _close, icon: const Icon(Icons.lock), label: const Text('Tutup kas hari ini')),
          ],
        ],
        if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 12),
        const Text('Saldo seharusnya = saldo awal + seluruh pembayaran tunai hari ini − pengeluaran tunai yang dicatat. Transfer dan QRIS tidak masuk saldo laci.'),
      ]),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))]),
  );
}
