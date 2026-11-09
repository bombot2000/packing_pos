import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/calculation/packing_faces.dart';
import '../../core/calculation/frame_calculator.dart';
import '../../core/calculation/timber_cut_optimizer.dart';
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
  final _framePostLength = TextEditingController();
  final _frameLengthRail = TextEditingController();
  final _frameWidthRail = TextEditingController();
  final _actualFrameMeters = TextEditingController();
  final _frameAdjustmentReason = TextEditingController();
  final _framePrice = TextEditingController(text: '0');
  final _timberStockLength = TextEditingController(text: '400');
  final _sawKerf = TextEditingController(text: '0.3');
  final _slatPrice = TextEditingController(text: '0');
  final _boardPrice = TextEditingController(text: '0');
  final _labor = TextEditingController(text: '0');
  final _overhead = TextEditingController(text: '0');
  final _markup = TextEditingController(text: '30');
  final _note = TextEditingController();
  final _actualSlatMeters = TextEditingController();
  final _actualBoardArea = TextEditingController();
  final _slatAdjustmentReason = TextEditingController();
  final _boardAdjustmentReason = TextEditingController();

  final _repository = PackingTransactionRepository();
  List<Map<String, Object?>> _masterMaterials = [];
  int? _selectedFrameMaterialId;
  int? _selectedSlatMaterialId;
  int? _selectedBoardMaterialId;
  bool _loadingMaterials = true;
  String? _materialLoadError;

  @override
  void initState() {
    super.initState();
    _loadMasterMaterials();
  }

  Future<void> _loadMasterMaterials() async {
    try {
      final materials = await _repository.listMaterials();
      if (!mounted) return;
      setState(() {
        _masterMaterials = materials;
        _loadingMaterials = false;
        _materialLoadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMaterials = false;
        _materialLoadError = error.toString();
      });
    }
  }

  String _normalizedUnit(String unit) =>
      unit.trim().toLowerCase().replaceAll('²', '2').replaceAll(' ', '');

  List<Map<String, Object?>> _materialsForUnit(String unit) =>
      _masterMaterials.where((item) =>
        _normalizedUnit(item['unit']?.toString() ?? '') == _normalizedUnit(unit)
      ).toList();

  Map<String, Object?>? _selectedMasterMaterial(int? id) {
    if (id == null) return null;
    for (final item in _masterMaterials) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  void _selectFrameMaterial(int? id) {
    final material = _selectedMasterMaterial(id);
    setState(() {
      _selectedFrameMaterialId = id;
      if (material != null) {
        _framePrice.text = (material['current_unit_price'] as num).toInt().toString();
      }
    });
    _calculatePrice();
  }

  void _selectSlatMaterial(int? id) {
    final material = _selectedMasterMaterial(id);
    setState(() {
      _selectedSlatMaterialId = id;
      if (material != null) {
        _slatPrice.text = (material['current_unit_price'] as num).toInt().toString();
      }
    });
    _calculatePrice();
  }

  void _selectBoardMaterial(int? id) {
    final material = _selectedMasterMaterial(id);
    setState(() {
      _selectedBoardMaterialId = id;
      if (material != null) {
        _boardPrice.text = (material['current_unit_price'] as num).toInt().toString();
      }
    });
    _calculatePrice();
  }

  Widget _materialSelector({
    required String label,
    required String unit,
    required int? selectedId,
    required ValueChanged<int?> onChanged,
  }) {
    final compatible = _materialsForUnit(unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          value: selectedId == null ||
                  !compatible.any((item) => item['id'] == selectedId)
              ? -1
              : selectedId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          hint: const Text('Harga manual / pilih master bahan'),
          items: [
            const DropdownMenuItem<int>(
              value: -1,
              child: Text('Harga manual (tanpa master)'),
            ),
            ...compatible.map((item) {
              final materialId = item['id'] as int;
              final price = (item['current_unit_price'] as num).toInt();
              return DropdownMenuItem<int>(
                value: materialId,
                child: Text(
                  item['name'].toString() + ' • ' + _rupiah(price) + '/' + item['unit'].toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (value) => onChanged(value == -1 ? null : value),
        ),
        if (compatible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'Belum ada bahan master dengan satuan ' + unit + '. Harga dapat diisi manual.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
  final Map<PackingFace, FaceBuildType> _modes = {
    for (final face in PackingFace.values) face: FaceBuildType.closedBoard,
  };
  PackingDimensions? _dimensions;
  FrameEstimate? _frameResult;
  TimberCutPlan? _timberPlan;
  PackingFacesResult? _result;
  PriceResult? _price;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _customer, _item, _length, _width, _height, _slatWidth, _gap,
      _framePostLength, _frameLengthRail, _frameWidthRail, _actualFrameMeters,
      _frameAdjustmentReason, _framePrice, _timberStockLength, _sawKerf,
      _slatPrice, _boardPrice, _labor, _overhead, _markup, _note,
      _actualSlatMeters, _actualBoardArea, _slatAdjustmentReason, _boardAdjustmentReason,
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

  double _dimensionOverride(TextEditingController controller, double fallback, String label) {
    if (controller.text.trim().isEmpty) return fallback;
    return _number(controller, label);
  }

  int _integer(TextEditingController controller, String label) {
    final value = _number(controller, label, allowZero: true);
    if (value > 9000000000000) throw FormatException('$label terlalu besar.');
    return value.round();
  }

  void _invalidate() {
    if (_result != null || _price != null) {
      setState(() { _result = null; _price = null; });
    }
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    try {
      final dimensions = PackingDimensions(
        lengthCm: _number(_length, 'Panjang'),
        widthCm: _number(_width, 'Lebar'),
        heightCm: _number(_height, 'Tinggi'),
      );
      final frame = FrameEstimate.eightCorner(
        postHeightCm: _dimensionOverride(_framePostLength, dimensions.heightCm, 'Panjang potong tiang'),
        lengthRailCutCm: _dimensionOverride(_frameLengthRail, dimensions.lengthCm, 'Panjang potong rel arah panjang'),
        widthRailCutCm: _dimensionOverride(_frameWidthRail, dimensions.widthCm, 'Panjang potong rel arah lebar'),
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
      final cutPieces = <TimberCutPiece>[
        ...frame.cutList.map((cut) => TimberCutPiece(
          label: cut.label,
          lengthCm: cut.lengthCm,
          quantity: cut.count,
        )),
        ...result.faces.where((face) => face.slat != null && face.slat!.count > 0).map((face) => TimberCutPiece(
          label: 'Bilah ' + _faceName(face.face),
          lengthCm: dimensions.faceSize(face.face).length,
          quantity: face.slat!.count,
        )),
      ];
      final timberPlan = TimberCutOptimizer.optimize(
        stockLengthCm: _number(_timberStockLength, 'Panjang stok kayu'),
        kerfCm: _number(_sawKerf, 'Lebar mata gergaji', allowZero: true),
        pieces: cutPieces,
      );
      setState(() {
        _dimensions = dimensions;
        _frameResult = frame;
        _timberPlan = timberPlan;
        _actualFrameMeters.text = frame.totalMeters.toStringAsFixed(3);
        _frameAdjustmentReason.clear();
        _result = result;
        _actualSlatMeters.text = result.totalSlatMeters.toStringAsFixed(3);
        _actualBoardArea.text = result.totalBoardAreaM2.toStringAsFixed(3);
        _slatAdjustmentReason.clear();
        _boardAdjustmentReason.clear();
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

  double _actualQuantity(TextEditingController controller, String label) =>
      _number(controller, label, allowZero: true);

  bool _isAdjusted(double actual, double calculated) =>
      (actual - calculated).abs() > 0.000001;

  void _calculatePrice() {
    if (_result == null) return;
    try {
      final actualFrame = _actualQuantity(_actualFrameMeters, 'Jumlah aktual rangka');
      final actualSlat = _actualQuantity(_actualSlatMeters, 'Jumlah aktual kayu bilah');
      final actualBoard = _actualQuantity(_actualBoardArea, 'Jumlah aktual papan');
      final lines = <MaterialCostLine>[
        MaterialCostLine(name: 'Kayu rangka', quantity: actualFrame, unitPrice: _integer(_framePrice, 'Harga kayu rangka per meter')),
        MaterialCostLine(name: 'Kayu bilah', quantity: actualSlat, unitPrice: _integer(_slatPrice, 'Harga kayu per meter')),
        MaterialCostLine(name: 'Papan', quantity: actualBoard, unitPrice: _integer(_boardPrice, 'Harga papan per m²')),
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
    String? suffix, bool currency = false, bool invalidate = true,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) { if (invalidate) { _invalidate(); } else { _calculatePrice(); } },
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
      final actualFrame = _actualQuantity(_actualFrameMeters, 'Jumlah aktual rangka');
      if (_frameResult != null && _isAdjusted(actualFrame, _frameResult!.totalMeters) && _frameAdjustmentReason.text.trim().isEmpty) {
        throw const FormatException('Alasan perubahan jumlah kayu rangka wajib diisi.');
      }
      final actualSlat = _actualQuantity(_actualSlatMeters, 'Jumlah aktual kayu bilah');
      final actualBoard = _actualQuantity(_actualBoardArea, 'Jumlah aktual papan');
      if (_isAdjusted(actualSlat, _result!.totalSlatMeters) && _slatAdjustmentReason.text.trim().isEmpty) {
        throw const FormatException('Alasan perubahan jumlah kayu bilah wajib diisi.');
      }
      if (_isAdjusted(actualBoard, _result!.totalBoardAreaM2) && _boardAdjustmentReason.text.trim().isEmpty) {
        throw const FormatException('Alasan perubahan jumlah papan wajib diisi.');
      }
      final materials = <MaterialUsageDraft>[];
      if (_frameResult != null && _frameResult!.totalMeters > 0) {
        materials.add(MaterialUsageDraft(
          materialId: _selectedFrameMaterialId,
          name: _selectedMasterMaterial(_selectedFrameMaterialId)?['name']?.toString() ?? 'Kayu rangka',
          unit: 'm',
          calculatedQuantity: _frameResult!.totalMeters,
          actualQuantity: actualFrame,
          adjustmentNote: _frameAdjustmentReason.text.trim(),
          unitPrice: _integer(_framePrice, 'Harga kayu rangka per meter'),
        ));
      }
      if (_result!.totalSlatMeters > 0) {
        materials.add(MaterialUsageDraft(
          materialId: _selectedSlatMaterialId,
          name: _selectedMasterMaterial(_selectedSlatMaterialId)?['name']?.toString() ?? 'Kayu bilah',
          unit: 'm',
          calculatedQuantity: _result!.totalSlatMeters,
          actualQuantity: actualSlat,
          adjustmentNote: _slatAdjustmentReason.text.trim(),
          unitPrice: _integer(_slatPrice, 'Harga kayu per meter'),
        ));
      }
      if (_result!.totalBoardAreaM2 > 0) {
        materials.add(MaterialUsageDraft(
          materialId: _selectedBoardMaterialId,
          name: _selectedMasterMaterial(_selectedBoardMaterialId)?['name']?.toString() ?? 'Papan',
          unit: 'm²',
          calculatedQuantity: _result!.totalBoardAreaM2,
          actualQuantity: actualBoard,
          adjustmentNote: _boardAdjustmentReason.text.trim(),
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
        'timberCutPlan': {
          'strategy': 'firstFitDecreasing',
          'stockLengthCm': _timberPlan!.stockLengthCm,
          'kerfCm': _timberPlan!.kerfCm,
          'stockCount': _timberPlan!.stockCount,
          'purchasedLengthMeters': _timberPlan!.purchasedLengthMeters,
          'totalPieceLengthCm': _timberPlan!.totalPieceLengthCm,
          'totalKerfCm': _timberPlan!.totalKerfCm,
          'leftoverLengthCm': _timberPlan!.leftoverLengthCm,
          'bins': _timberPlan!.bins.map((bin) => {
            'number': bin.number,
            'usedLengthCm': bin.usedLengthCm,
            'remainingLengthCm': bin.remainingLengthCm,
            'cuts': bin.cuts.map((cut) => {
              'label': cut.label,
              'lengthCm': cut.lengthCm,
            }).toList(),
          }).toList(),
        },
        'frame': {
          'method': 'eightCorner',
          'cuts': _frameResult!.cutList.map((cut) => {
            'label': cut.label,
            'count': cut.count,
            'cutLengthCm': cut.lengthCm,
            'totalMeters': cut.totalMeters,
          }).toList(),
          'calculatedMeters': _frameResult!.totalMeters,
          'actualMeters': actualFrame,
          'adjustmentReason': _frameAdjustmentReason.text.trim(),
        },
        'totals': {
          'frameMeters': _frameResult!.totalMeters,
          'slatMeters': _result!.totalSlatMeters,
          'boardAreaM2': _result!.totalBoardAreaM2,
        },
        'actualMaterialUsage': {
          'slatMeters': actualSlat,
          'slatAdjustmentReason': _slatAdjustmentReason.text.trim(),
          'boardAreaM2': actualBoard,
          'boardAdjustmentReason': _boardAdjustmentReason.text.trim(),
        },
        'masterMaterialSelection': {
          'frameMaterialId': _selectedFrameMaterialId,
          'frameMaterialName': _selectedMasterMaterial(_selectedFrameMaterialId)?['name'],
          'slatMaterialId': _selectedSlatMaterialId,
          'slatMaterialName': _selectedMasterMaterial(_selectedSlatMaterialId)?['name'],
          'boardMaterialId': _selectedBoardMaterialId,
          'boardMaterialName': _selectedMasterMaterial(_selectedBoardMaterialId)?['name'],
        },
        'pricing': {
          'frameUnitPrice': _integer(_framePrice, 'Harga kayu rangka per meter'),
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
      _sectionTitle('Rangka utama 8 sudut'),
      const Text('Estimasi rangka: 4 tiang sudut mengikuti tinggi barang, 4 rel arah panjang mengikuti panjang barang, dan 4 rel arah lebar mengikuti lebar barang. Isi ukuran potong hanya jika perlu menyesuaikan sambungan atau orientasi kayu; kosong = mengikuti dimensi barang.'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _numberField('Potong tiang', _framePostLength, suffix: 'cm', invalidate: true)),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Potong rel panjang', _frameLengthRail, suffix: 'cm')),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Potong rel lebar', _frameWidthRail, suffix: 'cm')),
      ]),
      Row(children: [
        Expanded(child: _numberField('Panjang stok', _timberStockLength, suffix: 'cm')),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Mata gergaji', _sawKerf, suffix: 'cm')),
      ]),
      const Text('Panjang stok dan lebar mata gergaji dipakai untuk estimasi jumlah batang. Optimasi menggunakan metode first-fit decreasing; hasil merupakan estimasi, bukan jaminan jumlah minimum.'),
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
        _sectionTitle('Daftar potongan rangka'),
        if (_frameResult != null)
          Card(child: Column(children: [
            ..._frameResult!.cutList.map((cut) => ListTile(
              dense: true,
              title: Text(cut.label),
              subtitle: Text(cut.count.toString() + ' potong × ' + cut.lengthCm.toStringAsFixed(1) + ' cm'),
              trailing: Text(cut.totalMeters.toStringAsFixed(2) + ' m'),
            )),
            const Divider(height: 1),
            ListTile(title: const Text('Total rangka'), trailing: Text(_frameResult!.totalMeters.toStringAsFixed(2) + ' m')),
          ])),
        _sectionTitle('Rencana pemotongan stok kayu'),
        if (_timberPlan != null)
          Card(child: Column(children: [
            ListTile(
              title: const Text('Perkiraan batang dibeli'),
              trailing: Text(_timberPlan!.stockCount.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(title: const Text('Panjang pembelian total'), trailing: Text(_timberPlan!.purchasedLengthMeters.toStringAsFixed(2) + ' m')),
            ListTile(title: const Text('Sisa stok total (termasuk kerf)'), trailing: Text(_timberPlan!.leftoverLengthCm.toStringAsFixed(1) + ' cm')),
            const Divider(height: 1),
            ..._timberPlan!.bins.map((bin) => ListTile(
              dense: true,
              title: Text('Batang ' + bin.number.toString()),
              subtitle: Text(bin.cuts.map((cut) => cut.label + ' ' + cut.lengthCm.toStringAsFixed(1) + ' cm').join(' • ')),
              trailing: Text('Sisa ' + bin.remainingLengthCm.toStringAsFixed(1) + ' cm'),
            )),
          ])),
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
        _sectionTitle('Penyesuaian jumlah bahan aktual'),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kayu rangka', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('Hasil hitung: ' + _frameResult!.totalMeters.toStringAsFixed(3) + ' m'),
          const SizedBox(height: 8),
          _numberField('Jumlah aktual rangka (m)', _actualFrameMeters, suffix: 'm', invalidate: false),
          const SizedBox(height: 8),
          TextField(controller: _frameAdjustmentReason, maxLines: 2, decoration: const InputDecoration(labelText: 'Alasan penyesuaian rangka (wajib jika berbeda)', border: OutlineInputBorder())),
        ]))),
        const Text('Jumlah hasil hitung dapat disesuaikan sesuai pemakaian nyata. Jika berbeda, isi alasan agar perubahan tercatat pada nota.'),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kayu bilah', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('Hasil hitung: ${_result!.totalSlatMeters.toStringAsFixed(3)} m'),
          const SizedBox(height: 8),
          _numberField('Jumlah aktual kayu (m)', _actualSlatMeters, suffix: 'm', invalidate: false),
          const SizedBox(height: 8),
          TextField(controller: _slatAdjustmentReason, maxLines: 2, decoration: const InputDecoration(labelText: 'Alasan penyesuaian kayu (wajib jika berbeda)', border: OutlineInputBorder())),
        ]))),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Papan', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('Hasil hitung: ${_result!.totalBoardAreaM2.toStringAsFixed(3)} m²'),
          const SizedBox(height: 8),
          _numberField('Jumlah aktual papan (m²)', _actualBoardArea, suffix: 'm²', invalidate: false),
          const SizedBox(height: 8),
          TextField(controller: _boardAdjustmentReason, maxLines: 2, decoration: const InputDecoration(labelText: 'Alasan penyesuaian papan (wajib jika berbeda)', border: OutlineInputBorder())),
        ]))),
        _sectionTitle('Master bahan dan biaya'),
        if (_loadingMaterials)
          const LinearProgressIndicator(),
        if (_materialLoadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Master bahan tidak dapat dimuat: ' + _materialLoadError! + '. Harga manual tetap dapat digunakan.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _materialSelector(
          label: 'Master kayu rangka (satuan meter)',
          unit: 'm',
          selectedId: _selectedFrameMaterialId,
          onChanged: _selectFrameMaterial,
        ),
        const SizedBox(height: 10),
        _numberField('Harga kayu rangka per meter', _framePrice, currency: true, invalidate: false),
        const SizedBox(height: 14),
        _materialSelector(
          label: 'Master kayu bilah (satuan meter)',
          unit: 'm',
          selectedId: _selectedSlatMaterialId,
          onChanged: _selectSlatMaterial,
        ),
        const SizedBox(height: 10),
        _numberField('Harga kayu bilah per meter', _slatPrice, currency: true, invalidate: false),
        const SizedBox(height: 14),
        _materialSelector(
          label: 'Master papan (satuan m²)',
          unit: 'm²',
          selectedId: _selectedBoardMaterialId,
          onChanged: _selectBoardMaterial,
        ),

        const SizedBox(height: 10),
        _numberField('Harga papan per m²', _boardPrice, currency: true, invalidate: false),
        const SizedBox(height: 10),
        _numberField('Biaya jasa', _labor, currency: true, invalidate: false),
        const SizedBox(height: 10),
        _numberField('Biaya tambahan', _overhead, currency: true, invalidate: false),
        const SizedBox(height: 10),
        _numberField('Markup', _markup, suffix: '%', invalidate: false),
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
      const Text('Catatan: jumlah batang pada rencana pemotongan merupakan estimasi first-fit decreasing untuk rangka dan bilah. Harga kayu masih dihitung berdasarkan meter teoritis; harga pembelian per batang dan optimasi papan lembar akan ditambahkan pada tahap berikutnya.'),
    ]),
  );
}
