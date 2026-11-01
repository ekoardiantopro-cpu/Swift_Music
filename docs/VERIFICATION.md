# Swift Music — Verifikasi 29 Oktober 2026

Catatan terbaru: [audit 1.3.0 build 5](AUDIT-1.3.0.md), sleep timer, pemulihan sesi, backup/restore playlist dan filter koleksi. [Audit 1.2.1](AUDIT-1.2.1.md) memuat pengujian media session saat layar mati dan teks besar; [audit 1.2.0](AUDIT-1.2.0.md) mencakup metadata/cover, playlist, folder persisten dan LRC. Bagian berikut mempertahankan hasil historis versi sebelumnya; gunakan manifest hash versi 1.3.0 untuk APK terbaru.

## Toolchain

- Flutter 3.47.8 stable, Dart 3.13.7, Windows.
- Android SDK: platform 36, build tools 36.0.0, NDK 28.2.13676358.
- JDK Eclipse Adoptium 17.0.20.1.
- Native scaffold Android/iOS sudah dibuat; dependensi berhasil di-resolve dan dikunci di `pubspec.lock`.
- Target Android minimum API 24; template Runner iOS menggunakan minimum iOS 15.0.

## Pemeriksaan yang lulus

| Pemeriksaan | Hasil |
| --- | --- |
| `dart format lib test` | Selesai |
| `flutter analyze` | No issues found |
| `flutter test --concurrency=1` | 21 test lulus |
| `flutter build apk --debug` | Berhasil |
| Delimiter/import sumber, parsing XML dan PowerShell | Lulus |

Test mencakup filter katalog, favorit dan riwayat, kegagalan penyimpanan, pemilihan lagu sebelum play, sinkronisasi metadata/state, reset posisi/durasi, buffering/error/retry, kegagalan command, lifecycle subscription, dan alur UI mini-player → full player → favorit → device picker pada layar 320×640. Tambahan impor lokal mencakup penyalinan/pemulihan file, deduplikasi isi, perpindahan sandbox, metadata rusak, file kosong/hilang, kegagalan baca, pembatalan picker, keberhasilan parsial, dan pembaruan daftar Library/queue.

Test dijalankan berurutan karena proses tester paralel sempat terputus sebelum suite UI selesai dimuat pada lingkungan dengan memori terbatas. Widget test memakai artwork placeholder agar tidak bergantung pada cache/network gambar.

Widget test menggunakan handler palsu dan tidak membuktikan playback native. Ia menemukan overflow horizontal pada tombol perangkat dan overflow vertikal pada bottom sheet; keduanya telah diperbaiki dan regression test lulus.

Build pertama menemukan kegagalan incremental cache Kotlin akibat perbedaan root drive proyek D: dan Pub cache C:. Build berhasil setelah `kotlin.incremental=false`; heap Gradle dibatasi 3 GB dan dua worker agar sesuai kapasitas komputer.

## Artefak Android

- File: `build/app/outputs/flutter-apk/app-debug.apk`
- Ukuran: 203.233.060 byte (sekitar 194 MiB), termasuk perbaikan Back, impor lokal, dan informasi versi/developer.
- SHA-256: `1D36AD3915641F221AAE8C90AD7F05E4F90C2D6B6F7DCA3FBEA1F5D173806CFB`
- Debug APK universal untuk ARM32, ARM64, dan x86-64. Ukuran besar mencakup runtime/debug symbols; bukan paket release untuk store.
- Release x86-64 untuk pengujian emulator sudah dibuat; masih menggunakan debug key bawaan proyek. Signing store dan kompilasi iOS belum dilakukan.

Paket emulator ringan sebelumnya dibangun khusus x86-64 (sekitar 20,6 MiB). Setelah pembaruan ikon, `build/app/outputs/flutter-apk/app-release.apk` telah diganti dengan **release universal ARM32, ARM64, dan x86-64**, 57.148.519 byte (sekitar 54,5 MiB), dibangun menggunakan `flutter build apk --release`. SHA-256: `CCF340BCFDE84F89B1A07579F2724961B99F183E11F21CF668EC532BA52BF3D9`. Paket masih memakai debug key untuk pengujian lokal. Paket debug lama tetap tersedia terpisah.

## Uji runtime

APK berhasil dipasang pada emulator `SwiftOS_Phone_API36` (Android API 36), dan `AudioServiceActivity` berhasil membuka Home serta full player. `dumpsys media_session` menunjukkan metadata `Midnight Bloom / SoundHelix · Demo 1 / Night Drive`.

