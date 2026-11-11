import 'package:flutter/material.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_receipt_detail_screen.dart';
import 'service_type_master_screen.dart';

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
  final _quantity = TextEditingController(text: '1');
  final _discount = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _receiptNote = TextEditingController();
  final _repo = PackingTransactionRepository();
  final List<PackingTransactionDraft> _jobs = [];
  List<Map<String, Object?>> _services = [];
  int? _serviceId;
  bool _loadingServices = true, _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadServices(); }
  @override
  void dispose() {
    _customer.dispose(); _item.dispose(); _length.dispose(); _width.dispose();
    _height.dispose(); _charge.dispose(); _quantity.dispose(); _discount.dispose(); _note.dispose(); _receiptNote.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final rows = await _repo.listServiceTypes();
      if (!mounted) return;
      setState(() {
        _services = rows;
        _loadingServices = false;
        if (_services.isNotEmpty && _serviceId == null) {
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

  Map<String, Object?>? _serviceById(int? id) {
    for (final row in _services) { if (row['id'] == id) return row; }
    return null;
  }

  double? _dimension(TextEditingController c) {
    final n = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return n != null && n.isFinite && n > 0 ? n : null;
  }
  int? _price() {
    final n = int.tryParse(_charge.text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '').trim());
    return n != null && n >= 0 ? n : null;
  }
  String _money(int n) => 'Rp ${n.toString().replaceAllMapped(RegExp(r'(?<=\\d)(?=(\\d{3})+(?!\\d))'), (_) => '.')}';
  int get _grandTotal => _jobs.fold<int>(0, (sum, job) => sum + job.sellingPrice);

  void _addJob() {
    FocusScope.of(context).unfocus();
    final service = _serviceById(_serviceId);
    final l = _dimension(_length), w = _dimension(_width), h = _dimension(_height), amount = _price();
    final quantity = int.tryParse(_quantity.text.trim());
    String? error;
    if (service == null) {
      error = 'Tambahkan jenis pekerjaan terlebih dahulu.';
    } else if (l == null || w == null || h == null) {
      error = 'Panjang, lebar, dan tinggi harus diisi angka lebih dari nol.';
    } else if (quantity == null || quantity < 1) {
      error = 'Qty pekerjaan harus berupa bilangan bulat minimal 1.';
    } else if (amount == null) {
      error = 'Ongkos harus berupa nominal Rupiah yang valid.';
    }
    if (error != null) { setState(() => _error = error); return; }
    final job = service!['name'].toString();
    final description = _item.text.trim().isEmpty ? job : '$job • ${_item.text.trim()}';
    final draft = PackingTransactionDraft(
      customerName: _customer.text.trim(), itemDescription: description,
      quantity: quantity!,
      lengthCm: l!, widthCm: w!, heightCm: h!,
      calculationSnapshot: {
        'mode': 'manual_service_charge', 'jobTypeId': _serviceId,
        'jobType': job, 'defaultPriceSnapshot': (service['default_price'] as num).toInt(),
        'manualPriceOverride': amount != (service['default_price'] as num).toInt(),
        'dimensionsAreReferenceOnly': true, 'priceSource': 'manual',
        'manualServiceCharge': amount,
      },
      sellingPrice: amount!, note: _note.text.trim(), materials: const [],
    );
    setState(() {
      _jobs.add(draft);
      _error = null;
      _item.clear(); _length.clear(); _width.clear(); _height.clear(); _quantity.text = '1'; _note.clear();
    });
  }

  void _removeJob(int index) => setState(() => _jobs.removeAt(index));

  Future<void> _saveReceipt() async {
    if (_jobs.isEmpty) { setState(() => _error = 'Tambahkan minimal satu pekerjaan ke nota.'); return; }
    if (_discountAmount < 0 || _discountAmount > _grandSubtotal) {
      setState(() => _error = 'Diskon tidak boleh melebihi subtotal pekerjaan.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      final receipt = await _repo.saveReceipt(
        List<PackingTransactionDraft>.unmodifiable(_jobs),
        customerName: _customer.text.trim(),
        note: _receiptNote.text.trim(),
        discountAmount: _discountAmount,
      );
      if (!mounted) return;
      final total = _grandTotal;
      final count = _jobs.length;
      final saved = await _repo.findReceiptByNo(receipt);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nota tersimpan • $receipt • ${_money(total)} • $count pekerjaan'),
        duration: const Duration(seconds: 4),
      ));
      if (saved != null) {
        // Continue straight to payment/print; back returns to the home page.
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PackingReceiptDetailScreen(receiptId: (saved['id'] as num).toInt()),
        ));
        return;
      }
      setState(() {
        _jobs.clear(); _customer.clear(); _receiptNote.clear();
        _item.clear(); _length.clear(); _width.clear(); _height.clear(); _note.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan nota: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {String? hint, String? suffix, TextInputType? type}) =>
    TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Buat nota packing')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Satu nota dapat berisi banyak pekerjaan. Tambahkan pekerjaan satu per satu, lalu simpan dan lakukan pembayaran untuk total seluruh nota.'),
      const SizedBox(height: 16),
      _field('Nama pelanggan', _customer, hint: 'Nama pelanggan untuk seluruh nota'),
      const SizedBox(height: 12),
      if (_loadingServices) const LinearProgressIndicator()
      else if (_services.isEmpty) Card(child: ListTile(
        title: const Text('Belum ada jenis pekerjaan'),
        subtitle: const Text('Buat jenis pekerjaan dan harga standar terlebih dahulu.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServiceTypeMasterScreen())); await _loadServices(); },
      ))
      else DropdownButtonFormField<int>(
        initialValue: _serviceId, isExpanded: true,
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
      const Divider(height: 28),
      Text('Pekerjaan berikutnya', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      _field('Nama / deskripsi barang', _item, hint: 'Contoh: Mesin, lemari, elektronik'),
      const SizedBox(height: 16),
      Text('Ukuran barang (informasi saja)', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field('Panjang', _length, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        Expanded(child: _field('Lebar', _width, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        Expanded(child: _field('Tinggi', _height, suffix: 'cm', type: const TextInputType.numberWithOptions(decimal: true))),
      ]),
      const SizedBox(height: 16),
      _field('Qty / jumlah koli', _quantity, hint: 'Contoh: 3', suffix: 'koli', type: TextInputType.number),
      const SizedBox(height: 12),
      _field('Harga per koli / pekerjaan', _charge, hint: 'Harga standar dapat diubah', suffix: 'Rupiah', type: TextInputType.number),
      const SizedBox(height: 12),
      _field('Catatan pekerjaan', _note, hint: 'Opsional'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _loadingServices || _services.isEmpty ? null : _addJob,
        icon: const Icon(Icons.add), label: const Text('Tambah pekerjaan ke nota'),
      ),
      if (_jobs.isNotEmpty) ...[
        const Divider(height: 28),
        Text('Daftar pekerjaan • ${_jobs.length}', style: Theme.of(context).textTheme.titleMedium),
        ...List.generate(_jobs.length, (i) {
          final job = _jobs[i];
          return Card(child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(job.itemDescription),
            subtitle: Text('Qty ${job.quantity} • ${job.lengthCm} × ${job.widthCm} × ${job.heightCm} cm • ${_money(job.sellingPrice)} / koli'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_money(job.sellingPrice * job.quantity), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(tooltip: 'Hapus pekerjaan', onPressed: () => _removeJob(i), icon: const Icon(Icons.delete_outline)),
            ]),
          ));
        }),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            ListTile(
              dense: true,
              title: const Text('Subtotal pekerjaan'),
              trailing: Text(_money(_grandSubtotal)),
            ),
            TextField(
              controller: _discount,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Diskon nota (Rupiah)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              title: const Text('TOTAL NOTA', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(_money(_grandTotal), style: Theme.of(context).textTheme.titleLarge),
            ),
          ]),
        )),
        const SizedBox(height: 8),
        _field('Catatan nota', _receiptNote, hint: 'Opsional, berlaku untuk seluruh nota'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveReceipt,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.receipt_long),
          label: Text(_saving ? 'Menyimpan nota...' : 'Simpan nota (${_jobs.length} pekerjaan)'),
        ),
      ],
      if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
    ]),
  );
}
