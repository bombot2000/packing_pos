import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'packing_cost_engine.dart';

class PackingCostEstimatorScreen extends StatefulWidget {
  const PackingCostEstimatorScreen({super.key});

  @override
  State<PackingCostEstimatorScreen> createState() => _PackingCostEstimatorScreenState();
}

class _PackingCostEstimatorScreenState extends State<PackingCostEstimatorScreen> {
  static const _settingsKey = 'packing_pos_cost_estimator_rates_v1';
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _wood = TextEditingController(text: '3500');
  final _stickLength = TextEditingController(text: '200');
  final _screw = TextEditingController(text: '320');
  final _nail = TextEditingController(text: '25');
  final _nailsPerKg = TextEditingController(text: '430');
  final _fasteners = TextEditingController(text: '68');
  final _labor = TextEditingController(text: '15000');
  final _electricity = TextEditingController(text: '1500');
  final _overhead = TextEditingController(text: '5000');
  final _margin = TextEditingController(text: '25');
  final _boardSheets = TextEditingController(text: '0');
  final _boardPrice = TextEditingController(text: '0');
  final _topSlats = TextEditingController(text: '1');
  final _bottomSlats = TextEditingController(text: '1');
  final _frontSlats = TextEditingController(text: '1');
  final _backSlats = TextEditingController(text: '1');
  final _leftSlats = TextEditingController(text: '1');
  final _rightSlats = TextEditingController(text: '1');
  PackingFastener _fastener = PackingFastener.nails;
  SlatCutAxis _topAxis = SlatCutAxis.length, _bottomAxis = SlatCutAxis.length;
  SlatCutAxis _frontAxis = SlatCutAxis.length, _backAxis = SlatCutAxis.length;
  SlatCutAxis _leftAxis = SlatCutAxis.width, _rightAxis = SlatCutAxis.width;
  bool _includeBoard = false, _loading = true, _saving = false;
  static final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  @override
  void initState() { super.initState(); _loadRates(); }

  double _number(TextEditingController c) {
    final raw = c.text.trim().replaceAll(' ', '');
    if (raw.isEmpty) return 0;
    if (raw.contains(',')) return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    final parts = raw.split('.');
    final thousands = parts.length > 1 && parts.first.isNotEmpty &&
        parts.first.length <= 3 && parts.skip(1).every((p) => p.length == 3 && int.tryParse(p) != null);
    return double.tryParse(thousands ? raw.replaceAll('.', '') : raw) ?? 0;
  }

