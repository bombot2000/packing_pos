import 'package:flutter/material.dart';
import '../../data/repositories/packing_transaction_repository.dart';

class PackingCalculatorScreen extends StatefulWidget {
  const PackingCalculatorScreen({super.key});
  @override
  State<PackingCalculatorScreen> createState() => _PackingCalculatorScreenState();
}

class _PackingCalculatorScreenState extends State<PackingCalculatorScreen> {
  final _customer = TextEditingController();
  final _item = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _charge = TextEditingController();
  final _note = TextEditingController();
  final _repo = PackingTransactionRepository();
  List<Map<String, Object?>> _services = [];
  int? _serviceId;
  bool _loadingServices = true, _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadServices(); }
  @override
  void dispose() {
    _customer.dispose(); _item.dispose(); _length.dispose(); _width.dispose(); _height.dispose(); _charge.dispose(); _note.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final rows = await _repo.listServiceTypes();
      if (!mounted) return;
      setState(() {
        _services = rows;
        _loadingServices = false;
        if (_services.isNotEmpty) {
          _serviceId = _services.first['id'] as int;
          _charge.text = (_services.first['default_price'] as num).toInt().toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() { _loadingServices = false; _error = 'Master pekerjaan gagal dimuat: $e'; });
    }
  }

  void _selectService(int? id) {
    final selected = _serviceById(id);
    setState(() {
      _serviceId = id;
      if (selected != null) _charge.text = (selected['default_price'] as num).toInt().toString();
    });
  }

  Map<String, Object?>? _serviceById(int? id) {\n    for (final row in _services) { if (row['id'] == id) return row; }\n    return null;\n  }\n\n  double? _dimension(TextEditingController c) {
    final n = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return n != null && n.isFinite && n > 0 ? n : null;
  }
  int? _price() {
    final n = int.tryParse(_charge.text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '').trim());
    return n != null && n >= 0 ? n : null;
  }
  String _money(int n) => 'Rp ' + n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.');

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final service = _serviceById(_serviceId);
    final l = _dimension(_length), w = _dimension(_width), h = _dimension(_height), amount = _price();
    String? error;
    if (service == null) error = 'Tambahkan jenis pekerjaan terlebih dahulu pada Master Jenis Pekerjaan.';
    else if (l == null || w == null || h == null) error = 'Panjang, lebar, dan tinggi harus diisi dengan angka lebih dari nol.';
    else if (amount == null) error = 'Ongkos harus berupa nominal Rupiah yang valid.';
    if (error != null) { setState(() => _error = error); return; }

    setState(() { _saving = true; _error = null; });
    try {
      final job = service!['name'].toString();
      final description = _item.text.trim().isEmpty ? job : '$job • ${_item.text.trim()}';
      final receipt = await _repo.save(PackingTransactionDraft(
        customerName: _customer.text.trim(), itemDescription: description,
        lengthCm: l!, widthCm: w!, heightCm: h!,
        calculationSnapshot: {
          'mode': 'manual_service_charge', 'jobTypeId': _serviceId,
          'jobType': job, 'defaultPriceSnapshot': (service['default_price'] as num).toInt(),
          'manualPriceOverride': amount != (service['default_price'] as num).toInt(),
          'dimensionsAreReferenceOnly': true, 'priceSource': 'manual',
          'manualServiceCharge': amount,
        },
        materialCost: 0, laborCost: 0, overheadCost: 0, sellingPrice: amount!,
        note: _note.text.trim(), materials: const [],
      ));
      if (!mounted) return;
      setState(() { _customer.clear(); _item.clear(); _length.clear(); _width.clear(); _height.clear(); _note.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Transaksi tersimpan • $receipt • ${_money(amount)}'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan transaksi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {String? hint, String? suffix, TextInputType? type}) =>
    TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaksi packing')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Pilih jenis pekerjaan. Harga standar akan terisi otomatis dan boleh diubah untuk transaksi ini. Ukuran hanya sebagai informasi; tidak memengaruhi ongkos.'),
      const SizedBox(height: 16),
      if (_loadingServices) const LinearProgressIndicator()
      else if (_services.isEmpty) Card(child: ListTile(
        title: const Text('Belum ada jenis pekerjaan'),
        subtitle: const Text('Buat jenis pekerjaan dan harga standar terlebih dahulu.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServiceTypeMasterScreen())); await _loadServices(); },
      ))
      else DropdownButtonFormField<int>(
        value: _serviceId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Jenis pekerjaan', border: OutlineInputBorder()),
        items: _services.map((e) => DropdownMenuItem<int>(
          value: e['id'] as int,
          child: Text('${e['name']} • ${_money((e['default_price'] as num).toInt())}', overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: _selectService,
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServiceTypeMasterScreen()));
          await _loadServices();
        },
        icon: const Icon(Icons.settings), label: const Text('Kelola jenis pekerjaan dan harga'),
      ),
      const SizedBox(height: 12),
      _field('Nama pelanggan', _customer, hint: 'Opsional'),
      const SizedBox(height: 12),
      _field('Nama / deskripsi barang', _item, hint: 'Contoh: Mesin, lemari, elektronik'),
      const SizedBox(height: 20),
      Text('Ukuran barang (informasi saja)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Ukuran tidak dipakai untuk menghitung ongkos.'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _field('Panjang', _length, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        Expanded(child: _field('Lebar', _width, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        Expanded(child: _field('Tinggi', _height, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
      ]),
      const SizedBox(height: 20),
      Text('Harga custom transaksi', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      _field('Ongkos / harga jasa', _charge, hint: 'Harga standar dapat diubah', suffix: 'Rupiah', type: TextInputType.number),
      const SizedBox(height: 12),
      _field('Catatan transaksi', _note, hint: 'Opsional'),
      if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _saving || _loadingServices || _services.isEmpty ? null : _save,
        icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Menyimpan...' : 'Simpan transaksi'),
      ),
    ]),
  );
}
