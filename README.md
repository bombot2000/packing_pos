# Packing POS

Flutter POS khusus jasa packing barang, bukan aplikasi transaksi pengiriman/kurir. Aplikasi dirancang offline-first dengan penyimpanan lokal SQLite.

## Fitur

Aplikasi ini mencatat ongkos jasa packing secara manual (bukan mesin hitung bahan kayu).

- Master jenis pekerjaan dengan harga standar yang dapat diubah saat transaksi.
- Satu nota berisi banyak pekerjaan; ukuran barang hanya informasi.
- Setelah nota disimpan, aplikasi langsung membuka detail nota untuk pembayaran dan cetak.
- Pembayaran penuh, DP, atau bertahap; metode tunai/transfer/QRIS/lainnya; kembalian tunai dihitung otomatis.
- Pembatalan nota keseluruhan dengan alasan wajib (nota batal tidak masuk laporan).
- Riwayat nota dengan pencarian nomor nota dan pelanggan.
- Laporan semua waktu, harian, bulanan: penjualan dan piutang mengikuti tanggal nota, uang masuk mengikuti tanggal pembayaran.
- Backup JSON dan restore atomik melalui transaksi SQLite.
- Printer Bluetooth ESC/POS untuk kertas 58 mm dan 80 mm.
- APK rilis dipublikasikan ke GitHub Releases, bukan Actions Artifacts.
- Master bahan masih tersimpan sebagai arsip; tidak dipakai dalam alur transaksi.

## Database dan keamanan data

- Database lokal: `packing_pos.db`.
- Schema saat ini versi 4 (v2: alasan pembatalan, v3: master jenis pekerjaan, v4: nota induk dan pembayaran tingkat nota).
- Migrasi tidak menghapus tabel atau transaksi.
- Restore backup mengganti data lokal yang ada setelah konfirmasi. File yang tidak valid dibatalkan seluruhnya oleh transaksi SQLite.
- Harga dan nama bahan pada transaksi lama disimpan sebagai snapshot.

## Printer Bluetooth

1. Pasangkan printer melalui Pengaturan Bluetooth Android.
2. Buka Pengaturan Printer di aplikasi.
3. Pilih printer yang sudah dipasangkan dan ukuran kertas 58 mm atau 80 mm.
4. Hubungkan, simpan, lalu lakukan tes cetak.
5. Dari detail transaksi, gunakan tombol Cetak Nota Bluetooth.

Ketersediaan fitur potong kertas bergantung pada kemampuan printer. Cetak nyata tetap perlu diuji pada model printer yang digunakan.

## Build dan GitHub Releases

Workflow: `.github/workflows/build-release.yml`.

Setiap push ke `feature/packing-calculation-engine` menjalankan `flutter analyze --no-fatal-infos` dan `flutter test`. APK release hanya dibangun dan dipublikasikan jika keystore permanen tersedia.

Tambahkan empat GitHub Actions Secrets berikut sebelum membuat APK rilis:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD` (atau `ANDROID_KEYSTORE_PASSWORD`)

Gunakan keystore permanen yang memang akan dipakai untuk aplikasi ini. Jangan mengganti keystore pada build berikutnya; tanda tangan yang berubah dapat membuat Android menolak update aplikasi dan memaksa uninstall.

## Branch kerja

Pengembangan aktif dilakukan di `feature/packing-calculation-engine`. Branch `main` tidak diubah selama pengerjaan fitur.
