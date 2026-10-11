# Kevin Companion 0.2.3 preview — build and validation

## What changed

This release repairs the installer. The separate Setup app adds **Retry as
administrator** after an access-denied result, preserves the selected game path
and install/disable operation, and saves a diagnostic report. Writable game
folders still use the ordinary permissions of the user running Setup.

The loader now reads its JSON records explicitly as UTF-8. Windows PowerShell
5.1 otherwise reads a record containing an accented folder name incorrectly.
That defect reproduced in repeat installation, Disable and transaction recovery.
A separate protected-folder test reproduced a first-install access-denied error.
The original home-PC error was not available, so neither reproduction establishes
what happened on that computer or to every subscriber.

**All four native hooks, KevinCompanion.u and mod.json are byte-identical to
public 0.2.2.** No gameplay, save schema or Workshop identity changes are included.
Supported public 0.1.0, 0.2.0, 0.2.1 and 0.2.2 upgrade identities remain pinned.

## Source preflight

| Check | Result |
| --- | --- |
| Windows PowerShell 5.1 UTF-8 lifecycle regression | 6 passed, 0 failed after the repair |
| Synthetic loader transactions and safety checks | 24 passed |
| Synthetic upgrade transactions and safety checks | 25 passed |
| Revised Setup source wrapping the existing 0.2.2 ZIP | 28 passed, 0 failed |
| Independent installer source review | No blocking findings |

The Setup source preflight above wraps the existing 0.2.2 payload; it is not a
final 0.2.3 artifact test. Synthetic loader tests use inert files. They exercise
transactions and records but do not launch Subsistence.

## Final artifact evidence

The exact final 0.2.3 Setup passed **28 wrapper checks** and **149 installation
checks**, with zero failures:

| Final artifact check | Passed | Failed |
| --- | ---: | ---: |
| Archive validation, tamper rejection, quoting, retry construction and offscreen UI | 28 | 0 |
| Fresh install, repeat install, Disable and reinstall | 50 | 0 |
| Protected-folder refusal, retry guidance and file preservation | 21 | 0 |
| Mid-install write failure and complete rollback | 21 | 0 |
| Public 0.2.2 upgrade, repeat install, Disable and reinstall | 57 | 0 |

The installation checks drove the real Setup form's worker and Windows
PowerShell 5.1 child process against isolated copies of the supported retail
files. Tests covered accented folder names, saved installation reports, original
backups, installed hashes and unchanged save sentinels. No game was launched.
The upgrade started from the actual public 0.2.2 installation, inside an isolated
fixture. It did not modify the player's live installation or saves.

Permission tests reproduced denied writes and checked the available retry and
saved report. **The Windows UAC prompt and elevated relaunch were not invoked.**
The tests therefore do not establish successful permission approval on every PC.
The original home-PC failure cause remains unknown without its error report.

Anonymous downloads from the immutable links below matched the exact final
local Setup and ZIP bytes. The evidence hashes and source identities are also
listed in [BUILD-PROOF.json](BUILD-PROOF.json).

## Inherited gameplay evidence

The exact reused 0.2.2 gameplay package passed ten static audits, 34 targeted
gathering checks and 18 native schema2 save/Disable/reinstall/reload checks.
Earlier historical evidence includes 168 controlled feature checks, death-bag
save cycles, legacy migration and an 11-check Workshop subscription/download
test. These are inherited results, not new gameplay tests of this installer
release. Gathering keeps the 2.5-times-wider search introduced in 0.2.2.

Production package SHA256:

```text
c23d1f377c329adf2dadd95132be192c0066a72fd04a049a8042cc040043f4bb
```

Supported: **Subsistence Alpha 68.19, Windows, standalone single-player**.
There is no multiplayer, every-mod, flawless-navigation or long-term public
playtest claim. Test classes, compiler stubs, original game packages, SDK files
and saves are excluded from the release. Setup is an unsigned community preview.

## Verified downloads

[Kevin Setup 0.2.3](https://github.com/SimpleNeb/Subsistence-Kevin/raw/6410f4b8a0c93f52f692a61817bedadcbdf0dc7e/downloads/Kevin-Setup-0.2.3-preview-Alpha68.19.exe) — SHA256:

```text
5de7d4f8355b72511981671c8540e3937610b1913990d85e74baf8b37db29f08
```

[0.2.3 ZIP installer](https://github.com/SimpleNeb/Subsistence-Kevin/raw/6410f4b8a0c93f52f692a61817bedadcbdf0dc7e/downloads/Kevin-Companion-0.2.3-preview-Alpha68.19.zip) — SHA256:

```text
402d9789cf9c33dde6b4023e29ab42ffba35b2c5e9dd5ffe2b4f10a1f3d45caa
```

Both files were downloaded anonymously from the immutable commit and matched
the local tested artifacts. Corresponding `.sha256` files are in the downloads
folder. Earlier release checksums do not identify these files.

A Workshop subscription alone does not install or update Kevin's code. Download
and run the local installer when installing a new release. Users already running
0.2.2 successfully do not need this installer repair for gameplay changes.
