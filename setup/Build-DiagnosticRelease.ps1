[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$baseline = Join-Path $repo 'downloads/Kevin-Companion-0.2.5-preview-Alpha68.19.zip'
$baselineHash = '684de53dd48574951722760455e8be983b45db803f5a37246c76469e0115fa2f'
Add-Type -Path (Join-Path $PSScriptRoot 'BundlePayload.cs') -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
$payload = [KevinSetup.BundlePayload]::Validate([IO.File]::ReadAllBytes($baseline), $baselineHash)
$output = [IO.Path]::GetFullPath($OutputDirectory)
[KevinSetup.BundlePayload]::CheckNoLinks($output)
if (Test-Path -LiteralPath $output) { throw 'Choose a new output directory; release artifacts are immutable.' }
[void][IO.Directory]::CreateDirectory($output)
$bundle = Join-Path $output 'Kevin-Companion-0.2.6-preview-Alpha68.19'
[void][IO.Directory]::CreateDirectory($bundle)
foreach ($entry in $payload.Files.GetEnumerator()) {
    $path = Join-Path $bundle $entry.Key
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllBytes($path, $entry.Value)
}
$utf8 = New-Object Text.UTF8Encoding($false)
$manifestPath = Join-Path $bundle 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$predecessorFiles = @()
foreach ($entry in $manifest.patches) {
    $patch = Get-Content -LiteralPath (Join-Path $bundle $entry.patch) -Raw -Encoding UTF8 | ConvertFrom-Json
    $predecessorFiles += [ordered]@{ gamePath=$patch.gamePath; sha256=$patch.output.sha256 }
}
foreach ($entry in $manifest.files) { $predecessorFiles += [ordered]@{ gamePath=$entry.gamePath; sha256=$entry.sha256 } }
$manifest.upgradeFrom = @($manifest.upgradeFrom) + @([ordered]@{
    buildId=$manifest.buildId; manifestSha256=[KevinSetup.BundlePayload]::HashFile($manifestPath)
    preservesSaveClasses=$true; files=$predecessorFiles
})
$manifest.buildId = 'alpha68.19-preview-diagnostics-026'
$manifest.companionVersion = '0.2.6-preview'
$manifest.note = 'Installer diagnostics update. Gameplay package and all four patches are byte-identical to validated 0.2.5; see VALIDATION.txt for inherited versus fresh checks.'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 30) + "`n", $utf8)
foreach ($name in @('KevinLoader.Common.ps1','Install-Kevin.ps1','Disable-Kevin.ps1','Install Kevin.cmd','Disable Kevin.cmd')) {
    [IO.File]::Copy((Join-Path $repo ('installer/' + $name)), (Join-Path $bundle $name), $true)
}
# Use the existing guide unchanged: this release changes no gameplay behavior.
$readmePath = Join-Path $bundle 'README.txt'
$readme = [IO.File]::ReadAllText($readmePath).Replace('0.2.5','0.2.6')
$readme = $readme.Replace('NEW IN 0.2.6', 'GAMEPLAY INCLUDED FROM 0.2.5')
$readme += @'

INSTALLER DIAGNOSTICS UPDATE
0.2.6 keeps the exact 0.2.5 companion code and patches. Failed file checks now
include expected/actual SHA256 and byte lengths, with recovery guidance.
Back up saves and preserve .KevinLoader before repair. If Kevin is already
installed, preserve its records and report the mismatch before changing files.
For a fresh install, restore a verified original or use Steam > Properties >
Installed Files > Verify integrity, then retry. Verification can replace other
mods; never force a patch or replace a checksum to accept unknown game files.
'@
[IO.File]::WriteAllText($readmePath, $readme, $utf8)
[IO.File]::WriteAllText((Join-Path $bundle 'VALIDATION.txt'), @'
KEVIN 0.2.6 PREVIEW - INSTALLER DIAGNOSTICS

The gameplay package, native metadata and all four binary patches are byte-for-
byte identical to public 0.2.5. Its gameplay validation is inherited; no new
gameplay tests are claimed for this installer-only update.

Fresh release checks are recorded in the repository BUILD-PROOF.md and
BUILD-PROOF-0.2.6.json: wrapper integrity/diagnostics, exact hash and length
rejections before changes, installation, repeat installation, disable/re-enable,
0.2.5 upgrade, original backups and save sentinel preservation on isolated
copies of supported Alpha 68.19 retail files. No game is launched by these tests.

The home-PC mismatch was an earlier development probe in ColdGame.u, not missing
files in the public bundle. The original backup matched the required source.
Unknown bytes remain rejected. The installer does not automatically restore
unrecognized or development files. Interactive UAC is not covered by these tests.

Setup remains unsigned. Checksums identify bytes, not a verified publisher.
'@, $utf8)
$checksums = @()
foreach ($file in @(Get-ChildItem -LiteralPath $bundle -File -Recurse | Sort-Object FullName)) {
    if ($file.Name -eq 'CHECKSUMS.sha256') { continue }
    $relative = $file.FullName.Substring($bundle.Length + 1).Replace('\','/')
    $checksums += [KevinSetup.BundlePayload]::HashFile($file.FullName) + '  ' + $relative
}
[IO.File]::WriteAllText((Join-Path $bundle 'CHECKSUMS.sha256'), ($checksums -join "`n") + "`n", $utf8)
$zipPath = Join-Path $output 'Kevin-Companion-0.2.6-preview-Alpha68.19.zip'
$stream = [IO.File]::Open($zipPath, 'CreateNew', 'Write', 'None')
$zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @(Get-ChildItem -LiteralPath $bundle -File -Recurse | Sort-Object FullName)) {
        $name = [IO.Path]::GetFileName($bundle) + '/' + $file.FullName.Substring($bundle.Length + 1).Replace('\','/')
        $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::Parse('2026-10-16T00:00:00Z')
        $target = $entry.Open()
        $source = [IO.File]::OpenRead($file.FullName)
        try { $source.CopyTo($target) } finally { $source.Dispose(); $target.Dispose() }
    }
} finally { $zip.Dispose(); $stream.Dispose() }
$zipHash = [KevinSetup.BundlePayload]::HashFile($zipPath)
[void][KevinSetup.BundlePayload]::Validate([IO.File]::ReadAllBytes($zipPath), $zipHash)
[IO.File]::WriteAllText(($zipPath + '.sha256'), $zipHash + '  ' + [IO.Path]::GetFileName($zipPath) + "`n", $utf8)
[pscustomobject]@{ bundle=$bundle; zip=$zipPath; sha256=$zipHash } | ConvertTo-Json