| Langkah runtime | State Android yang diamati |
| --- | --- |
| Putar audio demo dari Home | `PLAYING(3)`, posisi 1.211 ms, buffer 87.379 ms |
| Masuk background dengan tombol Home | `PLAYING(3)`, posisi 49.055 ms, buffer 131.082 ms |
| Pause melalui `cmd media_session dispatch pause` | `PAUSED(2)`, posisi 53.904 ms |
| Resume melalui `cmd media_session dispatch play` | `PLAYING(3)`, posisi 53.955 ms |

Screenshot full player menampilkan posisi 0:48 dari durasi 6:12 dan tombol Pause aktif. Emulator dijalankan tanpa output audio host (`-no-audio`), sehingga hasil ini membuktikan state/posisi engine dan integrasi media session, bukan penilaian kualitas suara. Pengujian lockscreen secara visual, perangkat fisik, interupsi panggilan, headset, serta kontrol iOS tetap diperlukan.

Saat cold boot, emulator sempat menampilkan ANR **System UI**, lalu pulih setelah memilih Wait. Ini merupakan keterbatasan lingkungan runtime yang tidak boleh dianggap sebagai bukti performa perangkat fisik. Pemanggilan awal `am start -W` sempat timeout walaupun aktivitas kemudian terbuka. Satu permintaan artwork awal juga mengalami connection refused; UI menggunakan fallback dan artwork berhasil dimuat pada full player berikutnya. Tidak ditemukan fatal exception AndroidRuntime pada pemeriksaan log startup/playback.

- [Screenshot Home](screenshots/home-android.png)
- [Screenshot full player saat playing](screenshots/player-android.png)
- [Diagnostik ANR System UI emulator saat cold boot](screenshots/emulator-system-ui-anr.png)

Emulator pengujian dihentikan setelah pemeriksaan agar tidak terus memakai memori komputer.

## Tambahan — Impor lagu lokal

APK terbaru memasukkan picker native `file_picker`, penyimpanan permanen file lokal, deduplikasi SHA-256, serta CatalogCubit untuk memperbarui Library, Search, dan antrean.

Uji Android API 36 dilakukan dengan WAV PCM sintetis 120 detik yang dibuat melalui `node tool/make-local-audio-fixture.cjs`; tidak menggunakan atau memindai koleksi audio pribadi. File dipilih melalui **Library → Pilih lagu lokal → Downloads**. Berhasil dibuat salinan WAV 1.920.044 byte dan metadata JSON di `files/local_music` sandbox aplikasi. Lagu muncul sebagai **Swift Local Test / Lagu lokal**.

Wi-Fi dan data seluler emulator dimatikan; `dumpsys connectivity` melaporkan **Active default network: none**. WAV sumber pengujian di Downloads dihapus setelah impor. `dumpsys media_session` kemudian menunjukkan:

```text
state=PLAYING(3), position=15825, buffered position=120000
active item id=6, error=null
description=Swift Local Test, Lagu lokal, On this device
```

[Screenshot playback lokal offline](screenshots/local-player-offline-android.png) menampilkan progress 0:20 dari durasi 2:00. [Screenshot Library lokal](screenshots/library-local-android.png) menunjukkan hasil impor. Emulator memakai `-no-audio`, sehingga kualitas suara tidak dinilai.

Pengujian restart native belum dapat disimpulkan: saat force-stop/relaunch, emulator keluar dan perangkat hilang dari ADB. Pemulihan katalog setelah restart/perpindahan direktori serta pemutaran dari salinan setelah file asal dihapus sudah diverifikasi melalui test penyimpanan. File picker dan playback native iOS belum diuji; dukungan codec selain WAV belum diverifikasi secara langsung pada perangkat.

Preferensi jaringan emulator dikembalikan ke kondisi awal (`wifi_on=1`, `mobile_data=1`) dan emulator dihentikan setelah pengujian.

## Menjalankan ulang di Windows

