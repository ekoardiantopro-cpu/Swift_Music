# Motion dan volume

Implementasi menggunakan animasi bawaan Flutter, tanpa paket animasi tambahan.

- Pergantian Home/Search/Library memakai fade dan slide 340 ms; IndexedStack tetap mempertahankan state tab. Navigasi bawah memakai kurva bawaan Salomon selama 360 ms. Back dari tab lain tetap kembali ke Home.
- Full player naik dari bawah selama 380 ms, kembali 260 ms. Hero memindahkan artwork dari mini-player ke full player. Artwork membesar saat Play dan glow berubah mengikuti status serta volume.
- Kartu Home, kategori Search, daftar lagu, mini-player, dan kontrol volume merespons sentuhan dengan skala 0,96 dan kembali selama 160 ms. Listener pointer tidak mengambil alih gesture scroll/tap.
- Ikon play/pause, favorit, mute, shuffle dan repeat memakai pergantian scale/fade 220 ms. Lagu aktif memiliki latar hijau bertransisi. Judul hasil pencarian dan angka persentase volume juga bertransisi.
- Equalizer mini 4 batang dan full player 32 batang menggambar ulang dengan CustomPainter/RepaintBoundary. Ticker berhenti ketika pause, volume nol, tab/route tersembunyi, aplikasi tidak aktif, atau pengaturan Reduce Motion aktif. Tidak ada timer periodik yang membangun ulang seluruh halaman.

Equalizer merupakan **visualisasi dekoratif status pemutaran**, bukan analisis FFT, waveform audio asli, atau DSP pengaturan frekuensi. Tingginya mengikuti volume aplikasi. Volume sebenarnya diteruskan melalui PlayerCubit → AudioHandler.customAction → AudioPlayer.setVolume dengan rentang 0–1. Volume aplikasi terpisah dari volume sistem perangkat.

Slider, tombol +/− sebesar 5%, mute dan pemulihan volume sebelumnya memakai satu state bersama. Permintaan slider diserialkan dan nilai menunggu diganti dengan target terbaru agar gesture cepat tidak menghasilkan urutan volume yang tertukar. Kegagalan perintah mengembalikan volume terakhir yang berhasil. Perubahan volume tidak mengganti lagu atau posisi playback. Volume saat ini berlaku selama service hidup; belum disimpan lintas penghentian proses.

Pengurangan gerakan mengikuti MediaQuery.disableAnimations. Animasi khusus memakai durasi nol, press scale dinonaktifkan, dan visualizer diam. Komponen Material mengikuti perilaku aksesibilitas Flutter.

Verifikasi otomatis: 24 test lulus, meliputi volume clamp/NaN/mute, gesture cepat dan kegagalan, visualizer pause/mute/reduced motion/TickerMode/lifecycle, UI volume pada 320×640, impor lokal, serta perilaku Back. Lihat VERIFICATION.md untuk build dan pemeriksaan emulator. Kelancaran perangkat fisik iOS/Android memerlukan profiling pada perangkat sasaran.

Panel volume tersembunyi saat full player dibuka. Tombol speaker di samping Device Picker membuka/menutup panel dengan AnimatedSize; menutup panel tidak mengubah volume atau playback. State panel direset tertutup saat full player dibuka kembali. Regression test UI memeriksa kondisi awal tersembunyi, buka/tutup, dan volume tetap tersimpan saat panel ditutup.

## Pilihan tampilan album

Tombol Tampilan album di bawah artwork membuka pilihan Cover (statis), Vinyl (piringan beralur berputar satu putaran per 12 detik), dan Pulse (sampul dengan denyut cahaya lembut). ArtworkStyleCubit menyimpan pilihan menggunakan SharedPreferencesAsync dengan key player_artwork_style dan mengembalikannya saat aplikasi dibuka ulang. Nilai tidak dikenal kembali ke Cover; pembacaan yang lambat tidak menimpa pilihan baru pengguna. Kegagalan simpan menampilkan pesan tanpa menghentikan playback.

