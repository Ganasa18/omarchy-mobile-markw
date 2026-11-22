<!-- SPDX-License-Identifier: MIT -->
# Rancangan panel pengaturan cepat

Mockup visual statis, belum terhubung ke perangkat. Semua nilai adalah contoh.
Sumber visual: tema `omamobile-clean-dark` dan panel quick settings milik proyek.

- `collapsed.html`: tarik dari tepi atas untuk membuka empat kontrol utama dan kecerahan.
- `expanded.html`: tarik panel lagi untuk membuka delapan kontrol, volume, dan edit tata letak.

Warna: latar #0b0d11, panel #12151b, kontrol #1c2029, teks #e8ebf1,
aksen aktif #9cc2ff. Font mockup Segoe UI; implementasi mengikuti font shell.
Target rancangan 390 px; lebar mengikuti perangkat sampai 480 px.

Pola interaksi yang diusulkan:
- Geser ke atas untuk menutup; Escape juga menutup.
- Ketuk badan kontrol untuk toggle; chevron atau tekan lama membuka detail Wi-Fi/Bluetooth.
- Kontrol aktif memakai warna aksen dan label status; warna bukan satu-satunya penanda.
- Fitur tanpa backend memakai status “Tidak tersedia” dan tidak dapat diaktifkan.
- Pending: tampilkan “Menghubungkan…”; gagal: kembalikan status aktual dan tampilkan pesan lokal.
- Slider kecerahan tampil di kedua mode; volume tampil di mode penuh.
- Edit memungkinkan urutan kontrol disesuaikan; kontrol tambahan di halaman berikutnya.
- Area sentuh minimal 44 px; saat diimplementasikan, tambahkan nama aksesibel dan fokus keyboard.
- Panel mengikuti jari; usulan snap masuk 240 ms dan keluar 180 ms, tanpa animasi dekoratif.
- Tema harus mengikuti tema shell; mockup ini memperlihatkan varian gelap terlebih dahulu.

Inventaris: P0 jam/tanggal/baterai, empat kontrol utama, kecerahan;
P1 kontrol tambahan, volume, detail koneksi, edit; P2 halaman pengaturan lengkap.
Mockup bukan konfirmasi bahwa fitur perangkat tersedia.

Pilihan komposisi: panel dua tahap ini menjaga akses singkat sekaligus menyediakan kontrol penuh.
Alternatif panel penuh sekali tarik mempercepat akses ke semua kontrol tetapi menutupi aplikasi;
alternatif daftar vertikal memberi ruang label lebih panjang tetapi memerlukan lebih banyak scroll.

Tidak ada perubahan pada QML, paket, konfigurasi perangkat, atau hardware.
