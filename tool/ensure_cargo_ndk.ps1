$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $repoRoot 'build-tools'
$zipPath = Join-Path $toolRoot 'cargo-ndk-x86_64-pc-windows-msvc-v4.1.2.zip'
$installDir = Join-Path $toolRoot 'cargo-ndk'
$exePath = Join-Path $installDir 'cargo-ndk-x86_64-pc-windows-msvc-v4.1.2\cargo-ndk.exe'
$expectedHash = 'e2687c647748a8fb1c06981a4fc39376a5b5f640474db3f73de7ae247b7c55e0'

if (-not (Test-Path -LiteralPath $exePath)) {
    New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
    Invoke-WebRequest `
        -Uri 'https://github.com/bbqsrc/cargo-ndk/releases/download/v4.1.2/cargo-ndk-x86_64-pc-windows-msvc-v4.1.2.zip' `
        -OutFile $zipPath
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw 'Checksum cargo-ndk tidak cocok.' }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $installDir -Force
}

if (-not (Test-Path -LiteralPath $exePath)) { throw 'Executable cargo-ndk tidak ditemukan setelah instalasi.' }
