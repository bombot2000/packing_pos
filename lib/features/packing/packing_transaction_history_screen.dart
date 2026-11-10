import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_transaction_detail_screen.dart';

class PackingTransactionHistoryScreen extends StatefulWidget {
  const PackingTransactionHistoryScreen({super.key});
  @override
  State<PackingTransactionHistoryScreen> createState() => _PackingTransactionHistoryScreenState();
}
class _PackingTransactionHistoryScreenState extends State<PackingTransactionHistoryScreen> {
  final _repo = PackingTransactionRepository();
  final _search = TextEditingController();
  late Future<List<Map<String, Object?>>> _future;
  @override
  void initState() { super.initState(); _future = _repo.listRecent(limit: 500); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  void _refresh() => setState(() => _future = _repo.listRecent(limit: 500));
  String _money(Object? v) {
    final n = (v as num?)?.toInt() ?? 0;
    return 'Rp ' + n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.');
  }
  String _job(Map<String, Object?> row) {
    try { return (jsonDecode(row['calculation_snapshot'] as String) as Map)['jobType']?.toString() ?? ''; } catch (_) { return ''; }
  }
  String _status(String? v) => v == 'completed' ? 'Lunas' : v == 'cancelled' ? 'Dibatalkan' : 'Belum lunas';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Riwayat transaksi'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('Gagal membaca transaksi: ${s.error}'));
        final all = s.data ?? [];
        final q = _search.text.trim().toLowerCase();
        final rows = all.where((r) => q.isEmpty || [r['receipt_no'], r['customer_name'], r['item_description'], _job(r)].join(' ').toLowerCase().contains(q)).toList();
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TextField(
            controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cari nomor nota, pelanggan, jenis pekerjaan...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.clear)),
              border: const OutlineInputBorder(),
            ),
          )),
          Expanded(child: rows.isEmpty
            ? Center(child: Text(all.isEmpty ? 'Belum ada transaksi tersimpan.' : 'Tidak ada transaksi yang cocok.'))
            : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.all(12), itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final row = rows[i]; final total = (row['selling_price'] as num).toInt(); final paid = (row['paid_amount'] as num).toInt();
                  return Card(child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                    title: Text(row['receipt_no'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_job(row).isNotEmpty) Text(_job(row), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if ((row['customer_name'] as String).isNotEmpty) Text(row['customer_name'] as String),
                      Text((row['item_description'] as String).isEmpty ? 'Barang tidak diberi nama' : row['item_description'] as String),
                      Text('${_status(row['status'] as String?)} • Dibayar ${_money(paid)} / ${_money(total)}'),
                    ]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PackingTransactionDetailScreen(transactionId: (row['id'] as num).toInt())));
                      if (mounted) _refresh();
                    },
                  ));
                },
              ),
            ),
          ),
        ]);
      },
    ),
  );
}
