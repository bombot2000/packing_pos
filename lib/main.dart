import 'package:flutter/material.dart';

import 'core/format/rupiah.dart';
import 'data/repositories/packing_identity_repository.dart';
import 'data/repositories/packing_transaction_repository.dart';
import 'features/packing/material_master_screen.dart';
import 'features/packing/packing_backup_screen.dart';
import 'features/packing/packing_calculator_screen.dart';
import 'features/packing/packing_cash_closing_screen.dart';
import 'features/packing/packing_customer_master_screen.dart';
import 'features/packing/packing_identity_settings_screen.dart';
import 'features/packing/packing_receivables_screen.dart';
import 'features/packing/packing_reports_screen.dart';
import 'features/packing/packing_transaction_history_screen.dart';
import 'features/packing/printer_settings_screen.dart';
import 'features/packing/service_type_master_screen.dart';

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
  final _repository = PackingTransactionRepository();
  String _businessName = 'Packing POS';
  int? _salesToday, _paidToday, _receivable;

  static const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  static const _months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _loadSummary();
  }

  Future<void> _loadIdentity() async {
    try {
      final settings = await _identityRepository.getSettings();
      if (mounted) setState(() => _businessName = settings['business_name'] ?? 'Packing POS');
    } catch (_) {}
  }

  Future<void> _loadSummary() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final today = await _repository.reportSummary(startDate: start, endDate: start.add(const Duration(days: 1)));
      final all = await _repository.reportSummary();
      final t = today['totals'] as Map;
      final a = all['totals'] as Map;
      if (!mounted) return;
      setState(() {
        _salesToday = (t['sales_total'] as num?)?.toInt() ?? 0;
        _paidToday = (t['paid_total'] as num?)?.toInt() ?? 0;
        _receivable = (a['receivable_total'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _loadSummary();
    _loadIdentity();
  }

  String _dateLabel() {
    final now = DateTime.now();
    return '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}';
  }

  Widget _stat(String label, int? value, IconData icon) => Expanded(
    child: Column(children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 4),
      FittedBox(child: Text(value == null ? '-' : formatRupiah(value), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );

  Widget _shortcut(IconData icon, String title, Widget page) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(page),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );

  Widget _setting(IconData icon, String title, String subtitle, Widget page) => ListTile(
    leading: Icon(icon), title: Text(title), subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right), onTap: () => _open(page),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_businessName)),
    body: RefreshIndicator(
      onRefresh: _loadSummary,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_dateLabel(), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _stat('Penjualan hari ini', _salesToday, Icons.point_of_sale),
              _stat('Uang masuk hari ini', _paidToday, Icons.payments_outlined),
              _stat('Piutang', _receivable, Icons.account_balance_wallet_outlined),
            ]),
            const SizedBox(height: 8),
            Text('Data tersimpan di perangkat dan dapat dipakai tanpa internet.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
        const SizedBox(height: 12),
        SizedBox(height: 64, child: FilledButton.icon(
          onPressed: () => _open(const PackingCalculatorScreen()),
          icon: const Icon(Icons.add_box_outlined, size: 28),
          label: const Text('Transaksi packing baru', style: TextStyle(fontSize: 18)),
        )),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5,
          children: [
            _shortcut(Icons.receipt_long, 'Riwayat transaksi', const PackingTransactionHistoryScreen()),
            _shortcut(Icons.account_balance_wallet_outlined, 'Daftar piutang', const PackingReceivablesScreen()),
            _shortcut(Icons.lock_clock, 'Tutup kas harian', const PackingCashClosingScreen()),
            _shortcut(Icons.bar_chart, 'Laporan usaha', const PackingReportsScreen()),
          ],
        ),
        const SizedBox(height: 12),
        Card(child: ExpansionTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Pengaturan & data'),
          subtitle: const Text('Master, printer, identitas usaha, backup'),
          children: [
            _setting(Icons.work_outline, 'Master jenis pekerjaan', 'Atur jenis jasa dan harga standar.', const ServiceTypeMasterScreen()),
            _setting(Icons.contacts_outlined, 'Master pelanggan', 'Daftar pelanggan langganan.', const PackingCustomerMasterScreen()),
            _setting(Icons.storefront_outlined, 'Identitas aplikasi dan nota', 'Nama usaha, alamat, dan nomor telepon.', const PackingIdentitySettingsScreen()),
            _setting(Icons.print, 'Pengaturan printer', 'Printer Bluetooth 58 atau 80 mm.', const PrinterSettingsScreen()),
            _setting(Icons.backup, 'Backup dan restore', 'Ekspor dan pulihkan data lokal.', const PackingBackupScreen()),
            _setting(Icons.inventory_2, 'Master bahan (arsip)', 'Data bahan lama tetap dipertahankan.', const MaterialMasterScreen()),
          ],
        )),
      ]),
    ),
  );
}
