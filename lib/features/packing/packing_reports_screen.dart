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
  String _period = 'all';

  Future<Map<String, Object?>> _loadReport() {
    final now = DateTime.now();
    if (_period == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      return _repository.reportSummary(startDate: start, endDate: start.add(const Duration(days: 1)));
    }
    if (_period == 'month') {
      final start = DateTime(now.year, now.month);
      final end = DateTime(now.year, now.month + 1);
      return _repository.reportSummary(startDate: start, endDate: end);
    }
    return _repository.reportSummary();
  }

  @override
  void initState() {
    super.initState();
    _report = _loadReport();
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    return 'Rp ${amount.toString().replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => '.',
    )}';
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
          onPressed: () => setState(() => _report = _loadReport()),
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
        final paymentMethods = ((data['payment_methods'] as List?) ?? const [])
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList();
        final hasCosts = ['material_cost_total', 'labor_cost_total', 'overhead_cost_total']
            .any((k) => ((totals[k] as num?) ?? 0) > 0);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Periode laporan', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Semua waktu')),
                DropdownMenuItem(value: 'today', child: Text('Hari ini')),
                DropdownMenuItem(value: 'month', child: Text('Bulan ini')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                  _period = value;
                  _report = _loadReport();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              _period == 'today' ? 'Ringkasan hari ini' : _period == 'month' ? 'Ringkasan bulan ini' : 'Ringkasan seluruh nota aktif',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                if (hasCosts && ((totals['gross_profit'] as num?) ?? 0) != 0)
                  _metric('Laba kotor', _money(totals['gross_profit']), Icons.trending_up),
                if (((totals['material_cost_total'] as num?) ?? 0) > 0)
                  _metric('Biaya bahan', _money(totals['material_cost_total']), Icons.inventory_2_outlined),
                if (((totals['labor_cost_total'] as num?) ?? 0) > 0)
                  _metric('Biaya jasa', _money(totals['labor_cost_total']), Icons.handyman_outlined),
                if (((totals['overhead_cost_total'] as num?) ?? 0) > 0)
                  _metric('Biaya tambahan', _money(totals['overhead_cost_total']), Icons.more_horiz),
                _metric('Pembayaran bersih', _money(totals['paid_total']), Icons.payments_outlined),
                if (((totals['refund_total'] as num?) ?? 0) > 0)
                  _metric('Total refund', _money(totals['refund_total']), Icons.undo),
                _metric('Arus kas tunai bersih', _money(totals['cash_received_total']), Icons.point_of_sale),
                _metric('Arus non-tunai bersih', _money(totals['non_cash_received_total']), Icons.account_balance_outlined),
                _metric('Piutang tersisa', _money(totals['receivable_total']), Icons.account_balance_wallet_outlined),
                _metric('Nota aktif', (totals['receipt_count'] as num? ?? 0).toString(), Icons.receipt_long),
                _metric('Jumlah pekerjaan', (totals['transaction_count'] as num? ?? 0).toString(), Icons.inventory_2_outlined),
              ],
            ),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              ListTile(
                title: const Text('Nota lunas'),
                trailing: Text((totals['completed_count'] as num? ?? 0).toString()),
              ),
              ListTile(
                title: const Text('Nota belum lunas'),
                trailing: Text((totals['open_count'] as num? ?? 0).toString()),
              ),
              ListTile(
                title: const Text('Dibatalkan (tidak dihitung sebagai penjualan)'),
                trailing: Text((totals['cancelled_count'] as num? ?? 0).toString()),
              ),
            ])),
            const SizedBox(height: 16),
            const Text(
              'Penerimaan per metode pembayaran',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(child: Column(children: paymentMethods.isEmpty
                ? [const ListTile(title: Text('Belum ada pembayaran pada periode ini.'))]
                : paymentMethods.map((item) {
                    final method = item['payment_method']?.toString() ?? '';
                    final label = switch (method) {
                      'cash' => 'Tunai',
                      'transfer' => 'Transfer',
                      'qris' => 'QRIS',
                      'other' => 'Lainnya',
                      _ => method.isEmpty ? 'Tidak diketahui' : method,
                    };
                    final count = (item['payment_count'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      title: Text(label),
                      subtitle: Text('$count transaksi pembayaran'),
                      trailing: Text(_money(item['amount'])),
                    );
                  }).toList())),
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
                      '${_quantity(item['quantity'])} ${item['unit']?.toString() ?? ''}',
                    ),
                    trailing: Text(_money(item['cost'])),
                  )).toList())),
            const SizedBox(height: 16),
            const Text(
              'Catatan: transaksi yang dibatalkan tidak masuk total penjualan dan pemakaian bahan. Periode menggunakan tanggal transaksi lokal perangkat.',
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