Renderer AlbumDisplay hanya mengubah visual; tidak mengakses audio handler atau posisi playback. Vinyl/Pulse berhenti saat pause, route tersembunyi, aplikasi tidak aktif, atau Reduce Motion aktif. Vinyl melanjutkan sudut putaran sebelumnya saat resume. Vinyl digambar menggunakan CustomPainter dan cover di tengah, tanpa aset raster atau dependensi tambahan.

## Ketuk untuk berganti tampilan

Area utama kini berganti Cover → Lirik → Vinyl → Spectrum → Wave → Pulse → Cover setiap diketuk. Pemilih langsung tetap tersedia. Pergantian memakai AnimatedSwitcher fade/scale 420 ms, dengan durasi nol saat Reduce Motion. Gesture scroll lirik tidak dianggap tap. Ketukan cepat langsung memperbarui tampilan; penulisan preferensi diserialkan dan hanya pilihan menunggu terbaru disimpan.

Spectrum menggambar 72 garis radial dengan warna cyan/biru/magenta dan glow. Wave menggambar tiga pita cahaya berlapis yang berulang tanpa sambungan fase. Keduanya CustomPainter dengan repaint clock terpisah, berhenti pada pause, mute, latar belakang, route tersembunyi dan Reduce Motion. Ini visualisasi dekoratif yang mengikuti playback/volume, bukan FFT atau waveform audio asli. Referensi gambar iStock dipakai sebagai inspirasi bentuk/warna saja; aset foto stok tidak dimasukkan ke aplikasi.

Mode Lirik menampilkan teks katalog atau lirik yang ditambahkan lewat ikon pensil. Teks pribadi disimpan per ID lagu melalui SharedPreferencesAsync, bisa diedit dan digulir. Lirik tidak diunduh otomatis dan belum memiliki sinkronisasi per baris/LRC; lagu instrumental atau tanpa teks menampilkan informasi ketersediaan secara jujur. Editor tidak menyimpan teks ke lagu lain bila metadata berubah saat dialog dibuka.

## Layout adaptif dan volume samping

Player memakai ukuran SafeArea/LayoutBuilder untuk menghitung diameter artwork berdasarkan sisa tinggi setelah teks dan kontrol. Ponsel portrait memakai satu kolom; tablet ≥760 logical pixel dan landscape lebar memakai dua kolom. Batas lebar konten 1100 dan artwork 400–420 logical pixel menjaga proporsi pada tablet. Judul panjang memakai ellipsis dengan tooltip. Teks aksesibilitas yang sangat besar mendapat fallback scroll agar tidak terpotong. Grid kategori Search dan tinggi shelf/shortcut Home mengikuti lebar dan text scaler.

Volume kini overlay vertikal selebar 80 logical pixel di kiri, dibuka dari ikon speaker kiri header. Tidak ada panel volume inline di bawah player, sehingga artwork dan kontrol tidak bergeser. Overlay slide/fade selama 220 ms, menutup setelah 3 detik tanpa interaksi, dan timer ditahan selama pointer menyentuh panel. Tap di luar, tombol tutup, atau Back menutup overlay; Back berikutnya baru menutup player. Slider vertikal, +/−5%, mute/restore tetap mengatur gain aplikasi melalui handler yang sama. Tombol hardware volume tetap memakai perilaku sistem operasi.

Tes layout mencakup 320×568, 390×844, 800×1280, 844×390, 568×320, DPR 3 dengan safe inset, dan text scale 1,8. Posisi kontrol diverifikasi di dalam viewport tanpa scroll pada ukuran normal tersebut. Tes overlay memeriksa sisi kiri, orientasi vertikal, tidak menggeser artwork, hold, auto-hide, Back dan tap luar.

Pembaruan 1.1.0 mengurangi pass glow Spectrum menjadi satu path gabungan, mengganti mesh Wave dengan tiga pita, dan membatasi decode/cache gambar. Rincian audit dan kompatibilitas codec ada pada [AUDIT-1.1.0.md](AUDIT-1.1.0.md).
