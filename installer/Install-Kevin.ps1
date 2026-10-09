[CmdletBinding()]
param([string]$GamePath, [switch]$AllowIsolatedCandidate)

. (Join-Path $PSScriptRoot 'KevinLoader.Common.ps1')
Assert-KevinClosed
if ($AllowIsolatedCandidate -and -not $GamePath) { throw 'Candidate testing requires an explicit isolated -GamePath.' }
$game = if ($AllowIsolatedCandidate) { Find-KevinGame $GamePath } else { $null }
$manifest = Get-KevinManifest $PSScriptRoot $game ([bool]$AllowIsolatedCandidate)
if (-not $game) { $game = Find-KevinGame $GamePath }
Assert-KevinGame $game $manifest
Repair-KevinPending $game
$statePath = Resolve-KevinPath $game '.KevinLoader/state.json'
$manifestHash = Get-KevinHash (Join-Path $PSScriptRoot 'manifest.json')
$upgradeRecords = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $previous = Read-KevinJson $statePath
    if ($previous.format -ne 'kevin-installed-v1' -or $previous.gameRoot -ne $game -or
        $previous.nativeModUuid -ne $script:KevinUuid -or $previous.status -notin @('installed','disabled')) {
        throw 'Invalid existing loader installation records.'
    }
    if ($previous.buildId -ne $manifest.buildId) {
        $upgradeRecords = Get-KevinApprovedUpgrade $manifest $previous
    } elseif ($previous.manifestSha256 -ne $manifestHash) {
        throw 'This build ID has different manifest bytes. A new build ID and explicit upgrade approval are required.'
    } elseif ($previous.status -eq 'installed') {
        foreach ($file in @($previous.files)) { Assert-KevinFile (Resolve-KevinPath $game $file.gamePath) $file.afterHash }
        Write-Host 'This Kevin loader build is already installed. Select Kevin Companion in the profile Mods list.'
        return
    }
}

# Check the complete release and every source before staging or changing files.
$expectedCore = @('UDKGame/CookedPC/ColdGame.u', 'UDKGame/CookedPC/Maps/ColdMaps/ColdIntroLogos.udk',
    'UDKGame/CookedPC/Maps/ColdMaps/ColdMenuMap.udk', 'UDKGame/CookedPC/Maps/ColdMaps/ColdMap1.udk')
$plans = @(); $seen = @{}
foreach ($entry in @($manifest.patches)) {
    $patchPath = Resolve-KevinPath $PSScriptRoot $entry.patch
    Assert-KevinFile $patchPath $entry.sha256
    $patch = Read-KevinJson $patchPath
    if ($patch.format -ne 'kevin-copy-patch-v1' -or $patch.gamePath -notin $expectedCore -or $seen.ContainsKey($patch.gamePath)) { throw 'Unexpected or duplicate core patch.' }
    $seen[$patch.gamePath] = $true
    $target = Resolve-KevinPath $game $patch.gamePath
    $originalSource = $target
    if ($null -ne $upgradeRecords) {
        $old = $upgradeRecords[$patch.gamePath]
        if (-not $old.beforeExists -or $old.beforeHash -ne $patch.source.sha256) { throw 'Upgrade uses a different original game version.' }
        $originalSource = Resolve-KevinPath $game $old.backup
        Assert-KevinFile $originalSource $patch.source.sha256 $patch.source.length
        $current = Get-KevinHash $target
        if (($previous.status -eq 'disabled' -and $current -ne $old.beforeHash) -or
            ($current -ne $old.beforeHash -and $current -ne $old.afterHash)) {
            throw 'Core files changed after the approved predecessor installation.'
        }
    } else { Assert-KevinFile $target $patch.source.sha256 $patch.source.length }
    Assert-KevinFile (Resolve-KevinPath ([IO.Path]::GetDirectoryName($patchPath)) $patch.payload.file) $patch.payload.sha256 $patch.payload.length
    $plans += [pscustomobject]@{ patchPath=$patchPath; patch=$patch; target=$target; original=$originalSource }
}
if ($seen.Count -ne $expectedCore.Count) { throw 'Not all required game entry points are covered.' }
$seenFiles = @{}
foreach ($entry in @($manifest.files)) {
    if ($entry.role -eq 'compatibility-package') {
        if ($entry.gamePath -ne 'UDKGame/CookedPC/KevinCompanion.u' -or -not $entry.retainOnDisable) { throw 'Invalid save compatibility package policy.' }
    } elseif ($entry.role -eq 'native-mod-metadata') {
        if ($entry.gamePath -ne 'UDKGame/Mods/Local/Kevin Companion/mod.json' -or -not $entry.retainOnDisable) { throw 'Invalid native mod metadata target.' }
    } else { throw 'Unknown release file role.' }
    if ($seenFiles.ContainsKey($entry.role)) { throw 'Duplicate release file role.' }; $seenFiles[$entry.role] = $true
    $source = Resolve-KevinPath $PSScriptRoot $entry.source
    Assert-KevinFile $source $entry.sha256 $entry.length
    if ($entry.role -eq 'native-mod-metadata' -and (Read-KevinJson $source).uuid -ne $script:KevinUuid) { throw 'Native mod UUID mismatch.' }
    $target = Resolve-KevinPath $game $entry.gamePath
    if ($null -ne $upgradeRecords) {
        Assert-KevinFile $target $upgradeRecords[$entry.gamePath].afterHash
    } elseif (Test-Path -LiteralPath $target) { Assert-KevinFile $target $entry.sha256 $entry.length }
}
if ($seenFiles.Count -ne 2) { throw 'Required package or native metadata role is missing.' }

