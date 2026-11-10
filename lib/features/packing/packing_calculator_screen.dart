import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';

/// Manual packing-service transaction screen.
///
/// Dimensions are recorded for reference only. They never affect the price.
/// The operator enters the job type and the agreed service charge manually.
class PackingCalculatorScreen extends StatefulWidget {
  const PackingCalculatorScreen({super.key});

  @override
  State<PackingCalculatorScreen> createState() =>
      _PackingCalculatorScreenState();
}

class _PackingCalculatorScreenState extends State<PackingCalculatorScreen> {
  final _customer = TextEditingController();
  final _jobType = TextEditingController(text: 'Packing Kayu');
  final _item = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _charge = TextEditingController();
  final _note = TextEditingController();

  final _repository = PackingTransactionRepository();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _customer.dispose();
    _jobType.dispose();
    _item.dispose();
    _length.dispose();
    _width.dispose();
    _height.dispose();
    _charge.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _dimension(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  int? _rupiahValue() {
    final raw = _charge.text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').replaceAll(' ', '').trim();
    final value = int.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  String _rupiah(int value) => 'Rp ' + value.toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );

  Future<void> _saveTransaction() async {
    FocusScope.of(context).unfocus();

    final jobType = _jobType.text.trim();
    final length = _dimension(_length);
    final width = _dimension(_width);
    final height = _dimension(_height);
    final charge = _rupiahValue();

    String? validationError;
    if (jobType.isEmpty) {
      validationError = 'Jenis pekerjaan wajib diisi.';
    } else if (length == null || width == null || height == null) {
      validationError = 'Panjang, lebar, dan tinggi harus diisi dengan angka lebih dari nol.';
    } else if (charge == null) {
      validationError = 'Ongkos harus diisi dengan nominal Rupiah yang valid.';
    }

    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final description = _item.text.trim().isEmpty
          ? jobType
          : '$jobType • ${_item.text.trim()}';

      final receipt = await _repository.save(
        PackingTransactionDraft(
          customerName: _customer.text.trim(),
          itemDescription: description,
          lengthCm: length!,
          widthCm: width!,
          heightCm: height!,
          calculationSnapshot: {
            'mode': 'manual_service_charge',
            'jobType': jobType,
            'dimensionsAreReferenceOnly': true,
            'priceSource': 'manual',
            'manualServiceCharge': charge,
          },
          materialCost: 0,
          laborCost: 0,
          overheadCost: 0,
          sellingPrice: charge!,
          note: _note.text.trim(),
          materials: const [],
        ),
      );

      if (!mounted) return;
      setState(() {
        _customer.clear();
        _jobType.text = 'Packing Kayu';
        _item.clear();
        _length.clear();
        _width.clear();
        _height.clear();
        _charge.clear();
        _note.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transaksi tersimpan. Nota: $receipt • Ongkos: ${_rupiah(charge)}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Gagal menyimpan transaksi: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Transaksi packing')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Jenis pekerjaan dan ongkos ditentukan sendiri. Ukuran barang hanya dicatat sebagai informasi dan tidak digunakan untuk menghitung harga.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            Text(
              'Data pekerjaan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _textField(
              'Jenis pekerjaan',
              _jobType,
              hint: 'Contoh: Packing Kayu, Packing Peti',
            ),
            const SizedBox(height: 12),
            _textField(
              'Nama pelanggan',
              _customer,
              hint: 'Opsional',
            ),
            const SizedBox(height: 12),
            _textField(
              'Nama / deskripsi barang',
              _item,
              hint: 'Contoh: Mesin, lemari, barang elektronik',
            ),
            const SizedBox(height: 20),
            Text(
              'Ukuran barang (informasi saja)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Ukuran tidak memengaruhi ongkos. Isi ukuran sesuai kondisi barang.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _textField(
                    'Panjang',
                    _length,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    suffix: 'cm',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _textField(
                    'Lebar',
                    _width,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    suffix: 'cm',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _textField(
                    'Tinggi',
                    _height,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    suffix: 'cm',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Ongkos pekerjaan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _textField(
              'Ongkos / harga jasa',
              _charge,
              hint: 'Isi harga sesuai kesepakatan',
              keyboardType: TextInputType.number,
              suffix: 'Rupiah',
            ),
            const SizedBox(height: 12),
            _textField(
              'Catatan transaksi',
              _note,
              hint: 'Opsional',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _saveTransaction,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan transaksi'),
            ),
          ],
        ),
      );
}
