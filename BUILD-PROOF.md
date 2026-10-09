# Kevin Companion 0.2.1 preview — build and validation

The 0.2.1 Setup and ZIP downloads are published at an immutable Git commit.
Both were downloaded without authentication and their SHA256 hashes verified.

## What changed

Version 0.2.1 adds the real Workshop item ID, **3816609201**, to the local mod's
metadata and identifies the successor installer version. It retains the exact
0.2.0 companion package, startup patches and installer scripts. No companion
gameplay code was rebuilt or changed for this update.

The production package contains 18 companion classes. Its SHA256 remains:

```text
e8455fdd1308ed952b162671d9e045e2df04e0da3e4a059b42308e9230b45e0e
```

## Inherited gameplay evidence

The unchanged gameplay package passed **168 checks, with zero failures**, during
the completed 0.2.0 validation. These are inherited results, not 168 new runs
for 0.2.1.

| Completed gameplay suite | Passed | Failed |
| --- | ---: | ---: |
| Command menu | 26 | 0 |
| Gathering | 21 | 0 |
| Revival | 26 | 0 |
| Inventory and equipment | 49 | 0 |
| Defensive combat | 27 | 0 |
| Death behavior | 19 | 0 |
| **Total inherited** | **168** | **0** |

The 0.2.0 release also completed native save/reload, disable/re-enable and
migration checks. Ten static production-package audits passed. The public
release excludes its validation classes, compiler declarations, game originals,
SDK files and save data.

## New Workshop and installer evidence

The actual Workshop item was created and its content uploaded successfully.
The new native subscribe/download check passed **11 checks, with zero failures**.
It confirmed the logged-in account, acknowledged subscription, completed download,
expected metadata, native item lookup and enumeration, exactly one linked Kevin
row, and distinct local versus Workshop selection by their respective IDs.

An additional file check verified that all **four files downloaded by Steam**
exactly matched the uploaded files by SHA256. This checks real Workshop delivery;
manually copied local files were not used as download evidence.

The new installer cycle passed: install the public 0.2.0 release, upgrade to
0.2.1, disable, then reinstall. File hashes matched the expected installed or
restored state, and save files remained unchanged by these installer operations.

The new native save/reload cycle passed **18 checks, with zero failures**. It
tested Workshop selection and local selection across disabling and re-enabling,
with the companion's complete saved inventory fingerprint unchanged. These are
new 0.2.1 checks, separate from the 168 inherited gameplay checks and the 11
Workshop checks above.

The final Setup wrapper passed **21 checks, with zero failures**, against the
exact 0.2.1 ZIP. These cover its payload validation and window construction;
they did not click the installer buttons or launch the game. Installer behavior
was checked separately by the completed install/upgrade/disable/reinstall cycle.

## Downloads and limits

[Download Kevin Setup 0.2.1](https://github.com/SimpleNeb/Subsistence-Kevin/raw/7d4ddfba7c9aeac9cfb2e7e19fbf41fe124fa3ec/downloads/Kevin-Setup-0.2.1-preview-Alpha68.19.exe)
— SHA256:

```text
543847d4c0a7cc7e3315a7471319862a92c738b18680828b01b4e4ba5beb3cbc
```

[Download the 0.2.1 ZIP installer](https://github.com/SimpleNeb/Subsistence-Kevin/raw/7d4ddfba7c9aeac9cfb2e7e19fbf41fe124fa3ec/downloads/Kevin-Companion-0.2.1-preview-Alpha68.19.zip)
— SHA256:

```text
27ab04eb3b46d9e365f67d0be1cb03b5361fa59ffa205a8127ab6e2454d7c5ea
```

The ZIP's checksum list also identifies its individual files. Older 0.2.0
checksums do not identify these 0.2.1 downloads.

Supported target: Subsistence Alpha 68.19 on Windows, standalone single-player.
The checks used isolated game copies and disposable profiles. They do not
establish multiplayer support, compatibility with every other mod, flawless
navigation across all terrain, or long-term public playtest coverage.

The command menu was exercised through native game fixtures and its screenshot
was inspected. This is not a claim of physical keyboard or mouse testing.
Setup is an unsigned community preview. Subsistence and its original assets
remain the property of their respective owners.
