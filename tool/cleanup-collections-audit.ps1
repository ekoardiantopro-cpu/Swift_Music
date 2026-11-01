# Only remove the three synthetic external files created by the 1.2.0 audit.
param([string]$Serial = 'emulator-5580')
$ErrorActionPreference = 'Stop'
$adbExecutable = Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/sdk/platform-tools/adb.exe'
$auditFiles = @(
    @('build/collection-fixtures/tagged.mp3', '/sdcard/Music/SwiftCollectionsAudit/tagged.mp3'),
    @('build/collection-fixtures/new.flac', '/sdcard/Music/SwiftCollectionsAudit/new.flac'),
    @('build/collection-fixtures/timed.lrc', '/sdcard/Download/SwiftTimed.lrc')
)
foreach ($auditFile in $auditFiles) {
    $expectedHash = (Get-FileHash -LiteralPath $auditFile[0] -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteHash = (& $adbExecutable -s $Serial shell sha256sum $auditFile[1]) -join ''
    if ($LASTEXITCODE -ne 0 -or !$remoteHash.StartsWith($expectedHash)) { throw "Synthetic fixture differs: $($auditFile[1])" }
}
foreach ($auditFile in $auditFiles) {
    & $adbExecutable -s $Serial shell rm -- $auditFile[1]
    if ($LASTEXITCODE -ne 0) { throw "Cannot remove verified fixture: $($auditFile[1])" }
}
# rmdir fails safely if anything else is present. No recursive deletion.
& $adbExecutable -s $Serial shell rmdir /sdcard/Music/SwiftCollectionsAudit
