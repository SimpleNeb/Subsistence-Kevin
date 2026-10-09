![Kevin Companion illustrated cover](artwork/preview.jpg)

**Kevin Companion for Subsistence — 0.2.0 preview**

A friend for the wilderness. Kevin joins you automatically, carries the supplies
you cannot leave behind, wears the gear you give him, and helps defend against
immediate threats. Send him to gather wood or fiber while you work nearby.

For **Subsistence Alpha 68.19 on Windows, standalone single-player only**.
You need your own installed copy of that game build.

1. Close Subsistence and [download Kevin Setup](https://github.com/SimpleNeb/Subsistence-Kevin/raw/b793c17a68246fb815df2bb2a9ba2e72bb482277/downloads/Kevin-Setup-0.2.0-preview-Alpha68.19.exe).
2. Open it and choose **Install / Update**. Setup finds the Steam game folder;
   use **Browse** if it cannot identify yours.
3. Start Subsistence, select **Kevin Companion** in your profile's **Mods** list,
   and start or continue the profile. Kevin needs no recruitment quest.

Prefer a ZIP? [Download the ZIP installer](https://github.com/SimpleNeb/Subsistence-Kevin/raw/b793c17a68246fb815df2bb2a9ba2e72bb482277/downloads/Kevin-Companion-0.2.0-preview-Alpha68.19.zip),
extract the entire archive, and double-click **Install Kevin.cmd**. It contains
the same companion package and installer scripts. Choose either Setup or the ZIP;
you do not need both. No compiler, SDK, Python, or account login is required.

A Steam Workshop subscription alone cannot install Kevin's companion code.
Workshop users still need to run Setup or the ZIP installer, then select Kevin
in the game's Mods list.

| What you want to do | Control |
| --- | --- |
| Open Kevin's inventory | Stand nearby and press your normal **Use** key |
| Give an order | Crouch nearby and press **Use** |
| Choose a menu command | Click, press **1–5**, or use the arrow keys and **Enter** |
| Close the command menu | **Escape** or right-click |
| Revive Kevin from his dropped bag | Crouch by the bag and press **Use** |
| Loot his dropped bag | Stand by the bag and press **Use** |

![Kevin's five-command menu in Subsistence](artwork/Kevin-Command-Menu.png)

The command menu offers **Follow Me**, **Stay Here**, **Inventory & Equipment**,
**Gather Wood**, and **Gather Fiber**. Kevin runs when he falls behind. Gather Wood
requires a usable axe in his cargo or toolbelt; Gather Fiber needs no tool.
Both jobs use actual nearby resources. Trees deplete, axes wear, and fiber plants
are consumed. Gathering stops when his cargo is full or he cannot work safely.
Stay nearby and give the gathering order again after reloading, revival, or a
combat interruption.

Kevin has **35 cargo slots, seven toolbelt slots, and six clothing slots**.
Drag items into his inventory; shift-click into Kevin is disabled. Take items
back by dragging or shift-clicking them out when your inventory has room. Put
clothing and armor in their matching slots. Items containing their own storage
cannot be carried in his inventory.

Equip a supported firearm in his toolbelt and provide matching ammunition:

| Firearm | Ammunition Kevin can use |
| --- | --- |
| M9 or Red9 | 9mm rounds |
| M37 shotgun | Shotgun shells |
| Double-barrel shotgun | Shotgun shells or shotgun slugs |
| Rifle or lever-action rifle | Rifle rounds |
| Revolver | .44 rounds |

Kevin reloads from what he actually carries. Ammunition is finite; explosive,
incendiary, and other unsupported weapon/ammunition combinations are not used
for defense.

If Kevin dies, his belongings remain in his dropped bag. Revive him there, or
wait **about two minutes while the world is running** for him to return near you
on safe outdoor ground. He returns with half health and an empty inventory;
retrieve and re-equip his original belongings. If no safe location is available,
his return waits. Saving retains the remaining return time, and the countdown
pauses while Kevin is disabled or you are dead. The game's normal loot-bag expiry
still applies, so recover valuable equipment promptly.

To disable Kevin for one profile, remove him from that profile's Mods selection.
To disable him everywhere, close the game and choose **Disable Kevin** in Setup,
or run **Disable Kevin.cmd** from the extracted ZIP. Disabling restores the
original startup files and retains his compatibility package and saved belongings.
Use **Install / Update** to enable him again or update a supported earlier preview.
Keep the game's `.KevinLoader` folder and `KevinCompanion.u`; existing Kevin saves
need those saved classes. The installer does not rewrite your save files.

This is an outdoor companion preview. Following pauses around bases and caves,
and terrain or obstacles may require repositioning or another order. Kevin does
not teleport to catch up. Multiplayer, building jobs, and taking direct player
control of Kevin are not included. The installer refuses unsupported game builds
and conflicting file changes; after a game update, use a matching Kevin release.

The download includes a player guide, completed validation details, and checksums.
Setup is an unsigned community preview. Its source and generated SHA256 checksum
are provided with the download. Report problems through this repository's Issues
page and include the game build and Kevin version.

Created by **SimpleNeb**. Unofficial and not affiliated with Subsistence's
developer. The cover is an illustration, not a gameplay screenshot. Subsistence
and its original assets belong to their respective owners; this project requires
your installed game and does not distribute the original game files or SDK.
