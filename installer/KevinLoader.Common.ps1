# Requires only Windows PowerShell 5.1 or PowerShell 7. No downloaded runtime.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:KevinUuid = '20b4beb3-1cc9-48e8-bcfc-c41410f6fdbf'
$script:KevinConfigPath = 'UDKGame/Config/UDKKevin.ini'

function Assert-KevinClosed {
    $running = @(Get-Process -Name Subsistence,UDK -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) { throw 'Close Subsistence and its development tools before changing the loader.' }
}

function Resolve-KevinPath([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains(':') -or @($Relative -split '[/\\]' | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count) {
        throw "Unsafe relative path: $Relative"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path leaves its intended directory.'
    }
    $walk = $full
    while ($walk.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $walk) {
            if (((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Linked paths are not supported by this installer: $walk"
            }
        }
        if ($walk -eq $base) { break }
        $walk = [IO.Path]::GetDirectoryName($walk)
    }
    return $full
}

function Get-KevinHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-KevinFile([string]$Path, [string]$Hash, $Length = $null) {
    if ($Hash -notmatch '^[a-fA-F0-9]{64}$' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file or valid checksum is missing: $Path"
    }
    if ($null -ne $Length -and (Get-Item -LiteralPath $Path).Length -ne [long]$Length) { throw "File length mismatch: $Path" }
    if ((Get-KevinHash $Path) -ne $Hash.ToLowerInvariant()) { throw "File version/checksum mismatch: $Path" }
}

function Get-KevinInteger($Value) {
    [long]$number = 0
    if (-not [long]::TryParse([string]$Value, [ref]$number) -or $number -lt 0) { throw 'Invalid binary patch integer.' }
    return $number
}

function Read-KevinJson([string]$Path) { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
function Write-KevinJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}

function Assert-KevinCandidateRoot([string]$PackageRoot, [string]$GameRoot, $Manifest) {
    if (-not $GameRoot -or $Manifest.PSObject.Properties.Name -notcontains 'candidateOnlyGameRoot') {
        throw 'Candidate testing requires its exact isolated game directory.'
    }
    $expected = [IO.Path]::GetFullPath([string]$Manifest.candidateOnlyGameRoot).TrimEnd('\','/')
    $actual = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\','/')
    $workspace = [IO.Path]::GetDirectoryName($expected)
    if ($actual -ine $expected -or [IO.Path]::GetFileName($expected) -ine 'runtime' -or
        [IO.Path]::GetFileName($workspace) -ine 'Subsistence-Kevin') {
        throw 'Candidate installation is restricted to the Subsistence-Kevin project runtime.'
    }
    [void](Resolve-KevinPath $workspace 'runtime/UDKGame/CookedPC')
    $build = Resolve-KevinPath $workspace 'build'
    $bundle = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\','/')
    if (-not $bundle.StartsWith($build + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'A candidate bundle must remain inside this project build directory.'
    }
    [void](Resolve-KevinPath $build $bundle.Substring($build.Length + 1))
    # Only the exact supported original establishes this development workspace.
    Assert-KevinFile (Resolve-KevinPath $workspace 'originals/ColdGame.u') '2d1d20eb6ca754139113e86af1013c09738f5a2a12eb8a0fe7a938e5986eaf4e' 32872255
}

function Get-KevinManifest([string]$PackageRoot, [string]$CandidateGameRoot = '', [bool]$AllowIsolatedCandidate = $false) {
    $path = Resolve-KevinPath $PackageRoot 'manifest.json'
    $manifest = Read-KevinJson $path
    if ($manifest.format -ne 'kevin-loader-v1' -or
        ($manifest.releaseStatus -ne 'VALIDATED' -and
        -not ($manifest.releaseStatus -eq 'ISOLATED_CANDIDATE' -and $AllowIsolatedCandidate))) {
        throw 'This is a DEV ONLY loader package. Installation is disabled until the complete release has passed gameplay validation.'
    }
    if ($manifest.releaseStatus -eq 'ISOLATED_CANDIDATE') {
        Assert-KevinCandidateRoot $PackageRoot $CandidateGameRoot $manifest
    } elseif ($manifest.PSObject.Properties.Name -contains 'candidateOnlyGameRoot') {
        throw 'A public release must not contain a private candidate runtime path.'
    }
    if ($manifest.nativeModUuid -ne $script:KevinUuid -or $manifest.buildId -notmatch '^[A-Za-z0-9_.-]{1,80}$') {
        throw 'Invalid loader identity.'
    }
    if (@($manifest.patches).Count -ne 4 -or @($manifest.files).Count -ne 2) { throw 'Release manifest is incomplete.' }
    return $manifest
}

function Find-KevinGame([string]$Requested) {
    if ($Requested) { return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Requested).Path).TrimEnd('\','/') }
    $roots = New-Object 'Collections.Generic.List[string]'
    $steam = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($null -ne $steam -and $steam.PSObject.Properties.Name -contains 'SteamPath') { $roots.Add([string]$steam.SteamPath) }
    if (${env:ProgramFiles(x86)}) { $roots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }
    foreach ($root in @($roots.ToArray())) {
        $vdf = Join-Path $root 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s*"([^"]+)"')) {
                $roots.Add($match.Groups[1].Value.Replace('\\','\'))
            }
        }
    }
    $found = @()
    foreach ($root in @($roots.ToArray() | Select-Object -Unique)) {
        $acf = Join-Path $root 'steamapps/appmanifest_418030.acf'
        if (-not (Test-Path -LiteralPath $acf -PathType Leaf)) { continue }
        $match = [regex]::Match([IO.File]::ReadAllText($acf), '"installdir"\s*"([^"]+)"')
        if ($match.Success -and $match.Groups[1].Value -notmatch '[/\\:]') {
            $game = Join-Path (Join-Path $root 'steamapps/common') $match.Groups[1].Value
            if (Test-Path -LiteralPath $game -PathType Container) { $found += [IO.Path]::GetFullPath($game) }
        }
    }
    $found = @($found | Select-Object -Unique)
    if ($found.Count -ne 1) { throw 'Subsistence could not be identified uniquely. Run again with -GamePath pointing to its installation directory.' }
    return $found[0].TrimEnd('\','/')
}

function Assert-KevinGame([string]$Root, $Manifest) {
    if (-not (Test-Path -LiteralPath (Resolve-KevinPath $Root 'UDKGame/CookedPC') -PathType Container)) { throw 'This is not a Subsistence game directory.' }
    foreach ($exe in @($Manifest.gameExecutables)) {
        Assert-KevinFile (Resolve-KevinPath $Root $exe.gamePath) $exe.sha256 $exe.length
    }
    if (@($Manifest.gameExecutables).Count -lt 1) { throw 'Manifest has no executable version gate.' }
}

function Get-KevinApprovedUpgrade($Manifest, $Previous) {
    # A release author must explicitly attest compatible saved classes and pin
    # every predecessor file. State records alone never authorize new bytes.
    if ($Manifest.PSObject.Properties.Name -notcontains 'upgradeFrom') {
        throw 'This release does not authorize an upgrade from the installed build.'
    }
    $matches = @($Manifest.upgradeFrom | Where-Object {
        $_.buildId -eq $Previous.buildId -and $_.manifestSha256 -eq $Previous.manifestSha256
    })
    if ($matches.Count -ne 1 -or $matches[0].preservesSaveClasses -ne $true) {
        throw 'Installed build/hash is not an explicitly approved save-compatible upgrade source.'
    }
    $approved = $matches[0]
    if ($approved.PSObject.Properties.Name -contains 'isolatedOnly' -and $approved.isolatedOnly -and
        $Manifest.releaseStatus -ne 'ISOLATED_CANDIDATE') { throw 'An isolated predecessor is not approved for public upgrade.' }
    $roles = @{
        'UDKGame/CookedPC/ColdGame.u'='core-patch'
        'UDKGame/CookedPC/Maps/ColdMaps/ColdIntroLogos.udk'='core-patch'
        'UDKGame/CookedPC/Maps/ColdMaps/ColdMenuMap.udk'='core-patch'
        'UDKGame/CookedPC/Maps/ColdMaps/ColdMap1.udk'='core-patch'
        'UDKGame/CookedPC/KevinCompanion.u'='compatibility-package'
        'UDKGame/Mods/Local/Kevin Companion/mod.json'='native-mod-metadata'
    }
    $expected = @{}
    foreach ($entry in @($approved.files)) {
        if (-not $roles.ContainsKey($entry.gamePath) -or $expected.ContainsKey($entry.gamePath) -or
            $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid predecessor file allowlist.' }
        $expected[$entry.gamePath] = $entry.sha256.ToLowerInvariant()
    }
    if ($expected.Count -ne 6) { throw 'Predecessor approval must pin all four hooks, package and mod metadata.' }
    $records = @{}; $configCount = 0
    foreach ($file in @($Previous.files)) {
        if ($file.role -eq 'activation-config' -and $file.gamePath -eq $script:KevinConfigPath) { $configCount++; continue }
        if (-not $roles.ContainsKey($file.gamePath) -or $records.ContainsKey($file.gamePath) -or
            $file.role -ne $roles[$file.gamePath] -or $file.afterHash -ne $expected[$file.gamePath]) {
            throw 'Installed records do not match the approved predecessor.'
        }
        if ($file.role -ne 'core-patch' -and -not $file.retainOnDisable) { throw 'Predecessor save-compatibility policy is invalid.' }
        $records[$file.gamePath] = $file
    }
    if ($records.Count -ne 6 -or $configCount -ne 1) { throw 'Incomplete predecessor installation records.' }
    return $records
}

function Write-KevinPatch([string]$Original, [string]$PatchPath, [string]$Destination) {
    $patch = Read-KevinJson $PatchPath
    if ($patch.format -ne 'kevin-copy-patch-v1') { throw 'Unknown patch format.' }
    $payload = Resolve-KevinPath ([IO.Path]::GetDirectoryName($PatchPath)) $patch.payload.file
    Assert-KevinFile $Original $patch.source.sha256 $patch.source.length
    Assert-KevinFile $payload $patch.payload.sha256 $patch.payload.length
    $sourceSize = Get-KevinInteger $patch.source.length
    $dataSize = Get-KevinInteger $patch.payload.length
    $outputSize = Get-KevinInteger $patch.output.length
    if ($outputSize -le 0 -or @($patch.operations).Count -gt 50000) { throw 'Invalid patch size or operation count.' }
    [long]$sum = 0
    foreach ($op in @($patch.operations)) {
        if ($op.kind -notin @('copy','data')) { throw 'Unknown binary patch operation.' }
        $offset = Get-KevinInteger $op.offset; $count = Get-KevinInteger $op.length
        $limit = if ($op.kind -eq 'copy') { $sourceSize } else { $dataSize }
        if ($count -le 0 -or $count -gt $limit -or $offset -gt $limit - $count -or $count -gt $outputSize - $sum) { throw 'Patch range exceeds file boundary.' }
        $sum += $count
    }
    if ($sum -ne $outputSize) { throw 'Patch operations do not reach the declared EOF.' }
    $input = $data = $output = $null
    try {
        $input = [IO.File]::Open($Original, 'Open', 'Read', 'Read')
        $data = [IO.File]::Open($payload, 'Open', 'Read', 'Read')
        $output = [IO.File]::Open($Destination, 'CreateNew', 'Write', 'None')
        $buffer = New-Object byte[] 1048576
        foreach ($op in @($patch.operations)) {
            $stream = if ($op.kind -eq 'copy') { $input } else { $data }
            [void]$stream.Seek([long]$op.offset, [IO.SeekOrigin]::Begin)
            [long]$remaining = $op.length
            while ($remaining -gt 0) {
                $read = $stream.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
                if ($read -le 0) { throw 'Unexpected EOF while reconstructing patch.' }
                $output.Write($buffer, 0, $read); $remaining -= $read
            }
        }
        $output.Flush($true)
    } finally {
        if ($null -ne $input) { $input.Dispose() }; if ($null -ne $data) { $data.Dispose() }; if ($null -ne $output) { $output.Dispose() }
    }
    Assert-KevinFile $Destination $patch.output.sha256 $outputSize
    return $patch
}

function Set-KevinConfig([string]$Text, [bool]$Enabled) {
    $lines = @($Text -split '\r?\n'); $result = New-Object 'Collections.Generic.List[string]'
    $section = $false; $foundSection = $false; $written = $false
    $setting = 'bLoaderEnabled=' + $(if ($Enabled) { 'True' } else { 'False' })
    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') {
            if ($section -and -not $written) { $result.Add($setting); $written = $true }
            $section = $Matches[1] -ieq 'KevinCompanion.KevinActivation'
            if ($section) { $foundSection = $true }
        }
        if ($section -and $line -match '^\s*bLoaderEnabled\s*=') {
            if (-not $written) { $result.Add($setting); $written = $true }
        } else { $result.Add($line) }
    }
    if (-not $foundSection) { $result.Add('[KevinCompanion.KevinActivation]') }
    if (-not $written) { $result.Add($setting) }
    return (($result.ToArray() -join "`r`n").TrimEnd("`r","`n") + "`r`n")
}

function New-KevinAction([string]$Root, [string]$Relative, [string]$Stage, [string]$Role, [bool]$Retain = $false) {
    $target = Resolve-KevinPath $Root $Relative
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    return [pscustomobject]@{ gamePath=$Relative; role=$Role; retainOnDisable=$Retain; stage=$Stage;
        beforeExists=[bool]$exists; beforeHash=$(if ($exists) { Get-KevinHash $target } else { $null });
        afterHash=(Get-KevinHash $Stage); backup=$null }
}

function Assert-KevinBefore([string]$Root, $Action) {
    $path = Resolve-KevinPath $Root $Action.gamePath
    if ($Action.beforeExists) { Assert-KevinFile $path $Action.beforeHash }
    elseif (Test-Path -LiteralPath $path) { throw "A new file appeared during staging: $path" }
}

function Set-KevinAtomic([string]$Stage, [string]$Target) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
    if (Test-Path -LiteralPath $Target -PathType Leaf) { [IO.File]::Replace($Stage, $Target, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($Stage, $Target) }
}

function Undo-KevinJournal([string]$Root, $Journal) {
    # Preflight every path before restoring any; never overwrite a third-party change.
    foreach ($a in @($Journal.actions)) {
        $target = Resolve-KevinPath $Root $a.gamePath
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $hash = Get-KevinHash $target
            if ($hash -ne $a.afterHash -and (-not $a.beforeExists -or $hash -ne $a.beforeHash)) { throw "Cannot roll back an externally changed file: $target" }
        } elseif ($a.beforeExists) { throw "Cannot roll back a missing original target: $target" }
        if ($a.beforeExists) { Assert-KevinFile (Resolve-KevinPath $Root $a.backup) $a.beforeHash }
    }
    $reverse = @($Journal.actions); [array]::Reverse($reverse)
    foreach ($a in $reverse) {
        $target = Resolve-KevinPath $Root $a.gamePath
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        if ((Get-KevinHash $target) -ne $a.afterHash) { continue }
        if ($a.beforeExists) {
            $restore = Resolve-KevinPath $Root ($Journal.transaction + '/restore-' + [guid]::NewGuid().ToString('N'))
            [IO.File]::Copy((Resolve-KevinPath $Root $a.backup), $restore, $false)
            Set-KevinAtomic $restore $target
            Assert-KevinFile $target $a.beforeHash
        } else { Remove-Item -LiteralPath $target -Force }
    }
}

function Repair-KevinPending([string]$Root) {
    $pending = Resolve-KevinPath $Root '.KevinLoader/pending.json'
    if (-not (Test-Path -LiteralPath $pending -PathType Leaf)) { return }
    $journal = Read-KevinJson $pending
    if ($journal.format -ne 'kevin-transaction-v1' -or $journal.gameRoot -ne $Root) { throw 'Unrecognized pending loader transaction.' }
    Assert-KevinClosed
    Undo-KevinJournal $Root $journal
    Remove-Item -LiteralPath $pending -Force
    Write-Host 'Recovered the prior interrupted loader transaction.'
}

function Invoke-KevinTransaction([string]$Root, [string]$Transaction, $Actions, $State, $OriginalCoreRecords = $null) {
    $dir = Resolve-KevinPath $Root $Transaction
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'backups'))
    $index = 0
    foreach ($a in $Actions) {
        Assert-KevinBefore $Root $a
        Assert-KevinFile $a.stage $a.afterHash
        if ($a.beforeExists) {
            $a.backup = "$Transaction/backups/$index.bin"
            $backup = Resolve-KevinPath $Root $a.backup
            [IO.File]::Copy((Resolve-KevinPath $Root $a.gamePath), $backup, $false)
            Assert-KevinFile $backup $a.beforeHash
        }
        $index++
    }
    # State is committed last and participates in the same rollback journal.
    if ($State.status -eq 'installed') {
        $State.files = @($Actions | Select-Object gamePath,role,retainOnDisable,beforeExists,beforeHash,afterHash,backup)
        # Rollback restores the pre-upgrade bytes recorded in Actions. Normal
        # Disable must instead restore the ORIGINAL game, never an older hook.
        # Preserve the verified original backup chain in the committed state.
        if ($null -ne $OriginalCoreRecords) {
            foreach ($file in $State.files) {
                if ($file.role -ne 'core-patch') { continue }
                if (-not $OriginalCoreRecords.ContainsKey($file.gamePath)) { throw 'Missing original core backup chain.' }
                $original = $OriginalCoreRecords[$file.gamePath]
                if (-not $original.beforeExists) { throw 'Predecessor has no original core backup.' }
                Assert-KevinFile (Resolve-KevinPath $Root $original.backup) $original.beforeHash
                $file.beforeExists = $true
                $file.beforeHash = $original.beforeHash
                $file.backup = $original.backup
            }
        }
    }
    $stateStage = Join-Path $dir 'state-next.json'; Write-KevinJson $stateStage $State
    $stateAction = New-KevinAction $Root '.KevinLoader/state.json' $stateStage 'state'
    if ($stateAction.beforeExists) {
        $stateAction.backup = "$Transaction/backups/state.json"
        [IO.File]::Copy((Resolve-KevinPath $Root '.KevinLoader/state.json'), (Resolve-KevinPath $Root $stateAction.backup), $false)
        Assert-KevinFile (Resolve-KevinPath $Root $stateAction.backup) $stateAction.beforeHash
    }
    $all = @($Actions) + @($stateAction)
    $journal = [pscustomobject]@{ format='kevin-transaction-v1'; gameRoot=$Root; transaction=$Transaction; actions=$all }
    $pending = Resolve-KevinPath $Root '.KevinLoader/pending.json'
    if (Test-Path -LiteralPath $pending) { throw 'An earlier loader transaction still needs recovery.' }
    $pendingStage = Join-Path $dir 'pending-next.json'; Write-KevinJson $pendingStage $journal
    [IO.File]::Move($pendingStage, $pending)
    try {
        foreach ($a in $all) {
            Assert-KevinClosed; Assert-KevinBefore $Root $a
            Assert-KevinFile $a.stage $a.afterHash
            Set-KevinAtomic $a.stage (Resolve-KevinPath $Root $a.gamePath)
            Assert-KevinFile (Resolve-KevinPath $Root $a.gamePath) $a.afterHash
        }
        Remove-Item -LiteralPath $pending -Force
    } catch {
        $failure = $_
        try { Undo-KevinJournal $Root $journal; Remove-Item -LiteralPath $pending -Force }
        catch { throw "Installation failed; automatic rollback needs attention. Preserve $pending and all backups. $($_.Exception.Message)" }
        throw "No changes were retained; the transaction rolled back. $($failure.Exception.Message)"
    }
}
