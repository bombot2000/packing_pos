import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format/friendly_error.dart';
import '../../core/format/money_input.dart';
import '../../core/format/rupiah.dart';
import 'packing_cost_engine.dart';

/// Sisi peti beserta arah potong bilah yang diizinkan engine.
enum _Face {
  top('Atas', [SlatCutAxis.length, SlatCutAxis.width]),
  bottom('Bawah', [SlatCutAxis.length, SlatCutAxis.width]),
  front('Depan', [SlatCutAxis.length, SlatCutAxis.height]),
  back('Belakang', [SlatCutAxis.length, SlatCutAxis.height]),
  left('Kiri', [SlatCutAxis.width, SlatCutAxis.height]),
  right('Kanan', [SlatCutAxis.width, SlatCutAxis.height]);

  const _Face(this.label, this.axes);
  final String label;
  final List<SlatCutAxis> axes;
}

String _axisName(SlatCutAxis axis) => switch (axis) {
      SlatCutAxis.length => 'Panjang',
      SlatCutAxis.width => 'Lebar',
      SlatCutAxis.height => 'Tinggi',
    };

class PackingCostEstimatorScreen extends StatefulWidget {
  const PackingCostEstimatorScreen({super.key});

  @override
  State<PackingCostEstimatorScreen> createState() => _PackingCostEstimatorScreenState();
}

class _PackingCostEstimatorScreenState extends State<PackingCostEstimatorScreen> {
  static const _settingsKey = 'packing_pos_cost_estimator_rates_v1';
  static const _maxSlatsPerFace = 20;

  // Ukuran barang
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _quantity = TextEditingController(text: '1');

  // Tarif (tersimpan di perangkat)
  final _wood = TextEditingController();
  final _stickLength = TextEditingController();
  final _screw = TextEditingController();
  final _nail = TextEditingController();
  final _nailsPerKg = TextEditingController();
  final _fasteners = TextEditingController();
  final _labor = TextEditingController();
  final _electricity = TextEditingController();
  final _overhead = TextEditingController();
  final _margin = TextEditingController();

  // Papan penutup (per pesanan, tidak disimpan)
  final _boardSheets = TextEditingController(text: '0');
  final _boardPrice = TextEditingController(text: '0');

  final Map<_Face, int> _slats = {for (final f in _Face.values) f: 1};
  final Map<_Face, SlatCutAxis> _axes = {
    _Face.top: SlatCutAxis.length,
    _Face.bottom: SlatCutAxis.length,
    _Face.front: SlatCutAxis.length,
    _Face.back: SlatCutAxis.length,
    _Face.left: SlatCutAxis.width,
    _Face.right: SlatCutAxis.width,
  };

  PackingFastener _fastener = PackingFastener.nails;
  bool _includeBoard = false, _loading = true, _saving = false;

  List<TextEditingController> get _all => [
        _length, _width, _height, _quantity, _wood, _stickLength, _screw, _nail,
        _nailsPerKg, _fasteners, _labor, _electricity, _overhead, _margin,
        _boardSheets, _boardPrice,
      ];

  @override
  void initState() {
    super.initState();
    _applyRates(const PackingRates());
    _loadRates();
  }

  @override
  void dispose() {
    for (final c in _all) { c.dispose(); }
    super.dispose();
  }

  // ---------------------------------------------------------------- parsing

