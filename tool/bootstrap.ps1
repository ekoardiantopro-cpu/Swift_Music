# Jalankan sekali dari PowerShell setelah Flutter stable tersedia di PATH.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter belum tersedia di PATH. Instal Flutter stable terlebih dahulu.'
}
if ((Test-Path -LiteralPath 'android') -or (Test-Path -LiteralPath 'ios')) {
    throw 'Folder native sudah ada. Ikuti langkah konfigurasi manual di README agar perubahan native Anda tidak tertimpa.'
}
# flutter create dapat membuat main.dart/widget_test: simpan sumber kita di memori.
$mainSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'lib/main.dart'))
$pubspecSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml'))
$readmeSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'README.md'))
try {
    & flutter create --platforms=android,ios --org com.swiftmusic --project-name swift_music --no-pub .
    if ($LASTEXITCODE -ne 0) { throw 'flutter create gagal.' }
} finally {
    [IO.File]::WriteAllText((Join-Path $projectRoot 'lib/main.dart'), $mainSource)
    [IO.File]::WriteAllText((Join-Path $projectRoot 'pubspec.yaml'), $pubspecSource)
    [IO.File]::WriteAllText((Join-Path $projectRoot 'README.md'), $readmeSource)
}
Copy-Item -LiteralPath 'native/android/AndroidManifest.xml' -Destination 'android/app/src/main/AndroidManifest.xml' -Force
Copy-Item -LiteralPath 'native/android/MainActivity.kt' -Destination 'android/app/src/main/kotlin/com/swiftmusic/swift_music/MainActivity.kt' -Force
New-Item -ItemType Directory -Path 'android/app/src/main/res/drawable','android/app/src/main/res/raw' -Force | Out-Null
Copy-Item -LiteralPath 'native/android/ic_stat_music_note.xml' -Destination 'android/app/src/main/res/drawable/ic_stat_music_note.xml' -Force
Copy-Item -LiteralPath 'native/android/keep.xml' -Destination 'android/app/src/main/res/raw/keep.xml' -Force
Copy-Item -LiteralPath 'native/ios/Info.plist' -Destination 'ios/Runner/Info.plist' -Force
Copy-Item -LiteralPath 'native/ios/AppDelegate.swift' -Destination 'ios/Runner/AppDelegate.swift' -Force
Add-Content -LiteralPath 'android/gradle.properties' -Value "`nforce-version-code-ignoring-abi=true"
$gradlePath = Join-Path $projectRoot 'android/app/build.gradle.kts'
if (Test-Path -LiteralPath $gradlePath) {
    $gradle = [IO.File]::ReadAllText($gradlePath)
    $gradle = $gradle.Replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    [IO.File]::WriteAllText($gradlePath, $gradle)
}
# Template counter bawaan tidak sesuai dengan aplikasi audio ini.
$counterTest = Join-Path $projectRoot 'test/widget_test.dart'
if (Test-Path -LiteralPath $counterTest) {
    Remove-Item -LiteralPath $counterTest
}
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get gagal.' }
& dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { throw 'Pembuatan ikon aplikasi gagal.' }
& dart format lib test
if ($LASTEXITCODE -ne 0) { throw 'dart format gagal.' }
& flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze gagal.' }
& flutter test --concurrency=1
if ($LASTEXITCODE -ne 0) { throw 'flutter test gagal.' }
Write-Output 'Selesai. Jalankan flutter run pada perangkat Android. Lihat README untuk iOS.'
