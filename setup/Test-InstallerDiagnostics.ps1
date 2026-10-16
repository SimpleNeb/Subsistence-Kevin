[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('Kevin-Diagnostics-' + [guid]::NewGuid().ToString('N'))))

# Runs the real installer against synthetic, isolated files. Never reads or
# launches a retail game, changes permissions, or restores a user's backups.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'installer/KevinLoader.Common.ps1')
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'Choose a new diagnostics output directory.' }
[void][IO.Directory]::CreateDirectory($outputRoot)
$script:passed = 0
function Check([bool]$Value, [string]$Message) {
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:passed++
    Write-Output ('PASS: ' + $Message)
}
function Put-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Snapshot([string]$Root) {
    $snapshot = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Force -Recurse)) {
        $snapshot[$file.FullName.Substring($Root.Length + 1)] = Get-KevinHash $file.FullName
    }
    return $snapshot
}
function Check-Unchanged([string]$Root, $Before, [string]$Label) {
    $after = Snapshot $Root
    Check ($after.Count -eq $Before.Count) ($Label + ': no files added or removed')
    $unchanged = $true
    foreach ($key in $Before.Keys) {
        if (-not $after.ContainsKey($key) -or $after[$key] -ne $Before[$key]) { $unchanged = $false }
    }
    Check $unchanged ($Label + ': all game files, save sentinel and original backup unchanged')
    Check (-not (Test-Path -LiteralPath (Join-Path $Root '.KevinLoader'))) ($Label + ': no transaction or installation state created')
}
function New-Fixture([string]$Name) {
    $base = Join-Path $outputRoot $Name
    $package = Join-Path $base 'package'
    $gameRoot = Join-Path $base 'game'
    [void][IO.Directory]::CreateDirectory($package)
    foreach ($scriptName in @('Install-Kevin.ps1','Disable-Kevin.ps1','KevinLoader.Common.ps1')) {
        [IO.File]::Copy((Join-Path $project ('installer/' + $scriptName)), (Join-Path $package $scriptName), $false)
    }
    $exe = Join-Path $gameRoot 'Binaries/Win64/Subsistence.exe'
    Put-Text $exe 'Synthetic executable fixture; never run.'
    Put-Text (Join-Path $gameRoot 'UDKGame/SaveData/preserve.sav') 'Save sentinel must survive every test.'
    $corePaths = @('UDKGame/CookedPC/ColdGame.u','UDKGame/CookedPC/Maps/ColdMaps/ColdIntroLogos.udk',
        'UDKGame/CookedPC/Maps/ColdMaps/ColdMenuMap.udk','UDKGame/CookedPC/Maps/ColdMaps/ColdMap1.udk')
    $patches = @()
    foreach ($relative in $corePaths) {
        $name = [IO.Path]::GetFileName($relative)
        $original = Join-Path $gameRoot $relative
        $originalText = 'Original synthetic bytes for ' + $name
        Put-Text $original $originalText
        $patchRelative = 'patches/' + $name + '.json'
        $payload = Join-Path $package ('patches/' + $name + '.bin')
        Put-Text $payload '|Kevin fixture hook'
        $expectedOutput = Join-Path $base ($name + '.expected')
        Put-Text $expectedOutput ($originalText + '|Kevin fixture hook')
        $patch = [ordered]@{
            format='kevin-copy-patch-v1'; gamePath=$relative
            source=@{ sha256=(Get-KevinHash $original); length=(Get-Item -LiteralPath $original).Length }
            payload=@{ file=($name + '.bin'); sha256=(Get-KevinHash $payload); length=(Get-Item -LiteralPath $payload).Length }
            output=@{ sha256=(Get-KevinHash $expectedOutput); length=(Get-Item -LiteralPath $expectedOutput).Length }
            operations=@(@{kind='copy';offset=0;length=(Get-Item -LiteralPath $original).Length},
                @{kind='data';offset=0;length=(Get-Item -LiteralPath $payload).Length})
        }
        Write-KevinJson (Join-Path $package $patchRelative) $patch
        $patches += @{ patch=$patchRelative; sha256=(Get-KevinHash (Join-Path $package $patchRelative)) }
    }
    $originalCore = Join-Path $gameRoot $corePaths[0]
    [IO.File]::Copy($originalCore, ($originalCore + '.harding-code-probe-original'), $false)
    Put-Text (Join-Path $package 'files/KevinCompanion.u') 'Synthetic compatibility package.'
    Put-Text (Join-Path $package 'files/mod.json') ('{"uuid":"' + $script:KevinUuid + '"}')
    $files = @()
    foreach ($entry in @(
        @{source='files/KevinCompanion.u';gamePath='UDKGame/CookedPC/KevinCompanion.u';role='compatibility-package'},
        @{source='files/mod.json';gamePath='UDKGame/Mods/Local/Kevin Companion/mod.json';role='native-mod-metadata'})) {
        $source = Join-Path $package $entry.source
        $files += @{source=$entry.source;gamePath=$entry.gamePath;role=$entry.role;retainOnDisable=$true;
            sha256=(Get-KevinHash $source);length=(Get-Item -LiteralPath $source).Length}
    }
    $manifest = [ordered]@{
        format='kevin-loader-v1';releaseStatus='VALIDATED';nativeModUuid=$script:KevinUuid;buildId='synthetic-diagnostic-test'
        gameExecutables=@(@{gamePath='Binaries/Win64/Subsistence.exe';sha256=(Get-KevinHash $exe);length=(Get-Item -LiteralPath $exe).Length})
        patches=$patches;files=$files
    }
    Write-KevinJson (Join-Path $package 'manifest.json') $manifest
    return [pscustomobject]@{ game=$gameRoot;package=$package;core=$originalCore;corePaths=$corePaths }
}

