# Packing POS

Flutter POS khusus jasa packing barang, bukan aplikasi transaksi pengiriman/kurir. Aplikasi dirancang offline-first dengan penyimpanan lokal SQLite.

## Fitur

Aplikasi mendukung transaksi ongkos jasa packing manual dan halaman estimasi biaya bahan packing kayu yang terpisah.

- Master pelanggan dan jenis pekerjaan dengan harga standar yang dapat disesuaikan.
- Satu nota dapat berisi banyak pekerjaan; ukuran barang pada transaksi jasa dicatat sebagai informasi.
- Setelah nota disimpan, aplikasi membuka detail nota untuk pembayaran dan cetak.
- Pembayaran penuh, DP, atau bertahap; metode tunai/transfer/QRIS/lainnya; kembalian tunai dihitung otomatis.
- Pengembalian dana pembayaran dicatat dalam ledger refund dengan alasan dan metode pengembalian.
- Pembatalan nota keseluruhan dengan alasan wajib; nota batal dikecualikan dari laporan penjualan.
- Riwayat nota dengan pencarian nomor nota dan pelanggan, serta daftar piutang.
- Laporan penjualan, pembayaran, pengembalian dana, piutang, dan penggunaan bahan.
- Kas harian: saldo awal, pengeluaran, tutup kas, buka kembali dengan alasan, dan riwayat audit snapshot.
- Backup JSON dan restore atomik melalui transaksi SQLite dengan validasi data sebelum pemulihan.
- Printer Bluetooth ESC/POS untuk kertas 58 mm dan 80 mm.
- Estimasi biaya packing kayu tersedia sebagai fitur terpisah. Rumus/model perhitungan yang telah disepakati dipertahankan; tarif dan harga bahan dapat disesuaikan secara lokal.
- Pengaturan tarif estimasi disimpan pada perangkat dan tidak mengubah transaksi lama.

## Database dan keamanan data

- Database lokal: `packing_pos.db`.
- Schema saat ini versi 9.
- Riwayat migrasi: v2 alasan pembatalan; v3 master jenis pekerjaan; v4 nota induk dan pembayaran tingkat nota; v5 kuantitas, harga satuan, dan diskon; v6 master pelanggan; v7 kas harian dan pengeluaran; v8 ledger pengembalian dana; v9 riwayat audit tutup/buka kembali kas.
- Migrasi database dilakukan bertahap melalui `onUpgrade`; jangan menghapus database aplikasi saat memperbarui.
- Restore backup mengganti data lokal setelah konfirmasi. Validasi dilakukan sebelum pemulihan dan proses restore menggunakan transaksi agar kegagalan tidak meninggalkan pemulihan setengah jalan.
- Harga dan nama bahan pada transaksi lama disimpan sebagai snapshot agar perubahan master tidak mengubah catatan historis.
- Tetap buat backup sebelum memasang build baru atau melakukan pemulihan data.

## Printer Bluetooth

1. Pasangkan printer melalui Pengaturan Bluetooth Android.
2. Buka Pengaturan Printer di aplikasi.
3. Pilih printer yang sudah dipasangkan dan ukuran kertas 58 mm atau 80 mm.
4. Hubungkan, simpan, lalu lakukan tes cetak.
5. Dari detail transaksi, gunakan tombol Cetak Nota Bluetooth.

Ketersediaan fitur potong kertas bergantung pada kemampuan printer. Cetak nyata tetap perlu diuji pada model printer yang digunakan.

## Build dan GitHub Releases

Workflow: `.github/workflows/build-release.yml`.

Workflow menggunakan Java 17 dan Flutter 3.47.7, lalu menjalankan `flutter analyze --no-fatal-infos`, `flutter test`, dan build APK debug untuk memvalidasi plugin Android. APK debug dipublikasikan ke GitHub Releases, bukan Actions Artifacts.

APK otomatis dari workflow menggunakan debug keystore sementara GitHub Actions. Sertifikat dapat berbeda antar-build sehingga APK mungkin tidak dapat dipasang sebagai pembaruan di atas aplikasi yang sudah terpasang. Jangan uninstall aplikasi lama atau menghapus data lokal hanya untuk memasang APK uji ini.

Build debug ini bukan APK rilis produksi yang ditandatangani dengan keystore permanen. Jika kelak menyiapkan signing produksi, gunakan keystore aplikasi yang sudah berlaku dan jangan mengganti keystore atau alias/password yang terkait dengannya.

## Branch dan pengembangan

Branch utama saat ini adalah `main`. Workflow CI juga memantau branch fitur yang tercantum pada `.github/workflows/build-release.yml`.
