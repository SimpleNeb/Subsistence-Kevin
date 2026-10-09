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
This wrapper adds no independent path around their guards and requests no UAC prompt.
Access-denied errors remain visible; the player can explicitly rerun as administrator
when their Steam folder permissions require it. It never escalates itself.

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

Prototype validation includes corrupt hash/content rejection, candidate/test/path
exclusion, extracted-script tamper rejection, argument quoting and an offscreen render.
It does not by itself attest a clicked Install/Disable end-to-end UI run. Root owns the
actual isolated installer/game validation. A future v0.2 EXE must embed the exact final
v0.2 ZIP, including its tested upgrade policy and scripts; rebuilding after tests changes
the wrapper hash, so preserve the resulting evidence alongside its published checksum.

Extracted packages are retained in LocalAppData/KevinCompanion/Setup for troubleshooting.
They contain only public release files. The UI cannot be closed during an active file
operation; externally killing Windows/PowerShell remains subject to installer journal
recovery on the next run. Game backups and saved-class packages are retained as before.
