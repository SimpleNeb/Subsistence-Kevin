[CmdletBinding()]
param([string]$GamePath)

. (Join-Path $PSScriptRoot 'KevinLoader.Common.ps1')
Assert-KevinClosed
$game = Find-KevinGame $GamePath
Repair-KevinPending $game
$statePath = Resolve-KevinPath $game '.KevinLoader/state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'No Kevin loader installation record was found at this game path.' }
$state = Read-KevinJson $statePath
if ($state.format -ne 'kevin-installed-v1' -or $state.gameRoot -ne $game -or $state.nativeModUuid -ne $script:KevinUuid -or $state.status -notin @('installed','disabled')) {
    throw 'Invalid Kevin installation record.'
}
Assert-KevinGame $game $state
$restores = @()
foreach ($file in @($state.files)) {
    $target = Resolve-KevinPath $game $file.gamePath
    if ($file.role -eq 'core-patch') {
        if (-not $file.beforeExists) { throw 'A core file has no original backup record.' }
        $backup = Resolve-KevinPath $game $file.backup
        Assert-KevinFile $backup $file.beforeHash
        $currentHash = Get-KevinHash $target
        if ($currentHash -ne $file.beforeHash -and $currentHash -ne $file.afterHash) { throw "The game changed after installation. No files were changed: $target" }
        if ($currentHash -eq $file.afterHash) { $restores += $file }
    } elseif ($file.role -in @('compatibility-package','native-mod-metadata')) {
        Assert-KevinFile $target $file.afterHash
        if (-not $file.retainOnDisable) { throw 'Refusing a policy that removes save compatibility files.' }
    } elseif ($file.role -ne 'activation-config') { throw 'Unknown installed file role.' }
}

$transaction = '.KevinLoader/transactions/' + [guid]::NewGuid().ToString('N')
$directory = Resolve-KevinPath $game $transaction
[void][IO.Directory]::CreateDirectory($directory)
$config = Resolve-KevinPath $game $script:KevinConfigPath
$oldConfig = if (Test-Path -LiteralPath $config -PathType Leaf) { [IO.File]::ReadAllText($config) } else { '' }
$stage = Join-Path $directory 'disabled.ini'
[IO.File]::WriteAllText($stage, (Set-KevinConfig $oldConfig $false), (New-Object Text.UTF8Encoding($false)))
# Global opt-out is the first committed change, including for saved registries
# whose native Workshop UUID remains selected. Profiles and saves are untouched.
$actions = @(New-KevinAction $game $script:KevinConfigPath $stage 'activation-config' $true)
$index = 0
foreach ($file in $restores) {
    $stage = Join-Path $directory ("restore-$index.bin"); $index++
    [IO.File]::Copy((Resolve-KevinPath $game $file.backup), $stage, $false)
    Assert-KevinFile $stage $file.beforeHash
    $actions += New-KevinAction $game $file.gamePath $stage 'core-restore'
}
$state.status = 'disabled'
Invoke-KevinTransaction $game $transaction $actions $state
Write-Host 'Kevin is globally disabled and the original game loader files are restored.'
Write-Host 'The complete KevinCompanion.u, native mod entry, saves, and backups were retained for save compatibility.'
