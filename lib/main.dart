import 'package:flutter/material.dart';
void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const PackingPosApp()); }
class PackingPosApp extends StatelessWidget {
  const PackingPosApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Packing POS', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)), useMaterial3: true),
    home: const HomePage());
}
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Packing POS')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Layanan packing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('Hitung bahan dan biaya berdasarkan panjang, lebar, dan tinggi barang.'),
        const SizedBox(height: 16), FilledButton.icon(onPressed: null, icon: const Icon(Icons.add), label: const Text('Transaksi packing baru')),
      ]))),
      const SizedBox(height: 12),
      const Card(child: ListTile(leading: Icon(Icons.wifi_off), title: Text('Mode offline'), subtitle: Text('Data disimpan lokal di perangkat.'))),
      const ListTile(leading: Icon(Icons.receipt_long), title: Text('Transaksi'), subtitle: Text('Riwayat nota')),
      const ListTile(leading: Icon(Icons.inventory_2), title: Text('Bahan'), subtitle: Text('Master bahan dan harga')),
      const ListTile(leading: Icon(Icons.bar_chart), title: Text('Laporan')),
      const ListTile(leading: Icon(Icons.backup), title: Text('Backup dan restore')),
    ]));
}
