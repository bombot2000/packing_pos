import 'package:flutter/material.dart';

import 'features/packing/packing_calculator_screen.dart';
import 'features/packing/packing_transaction_history_screen.dart';
import 'features/packing/material_master_screen.dart';
import 'features/packing/packing_reports_screen.dart';
import 'features/packing/packing_backup_screen.dart';
import 'features/packing/printer_settings_screen.dart';

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
      Card(child: ListTile(
        leading: const Icon(Icons.inventory_2),
        title: const Text('Master bahan'),
        subtitle: const Text('Kelola nama, satuan, dan harga bahan packing.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaterialMasterScreen())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.bar_chart),
        title: const Text('Laporan usaha'),
        subtitle: const Text('Ringkasan penjualan, pembayaran, piutang, dan pemakaian bahan.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingReportsScreen())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.print),
        title: const Text('Pengaturan printer'),
        subtitle: const Text('Pasangkan printer Bluetooth dan pilih kertas 58 atau 80 mm.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.backup),
        title: const Text('Backup dan restore'),
        subtitle: const Text('Ekspor dan pulihkan data lokal melalui file JSON.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingBackupScreen())),
      )),
    ]),
  );
}