Pembaruan ikon: master dibuat dengan tool `image_gen` bawaan dan disimpan di `assets/branding/swift_music_icon.png`; prompt serta referensi gaya dicatat di `assets/branding/ICON_DESIGN.md`. `flutter_launcher_icons` membuat ikon Android legacy/adaptive serta 25 ukuran iOS. Seluruh ukuran iOS sesuai katalog; ikon marketing 1024×1024 memakai PNG RGB tanpa alpha. Analyzer bersih dan ketiga regression test UI lulus setelah penggunaan `BrandMark` pada Home/Tentang. APK universal berhasil dibangun, dipasang, dan dibuka di profil `SwiftMusic_API36`. Pemeriksaan launcher menunjukkan simbol utuh pada mask bulat: [screenshot launcher](screenshots/new-launcher-icon.png). [Halaman Tentang dengan logo baru](screenshots/new-brand-about.png). Build/runtime iOS belum diverifikasi pada macOS.

Pemulihan emulator: profil lama API 26 kemudian menampilkan **Decryption unsuccessful / Reset phone**. Profil lama tidak direset/dihapus. Dibuat profil terpisah **SwiftMusic_API36** menggunakan `avdmanager` dan system image Android 36 Google APIs x86-64 yang sudah terpasang. Berkas runtime berada di `.emulator/SwiftMusic_API36.avd`, diabaikan oleh Git. Jalankan profil ini melalui `tool/start-emulator.ps1` dalam terminal yang tetap aktif.

Pada profil baru, `/data/user/0` terpasang dari `/dev/block/dm-55`, kapasitas 5,8 GiB (bukan tmpfs 256 MiB seperti profil bermasalah). Setelah reboot Android, marker uji tetap terbaca, paket Swift Music tetap terpasang, dan aplikasi dibuka lagi dalam 3.227 ms. Ruang tersedia setelah pengujian sekitar 4,5 GiB. [Screenshot aplikasi pada emulator baru setelah reboot](screenshots/fresh-emulator-running.png). Emulator baru dibiarkan aktif untuk digunakan.

Pada pemeriksaan terakhir, aplikasi berhasil dijalankan di `SwiftOS_Phone_API26` dengan APK release ringan. Versi debug terlalu besar untuk partisi `/data` 256 MiB pada profil tersebut. Kepadatan layar disesuaikan ke 210 pada resolusi 540×960. Emulator dijalankan dalam sesi interaktif yang tetap aktif agar tidak berhenti bersama proses peluncur.

Pemeriksaan Back Android langsung berhasil: Tentang → Library → Home → background. Pembukaan kembali menggunakan task/activity yang sama (`Activity not started, its current task has been brought to the front`), waktu launch ulang 19 ms, lalu Home tampil kembali tanpa layar hitam. [Screenshot aplikasi aktif](screenshots/running-api26.png). Pemeriksaan Android 16 sebelumnya terganggu startup/kelambatan emulator dan tidak dianggap lolos runtime.

Pembaruan navigasi Back: `PopScope` mengembalikan Search/Library ke Home; route Tentang/full player tetap ditutup oleh Navigator terlebih dahulu. Manifest mengaktifkan callback Back Android modern. Launcher sekarang `.MainActivity : AudioServiceActivity`, dengan override root `popSystemNavigator()` untuk memindahkan task ke background tanpa menghancurkan activity audio. Analyzer bersih, build Kotlin/Android berhasil, dan seluruh 21 test berhasil dalam satu run, termasuk regression test urutan Back serta permintaan meninggalkan UI hanya ketika sudah berada di Home.

Pembaruan halaman **Tentang Swift Music** sudah dibangun dan dipasang ke emulator. Pemeriksaan visual menampilkan **1.0.0 (build 1)** serta developer **ekoardianto.pro@gmail.com** dengan benar; [screenshot halaman informasi](screenshots/about-android.png). Versi diperoleh lewat `PackageInfo.fromPlatform()`, bukan teks versi tetap pada UI. Analyzer bersih. Pada validasi perubahan ini, satu proses widget test terputus setelah 19 test lain selesai; suite UI diulang terpisah dan kedua test lulus. Native iOS belum diuji.

Emulator interaktif dibiarkan terbuka pada halaman informasi sesuai permintaan menjalankan aplikasi.

```powershell
powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 analyze
powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 test --concurrency=1
powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 build apk --debug
powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 devices
powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 run -d <device-id>
```

Wrapper mendeteksi SDK lokal dan hanya mengatur environment prosesnya; tidak mengubah konfigurasi PATH sistem.

## Pembaruan smooth motion dan volume — 29 Oktober 2026

