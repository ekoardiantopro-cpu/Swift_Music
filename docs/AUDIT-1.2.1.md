# Swift Music 1.2.1 (build 4) — 30 Oktober 2026

## Perbaikan aksesibilitas

Pengujian emulator lanjutan menemukan area album menyusut terlalu jauh pada teks 200%. Judul Lirik terbungkus dan hampir seluruh ruang baca habis untuk header. Pada teks besar, player kini menggunakan lebar yang tersedia untuk area album/lirik dan mengizinkan halaman digulir. Judul panel dibatasi satu baris. Ukuran teks pilihan pengguna tetap dihormati.

Analyzer bersih. Tes regresi khusus pada viewport 320×640 dan teks 200% lulus: area album minimal 280 piksel logis, viewport isi lirik lebih dari 90 piksel, tanpa layout exception. Beberapa run flutter_tester Windows terputus sebelum selesai seperti pada audit sebelumnya; run diagnostik terisolasi berhasil. Hasil ini tidak berarti seluruh suite dijalankan ulang dalam satu run pada versi ini. Versi 1.2.0 sebelumnya memiliki 42 kasus yang telah lulus melintasi run suite dan kasus terisolasi.

## Pengujian media session Android

Emulator SwiftMusic_API36 / Android 36, lagu WAV lokal Swift Local Test. Semua perubahan pengaturan font/rotasi dipulihkan setelah pengujian.

| Pemeriksaan | Hasil |
| --- | --- |
| Tekan Home saat musik berjalan | PLAYING di background |
| Kontrol media background | PAUSED pada 42.106 ms; PLAYING kembali pada 42.107 ms |
| Layar dimatikan | State tetap PLAYING |
| Transport play langsung saat layar mati | PLAYING pada 49.802 ms |
| Transport pause langsung saat layar mati | PAUSED pada 57.390 ms; Android `mWakefulness=Asleep` |
| Landscape, teks 150% | Layout dua kolom, kontrol utama tetap terlihat |

Perintah ADB keyevent PLAY/PAUSE diperlakukan audio_service sebagai klik media/toggle; ia tidak dapat dijadikan bukti aksi pause yang idempotent. Pemeriksaan layar mati diulang melalui `cmd media_session monitor media-session` dengan perintah transport `play` dan `pause`. Source plugin lokal `AudioService.java` menjelaskan pemetaan keycode tersebut; tidak diperlukan perubahan pemutar untuk hasil ini.

Data awal keyevent dipertahankan dalam [laporan lifecycle](reports/emulator-lifecycle-1.2.0.json) agar hasil yang tidak konsisten tidak disembunyikan. Pemeriksaan transport langsung menjadi acuan untuk kontrol saat layar mati.

[Hasil transport langsung saat layar mati](reports/emulator-transport-screen-off-1.2.1.json) mencatat state Play dan Pause yang terverifikasi.

- [Landscape teks 150%](screenshots/landscape-large-text-1.2.0.png)
- [Masalah teks 200% sebelum perbaikan](screenshots/portrait-text-200-1.2.0.png)
- [Lirik terbaca pada teks 200% setelah perbaikan](screenshots/portrait-text-200-1.2.1.png)
- [Kontrol dijangkau dengan scroll pada teks 200%](screenshots/controls-text-200-1.2.1.png)

## Hasil APK akhir

Build release ARM32/ARM64/x86-64 dan universal berhasil. x86-64 terpasang melalui update tanpa menghapus data, dengan `versionName=1.2.1`, `versionCode=4`. [Ukuran dan SHA-256](reports/apk-sha256-1.2.1.json). ARM64 sekitar 21,1 MiB, universal sekitar 56,6 MiB.

Uji native teks 200% menunjukkan header Lirik dan isi terbaca. Kontrol utama dapat dijangkau dengan scroll. Back pertama saat overlay volume terbuka menutup overlay dan mempertahankan full player; Back berikutnya kembali ke Home; Back di root memindahkan aplikasi ke background (fokus Launcher). Aplikasi kemudian dibuka kembali. Pengaturan font kembali 1.0, auto-rotation 1 dan user_rotation 1 sesuai kondisi awal. Pemeriksaan crash buffer Android tidak menemukan entri crash.

- [Volume terbuka di kiri](screenshots/volume-back-1.2.1.png)
- [Back menutup volume tanpa menutup player](screenshots/back-closes-volume-1.2.1.png)

Emulator tidak membuktikan kualitas suara, konsumsi baterai perangkat fisik, Bluetooth, interupsi panggilan atau keamanan lockscreen dengan PIN. iOS belum dibangun/diuji di lingkungan Windows.
