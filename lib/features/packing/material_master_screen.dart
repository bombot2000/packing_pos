import 'package:flutter/material.dart';

import '../../data/repositories/packing_transaction_repository.dart';

class MaterialMasterScreen extends StatefulWidget {
  const MaterialMasterScreen({super.key});
  @override
  State<MaterialMasterScreen> createState() => _MaterialMasterScreenState();
}

class _MaterialMasterScreenState extends State<MaterialMasterScreen> {
  final PackingTransactionRepository _repository = PackingTransactionRepository();
  late Future<List<Map<String, Object?>>> _materials;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() { _materials = _repository.listMaterials(); }
  String _rupiah(int value) => 'Rp ' + value.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.');

  Future<void> _editMaterial([Map<String, Object?>? material]) async {
    final name = TextEditingController(text: material?['name']?.toString() ?? '');
    final unit = TextEditingController(text: material?['unit']?.toString() ?? '');
    final price = TextEditingController(text: material?['current_unit_price']?.toString() ?? '0');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(material == null ? 'Tambah bahan' : 'Ubah bahan'),
      content: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama bahan', hintText: 'Contoh: Kayu reng'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Nama bahan wajib diisi' : null),
        const SizedBox(height: 12),
        TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan', hintText: 'batang, m, m², lembar'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Satuan wajib diisi' : null),
        const SizedBox(height: 12),
        TextFormField(controller: price, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga per satuan (Rupiah)', prefixText: 'Rp '),
          validator: (v) { final n = int.tryParse((v ?? '').replaceAll('.', '').replaceAll(',', '')); return n == null || n < 0 ? 'Masukkan harga Rupiah yang valid' : null; }),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
        FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Simpan'))],
    ));
    if (saved == true) {
      try {
        await _repository.saveMaterial(id: material?['id'] as int?, name: name.text, unit: unit.text,
          currentUnitPrice: int.parse(price.text.replaceAll('.', '').replaceAll(',', '')));
        if (!mounted) return;
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Master bahan berhasil disimpan.')));
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan bahan: $error')));
      }
    }
    name.dispose(); unit.dispose(); price.dispose();
  }

  Future<void> _deactivate(Map<String, Object?> material) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Nonaktifkan bahan?'),
      content: Text('Bahan "${material['name']}" tidak akan tampil sebagai pilihan aktif. Data transaksi lama tetap tersimpan.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Nonaktifkan'))],
    ));
    if (confirmed != true) return;
    try {
      await _repository.deactivateMaterial(material['id'] as int);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bahan dinonaktifkan.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menonaktifkan bahan: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Master bahan'), actions: [IconButton(tooltip: 'Muat ulang', onPressed: () => setState(_reload), icon: const Icon(Icons.refresh))]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _editMaterial(), icon: const Icon(Icons.add), label: const Text('Tambah bahan')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: _materials, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Tidak dapat memuat master bahan: ${snapshot.error}')));
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Belum ada bahan. Tambahkan bahan dan harga satuannya untuk menyiapkan master biaya packing.', textAlign: TextAlign.center)));
      return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) { final item = rows[index]; final price = (item['current_unit_price'] as num).toInt();
          return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
            title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${_rupiah(price)} / ${item['unit']}'), onTap: () => _editMaterial(item),
            trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _editMaterial(item); if (v == 'deactivate') _deactivate(item); },
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Ubah')), PopupMenuItem(value: 'deactivate', child: Text('Nonaktifkan'))])));
        });
    }),
  );
}
