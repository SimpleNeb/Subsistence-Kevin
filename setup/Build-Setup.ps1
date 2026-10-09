[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$zip = (Resolve-Path -LiteralPath $ZipPath).Path
$output = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $output) { throw 'Setup artifacts are immutable. Choose a new output path.' }
if ([IO.Path]::GetExtension($output) -ine '.exe') { throw 'The output must be an EXE.' }
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Finalized release ZIP checksum mismatch.' }
$source = Join-Path $PSScriptRoot 'BundlePayload.cs'
Add-Type -Path $source -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
$payload = [KevinSetup.BundlePayload]::Validate([IO.File]::ReadAllBytes($zip), $hash)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The Windows .NET Framework C# compiler is unavailable.' }
$parent = [IO.Path]::GetDirectoryName($output)
[KevinSetup.BundlePayload]::CheckNoLinks($parent)
[void][IO.Directory]::CreateDirectory($parent)
$staging = Join-Path $parent ('.kevin-setup-build-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($staging)
try {
    $constants = Join-Path $staging 'BuildInfo.cs'
    [IO.File]::WriteAllText($constants, ('namespace KevinSetup { internal static class BuildInfo { internal const string ZipSha256 = "' + $hash + '"; } }'))
    $embedded = Join-Path $staging 'release.zip'
    [IO.File]::Copy($zip, $embedded, $false)
    if ((Get-FileHash -LiteralPath $embedded -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Release changed during staging.' }
    $stagedExe = Join-Path $staging ([IO.Path]::GetFileName($output))
    $compilerArgs = @('/nologo','/target:winexe','/platform:x64','/optimize+',('/out:' + $stagedExe),
        ('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')),
        ('/resource:' + $embedded + ',Kevin.Payload.zip'),
        '/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll',
        '/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll','/reference:System.Web.Extensions.dll',
        $source, (Join-Path $PSScriptRoot 'KevinSetup.cs'), $constants)
    & $compiler $compilerArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagedExe)) { throw 'Setup compilation failed.' }
    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($stagedExe))
    $resource = $assembly.GetManifestResourceStream('Kevin.Payload.zip')
    $memory = New-Object IO.MemoryStream
    try { $resource.CopyTo($memory); if ([KevinSetup.BundlePayload]::Hash($memory.ToArray()) -ne $hash) { throw 'Embedded ZIP differs from the audited archive.' } }
    finally { $resource.Dispose(); $memory.Dispose() }
    $exeHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $proof = [ordered]@{ format='kevin-setup-build-v1'; version=$payload.Version; buildId=$payload.BuildId;
        archiveSha256=$hash; setupSha256=$exeHash; sourceSha256=@{};
        signed=$false; requestedExecutionLevel='asInvoker'; networkAccess=$false;
        wrapperGameplayTested=$false; note='Wraps the exact audited ZIP; no installer or game was run by this build.' }
    foreach ($name in @('BundlePayload.cs','KevinSetup.cs','app.manifest','Build-Setup.ps1')) {
        $proof.sourceSha256[$name] = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    foreach ($path in @($output, ($output + '.sha256'), ($output + '.build.json'))) { if (Test-Path -LiteralPath $path) { throw 'A setup output already exists.' } }
    [IO.File]::Move($stagedExe, $output)
    [IO.File]::WriteAllText(($output + '.sha256'), ($exeHash + '  ' + [IO.Path]::GetFileName($output) + "`n"), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText(($output + '.build.json'), ($proof | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    $proof | ConvertTo-Json -Depth 8
} finally {
    $resolved = [IO.Path]::GetFullPath($staging)
    if ($resolved.StartsWith($parent.TrimEnd('\') + '\.kevin-setup-build-', [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