  /// Angka desimal; koma atau titik dianggap pemisah desimal.
  double? _dec(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v != null && v.isFinite ? v : null;
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static String _rp(double v) => formatRupiah(v.round());

  // ------------------------------------------------------------ validators

  String? _errPositiveDim(TextEditingController c) {
    if (c.text.trim().isEmpty) return null; // kosong = belum diisi, bukan salah
    final v = _dec(c);
    return v == null || v <= 0 ? 'Isi angka > 0' : null;
  }

  String? _errRupiah(TextEditingController c) =>
      parseRupiah(c.text) == null ? 'Wajib diisi' : null;

  String? _errDecimal(TextEditingController c, {bool positive = false}) {
    final v = _dec(c);
    if (v == null) return 'Wajib diisi';
    if (v < 0 || (positive && v == 0)) return positive ? 'Harus > 0' : 'Tidak boleh minus';
    return null;
  }

  String? _errMargin() {
    final v = _dec(_margin);
    if (v == null) return 'Wajib diisi';
    if (v < 0 || v >= 100) return 'Isi 0 – 99';
    return null;
  }

  String? _errInteger(TextEditingController c, {int min = 0}) {
    final v = _int(c);
    if (v == null) return 'Wajib diisi';
    return v < min ? 'Minimal $min' : null;
  }

  /// Pesan masalah tarif pertama yang ditemukan, atau null bila semua valid.
  String? _ratesProblem({required bool includeBoard}) {
    final checks = <(String, String?)>[
      ('Harga kayu per lonjor', _errRupiah(_wood)),
      ('Panjang satu lonjor', _errDecimal(_stickLength, positive: true)),
      ('Harga sekrup', _errRupiah(_screw)),
      ('Harga paku per gram', _errDecimal(_nail)),
      ('Jumlah paku per kg', _errInteger(_nailsPerKg, min: 1)),
      ('Jumlah pengikat per koli', _errInteger(_fasteners)),
      ('Upah per koli', _errRupiah(_labor)),
      ('Listrik per koli', _errRupiah(_electricity)),
      ('Overhead per koli', _errRupiah(_overhead)),
      ('Target margin', _errMargin()),
      if (includeBoard) ('Lembar papan per koli', _errDecimal(_boardSheets)),
      if (includeBoard) ('Harga papan per lembar', _errRupiah(_boardPrice)),
    ];
    for (final (label, err) in checks) {
      if (err != null) return '$label: ${err.toLowerCase()}. Periksa di "Pengaturan tarif".';
    }
    return null;
  }

  // ----------------------------------------------------------------- rates

  PackingRates _buildRates() => PackingRates(
        topSlats: _slats[_Face.top]!, bottomSlats: _slats[_Face.bottom]!,
        frontSlats: _slats[_Face.front]!, backSlats: _slats[_Face.back]!,
        leftSlats: _slats[_Face.left]!, rightSlats: _slats[_Face.right]!,
        topSlatAxis: _axes[_Face.top]!, bottomSlatAxis: _axes[_Face.bottom]!,
        frontSlatAxis: _axes[_Face.front]!, backSlatAxis: _axes[_Face.back]!,
        leftSlatAxis: _axes[_Face.left]!, rightSlatAxis: _axes[_Face.right]!,
        woodPerLonjor: (parseRupiah(_wood.text) ?? 0).toDouble(),
        woodStickLengthCm: _dec(_stickLength) ?? 0,
        screwPerPiece: (parseRupiah(_screw.text) ?? 0).toDouble(),
        nailPerGram: _dec(_nail) ?? 0,
        nailsPerKg: _int(_nailsPerKg) ?? 0,
        fastenersPerPackage: _int(_fasteners) ?? 0,
        laborPerPackage: (parseRupiah(_labor.text) ?? 0).toDouble(),
        electricityPerPackage: (parseRupiah(_electricity.text) ?? 0).toDouble(),
        overheadPerPackage: (parseRupiah(_overhead.text) ?? 0).toDouble(),
        marginPercent: _dec(_margin) ?? 0,
        boardSheetsPerPackage: _dec(_boardSheets) ?? 0,
        boardPricePerSheet: (parseRupiah(_boardPrice.text) ?? 0).toDouble(),
      );

  void _applyRates(PackingRates r) {
    _wood.text = groupThousands(r.woodPerLonjor.round());
    _stickLength.text = _fmt(r.woodStickLengthCm);
    _screw.text = groupThousands(r.screwPerPiece.round());
    _nail.text = _fmt(r.nailPerGram);
    _nailsPerKg.text = r.nailsPerKg.toString();
    _fasteners.text = r.fastenersPerPackage.toString();
    _labor.text = groupThousands(r.laborPerPackage.round());
    _electricity.text = groupThousands(r.electricityPerPackage.round());
    _overhead.text = groupThousands(r.overheadPerPackage.round());
    _margin.text = _fmt(r.marginPercent);
    _slats[_Face.top] = r.topSlats;
    _slats[_Face.bottom] = r.bottomSlats;
    _slats[_Face.front] = r.frontSlats;
    _slats[_Face.back] = r.backSlats;
    _slats[_Face.left] = r.leftSlats;
    _slats[_Face.right] = r.rightSlats;
    _axes[_Face.top] = r.topSlatAxis;
    _axes[_Face.bottom] = r.bottomSlatAxis;
    _axes[_Face.front] = r.frontSlatAxis;
    _axes[_Face.back] = r.backSlatAxis;
    _axes[_Face.left] = r.leftSlatAxis;
    _axes[_Face.right] = r.rightSlatAxis;
  }

  Future<void> _loadRates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsKey);
      if (raw != null) {
        _applyRates(PackingRates.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map)));
      }
    } catch (_) {
      // Data tarif rusak: pakai nilai standar. Data transaksi tidak tersentuh.
      _applyRates(const PackingRates());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveRates() async {
    final problem = _ratesProblem(includeBoard: false);
    if (problem != null) { _toast(problem); return; }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(_settingsKey, jsonEncode(_buildRates().toSettingsJson()));
      if (!ok) throw StateError('Pengaturan tidak dapat disimpan.');
      _toast('Tarif tersimpan di perangkat.');
    } catch (e) {
      _toast('Gagal menyimpan tarif: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetRates() {
    setState(() => _applyRates(const PackingRates()));
    _toast('Tarif dikembalikan ke standar. Tekan "Simpan tarif" untuk menyimpannya.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------ calculation

  ({PackingCostResult? result, String? problem}) _calculate() {
    final p = _dec(_length), l = _dec(_width), t = _dec(_height);
    if (p == null || l == null || t == null || p <= 0 || l <= 0 || t <= 0) {
      return (result: null, problem: 'Isi panjang, lebar, dan tinggi barang untuk melihat estimasi harga.');
    }
    final qty = _int(_quantity);
    if (qty == null || qty < 1) {
      return (result: null, problem: 'Jumlah koli minimal 1.');
    }
    final rateProblem = _ratesProblem(includeBoard: _includeBoard);
    if (rateProblem != null) return (result: null, problem: rateProblem);
    try {
      final result = PackingCostResult.calculate(
        lengthCm: p, widthCm: l, heightCm: t, packageCount: qty,
        fastener: _fastener, rates: _buildRates(), includeBoard: _includeBoard,
      );
      return (result: result, problem: null);
    } on ArgumentError catch (e) {
      final msg = friendlyError(e);
      final tooLong = msg.contains('lonjor');
      return (
        result: null,
        problem: tooLong
            ? '$msg Perkecil ukuran, atau ubah "Panjang satu lonjor" di Pengaturan tarif.'
            : msg,
      );
    }
  }

  void _clearInputs() {
    FocusScope.of(context).unfocus();
    setState(() {
      _length.clear(); _width.clear(); _height.clear();
      _quantity.text = '1';
      _includeBoard = false;
      _boardSheets.text = '0';
      _boardPrice.text = '0';
    });
  }

  // ------------------------------------------------------------ small widgets

  Widget _numField(
    String label,
    TextEditingController c, {
    String? suffix,
    String? prefix,
    String? helper,
    String? error,
    bool decimal = false,
    bool rupiah = false,
    bool last = false,
  }) {
    final formatters = <TextInputFormatter>[
      if (rupiah) RupiahInputFormatter()
      else if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
      else FilteringTextInputFormatter.digitsOnly,
    ];
    return TextField(
      controller: c,
      keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
      inputFormatters: formatters,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixText: prefix,
        helperText: helper,
        helperMaxLines: 2,
        errorText: error,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _section(String title, {String? subtitle, required List<Widget> children}) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _quantityStepper() {
    final qty = _int(_quantity) ?? 1;
    void change(int delta) =>
        setState(() => _quantity.text = (qty + delta).clamp(1, 9999).toString());
    return Row(children: [
      const Expanded(child: Text('Jumlah koli', style: TextStyle(fontSize: 16))),
      IconButton.filledTonal(
        tooltip: 'Kurangi', onPressed: qty > 1 ? () => change(-1) : null, icon: const Icon(Icons.remove)),
      SizedBox(
        width: 72,
        child: TextField(
          controller: _quantity,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
      ),
      IconButton.filledTonal(tooltip: 'Tambah', onPressed: () => change(1), icon: const Icon(Icons.add)),
    ]);
  }

  Widget _slatStepper(_Face face) {
    final count = _slats[face]!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Kurangi bilah ${face.label}',
          onPressed: count > 0 ? () => setState(() => _slats[face] = count - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(face.label, style: Theme.of(context).textTheme.labelMedium),
            Text('$count', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Tambah bilah ${face.label}',
          onPressed: count < _maxSlatsPerFace ? () => setState(() => _slats[face] = count + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]),
    );
  }

  Widget _slatGrid() {
    final rows = <Widget>[];
    for (var i = 0; i < _Face.values.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(Row(children: [
        Expanded(child: _slatStepper(_Face.values[i])),
        const SizedBox(width: 8),
        Expanded(child: _slatStepper(_Face.values[i + 1])),
      ]));
    }
    return Column(children: rows);
  }

  Widget _axisField(_Face face) => DropdownButtonFormField<SlatCutAxis>(
        value: face.axes.contains(_axes[face]) ? _axes[face] : face.axes.first,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: '${face.label}: bilah searah',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: face.axes
            .map((a) => DropdownMenuItem(value: a, child: Text(_axisName(a))))
            .toList(),
        onChanged: (v) => setState(() => _axes[face] = v ?? face.axes.first),
      );

  Widget _axisGrid() {
    final rows = <Widget>[];
    for (var i = 0; i < _Face.values.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: [
        Expanded(child: _axisField(_Face.values[i])),
        const SizedBox(width: 8),
        Expanded(child: _axisField(_Face.values[i + 1])),
      ]));
    }
    return Column(children: rows);
  }

  // ----------------------------------------------------------- result sheet

  String _customerSummary(PackingCostResult r) {
    final qty = _int(_quantity) ?? 1;
    final size = '${_fmt(_dec(_length)!)} × ${_fmt(_dec(_width)!)} × ${_fmt(_dec(_height)!)} cm';
    final perKoli = qty > 1 ? '\n≈ ${_rp(r.roundedPrice / qty)} per koli' : '';
    return 'Estimasi packing kayu\n'
        'Ukuran: $size\n'
        'Jumlah: $qty koli\n'
        'Harga: ${_rp(r.roundedPrice)}$perKoli';
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ]),
      );

  void _showDetail(PackingCostResult r) {
    final qty = _int(_quantity) ?? 1;
    final marginPct = _dec(_margin) ?? 0;
    final fastenerLabel = _fastener == PackingFastener.nails ? 'Paku' : 'Sekrup';
    final fastenerQty = _fastener == PackingFastener.nails
        ? '${r.fastenerQuantity.toStringAsFixed(0)} gram'
        : '${r.fastenerQuantity.toStringAsFixed(0)} buah';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rincian estimasi', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Kebutuhan bahan', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            _row('Kayu', '${r.woodSticksPerPackage * qty} lonjor ($qty koli × ${r.woodSticksPerPackage})'),
            _row(fastenerLabel, fastenerQty),
            _row('Bilah penguat', '${r.slatCountPerPackage} batang/koli'),
            if (_includeBoard) _row('Papan penutup', '${_fmt(r.boardQuantity)} lembar'),
            const Divider(height: 24),
            Text('Biaya (modal)', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            _row('Kayu', _rp(r.woodCost)),
            _row(fastenerLabel, _rp(r.fastenerCost)),
            _row('Upah pengerjaan', _rp(r.laborCost)),
            _row('Listrik', _rp(r.electricityCost)),
            _row('Overhead', _rp(r.overheadCost)),
            if (_includeBoard) _row('Papan penutup', _rp(r.boardCost)),
            const Divider(height: 24),
            _row('Total modal', _rp(r.totalCost), bold: true),
            _row('Harga + margin ${_fmt(marginPct)}%', _rp(r.suggestedPrice)),
            _row('Harga jual (dibulatkan ke Rp1.000)', _rp(r.roundedPrice), bold: true),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.copy),
                label: const Text('Salin untuk pelanggan'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _customerSummary(r)));
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Disalin. Tempel ke WhatsApp. Modal tidak ikut disalin.');
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rangka dasar 4P + 4L + 4T, ditambah bilah penguat sesuai isian. '
              'Ini estimasi, bukan nota transaksi.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _resultBar(({PackingCostResult? result, String? problem}) calc) {
    final scheme = Theme.of(context).colorScheme;
    final r = calc.result;
    final qty = _int(_quantity) ?? 1;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: r == null ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: r == null
              ? Row(children: [
                  Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text(calc.problem ?? '')),
                ])
              : Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Estimasi harga jual', style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        _rp(r.roundedPrice),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900, color: scheme.primary),
                      ),
                      Text(
                        '${qty > 1 ? '≈ ${_rp(r.roundedPrice / qty)}/koli • ' : ''}Modal ${_rp(r.totalCost)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _showDetail(r), child: const Text('Rincian')),
                ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final calc = _calculate();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estimasi Biaya Packing Kayu'),
        actions: [
          IconButton(
            tooltip: 'Kosongkan ukuran',
            onPressed: _loading ? null : _clearInputs,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              children: [
                _section('1. Ukuran barang', subtitle: 'Isi ukuran barang yang mau dipacking, dalam cm.', children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _numField('Panjang', _length, suffix: 'cm', decimal: true, error: _errPositiveDim(_length))),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('Lebar', _width, suffix: 'cm', decimal: true, error: _errPositiveDim(_width))),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('Tinggi', _height, suffix: 'cm', decimal: true, error: _errPositiveDim(_height), last: true)),
                  ]),
                  const SizedBox(height: 12),
                  _quantityStepper(),
                ]),
                const SizedBox(height: 12),
                _section(
                  '2. Bilah penguat',
                  subtitle: 'Kayu tambahan di tengah tiap sisi peti. 1 bilah membagi sisi jadi 2 bagian. Isi 0 bila tidak dipakai.',
                  children: [
                    Wrap(spacing: 8, children: [
                      ActionChip(
                        label: const Text('Tanpa bilah'),
                        onPressed: () => setState(() { for (final f in _Face.values) { _slats[f] = 0; } }),
                      ),
                      ActionChip(
                        label: const Text('1 bilah tiap sisi'),
                        onPressed: () => setState(() { for (final f in _Face.values) { _slats[f] = 1; } }),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _slatGrid(),
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        title: const Text('Arah potong bilah (lanjutan)'),
                        subtitle: const Text('Biasanya tidak perlu diubah'),
                        children: [_axisGrid()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _section('3. Pengikat', children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PackingFastener>(
                      segments: const [
                        ButtonSegment(value: PackingFastener.nails, label: Text('Paku 1¼ inch')),
                        ButtonSegment(value: PackingFastener.screws, label: Text('Sekrup')),
                      ],
                      selected: {_fastener},
                      onSelectionChanged: (v) => setState(() => _fastener = v.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Per koli dipakai ${_int(_fasteners) ?? 0} buah (ubah di Pengaturan tarif).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pakai papan penutup'),
                        subtitle: const Text('Aktifkan hanya jika peti ditutup papan. Papan rangka tidak dihitung.'),
                        value: _includeBoard,
                        onChanged: (v) => setState(() => _includeBoard = v),
                      ),
                      if (_includeBoard) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _numField('Lembar per koli', _boardSheets, decimal: true, suffix: 'lbr', error: _errDecimal(_boardSheets))),
                        const SizedBox(width: 8),
                        Expanded(child: _numField('Harga per lembar', _boardPrice, prefix: 'Rp ', rupiah: true, error: _errRupiah(_boardPrice), last: true)),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Pengaturan tarif'),
                    subtitle: const Text('Harga bahan, upah, dan margin. Tersimpan di HP ini.'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Kayu', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _numField('Harga kayu per lonjor', _wood, prefix: 'Rp ', rupiah: true, error: _errRupiah(_wood)),
                      const SizedBox(height: 10),
                      _numField('Panjang satu lonjor', _stickLength, suffix: 'cm', decimal: true, error: _errDecimal(_stickLength, positive: true), helper: 'Lonjor = satu batang kayu utuh dari toko'),
                      const SizedBox(height: 16),
                      Text('Pengikat', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _numField('Harga paku per gram', _nail, prefix: 'Rp ', decimal: true, error: _errDecimal(_nail)),
                      const SizedBox(height: 10),
                      _numField('Jumlah paku per kg', _nailsPerKg, suffix: 'buah', error: _errInteger(_nailsPerKg, min: 1)),
                      const SizedBox(height: 10),
                      _numField('Harga sekrup per buah', _screw, prefix: 'Rp ', rupiah: true, error: _errRupiah(_screw)),
                      const SizedBox(height: 10),
                      _numField('Jumlah pengikat per koli', _fasteners, suffix: 'buah', error: _errInteger(_fasteners)),
                      const SizedBox(height: 16),
                      Text('Biaya per koli', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _numField('Upah pengerjaan', _labor, prefix: 'Rp ', rupiah: true, error: _errRupiah(_labor)),
                      const SizedBox(height: 10),
                      _numField('Listrik', _electricity, prefix: 'Rp ', rupiah: true, error: _errRupiah(_electricity)),
                      const SizedBox(height: 10),
                      _numField('Overhead', _overhead, prefix: 'Rp ', rupiah: true, error: _errRupiah(_overhead)),
                      const SizedBox(height: 16),
                      _numField('Target margin', _margin, suffix: '%', decimal: true, error: _errMargin(), helper: 'Persen keuntungan dari harga jual (0 – 99)', last: true),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveRates,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Menyimpan...' : 'Simpan tarif'),
                      ),
                      TextButton(onPressed: _resetRates, child: const Text('Kembalikan ke tarif standar')),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _loading ? null : _resultBar(calc),
    );
  }
}