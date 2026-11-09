import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_transaction_detail_screen.dart';

class PackingTransactionHistoryScreen extends StatefulWidget {
  const PackingTransactionHistoryScreen({super.key});

  @override
  State<PackingTransactionHistoryScreen> createState() => _PackingTransactionHistoryScreenState();
}

class _PackingTransactionHistoryScreenState extends State<PackingTransactionHistoryScreen> {
  final _repository = PackingTransactionRepository();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listRecent(limit: 500);
  }

  void _refresh() => setState(() => _future = _repository.listRecent(limit: 500));

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return 'Rp ${amount.toString().replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (m) => '.',
    )}';
  }

  String _status(String? value) {
    switch (value) {
      case 'completed': return 'Lunas';
      case 'cancelled': return 'Dibatalkan';
      default: return 'Belum lunas';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Riwayat transaksi'),
      actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Gagal membaca transaksi: ${snapshot.error}'),
          ));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(child: Text('Belum ada transaksi tersimpan.'));
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final row = rows[index];
              final total = (row['selling_price'] as num).toInt();
              final paid = (row['paid_amount'] as num).toInt();
              final receipt = row['receipt_no'] as String;
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                title: Text(receipt, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((row['customer_name'] as String).isNotEmpty)
                      Text(row['customer_name'] as String),
                    Text((row['item_description'] as String).isEmpty
                        ? 'Barang tidak diberi nama'
                        : row['item_description'] as String),
                    Text('${_status(row['status'] as String?)} • Dibayar ${_money(paid)} / ${_money(total)}'),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PackingTransactionDetailScreen(
                      transactionId: (row['id'] as num).toInt(),
                    ),
                  ));
                  if (mounted) _refresh();
                },
              ));
            },
          ),
        );
      },
    ),
  );
}
