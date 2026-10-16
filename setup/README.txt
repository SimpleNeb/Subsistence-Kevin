KEVIN COMPANION SINGLE-FILE WINDOWS SETUP -- SOURCE / BUILD WORKFLOW

This small offline Windows Forms app embeds an exact finalized release ZIP. It shows
Install / Update, Disable Kevin, Browse and Read player guide. It detects Steam library
folders using the local registry and appmanifest_418030.acf; ambiguous paths require
Browse. It never downloads files, signs in, accepts credentials or publishes anything.

The executable verifies the embedded ZIP SHA256, strict file allowlist, each checksum,
VALIDATED release status, native UUID and version. It extracts into a unique local-app
data folder and checks those files again before running the SAME embedded installer
or disable script in hidden Windows PowerShell 5.1. The original scripts still enforce
game closed, exact game version, package hashes, backups, transactions and rollback.
This wrapper adds no independent path around their guards. It starts with normal
Windows permissions. An access-denied failure offers Retry as administrator, which
restarts the same Setup EXE through the Windows permission prompt and preserves
the selected folder and operation. The elevated EXE revalidates and extracts its
own embedded ZIP. Cancelling the Windows prompt starts no retry.

Build ONLY after a ZIP has passed all release gates:
  Windows PowerShell 5.1 -File release/setup/Build-Setup.ps1
    -ZipPath <finalized-release.zip> -ExpectedSha256 <audited ZIP SHA256>
    -OutputPath <new Kevin-Companion-Setup-version.exe path>
These are maintainer instructions. Players only download and run the EXE.
The output must be new. The build checks the embedded archive bytes again and writes
an adjacent SHA256 file and build-evidence JSON. It never executes the installer.
The .NET Framework compiler already included on this machine is sufficient. No third
party runtime is bundled or downloaded. Supported player environment: 64-bit Windows
with .NET Framework 4.7.2+ and Windows PowerShell 5.1 (normal supported Windows 10/11).

Unsigned preview: no signing certificate is available. Do not claim a trusted/signed
publisher or tell players to disable security software. Publish SHA256 and source on
the verified project release page. Keep the ZIP/manual .cmd option as a fallback.

Test-Setup.ps1 covers archive checks, tamper rejection, argument quoting, permission
retry construction, failure guidance and an offscreen render. It does not execute
the installer or the Windows permission prompt. Test-Installer.ps1 executes the
real PowerShell install/disable scripts against isolated copies of retail files,
including repeat installation, disable/reinstall and predecessor upgrade.
Test-InstallerDiagnostics.ps1 checks exact diagnostics and rejection-before-writes
using synthetic fixtures. Neither launches the game. Earlier release evidence
refers to an office-only SetupForm integration harness that is not in this repo.
Preserve the exact final EXE's test evidence and published checksum; rebuilding
after testing changes the wrapper hash. Real interactive UAC consent is separate
from testing the same-EXE runas request and error handling.

Extracted packages are retained in LocalAppData/KevinCompanion/Setup for troubleshooting.
Each install/disable attempt also saves a report in LocalAppData/KevinCompanion/Logs.
Save setup report exports a copy. Reports contain the selected local game path,
release identity, Windows/access information and installer output, but no save
contents or credentials. A failure before that folder can be created remains on
screen. Read player guide opens PLAYER-GUIDE.txt for releases that include it.
They contain only public release files. The UI cannot be closed during an active file
operation; externally killing Windows/PowerShell remains subject to installer journal
recovery on the next run. Game backups and saved-class packages are retained as before.

Build-DiagnosticRelease.ps1 reproduces the 0.2.6 payload from the checksum-pinned
public 0.2.5 archive plus installer source. It copies the gameplay package and
patches unchanged and explicitly authorizes the exact 0.2.5 predecessor. Choose
a new output directory, run the tests, then build and test the final Setup EXE.
SIGNING.md in the repository root describes publisher signing prerequisites.
