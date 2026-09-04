# The tweaks in detail

Every tweak is off until you turn it on, and each one lists the config keys it reads. The keys
matter only if you edit the file by hand — the settings tab writes all of them for you.

## Where the settings live

**In the game's own Options menu, under a new tab called Tweaks.** Nothing else to install.

```
Options ▸  Audio   Visual   Gameplay   Accessibility   [ Tweaks ]
```

It is there both from the title screen and from the pause menu mid-run, it cycles with the shoulder
buttons like the vanilla tabs, and each dial appears only once you switch its feature on. Changes
save as you make them and apply from the next wave, the next pickup or the next death — no restart.

Brotato's own built-in Mods menu (Main menu → Mods) only *lists* installed mods and shows their
description; it has no settings editor, so it will not get you there.

Two other ways, if you want them:

**[Brotato Mod Options](https://github.com/BrotatoMods/Brotato-Mod-Options)**, if you already have
it for other mods, still works — this mod's settings appear on its screen and are saved. It is the
plainer of the two screens: no descriptions, no grouping, and every number shown as a percentage.

**By hand — edit `user.json`.** Launch the game once after installing, then open:

| Platform | File |
|---|---|
| macOS | `~/Library/Application Support/Brotato/configs/Brotato-Tweaks/user.json` |
| Windows | `%APPDATA%\Brotato\configs\Brotato-Tweaks\user.json` |
| Linux | `~/.local/share/Brotato/configs/Brotato-Tweaks/user.json` |

(Brotato sets `use_custom_user_dir`, so it is a plain `Brotato` folder, not the usual
`Godot/app_userdata/` one. The same folder holds `logs/` and your saves.)

It is a flat JSON file of the keys listed under each tweak below. Edit it with the game closed,
then start the game.

> **Edit `user.json`, not `default.json`.** ModLoader rebuilds `default.json` from the mod's schema
> on effectively every launch, so anything you type into that one is gone next time. The mod
> creates `user.json` on its first run precisely so there is a file that survives. Confirm which
> one it is using in `logs/modloader.log`:
>
> ```
> INFO Brotato-Tweaks: created configs/Brotato-Tweaks/user.json - edit that one, not default.json
> INFO Brotato-Tweaks: mounted - enemies x3, enemy hp x0.5, dmg x1, spd x1
> ```
>
> That second line always names what is on, so it is the fastest way to check a setting took.

Settings are read when each tweak acts, so a change applies from the next wave, the next pickup or
the next death. Only a hand edit needs the game closed.

## Enemy multiplier

Multiplies how many enemies each spawn group rolls, and scales the wave's `max_enemies` by the same
amount. That second half matters more than it sounds: once a wave has more enemies alive than its
cap, the game picks live enemies at random and **deletes** them, loot and all. Multiplying spawns
without lifting the cap gets you the same crowd plus a lot of quietly deleted enemies.

There is a third half, and it is the one that makes a high multiplier mean anything. The game
releases queued enemies on a fixed budget — two every third physics frame, **40 a second**, no
matter how many are waiting. Past about 4× the plan queues faster than that for the whole wave,
the extra enemies never arrive, and the lifted cap sits there unfilled. `enemies_fast_spawn`
releases them by the same multiplier instead. This is the setting that costs frame rate; turn it
off to keep vanilla's pace and use the multiplier as a slow trickle.

Left alone on purpose: **bosses and elites**, and **loot aliens and trees**. Multiplying loot
aliens is an economy mod wearing an enemy multiplier's name, and the game itself draws the same
line — the vanilla "more enemies" stat skips loot groups too.

High multipliers cost frame rate, and the cost is real: five times the enemies is five times the
collision and pathing work. Two or three is where the game still feels like itself.

| Key | Default |
|---|---|
| `enemies_enabled` | `false` |
| `enemies_multiplier` | `2` (1–10) |
| `enemies_raise_cap` | `true` |
| `enemies_fast_spawn` | `true` |

## Enemy stat dials

Scales enemy health, damage and speed on the way out of the game's own stat resolver — the same
place the accessibility sliders in Options apply, so the game is already balanced around these
numbers moving.

This is what makes the enemy multiplier playable at its top end. 5× enemies at 1× health is a
slideshow you lose; 5× enemies at 0.4× health is horde mode.

The bottom of each range means something different. Health never drops below 1, because a
zero-health enemy is a dead one at spawn. Damage never drops below 1 either — the game floors every
armoured hit at 1 itself, so no dial can make enemies harmless. Speed 0 does work, and leaves them
standing still.

| Key | Default |
|---|---|
| `enemy_stats_enabled` | `false` |
| `enemy_health_multiplier` | `1` (0.1–5) |
| `enemy_damage_multiplier` | `1` (0.1–5) |
| `enemy_speed_multiplier` | `1` (0–5) |

## Horde every wave

Adds the zone's horde groups — the ones a scheduled horde wave uses — to every wave, on top of what
that wave already spawns. It is an addition, not a replacement, so a horde wave is the normal wave
plus a horde.

Waves the game already scheduled as hordes are skipped, so you never get a double horde. Each
group's own wave range is honoured, because that is the zone author saying which hordes make sense
when. And injected hordes are multiplied by the enemy multiplier like any other enemy group.

| Key | Default |
|---|---|
| `horde_every_wave_enabled` | `false` |

## Elite schedule

Moves the wave the run's first elite is scheduled around, and changes how often a scheduled elite
comes as a horde instead. *How many* elites you get is still the game's call and still depends on
difficulty — only the timing and the coin flip change.

Endless is left alone on purpose: the game tops up elites mid-run with an absolute wave number, and
overriding that would schedule them into the past, where they simply never spawn.

| Key | Default |
|---|---|
| `elites_enabled` | `false` |
| `elites_first_wave` | `11` (1–50) — 11 matches vanilla |
| `elites_horde_chance` | `40` percent (0–100) |

## Bonus elites and bosses

The elite schedule above moves vanilla's timetable. This one ignores it: a fixed number of elites,
and a fixed number of bosses, added to **every** wave from wave 1, on top of whatever that wave
already spawns. No chance, no schedule, no difficulty gate — and vanilla's own elites still turn up
as well. The two switches are independent of each other and of the elite schedule.

They are the zone's own elites and the zone's own bosses, built by the game's own builders, so a
bonus boss is that boss at full health — one of them is a wave on its own. Each is picked from the
zone's list, every distinct one before any repeat, so a dial of ten on a zone with four elites
cycles rather than stacking the same one ten times.

Bonus elites and bosses arrive at the top of the wave, which is vanilla's own behaviour for an
elite group, and the enemy multiplier deliberately skips them — the two dials do not multiply each
other.

**On the last wave they have to die before the wave will end early.** The game ends a boss wave the
moment the last boss falls, and it counts elites in that number, so anything this added is part of
what has to be cleared. That is vanilla's rule for its own double boss, applied to more of them.

| Key | Default |
|---|---|
| `bonus_elites_enabled` | `false` |
| `bonus_elites_count` | `1` (1–10) |
| `bonus_bosses_enabled` | `false` |
| `bonus_bosses_count` | `1` (1–10) |

## Wave length

Multiplies each wave's duration, floored at 10 seconds.

Spawn timings inside a wave stay where the game put them, which is the interesting part: they are
absolute seconds, so a short wave cuts off the groups that were timed to arrive late, and a long
wave has everything on the field by the original duration and is carried by the repeating groups
after that. Rescaling the timings too would change *which* enemies a wave is made of rather than
how long it lasts.

| Key | Default |
|---|---|
| `wave_duration_enabled` | `false` |
| `wave_duration_multiplier` | `1` (0.25–3) |

## Death Guard

The game can already restart a wave — it is the "Retry wave" option in Options, and it is
unlimited. Death Guard is that same offer, made without turning the vanilla option on: while it is
enabled the retry prompt appears every time every player dies, as many times as you need.

Each restart is counted by the game's own retry counter, so it survives quitting and resuming a
run, resets with the run, and shows up on the end-run screen as the retry it is.

The restart itself is entirely the game's: same `Retry wave` confirm button, same
`reset_to_start_wave_state()`. This mod only decides whether the button is on screen.

| Key | Default |
|---|---|
| `death_guard_enabled` | `false` |

## All Cursed

Everything you are offered arrives cursed: stronger effects, and the curse that comes with them. It
calls the DLC's own `curse_item()`, so a cursed item from this mod is indistinguishable from one
the game cursed itself — including what it charges you in `stat_curse`, which means more cursed
enemies, which is the point.

- **Needs the Abyssal Terrors DLC.** Without it there is no curse system and this does nothing.
- **The shop card shows the curse.** Items and weapons are cursed when they are rolled, not when
  they are taken, so the curse icon, the boosted numbers and the `stat_curse` you are about to pay
  are all on the card before you buy. The same goes for a crate's item.
- A second pass at pickup catches what never passes through a roll: starting gear, the pre-run
  weapon screen, a consumable's item. Nothing is cursed twice — an already cursed item is handed
  straight back.
- Your **character** is never cursed, and neither are **level-up stat upgrades** — those never go
  through either path.

Cursed **enemies** are the other half of the DLC's curse system, and they have their own dial. The
game rolls one per enemy off your `stat_curse`; this rolls a second one at whatever chance you set,
on top of it. A cursed enemy is made by the DLC's own method — the same purple outline, the same
health, damage and speed boost, the same extra gold — so it is worth what a cursed enemy is worth.
Bosses and loot aliens are never cursed, and an enemy the game already cursed is never cursed
twice. At `0` the rate is the game's own.

| Key | Default |
|---|---|
| `cursed_enabled` | `false` |
| `cursed_items` | `true` |
| `cursed_weapons` | `true` |
| `cursed_enemy_chance` | `0` percent (0–100) |

## Recurse

A cursed item you lock in the shop keeps the exact curse it was given, forever. That is not a rule
anyone wrote — it falls out of `curse_item()` opening with "already cursed? hand it back", which is
also what stops the Fish Hook ever looking at a slot twice. So the roll that cursed it is the only
roll it ever gets, and the numbers on it are whatever that roll happened to give you.

Turn Recurse on and a cursed locked item is **put back through the offer roll** every time you leave
the shop — the same roll a brand new shop item goes through, made on the item's original. The curse
that comes back was rolled the way the game rolls one: a base modifier, a bump per wave, and a
random swing either side. So what you get can be better or worse than what you locked. Lock, leave,
come back, look.

**There is no chance setting**, on purpose. A locked cursed item is re-cursed exactly as often as a
new item of the same kind would arrive cursed — which is your Curse stat's doing, and with **All
Cursed** on is every single time. That is the pairing this tweak is for.

- **Needs the Abyssal Terrors DLC**, like everything else about curses.
- **A roll that misses costs you nothing.** The slot keeps the curse it already had — an item
  cannot lose a curse by being offered one.
- The item's **price does not move**: the curse never touched `value`, so a re-rolled item costs
  what it cost.
- It runs **before** the game's own pass over your locked items, so a slot the Fish Hook curses on
  this visit is not immediately re-rolled, and that item's pity counter is neither read nor written.

| Key | Default |
|---|---|
| `recurse_enabled` | `false` |

## No item limits

Some items are rationed. The shop card says `Unique` for the ones you may hold one of, and
`Limited (1/2)` for the ones with a number, and once you are at that number the game stops offering
them — in the shop, in crates, and from a treasure map alike. All of that is one field, `max_nb`,
read in one place.

Two switches, because they are two different runs:

- **No limit on limited items** covers everything capped at two or more.
- **No limit on unique items** covers the ones capped at one. These are the items the game most
  deliberately gave you only one of, so this is the sillier of the two — which is why it is its own
  switch.

An item the game never offers at all (`max_nb` of `0` — a character's own item, or one that only
arrives from an effect) is left alone by both. Putting those in the shop pool would be a different
feature.

The items that **duplicate** one of yours follow the same cap, and it is lifted with it, so a
Duplicator will not refuse to clone something the shop is happily selling you a third of.

The card still reads `Unique`, because that text is the item's own description and this tweak does
not rewrite it.

| Key | Default |
|---|---|
| `unlimited_items_enabled` | `false` |
| `unlimited_uniques_enabled` | `false` |

## Bans

The shop's ban button, with the allowance set by you. Vanilla gives every run 8 tokens; this gives
it as many as you want, and each ban still costs one.

- **It turns ban mode on for the run**, so you do not also have to remember the toggle on the
  character screen. It also lifts the challenge that normally has to be completed before bans
  appear at all.
- **Ban weapons too** puts the ban button on shop weapons, which vanilla hides. Everything behind
  it already worked — the game bans weapons this way from item boxes. A banned weapon is *that
  weapon at that tier*, the same way a banned item is that item, and it shows up in the pause
  menu's banned list with the rest.
- The allowance applies **from the next run**, because tokens are handed out when a run starts.
- The fisherman still cannot ban bait. That is the game protecting a character from itself, not a
  gate.

| Key | Default |
|---|---|
| `bans_enabled` | `false` |
| `bans_max` | `8` (0–100) — 8 matches vanilla |
| `bans_weapons` | `false` |

## Recycle items

Vanilla lets you recycle a **weapon** you own, and an **item** only while it is still being offered
to you. An item you have already taken is the one thing in a run you cannot get rid of. Turn this
on and the shop's item panel gets the same Recycle button the weapon panel has: click an item, and
it goes back for materials at the same rate a weapon does.

- **One click is one copy.** Identical items are drawn as a single square with a number on it, and
  each click takes one off that number — an item you hold three of takes three clicks. That is the
  game's own behaviour for a stack of identical weapons, not something this reimplements.
- **The payout is vanilla's**, including your Recycling Gains, the coupon, the items-price stat and
  any item that changes what one particular item is worth. The number on the button is the number
  you get, because both come out of the same two steps.
- **Your character cannot be recycled.** The character sits in the item list like everything else,
  and recycling it would strip the run of everything the character gives it.
- It does **not** count towards the recycling challenge. That is progress written to your save
  file, and this mod writes nothing there — vanilla's own item-box recycle does not count either.

| Key | Default |
|---|---|
| `recycle_items_enabled` | `false` |

## Weapon limit

Fixes how many weapons a player may hold. Vanilla starts you with six slots and then lets
characters, items and level-ups move that number around; this pins it, and everything that asks
"does another weapon fit" gets the pinned answer — the shop, the weapon counter on the pause menu,
the gear panel.

Set it to **1** for a one-weapon run. A character that starts with more than the limit is trimmed
at run start, from the back, so the weapon you picked on the selection screen is the one you keep.

The underlying weapon-slot effect is never overwritten, only answered over the top of, so turning
the tweak off mid-run gives you your character's real slot count back, untouched. Level-up weapon
slot upgrades are capped with it, so a low limit cannot leave you being offered a slot you are not
allowed to have, forever.

| Key | Default |
|---|---|
| `weapon_limit_enabled` | `false` |
| `weapon_limit` | `6` (1–12) — 6 matches vanilla |

## Past wave 20

Two vanilla rules that only exist in endless, each with its own switch. Neither one does anything
before wave 21, so both are safe to leave on for a normal run.

**Stop harvesting decay.** From wave 21 the game takes 20% of your Harvesting stat off at the end
of every wave, compounding, so a harvesting build unwinds on its own no matter how well you play.
Turn this on and the stat stays exactly where the run left it.

It does not start growing again — the +5% a wave you get up to wave 20 is a separate vanilla rule,
and turning that back on is a different feature. Nor does the Harvesting tooltip change: it is
built from the game's own `ENDLESS_HARVESTING_DECREASE` and will still describe the decay this is
skipping.

**Keep the Piggy Bank working.** The Piggy Bank pays you 20% of your materials at the start of
every wave and stops paying after wave 20 — it is the item's "limited" clause, and the Saver starts
the run holding it. Turn this on and it keeps paying at the same rate for as long as the run lasts.

Only a positive rate is affected. The Entrepreneur, who *loses* materials at the start of a wave,
is left exactly as vanilla has them, including vanilla's own endless rule that takes all of them.

| Key | Default |
|---|---|
| `endless_harvesting_enabled` | `false` |
| `endless_piggy_bank_enabled` | `false` |

## Logging

Writes one line per wave to `modloader.log` saying what each wave tweak did. Off by default; useful
when a setting does not seem to be taking effect.

| Key | Default |
|---|---|
| `verbose_log` | `false` |

## What it writes

The mod never writes to `RunData`, `ProgressData` or a save file except where the game writes the
same field itself. Its only files are its own config.

- The enemy multiplier, horde injection and wave length all rewrite a per-wave copy of the wave
  data that the game throws away at the end of the wave.
- Bonus elites and bosses append two groups to that same per-wave copy, leaving the game's own
  elite and boss schedules exactly as it filled them.
- The enemy stat dials multiply a returned number. Nothing is stored, not even in the game's own
  stat cache.
- The elite schedule changes two arguments to a vanilla call and lets it do its own work.
- Death Guard makes a hidden button visible. The vanilla button does the writing.
- All Cursed hands a cursed duplicate to the same method the game was going to call anyway, and
  curses an enemy by calling the DLC's own method on it.
- Recurse replaces one locked shop slot with a freshly cursed copy — the same field, in the same
  method, that the game's own Fish Hook pass writes. Locked shop items are run state; nothing
  reaches a save file.
- The item limits write nothing at all. They leave one entry out of the answer to "which items are
  at their cap", which is the only question the cap is ever asked.
- The weapon limit answers three vanilla questions with a different number and writes nothing. The
  one exception is a run started over the limit, where the weapons past it are dropped with the
  game's own `remove_weapon_by_index()`.
- Bans write one number the game writes itself at run start, at the same two moments.
- Recycling an item is the game's own `remove_item()` and `add_gold()`, in the shop, when you click
  the button — the same two calls the game makes to recycle a weapon on the same screen. It
  deliberately does not touch the recycling challenge, which is the one part of a recycle that
  would reach your save file.
- Stopping the harvesting decay writes nothing: it skips a stat removal the game was about to make,
  so the stat is left where it already was.
- The Piggy Bank past wave 20 adds materials with the game's own `add_gold()`, at the same moment
  and by the same sum vanilla uses up to wave 20. Run state only — nothing reaches a save file.

Turn everything off, or delete the mod mid-run, and the game is back to vanilla with no residue.

One thing worth saying plainly: any of these changes the run. Scores set with one on are not
comparable to vanilla ones, and Death Guard deliberately raises the retry counter the end-run
screen shows.
