import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_receipt_detail_screen.dart';
import 'service_type_master_screen.dart';
import 'packing_customer_master_screen.dart';

class PackingCalculatorScreen extends StatefulWidget {
  const PackingCalculatorScreen({super.key, this.editReceiptId});
  final int? editReceiptId;
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
  List<Map<String, Object?>> _customers = [];
  int? _serviceId;
  bool _loadingServices = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServices();
    _loadCustomers();
    if (widget.editReceiptId != null) _loadReceiptForEdit();
  }

  Future<void> _loadReceiptForEdit() async {
    try {
      final id = widget.editReceiptId!;
      final receipt = await _repo.findReceiptById(id);
      if (receipt == null) throw StateError('Nota tidak ditemukan.');
      if (receipt['status'] != 'open' || (receipt['paid_amount'] as num).toInt() != 0) {
        throw StateError('Hanya nota yang belum dibayar yang dapat diedit.');
      }
      final payments = await _repo.receiptPaymentsFor(id);
      if (payments.isNotEmpty) throw StateError('Nota sudah memiliki pembayaran.');
      final rows = await _repo.jobsForReceipt(id);
      final drafts = <PackingTransactionDraft>[];
      for (final row in rows) {
        final rawSnapshot = row['calculation_snapshot'];
        final snapshot = rawSnapshot is String
            ? Map<String, Object?>.from(jsonDecode(rawSnapshot) as Map)
            : <String, Object?>{};
        final materialRows = await _repo.materialsFor((row['id'] as num).toInt());
        final materials = materialRows.map((m) => MaterialUsageDraft(
          materialId: (m['material_id'] as num?)?.toInt(),
          name: m['material_name_snapshot'] as String,
          unit: m['unit_snapshot'] as String,
          calculatedQuantity: (m['calculated_quantity'] as num).toDouble(),
          actualQuantity: (m['actual_quantity'] as num).toDouble(),
          unitPrice: (m['unit_price_snapshot'] as num).toInt(),
          adjustmentNote: m['adjustment_note'] as String? ?? '',
        )).toList();
        drafts.add(PackingTransactionDraft(
          customerName: row['customer_name'] as String? ?? '',
          itemDescription: row['item_description'] as String? ?? '',
          quantity: (row['quantity'] as num?)?.toInt() ?? 1,
          lengthCm: (row['length_cm'] as num).toDouble(),
          widthCm: (row['width_cm'] as num).toDouble(),
          heightCm: (row['height_cm'] as num).toDouble(),
          calculationSnapshot: snapshot,
          materialCost: (row['material_cost'] as num?)?.toInt() ?? 0,
          laborCost: (row['labor_cost'] as num?)?.toInt() ?? 0,
          overheadCost: (row['overhead_cost'] as num?)?.toInt() ?? 0,
          sellingPrice: (row['unit_price'] as num?)?.toInt() ?? (row['selling_price'] as num).toInt(),
          note: row['note'] as String? ?? '',
          materials: materials,
        ));
      }
      if (!mounted) return;
      setState(() {
        _customer.text = receipt['customer_name'] as String? ?? '';
        _receiptNote.text = receipt['note'] as String? ?? '';
        _discount.text = ((receipt['discount_amount'] as num?)?.toInt() ?? 0).toString();
        _jobs
          ..clear()
          ..addAll(drafts);
        if (drafts.isNotEmpty) {
          final snapshotServiceId =
              (drafts.first.calculationSnapshot['jobTypeId'] as num?)?.toInt();
          // A service may have been deactivated since this receipt was created.
          // Keep the historical job snapshot, but never assign an unavailable
          // value to the active-service dropdown.
          _serviceId = _services.any((service) => service['id'] == snapshotServiceId)
              ? snapshotServiceId
              : (_loadingServices || _services.isEmpty
                  ? null
                  : _services.first['id'] as int);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Nota tidak dapat dimuat untuk diedit: $e');
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final rows = await _repo.listCustomers();
      if (mounted) setState(() => _customers = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'Master pelanggan gagal dimuat: $e');
    }
  }
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
        final selectedServiceExists = _services.any((service) => service['id'] == _serviceId);
        if (_services.isNotEmpty && !selectedServiceExists) {
          _serviceId = _services.first['id'] as int;
          _charge.text = (_services.first['default_price'] as num).toInt().toString();
        } else if (_serviceId != null && !selectedServiceExists) {
          _serviceId = null;
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
  String _money(int n) => 'Rp ${n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
  int get _grandSubtotal => _jobs.fold<int>(0, (sum, job) => sum + job.sellingPrice * job.quantity);
  int get _discountAmount => int.tryParse(_discount.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
  int get _grandTotal => _grandSubtotal - _discountAmount;

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
      if (widget.editReceiptId != null) {
        await _repo.updateUnpaidReceipt(
          widget.editReceiptId!,
          List<PackingTransactionDraft>.unmodifiable(_jobs),
          customerName: _customer.text.trim(),
          note: _receiptNote.text.trim(),
          discountAmount: _discountAmount,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nota berhasil diperbarui.')));
        Navigator.of(context).pop(true);
        return;
      }
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
    appBar: AppBar(title: Text(widget.editReceiptId == null ? 'Buat nota packing' : 'Edit nota packing')),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), children: [
      Text(widget.editReceiptId == null
        ? 'Satu nota dapat berisi banyak pekerjaan. Tambahkan pekerjaan satu per satu, lalu simpan dan lakukan pembayaran untuk total seluruh nota.'
        : 'Edit data nota yang belum dibayar. Hapus pekerjaan yang tidak diperlukan atau tambahkan pekerjaan baru, lalu simpan perubahan.'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Autocomplete<String>(
              initialValue: TextEditingValue(text: _customer.text),
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return _customers.map((row) => row['name'] as String);
                return _customers
                    .map((row) => row['name'] as String)
                    .where((name) => name.toLowerCase().contains(query));
              },
              onSelected: (value) => _customer.text = value,
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                if (controller.text != _customer.text && !focusNode.hasFocus) {
                  controller.text = _customer.text;
                }
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _customer.text = value,
                  decoration: const InputDecoration(
                    labelText: 'Nama pelanggan',
                    hintText: 'Pilih pelanggan atau ketik nama baru',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Kelola master pelanggan',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PackingCustomerMasterScreen(),
              ));
              await _loadCustomers();
            },
            icon: const Icon(Icons.contacts_outlined),
          ),
        ],
      ),
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
      ],
      if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
    ]),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Total nota', style: Theme.of(context).textTheme.labelMedium),
                        Text(
                          _money(_grandTotal < 0 ? 0 : _grandTotal),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Text('${_jobs.length} pekerjaan', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || _jobs.isEmpty ? null : _saveReceipt,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving
                      ? 'Menyimpan nota...'
                      : widget.editReceiptId == null
                          ? 'Simpan nota'
                          : 'Simpan perubahan nota'),
                ),
              ),
              if (_jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Tambahkan pekerjaan terlebih dahulu untuk menyimpan nota.'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
