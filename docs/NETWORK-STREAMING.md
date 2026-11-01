# Open Network Stream — Swift Music 1.4.0

Mulai 1.4.1, **Library → Playlists → Streaming** menyediakan tiga ikon horizontal: Open Stream, YouTube dan Spotify. Ikon memakai fade/slide saat pertama tampil, respons skala saat ditekan, dan transisi logo saat sumber dipilih. Motion mengikuti pengaturan aksesibilitas/motion aplikasi, tanpa ticker berulang. Pengaturan sumber di halaman Streaming dapat mengaktifkan satu atau beberapa sumber. Semua aktif pada awalnya; pilihan disimpan di perangkat. WebView baru dibuat setelah tautan layanan divalidasi dan tombol buka ditekan.

## Dukungan aktual

| Input | Perilaku |
| --- | --- |
| HTTP/HTTPS audio | Audio memakai just_audio/audio_service yang sudah ada, termasuk notifikasi dan background audio |
| HTTP/HTTPS video / IPTV | Entri playlist memiliki aksi tonton fullscreen melalui video_player; codec dan manifest mengikuti dukungan platform. Video tidak masuk antrean audio native |
| M3U/M3U8 daftar lagu | Dibaca sebagai daftar URL; judul Unicode, URL relatif, deduplikasi dan batas 1.000 entri |
| M3U8 HLS | Dipertahankan sebagai satu manifest; segmen TS tidak menjadi lagu terpisah |
| XSPF, PLS, WPL, ASX/WAX/WVX | Parser menghasilkan daftar URL; konten akhirnya tetap harus didukung engine/perangkat |
| MPD | DASH melalui engine Android; iOS menampilkan keterbatasan dan meminta HLS |
| TS atau MKV | Hanya audio jika codec/kontainernya didukung perangkat; tidak ada tampilan video |
| M4S | Tidak dimainkan sendiri; memerlukan manifest dan init segment |
| ISM/ISML, RTSP/RTMP/RTMPS/RTMPE, MMS, FTP, UDP/RTP | Alamat dikenali, tetapi tidak didukung engine internal saat ini. Tersedia tombol membuka aplikasi eksternal yang kompatibel; aplikasinya harus terpasang |

M3U8 berarti teks UTF-8, bukan enkripsi. Enkripsi HLS/DRM merupakan kemampuan terpisah; tidak ada konfigurasi lisensi DRM dalam versi ini. URL tanpa ekstensi playlist dapat dibaca dengan pilihan “Baca sebagai playlist”. Playlist bertingkat tunggal dibatasi empat tingkat; playlist multi-entri bertingkat dapat dibuka per entri. Tidak ada jaminan universal semua codec/protokol.

## Sesi dan memori

Antrean jaringan sementara menggantikan antrean aktif sambil menyimpan snapshot antrean lokal di memori. URL stream tidak masuk sesi disk, riwayat lokal, atau statistik. Kembali ke lagu lokal menghentikan source jaringan dan mengembalikan antrean lokal dalam keadaan dijeda. Private Playback juga menyamarkan judul/artis di kontrol media. Private Playback bukan VPN dan tidak menyembunyikan alamat IP dari server.

Playlist dibatasi 2 MB, 1.000 entri, empat redirect dan deadline request. XML dengan deklarasi DTD/entity ditolak; playlist tidak dapat membuka file lokal melalui `file://`. HTTP biasa diizinkan dalam konfigurasi native karena pengguna dapat memasukkan server HTTP. Tidak ada bypass sertifikat TLS. Subtitle pendamping `.lrc`, `.vtt`, `.srt` dicari dengan nama dasar URL yang sama hanya jika dipilih dan hanya untuk satu stream; maksimal 256 KB/file, dengan deadline. Subtitle dikonversi menjadi lirik tersinkron di player audio.

## YouTube dan YouTube Music

Halaman YouTube menampilkan situs resmi YouTube Music (`music.youtube.com`) di WebView dalam Swift Music, sehingga beranda, chart, dan rekomendasi berasal langsung dari layanan. YouTube Data API key tidak dipakai untuk halaman ini. Google memblokir OAuth/login Google di embedded WebView; akun yang belum terautentikasi mungkin tidak bisa login di sini. Playback dikelola situs/player YouTube Music, tidak menjadi antrean audio native Swift Music. Situs dihentikan saat aplikasi masuk background.

SponsorBlock bersifat opsional, aktif pada form awal. API dipanggil dengan prefix SHA-256 empat karakter; hanya kategori `sponsor` dengan aksi `skip` yang dipakai. Interval tidak valid diabaikan, interval bertumpuk digabung, dan seek menuju akhir segmen dilakukan pada pembaruan posisi. Setiap segmen dilewati maksimal satu kali per pembukaan video agar pengguna dapat mengulang manual. Jika API gagal atau data belum tersedia, pemutaran tetap dapat berjalan. Ini bukan pemblokir iklan pre-roll/mid-roll YouTube. Atribusi data SponsorBlock tersedia di UI.

## Spotify

Spotify memakai embed resmi dan tautan membuka aplikasi resmi. Saat embed dibuka, mini-player Swift Music tersedia sebagai kontrol sesi; memulai track lokal menghentikan embed agar tidak ada dua sumber audio bersamaan. Tombol tutup sesi juga menghentikan embed dan mengembalikan antrean lokal. Pengalaman playback penuh mengikuti akun, browser, dan layanan Spotify; akun Free dapat hanya memperoleh preview. Aplikasi tidak meminta atau menyimpan kata sandi Spotify.

Embed bukan stream native dalam antrean audio OS: metadata/status sinkron penuh, kontrol lockscreen, dan audio background Spotify tidak diklaim tersedia. Spotify Soloist menyediakan kontrol desktop lewat WebSocket lokal dan mensyaratkan Premium pemilik; bridge Soloist bukan bagian build Android/iOS ini.

Referensi: [librespot](https://github.com/librespot-org/librespot), [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference), [Spotify Embeds](https://developer.spotify.com/documentation/embeds/tutorials/using-the-iframe-api), [SponsorBlock API](https://wiki.sponsor.ajay.app/w/API_Docs).

## Verifikasi

Tes `network_stream_test.dart` mencakup M3U/HLS, XML/PLS, URL relatif setelah redirect, batas input, validasi host layanan, segmen SponsorBlock dan subtitle. Tes UI komposisi produksi memeriksa akses Open Stream, penolakan alamat kosong dan persistensi toggle Spotify. Lihat log build/test tahap streaming di `build/`. Pengujian iOS memerlukan macOS/Xcode; dukungan native yang belum diuji tidak dinyatakan terverifikasi.
