<!-- SPDX-License-Identifier: MIT -->
# Rancangan alat developer: SSH Wi-Fi dan flash

Mockup visual statis, belum terhubung ke perangkat. Semua nilai contoh;
alamat memakai blok dokumentasi 192.0.2.0/24.

- `wifi-ssh.html`: membuka SSH di Wi-Fi saat perlu, dengan mati otomatis,
  alamat, perintah yang bisa disalin, dan sesi aktif.
- `esp-flash.html`: antarmuka PlatformIO Core untuk satu proyek: env, port,
  build/upload/monitor/clean, progres, dan log (output atau serial).

Gaya: monokrom, monospace, baris rata dengan garis tipis, tanpa kartu,
chip, atau warna aksen. Yang aktif ditandai dengan warna terbalik.
Radius: wadah luar 8 px, komponen di dalamnya 4 px (radius luar dikurangi
jarak 4 px, jadi lengkungannya sejajar); kontrol kecil 6 px dengan isi 3 px.
Target 390 px, sampai 480 px.

Tidak ada perubahan pada QML, paket, konfigurasi perangkat, atau hardware.
