# Kevin Companion 0.2.4 — build and validation

This release adds manual HUD recall and repairs native firearm transfers, including supported flashlight attachments. Installer scripts and native startup hooks remain unchanged from 0.2.3.

The exact production package passed ten static audits. Fresh controlled native checks:

| Feature | Passed | Failed |
| --- | ---: | ---: |
| recall | 43 | 0 |
| inventory | 72 | 0 |
| combat | 28 | 0 |
| menu | 26 | 0 |
| gathering | 34 | 0 |
| revival | 27 | 0 |
| death | 20 | 0 |

Native disk tests passed **18 checks** upgrading the prior save30 through enabled, disabled and re-enabled states, plus **23 checks** preserving a loaded, upgraded gun and partially charged flashlight across a fresh four-stage disk cycle. Full inventory fingerprints remain unchanged within each chain.

The final Setup passed **28 wrapper checks** and **154 actual installation checks** on isolated copies of the supported retail files: fresh installation, repeated installation, Disable/reinstall, denied writes, rollback and public0.2.3 upgrade. Save sentinels and backups were preserved. These installation tests did not launch the game or modify the live player installation.

**Interactive Windows UAC consent and elevated relaunch were not exercised.** Permission tests verify refusal, retry construction, reports and preservation; they do not establish that every PC will grant permission.

Historical legacy-schema migration and Workshop subscription tests remain inherited evidence; they are not counted as fresh0.2.4 tests. This is a controlled Windows single-player Alpha68.19 preview, not an exhaustive public playtest.

**Setup remains unsigned.** Smart App Control may block it, and the reported third-party antivirus detections remain unresolved without their exact details. SHA256 hashes identify files; they do not provide publisher authentication or a malware-free guarantee.

## Verified downloads

[Kevin Setup 0.2.4](https://github.com/SimpleNeb/Subsistence-Kevin/raw/ccb4ea4111a7a682bfac44f956ed104c97e25b78/downloads/Kevin-Setup-0.2.4-preview-Alpha68.19.exe) — SHA256:

```text
664774692334387cc763b748184d1b8a528a45633dd368091e28184b6b3a1d88
```

[Complete installer ZIP](https://github.com/SimpleNeb/Subsistence-Kevin/raw/ccb4ea4111a7a682bfac44f956ed104c97e25b78/downloads/Kevin-Companion-0.2.4-preview-Alpha68.19.zip) — SHA256:

```text
402f985c5eba4a6926262540e241bfc551501dadd1182a187af5432a91a789da
```

Both were downloaded anonymously from the same immutable commit and matched the exact tested local artifacts. [BUILD-PROOF.json](BUILD-PROOF.json) lists source identities and evidence hashes. Workshop subscription alone does not install or update the companion code; run the new installer with the game closed.
