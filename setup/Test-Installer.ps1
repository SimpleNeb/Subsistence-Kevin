[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BundlePath,
    [Parameter(Mandatory=$true)][string]$GameSource,
    [string]$PreviousBundle
)

# Exercise the actual released scripts against disposable copies of retail files.
# GameSource is read only. No game process, Steam operation or elevation is started.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$directory = Join-Path $project ('build/installer-tests/' + [guid]::NewGuid().ToString('N'))
$sourceRoot = (Resolve-Path -LiteralPath $GameSource).Path
$powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { throw 'Windows PowerShell 5.1 is required.' }
$corePaths = @(
    'UDKGame/CookedPC/ColdGame.u',
    'UDKGame/CookedPC/Maps/ColdMaps/ColdIntroLogos.udk',
    'UDKGame/CookedPC/Maps/ColdMaps/ColdMenuMap.udk',
    'UDKGame/CookedPC/Maps/ColdMaps/ColdMap1.udk'
)
$configPath = 'UDKGame/Config/UDKKevin.ini'
$sentinelPath = 'UDKGame/SaveData/installer-regression-sentinel.sav'
$script:passed = 0
$script:runs = @()
$script:fixtures = @()

function Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Check([bool]$Value, [string]$Message) {
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:passed++
    Write-Output ('PASS: ' + $Message)
}
function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Child-Path([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains(':') -or @($Relative -split '[/\\]' | Where-Object { $_ -in @('..','.','') }).Count) {
        throw "Unsafe fixture or bundle path: $Relative"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $result = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $result.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path leaves its intended directory.'
    }
    # A parent junction could redirect a test write into the real game.
    $walk = $result
    while ($walk) {
        if (Test-Path -LiteralPath $walk) {
            if ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked paths are not supported by this test: $walk"
            }
        }
        $next = [IO.Path]::GetDirectoryName($walk)
        if ($next -eq $walk) { break }
        $walk = $next
    }
    return $result
}
function Copy-Verified([string]$Source, [string]$Destination, [string]$ExpectedHash) {
    if ((Hash $Source) -ne $ExpectedHash) { throw "Source does not match the release: $Source" }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
    [IO.File]::Copy($Source, $Destination, $false)
    if ((Hash $Destination) -ne $ExpectedHash) { throw "Fixture copy failed verification: $Destination" }
}
function Open-Bundle([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        if ([IO.Path]::GetExtension($resolved) -ine '.zip') { throw 'Bundle must be an extracted directory or ZIP.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extracted = Child-Path $directory ('bundles/' + $Label)
        [void][IO.Directory]::CreateDirectory($extracted)
        $archive = [IO.Compression.ZipFile]::OpenRead($resolved)
        try {
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('\','/').TrimEnd('/')
                if (-not $name) { continue }
                $target = Child-Path $extracted $name
                if ($entry.FullName.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($target); continue }
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
        } finally { $archive.Dispose() }
        $manifests = @(Get-ChildItem -LiteralPath $extracted -Filter manifest.json -File -Recurse)
        if ($manifests.Count -ne 1) { throw 'Bundle ZIP must contain exactly one manifest.' }
        $resolved = $manifests[0].DirectoryName
    }
    $manifestFile = Child-Path $resolved 'manifest.json'
    $manifest = Read-Json $manifestFile
    if ($manifest.format -ne 'kevin-loader-v1' -or $manifest.releaseStatus -ne 'VALIDATED') {
        throw 'These tests require the finalized VALIDATED release bundle.'
    }
    $patches = @{}
    foreach ($entry in @($manifest.patches)) {
        $patchPath = Child-Path $resolved $entry.patch
        if ((Hash $patchPath) -ne $entry.sha256) { throw 'Bundle patch checksum mismatch.' }
        $patch = Read-Json $patchPath
        if ($patch.gamePath -notin $corePaths -or $patches.ContainsKey($patch.gamePath)) { throw 'Unexpected patch target.' }
        $patches[$patch.gamePath] = $patch
    }
    if ($patches.Count -ne 4) { throw 'All four core patches are required.' }
    return [pscustomobject]@{ root=$resolved; manifest=$manifest; manifestHash=(Hash $manifestFile); patches=$patches }
}
function Find-Pristine([string]$Relative, [string]$ExpectedHash) {
    $current = Child-Path $sourceRoot $Relative
    if ((Hash $current) -eq $ExpectedHash) { return $current }
    if ($Relative -eq 'UDKGame/CookedPC/ColdGame.u') {
        $backup = Child-Path $sourceRoot ($Relative + '.harding-code-probe-original')
        if ((Test-Path -LiteralPath $backup -PathType Leaf) -and (Hash $backup) -eq $ExpectedHash) { return $backup }
    }
    # An installed source game keeps the pristine map inputs in its loader
    # transaction backups. Records locate bytes; release hashes authorize them.
    $statePath = Child-Path $sourceRoot '.KevinLoader/state.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Read-Json $statePath
        $records = @($state.files | Where-Object {
            $_.gamePath -eq $Relative -and $_.role -eq 'core-patch' -and
            $_.beforeExists -and $_.beforeHash -eq $ExpectedHash
        })
        if ($records.Count -eq 1) {
            $backup = Child-Path $sourceRoot $records[0].backup
            if ((Test-Path -LiteralPath $backup -PathType Leaf) -and (Hash $backup) -eq $ExpectedHash) { return $backup }
        }
    }
    throw "No checksum-verified pristine source is available for $Relative"
}
function New-Fixture([string]$Name, $Bundle) {
    $root = Child-Path $directory $Name
    [void][IO.Directory]::CreateDirectory($root)
    foreach ($entry in @($Bundle.manifest.gameExecutables)) {
        Copy-Verified (Child-Path $sourceRoot $entry.gamePath) (Child-Path $root $entry.gamePath) $entry.sha256
    }
    foreach ($relative in $corePaths) {
        $expected = $Bundle.patches[$relative].source.sha256
        Copy-Verified (Find-Pristine $relative $expected) (Child-Path $root $relative) $expected
    }
    $sourceConfig = Child-Path $sourceRoot $configPath
    $targetConfig = Child-Path $root $configPath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($targetConfig))
    if (Test-Path -LiteralPath $sourceConfig -PathType Leaf) {
        [IO.File]::Copy($sourceConfig, $targetConfig, $false)
    }
    [IO.File]::AppendAllText($targetConfig, "`r`n[KevinInstallerRegression]`r`nPreserveThisSetting=FixtureOnly`r`n", (New-Object Text.UTF8Encoding($false)))
    $sentinel = Child-Path $root $sentinelPath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($sentinel))
    [IO.File]::WriteAllText($sentinel, ('Fixture save sentinel: ' + [guid]::NewGuid().ToString('N')))
    $fixture = [pscustomobject]@{ root=$root; sentinelHash=(Hash $sentinel) }
    $script:fixtures += $fixture
    return $fixture
}
function Run-Installer($Bundle, $Fixture, [string]$Action, [string]$Label, [bool]$ExpectSuccess = $true) {
    $scriptPath = Child-Path $Bundle.root ($Action + '-Kevin.ps1')
    $quotedScript = "'" + $scriptPath.Replace("'", "''") + "'"
    $quotedGame = "'" + $Fixture.root.Replace("'", "''") + "'"
    $command = '$ErrorActionPreference = ''Stop''; try { & ' + $quotedScript + ' -GamePath ' + $quotedGame + '; exit 0 } catch { [Console]::Error.WriteLine(($_ | Out-String)); exit 1 }'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $powershell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.Result + $stderr.Result
        $code = $process.ExitCode
    } finally { $process.Dispose() }
    $log = Child-Path $directory ('logs/' + $Label + '.txt')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($log))
    [IO.File]::WriteAllText($log, $output, (New-Object Text.UTF8Encoding($false)))
    $script:runs += [pscustomobject]@{ label=$Label; action=$Action; build=$Bundle.manifest.buildId; game=$Fixture.root; exitCode=$code; log=$log }
    if (($code -eq 0) -ne $ExpectSuccess) { throw "FAIL: $Label exited $code. See $log`n$output" }
    $script:passed++
    Write-Host ('PASS: ' + $Label + ' exit status')
    return $output
}
function Check-Preserved($Fixture, [string]$Label) {
    Check ((Hash (Child-Path $Fixture.root $sentinelPath)) -eq $Fixture.sentinelHash) ($Label + ': save sentinel unchanged')
    Check ([IO.File]::ReadAllText((Child-Path $Fixture.root $configPath)).Contains('PreserveThisSetting=FixtureOnly')) ($Label + ': unrelated configuration preserved')
    Check (-not (Test-Path -LiteralPath (Child-Path $Fixture.root '.KevinLoader/pending.json'))) ($Label + ': no pending transaction')
}
function Check-Installed($Bundle, $Fixture, [string]$Label) {
    $state = Read-Json (Child-Path $Fixture.root '.KevinLoader/state.json')
    Check ($state.status -eq 'installed' -and $state.buildId -eq $Bundle.manifest.buildId -and
        $state.manifestSha256 -eq $Bundle.manifestHash) ($Label + ': correct installed release recorded')
    foreach ($relative in $corePaths) {
        Check ((Hash (Child-Path $Fixture.root $relative)) -eq $Bundle.patches[$relative].output.sha256) ($Label + ': patched ' + $relative)
        $records = @($state.files | Where-Object { $_.gamePath -eq $relative })
        Check ($records.Count -eq 1) ($Label + ': one original backup record for ' + $relative)
        $record = $records[0]
        Check ($record.beforeExists -and $record.beforeHash -eq $Bundle.patches[$relative].source.sha256 -and
            (Hash (Child-Path $Fixture.root $record.backup)) -eq $record.beforeHash) ($Label + ': verified pristine backup for ' + $relative)
    }
    foreach ($entry in @($Bundle.manifest.files)) {
        Check ((Hash (Child-Path $Fixture.root $entry.gamePath)) -eq $entry.sha256) ($Label + ': release file ' + $entry.gamePath)
    }
    Check-Preserved $Fixture $Label
}
function Check-Disabled($Bundle, $Fixture, [string]$Label) {
    $state = Read-Json (Child-Path $Fixture.root '.KevinLoader/state.json')
    Check ($state.status -eq 'disabled') ($Label + ': disabled state recorded')
    foreach ($relative in $corePaths) {
        Check ((Hash (Child-Path $Fixture.root $relative)) -eq $Bundle.patches[$relative].source.sha256) ($Label + ': pristine ' + $relative)
    }
    foreach ($entry in @($Bundle.manifest.files)) {
        Check ($entry.retainOnDisable -and (Hash (Child-Path $Fixture.root $entry.gamePath)) -eq $entry.sha256) ($Label + ': compatibility file retained ' + $entry.gamePath)
    }
    Check ([IO.File]::ReadAllText((Child-Path $Fixture.root $configPath)).Contains('bLoaderEnabled=False')) ($Label + ': loader disabled in configuration')
    Check-Preserved $Fixture $Label
}