`flutter analyze` bersih dan `flutter test --concurrency=1` meluluskan 24 test. Cakupan baru: volume clamp dan nilai non-finite, mute/restore, serialisasi gesture cepat, rollback kegagalan, visualizer pause/mute/reduced motion/tab tersembunyi/lifecycle, serta kontrol volume dan layout 320×640. Regresi Back dan impor lokal tetap lulus. Detail implementasi: [MOTION.md](MOTION.md).

APK release universal terbaru berhasil dibangun (57.350.080 byte), SHA-256 `205EE314F54D5AE03CFB9E5E4C3654582A42E55086297F755D7F60FAD2C9E522`. Paket Android ARM32/ARM64/x86-64 memakai signing pengembangan untuk pengujian lokal. iOS belum dibangun di Windows.
Pada build final, 21 test non-UI lulus; proses tester suite UI terputus ketika digabung. Ketiga test UI diulang terpisah dan seluruhnya lulus, termasuk assertion lebar visualizer >200 pada layar 320 piksel. Pemeriksaan resource APK dengan aapt memastikan ikon play/pause/previous/next/stop dipertahankan melalui keep.xml agar resource shrinker release tidak menghapus kontrol notifikasi.

APK final dipasang dengan install -r pada SwiftMusic_API36 dan dibuka sukses (cold launch 3.182 ms). WAV sintetis lokal tetap tersimpan setelah reboot/update, diputar melalui Library, dan media_session melaporkan PLAYING dengan active item 6 serta metadata Swift Local Test tanpa error. Pemeriksaan visual menunjukkan equalizer terlihat, slider mengubah volume dari 100% ke 65%, tinggi batang mengecil, dan mute/restore serta pause/resume berfungsi. [Player bergerak](screenshots/motion-final.png) dan [volume 65%](screenshots/motion-volume-final.png). Emulator dibiarkan terbuka pada full player. Pemeriksaan ini membuktikan fungsi/tampilan pada emulator, bukan benchmark frame rate perangkat fisik.

## Koreksi panel volume — 29 Oktober 2026

Panel volume sekarang tersembunyi secara default dan ditoggle lewat tombol speaker di sebelah Device Picker. AnimatedSize menghaluskan buka/tutup. Menutup panel mempertahankan level volume. Analyzer bersih; ketiga regression test UI lulus setelah proses tester pertama terputus dan diulang. Tes mencakup volume awal tersembunyi, tampil setelah tombol diketuk, hilang setelah ditutup, dan level tetap tersimpan.

APK koreksi volume berhasil dibangun. SHA-256 terbaru: E87F319858703936C68C9B5079D626679E8AF6BB55F54819D0F7EA2E548621C0.

## Pilihan animasi album — 29 Oktober 2026

Ditambahkan Cover, Vinyl dan Pulse melalui pemilih Tampilan album. Analyzer bersih. Empat test baru lulus untuk preferensi tersimpan, pembacaan tertunda (termasuk pilihan Cover eksplisit), nilai tidak dikenal/kegagalan simpan, ukuran piringan penuh, dan lifecycle/reduced-motion/TickerMode pada kedua animasi. Ketiga tes UI lulus terpisah, mencakup pemilihan Vinyl/Pulse di layar 320×640 serta regresi volume, favorit, Back dan impor lokal. Tester UI sempat terputus ketika digabung dengan suite lain dan berhasil setelah diulang terpisah.

APK release universal terbaru: 57.448.856 byte; SHA-256 C042628AA970B1E79DF27C5CEA7824358678675F9E5075152A16D7E732F75773. Build iOS belum diuji di Windows.

APK dipasang dan dijalankan di SwiftMusic_API36. Menu pemilih menampilkan ketiga mode; Vinyl terlihat sebagai piringan penuh dengan alur dan cover di tengah. Setelah force-stop dan cold launch ulang (2.647 ms), full player memulihkan label Tampilan album · Vinyl. [Menu pilihan](screenshots/album-options.png) dan [piringan vinyl](screenshots/album-vinyl.png). Emulator dibiarkan aktif pada full player mode Vinyl.

## Siklus ketukan, lirik dan visualizer neon — 29 Oktober 2026

Area utama berganti Cover → Lirik → Vinyl → Spectrum → Wave → Pulse saat diketuk; menu pemilih tetap ada. Lirik katalog/pengguna ditampilkan di area yang sama dan bisa digulir. Ikon pensil membuka editor lirik per lagu. Spectrum dan Wave digambar dengan CustomPainter, warna cyan/biru/magenta terinspirasi referensi. Gambar stok tidak dimasukkan ke aset. Visualizer dekoratif belum memakai FFT; lirik belum tersinkron waktu.

