# Packing POS

Flutter POS khusus jasa packing barang, bukan aplikasi transaksi pengiriman/kurir. Aplikasi dirancang offline-first dengan penyimpanan lokal SQLite.

## Fitur yang sudah tersedia di branch fitur

- Transaksi packing berdasarkan panjang, lebar, dan tinggi barang.
- Enam bidang dikonfigurasi independen: atas, bawah, depan, belakang, kiri, dan kanan.
- Konstruksi bidang: bilah kayu terbuka, papan tertutup, atau tidak digunakan.
- Celah bilah tetap; sisa lebar tepi dilaporkan dan celah tidak direnggangkan.
- Estimasi rangka 8 sudut: empat tiang, empat rel arah panjang, dan empat rel arah lebar. Panjang potong dapat disesuaikan.
- Daftar potongan kayu dan optimasi jumlah batang berbasis first-fit decreasing dengan allowance mata gergaji.
- Nesting papan lembar berbasis guillotine best-short-side-fit dengan rotasi.
- Dua mode harga pembelian: kayu per meter atau per batang; papan per m² atau per lembar.
- Master bahan dengan snapshot nama, satuan, dan harga saat transaksi.
- Jumlah aktual dapat disesuaikan dengan alasan wajib jika berbeda dari hasil hitung.
- Nota transaksi, pembayaran bertahap, pembatalan dengan alasan, riwayat transaksi.
- Laporan semua waktu, harian, dan bulanan.
- Backup JSON dan restore atomik melalui transaksi SQLite.
- Printer Bluetooth ESC/POS untuk kertas 58 mm dan 80 mm.
- APK rilis dipublikasikan ke GitHub Releases, bukan Actions Artifacts.

## Catatan perhitungan

Rangka 8 sudut saat ini memakai model 4 tiang + 4 rel panjang + 4 rel lebar. Ukuran potong default mengikuti dimensi barang; ubah ukuran potong jika sambungan atau orientasi penampang kayu mengharuskan panjang berbeda.

Optimasi pemotongan kayu dan nesting papan adalah heuristik praktis, bukan jaminan jumlah stok atau limbah minimum matematis. Kerf dimasukkan sebagai allowance. Pastikan ukuran lembar/stok, arah serat, sambungan, dan ukuran potong sesuai bahan nyata sebelum pembelian.

Mode harga per batang/lembar menggunakan jumlah pembelian dari rencana potong. Mode harga per meter/m² memakai jumlah teoritis atau jumlah aktual yang disesuaikan. Jangan mencampur kedua mode pada bahan yang sama karena akan menghitung biaya ganda.

## Database dan keamanan data

- Database lokal: `packing_pos.db`.
- Schema saat ini versi 2.
- Migrasi versi 1 ke 2 hanya menambahkan kolom alasan pembatalan; tidak menghapus tabel atau transaksi.
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
- `ANDROID_STORE_PASSWORD`

Gunakan keystore permanen yang memang akan dipakai untuk aplikasi ini. Jangan mengganti keystore pada build berikutnya; tanda tangan yang berubah dapat membuat Android menolak update aplikasi dan memaksa uninstall.

## Branch kerja

Pengembangan aktif dilakukan di `feature/packing-calculation-engine`. Branch `main` tidak diubah selama pengerjaan fitur.
