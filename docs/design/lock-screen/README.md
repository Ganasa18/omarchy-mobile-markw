<!-- SPDX-License-Identifier: MIT -->
# Contoh lock screen

Rancangan statis mengikuti warna panel quick settings: gelap, teks terang,
aksen pastel #9cc2ff. Wallpaper SVG dibuat untuk mockup ini.

- `locked.html`: jam, tanggal, baterai, notifikasi dengan isi disembunyikan,
  dan petunjuk geser ke atas.
- `pin.html`: tampilan setelah geser ke atas, dengan papan angka dan tombol batal.

Semua waktu, persentase, notifikasi, dan digit terisi adalah ilustrasi.
Tombol belum memproses PIN. Jumlah digit implementasi harus mengikuti konfigurasi
pengguna. Tidak ada klaim dukungan sidik jari, panggilan darurat, atau kamera.
Mockup tidak mengubah autentikasi, QML, paket, maupun ponsel.
Target pratinjau: 390 × 844 px, lebar fleksibel hingga 480 px.
