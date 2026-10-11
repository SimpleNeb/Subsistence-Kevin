# Kevin Companion 0.2.3 preview — player guide

Kevin joins you automatically when his mod is selected. Start or continue a
supported single-player world; no recruitment quest is required.

Version 0.2.3 improves Setup's permission handling and diagnostic reports, and
corrects installation-record reading for non-English folder names. Gameplay is
identical to 0.2.2, including its wider gathering range. Keep the same
[Workshop subscription](https://steamcommunity.com/sharedfiles/filedetails/?id=3816609201).
If Kevin already works, this version adds no gameplay changes.

## Install or update

1. Subscribe to the Workshop item.
2. Close Subsistence. [Download Kevin Setup 0.2.3](https://github.com/SimpleNeb/Subsistence-Kevin/raw/6410f4b8a0c93f52f692a61817bedadcbdf0dc7e/downloads/Kevin-Setup-0.2.3-preview-Alpha68.19.exe),
   open it, and click **Install / Update**. Use **Browse** if Setup cannot find
   your Steam game folder. For an access-denied error, choose **Retry as
   administrator** and approve the Windows permission prompt.
3. Start the game, select **Kevin Companion** in the profile's **Mods** list,
   and start or continue that profile.

Subscribing alone does not install Kevin's companion code. Setup is required,
including when upgrading from the supported **0.1.0, 0.2.0, 0.2.1 or 0.2.2 previews**. No
compiler or account login is needed in Setup. If you use the
[ZIP installer](https://github.com/SimpleNeb/Subsistence-Kevin/raw/6410f4b8a0c93f52f692a61817bedadcbdf0dc7e/downloads/Kevin-Companion-0.2.3-preview-Alpha68.19.zip)
instead, extract the complete archive and double-click **Install Kevin.cmd**.

**For every Kevin update, download and run the new version's installer with the
game closed.** A Workshop update alone does not update the installed companion
code. Keep your subscription and choose **Install / Update** in the new Setup,
or run **Install Kevin.cmd** from the new ZIP.

## Talk to Kevin

Stand close and press your normal **Use** key to open his inventory. Crouch
near him and press **Use** for the command menu.

| Command | What Kevin does |
| --- | --- |
| Follow Me | Follows you and runs when he falls behind |
| Stay Here | Waits where you leave him |
| Inventory & Equipment | Opens his cargo, weapons and clothing |
| Gather Wood | Chops nearby trees using a usable axe you supplied |
| Gather Fiber | Collects nearby fiber plants; no tool required |

Click a command, press **1–5**, or use the arrow keys and **Enter**.
**Escape** or right-click closes the menu. Taking damage also closes it.

## Supplies, clothes and weapons

Kevin has **35 cargo slots, seven toolbelt slots and six clothing slots**.
Drag items into his inventory; shift-click into Kevin is disabled. Take items
back by dragging or shift-clicking them into your inventory when you have room.
Put clothing and armor in their matching slots. Items containing their own
storage cannot be placed in Kevin's inventory.

Put a supported firearm in his toolbelt and provide matching ammunition:

| Firearm | Ammunition Kevin can use |
| --- | --- |
| M9 or Red9 | 9mm rounds |
| M37 shotgun | Shotgun shells |
| Double-barrel shotgun | Shotgun shells or shotgun slugs |
| Rifle or lever-action rifle | Rifle rounds |
| Revolver | .44 rounds |

Kevin helps defend against immediate threats and reloads from his carried
ammunition. His ammunition is finite. Explosive, incendiary and other
unsupported weapon/ammunition combinations are not used for defense.

## Wood and fiber

Give Kevin a usable axe in his cargo or toolbelt, then choose **Gather Wood**.
Wood comes from actual trees and follows the player's tree-depletion record.
Chopping wears the axe. **Gather Fiber** consumes actual nearby plants.

Kevin now searches 2.5 times farther than before, centered on his current
position whenever he chooses the next resource. He still works within a limited
distance of you, so stay near him. The wider search helps him move through
nearby patches; it does not make every tree or plant reachable.

Gathering can stop if his cargo is full, his axe is unusable, no reachable
resources remain in range, the route is blocked or the job becomes unsafe.
A full cargo inventory stops gathering before a resource is consumed. If Kevin
stops gathering and follows you, move near another patch and give the order
again. Choose another command to change his job.

Gathering jobs do not resume after a reload, revival or combat interruption.
Open the command menu and give the order again.

## If Kevin dies

His belongings stay in his dropped loot bag. **Crouch and press Use** on the
bag to revive him nearby, or wait about **two minutes while the world is
running** for him to return near you on safe outdoor ground. If no safe location
is available, his return waits.

He returns with half health and an empty inventory. Retrieve his original
belongings from the bag and equip him again; revival does not duplicate them.
**Stand and press Use** for normal looting. The game's ordinary bag expiry
still applies, so recover valuable equipment promptly.

Saving and quitting preserves the remaining return time. The countdown pauses
while Kevin is disabled or you are dead.

## Saving, disabling and re-enabling

Kevin's location, belongings, health and follow/stay order are saved. Gathering
orders must be given again after loading.

For one profile, remove Kevin Companion from that profile's Mods selection.
For every profile, close the game and choose **Disable Kevin** in Setup, or
double-click **Disable Kevin.cmd** from the extracted ZIP. This restores the
original startup files and retains Kevin's compatibility package and saved
belongings. Use **Install / Update** to enable the supported build again.

Keep the game's `.KevinLoader` folder and `KevinCompanion.u`. The first contains
the backups and install record; the second supplies the classes used by Kevin
saves. The installer and disable tool do not rewrite your save files.

## Preview limits

Supported: **Windows, standalone single-player, Subsistence Alpha 68.19**.
Following and gathering are intended for outdoor surface terrain. Following
pauses around bases and caves. Obstacles may require repositioning or another
order; Kevin does not teleport to catch up.

Multiplayer, building jobs and taking direct control of Kevin as the player
character are not included. This preview has not had a long public playtest
across every terrain, enemy, weapon or combination of mods.

Setup refuses unsupported game versions and conflicting file changes. After a
game update, use a Kevin release that supports that build. Setup is unsigned;
use the supplied checksums to identify the release you downloaded.

This is an unofficial community mod, not affiliated with Subsistence's developer.
See [build and validation details](BUILD-PROOF.md) for the checks and their scope.

## If installation fails

Keep Subsistence closed. Use **Browse** to select its folder containing
`Binaries` and `UDKGame`. If Windows denies access, **Retry as administrator**
reopens the same installer with your selected folder and action. Canceling the
Windows permission prompt leaves Setup open so you can retry later.

For other failures, click **Save setup report...**. Setup also saves reports in
`%LOCALAPPDATA%\KevinCompanion\Logs`. Reports include local folder paths;
review those before posting them publicly. Include the report, Kevin version
and game build when reporting an issue.

The ZIP fallback uses the same loader scripts. If its command window reports
access denied, right-click **Install Kevin.cmd** and choose **Run as administrator**.
Setup is recommended for its folder picker, retry button and saved reports.

A game-version/checksum error needs a matching supported game build. Keep the
`.KevinLoader` backups when a previous installation exists; do not force a
patch over changed files. These improvements address reproduced installer
issues, but an unfamiliar error still needs its report for diagnosis.
