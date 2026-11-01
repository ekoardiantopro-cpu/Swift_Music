# Swift Music 1.3.0 (build 5) — 30 Oktober 2026

## Fitur baru

- **Sleep timer:** tombol bulan di kanan baris perangkat pada full player. Pilih 15/30/60 menit, setelah lagu selesai, atau batalkan. Timer dimiliki audio handler dan tetap aktif saat route player ditutup. Durasi memakai waktu berjalan, termasuk ketika musik dijeda. Timer tidak dipulihkan setelah force-stop/restart karena sesi dibuka dalam keadaan dijeda.
- **Setelah lagu selesai:** handler memakai loop-one sementara sebagai guard agar lagu berikutnya tidak mulai, lalu menjeda ketika event batas lagu diterima dan mengembalikan pengaturan repeat pengguna. Berganti lagu secara manual membatalkan mode ini. Status repeat yang disimpan tetap pilihan pengguna, bukan guard sementara. Tidak mengklaim penghentian sample-accurate.
- **Sesi terakhir:** antrean berurutan, lagu aktif, posisi, volume, status shuffle dan repeat disimpan sebagai satu dokumen preferensi. Checkpoint setiap lima detik hanya saat playing; pause, seek, pengaturan dan edit antrean juga menyimpan. Saat cold start, item yang hilang disaring dan sesi dipulihkan paused tanpa memuat audio/jaringan. Play memuat source secara lazy dengan posisi tersimpan. Urutan acak hasil shuffle dapat dibentuk ulang; urutan logis antrean dipertahankan. Force-stop mendadak dapat kehilangan kemajuan sejak checkpoint terakhir.
- **Cadangan:** Library → ikon impor → Cadangkan / pulihkan koleksi. JSON UTF-8 maksimal 2 MiB berisi playlist, label lagu dan favorit, tanpa audio, path file, izin folder atau lirik. Preview menampilkan jumlah playlist/favorit dan referensi lagu yang belum tersedia. Pemulihan menggabungkan sebagai playlist baru; playlist identik dilewati. File musik identik dicocokkan melalui ID hash ketika diimpor. Nama lagu yang belum tersedia ditampilkan pada playlist.
- **Filter koleksi:** Search → Filter koleksi. Gabungkan folder tersimpan, format lokal, teks artis/album dan durasi. Durasi yang belum diketahui bisa dipilih tersendiri. Baris hasil dibangun secara lazy; pilihan format disiapkan saat panel dibuka. Filter folder juga mencatat membership penyedia yang tidak menyediakan ukuran/mtime; file demikian tetap dibaca ulang saat scan.

## Pengujian kode

Analyzer bersih. Run utama menyelesaikan 48 kasus, disusul tiga pengujian UI lama terisolasi yang lulus. Run utama terputus saat memasuki suite UI pada flutter_tester Windows; hasil tersebut tidak diklaim sebagai satu run penuh yang sukses. Pengujian tambahan yang relevan diulang setelah perubahan dan lulus (11 kasus timer/session, backup/filter dan folder). Regresi tambahan untuk source restore/akhir lagu menambah jumlah kasus menjadi 52.

Kasus baru mencakup penggantian/pembatalan timer dan callback lama, expiry setelah background terlambat, parsing sesi rusak, batas angka, penyaringan lagu hilang, urutan/current ID/posisi, round-trip label cadangan, merge idempotent, cadangan invalid/oversize, kombinasi filter dan wiring sheet timer ke handler bersama. Full player tetap diuji pada beberapa viewport dan teks 200%.

## Batas verifikasi

Pengujian perangkat fisik tetap ditunda sesuai pilihan pengguna untuk memakai emulator. iOS belum dibangun pada lingkungan Windows. Bluetooth, interupsi panggilan, kualitas keluaran suara dan pengukuran baterai belum diverifikasi. Dukungan codec platform tetap mengikuti audit versi sebelumnya. Signing APK lokal masih memakai debug key.

## Pemeriksaan native emulator

