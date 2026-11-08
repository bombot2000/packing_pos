import 'package:flutter/material.dart';

import 'features/packing/packing_calculator_screen.dart';
import 'features/packing/packing_transaction_history_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PackingPosApp());
}

class PackingPosApp extends StatelessWidget {
  const PackingPosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Packing POS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F7F6),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Packing POS')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Layanan packing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Hitung kebutuhan bahan dan biaya berdasarkan panjang, lebar, dan tinggi barang.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingCalculatorScreen())),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Transaksi packing baru'),
          ),
        ]),
      )),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: const Text('Riwayat transaksi'),
        subtitle: const Text('Buka nota, periksa bahan, dan catat pembayaran.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingTransactionHistoryScreen())),
      )),
      const Card(child: ListTile(
        leading: Icon(Icons.wifi_off),
        title: Text('Mode offline'),
        subtitle: Text('Transaksi dan pembayaran disimpan di perangkat.'),
      )),
      const ListTile(leading: Icon(Icons.inventory_2), title: Text('Bahan'), subtitle: Text('Master bahan dan harga — tahap berikutnya')),
      const ListTile(leading: Icon(Icons.bar_chart), title: Text('Laporan — tahap berikutnya')),
      const ListTile(leading: Icon(Icons.backup), title: Text('Backup dan restore — tahap berikutnya')),
    ]),
  );
}
