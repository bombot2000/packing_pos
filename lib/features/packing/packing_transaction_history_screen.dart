import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/format/rupiah.dart';
import '../../data/repositories/packing_transaction_repository.dart';
import 'packing_receipt_detail_screen.dart';
import 'packing_receivables_screen.dart';

class PackingTransactionHistoryScreen extends StatefulWidget {
  const PackingTransactionHistoryScreen({super.key});

  @override
  State<PackingTransactionHistoryScreen> createState() =>
      _PackingTransactionHistoryScreenState();
}

class _PackingTransactionHistoryScreenState
    extends State<PackingTransactionHistoryScreen> {
  static const _pageSize = 30;
  final _repo = PackingTransactionRepository();
  final _search = TextEditingController();
  Timer? _searchTimer;
  String _status = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  int _page = 0;
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> _load() => _repo.searchReceipts(
        query: _search.text,
        status: _status,
        startDate: _startDate,
        endDate: _endDate,
        limit: _pageSize,
        offset: _page * _pageSize,
      );

  void _refresh({bool resetPage = false}) {
    if (resetPage) _page = 0;
    setState(() => _future = _load());
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _refresh(resetPage: true);
    });
  }

  void _clearFilters() {
    _searchTimer?.cancel();
    _search.clear();
    setState(() {
      _status = 'all';
      _startDate = null;
      _endDate = null;
      _page = 0;
      _future = _load();
    });
  }

  bool get _hasFilters => _search.text.trim().isNotEmpty || _status != 'all' || _startDate != null || _endDate != null;

  String _money(Object? value) => formatRupiah(value);

  String _statusLabel(Map<String, Object?> row) {
    if (row['status'] == 'completed') return 'Lunas';
    if (row['status'] == 'cancelled') return 'Dibatalkan';
    return ((row['paid_amount'] as num?)?.toInt() ?? 0) > 0
        ? 'Dibayar sebagian'
        : 'Belum dibayar';
  }

  String _dateLabel(DateTime? value) => value == null
      ? 'Semua'
      : '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _chooseDate({required bool start}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (start ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Pilih tanggal awal' : 'Pilih tanggal akhir',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
        if (_endDate != null && _startDate!.isAfter(_endDate!)) {
          _endDate = selected;
        }
      } else {
        _endDate = selected;
        if (_startDate != null && _endDate!.isBefore(_startDate!)) {
          _startDate = selected;
        }
      }
      _page = 0;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Riwayat nota'),
          actions: [
            IconButton(
              tooltip: 'Daftar piutang',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PackingReceivablesScreen(),
              )),
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: () => _refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Cari nota, pelanggan, no. pekerjaan atau barang...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchTimer?.cancel();
                            _search.clear();
                            _refresh(resetPage: true);
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status nota',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua status')),
                  DropdownMenuItem(value: 'unpaid', child: Text('Belum dibayar')),
                  DropdownMenuItem(value: 'partial', child: Text('Dibayar sebagian')),
                  DropdownMenuItem(value: 'completed', child: Text('Lunas')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _status = value;
                    _page = 0;
                    _future = _load();
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chooseDate(start: true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text('Dari: ${_dateLabel(_startDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chooseDate(start: false),
                      icon: const Icon(Icons.event, size: 16),
                      label: Text('Sampai: ${_dateLabel(_endDate)}'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hapus filter tanggal',
                    onPressed: _startDate == null && _endDate == null
                        ? null
                        : () => setState(() {
                              _startDate = null;
                              _endDate = null;
                              _page = 0;
                              _future = _load();
                            }),
                    icon: const Icon(Icons.filter_alt_off),
                  ),
                ],
              ),
            ),
            if (_hasFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('Hapus semua filter'),
                  ),
                ),
              ),
            Expanded(
              child: FutureBuilder<Map<String, Object?>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Gagal membaca nota: ${snapshot.error}'));
                  }
                  final result = snapshot.data ?? const <String, Object?>{};
                  final rows = (result['rows'] as List<Map<String, Object?>>?) ?? [];
                  final total = (result['total'] as int?) ?? 0;
                  final pageCount = total == 0 ? 1 : (total / _pageSize).ceil();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Menampilkan ${total == 0 ? 0 : _page * _pageSize + 1}'
                              '-${(_page * _pageSize + rows.length)} dari $total nota'),
                        ),
                      ),
                      Expanded(
                        child: rows.isEmpty
                            ? Center(
                                child: Text(total == 0
                                    ? 'Belum ada nota yang sesuai filter.'
                                    : 'Tidak ada nota pada halaman ini.'),
                              )
                            : RefreshIndicator(
                                onRefresh: () async => _refresh(),
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    final amount = (row['total_amount'] as num).toInt();
                                    final paid = (row['paid_amount'] as num).toInt();
                                    return Card(
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          child: Icon(Icons.receipt_long),
                                        ),
                                        title: Text(
                                          row['receipt_no'] as String,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if ((row['customer_name'] as String).isNotEmpty)
                                              Text(row['customer_name'] as String),
                                            Text('${row['job_count'] ?? 0} pekerjaan • ${_statusLabel(row)}'),
                                            Text('${_statusLabel(row)} • Total ${_money(amount)}'),
                                            Text('Pembayaran ${_money(paid)} • Sisa ${_money(amount - paid)}'),
                                            Text((row['created_at'] as String).replaceFirst('T', ' ')),
                                          ],
                                        ),
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () async {
                                          await Navigator.of(context).push(MaterialPageRoute(
                                            builder: (_) => PackingReceiptDetailScreen(
                                              receiptId: (row['id'] as num).toInt(),
                                            ),
                                          ));
                                          if (mounted) _refresh();
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Halaman sebelumnya',
                              onPressed: _page > 0
                                  ? () => setState(() {
                                        _page--;
                                        _future = _load();
                                      })
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('Halaman ${_page + 1} dari $pageCount'),
                            IconButton(
                              tooltip: 'Halaman berikutnya',
                              onPressed: _page + 1 < pageCount
                                  ? () => setState(() {
                                        _page++;
                                        _future = _load();
                                      })
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
}
