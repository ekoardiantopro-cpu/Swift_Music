# Wrapper lokal: memakai SDK yang terpasang tanpa mengubah PATH sistem.
# Contoh: powershell -ExecutionPolicy Bypass -File tool/flutter.ps1 test
$ErrorActionPreference = 'Stop'
$flutterRoot = $env:FLUTTER_ROOT
if (-not $flutterRoot) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
    } else {
        $flutterRoot = Join-Path $env:USERPROFILE 'develop/flutter'
    }
}
$flutterExecutable = Join-Path $flutterRoot 'bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutterExecutable)) {
    throw 'Flutter tidak ditemukan. Set FLUTTER_ROOT ke lokasi SDK Flutter Anda.'
}
$mingitPath = Join-Path $env:USERPROFILE 'develop/mingit/cmd'
$env:PATH = (Join-Path $flutterRoot 'bin') + ';' + $mingitPath + ';' + $env:PATH
if (-not $env:ANDROID_HOME) {
    $androidCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Android/Sdk'),
        (Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/sdk')
    )
    foreach ($candidate in $androidCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $env:ANDROID_HOME = $candidate
            break
        }
    }
}
if (-not $env:JAVA_HOME) {
    $javaDirectory = Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/java'
    if (Test-Path -LiteralPath $javaDirectory) {
        $javaCandidate = Get-ChildItem -LiteralPath $javaDirectory -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe') } |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($javaCandidate) { $env:JAVA_HOME = $javaCandidate.FullName }
    }
}
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
& $flutterExecutable @args
exit $LASTEXITCODE
