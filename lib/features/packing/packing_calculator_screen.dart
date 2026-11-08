import 'package:flutter/material.dart';
import '../core/calculation/packing_faces.dart';

class PackingCalculatorScreen extends StatefulWidget {
  const PackingCalculatorScreen({super.key});
  @override State<PackingCalculatorScreen> createState() => _PackingCalculatorScreenState();
}

class _PackingCalculatorScreenState extends State<PackingCalculatorScreen> {
  final _length = TextEditingController(text: '100');
  final _width = TextEditingController(text: '60');
  final _height = TextEditingController(text: '50');
  final _slatWidth = TextEditingController(text: '5');
  final _gap = TextEditingController(text: '5');
  final Map<PackingFace, FaceBuildType> _modes = {
    for (final face in PackingFace.values) face: FaceBuildType.closedBoard,
  };
  PackingFacesResult? _result;
  String? _error;

  @override
  void dispose() {
    _length.dispose(); _width.dispose(); _height.dispose();
    _slatWidth.dispose(); _gap.dispose();
    super.dispose();
  }

  double _number(TextEditingController c, String label) {
    final value = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) {
      throw FormatException('$label harus berupa angka lebih dari 0.');
    }
    return value;
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
      final gap = double.tryParse(_gap.text.trim().replaceAll(',', '.'));
      if (gap == null || !gap.isFinite || gap < 0) {
        throw const FormatException('Celah harus angka nol atau lebih.');
      }
      final configs = PackingFace.values.map((face) => FaceBuildConfig(
        face: face,
        buildType: _modes[face]!,
        slatWidthCm: slatWidth,
        gapCm: gap,
      )).toList();
      final result = PackingFacesCalculator.calculate(dimensions: dimensions, configs: configs);
      setState(() { _result = result; _error = null; });
    } on FormatException catch (e) {
      setState(() { _error = e.message; _result = null; });
    } on ArgumentError catch (e) {
      setState(() { _error = e.message?.toString() ?? 'Periksa ukuran.'; _result = null; });
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

  Widget _numberField(String label, TextEditingController controller, {String suffix = 'cm'}) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kalkulator packing')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Dimensi barang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _numberField('Panjang', _length)),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Lebar', _width)),
        const SizedBox(width: 8),
        Expanded(child: _numberField('Tinggi', _height)),
      ]),
      const SizedBox(height: 20),
      const Text('Pengaturan bilah kayu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _numberField('Lebar bilah', _slatWidth)),
        const SizedBox(width: 10),
        Expanded(child: _numberField('Celah tetap', _gap)),
      ]),
      const SizedBox(height: 20),
      const Text('Konstruksi setiap bidang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
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
                if (value != null) setState(() { _modes[face] = value; _result = null; });
              },
            ),
          ]),
        ),
      )),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _calculate, icon: const Icon(Icons.calculate_outlined), label: const Text('Hitung kebutuhan bahan')),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      if (_result != null) ...[
        const SizedBox(height: 20),
        const Text('Hasil perhitungan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
        const Text('Catatan: hasil ini adalah estimasi geometris. Potongan sambungan, rangka, waste, dan optimasi ukuran stok belum dimasukkan.'),
      ],
    ]),
  );
}
