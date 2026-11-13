import 'package:flutter/material.dart';

import '../../core/format/rupiah.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_receipt_detail_screen.dart';

class PackingReceivablesScreen extends StatefulWidget {
  const PackingReceivablesScreen({super.key});

  @override
  State<PackingReceivablesScreen> createState() => _PackingReceivablesScreenState();
}

class _PackingReceivablesScreenState extends State<PackingReceivablesScreen> {
  final _repository = PackingTransactionRepository();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listReceivables();
  }

  String _money(Object? value) => formatRupiah(value);

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (parsed == null) return '-';
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Daftar piutang'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: () => setState(() {
                _future = _repository.listReceivables();
              }),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Gagal membaca piutang: ${snapshot.error}'));
            }
            final rows = snapshot.data ?? [];
            final total = rows.fold<int>(
              0,
              (sum, row) => sum + (row['remaining_amount'] as num).toInt(),
            );
            return Column(
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    title: const Text('Total piutang belum tertagih'),
                    subtitle: Text('${rows.length} nota • Urut dari nota paling lama'),
                    trailing: Text(
                      _money(total),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(child: Text('Tidak ada piutang yang belum lunas.'))
                      : RefreshIndicator(
                          onRefresh: () async {
                            setState(() {
                              _future = _repository.listReceivables();
                            });
                            await _future;
                          },
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final remaining =
                                  (row['remaining_amount'] as num).toInt();
                              final customerOutstanding =
                                  (row['customer_outstanding'] as num).toInt();
                              final customer =
                                  (row['customer_name'] as String?)?.trim() ?? '';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(child: Text('${index + 1}')),
                                  title: Text(
                                    customer.isEmpty ? 'Pelanggan umum' : customer,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row['receipt_no'] as String),
                                      Text('Tanggal nota: ${_date(row['created_at'])}'),
                                      Text('Total nota: ${_money(row['total_amount'])}'),
                                      Text('Sudah dibayar: ${_money(row['paid_amount'])}'),
                                      Text(
                                        'Total piutang pelanggan: ${_money(customerOutstanding)}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Sisa'),
                                      Text(
                                        _money(remaining),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PackingReceiptDetailScreen(
                                        receiptId: (row['id'] as num).toInt(),
                                      ),
                                    ),
                                  ).then((_) {
                                    if (mounted) {
                                      setState(() {
                                        _future = _repository.listReceivables();
                                      });
                                    }
                                  }),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      );
}