Analyzer bersih. Enam tes fitur (ketukan cepat, persistensi/race preferensi, siklus lengkap, lifecycle/reduced motion keempat mode animasi, editor dan isolasi lirik per lagu) lulus. Ketiga tes UI termasuk siklus ketuk dan pemilih menu yang digulir pada 320×640 lulus dengan --no-enable-impeller; proses tester default sempat terputus. Log run UI yang lulus berada di build/player-ui-test.log. APK universal release: 57.875.532 byte, SHA-256 2F0B192D1AE7829829F8EE0C4C706E3B043F369237B4734DD4CDCEC6AF71D6C6.

APK terbaru dipasang dengan install -r di SwiftMusic_API36 dan cold launch berhasil (3.302 ms). Satu ketukan dari Vinyl memunculkan Spectrum, ketukan berikutnya Wave; tiga ketukan berurutan kembali ke Lirik melalui Pulse dan Cover. Lirik tampil di area utama dengan ikon editor, dapat digulir, dan playback native tetap PLAYING tanpa error. [Spectrum](screenshots/cycle-spectrum.png), [Wave](screenshots/cycle-wave.png), [Lirik](screenshots/cycle-lyrics.png). Emulator dibiarkan aktif agar pergantian tampilan bisa dicoba langsung.

## Player fit layar dan volume kiri — 29 Oktober 2026

ResponsivePlayer menghitung artwork dari SafeArea dan sisa tinggi setelah kontrol, dengan satu kolom pada portrait serta dua kolom pada tablet/landscape. Grid Search dan tinggi kartu Home mengikuti lebar/text scaler. Volume dipindah ke overlay vertikal kiri yang muncul dari ikon speaker kiri header, auto-hide 3 detik, ditahan saat pointer menyentuh panel, serta bisa ditutup melalui Back/tap luar/X. Tidak ada panel volume bawah yang menggeser layout.

Analyzer bersih. Tes player responsif lulus terisolasi (no-enable-impeller), memeriksa kontrol tetap di viewport pada 320×568, 390×844, 800×1280, 844×390 dan 568×320; juga DPR3 dengan safe inset, text scale1,8, posisi overlay kiri, rasio vertikal, artwork tidak bergeser, hold, auto-hide, Back, tap luar, mute dan volume. Tes Back juga lulus terisolasi. Run gabungan sempat mengalami crash native flutter_tester Windows 0xC0000005; log diagnosis tersimpan di build/responsive-player-test.log, tidak dinyatakan sebagai run lulus.

APK release universal terbaru berukuran 57.957.472 byte; SHA-256 22486E5194487F0B59E73F3230A0DA43459FDBA262A2384ABF39ABF36B912D8B. Perilaku volume hardware tidak diubah. Build/perangkat iOS belum diuji pada Windows.

Pemeriksaan native Android berhasil: pada portrait 540×960 seluruh artwork, seekbar, transport dan device picker terlihat tanpa menggulir. Rotasi ke landscape 960×540 mengubah layar menjadi dua kolom dengan kontrol tetap terlihat. [Portrait fit](screenshots/player-fit-portrait.png) dan [landscape fit](screenshots/player-fit-landscape.png). Pengaturan rotasi emulator dikembalikan ke awal (accelerometer_rotation=1, user_rotation=0). Tombol tutup volume kemudian dipindah ke baris bawah overlay agar persentase di atas tidak tertutup; tes player responsif diulang dan lulus.

APK final dipasang dan cold launch berhasil (4.204 ms). [Player final dengan Vinyl](screenshots/player-fit-final.png) memuat seluruh kontrol pada portrait; [overlay volume kiri final](screenshots/player-volume-left.png) menampilkan persentase utuh, slider vertikal, +/−, mute dan tutup di baris bawah. Overlay dibuka dari ikon speaker kiri header dan menutup otomatis; emulator dibiarkan aktif pada full player.

## Audit versi 1.1.0 — folder, Wave, resource dan format

Versi 1.1.0 (build 2) sudah dibangun untuk ARM64, ARM32, x86-64 dan universal, dipasang serta dijalankan pada emulator. Ringkasan lengkap pengujian, bukti folder/subfolder/duplikat, hasil 12 codec, 36 tes, pemulihan error, snapshot memori, hash APK, pembersihan fixture dan batas iOS/format ada pada [AUDIT-1.1.0.md](AUDIT-1.1.0.md).
