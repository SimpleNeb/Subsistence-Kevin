[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Prepare','Finalize')][string]$Stage,
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$WorkDirectory,
    [ValidatePattern('^0\.2\.[0-9]+-preview$')][string]$ExpectedVersion = '0.2.6-preview',
    [string]$ExpectedSignerSubject,
    [ValidatePattern('^[a-fA-F0-9]{40}$')][string]$SourceCommit
)
# Local preparation/verification only. Azure signing is a separate workflow step.
# Requires Windows PowerShell 5.1, matching the existing Setup build and tests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this helper with Windows PowerShell 5.1.' }
$zip = (Resolve-Path -LiteralPath $ZipPath).Path
$expectedHash = $ExpectedSha256.ToLowerInvariant()
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'Finalized release ZIP checksum mismatch.'
}
Add-Type -Path (Join-Path $PSScriptRoot 'BundlePayload.cs') -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
$payload = [KevinSetup.BundlePayload]::Validate([IO.File]::ReadAllBytes($zip), $expectedHash)
if ($payload.Version -cne $ExpectedVersion) { throw 'The archive version differs from the requested signing release.' }
$work = [IO.Path]::GetFullPath($WorkDirectory)
[KevinSetup.BundlePayload]::CheckNoLinks($work)
$name = 'Kevin-Setup-' + $ExpectedVersion + '-Alpha68.19-signed.exe'
$stagedExe = Join-Path $work $name
$buildProofPath = $stagedExe + '.build.json'

if ($Stage -eq 'Prepare') {
    if (Test-Path -LiteralPath $work) { throw 'Signing work directory must be new; existing artifacts are immutable.' }
    [void][IO.Directory]::CreateDirectory($work)
    # Use a separate process so the builder loads its own BundlePayload type.
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Build-Setup.ps1') -ZipPath $zip -ExpectedSha256 $expectedHash -OutputPath $stagedExe
    if ($LASTEXITCODE -ne 0) { throw 'Setup preparation failed.' }
    $unsigned = Get-AuthenticodeSignature -LiteralPath $stagedExe
    if ($unsigned.Status -ne 'NotSigned') { throw 'Expected a newly built unsigned EXE before the service signing step.' }
    Write-Output ('Prepared unsigned candidate for explicit service signing: ' + $stagedExe)
    return
}

if ([string]::IsNullOrWhiteSpace($ExpectedSignerSubject)) { throw 'Finalize requires the exact validated certificate subject.' }
foreach ($required in @($stagedExe, $buildProofPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Prepared artifact is missing: ' + $required) }
    if (((Get-Item -LiteralPath $required).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked signing artifacts are unsupported.' }
}
$proof = Get-Content -LiteralPath $buildProofPath -Raw | ConvertFrom-Json
if ($proof.format -cne 'kevin-setup-build-v1' -or $proof.version -cne $ExpectedVersion -or
    $proof.archiveSha256 -cne $expectedHash -or $proof.buildId -cne $payload.BuildId -or $proof.signed -ne $false) {
    throw 'Unsigned build proof does not match the requested release.'
}

$signature = Get-AuthenticodeSignature -LiteralPath $stagedExe
if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
    $signature.SignatureType -ne 'Authenticode') { throw 'A valid embedded Authenticode signature is required.' }
if ($signature.SignerCertificate.Subject -cne $ExpectedSignerSubject) { throw 'The verified publisher differs from the configured certificate subject.' }
if ($null -eq $signature.TimeStamperCertificate) { throw 'A verified timestamp is required.' }

# Signing must preserve the exact audited ZIP embedded by Build-Setup.ps1.
$assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($stagedExe))
$resource = $assembly.GetManifestResourceStream('Kevin.Payload.zip')
if ($null -eq $resource) { throw 'Signed Setup is missing its release archive.' }
$memory = New-Object IO.MemoryStream
try {
    $resource.CopyTo($memory)
    if ([KevinSetup.BundlePayload]::Hash($memory.ToArray()) -cne $expectedHash) { throw 'Signed Setup contains a different release archive.' }
} finally { $resource.Dispose(); $memory.Dispose() }

# Inspect exact payload bytes without changing the ZIP or running any script.
$inspection = Join-Path $work ('signature-inspection-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($inspection)
$scriptProof = @()
foreach ($entry in $payload.Files.GetEnumerator() | Where-Object { $_.Key.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase) } | Sort-Object Key) {
    $scriptPath = Join-Path $inspection $entry.Key
    [IO.File]::WriteAllBytes($scriptPath, $entry.Value)
    $scriptSignature = Get-AuthenticodeSignature -LiteralPath $scriptPath
    $scriptProof += [ordered]@{
        name = $entry.Key
        sha256 = [KevinSetup.BundlePayload]::Hash($entry.Value)
        status = $scriptSignature.Status.ToString()
        signed = ($scriptSignature.Status -eq 'Valid')
        publisher = $(if ($null -ne $scriptSignature.SignerCertificate) { $scriptSignature.SignerCertificate.Subject } else { $null })
    }
}
if ($scriptProof.Count -ne 3) { throw 'Expected exactly three installer PowerShell scripts.' }
$finalHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash.ToLowerInvariant()
$unsignedHash = $proof.setupSha256
$proof.setupSha256 = $finalHash
$proof.signed = $true
$proof | Add-Member -NotePropertyName unsignedSetupSha256 -NotePropertyValue $unsignedHash
$proof | Add-Member -NotePropertyName signing -NotePropertyValue ([ordered]@{
    provider = 'Microsoft Artifact Signing'
    status = $signature.Status.ToString()
    publisher = $signature.SignerCertificate.Subject
    certificateThumbprint = $signature.SignerCertificate.Thumbprint
    timestampAuthority = $signature.TimeStamperCertificate.Subject
    timestampCertificateThumbprint = $signature.TimeStamperCertificate.Thumbprint
    verifiedUtc = [DateTime]::UtcNow.ToString('o')
    sourceCommit = $SourceCommit
    payloadScripts = $scriptProof
    allPayloadScriptsSigned = (@($scriptProof | Where-Object { -not $_.signed }).Count -eq 0)
    scope = 'Outer Setup EXE only; finalized ZIP preserved byte-for-byte. No SmartScreen or Smart App Control acceptance guarantee.'
    releaseStatus = 'REVIEW_REQUIRED'
})
$candidate = Join-Path $work 'review-candidate'
if (Test-Path -LiteralPath $candidate) { throw 'A review candidate already exists; use a new work directory.' }
[void][IO.Directory]::CreateDirectory($candidate)
$finalExe = Join-Path $candidate $name
[IO.File]::Copy($stagedExe, $finalExe, $false)
if ((Get-FileHash -LiteralPath $finalExe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $finalHash) { throw 'Signed EXE changed while creating the review candidate.' }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText(($finalExe + '.sha256'), ($finalHash + '  ' + $name + "`n"), $utf8)
[IO.File]::WriteAllText(($finalExe + '.build.json'), ($proof | ConvertTo-Json -Depth 12), $utf8)
Write-Output ('Verified signed review candidate: ' + $finalExe)
Write-Output ('Payload scripts with valid signatures: ' + @($scriptProof | Where-Object { $_.signed }).Count + '/' + $scriptProof.Count)
Write-Output 'Run the final artifact tests and gameplay checks before publishing. No release has been published.'
