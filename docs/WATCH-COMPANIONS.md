# Pendamping Wear OS dan Apple Watch

Target keduanya. Implementasi awal adalah **remote untuk pemutar ponsel**, bukan pemutar offline mandiri. Tidak mengirim audio, URI file, atau seluruh katalog ke jam. Kontrol dibatasi ke play/pause, previous/next, volume, seek, dan permintaan status; nilai divalidasi di Dart. Snapshot judul/artis/status terbaru dikirim saat berubah, maksimal dua kali per detik, tanpa polling terus-menerus.

## Wear OS

Modul `android/wear` memakai widget Android native dan Google Play Services Data Layer. Package dan sertifikat penandatangan harus sama dengan aplikasi ponsel. Build pengembangan saat ini memakai debug signing, sama dengan build ponsel lokal. Jalankan dari direktori `android`: `./gradlew :wear:assembleDebug`. Pasang hasil dari `build/wear/outputs/apk/debug/` ke jam Wear OS API 30+ yang dipasangkan dengan Android. Jalankan Swift Music di ponsel terlebih dahulu. Transport saat ini mengikuti masa hidup engine aplikasi ponsel; belum ada cold-start service khusus. Kontrol tidak dijamin ketika proses ponsel sudah dimatikan sistem. Status cache ditandai sebagai status terakhir, bukan koneksi aktif.

## Apple Watch

Sumber SwiftUI ada di `companions/apple-watch/SwiftMusicWatchApp.swift`; bridge iPhone memakai WatchConnectivity dalam `ios/Runner/AppDelegate.swift`. Di Mac dengan Xcode dan XcodeGen, jalankan `xcodegen generate` dari folder pendamping untuk membuat proyek uji jam. Pastikan `WKCompanionAppBundleIdentifier` sama persis dengan bundle ID Runner dan gunakan signing team yang sama. Untuk distribusi, tambahkan target watch tersebut ke workspace Runner dan embed sebagai Watch Content; spesifikasi proyek uji belum menggantikan tahap integrasi archive tersebut. Belum dikompilasi atau diuji di Windows ini.

## Verifikasi yang masih diperlukan

Build debug aplikasi ponsel dan Wear OS berhasil pada 30 Oktober 2026. APK jam: `build/wear/outputs/apk/debug/wear-debug.apk` (5.117.707 byte). Tes Dart membuktikan routing play/pause/next/previous/seek/volume, penolakan nilai di luar batas/nonfinite, dan snapshot tanpa lokasi file. Analyzer bersih.

Pasangan emulator/jam nyata belum tersedia. Uji pairing, kehilangan koneksi, app background, pause/resume, batas volume, kill/relaunch proses, dan pemulihan status pada masing-masing platform. Jangan menandai fitur jam selesai sebelum pengujian pasangan berhasil. Apple Watch belum dikompilasi.

Referensi primer: [Android Data Layer](https://developer.android.com/training/wearables/data/overview), [Apple WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession).
