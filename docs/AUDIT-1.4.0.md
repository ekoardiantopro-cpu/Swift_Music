# Audit Swift Music 1.4.0 (build 6)

Tanggal: 30 Oktober 2026. Implementasi streaming menambah tiga sumber horizontal, toggle sumber tersimpan, parser playlist jaringan, subtitle HTTP pendamping, pemutar resmi layanan, serta SponsorBlock opsional. Rincian dukungan dan batasnya: [NETWORK-STREAMING.md](NETWORK-STREAMING.md). Ini tidak menyatakan seluruh 86 saran telah selesai.

## Android

Build release per ABI berhasil; gunakan APK ARM64, ARM32 atau x86_64 sesuai perangkat. `app-release.apk` universal yang lama bukan artefak versi ini. Hash artefak versi 1.4.0 ada di `reports/apk-sha256-1.4.0.json`. Penandatanganan lokal masih menggunakan debug key, sebagaimana build sebelumnya; bukan rilis store.

Emulator SwiftMusic_API36 diperbarui menggunakan `adb install -r`, tanpa menghapus data. Server fixture lokal `tool/stream-audit-server.cjs` melayani M3U, WAV 60 detik dengan dukungan Range, dan LRC. Sambungan melalui `adb reverse`; fixture ini bukan fitur server produksi aplikasi.

Hasil native:

- Home menampilkan Open Stream, YouTube dan Spotify.
- Playlist HTTP terbaca dan WAV mencapai status Android `PLAYING`, dengan buffer 60.000 ms.
- Private Playback menyamarkan metadata menjadi `Private Playback / Swift Music`.
- Subtitle `test.lrc` ditemukan; dua baris tampil di full player. Screenshot: `reports/network-lyrics-1.4.0.png`.
- Uji pengembalian: sebelum stream, **Swift Local Test** dijeda pada **11.513 ms**, indeks 1. Saat streaming, **Network Audit** diputar pada indeks 0. Setelah kembali, **Swift Local Test** berada pada **11.513 ms**, indeks 1, buffer 0, tanpa autoplay. Lihat `reports/network-before-1.4.0.txt`, `network-during-1.4.0.txt`, dan `network-after-1.4.0.txt`.
- Uji ini menemukan dan memperbaiki event indeks/durasi dari source yang sudah dihentikan, yang sebelumnya dapat menimpa metadata lokal saat shuffle dipulihkan. Event tersebut kini diabaikan saat source belum dimuat; pemilihan metadata dipublikasikan eksplisit setelah prepare.
- YouTube IFrame berhasil memutar video contoh resmi `M7lc1UVf-VE`; screenshot `reports/youtube-1.4.0.png` memperlihatkan video berjalan setelah tombol play ditekan. SponsorBlock merespons tidak ada segmen untuk video tersebut. Skip sponsor native pada video bersegmen belum terverifikasi. Fullscreen otomatis melalui gesture dinonaktifkan agar halaman sumber dapat digulir secara biasa.
- Embed Spotify menampilkan track dan preview dapat dijalankan; screenshot `reports/spotify-1.4.0.png` memperlihatkan kontrol pause serta progres preview. Ini bukan pemutaran penuh atau autentikasi akun Spotify.
- Pemeriksaan log pada sesi HTTP tidak menemukan crash native, error Flutter, atau overflow.

Pemutar lokal menghentikan decoder/buffer saat berpindah ke layanan web dan mempertahankan posisi untuk pemuatan malas. Favorit jaringan dinonaktifkan karena antrean jaringan bersifat sementara. Memori aplikasi belum diukur lintas perangkat; ukuran APK tidak dijadikan klaim penggunaan RAM.

## Tes

`network_stream_test.dart`: 7 tes lulus saat dijalankan terpisah, mencakup UTF-8, HLS, PLS/XML, redirect/URL relatif, batas input, host layanan, segmen sponsor dan subtitle. Tes komposisi UI produksi lulus pada `build/final-ui-retry.log`, termasuk penolakan alamat kosong dan toggle sumber Spotify. Sembilan tes Cubit player lulus bersama tes streaming pada run awal (`build/test-stream.log`: 17 lulus).

Beberapa pengulangan gabungan mengalami penghentian tester Windows (`did not complete` atau `No tests were found`), tanpa assertion failure. Hasil pengulangan file terkait dicatat terpisah; tidak menyatakan suite gabungan stabil. Log analyzer dan build tersimpan di `build/`.

## Belum terverifikasi / belum tersedia

Spotify memakai embed resmi dan tautan aplikasi resmi, **bukan librespot**; pengguna belum memiliki Premium. Tidak ada uji streaming penuh dengan akun Spotify. YouTube Music menerima tautan video/lagu, belum login atau katalog akun; tidak menyediakan background audio YouTube. Konten terbatas wilayah/akun dan SponsorBlock pada video bersegmen masih memerlukan pengujian layanan nyata.

RTSP/RTMP/RTMPE/RTMPS/MMS/FTP/UDP/RTP serta Smooth Streaming tidak diputar engine internal; aplikasi eksternal yang kompatibel diperlukan. MKV/TS hanya menghasilkan audio bila codec perangkat mendukung. DASH internal khusus Android; iOS menggunakan HLS. iOS belum dibangun atau diuji karena lingkungan Windows.
