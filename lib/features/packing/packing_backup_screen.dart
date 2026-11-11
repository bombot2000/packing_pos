import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/packing_backup_validator.dart';
import '../../data/repositories/packing_transaction_repository.dart';

class PackingBackupScreen extends StatefulWidget {
  const PackingBackupScreen({super.key});

  @override
  State<PackingBackupScreen> createState() => _PackingBackupScreenState();
}

class _PackingBackupScreenState extends State<PackingBackupScreen> {
  final _repository = PackingTransactionRepository();
  bool _busy = false;

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final backup = await _repository.exportBackup();
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/packing_pos_backup_$stamp.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(backup),
        flush: true,
      );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'Backup data Packing POS',
        subject: 'Backup Packing POS',
      );
    } catch (error) {
      _message('Gagal membuat backup: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    try {
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Isi file tidak dapat dibaca.');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Struktur file backup tidak valid.');
      }
      // Validate before showing the destructive confirmation, then show the
      // user exactly which backup and how much data will replace local records.
      final validated = PackingBackupValidator.validate(decoded);
      final createdAt = decoded['createdAt'] is String
          ? decoded['createdAt'] as String
          : 'Tidak tercatat';
      int count(String table) => validated[table]?.length ?? 0;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pulihkan backup?'),
          content: SingleChildScrollView(
            child: Text(
              'File: ${file.name}\\n'
              'Tanggal backup: $createdAt\\n'
              'Versi format: ${decoded['version']}\\n\\n'
              'Data yang akan dipulihkan:\\n'
              '• Nota: ${count('packing_receipts')}\\n'
              '• Pekerjaan: ${count('packing_transactions')}\\n'
              '• Riwayat pembayaran: ${count('receipt_payments') + count('transaction_payments')}\\n'
              '• Pelanggan: ${count('customers')}\\n'
              '• Master bahan: ${count('materials')}\\n'
              '• Sesi kas: ${count('cash_sessions')}\\n'
              '• Pengeluaran kas: ${count('cash_expenses')}\\n\\n'
              'Restore akan mengganti data lokal dengan isi file ini. '
              'Buat backup terbaru terlebih dahulu jika data sekarang masih diperlukan.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Pulihkan data'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      await _repository.restoreBackup(decoded);
      _message('Backup berhasil dipulihkan.');
    } catch (error) {
      _message('Backup tidak dapat dipulihkan: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup dan restore')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.backup_outlined, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Backup seluruh data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mencakup transaksi, rincian bahan dan harga snapshot, pembayaran, master bahan, master jenis pekerjaan dan harga jasa, serta pengaturan. File disimpan sebagai JSON dan dapat dibagikan ke penyimpanan lain.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _exportBackup,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Buat dan bagikan backup'),
            ),
          ]),
        )),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.restore, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Pulihkan dari file backup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pilih file JSON hasil backup Packing POS. Format dan semua tabel diperiksa sebelum data diganti. Jika proses database gagal, seluruh perubahan pemulihan dibatalkan.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restoreBackup,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Pilih file backup'),
            ),
          ]),
        )),
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: 16),
        const Text(
          'Penting: simpan salinan backup di luar HP secara berkala. Restore mengganti data lokal yang ada; proses ini tidak menghapus aplikasi.',
        ),
      ],
    ),
  );
}