$transaction = '.KevinLoader/transactions/' + [guid]::NewGuid().ToString('N')
$directory = Resolve-KevinPath $game $transaction
[void][IO.Directory]::CreateDirectory($directory)
$actions = @(); $index = 0
foreach ($plan in $plans) {
    $stage = Join-Path $directory ("stage-$index.bin"); $index++
    [void](Write-KevinPatch $plan.original $plan.patchPath $stage)
    $actions += New-KevinAction $game $plan.patch.gamePath $stage 'core-patch'
}
foreach ($entry in @($manifest.files)) {
    $stage = Join-Path $directory ("stage-$index.bin"); $index++
    [IO.File]::Copy((Resolve-KevinPath $PSScriptRoot $entry.source), $stage, $false)
    Assert-KevinFile $stage $entry.sha256 $entry.length
    $actions += New-KevinAction $game $entry.gamePath $stage $entry.role ([bool]$entry.retainOnDisable)
}
$config = Resolve-KevinPath $game $script:KevinConfigPath
$oldConfig = if (Test-Path -LiteralPath $config -PathType Leaf) { [IO.File]::ReadAllText($config) } else { '' }
$configStage = Join-Path $directory 'enabled.ini'
[IO.File]::WriteAllText($configStage, (Set-KevinConfig $oldConfig $true), (New-Object Text.UTF8Encoding($false)))
$actions += New-KevinAction $game $script:KevinConfigPath $configStage 'activation-config' $true
$state = [pscustomobject]@{ format='kevin-installed-v1'; status='installed'; buildId=$manifest.buildId;
    nativeModUuid=$script:KevinUuid; gameRoot=$game; gameExecutables=@($manifest.gameExecutables);
    manifestSha256=$manifestHash; files=@();
    installedUtc=[DateTime]::UtcNow.ToString('o'); compatibilityPolicy='Retain the complete KevinCompanion.u while any saves may reference it.' }
if ($null -ne $upgradeRecords) {
    $state | Add-Member -NotePropertyName upgradedFrom -NotePropertyValue ([pscustomobject]@{
        buildId=$previous.buildId;manifestSha256=$previous.manifestSha256;status=$previous.status})
}
Invoke-KevinTransaction $game $transaction $actions $state $upgradeRecords
Write-Host 'Kevin loader installed. Select Kevin Companion in your profile Mods list, then start or continue the game.'
Write-Host 'Backups and installation records are stored in the game directory under .KevinLoader.'
