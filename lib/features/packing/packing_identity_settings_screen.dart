import 'package:flutter/material.dart';
import '../../core/format/friendly_error.dart';

import '../../data/repositories/packing_identity_repository.dart';

class PackingIdentitySettingsScreen extends StatefulWidget {
  const PackingIdentitySettingsScreen({super.key});

  @override
  State<PackingIdentitySettingsScreen> createState() =>
      _PackingIdentitySettingsScreenState();
}

class _PackingIdentitySettingsScreenState
    extends State<PackingIdentitySettingsScreen> {
  final _repository = PackingIdentityRepository();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await _repository.getSettings();
      if (!mounted) return;
      _name.text = values['business_name'] ?? 'Packing POS';
      _address.text = values['business_address'] ?? '';
      _phone.text = values['business_phone'] ?? '';
    } catch (error) {
      _message('Gagal memuat pengaturan: ${friendlyError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repository.saveSettings(
        businessName: _name.text,
        address: _address.text,
        phone: _phone.text,
      );
      if (!mounted) return;
      _message('Identitas usaha berhasil disimpan.');
      Navigator.of(context).pop(true);
    } catch (error) {
      _message(friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Identitas aplikasi dan nota')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.storefront_outlined, size: 36),
                  const SizedBox(height: 8),
                  Text('Nama ini akan tampil pada halaman utama dan kepala nota cetak.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama usaha / judul Packing POS',
                      hintText: 'Contoh: BOMBOT PACKING',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _address,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Alamat usaha (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    maxLength: 30,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor telepon (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Menyimpan...' : 'Simpan identitas'),
                    ),
                  ),
                ]),
              )),
              const SizedBox(height: 8),
              const Text('Pengaturan ini tersimpan di perangkat dan ikut dalam file backup. Tidak mengubah nama ikon aplikasi Android.'),
            ],
          ),
  );
}
