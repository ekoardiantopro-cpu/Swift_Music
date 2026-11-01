# Audit Swift Music 1.1.0 (build 2)

Pemeriksaan 29 Oktober 2026. Android diuji pada emulator Google APIs Android 36, 540×960 / 210 dpi. iOS memiliki implementasi pemilih folder dengan security-scoped URL, tetapi build/runtime iOS belum diverifikasi karena lingkungan kerja Windows.

## Folder musik

Library menyediakan **Pilih folder musik**, **Pilih lagu lokal**, dan informasi format. Header impor juga membuka pilihan folder/file. Android menggunakan ACTION_OPEN_DOCUMENT_TREE dan DocumentsContract, sehingga tombol sistem **USE THIS FOLDER** benar-benar muncul; tidak menebak path storage atau meminta akses seluruh penyimpanan. iOS memakai UIDocumentPicker (.folder). Pembacaan dan listing native berjalan di worker.

Folder dipindai beserta subfolder; file yang dikenali disalin bertahap ke sandbox aplikasi. Transfer maksimum 64 KiB per chunk, satu file pada satu waktu, dan SHA-256 dihitung sambil menulis. File identik dilewati meskipun namanya berbeda. Progres UI dibatasi paling sering 10 kali per detik, dan pembatalan membersihkan salinan parsial serta menutup handle. Folder cloud dapat memerlukan waktu unduh dari penyedia file. Pembatalan saat listing menunggu operasi listing selesai; UI menampilkan status menghentikan.

Uji native memakai folder sintetis buatan sendiri: 12 format audio, satu salinan MP3, satu file rusak, dan satu teks non-audio, sebagian di subfolder. Impor menambahkan **13 file unik**, melewati satu duplikat dan mengabaikan teks. Rescan menambahkan **0** dan melewati **14 duplikat**. Pemutaran yang sudah berjalan tetap PLAYING selama impor. Setelah force-stop/relaunch, FLAC hasil impor tetap diputar.

- [Tombol folder pada Library](screenshots/folder-library.png)
- [Tombol sistem gunakan folder ini](screenshots/folder-use-this-folder.png)
- [Hasil impor](screenshots/folder-imported.png)
- [Rescan tanpa duplikat tambahan](screenshots/folder-rescan.png)

## Format: hasil uji, bukan janji semua codec

Pemilih menerima 23 ekstensi container/audio. Ekstensi bukan jaminan codec didukung. Pemutar tetap memakai just_audio + decoder platform, tanpa paket FFmpeg besar di APK. WMA, APE, DSD, MIDI dan DRM belum didukung. ALAC di M4A bukan otomatis sama dukungannya dengan AAC di M4A.

| File uji | Codec | Hasil pada emulator Android 36 |
|---|---|---|
| MP3 | MPEG Layer III | PLAYING |
| M4A | AAC | PLAYING |
| AAC/ADTS | AAC | PLAYING |
| WAV | PCM 16-bit | PLAYING |
| FLAC | FLAC | PLAYING |
| OGG | Vorbis | PLAYING |
| OPUS | Opus | PLAYING |
| WEBM | Opus | PLAYING |
| MKA | Opus | PLAYING |
| MP2 | MPEG Layer II | PLAYING |
| AIFF | PCM big endian | Gagal pada backend/perangkat uji |
| CAF | ALAC | Gagal pada backend/perangkat uji |

File rusak juga gagal dengan aman; memilih WAV sesudahnya kembali PLAYING. Error codec ditahan sampai retry/pemilihan lagu agar event idle tidak menghapus pesan. Next/Previous dapat memuat ulang sumber setelah error. Hasil perangkat lain, parameter codec lain, DRM, dan iOS tidak disimpulkan dari tabel ini.

Data native build final: [codec-results-android36.json](reports/codec-results-android36.json), dihasilkan `tool/audit-codecs.ps1` melalui Search dan media_session. Fixture di `build/audio-fixtures` dibuat dari sine sintetis menggunakan FFmpeg sebagai **alat pengujian host saja**; executable FFmpeg dan fixture tidak masuk aset aplikasi/APK.

