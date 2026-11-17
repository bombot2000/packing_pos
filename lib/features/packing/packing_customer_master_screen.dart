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
    final values = await showDialog<_CustomerFormValues>(
      context: context,
      builder: (_) => _CustomerEditDialog(customer: customer),
    );
    if (values == null || !mounted) return;

    try {
      await _repository.saveCustomer(
        id: (customer?['id'] as num?)?.toInt(),
        name: values.name,
        phone: values.phone,
        address: values.address,
        note: values.note,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data pelanggan tersimpan.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pelanggan: ${friendlyError(error)}')),
        );
      }
    }
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
      if (mounted) _reload();
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
              return Center(child: Text('Gagal memuat pelanggan: ${friendlyError(snapshot.error!)}'));
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

/// The dialog owns its controllers so they are disposed with the dialog
/// subtree, not immediately when showDialog completes during reverse animation.
class _CustomerEditDialog extends StatefulWidget {
  const _CustomerEditDialog({this.customer});

  final Map<String, Object?>? customer;

  @override
  State<_CustomerEditDialog> createState() => _CustomerEditDialogState();
}

class _CustomerEditDialogState extends State<_CustomerEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _note;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _name = TextEditingController(text: customer?['name'] as String? ?? '');
    _phone = TextEditingController(text: customer?['phone'] as String? ?? '');
    _address = TextEditingController(text: customer?['address'] as String? ?? '');
    _note = TextEditingController(text: customer?['note'] as String? ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.customer == null ? 'Tambah pelanggan' : 'Edit pelanggan'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nama pelanggan *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama wajib diisi.'
                      : null,
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Nomor telepon'),
                ),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Catatan'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(
                  context,
                  _CustomerFormValues(
                    name: _name.text,
                    phone: _phone.text,
                    address: _address.text,
                    note: _note.text,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      );
}

class _CustomerFormValues {
  const _CustomerFormValues({
    required this.name,
    required this.phone,
    required this.address,
    required this.note,
  });

  final String name;
  final String phone;
  final String address;
  final String note;
}
