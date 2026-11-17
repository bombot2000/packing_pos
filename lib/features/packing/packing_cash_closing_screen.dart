import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/format/money_input.dart';
import '../../core/format/friendly_error.dart';

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
  List<Map<String, Object?>> _history = const [];
  List<Map<String, Object?>> _auditEvents = const [];
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
      final history = await _repository.listCashSessions(limit: 30);
      final events = session == null ? const <Map<String, Object?>>[] : await _repository.cashSessionEvents((session['id'] as num).toInt());
      if (mounted) {
        setState(() {
          _summary = summary;
          _history = history;
          _auditEvents = events;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
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
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final amount = parseRupiah(_opening.text);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Masukkan saldo awal berupa angka nol atau lebih.');
      return;
    }
    await _run(() async { await _repository.startCashSession(date: DateTime.now(), openingBalance: amount); });
  }

  Future<void> _addExpense() async {
    final session = _summary?['session'] as Map<String, Object?>?;
    final amount = parseRupiah(_expenseAmount.text);
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
    final amount = parseRupiah(_counted.text);
    if (session == null || amount == null || amount < 0) { setState(() => _error = 'Masukkan jumlah uang fisik yang dihitung.'); return; }
    await _run(() async {
      await _repository.closeCashSession(sessionId: (session['id'] as num).toInt(), countedBalance: amount);
    });
  }

  Future<void> _reopen() async {
    final session = _summary?['session'] as Map<String, Object?>?;
    if (session == null) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buka kembali sesi kas'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Alasan koreksi wajib diisi',
            hintText: 'Contoh: ada pembayaran tunai yang belum dicatat',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            if (controller.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, controller.text.trim());
          }, child: const Text('Buka kembali')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    await _run(() async {
      await _repository.reopenCashSession(
        sessionId: (session['id'] as num).toInt(), reason: reason,
      );
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
          TextField(controller: _opening, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Saldo awal / modal kas (Rp)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('Mulai sesi kas')),
        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(status == 'closed' ? 'Kas sudah ditutup' : 'Sesi kas sedang berjalan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _line('Saldo awal', _money(session['opening_balance'])),
            _line('Penerimaan tunai', _money(summary['cash_received'])),
            if (((summary['cash_refunded'] as num?) ?? 0) > 0)
              _line('Pengembalian dana tunai', _money(summary['cash_refunded'])),
            _line('Pengeluaran tunai', _money(summary['expense_total'])),
            const Divider(),
            _line('Saldo seharusnya', _money(status == 'closed' ? session['expected_balance'] : summary['expected_balance']), bold: true),
            if (status == 'closed') ...[
              _line('Uang fisik dihitung', _money(session['counted_balance'])),
              _line('Selisih kas', _money(session['difference']), bold: true),
              if ((session['note'] as String? ?? '').isNotEmpty) Text('Catatan: ${session['note']}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reopen,
                icon: const Icon(Icons.lock_open),
                label: const Text('Buka kembali untuk koreksi'),
              ),
            ],
          ]))),
          const Text('Pengeluaran tunai', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Card(child: Column(children: expenses.isEmpty
              ? <Widget>[const ListTile(title: Text('Belum ada pengeluaran.'))]
              : expenseTiles)),
          if (status == 'open') ...[
            const SizedBox(height: 12),
            TextField(controller: _expenseAmount, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Nominal pengeluaran (Rp)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _expenseCategory, decoration: const InputDecoration(labelText: 'Kategori (contoh: makan, transport, operasional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _expenseNote, decoration: const InputDecoration(labelText: 'Keterangan (opsional)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _addExpense, icon: const Icon(Icons.add), label: const Text('Catat pengeluaran')),
            const Divider(height: 28),
            TextField(controller: _counted, keyboardType: TextInputType.number, inputFormatters: [RupiahInputFormatter()], decoration: const InputDecoration(labelText: 'Uang fisik hasil hitung (Rp)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _close, icon: const Icon(Icons.lock), label: const Text('Tutup kas hari ini')),
          ],
        ],
        if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 12),
        if (_auditEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Audit sesi kas hari ini', style: Theme.of(context).textTheme.titleMedium),
          ..._auditEvents.map((event) {
            final closed = event['event_type'] == 'closed';
            Map<String, dynamic> snapshot = {};
            try { snapshot = Map<String, dynamic>.from(jsonDecode(event['snapshot_json'] as String) as Map); } catch (_) {}
            final when = DateTime.tryParse(event['created_at'] as String? ?? '')?.toLocal();
            final timeLabel = when == null ? '' : '${when.day.toString().padLeft(2, '0')}-${when.month.toString().padLeft(2, '0')}-${when.year} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
            return Card(child: ListTile(
              leading: Icon(closed ? Icons.lock : Icons.lock_open),
              title: Text(closed ? 'Penutupan kas' : 'Pembukaan kembali kas'),
              subtitle: Text([
                timeLabel,
                if ((event['reason'] as String? ?? '').isNotEmpty) 'Alasan/catatan: ${event['reason']}',
                if (closed) 'Saldo seharusnya: ${_money(snapshot['expected_balance'])} • Fisik: ${_money(snapshot['counted_balance'])} • Selisih: ${_money(snapshot['difference'])}',
                if (!closed) 'Saldo penutupan sebelumnya: ${_money(snapshot['expected_balance'])} • Fisik: ${_money(snapshot['counted_balance'])} • Selisih: ${_money(snapshot['difference'])}',
              ].join('\\n')),
            ));
          }),
        ],
        const Divider(height: 28),
        Text('Riwayat tutup kas', style: Theme.of(context).textTheme.titleMedium),
        if (_history.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Belum ada riwayat sesi kas.'),
          )
        else
          ..._history.map((item) {
            final dateKey = item['date_key'] as String;
            final dateParts = dateKey.split('-');
            final dateLabel = dateParts.length == 3
                ? '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}'
                : dateKey;
            final closed = item['status'] == 'closed';
            return Card(
              child: ListTile(
                leading: Icon(closed ? Icons.lock : Icons.lock_open),
                title: Text(dateLabel),
                subtitle: Text(closed
                    ? 'Saldo fisik: ${_money(item['counted_balance'])} • Selisih: ${_money(item['difference'])}'
                    : 'Sesi masih terbuka'),
                trailing: Text(
                  _money(closed ? item['expected_balance'] : item['opening_balance']),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        const Text('Saldo seharusnya = saldo awal + seluruh pembayaran tunai hari ini − pengeluaran tunai yang dicatat. Transfer dan QRIS tidak masuk saldo laci.'),
      ]),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))), Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))]),
  );
}
