import 'package:flutter/material.dart';
import '../../core/format/friendly_error.dart';

import '../../data/repositories/packing_transaction_repository.dart';

class PackingCustomerMasterScreen extends StatefulWidget {
  const PackingCustomerMasterScreen({super.key});

  @override
  State<PackingCustomerMasterScreen> createState() =>
      _PackingCustomerMasterScreenState();
}

class _PackingCustomerMasterScreenState
    extends State<PackingCustomerMasterScreen> {
  final _repository = PackingTransactionRepository();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listCustomers(activeOnly: false);
  }

  void _reload() => setState(() {
        _future = _repository.listCustomers(activeOnly: false);
      });

  Future<void> _edit([Map<String, Object?>? customer]) async {
    final name = TextEditingController(text: customer?['name'] as String? ?? '');
    final phone = TextEditingController(text: customer?['phone'] as String? ?? '');
    final address = TextEditingController(text: customer?['address'] as String? ?? '');
    final note = TextEditingController(text: customer?['note'] as String? ?? '');
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer == null ? 'Tambah pelanggan' : 'Edit pelanggan'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nama pelanggan *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama wajib diisi.'
                      : null,
                ),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Nomor telepon'),
                ),
                TextFormField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                TextFormField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Catatan'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await _repository.saveCustomer(
          id: (customer?['id'] as num?)?.toInt(),
          name: name.text,
          phone: phone.text,
          address: address.text,
          note: note.text,
        );
        _reload();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data pelanggan tersimpan.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan pelanggan: ${friendlyError(error)}')),
          );
        }
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
    note.dispose();
  }

  Future<void> _deactivate(Map<String, Object?> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nonaktifkan pelanggan?'),
        content: Text(
          'Pelanggan "${customer['name']}" tidak akan muncul dalam pilihan baru. '
          'Riwayat nota lama tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deactivateCustomer((customer['id'] as num).toInt());
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menonaktifkan pelanggan: ${friendlyError(error)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Master pelanggan'),
          actions: [
            IconButton(
              tooltip: 'Tambah pelanggan',
              onPressed: _edit,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Gagal memuat pelanggan: ${snapshot.error}'));
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Belum ada data pelanggan.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah pelanggan'),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final row = rows[index];
                final active = (row['is_active'] as num).toInt() == 1;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(active ? Icons.person_outline : Icons.person_off_outlined),
                    ),
                    title: Text(row['name'] as String),
                    subtitle: Text([
                      if ((row['phone'] as String).isNotEmpty) row['phone'],
                      if ((row['address'] as String).isNotEmpty) row['address'],
                      if (!active) 'Nonaktif',
                    ].join(' • ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(row);
                        if (value == 'deactivate') _deactivate(row);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        if (active)
                          const PopupMenuItem(
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
        floatingActionButton: FloatingActionButton(
          onPressed: _edit,
          child: const Icon(Icons.add),
        ),
      );
}
