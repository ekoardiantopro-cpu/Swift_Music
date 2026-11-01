# Removes ONLY the generated codec fixtures, verified by SHA-256, from the test
# emulator. Never uninstalls the app, wipes data or deletes unknown music files.
param([string]$Serial = 'emulator-5580')
$ErrorActionPreference = 'Stop'
$adbExecutable = Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/sdk/platform-tools/adb.exe'
$fixtureRoot = (Resolve-Path -LiteralPath 'build/audio-fixtures').Path
$fixtures = Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse
if ($fixtures.Count -ne 15) { throw 'Fixture set tidak sesuai; cleanup dibatalkan.' }
$rows = foreach ($file in $fixtures) {
    if ($file.Name -ne 'ignore.txt' -and $file.Name -notmatch '^(?:\d{2} Test [A-Za-z0-9 ]+|Broken audio|Copy of MP3)\.[a-z0-9]+$') {
        throw 'Nama di luar fixture uji; cleanup dibatalkan.'
    }
    $relative = $file.FullName.Substring($fixtureRoot.Length + 1).Replace('\','/')
    if ($relative -match "[^A-Za-z0-9 ./]" -or $relative.Contains('..')) { throw 'Path fixture tidak aman.' }
    [pscustomobject]@{ Relative = $relative; Extension = $file.Extension.Substring(1); Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$lines = @(
    'set -eu',
    'target=$(readlink -f /data/user/0/com.swiftmusic.swift_music/files/local_music)',
    'case "$target" in /data/user/0/com.swiftmusic.swift_music/files/local_music|/data/data/com.swiftmusic.swift_music/files/local_music) ;; *) echo "Invalid app directory"; exit 2 ;; esac',
    'test -d "$target"',
    'delete_audio() { hash="$1"; ext="$2"; audio="$target/$hash.$ext"; record="$target/$hash.json"; if [ -f "$audio" ] && [ -f "$record" ]; then actual=$(sha256sum "$audio" | cut -d" " -f1); test "$actual" = "$hash"; grep -Fq "\"id\":\"local-$hash\"" "$record"; rm -- "$audio" "$record"; echo "Removed test audio $hash"; fi; }'
)
$seen = [Collections.Generic.HashSet[string]]::new()
foreach ($row in $rows) {
    if ($row.Extension -ne 'txt' -and $seen.Add($row.Hash)) { $lines += ('delete_audio {0} {1}' -f $row.Hash,$row.Extension) }
}
if ($seen.Count -ne 13) { throw 'Hash fixture tidak sesuai; cleanup dibatalkan.' }
$lines += @(
    'external=$(readlink -f /sdcard/Music/SwiftFolderTest)',
    'case "$external" in /storage/emulated/0/Music/SwiftFolderTest) ;; *) echo "Invalid source directory"; exit 3 ;; esac',
    'delete_source() { file="$external/$1"; expected="$2"; if [ -f "$file" ]; then actual=$(sha256sum "$file" | cut -d" " -f1); if [ "$actual" = "$expected" ]; then rm -- "$file"; fi; fi; }'
)
foreach ($row in $rows) { $lines += ("delete_source '{0}' {1}" -f $row.Relative,$row.Hash) }
$lines += 'rmdir "$external/Nested" 2>/dev/null || true'
$lines += 'rmdir "$external" 2>/dev/null || true'
$scriptPath = Join-Path (Get-Location) 'build/cleanup-codec-fixtures.sh'
[IO.File]::WriteAllText($scriptPath, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$wasRoot = ((& $adbExecutable -s $Serial shell id -u) -join '').Trim() -eq '0'
& $adbExecutable -s $Serial shell am force-stop com.swiftmusic.swift_music
try {
    & $adbExecutable -s $Serial root
    & $adbExecutable -s $Serial wait-for-device
    if (((& $adbExecutable -s $Serial shell id -u) -join '').Trim() -ne '0') { throw 'Emulator tidak mengizinkan cleanup fixture sandbox.' }
    & $adbExecutable -s $Serial push $scriptPath /data/local/tmp/swift-cleanup-fixtures.sh
    & $adbExecutable -s $Serial shell sh /data/local/tmp/swift-cleanup-fixtures.sh
    if ($LASTEXITCODE -ne 0) { throw 'Cleanup dihentikan oleh pemeriksaan keamanan.' }
} finally {
    if (-not $wasRoot) { & $adbExecutable -s $Serial unroot; & $adbExecutable -s $Serial wait-for-device }
}
