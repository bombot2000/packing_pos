import 'package:flutter/material.dart';
import 'features/packing/packing_calculator_screen.dart';
import 'features/packing/packing_transaction_history_screen.dart';
import 'features/packing/material_master_screen.dart';
import 'features/packing/service_type_master_screen.dart';
import 'features/packing/packing_reports_screen.dart';
import 'features/packing/packing_backup_screen.dart';
import 'features/packing/printer_settings_screen.dart';
import 'features/packing/packing_identity_settings_screen.dart';
import 'data/repositories/packing_identity_repository.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const PackingPosApp()); }

class PackingPosApp extends StatelessWidget {
  const PackingPosApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Packing POS', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF5F7F6)),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _identityRepository = PackingIdentityRepository();
  String _businessName = 'Packing POS';

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final settings = await _identityRepository.getSettings();
    if (mounted) setState(() => _businessName = settings['business_name'] ?? 'Packing POS');
  }

  Future<void> _openIdentitySettings() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const PackingIdentitySettingsScreen(),
    ));
    if (changed == true) await _loadIdentity();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_businessName)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_businessName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Catat jenis pekerjaan, ukuran barang, dan ongkos jasa secara manual.'),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingCalculatorScreen())), icon: const Icon(Icons.add_box_outlined), label: const Text('Transaksi packing baru')),
      ]))),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.work_outline), title: const Text('Master jenis pekerjaan'), subtitle: const Text('Atur jenis jasa dan harga standar.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServiceTypeMasterScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Riwayat transaksi'), subtitle: const Text('Cari nota, pelanggan, jenis pekerjaan, dan pembayaran.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingTransactionHistoryScreen())))),
      const Card(child: ListTile(leading: Icon(Icons.wifi_off), title: Text('Mode offline'), subtitle: Text('Transaksi dan pembayaran disimpan di perangkat.'))),
      Card(child: ListTile(leading: const Icon(Icons.inventory_2), title: const Text('Master bahan (arsip)'), subtitle: const Text('Data bahan lama tetap dipertahankan.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaterialMasterScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.bar_chart), title: const Text('Laporan usaha'), subtitle: const Text('Penjualan, pembayaran, piutang, dan biaya.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingReportsScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.storefront_outlined), title: const Text('Identitas aplikasi dan nota'), subtitle: const Text('Ubah nama usaha, alamat, dan nomor telepon.'), trailing: const Icon(Icons.chevron_right), onTap: _openIdentitySettings)),
      Card(child: ListTile(leading: const Icon(Icons.print), title: const Text('Pengaturan printer'), subtitle: const Text('Printer Bluetooth 58 atau 80 mm.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())))),
      Card(child: ListTile(leading: const Icon(Icons.backup), title: const Text('Backup dan restore'), subtitle: const Text('Ekspor dan pulihkan data lokal.'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackingBackupScreen())))),
    ]),
  );
}