Referensi resmi: [Media3 supported formats](https://developer.android.com/media/media3/exoplayer/supported-formats), [just_audio: catatan format dan ekstensi](https://pub.dev/packages/just_audio), [Apple directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels).

## Wave dan penggunaan resource

- Wave diganti menjadi tiga pita cyan/violet/magenta dengan fill transparan, garis tepi lembut dan satu glow. Bukan lagi mesh 16 lapisan. [Pratinjau Wave](screenshots/wave-redesign.png).
- Spectrum memakai 72 batang dalam satu Path: satu pass glow untuk seluruh ring, bukan blur per batang. Label logo menjadi widget statis, tanpa membuat TextPainter native setiap frame.
- Animasi berhenti saat pause, mute (neon), route tersembunyi, background atau Reduce Motion. Visualisasi tetap dekoratif, bukan FFT audio.
- Library, Artists, Albums dan isi grup memakai builder/sliver lazy. Baris lagu tidak dibangun ulang pada setiap tick posisi playback.
- Gambar didekode sesuai ukuran tampil/DPR, dibatasi 1024 piksel. Image cache maksimum 48 MiB / 128 entri.
- APK dipisah per ABI: ARM64 sekitar **20,7 MiB**, ARM32 sekitar **18,3 MiB**, x86-64 sekitar **22,2 MiB**. Universal tetap tersedia untuk kemudahan instalasi, sekitar 55 MiB. Perbedaan ukuran terutama berasal dari pemisahan arsitektur; tidak diklaim sebagai pengurangan sebesar itu pada semua komponen runtime.
- Snapshot saat Wave aktif, audio lokal PLAYING dan setelah uji berbagai file: TOTAL PSS 111.210 KiB (sekitar 108,6 MiB), RSS 241.204 KiB. Ini satu pengukuran emulator, bukan batas memori atau benchmark perangkat fisik. Seek pada Opus tercatat ke 8.136 ms dan playback tetap berjalan.

## Audit fitur otomatis

36 test telah lulus melintasi run penuh dan run UI terisolasi. Run penuh meluluskan 34 test sebelum proses flutter_tester Windows terputus saat dua test UI; keduanya diulang terpisah dan lulus. Log run penuh: `build/audit-final-tests.log`. Analyzer bersih. Overflow ubin genre Search yang ditemukan saat audit sudah diperbaiki.

Cakupan: pencarian/genre, favorit/riwayat, impor file/folder, progres, pembatalan di tengah file, deduplikasi, partial failure, akses dokumen chunked/close, file hilang/metadata rusak, persistensi salinan setelah restart/perpindahan direktori, play/pause, seek/skip, shuffle dan tiga repeat mode, volume/mute/error, pilihan tampilan cepat/persisten, lifecycle animasi, lirik/editor, Artist, Back, layout ponsel/tablet/landscape, safe area, teks besar, dan popup volume kiri.

Device Picker tetap demo sesuai spesifikasi awal. Lirik dapat ditambahkan per lagu, belum sinkron LRC dan tidak diunduh otomatis. Metadata lagu lokal memakai nama file dan label lokal; pembacaan tag/cover tertanam belum diimplementasikan. Audit ini tidak menjamin semua file, perangkat, atau versi OS akan memberi hasil yang sama.

Pemeriksaan ulang pada APK final: AIFF, CAF/ALAC, dan file rusak melaporkan ERROR(7) dengan pesan codec yang jelas; 10 format lainnya PLAYING. Retry AIFF tetap berada pada AIFF. Next memuat CAF yang juga gagal, lalu WebM yang siap diputar; Play mengembalikannya ke PLAYING tanpa error. [Pesan codec](screenshots/codec-error-final.png) dan [pemulihan](screenshots/codec-recovery-final.png). Handler memakai errorStream sesuai API just_audio 0.10, tidak lagi mengandalkan onError stream lama. Hash paket final tercatat pada [manifest APK](reports/apk-sha256-1.1.0.json).

Sesudah audit, 13 salinan sintetis di sandbox dan 15 sumber uji (termasuk duplikat/teks) dibersihkan menggunakan pemeriksaan SHA-256 dan whitelist direktori. Musik yang sudah ada tidak dihapus. ADB dikembalikan ke UID 2000/non-root. Aplikasi dibuka ulang pada Library versi 1.1.0, dan lagu lama Swift Local Test masih terlihat: [Library final](screenshots/library-final-1-1.png).
