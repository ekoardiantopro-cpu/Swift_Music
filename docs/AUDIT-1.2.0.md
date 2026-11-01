# Swift Music 1.2.0 (build 3)

## Perubahan

- Metadata native judul, artis, album, genre, durasi dan embedded cover; fallback aman untuk tag yang tidak tersedia. Cover maksimal 768 piksel/JPEG, dibaca di worker native. Migrasi metadata koleksi lama dilakukan satu kali.
- Sumber folder disimpan dengan izin persistable Android SAF / bookmark iOS. Bisa pindai ulang, lepas sumber tanpa menghapus lagu, dan aktif/nonaktifkan deteksi lagu baru. Pemeriksaan tiap menit dan saat resume hanya dimulai ketika aplikasi aktif. Ukuran/waktu modifikasi menjadi fingerprint; penyedia tanpa informasi tersebut dibaca ulang dan tetap dideduplikasi berdasarkan SHA-256.
- Playlist pribadi: buat, ubah nama, hapus, tambah/keluarkan lagu, urutkan dengan drag. Pilihan pengurutan Library disimpan. Menu lagu menyediakan tambah playlist, tambah antrean, dan hapus salinan lokal.
- Penghapusan salinan lokal membersihkan favorit, riwayat, playlist, dan antrean. File sumber tetap ada. Lagu yang sengaja dihapus dikecualikan dari scan otomatis; pilih ulang folder untuk mengimpornya kembali.
- Antrean dapat diurutkan dan lagu dikeluarkan. Pemilihan lagu dari Library memakai ID, bukan posisi pada katalog. Putar playlist mengganti antrean dengan isi playlist.
- Impor TXT/LRC UTF-8/UTF-16 maksimal 256 KiB. LRC mendukung timestamp per baris, beberapa timestamp, pecahan detik dan offset. Baris aktif disorot/digulir sesuai posisi pemutar. Tekan lama baris untuk seek; tap area album tetap berganti visual. Teks biasa tidak diberi sinkronisasi palsu. Animasi mengikuti pengaturan reduced motion.

## Batas dukungan

Tidak ditambahkan dependency codec besar. Decoding tetap menggunakan just_audio/codec platform. Daftar ekstensi bukan jaminan semua encoding dapat diputar. Hasil sampel codec Android sebelumnya ada di [audit 1.1.0](AUDIT-1.1.0.md): 10/12 sampel berhasil; AIFF PCM dan CAF ALAC tidak berhasil pada emulator uji. Tidak mengklaim dukungan WMA/APE/DSD/MIDI/DRM.

Visualizer dekoratif bukan pengukuran FFT audio. Device picker tetap simulasi UI. Metadata lirik tertanam tidak dijamin tersedia dari API native; gunakan impor LRC/TXT atau editor. Belum ada pengambilan lirik dari layanan internet.

iOS disiapkan dalam source/template tetapi belum dikompilasi atau diuji karena lingkungan Windows. Uji Android fisik, interupsi panggilan/Bluetooth dan pengukuran baterai tetap diperlukan. Paket release lokal masih memakai debug signing key.

## Validasi

Analyzer bersih. Total 42 tes lulus melintasi run suite dan pengulangan terisolasi, termasuk persistence/pengeditan playlist, parser LRC, highlight/seek lirik, metadata/cover dan penghapusan aman, pemulihan sumber folder/fingerprint/new-file scan dan pengecualian lagu yang dihapus. Sebagian run Windows flutter_tester terputus sebelum selesai; kasus tersebut dijalankan ulang terisolasi setelah daemon Gradle dihentikan untuk membebaskan RAM. Hasil ini tidak diklaim sebagai satu run penuh yang bebas gangguan.

Uji release pada emulator SwiftMusic_API36 (540×960/210 dpi) menggunakan audio sintetis dan cover ikon milik proyek:

| Alur | Bukti hasil |
| --- | --- |
| Impor MP3 dengan tag dan cover | Library menampilkan Swift Tagged Test / Swift Test Artist / cover; media session menampilkan Swift Test Album, durasi sekitar 90 detik |
| Playlist pribadi | Buat, tambah lagu melalui pemilih dan menu lagu, putar 1 lalu 2 lagu; playlist tetap tersedia setelah force-stop/relaunch |
| Izin folder persisten | Pindai ulang setelah force-stop tanpa picker/izin ulang; menemukan 1 FLAC baru dan melewati 1 duplikat |
| Reorder antrean | Geser handle: item aktif berpindah indeks 0→1; judul tetap Swift Tagged Test dan posisi lanjut 68.774 ms |
| Hapus item antrean aktif | Pemutar berpindah ke Swift New Track, tanpa error native |
| Impor LRC | Pemilih Files membaca SwiftTimed.lrc UTF-8, menyorot baris akhir pada 1:18 |
| Tekan lama baris LRC | Seek tepat 20.000 ms, state PAUSED, highlight berubah ke baris [00:20] |
| Hapus salinan Library | Playlist berkurang 2→1 lagu; file FLAC sumber masih ada (1.099.048 byte). Rescan: 0 ditambahkan, 2 duplikat dilewati; lagu yang dihapus tidak kembali |

Uji penghapusan menemukan mini-player mempertahankan item lama ketika handler mengirim null. `PlayerState.copyWith` kini dapat mengosongkan item; Cubit mereset posisi/durasi saat antrean kosong. Tes regresi dan delapan tes player lainnya lulus setelah perbaikan.

APK akhir dibangun ulang untuk ARM32/ARM64/x86-64 serta universal, lalu x86-64 dipasang ulang dengan sukses (`versionCode=3`, `versionName=1.2.0`). Mengeluarkan seluruh tujuh item dari antrean awal dan kembali ke Home menyembunyikan mini-player: [hasil antrean kosong](screenshots/empty-queue-1.2.0.png).

Data lagu sintetis yang diimpor, playlist audit, dan sumber folder audit dilepas melalui aplikasi setelah pengujian. Koleksi yang sudah ada sebelum audit dipertahankan. Tidak ditemukan entri Android crash selama pemeriksaan runtime. Kualitas keluaran suara/baterai tidak diukur.

- [Library dengan tag/cover](screenshots/library-1.2.0.png)
- [Playlist dipulihkan setelah restart](screenshots/library-restored-1.2.0.png)
- [Antrean setelah reorder](screenshots/queue-1.2.0.png)
- [LRC setelah seek](screenshots/lyrics-1.2.0.png)
- [Ukuran dan SHA-256 APK](reports/apk-sha256-1.2.0.json)