| Alur | Hasil |
| --- | --- |
| Simpan sesi dan force-stop/relaunch | Swift Local Test tetap terpilih, indeks antrean 6, posisi 35.072 ms, playing false, buffer 0; decoder belum dimuat |
| Volume sesi | 80% tersimpan dan tampil kembali pada overlay setelah relaunch |
| Timer 15 menit | Sheet menampilkan waktu deadline dan tombol pembatalan; pembatalan berhasil. Expiry durasi diuji melalui scheduler/clock terkontrol pada unit test, bukan menunggu 15 menit nyata |
| Ekspor cadangan | File picker Android menyimpan JSON valid (327 byte, 1 playlist, 0 favorit) di Download dengan nama audit unik |
| Pulihkan cadangan | Playlist audit dihapus melalui aplikasi lalu dipulihkan; playlist kembali memuat Swift Local Test |
| Filter gabungan | Format WAV + maksimal 3 menit menampilkan Swift Local Test (120 detik) |

Pengujian awal timer setelah lagu pada sesi lazy menemukan false boundary ketika source baru dimuat. Guard akhir lagu diperketat: engine harus sudah dimuat, sedang playing, event sebelumnya ready, dan indeks item tetap sama pada loop-one. Regresi membuktikan pemuatan source/pergantian item tidak menghabiskan timer. Setelah perubahan final, analyzer bersih dan 15 kasus terkait timer/player lulus, termasuk regresi tersebut.

## Hasil APK akhir

Release dibangun ulang untuk ARM32/ARM64/x86-64 dan universal; x86-64 terpasang sebagai update (`versionName=1.3.0`, `versionCode=5`). ARM64 sekitar 21,2 MiB; universal sekitar 56,9 MiB. Manifest SHA-256 di bawah mengacu pada build akhir.

Antrean disusun menjadi Midnight Bloom → Swift Local Test → Electric Heart, kemudian aplikasi di-force-stop. Relaunch mempertahankan lagu aktif di indeks 1 dan posisi 114.783 ms tanpa autoplay/buffer. Timer setelah lagu diaktifkan sebelum lazy load. Native session kemudian benar-benar menunjukkan PLAYING pada 114.794 ms. Setelah sekitar lima detik pada batas loop dan aplikasi di background, state menjadi PAUSED pada 18 ms, indeks tetap 1 dan metadata tetap Swift Local Test. Electric Heart tidak mulai. Repeat kembali none dan sheet timer kembali nonaktif. Ini menguji lagu aktif yang bukan item terakhir antrean.

[Laporan state native sebelum/sesudah akhir lagu](reports/sleep-native-1.3.0.json), [timer nonaktif setelah selesai](screenshots/sleep-finished-1.3.0.png).

Cold boot terakhir sempat memunculkan ANR System UI emulator. Memilih Wait memulihkan UI tanpa reset/wipe. Tidak ada entri crash aplikasi pada pemeriksaan Android crash buffer. Keterbatasan lingkungan ini tidak dianggap sebagai bukti performa HP fisik. Volume dikembalikan ke 100%, timer tidak aktif dan aplikasi dibiarkan terbuka setelah pengujian.

Playlist audit dan file cadangan audit dihapus setelah pemeriksaan; file cadangan dihapus hanya setelah SHA-256 cocok dengan salinan host. Sumber folder audit lama yang sudah tidak tersedia dilepas lewat UI. Koleksi pengguna tidak dihapus.

- [Sesi/volume setelah relaunch](screenshots/session-restored-1.3.0.png)
- [Pilihan timer](screenshots/sleep-options-1.3.0.png)
- [Timer aktif](screenshots/sleep-active-1.3.0.png)
- [Ekspor cadangan](screenshots/backup-export-1.3.0.png)
- [Pemulihan cadangan](screenshots/backup-restore-1.3.0.png)
- [Filter gabungan](screenshots/filter-results-1.3.0.png)
- [Ukuran dan SHA-256 APK](reports/apk-sha256-1.3.0.json)
