import 'package:flutter/material.dart';
import '../../core/format/rupiah.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_receipt_detail_screen.dart';

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
  void initState() { super.initState(); _future = _repo.listReceipts(limit: 500); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  void _refresh() => setState(() => _future = _repo.listReceipts(limit: 500));
  String _money(Object? v) => formatRupiah(v);
  String _status(Map<String, Object?> row) => row['status'] == 'completed'
      ? 'Lunas'
      : row['status'] == 'cancelled'
          ? 'Dibatalkan'
          : ((row['paid_amount'] as num?)?.toInt() ?? 0) > 0
              ? 'Dibayar sebagian'
              : 'Belum dibayar';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Riwayat nota'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('Gagal membaca nota: ${s.error}'));
        final all = s.data ?? [];
        final q = _search.text.trim().toLowerCase();
        final rows = all.where((r) => q.isEmpty || [r['receipt_no'], r['customer_name']].join(' ').toLowerCase().contains(q)).toList();
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TextField(
            controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cari nomor nota atau pelanggan...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.clear)),
              border: const OutlineInputBorder(),
            ),
          )),
          Expanded(child: rows.isEmpty
            ? Center(child: Text(all.isEmpty ? 'Belum ada nota tersimpan.' : 'Tidak ada nota yang cocok.'))
            : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.all(12), itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final total = (row['total_amount'] as num).toInt();
                  final paid = (row['paid_amount'] as num).toInt();
                  return Card(child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                    title: Text(row['receipt_no'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((row['customer_name'] as String).isNotEmpty) Text(row['customer_name'] as String),
                      Text('${_status(row)} • Total ${_money(total)}'),
                      Text('Pembayaran ${_money(paid)}'),
                      Text((row['created_at'] as String).replaceFirst('T', ' ')),
                    ]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PackingReceiptDetailScreen(receiptId: (row['id'] as num).toInt())));
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
