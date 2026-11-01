# Swift Music 1.4.1 — penempatan sumber dan motion

Tiga sumber streaming dipindahkan dari Home ke **Library → Playlists → Streaming**, di dalam area yang dapat digulir agar tidak menambah tinggi header tetap. Halaman Streaming tetap menyediakan pemilihan sumber setelah dibuka.

Efek masuk bertahap memakai fade dan slide 8 logical pixel selama 480/560/640 ms dengan easeOutCubic. Efek dimulai ulang ketika Library menjadi terlihat, bukan ketika tab tersembunyi dimuat. Tekanan memberi respons skala 0,96; logo sumber terpilih bertransisi ke skala 1,08 dan rotasi ringan pada halaman Streaming. Tidak ada ticker berulang. Preferensi motion ringan/nonaktif dan pengaturan disableAnimations sistem dihormati.

Analyzer: `build/analyze-library-motion.log` bersih. Tes UI produksi pada `build/test-library-source-ui.log` lulus: sumber tidak hit-testable dari Home, tersedia dari Library, dan form serta toggle sumber tetap berfungsi. Beberapa run tester Windows sebelumnya berhenti dengan `No tests were found`; pengulangan terpisah di atas berhasil tanpa assertion failure atau peringatan tap.

Versi paket 1.4.1+7. Fitur streaming dan batas dukungannya tetap dijelaskan di [NETWORK-STREAMING.md](NETWORK-STREAMING.md).

Build release ARM64/ARM32/x86_64 berhasil dan APK x86_64 dipasang menggunakan `adb install -r` di emulator API 36. Home tidak menampilkan ikon sumber; Library menampilkan ketiga ikon pada bagian Streaming, dan Open Stream tetap membuka form. Screenshot: `reports/home-1.4.1.png` dan `reports/library-1.4.1.png`. Pemeriksaan log sesi ini tidak menemukan crash native, error Flutter, atau overflow. Emulator ditinggalkan pada Library. Hash APK: `reports/apk-sha256-1.4.1.json`.