# First demonstrate that this fixture reaches the real commit/disable paths;
# subsequent rejections cannot be caused by an incomplete synthetic manifest.
$clean = New-Fixture 'clean'
$beforeClean = Snapshot $clean.game
& (Join-Path $clean.package 'Install-Kevin.ps1') -GamePath $clean.game
$state = Read-KevinJson (Join-Path $clean.game '.KevinLoader/state.json')
Check ($state.status -eq 'installed') 'valid fixture passes the actual installer'
foreach ($relative in $clean.corePaths) {
    $expected = Join-Path (Split-Path -Parent $clean.game) ([IO.Path]::GetFileName($relative) + '.expected')
    Check ((Get-KevinHash (Join-Path $clean.game $relative)) -eq (Get-KevinHash $expected)) ('actual patch output verified: ' + [IO.Path]::GetFileName($relative))
}
& (Join-Path $clean.package 'Disable-Kevin.ps1') -GamePath $clean.game
foreach ($relative in $clean.corePaths) {
    Check ((Get-KevinHash (Join-Path $clean.game $relative)) -eq $beforeClean[$relative.Replace('/', '\')]) ('Disable restores original: ' + [IO.Path]::GetFileName($relative))
}
Check ((Get-KevinHash (Join-Path $clean.game 'UDKGame/SaveData/preserve.sav')) -eq $beforeClean['UDKGame\SaveData\preserve.sav']) 'valid install/disable preserves save sentinel'

foreach ($case in @('same-length-edit','wrong-length')) {
    $fixture = New-Fixture $case
    $originalHash = Get-KevinHash $fixture.core
    $originalLength = (Get-Item -LiteralPath $fixture.core).Length
    $changed = [IO.File]::ReadAllBytes($fixture.core)
    $changed[0] = $changed[0] -bxor 1
    if ($case -eq 'wrong-length') { $changed = [byte[]]($changed + [byte]0) }
    [IO.File]::WriteAllBytes($fixture.core, $changed)
    $actualHash = Get-KevinHash $fixture.core
    $before = Snapshot $fixture.game
    $failure = $null
    try { & (Join-Path $fixture.package 'Install-Kevin.ps1') -GamePath $fixture.game } catch { $failure = $_.Exception.Message }
    Check ($null -ne $failure) ($case + ': actual installer refuses changed source')
    $prefix = if ($case -eq 'wrong-length') { 'File length mismatch:' } else { 'File version/checksum mismatch:' }
    Check ($failure.StartsWith($prefix)) ($case + ': preserves the specific mismatch reason')
    Check ($failure.Contains($fixture.core) -and $failure.Contains('Expected SHA256: ' + $originalHash) -and
        $failure.Contains('Actual SHA256: ' + $actualHash)) ($case + ': reports exact path and both SHA256 values')
    Check ($failure.Contains('Expected length: ' + $originalLength) -and $failure.Contains('Actual length: ' + $changed.Length)) ($case + ': reports both lengths')
    Check-Unchanged $fixture.game $before $case
}

$hashOnlyFailure = $null
try { Assert-KevinFile $fixture.core $originalHash } catch { $hashOnlyFailure = $_.Exception.Message }
Check ($null -ne $hashOnlyFailure -and $hashOnlyFailure.Contains('Expected length: not specified') -and
    $hashOnlyFailure.Contains('Actual SHA256: ' + $actualHash)) 'hash-only state checks include available diagnostics without inventing a length'
Assert-KevinFile $fixture.core $actualHash $changed.Length
Check $true 'matching hash and length remain accepted'
$report = [ordered]@{passed=$script:passed;failed=0;syntheticFixturesOnly=$true;gameLaunched=$false;
    cases=@('valid-install-disable','same-length-edit','wrong-length','hash-only');outputDirectory=$outputRoot}
Write-KevinJson (Join-Path $outputRoot 'test-results.json') $report
$report | ConvertTo-Json -Depth 5
