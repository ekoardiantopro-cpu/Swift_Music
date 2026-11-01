# Manual Android audit helper. Import build/audio-fixtures via the app first,
# open Search in the 540x960/210dpi test emulator, then run this script.
param([string]$Serial = 'emulator-5580')
$ErrorActionPreference = 'Stop'
$adbExecutable = Join-Path $env:LOCALAPPDATA 'SwiftOSAndroid/sdk/platform-tools/adb.exe'
$queries = @('01','02','03','04','05','06','07','08','09','10','11','12','Broken','04')
$results = @()
foreach ($query in $queries) {
    & $adbExecutable -s $Serial shell input tap 480 177
    & $adbExecutable -s $Serial shell input tap 220 177
    & $adbExecutable -s $Serial shell input text $query
    & $adbExecutable -s $Serial shell input keyevent 4
    Start-Sleep -Milliseconds 250
    & $adbExecutable -s $Serial shell input tap 220 350
    Start-Sleep -Milliseconds 1800
    $sessionDump = (& $adbExecutable -s $Serial shell dumpsys media_session) -join "`n"
    $stateMatches = [regex]::Matches($sessionDump, 'state=PlaybackState \{state=([^,]+), position=(\d+)[^\r\n]*')
    $metadataMatches = [regex]::Matches($sessionDump, 'metadata:.*description=([^\r\n]+)')
    $state = if ($stateMatches.Count) { $stateMatches[$stateMatches.Count - 1] } else { $null }
    $metadata = if ($metadataMatches.Count) { $metadataMatches[$metadataMatches.Count - 1].Groups[1].Value.Trim() } else { '' }
    $record = [ordered]@{
        query = $query
        state = if ($state) { $state.Groups[1].Value } else { 'MISSING' }
        position = if ($state) { [long]$state.Groups[2].Value } else { 0 }
        metadata = $metadata
        detail = if ($state) { $state.Value } else { '' }
    }
    $results += [pscustomobject]$record
    Write-Output ('{0}: {1} - {2}' -f $query, $record.state, $metadata)
    & $adbExecutable -s $Serial shell input keyevent 127
}
$reportPath = Join-Path (Get-Location) 'build/codec-audit.json'
[IO.File]::WriteAllText($reportPath, ($results | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
