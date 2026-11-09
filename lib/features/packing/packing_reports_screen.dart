import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';

class PackingReportsScreen extends StatefulWidget {
  const PackingReportsScreen({super.key});

  @override
  State<PackingReportsScreen> createState() => _PackingReportsScreenState();
}

class _PackingReportsScreenState extends State<PackingReportsScreen> {
  final _repository = PackingTransactionRepository();
  late Future<Map<String, Object?>> _report;

  @override
  void initState() {
    super.initState();
    _report = _repository.reportSummary();
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return 'Rp ' + amount.toString().replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
  }

  String _quantity(Object? value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(3);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Laporan usaha'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          onPressed: () => setState(() => _report = _repository.reportSummary()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, Object?>>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Laporan gagal dimuat: ${snapshot.error}'),
          ));
        }
        final data = snapshot.data!;
        final totals = Map<String, Object?>.from(data['totals'] as Map);
        final materials = (data['materials'] as List)
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Ringkasan seluruh transaksi aktif',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.65,
              children: [
                _metric('Penjualan', _money(totals['sales_total']), Icons.point_of_sale),
                _metric('Pembayaran diterima', _money(totals['paid_total']), Icons.payments_outlined),
                _metric('Piutang tersisa', _money(totals['receivable_total']), Icons.account_balance_wallet_outlined),
                _metric('Transaksi aktif', (totals['transaction_count'] as num? ?? 0).toString(), Icons.receipt_long),
              ],
            ),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              ListTile(
                title: const Text('Lunas'),
                trailing: Text((totals['completed_count'] as num? ?? 0).toString()),
              ),
              ListTile(
                title: const Text('Belum lunas'),
                trailing: Text((totals['open_count'] as num? ?? 0).toString()),
              ),
              ListTile(
                title: const Text('Dibatalkan (tidak dihitung sebagai penjualan)'),
                trailing: Text((totals['cancelled_count'] as num? ?? 0).toString()),
              ),
            ])),
            const SizedBox(height: 16),
            const Text(
              'Pemakaian bahan aktual',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(child: Column(children: materials.isEmpty
                ? [const ListTile(title: Text('Belum ada pemakaian bahan.'))]
                : materials.map((item) => ListTile(
                    title: Text(item['name']?.toString() ?? '-'),
                    subtitle: Text(
                      _quantity(item['quantity']) + ' ' + (item['unit']?.toString() ?? ''),
                    ),
                    trailing: Text(_money(item['cost'])),
                  )).toList())),
            const SizedBox(height: 16),
            const Text(
              'Catatan: laporan ini merupakan ringkasan semua transaksi aktif sejak aplikasi digunakan. Transaksi yang dibatalkan tidak masuk total penjualan dan pemakaian bahan.',
            ),
          ],
        );
      },
    ),
  );

  Widget _metric(String label, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