  int _integer(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  bool _hasValidNumber(TextEditingController controller, {bool integer = false}) {
    final raw = controller.text.trim().replaceAll(' ', '');
    if (raw.isEmpty) return false;
    if (integer) return int.tryParse(raw) != null;

    final normalized = raw.contains(',')
        ? raw.replaceAll('.', '').replaceAll(',', '.')
        : (() {
            final parts = raw.split('.');
            final thousands = parts.length > 1 &&
                parts.first.isNotEmpty &&
                parts.first.length <= 3 &&
                parts.skip(1).every(
                  (part) => part.length == 3 && int.tryParse(part) != null,
                );
            return thousands ? raw.replaceAll('.', '') : raw;
          })();
    final value = double.tryParse(normalized);
    return value != null && value.isFinite;
  }

  PackingRates get _rates => PackingRates(
    topSlats: _integer(_topSlats), bottomSlats: _integer(_bottomSlats),
    frontSlats: _integer(_frontSlats), backSlats: _integer(_backSlats),
    leftSlats: _integer(_leftSlats), rightSlats: _integer(_rightSlats),
    topSlatAxis: _topAxis, bottomSlatAxis: _bottomAxis,
    frontSlatAxis: _frontAxis, backSlatAxis: _backAxis,
    leftSlatAxis: _leftAxis, rightSlatAxis: _rightAxis,
    woodPerLonjor: _number(_wood), woodStickLengthCm: _number(_stickLength),
    screwPerPiece: _number(_screw), nailPerGram: _number(_nail),
    nailsPerKg: _integer(_nailsPerKg), fastenersPerPackage: _integer(_fasteners),
    laborPerPackage: _number(_labor), electricityPerPackage: _number(_electricity),
    overheadPerPackage: _number(_overhead), marginPercent: _number(_margin),
    boardSheetsPerPackage: _number(_boardSheets), boardPricePerSheet: _number(_boardPrice),
  );

  PackingCostResult? get _result {
    final p = _number(_length), l = _number(_width), t = _number(_height);
    final qty = _integer(_quantity);
    if (p <= 0 || l <= 0 || t <= 0 || qty <= 0) return null;
    try {
      return PackingCostResult.calculate(
        lengthCm: p, widthCm: l, heightCm: t, packageCount: qty,
        fastener: _fastener, rates: _rates, includeBoard: _includeBoard,
      );
    } on ArgumentError { return null; }
  }

  Future<void> _loadRates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsKey);
      if (raw != null) {
        final r = PackingRates.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        _wood.text = r.woodPerLonjor.toString();
        _stickLength.text = r.woodStickLengthCm.toString();
        _screw.text = r.screwPerPiece.toString();
        _nail.text = r.nailPerGram.toString();
        _nailsPerKg.text = r.nailsPerKg.toString();
        _fasteners.text = r.fastenersPerPackage.toString();
        _labor.text = r.laborPerPackage.toString();
        _electricity.text = r.electricityPerPackage.toString();
        _overhead.text = r.overheadPerPackage.toString();
        _margin.text = r.marginPercent.toString();
        _topSlats.text = r.topSlats.toString();
        _bottomSlats.text = r.bottomSlats.toString();
        _frontSlats.text = r.frontSlats.toString();
        _backSlats.text = r.backSlats.toString();
        _leftSlats.text = r.leftSlats.toString();
        _rightSlats.text = r.rightSlats.toString();
        _topAxis = r.topSlatAxis; _bottomAxis = r.bottomSlatAxis;
        _frontAxis = r.frontSlatAxis; _backAxis = r.backSlatAxis;
        _leftAxis = r.leftSlatAxis; _rightAxis = r.rightSlatAxis;
      }
    } catch (_) {
      // Invalid preference data falls back to safe defaults; no transaction data is touched.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveRates() async {
    final integerInputs = [
      _nailsPerKg, _fasteners, _topSlats, _bottomSlats,
      _frontSlats, _backSlats, _leftSlats, _rightSlats,
    ];
    final decimalInputs = [
      _wood, _stickLength, _screw, _nail, _labor,
      _electricity, _overhead, _margin,
      if (_includeBoard) _boardSheets,
      if (_includeBoard) _boardPrice,
    ];
    if (integerInputs.any((c) => !_hasValidNumber(c, integer: true)) ||
        decimalInputs.any((c) => !_hasValidNumber(c))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Isi semua tarif dengan angka yang valid. Jumlah bilah dan pengikat harus bilangan bulat.'),
      ));
      return;
    }

    final r = _rates;
    if ([r.woodPerLonjor, r.woodStickLengthCm, r.screwPerPiece, r.nailPerGram,
      r.laborPerPackage, r.electricityPerPackage, r.overheadPerPackage,
      r.marginPercent]
      .any((v) => !v.isFinite || v < 0) || r.woodStickLengthCm <= 0 ||
      [r.topSlats, r.bottomSlats, r.frontSlats, r.backSlats, r.leftSlats, r.rightSlats]
        .any((v) => v < 0) ||
      r.nailsPerKg <= 0 || r.fastenersPerPackage < 0 || r.marginPercent >= 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Periksa tarif. Nilai harus valid dan margin di bawah 100%.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(_settingsKey, jsonEncode(r.toSettingsJson()));
      if (!ok) throw StateError('Pengaturan tidak dapat disimpan.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarif estimasi packing tersimpan di perangkat.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan tarif: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {String? suffix}) => TextField(
    controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder(), isDense: true),
  );

  Widget _axisField(
    String label,
    SlatCutAxis value,
    List<SlatCutAxis> allowedAxes,
    ValueChanged<SlatCutAxis?> onChanged,
  ) => DropdownButtonFormField<SlatCutAxis>(
    value: allowedAxes.contains(value) ? value : allowedAxes.first,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    items: allowedAxes.map((axis) => DropdownMenuItem(
      value: axis,
      child: Text(switch (axis) {
        SlatCutAxis.length => 'Panjang',
        SlatCutAxis.width => 'Lebar',
        SlatCutAxis.height => 'Tinggi',
      }),
    )).toList(),
    onChanged: onChanged,
  );

  Widget _cost(String label, double amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [Expanded(child: Text(label)), Text(_currency.format(amount), style: const TextStyle(fontWeight: FontWeight.w600))]),
  );

  @override
  void dispose() {
    for (final c in [_length, _width, _height, _quantity, _wood, _stickLength,
      _screw, _nail, _nailsPerKg, _fasteners, _labor, _electricity, _overhead,
      _margin, _boardSheets, _boardPrice, _topSlats, _bottomSlats,
      _frontSlats, _backSlats, _leftSlats, _rightSlats]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Estimasi Biaya Packing Kayu')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ukuran barang', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field('Panjang', _length, suffix: 'cm')),
                const SizedBox(width: 8),
                Expanded(child: _field('Lebar', _width, suffix: 'cm')),
                const SizedBox(width: 8),
                Expanded(child: _field('Tinggi', _height, suffix: 'cm')),
              ]),
              const SizedBox(height: 12),
              _field('Jumlah koli', _quantity, suffix: 'koli'),
            ],
          ))),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Jumlah bilah per bidang', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Isi jumlah bilah tambahan pada setiap bidang. 1 bilah membagi bidang menjadi 2 bagian; 2 bilah menjadi 3 bagian. Isi 0 jika tidak memakai bilah tambahan.',
                style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _field('Atas', _topSlats, suffix: 'bilah')),
                const SizedBox(width: 8),
                Expanded(child: _field('Bawah', _bottomSlats, suffix: 'bilah')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('Depan', _frontSlats, suffix: 'bilah')),
                const SizedBox(width: 8),
                Expanded(child: _field('Belakang', _backSlats, suffix: 'bilah')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('Kiri', _leftSlats, suffix: 'bilah')),
                const SizedBox(width: 8),
                Expanded(child: _field('Kanan', _rightSlats, suffix: 'bilah')),
              ]),
              const SizedBox(height: 12),
              const Text('Arah potong bilah (sesuaikan kondisi pemasangan)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _axisField('Atas: potong searah', _topAxis, const [SlatCutAxis.length, SlatCutAxis.width], (v) => setState(() => _topAxis = v ?? _topAxis))),
                const SizedBox(width: 8),
                Expanded(child: _axisField('Bawah: potong searah', _bottomAxis, const [SlatCutAxis.length, SlatCutAxis.width], (v) => setState(() => _bottomAxis = v ?? _bottomAxis))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _axisField('Depan: potong searah', _frontAxis, const [SlatCutAxis.length, SlatCutAxis.height], (v) => setState(() => _frontAxis = v ?? _frontAxis))),
                const SizedBox(width: 8),
                Expanded(child: _axisField('Belakang: potong searah', _backAxis, const [SlatCutAxis.length, SlatCutAxis.height], (v) => setState(() => _backAxis = v ?? _backAxis))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _axisField('Kiri: potong searah', _leftAxis, const [SlatCutAxis.width, SlatCutAxis.height], (v) => setState(() => _leftAxis = v ?? _leftAxis))),
                const SizedBox(width: 8),
                Expanded(child: _axisField('Kanan: potong searah', _rightAxis, const [SlatCutAxis.width, SlatCutAxis.height], (v) => setState(() => _rightAxis = v ?? _rightAxis))),
              ]),
              const SizedBox(height: 14),
              Text('Bahan pengikat', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<PackingFastener>(
                segments: const [
                  ButtonSegment(value: PackingFastener.nails, label: Text('Paku 1¼ inch')),
                  ButtonSegment(value: PackingFastener.screws, label: Text('Sekrup')),
                ],
                selected: {_fastener},
                onSelectionChanged: (v) => setState(() => _fastener = v.first),
              ),
              const SizedBox(height: 6),
              Text('Per koli: ${_integer(_fasteners)} buah pengikat. Paku dihitung berdasarkan berat per kg.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ))),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero, title: const Text('Papan penutup (opsional)'),
                subtitle: const Text('Tidak menghitung papan bagian dalam/rangka. Aktifkan hanya jika memakai papan penutup.'),
                value: _includeBoard, onChanged: (v) => setState(() => _includeBoard = v),
              ),
              if (_includeBoard) Row(children: [
                Expanded(child: _field('Lembar per koli', _boardSheets)),
                const SizedBox(width: 8),
                Expanded(child: _field('Harga per lembar', _boardPrice, suffix: 'Rp')),
              ]),
            ],
          ))),
          const SizedBox(height: 10),
          Card(child: ExpansionTile(
            title: const Text('Pengaturan tarif'),
            subtitle: const Text('Nilai awal dapat disesuaikan dan disimpan lokal.'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _field('Harga kayu per lonjor', _wood, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Panjang satu lonjor', _stickLength, suffix: 'cm'),
              const SizedBox(height: 8),
              _field('Harga sekrup per buah', _screw, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Harga paku per gram', _nail, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Jumlah paku per kg', _nailsPerKg, suffix: 'buah'),
              const SizedBox(height: 8),
              _field('Jumlah pengikat per koli', _fasteners, suffix: 'buah'),
              const SizedBox(height: 8),
              _field('Upah per koli', _labor, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Listrik per koli', _electricity, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Overhead per koli', _overhead, suffix: 'Rp'),
              const SizedBox(height: 8),
              _field('Target margin', _margin, suffix: '%'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _saveRates,
                icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Menyimpan...' : 'Simpan tarif'),
              ),
            ],
          )),
          const SizedBox(height: 10),
          if (result == null)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Isi panjang, lebar, tinggi, dan jumlah koli untuk melihat rincian estimasi.')))
          else Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(
            padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rincian estimasi', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Rangka dasar: ${result.frameLengthCm.toStringAsFixed(0)} cm'),
                Text('Jumlah bilah: ${result.slatCountPerPackage} buah/koli'),
                Text('Panjang bilah tambahan: ${result.slatLengthCm.toStringAsFixed(0)} cm/koli'),
                Text('Pembagian bidang: atas ${_topSlats.text}, bawah ${_bottomSlats.text}, depan ${_frontSlats.text}, belakang ${_backSlats.text}, kiri ${_leftSlats.text}, kanan ${_rightSlats.text} bilah'),
                Text('Arah potong: atas ${_topAxis.name}, bawah ${_bottomAxis.name}, depan ${_frontAxis.name}, belakang ${_backAxis.name}, kiri ${_leftAxis.name}, kanan ${_rightAxis.name}'),
                Text('Kayu: ${result.woodSticksPerPackage} lonjor/koli × ${_integer(_quantity)} koli'),
                Text(_fastener == PackingFastener.nails
                  ? 'Paku: ${result.fastenerQuantity.toStringAsFixed(1)} gram'
                  : 'Sekrup: ${result.fastenerQuantity.toStringAsFixed(0)} buah'),
                const Divider(height: 20),
                _cost('Kayu rangka', result.woodCost),
                _cost(_fastener == PackingFastener.nails ? 'Paku' : 'Sekrup', result.fastenerCost),
                _cost('Upah pengerjaan', result.laborCost),
                _cost('Listrik', result.electricityCost),
                _cost('Overhead', result.overheadCost),
                if (_includeBoard) _cost('Papan penutup', result.boardCost),
                const Divider(height: 20),
                _cost('TOTAL MODAL', result.totalCost),
                _cost('Harga sebelum pembulatan', result.suggestedPrice),
                const SizedBox(height: 8),
                const Text('ESTIMASI HARGA JUAL', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_currency.format(result.roundedPrice), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                Text('Margin ${_rates.marginPercent.toStringAsFixed(0)}% • dibulatkan ke atas per Rp1.000', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          )),
          const SizedBox(height: 12),
          const Text('Rangka dasar: 4P + 4L + 4T. Jumlah bilah tambahan ditentukan manual untuk masing-masing bidang; 1 bilah membagi bidang menjadi 2 bagian. Papan penutup dihitung terpisah. Hasil ini merupakan estimasi, bukan nota transaksi.', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
