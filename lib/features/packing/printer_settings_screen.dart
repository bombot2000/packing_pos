import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/packing_receipt_printer.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BluetoothInfo> _devices = [];
  String? _selectedMac;
  int _paperWidth = 58;
  bool _loading = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedMac = prefs.getString(PackingReceiptPrinter.printerMacKey);
      _paperWidth = prefs.getInt(PackingReceiptPrinter.paperWidthKey) ?? 58;
    });
    await _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    setState(() { _loading = true; _error = null; });
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 31) {
        await Permission.bluetoothConnect.request();
      }
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        throw StateError('Izin Bluetooth belum diberikan. Aktifkan izin Bluetooth untuk Packing POS di pengaturan Android.');
      }
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) throw StateError('Bluetooth HP belum aktif.');
      final devices = await PackingReceiptPrinter.pairedDevices();
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _connected = connected;
        if (_selectedMac != null && !devices.any((d) => d.macAdress == _selectedMac)) {
          _selectedMac = null;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePaper(int width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PackingReceiptPrinter.paperWidthKey, width);
    if (mounted) setState(() => _paperWidth = width);
  }

  Future<void> _connect() async {
    if (_selectedMac == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final connected = await PackingReceiptPrinter.connect(_selectedMac!);
      if (!connected) throw StateError('Koneksi printer gagal. Pastikan printer sudah dipasangkan melalui pengaturan Bluetooth HP.');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PackingReceiptPrinter.printerMacKey, _selectedMac!);
      if (mounted) {
        setState(() => _connected = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Printer berhasil terhubung dan disimpan.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await PackingReceiptPrinter.disconnect();
      if (mounted) setState(() => _connected = false);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _testPrint() async {
    try {
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected && _selectedMac != null) {
        final ok = await PackingReceiptPrinter.connect(_selectedMac!);
        if (!ok) throw StateError('Koneksi printer gagal.');
      }
      final bytes = <int>[];
      final profile = await CapabilityProfile.load();
      final generator = Generator(_paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58, profile);
      bytes.addAll(generator.reset());
      bytes.addAll(generator.text('PACKING POS', styles: const PosStyles(align: PosAlign.center, bold: true)));
      bytes.addAll(generator.text('TES CETAK', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.hr());
      bytes.addAll(generator.text('Kertas $_paperWidth mm'));
      bytes.addAll(generator.text('Bluetooth OK'));
      bytes.addAll(generator.feed(3));
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw StateError('Printer tidak menerima data tes.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tes cetak berhasil dikirim.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengaturan printer')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Printer Bluetooth thermal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Pasangkan printer terlebih dahulu melalui Pengaturan Bluetooth Android. Aplikasi menampilkan perangkat yang sudah dipasangkan.'),
      const SizedBox(height: 16),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 58, label: Text('58 mm')),
          ButtonSegment(value: 80, label: Text('80 mm')),
        ],
        selected: {_paperWidth},
        onSelectionChanged: (value) => _savePaper(value.first),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _loading ? null : _refreshDevices,
        icon: const Icon(Icons.refresh),
        label: const Text('Cari perangkat yang sudah dipasangkan'),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_devices.isNotEmpty)
        DropdownButtonFormField<String>(
          value: _selectedMac,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Pilih printer', border: OutlineInputBorder()),
          items: _devices.map((device) => DropdownMenuItem(
            value: device.macAdress,
            child: Text('${device.name} • ${device.macAdress}', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (value) => setState(() => _selectedMac = value),
        )
      else if (!_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Belum ada perangkat terpasang yang ditemukan.'),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _loading || _selectedMac == null ? null : _connect,
        icon: const Icon(Icons.bluetooth_connected),
        label: const Text('Hubungkan dan simpan printer'),
      ),
      OutlinedButton.icon(
        onPressed: _connected ? _disconnect : null,
        icon: const Icon(Icons.bluetooth_disabled),
        label: const Text('Putuskan koneksi'),
      ),
      OutlinedButton.icon(
        onPressed: _selectedMac == null || _loading ? null : _testPrint,
        icon: const Icon(Icons.print_outlined),
        label: const Text('Tes cetak'),
      ),
      if (_connected) const ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Printer terhubung')),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    ]),
  );
}
