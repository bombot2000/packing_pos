import 'package:flutter/material.dart';
import '../../data/repositories/packing_transaction_repository.dart';

class ServiceTypeMasterScreen extends StatefulWidget {
  const ServiceTypeMasterScreen({super.key});
  @override
  State<ServiceTypeMasterScreen> createState() => _ServiceTypeMasterScreenState();
}

class _ServiceTypeMasterScreenState extends State<ServiceTypeMasterScreen> {
  final _repo = PackingTransactionRepository();
  late Future<List<Map<String, Object?>>> _future;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() => _future = _repo.listServiceTypes(activeOnly: false);

  String _money(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    return 'Rp ${n.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(builder: (_) => _ServiceEditor(
        name: row?['name']?.toString() ?? '',
        price: row?['default_price']?.toString() ?? '0',
      )),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.saveServiceType(id: row?['id'] as int?, name: result['name']! as String, defaultPrice: result['price']! as int);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  Future<void> _toggle(Map<String, Object?> row) async {
    final active = (row['is_active'] as num).toInt() == 1;
    try {
      await _repo.setServiceTypeActive(row['id'] as int, !active);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengubah status: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Master jenis pekerjaan'), actions: [
      IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Tambah pekerjaan')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('Gagal memuat: ${s.error}'));
        final rows = s.data ?? [];
        if (rows.isEmpty) return const Center(child: Text('Belum ada jenis pekerjaan.'));
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = rows[i]; final active = (row['is_active'] as num).toInt() == 1;
            return Card(child: ListTile(
              title: Text(row['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${_money(row['default_price'])} • ${active ? 'Aktif' : 'Nonaktif'}'),
              onTap: () => _edit(row),
              trailing: PopupMenuButton<String>(
                onSelected: (v) { if (v == 'edit') _edit(row); if (v == 'toggle') _toggle(row); },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Ubah nama / harga')),
                  PopupMenuItem(value: 'toggle', child: Text(active ? 'Nonaktifkan' : 'Aktifkan')),
                ],
              ),
            ));
          },
        );
      },
    ),
  );
}

class _ServiceEditor extends StatefulWidget {
  const _ServiceEditor({required this.name, required this.price});
  final String name, price;
  @override
  State<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends State<_ServiceEditor> {
  late final _name = TextEditingController(text: widget.name);
  late final _price = TextEditingController(text: widget.price);
  String? _error;
  @override
  void dispose() { _name.dispose(); _price.dispose(); super.dispose(); }
  void _save() {
    final value = int.tryParse(_price.text.replaceAll('.', '').replaceAll(',', '').trim());
    if (_name.text.trim().isEmpty) { setState(() => _error = 'Nama pekerjaan wajib diisi.'); return; }
    if (value == null || value < 0) { setState(() => _error = 'Harga harus berupa Rupiah nol atau lebih.'); return; }
    Navigator.of(context).pop<Map<String, Object?>>({'name': _name.text.trim(), 'price': value});
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name.isEmpty ? 'Tambah pekerjaan' : 'Ubah pekerjaan')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      TextField(controller: _name, textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nama jenis pekerjaan', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      TextField(controller: _price, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Harga standar', prefixText: 'Rp ', border: OutlineInputBorder())),
      if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Simpan')),
      OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Batal')),
    ]),
  );
}
