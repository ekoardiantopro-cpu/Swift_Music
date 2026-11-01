# Jalankan di terminal tersendiri; tutup jendela emulator untuk mengakhiri sesi.
# Tidak memakai wipe-data dan tidak menghapus atau mereset profil lain.
param([string]$AvdName = 'SwiftMusic_API36')
$ErrorActionPreference = 'Stop'
$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) {
    $sdkRoot = Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/sdk'
}
$emulatorExecutable = Join-Path $sdkRoot 'emulator/emulator.exe'
if (-not (Test-Path -LiteralPath $emulatorExecutable)) {
    throw 'Emulator tidak ditemukan. Set ANDROID_HOME ke lokasi Android SDK.'
}
Write-Output "Menjalankan $AvdName. Biarkan terminal ini tetap terbuka."
& $emulatorExecutable -avd $AvdName -gpu auto -no-snapshot -no-boot-anim -cores 2 -port 5580
exit $LASTEXITCODE