# Validate the destination ancestry before the first write.
[void](Child-Path $project ('build/installer-tests/' + [IO.Path]::GetFileName($directory)))
[void][IO.Directory]::CreateDirectory($directory)
Write-Output ('Isolated test evidence: ' + $directory)
$bundle = Open-Bundle $BundlePath 'current'
$previous = if ($PreviousBundle) { Open-Bundle $PreviousBundle 'previous' } else { $null }
try {
    $fixture = New-Fixture 'fresh-game' $bundle
    $cold = Child-Path $fixture.root 'UDKGame/CookedPC/ColdGame.u'
    $sourceCold = Child-Path $sourceRoot 'UDKGame/CookedPC/ColdGame.u'
    $pristineHash = $bundle.patches['UDKGame/CookedPC/ColdGame.u'].source.sha256
    # A previously installed loader has a different length. Use its pristine
    # backup for fixtures, then corrupt only the fixture to test checksum errors.
    if ((Hash $sourceCold) -ne $pristineHash -and
        (Get-Item -LiteralPath $sourceCold).Length -eq $bundle.patches['UDKGame/CookedPC/ColdGame.u'].source.length) {
        [IO.File]::Copy($sourceCold, $cold, $true)
    } else {
        $stream = [IO.File]::Open($cold, 'Open', 'ReadWrite', 'None')
        try { $first = $stream.ReadByte(); $stream.Position = 0; $stream.WriteByte([byte]($first -bxor 1)) }
        finally { $stream.Dispose() }
    }
    $mismatchHash = Hash $cold
    $configBefore = Hash (Child-Path $fixture.root $configPath)
    $failure = Run-Installer $bundle $fixture 'Install' 'modified-source-rejected' $false
    Check ($failure -match 'checksum mismatch' -and $failure.Contains('ColdGame.u')) 'modified source reports the failing file/checksum'
    Check (-not (Test-Path -LiteralPath (Child-Path $fixture.root '.KevinLoader'))) 'modified source rejected before loader staging or state writes'
    Check ((Hash $cold) -eq $mismatchHash -and (Hash (Child-Path $fixture.root $configPath)) -eq $configBefore) 'rejected installation leaves input bytes and configuration unchanged'
    foreach ($relative in @($corePaths | Where-Object { $_ -ne 'UDKGame/CookedPC/ColdGame.u' })) {
        Check ((Hash (Child-Path $fixture.root $relative)) -eq $bundle.patches[$relative].source.sha256) ('rejected installation preserves ' + $relative)
    }
    foreach ($entry in @($bundle.manifest.files)) {
        Check (-not (Test-Path -LiteralPath (Child-Path $fixture.root $entry.gamePath))) ('rejected installation creates no ' + $entry.gamePath)
    }
    Check-Preserved $fixture 'rejected installation'
    [IO.File]::Copy((Find-Pristine 'UDKGame/CookedPC/ColdGame.u' $pristineHash), $cold, $true)
    Check ((Hash $cold) -eq $pristineHash) 'fixture restored to verified pristine input'
    [void](Run-Installer $bundle $fixture 'Install' 'fresh-install')
    Check-Installed $bundle $fixture 'fresh install'
    $stateBefore = Hash (Child-Path $fixture.root '.KevinLoader/state.json')
    $transactionsBefore = @(Get-ChildItem -LiteralPath (Child-Path $fixture.root '.KevinLoader/transactions') -Directory).Count
    [void](Run-Installer $bundle $fixture 'Install' 'repeat-install')
    Check ((Hash (Child-Path $fixture.root '.KevinLoader/state.json')) -eq $stateBefore -and
        @(Get-ChildItem -LiteralPath (Child-Path $fixture.root '.KevinLoader/transactions') -Directory).Count -eq $transactionsBefore) 'repeat install is idempotent without new state or transactions'
    Check-Installed $bundle $fixture 'repeat install'
    [void](Run-Installer $bundle $fixture 'Disable' 'disable-fresh')
    Check-Disabled $bundle $fixture 'disable fresh'
    [void](Run-Installer $bundle $fixture 'Install' 'reinstall-disabled')
    Check-Installed $bundle $fixture 'reinstall disabled'

    if ($null -ne $previous) {
        $upgrade = New-Fixture 'upgrade-game' $previous
        [void](Run-Installer $previous $upgrade 'Install' 'install-predecessor')
        Check-Installed $previous $upgrade 'predecessor install'
        $oldState = Read-Json (Child-Path $upgrade.root '.KevinLoader/state.json')
        [void](Run-Installer $bundle $upgrade 'Install' 'upgrade-current')
        Check-Installed $bundle $upgrade 'upgrade current'
        $newState = Read-Json (Child-Path $upgrade.root '.KevinLoader/state.json')
        Check ($newState.upgradedFrom.buildId -eq $previous.manifest.buildId -and
            $newState.upgradedFrom.manifestSha256 -eq $previous.manifestHash) 'upgrade records the exact predecessor'
        foreach ($relative in $corePaths) {
            $oldRecord = @($oldState.files | Where-Object { $_.gamePath -eq $relative })[0]
            $newRecord = @($newState.files | Where-Object { $_.gamePath -eq $relative })[0]
            Check ($newRecord.backup -eq $oldRecord.backup -and $newRecord.beforeHash -eq $oldRecord.beforeHash) ('upgrade preserves the original backup chain for ' + $relative)
        }
        [void](Run-Installer $bundle $upgrade 'Disable' 'disable-upgraded')
        Check-Disabled $bundle $upgrade 'disable upgraded'
    }
    $report = [ordered]@{ passed=$script:passed; failed=0; bundleBuild=$bundle.manifest.buildId;
        bundleManifestSha256=$bundle.manifestHash; previousBuild=$(if ($previous) { $previous.manifest.buildId } else { $null });
        gameSource=$sourceRoot; liveGameWritten=$false; gameLaunched=$false; fixtures=$script:fixtures; runs=$script:runs }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Child-Path $directory 'test-results.json') -Encoding UTF8
    $report | ConvertTo-Json -Depth 8
} catch {
    $report = [ordered]@{ passed=$script:passed; failed=1; error=($_ | Out-String); gameSource=$sourceRoot;
        liveGameWritten=$false; gameLaunched=$false; fixtures=$script:fixtures; runs=$script:runs }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Child-Path $directory 'test-results.json') -Encoding UTF8
    throw
}
