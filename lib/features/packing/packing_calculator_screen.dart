import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/calculation/packing_faces.dart';
import '../../core/calculation/pricing_calculator.dart';
import '../../data/repositories/packing_transaction_repository.dart';

class PackingCalculatorScreen extends StatefulWidget {
  const PackingCalculatorScreen({super.key});

  @override
  State<PackingCalculatorScreen> createState() => _PackingCalculatorScreenState();
}

class _PackingCalculatorScreenState extends State<PackingCalculatorScreen> {
  final _customer = TextEditingController();
  final _item = TextEditingController();
  final _length = TextEditingController(text: '100');
  final _width = TextEditingController(text: '60');
  final _height = TextEditingController(text: '50');
  final _slatWidth = TextEditingController(text: '5');
  final _gap = TextEditingController(text: '5');
  final _slatPrice = TextEditingController(text: '0');
  final _boardPrice = TextEditingController(text: '0');
  final _labor = TextEditingController(text: '0');
  final _overhead = TextEditingController(text: '0');
  final _markup = TextEditingController(text: '30');
  final _note = TextEditingController();

  final _repository = PackingTransactionRepository();
  final Map<PackingFace, FaceBuildType> _modes = {
    for (final face in PackingFace.values) face: FaceBuildType.closedBoard,
  };
  PackingDimensions? _dimensions;
  PackingFacesResult? _result;
  PriceResult? _price;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _customer, _item, _length, _width, _height, _slatWidth, _gap,
      _slatPrice, _boardPrice, _labor, _overhead, _markup, _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller, String label, {bool allowZero = false}) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || (allowZero ? value < 0 : value <= 0)) {
      throw FormatException('$label harus berupa angka ${allowZero ? 'nol atau lebih' : 'lebih dari 0'}.');
    }
    return value;
  }

  int _integer(TextEditingController controller, String label) {
    final value = _number(controller, label, allowZero: true);
    if (value > 9000000000000) throw FormatException('$label terlalu besar.');
    return value.round();
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    try {
      final dimensions = PackingDimensions(
        lengthCm: _number(_length, 'Panjang'),
        widthCm: _number(_width, 'Lebar'),
        heightCm: _number(_height, 'Tinggi'),
      );
      final slatWidth = _number(_slatWidth, 'Lebar bilah');
      final gap = _number(_gap, 'Celah', allowZero: true);
      final configs = PackingFace.values.map((face) => FaceBuildConfig(
        face: face,
        buildType: _modes[face]!,
        slatWidthCm: slatWidth,
        gapCm: gap,
      )).toList();
      final result = PackingFacesCalculator.calculate(dimensions: dimensions, configs: configs);
      setState(() {
        _dimensions = dimensions;
        _result = result;
        _error = null;
        _price = null;
      });
      _calculatePrice();
    } on FormatException catch (e) {
      setState(() { _error = e.message; _result = null; _price = null; });
    } on ArgumentError catch (e) {
      setState(() { _error = e.message?.toString() ?? 'Periksa ukuran.'; _result = null; _price = null; });
    }
  }

  void _calculatePrice() {
    if (_result == null) return;
    try {
      final lines = <MaterialCostLine>[
        MaterialCostLine(name: 'Kayu bilah', quantity: _result!.totalSlatMeters, unitPrice: _integer(_slatPrice, 'Harga kayu per meter')),
        MaterialCostLine(name: 'Papan', quantity: _result!.totalBoardAreaM2, unitPrice: _integer(_boardPrice, 'Harga papan per m²')),
      ];
      final price = PricingCalculator.calculate(
        materials: lines,
        laborCost: _integer(_labor, 'Biaya jasa'),
        overheadCost: _integer(_overhead, 'Biaya tambahan'),
        markupPercent: _number(_markup, 'Markup', allowZero: true),
      );
      setState(() { _price = price; _error = null; });
    } on FormatException catch (e) {
      setState(() { _price = null; _error = e.message; });
    } on ArgumentError catch (e) {
      setState(() { _price = null; _error = e.message?.toString() ?? 'Periksa biaya.'; });
    }
  }

  String _faceName(PackingFace face) {
    switch (face) {
      case PackingFace.top: return 'Atas';
      case PackingFace.bottom: return 'Bawah';
      case PackingFace.front: return 'Depan';
      case PackingFace.back: return 'Belakang';
      case PackingFace.left: return 'Kiri';
      case PackingFace.right: return 'Kanan';
    }
  }

  String _modeName(FaceBuildType mode) {
    switch (mode) {
      case FaceBuildType.openSlat: return 'Kayu terbuka';
      case FaceBuildType.closedBoard: return 'Papan tertutup';
      case FaceBuildType.none: return 'Tidak dipakai';
    }
  }

  String _rupiah(int value) => 'Rp ${value.toString().replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
    (match) => '.',
  )}';

  Widget _numberField(String label, TextEditingController controller, {
    String? suffix, bool currency = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      prefixText: currency ? 'Rp ' : null,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 20),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );

  Future<void> _saveTransaction() async {
    if (_result == null || _price == null || _dimensions == null) {
      _calculate();
      if (_result == null || _price == null) return;
    }
    setState(() => _saving = true);
    try {
      final materials = <MaterialUsageDraft>[];
      if (_result!.totalSlatMeters > 0) {
        materials.add(MaterialUsageDraft(
          name: 'Kayu bilah',
          unit: 'm',
          calculatedQuantity: _result!.totalSlatMeters,
          unitPrice: _integer(_slatPrice, 'Harga kayu per meter'),
        ));
      }
      if (_result!.totalBoardAreaM2 > 0) {
        materials.add(MaterialUsageDraft(
          name: 'Papan',
          unit: 'm²',
          calculatedQuantity: _result!.totalBoardAreaM2,
          unitPrice: _integer(_boardPrice, 'Harga papan per m²'),
        ));
      }
      final snapshot = <String, Object?>{
        'dimensionsCm': {
          'length': _dimensions!.lengthCm,
          'width': _dimensions!.widthCm,
          'height': _dimensions!.heightCm,
        },
        'faces': _result!.faces.map((face) => {
          'face': face.face.name,
          'buildType': face.buildType.name,
          'slatCount': face.slat?.count,
          'slatLinearMeters': face.slat?.totalLinearMeters,
          'boardAreaM2': face.boardAreaM2,
        }).toList(),
        'totals': {
          'slatMeters': _result!.totalSlatMeters,
          'boardAreaM2': _result!.totalBoardAreaM2,
        },
        'pricing': {
          'slatUnitPrice': _integer(_slatPrice, 'Harga kayu per meter'),
          'boardUnitPrice': _integer(_boardPrice, 'Harga papan per m²'),
          'markupPercent': _number(_markup, 'Markup', allowZero: true),
        },
      };
      // Ensure the snapshot remains JSON-serializable before writing.
      jsonEncode(snapshot);
      final receipt = await _repository.save(PackingTransactionDraft(
        customerName: _customer.text,
        itemDescription: _item.text,
        lengthCm: _dimensions!.lengthCm,
        widthCm: _dimensions!.widthCm,
        heightCm: _dimensions!.heightCm,
        calculationSnapshot: snapshot,
        materialCost: _price!.materialCost,
        laborCost: _price!.laborCost,
        overheadCost: _price!.overheadCost,
        sellingPrice: _price!.sellingPrice,
        note: _note.text,
        materials: materials,
      ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Transaksi tersimpan'),
          content: Text('Nomor nota: $receipt\nHarga jual: ${_rupiah(_price!.sellingPrice)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan transaksi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaksi packing')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      _sectionTitle('Data pelanggan dan barang'),
      TextField(controller: _customer, decoration: const InputDecoration(labelText: 'Nama pelanggan (opsional)', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _item, decoration: const InputDecoration(labelText: 'Nama / deskripsi barang', border: OutlineInputBorder())),
      _sectionTitle('Dimensi barang'),
      Row(children: [
        Expanded(child: _numberField('Panjang', _length, suffix: 'cm')),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Lebar', _width, suffix: 'cm')),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Tinggi', _height, suffix: 'cm')),
      ]),
      _sectionTitle('Pengaturan bilah kayu'),
      Row(children: [
        Expanded(child: _numberField('Lebar bilah', _slatWidth, suffix: 'cm')),
        const SizedBox(width: 10),
        Expanded(child: _numberField('Celah tetap', _gap, suffix: 'cm')),
      ]),
      _sectionTitle('Konstruksi setiap bidang'),
      ...PackingFace.values.map((face) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(_faceName(face), style: const TextStyle(fontWeight: FontWeight.w600))),
            DropdownButton<FaceBuildType>(
              value: _modes[face],
              items: FaceBuildType.values.map((mode) => DropdownMenuItem(
                value: mode, child: Text(_modeName(mode)),
              )).toList(),
              onChanged: (value) {
                if (value != null) setState(() { _modes[face] = value; _result = null; _price = null; });
              },
            ),
          ]),
        ),
      )),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Hitung kebutuhan dan harga'),
      ),
      if (_result != null) ...[
        _sectionTitle('Hasil kebutuhan bahan'),
        Card(child: Column(children: [
          ..._result!.faces.map((face) => ListTile(
            dense: true,
            title: Text(_faceName(face.face)),
            subtitle: Text(_modeName(face.buildType)),
            trailing: face.slat != null
                ? Text('${face.slat!.count} bilah • ${face.slat!.totalLinearMeters.toStringAsFixed(2)} m')
                : face.boardAreaM2 != null
                    ? Text('${face.boardAreaM2!.toStringAsFixed(3)} m²')
                    : const Text('—'),
          )),
          const Divider(height: 1),
          ListTile(title: const Text('Total kayu bilah'), trailing: Text('${_result!.totalSlatMeters.toStringAsFixed(2)} m')),
          ListTile(title: const Text('Total luas papan'), trailing: Text('${_result!.totalBoardAreaM2.toStringAsFixed(3)} m²')),
        ])),
        _sectionTitle('Biaya dan harga jual'),
        _numberField('Harga kayu bilah per meter', _slatPrice, currency: true),
        const SizedBox(height: 10),
        _numberField('Harga papan per m²', _boardPrice, currency: true),
        const SizedBox(height: 10),
        _numberField('Biaya jasa', _labor, currency: true),
        const SizedBox(height: 10),
        _numberField('Biaya tambahan', _overhead, currency: true),
        const SizedBox(height: 10),
        _numberField('Markup', _markup, suffix: '%'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _calculatePrice,
          icon: const Icon(Icons.price_check),
          label: const Text('Hitung ulang harga'),
        ),
        if (_price != null) Card(child: Column(children: [
          ListTile(title: const Text('Biaya bahan'), trailing: Text(_rupiah(_price!.materialCost))),
          ListTile(title: const Text('Biaya jasa'), trailing: Text(_rupiah(_price!.laborCost))),
          ListTile(title: const Text('Biaya tambahan'), trailing: Text(_rupiah(_price!.overheadCost))),
          const Divider(height: 1),
          ListTile(
            title: const Text('Harga jual', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text(_rupiah(_price!.sellingPrice), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        ])),
        const SizedBox(height: 10),
        TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'Catatan transaksi', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveTransaction,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Menyimpan...' : 'Simpan transaksi dan buat nota'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 20),
      const Text('Catatan: estimasi ini belum memasukkan rangka, sambungan, waste, dan optimasi ukuran stok. Nilai biaya bahan mengikuti satuan teoritis meter dan m².'),
    ]),
  );
}
