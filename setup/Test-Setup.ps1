[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FinalZip,
      [Parameter(Mandatory=$true)][string]$ExpectedSha256,
      [Parameter(Mandatory=$true)][string]$PrototypeExe,
      [string]$CompatibilityZip,
      [string]$CompatibilitySha256)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'BundlePayload.cs') -ReferencedAssemblies System.IO.Compression,System.IO.Compression.FileSystem,System.Web.Extensions
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem,System.Drawing,System.Windows.Forms
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $FinalZip).Path)
$payload = [KevinSetup.BundlePayload]::Validate($bytes, $ExpectedSha256)
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$directory = Join-Path $project ('build/setup-tests/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$script:passed = 0
function Check([bool]$Value, [string]$Message) {
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:passed++; Write-Output ('PASS: ' + $Message)
}
function Reject([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Check $rejected $Message
}
function Copy-Files {
    $copy = @{}
    foreach ($entry in $payload.Files.GetEnumerator()) { $copy[$entry.Key] = $entry.Value }
    return $copy
}
function Update-Checksums($Files) {
    $lines = @()
    foreach ($name in @($Files.Keys | Sort-Object)) {
        if ($name -ne 'CHECKSUMS.sha256') { $lines += [KevinSetup.BundlePayload]::Hash($Files[$name]) + '  ' + $name }
    }
    $Files['CHECKSUMS.sha256'] = [Text.Encoding]::ASCII.GetBytes(($lines -join "`n") + "`n")
}
function Make-Zip($Files) {
    $memory = New-Object IO.MemoryStream
    $archive = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($name in $Files.Keys) {
            $entry = $archive.CreateEntry('Kevin-Companion-' + $payload.Version + '-Alpha68.19/' + $name)
            $stream = $entry.Open()
            try { $stream.Write($Files[$name], 0, $Files[$name].Length) } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    $result = $memory.ToArray(); $memory.Dispose(); return ,$result
}
function Validate-Changed($Files) {
    $changed = Make-Zip $Files
    return [KevinSetup.BundlePayload]::Validate($changed, [KevinSetup.BundlePayload]::Hash($changed))
}
$expectedCount = if ($payload.Version.StartsWith('0.2.')) { 20 } else { 19 }
Check ($payload.Files.Count -eq $expectedCount) 'exact finalized release ZIP validated'
if ([bool]$CompatibilityZip -ne [bool]$CompatibilitySha256) { throw 'Compatibility ZIP and SHA256 must be supplied together' }
if ($CompatibilityZip) {
    $compatibilityBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $CompatibilityZip).Path)
    $compatibility = [KevinSetup.BundlePayload]::Validate($compatibilityBytes,$CompatibilitySha256)
    Check ($compatibility.Version.StartsWith('0.1.') -and $compatibility.Files.Count -eq 19 -and -not $compatibility.Files.ContainsKey('PLAYER-GUIDE.txt')) 'unchanged public v0.1 format remains accepted'
}
Reject { [KevinSetup.BundlePayload]::Validate($bytes, ('0' * 64)) } 'wrong archive hash rejected'
$files = Copy-Files
$files['files/KevinCompanion.u'] = [Text.Encoding]::UTF8.GetBytes('changed')
Reject { Validate-Changed $files } 'modified package with stale file checksum rejected'
$files = Copy-Files
$files['files/KevinValidation.u'] = $files['files/KevinCompanion.u']; $files.Remove('files/KevinCompanion.u')
Update-Checksums $files
Reject { Validate-Changed $files } 'validation package excluded even with correct checksums'
$files = Copy-Files
$files['../escape.ps1'] = $files['README.txt']; $files.Remove('README.txt')
Update-Checksums $files
Reject { Validate-Changed $files } 'path traversal rejected'
$files = Copy-Files
$files['hidden.txt'] = [Text.Encoding]::UTF8.GetBytes('unexpected')
Update-Checksums $files
Reject { Validate-Changed $files } 'extra file rejected'
if ($payload.Version.StartsWith('0.2.')) {
    Check ($payload.Files.ContainsKey('PLAYER-GUIDE.txt')) 'v0.2 has its exact player guide entry'
    $files = Copy-Files; $files.Remove('PLAYER-GUIDE.txt'); Update-Checksums $files
    Reject { Validate-Changed $files } 'v0.2 missing player guide rejected even with matching checksums'
    $files = Copy-Files; $files['docs/PLAYER-GUIDE.txt'] = $files['PLAYER-GUIDE.txt']; $files.Remove('PLAYER-GUIDE.txt'); Update-Checksums $files
    Reject { Validate-Changed $files } 'misplaced guide excluded from exact allowlist'
    $files = Copy-Files; $files['PLAYER-GUIDE.txt'] = [Text.Encoding]::UTF8.GetBytes('changed')
    Reject { Validate-Changed $files } 'guide with stale checksum rejected'
    $files = Copy-Files; $files['PLAYER-GUIDE.txt'] = [byte[]]@(255,254,255); Update-Checksums $files
    Reject { Validate-Changed $files } 'malformed UTF-8 guide rejected even with matching checksums'
    $files = Copy-Files; $files['PLAYER-GUIDE.txt'] = [Text.Encoding]::UTF8.GetBytes('   '); Update-Checksums $files
    Reject { Validate-Changed $files } 'blank guide rejected'
    $files = Copy-Files; $files['PLAYER-GUIDE.txt'] = [byte[]]@(65,0,66); Update-Checksums $files
    Reject { Validate-Changed $files } 'binary null in guide rejected'
}
$files = Copy-Files
$manifest = [Text.Encoding]::UTF8.GetString($files['manifest.json']) | ConvertFrom-Json
$manifest.releaseStatus = 'ISOLATED_CANDIDATE'
$files['manifest.json'] = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 20))
Update-Checksums $files
Reject { Validate-Changed $files } 'development candidate rejected even with valid checksums'
$files = Copy-Files
$manifest = [Text.Encoding]::UTF8.GetString($files['manifest.json']) | ConvertFrom-Json
$manifest | Add-Member -NotePropertyName candidateOnlyGameRoot -NotePropertyValue 'private-path'
$files['manifest.json'] = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 20))
Update-Checksums $files
Reject { Validate-Changed $files } 'private candidate field rejected'
$extracted = $payload.Extract((Join-Path $directory 'extracted'))
$payload.VerifyExtracted($extracted)
Check ((Get-ChildItem -LiteralPath $extracted -Recurse -File).Count -eq $expectedCount) 'verified extraction has exactly release files'
[IO.File]::AppendAllText((Join-Path $extracted 'Install-Kevin.ps1'), '# tampered')
Reject { $payload.VerifyExtracted($extracted) } 'modified installer rejected before execution'
# Load the compiled prototype for pure quote tests and an OFFSCREEN render only.
# Never call Program.Main or RunInstaller; no game or installer process is launched.
$assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $PrototypeExe).Path))
$formType = $assembly.GetType('KevinSetup.SetupForm')
$quote = $formType.GetMethod('Quote', [Reflection.BindingFlags]'NonPublic,Static')
Check ($quote.Invoke($null, @('C:\some folder\game')) -ceq '"C:\some folder\game"') 'path with spaces quoted as data'
Check ($quote.Invoke($null, @('C:\some folder\')) -ceq '"C:\some folder\\"') 'trailing backslash quoted correctly'
$elevation = $formType.GetMethod('ElevatedStartInfo', [Reflection.BindingFlags]'NonPublic,Static')
$startInfo = $elevation.Invoke($null, @('C:\Downloads\Kevin Setup.exe', 'D:\Steam Library\Kevin''s [game]', $false))
Check ($startInfo.FileName -ceq 'C:\Downloads\Kevin Setup.exe' -and $startInfo.Verb -ceq 'runas' -and $startInfo.UseShellExecute -and
    $startInfo.Arguments -ceq '--game-path "D:\Steam Library\Kevin''s [game]" --action install') 'Windows elevation targets the same EXE and forwards the selected folder as data'
$startInfo = $elevation.Invoke($null, @('C:\Downloads\Kevin Setup.exe', 'D:\Steam Library\Game', $true))
Check ($startInfo.Arguments.EndsWith('--action disable')) 'elevation retry preserves Disable rather than changing operation'
$nativePayloadType = $assembly.GetType('KevinSetup.BundlePayload')
$nativePayload = $nativePayloadType.GetMethod('Validate').Invoke($null, @($bytes, $ExpectedSha256))
$form = [Activator]::CreateInstance($formType, [object[]]@($nativePayload))
try {
    $flags = [Reflection.BindingFlags]'NonPublic,Instance'
    $showFailure = $formType.GetMethod('ShowFailure', $flags)
    $status = $formType.GetField('status', $flags).GetValue($form)
    $administrator = $formType.GetField('administrator', $flags).GetValue($form)
    $showFailure.Invoke($form, @('System.UnauthorizedAccessException: Access denied'))
    $isAdmin = $formType.GetMethod('IsAdministrator', [Reflection.BindingFlags]'NonPublic,Static').Invoke($null,@())
    Check ($administrator.Enabled -eq (-not $isAdmin) -and $status.Text.Contains('Windows')) 'access denial offers the Windows permission retry only without administrator access'
    $showFailure.Invoke($form, @('File version/checksum mismatch: game'))
    Check (-not $administrator.Enabled -and $status.Text.Contains('Alpha 68.19')) 'file mismatch gives compatibility guidance without an irrelevant elevation retry'
    $showFailure.Invoke($form, @('Close Subsistence and its development tools before changing the loader.'))
    Check ($status.Text.StartsWith('Close Subsistence')) 'running game gives actionable close-and-retry guidance'
    $showFailure.Invoke($form, @('Unknown test failure'))
    Check ($status.Text.Contains('Save setup report')) 'unclassified failures explain how to capture the report'
    $status.Text = 'Kevin installed.'
    $formType.GetField('logPath', $flags).SetValue($form, $directory)
    $formType.GetField('reportText', $flags).SetValue($form, 'Installation succeeded. Exit code: 0')
    $formType.GetMethod('PersistReport', $flags).Invoke($form, @())
    Check ($status.Text -ceq 'Kevin installed.' -and $null -eq $formType.GetField('logPath', $flags).GetValue($form) -and
        $formType.GetField('reportText', $flags).GetValue($form).StartsWith('Installation succeeded. Exit code: 0')) 'failed automatic log write preserves installation result and exportable report'
    $status.Text = 'Choose Install, then select Kevin Companion in your profile''s Mods list.'
    $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
    try {
        $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
        # A hidden parent omits its children from WM_PRINT. Render each real control
        # separately and composite at its layout position; never show the window.
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $offsetX = [int](($form.Width - $form.ClientSize.Width) / 2)
            $offsetY = $form.Height - $form.ClientSize.Height - $offsetX
            foreach ($control in $form.Controls) {
                $child = New-Object Drawing.Bitmap($control.Width, $control.Height)
                try {
                    $control.DrawToBitmap($child, (New-Object Drawing.Rectangle(0,0,$control.Width,$control.Height)))
                    $graphics.DrawImageUnscaled($child, $control.Left + $offsetX, $control.Top + $offsetY)
                } finally { $child.Dispose() }
            }
        } finally { $graphics.Dispose() }
        $bitmap.Save((Join-Path $directory 'setup-offscreen.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
} finally { $form.Dispose() }
Check (Test-Path -LiteralPath (Join-Path $directory 'setup-offscreen.png')) 'offscreen controls rendered without showing or executing installer'
$report = @{ passed=$script:passed; failed=0; archiveSha256=$ExpectedSha256;
    compatibilityArchiveSha256=$CompatibilitySha256; releaseFiles=$expectedCount;
    setupSha256=(Get-FileHash -LiteralPath $PrototypeExe -Algorithm SHA256).Hash.ToLowerInvariant();
    installerRun=$false; gameLaunched=$false; offscreenImage=(Join-Path $directory 'setup-offscreen.png') }
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $directory 'test-results.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5
