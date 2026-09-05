# Brotato Tweaks

Optional gameplay tweaks for [Brotato](https://store.steampowered.com/app/1942280/Brotato/), each
one a switch you flip. **Everything is off until you turn it on**, so installing this mod changes
nothing about the game.

Set them from a **Tweaks** tab the mod adds to the game's own Options menu — from the title screen
and from the pause menu mid-run. No other mod required.

```
Options ▸  Audio   Visual   Gameplay   Accessibility   [ Tweaks ]
```

## The tweaks

| Tweak | What it does |
|---|---|
| **Enemy multiplier** | Spawns 1× to 10× the usual number of enemies, and lifts the wave's own enemy cap so they actually stay on screen instead of being culled. |
| **Enemy stat dials** | Scale enemy health, damage and speed independently. What makes a big multiplier playable. |
| **Horde every wave** | Adds the zone's horde groups to every wave, on top of what it already spawns. |
| **Elite schedule** | Move the first elite wave earlier or later, and change how often an elite is a horde instead. |
| **Bonus elites and bosses** | Adds elites, or the zone's actual bosses, to *every* wave from wave 1 — up to ten of each, on top of everything the wave already spawns. No chance and no schedule; vanilla's own elites still turn up as well. |
| **Wave length** | Longer or shorter waves. |
| **Death Guard** | When every player dies, offers to restart the wave instead of ending the run, as many times as you need. |
| **All Cursed** | Curses every item and weapon you are offered, using the DLC's own curse, and can curse enemies on spawn as well. Needs Abyssal Terrors. |
| **Recurse** | Re-rolls the curse on a cursed item you have locked in the shop, instead of leaving it stuck with the one it was given — at the same chance a new item has of arriving cursed. Needs Abyssal Terrors. |
| **No item limits** | Lifts the game's per-item cap, so an item you are only allowed one or two of keeps being offered. Two switches: limited items, and uniques. |
| **Bans** | Sets how many shop bans a run gets, and can put the ban button on weapons too. |
| **Recycle items** | Puts the shop's Recycle button on the items you already own, not just on weapons. One click recycles one copy. |
| **Weapon limit** | Fixes how many weapons you may hold, from one to twelve, whatever your character and items say. |
| **Past wave 20** | Two endless rules, off individually: stop Harvesting decaying by 20% a wave, and keep the Piggy Bank paying. |

Each one, with its dials and what it does and does not touch, is in
[docs/tweaks.md](docs/tweaks.md).

## Install

Download the zip from [Releases](https://github.com/SamadiPour/brotato-tweaks/releases) and drop it
in Brotato's `mods` folder:

| Platform | Folder |
|---|---|
| macOS | `~/Documents/Brotato/mods/` |
| Windows | `%USERPROFILE%\Documents\Brotato\mods\` |
| Linux | `~/.local/share/Brotato/mods/` (or beside the game) |

ModLoader ships inside the game — no patched executable, no separate install. Start the game and
the Tweaks tab is in Options.

To build it yourself:

```console
$ tools/build.sh --install     # zip it and copy it into the game's mods/ folder
```

Built for **Brotato 1.1.15** with ModLoader **6.3.0**. The Abyssal Terrors DLC is optional; the two
curse tweaks are the only ones that need it.

## Saves and runs

The mod writes nothing to your save file. Every tweak either rewrites a per-wave copy the game
throws away, or writes the one field the game writes itself at the same moment. Turn everything
off, or delete the mod mid-run, and the game is back to vanilla with no residue —
[the full list is in docs/tweaks.md](docs/tweaks.md#what-it-writes).

Runs made with a tweak on are not comparable to vanilla ones, and Death Guard deliberately raises
the retry counter the end-run screen shows.

## Documentation

| Doc | What is in it |
|---|---|
| [The tweaks in detail](docs/tweaks.md) | Every tweak, every setting, where the config lives |
| [00 — Research](docs/00-research.md) | The vanilla source each tweak stands on, with the code quoted, and why each seam was chosen |
| [01 — Architecture](docs/01-architecture.md) | Module contracts, extension points, settings, failure policy |
| [02 — Development setup](docs/02-dev-setup.md) | Godot 3, decompiling the game, the loop, adding a tweak |

```console
$ tests/run.sh                 # parse + core checks against stubs
$ tests/run_extensions.sh      # real ModLoader + adapters against decompiled vanilla
$ tests/run_menu.sh            # the settings tab, laid out on a real title screen
$ tests/run_baseline.sh        # the vanilla facts this mod stands on, still true
```

## License

MIT — see [LICENSE](LICENSE).
