# Kevin Companion 0.2.2 preview — build and validation

## What changed

Kevin searches **2.5 times farther** for wood and fiber: 3,500 rather than
1,400 Unreal units. Each new search starts from his current position, helping
him continue through nearby patches. Targets stay within 4,000 units of you;
work stops beyond 4,500. A longer approach can take up to 35 seconds before
Kevin abandons it.

Only `KevinGatheringJob.uc` changed among the **18 production classes**.
The arbitrary 64-candidate search cutoff was removed. Native harvesting,
axe wear, resource depletion and cargo checks are unchanged, as are the other
17 production sources, save schema, startup patches, installer scripts and
Workshop metadata.

## Fresh checks on 0.2.2

| Check | Result |
| --- | --- |
| Static package audits | **10 passed** |
| Native gathering fixture | **34 passed, 0 failed** |
| Native save/reload, disable and re-enable | **18 passed, 0 failed** |
| Installer upgrade, disable and reinstall | **Passed; installer actions left saves unchanged** |
| Final Setup wrapper | **21 passed, 0 failed** |
| Public Setup and ZIP downloads | **Anonymous downloads matched their final SHA256 hashes** |

Gathering checks covered real tree selection beyond the old range, actual
approach and harvest of distant fiber, continued searching from Kevin's new
position, both player-distance limits, and the existing axe, depletion, cargo
and cancellation checks. The distant-tree assertion verifies selection;
the retained tree tests exercise actual chopping.

The save cycle loaded an authentic 0.2.1 save and preserved the complete
inventory fingerprint through all three stages. The installed upgrade baseline
was an isolated 0.2.1 candidate whose six installed payload hashes matched the
public release. A separate live upgrade from public 0.2.1 to 0.2.2 also passed,
with **63 save files backed up and unchanged**. That installer check did not
launch the game.

Setup wrapper checks cover its payload and window construction, not clicking
installer buttons or game behavior; the installer cycles above tested those
file changes separately.

Tested production package SHA256:

```text
c23d1f377c329adf2dadd95132be192c0066a72fd04a049a8042cc040043f4bb
```

## Inherited evidence and limits

The earlier gameplay package passed **168 checks with zero failures** across
commands, gathering, revival, inventory, defense and death. Earlier releases
also completed live-inventory and death-bag save cycles, legacy-save migration,
and an **11-check Workshop subscription/download test** with exact downloaded
file verification. These are historical results, not fresh tests of 0.2.2.

Supported: **Subsistence Alpha 68.19, Windows, standalone single-player**.
Tests used isolated copies and disposable profiles. They do not establish
multiplayer support, compatibility with every mod, or flawless navigation.
Bases, caves and obstacles can still interrupt movement or gathering. There
is no teleport catch-up or long-term public playtest claim.

Test classes, compiler stubs, original game packages, SDK files and saves are
excluded from the release. Setup is an unsigned community preview.

## Verified downloads

Both downloads below were retrieved anonymously from the immutable commit and
matched the final local release bytes.

[Kevin Setup 0.2.2](https://github.com/SimpleNeb/Subsistence-Kevin/raw/3eaf0ede184267efe3e96dad30005b04f1338703/downloads/Kevin-Setup-0.2.2-preview-Alpha68.19.exe) — SHA256:

```text
fbccb529511746a3abe9dc087f954b52d9dcb7356ac552a36c0e1c7bfb2d66f7
```

[0.2.2 ZIP installer](https://github.com/SimpleNeb/Subsistence-Kevin/raw/3eaf0ede184267efe3e96dad30005b04f1338703/downloads/Kevin-Companion-0.2.2-preview-Alpha68.19.zip) — SHA256:

```text
0a3877e002402cf980647997a00d0a7a3bd21af50f74c16736cbadad2f58c5e9
```

For every update, download and run the new version's local installer with
Subsistence closed. A Workshop subscription alone does not install or update
Kevin's code. Earlier release checksums do not identify these downloads.
