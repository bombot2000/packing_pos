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
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _materials = _repository.listMaterials();
  }

  String _rupiah(int value) {
    final formatted = value.toString().replaceAllMapped(
      RegExp(r'(?<=\\d)(?=(\\d{3})+(?!\\d))'),
      (_) => '.',
    );
    return 'Rp $formatted';
  }

  Future<void> _editMaterial([Map<String, Object?>? material]) async {
    // Use a normal page route instead of DialogRoute. Android Back now pops
    // an ordinary page, avoiding the dialog-overlay teardown path.
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => _MaterialEditorScreen(material: material),
      ),
    );

    if (result == null || !mounted) return;

    try {
      await _repository.saveMaterial(
        id: material?['id'] as int?,
        name: result['name']! as String,
        unit: result['unit']! as String,
        currentUnitPrice: result['price']! as int,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master bahan berhasil disimpan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan bahan: $error')),
      );
    }
  }

  Future<void> _deactivate(Map<String, Object?> material) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Nonaktifkan bahan?'),
            content: Text(
              'Bahan "${material['name']}" tidak akan tampil sebagai pilihan aktif. Data transaksi lama tetap tersimpan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Nonaktifkan'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      await _repository.deactivateMaterial(material['id'] as int);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bahan dinonaktifkan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menonaktifkan bahan: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Master bahan'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _editMaterial,
          icon: const Icon(Icons.add),
          label: const Text('Tambah bahan'),
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: _materials,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Tidak dapat memuat master bahan: ${snapshot.error}',
                  ),
                ),
              );
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Belum ada bahan. Tambahkan bahan dan harga satuannya untuk menyiapkan master biaya packing.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = rows[index];
                final price = (item['current_unit_price'] as num).toInt();
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_outlined),
                    ),
                    title: Text(
                      item['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${_rupiah(price)} / ${item['unit']}'),
                    onTap: () => _editMaterial(item),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editMaterial(item);
                        if (value == 'deactivate') _deactivate(item);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Ubah')),
                        PopupMenuItem(
                          value: 'deactivate',
                          child: Text('Nonaktifkan'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class _MaterialEditorScreen extends StatefulWidget {
  const _MaterialEditorScreen({required this.material});

  final Map<String, Object?>? material;

  @override
  State<_MaterialEditorScreen> createState() => _MaterialEditorScreenState();
}

class _MaterialEditorScreenState extends State<_MaterialEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _price;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.material?['name']?.toString() ?? '',
    );
    _unit = TextEditingController(
      text: widget.material?['unit']?.toString() ?? '',
    );
    _price = TextEditingController(
      text: widget.material?['current_unit_price']?.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final parsedPrice = int.tryParse(
      _price.text.replaceAll('.', '').replaceAll(',', '').trim(),
    );

    if (_name.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Nama bahan wajib diisi.');
      return;
    }
    if (_unit.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Satuan wajib diisi.');
      return;
    }
    if (parsedPrice == null || parsedPrice < 0) {
      setState(() => _errorMessage = 'Masukkan harga Rupiah yang valid.');
      return;
    }

    Navigator.of(context).pop<Map<String, Object?>>({
      'name': _name.text.trim(),
      'unit': _unit.text.trim(),
      'price': parsedPrice,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.material != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Ubah bahan' : 'Tambah bahan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama bahan',
              hintText: 'Contoh: Kayu reng',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _unit,
            decoration: const InputDecoration(
              labelText: 'Satuan',
              hintText: 'batang, m, m², lembar',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Harga per satuan (Rupiah)',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan bahan'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }
}
