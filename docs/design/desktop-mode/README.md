<!-- SPDX-License-Identifier: MIT -->
# Mode desktop

Mockup statis untuk mode desktop di layar ponsel sendiri. markw tidak punya
keluaran video, jadi mode ini tidak menampilkan ke monitor luar.

- `tile.html` / `tile.png`: tile **Desktop** baru di quick settings (garis
  putus-putus menandai tile baru).
- `desktop.html` / `desktop.png`: layar setelah mode menyala, landscape
  1920 × 1080 dengan scale 1,5 (1280 × 720 logis). Tata letak mengikuti
  rancangan owner (2026-11-11), dengan warna mode ponsel (latar #0b0d11,
  panel #12151b, kontrol #1c2029, aksen #9cc2ff):
  - bar atas tipis berisi logo, label MODE DESKTOP, status, dan jam;
  - jendela mengambang dengan judul dan tombol minimize, maximize, dan tutup;
  - kartu status di kanan atas (layar HP, keyboard, layar sentuh, baterai,
    Atur layar & input);
  - petunjuk shortcut dan dock di bawah (peluncur, aplikasi yang disematkan
    dengan titik untuk yang sedang jalan, pengaturan).

- `desktop-clean.png`: versi yang lebih tenang dengan layout yang sama.
  Kartu status disembunyikan sampai status di bar atas diketuk, tidak ada
  petunjuk shortcut, tidak ada garis antar baris dan antar panel, tombol
  jendela tanpa latar, dock hanya berisi peluncur dan empat aplikasi.
- `desktop-clean-status.png`: versi clean saat kartu status dibuka dari bar
  atas, dengan jendela di belakangnya sedikit diredupkan.

Usulan perilaku:
- Saat menyala: transform layar dan sentuhan landscape, scale 1,5, keyboard
  layar disembunyikan, dan notifikasi singkat berisi shortcut utama.
- Saat mati: semuanya kembali ke keadaan sebelumnya (portrait, scale 2,
  keyboard layar menyala).
- Belum diputuskan: otomatis menyala saat keyboard tersambung, dan arah
  landscape (tombol volume di atas atau di bawah).

Nama, jam, isi terminal, dan halaman web hanyalah ilustrasi. Mockup ini tidak
mengubah QML, paket, maupun ponsel. Render dengan Edge headless
(`--screenshot`, 390 × 844 dan 1280 × 720).

## Semua aplikasi (`launcher.html`, `launcher.png`)

Di mode desktop, daftar semua aplikasi tidak lagi memenuhi layar seperti
laci di ponsel. Daftarnya jadi menu mengambang di atas dock, sekitar 660 × 500:

- kolom cari di atas, langsung bisa diketik dengan keyboard;
- grid enam kolom urut A–Z (ikon dan nama), bisa digulir;
- pintasan di bagian bawah: panah memilih, Enter membuka, Esc menutup;
- desktop di belakangnya sedikit digelapkan, dan tombol peluncur di dock
  menyala.

Tidak ada baris "Terakhir dibuka": dock sudah berisi aplikasi yang terakhir
dibuka.

## Screenshot asli (markw, 2026-11-11, omamobile-shell 0.2.36, English)

Diambil dengan `grim` di HP, pada skala 1,5 (1280 × 720):

- `screenshot-desktop.png`: desktop kosong dengan bar atas dan dock berisi
  aplikasi yang terakhir dibuka;
- `screenshot-launcher.png`: menu semua aplikasi terbuka di atas dock.

Kartu status sengaja tidak difoto karena menampilkan nama perangkat Bluetooth
dan nama Wi-Fi.
