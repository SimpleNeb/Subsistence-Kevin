# Kevin Companion 0.2.5. Build and validation

This release adds native loot-box gathering, scrap and Gather All commands, a wider search area, and defensive hunting/recurve bows using supplied ordinary or premium arrows. Installer scripts and native startup hooks remain unchanged from 0.2.4.

The exact production package passed ten static audits. Fresh controlled native checks:

| Feature | Passed | Failed |
| --- | ---: | ---: |
| recall | 43 | 0 |
| inventory | 72 | 0 |
| combat | 28 | 0 |
| menu | 36 | 0 |
| gathering | 34 | 0 |
| revival | 27 | 0 |
| death | 20 | 0 |
| scavenging | 30 | 0 |
| bow | 54 | 0 |

Native disk tests passed **18 checks** upgrading the public 0.2.4 save3 through enabled, disabled and re-enabled states, plus **23 checks** preserving a loaded, upgraded gun and partially charged flashlight across a fresh four-stage disk cycle. A further **25 checks** preserve actual generated crate loot and factory scrap through their own seed, reload, disabled and re-enabled saves. Full inventory fingerprints remain unchanged within each chain.

The final Setup passed **28 wrapper checks** and **154 actual installation checks** on isolated copies of the supported retail files: fresh installation, repeated installation, Disable/reinstall, denied writes, rollback and public0.2.4 upgrade. Save sentinels and backups were preserved. These installation tests did not launch the game or modify the live player installation.

**Interactive Windows UAC consent and elevated relaunch were not exercised.** Permission tests verify refusal, retry construction, reports and preservation; they do not establish that every PC will grant permission.

Historical legacy-schema migration and Workshop subscription tests remain inherited evidence; they are not counted as fresh0.2.5 tests. This is a controlled Windows single-player Alpha68.19 preview, not an exhaustive public playtest.

**Setup remains unsigned.** Smart App Control may block it, and the reported third-party antivirus detections remain unresolved without their exact details. SHA256 hashes identify files; they do not provide publisher authentication or a malware-free guarantee.

## Verified downloads

[Kevin Setup 0.2.5](https://github.com/SimpleNeb/Subsistence-Kevin/raw/e0892d87ee6a25f3d89bcb1727c3bc1f88382d09/downloads/Kevin-Setup-0.2.5-preview-Alpha68.19.exe). SHA256:

```text
6cfdfd25e1f3ddf5d177515abfc5b50a9a65a0d669c397f2ceca9da6f2c930cb
```

[Complete installer ZIP](https://github.com/SimpleNeb/Subsistence-Kevin/raw/e0892d87ee6a25f3d89bcb1727c3bc1f88382d09/downloads/Kevin-Companion-0.2.5-preview-Alpha68.19.zip). SHA256:

```text
684de53dd48574951722760455e8be983b45db803f5a37246c76469e0115fa2f
```

Both were downloaded anonymously from the same immutable commit and matched the exact tested local artifacts. [BUILD-PROOF.json](BUILD-PROOF.json) lists source identities and evidence hashes. Workshop subscription alone does not install or update the companion code; run the new installer with the game closed.
