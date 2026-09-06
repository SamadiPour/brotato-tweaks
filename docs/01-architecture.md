# 01 — Architecture

## Shape of the thing

Seventeen independent tweaks, one shared spine, and one screen to set them from:

```
        vanilla game                            mod

 ┌──────────────────────────┐   ┌──────────────────────────────┐
 │ EntitySpawner.init       │──▶│ extensions/global/           │──┐
 │ EntitySpawner.enemy_resp.│──▶│                              │  │
 │ EntityService.get_final_*│──▶│                              │  │
 │ ItemService.apply_item_* │──▶│ extensions/singletons/       │  │
 │ RunData.add_item/weapon  │──▶│                              │──┤  thin adapters:
 │ RunData.init_elites_spawn│──▶│                              │  │
 │ RunData.remove_stat      │──▶│                              │  │
 │ WaveManager.init         │──▶│ extensions/zones/            │  │  find, ask, apply
 │ RunData.reset / effects  │──▶│                              │  │
 │ ZoneService.get_wave_data│──▶│                              │  │
 │ Main.players_spawned     │──▶│ extensions/main.gd           │  │
 │ MenuRetryWave.show       │──▶│ extensions/ui/menus/ingame/  │──┤
 │ UpgradesUIPlayerContainer│──▶│                              │  │
 │ ShopItem / DifficultySel.│──▶│ extensions/ui/menus/…        │──┤
 │ ItemPopup / BaseShop     │──▶│                              │──┤
 │ Shop / CoopShop          │──▶│                              │──┤
 │ TitleScreen / PauseMenu  │──▶│                              │──┤
 └──────────────────────────┘   └───────────────┬──────────────┘  │
                                        mounts  │                 ▼
                                                ▼   ┌────────────────────────────┐
                                 ┌──────────────────┤ tweaks.gd                  │
                                 │ ui/              │   on/off, logging          │
                                 │  options_tab     ├──────┬─────────┬───────────┘
                                 │  tweaks_tab      │      │         │
                                 └──────────────────┘      │         ▼
                                          ▲                │  ┌────────────────┐
                                          │                │  │ settings_store │
                                          │                │  │ (ModLoader)    │
                                          │                │  └───────┬────────┘
      ┌──────────────────┬─────────────────┴┬──────────────┴──┐       ▼
      ▼                  ▼                  ▼                 ▼  ┌────────────────┐
┌──────────────┐ ┌──────────────┐ ┌────────────────┐             │ settings_layout│
│ wave_scaling │ │ enemy_stats  │ │ elite_schedule │             │ (pure)         │
│ (pure)       │ │ (pure)       │ │ (pure)         │             └────────────────┘
└──────────────┘ └──────────────┘ └────────────────┘
                 ┌──────────────┐ ┌────────────────┐    ┌────────────────┐
                 │ loadout      │ │ bonus_spawns   │    │ curse          │
                 │ (pure)       │ │ (pure)         │    │ (reads the DLC)│
                 └──────────────┘ └────────────────┘    └────────────────┘
                 ┌──────────────┐ ┌────────────────┐    ┌────────────────┐
                 │ recycling    │ │ item_limits    │    │ tweaks_lookup  │
                 │ (pure)       │ │ (pure)         │    │ (finds Tweaks) │
                 └──────────────┘ └────────────────┘    └────────────────┘
                                                          ▲
                                        every adapter ────┘
```

- **Adapters contain no decisions.** Each one calls the vanilla method, asks `Tweaks` a question,
  and applies the answer. Finding `Tweaks` to ask is `core/tweaks_lookup.gd`, once rather than
  thirteen times.
- **`Tweaks` answers about the game and nothing else.** It says "is this on", turns a feature off
  when an adapter reports that vanilla no longer looks the way it needs to, and writes the log line
  that names which tweaks are live. Where a setting is *kept* — the config file, the debounce, the
  Mod Options bridge — is `core/settings_store.gd`, because none of that is a decision about the
  game.
- **The cores take data and return data.** Eight of them name no game class at all and are exercised
  headless by `tests/run.sh`. Three do not pretend to: `curse.gd` reaches for the DLC resource
  through `ProgressData`, so only its pure half — the two item rules — runs under stubs;
  `settings_store.gd` is ModLoader's whole surface; and `tweaks_lookup.gd` is one group lookup.

That separation is what makes this survivable across patches: a renamed vanilla method breaks one
adapter, and the mod's answer is to switch that one feature off.

## File layout

```
root/mods-unpacked/Brotato-Tweaks/
  manifest.json          declares the mod and the settings schema
  mod_main.gd            _init installs seventeen extensions, _ready mounts Tweaks
  tweaks.gd              the mod's own node; answers the adapters, delegates settings to the store

  core/
    settings_store.gd    the settings themselves, and the whole of the ModLoader side of them
    tweaks_lookup.gd     how all thirteen adapters find the Tweaks node
    wave_scaling.gd      pure: one wave's spawn plan — multiply it, lengthen it, add hordes
    enemy_stats.gd       pure: one enemy stat times a dial, with the right floor
    elite_schedule.gd    pure: which init_elites_spawn() call may be rewritten, and to what
    bonus_spawns.gd      pure: how many bonus elites or bosses a wave gets, and which ones
    spawn_rate.gd        pure: how many extra queued enemies one spawn tick may release
    loadout.gd           pure: how many ban tokens and how many weapon slots a player gets
    recycling.gd         pure: the specific_items_price factor a recycle is priced through
    item_limits.gd       pure: whether one item's own max_nb cap should be ignored
    settings_layout.gd   pure: the schema plus the settings — rows a screen can draw, and
                         which saved numbers the schema no longer allows
    curse.gd             find the DLC, curse or re-curse one item, curse one enemy — or hand it
                         straight back
    logger.gd            ModLoaderLog with a mod-scoped prefix

  ui/
    options_tab.gd       adds the tab to a MenuOptions; the only file that names its node paths
    tweaks_tab.gd        the screen itself: draws rows, reports changes, decides nothing

  extensions/            mirrors vanilla paths exactly
    global/entity_spawner.gd
    main.gd
    singletons/entity_service.gd
    singletons/item_service.gd
    singletons/run_data.gd
    singletons/zone_service.gd
    ui/menus/ingame/pause_menu.gd
    ui/menus/ingame/retry_wave.gd
    ui/menus/ingame/upgrades_ui_player_container.gd
    ui/menus/run/difficulty_selection/difficulty_selection.gd
    ui/menus/shop/base_shop.gd
    ui/menus/shop/coop_shop.gd
    ui/menus/shop/item_popup.gd
    ui/menus/shop/shop.gd
    ui/menus/shop/shop_item.gd
    ui/menus/title_screen/title_screen.gd
    zones/wave_manager.gd
```

There are no scenes, no assets and no translations, so the zip is the scripts and the manifest. The
settings tab is built in code out of the game's own widgets for that reason: a `.tscn` would carry
resource paths that a patch can move, and an icon would carry a `.import` folder.

## Lifecycle

| When | What happens |
|---|---|
| `mod_main._init()` | Install the seventeen script extensions. Nothing else — the game is barely alive here. Four of them are the shop, three of which inherit from the fourth; ModLoader sorts every queued extension by its inheritance chain, so the order they are listed in is not load-bearing. |
| `mod_main._ready()` | Add the `Tweaks` node, which adds its `SettingsStore` child and calls `mount()` on it: read the config, create `user.json` if it is not there yet, wire the ModLoader and Mod Options signals, start the save debounce. Then log which tweaks are on. No game content is read. |
| Config changed | `ModLoader.current_config_changed` → re-read settings, repair them against the schema the way `mount()` does, and log the new summary. Every tweak reads its setting at the moment it acts, so changes take effect on the next wave, the next pickup, the next death. |
| The title screen or the pause menu is built | Its adapter calls `OptionsTab.attach()`, which appends the mod's tab to the Options menu's `UIBetterTabContainer`. See "The settings tab" below. |
| A widget on the mod's own tab moves | `TweaksTab.setting_changed` → `Tweaks.set_setting()` → `SettingsStore.set_setting()`, which saves `user.json` (debounced) and emits `changed`. `Tweaks` re-emits that as `settings_changed`, which is what hides or shows the sub-options below a toggle. |
| A widget on the Mod Options screen moves | `ModsConfigInterface.setting_changed` → the same `set_setting()`. See "Brotato Mod Options" below. |
| A wave is loaded | `ZoneService.get_wave_data()` → `Tweaks.scale_wave_duration()` sets how long it lasts, before `main.gd` reads it for the timer. |
| A wave is assembled | `WaveManager.init()` → `Tweaks.bonus_elite_count()` / `bonus_boss_count()` / `pick_bonus()`, and one group per feature is appended to what vanilla just finished building. |
| A wave starts | `EntitySpawner.init()` → `Tweaks.inject_hordes()` then `Tweaks.scale_wave()` rewrite that wave's spawn plan, in that order. Both run after the line above, and both skip the `is_boss` groups it added. |
| An enemy stat is resolved | `EntityService.get_final_enemy_*()` → `Tweaks.scale_enemy_*()`. |
| A run is set up | `RunData.init_elites_spawn()` → `Tweaks.elite_schedule_args()`. |
| An item or weapon is rolled for the shop or a crate | `ItemService.apply_item_effect_modifications()` → `Tweaks.curse_data()`, so the card shows the curse before it is bought. |
| The pool for that roll is narrowed | `ItemService.get_limited_items()` → `Tweaks.item_limit_lifted()`, and an item whose cap the player lifted is left out of the answer, so vanilla never removes it from the pool. Its only other caller — the treasure map's extra crate item — is covered by the same line. |
| A duplicating item asks how many clones are left | `RunData.get_remaining_max_nb_item()` → the same `Tweaks.item_limit_lifted()`, answered with `Utils.LARGE_NUMBER`, which is vanilla's own answer for an uncapped item. |
| The shop closes | `BaseShop._on_tree_exited()` → each cursed locked slot's original goes back through `ItemService.apply_item_effect_modifications()` — the offer roll, All Cursed included — and `Tweaks.recurse_locked()` says which of the two the slot keeps. *Before* the vanilla call, so vanilla's Fish Hook pass sees the shop it would have seen. |
| An item or weapon enters an inventory | `RunData.add_item/add_weapon` → `Tweaks.curse_data()`. Whatever the roll already cursed arrives cursed and is handed straight back. |
| An enemy spawns | `EntitySpawner.enemy_respawned` → `Tweaks.curse_enemy()`, straight after the DLC's own listener has had its roll on the same enemy. |
| A run is reset, and again when a difficulty is chosen | `RunData.reset()` / `DifficultySelection._on_element_pressed()` → `Tweaks.apply_ban_tokens()`. Both, because the second overwrites the first with the vanilla constant. |
| Anything asks how many weapons fit | `RunData.get_player_effect/get_free_weapon_slots/has_weapon_slot_available()` → `Tweaks.weapon_limit()`. Nothing is written; the vanilla effect underneath is untouched. |
| Starting weapons are handed out | `RunData.add_starting_items_and_weapons()` → `Tweaks.weapon_overflow()`, and anything past the limit is dropped from the back. |
| A shop card or an item-box panel is drawn | `ShopItem.manage_ban_button_visibility()` / `UpgradesUIPlayerContainer.show_item()` → `Tweaks.ban_allowance()`, `bans_cover_weapons()`, `ban_label_counts()`. |
| An owned item is hovered or clicked in the shop | `ItemPopup.should_show_buttons()` → `Tweaks.recycle_items()`, which is what puts Recycle on an item's popup as well as a weapon's. |
| Recycle is pressed on an owned item | `ItemPopup._on_DiscardButton_pressed()` → `BaseShop.tweaks_recycle_item()` → `Tweaks.recycle_price_factor()`, then the game's own `remove_item()` and `add_gold()`. One press, one copy. |
| Every player dies | `MenuRetryWave.show()` → `Tweaks.feature_enabled("death_guard")` decides whether to offer the restart. |
| The harvesting stat is removed, past wave 20 | `RunData.remove_stat()` → `Tweaks.keep_harvesting()`, and the removal is skipped. The one vanilla line this can be is the endless decay. |
| The players spawn into a wave, past wave 20 | `Main._on_EntitySpawner_players_spawned()` → `Tweaks.keep_piggy_bank()`, and the payout vanilla stops at wave 20 is made after its call. |

Nothing is loaded eagerly and nothing is cached, because no tweak reads the item catalog or
anything else expensive. Two things are on a hot path: the enemy stat dials, once per enemy stat
lookup, and `RunData.get_player_effect()`, several times per enemy per frame. The dials are a group
lookup, a clamp and a multiply; `get_player_effect()` compares the key against two integers before
it does anything at all, and the RunData adapter keeps the `Tweaks` node it found rather than
walking the tree for it. `remove_stat()` is on the same adapter and is not hot — a few calls a run
— but follows the same shape: one integer compare and a wave comparison before anything is looked
up.

## Module contracts

### `core/wave_scaling.gd`

```gdscript
static func scale(wave_data, multiplier: float, raise_cap: bool, enemy_type: int) -> Dictionary
# {ok, reason, groups_scaled, units_scaled, cap_before, cap_after}
```

Rewrites the wave in place and reports what it did. `ok` false means the wave was not shaped the
way this expects, and `reason` says how; the caller switches the feature off on that.

`enemy_type` is the caller's `EntityType.ENEMY`, passed in so the module names no game global and
the enum stays the game's to define.

Two rules it enforces, both copied from vanilla's own condition in
`on_group_spawn_timing_reached()` — see [00 — Research](00-research.md#1-enemy-multiplier):

- only units whose `type` is ENEMY are scaled; bosses and elites are not this feature.
- loot groups and neutral groups are never touched, because loot aliens are free items and trees
  are free materials.

And one rule that is about not corrupting the game: **groups are replaced, never edited.** Several
groups in a wave's array are references to session-lifetime resources, so editing one in place
would compound the multiplier on every later wave and outlive turning the setting off.

```gdscript
static func scale_duration(wave_data, multiplier: float) -> Dictionary
# {ok, reason, before, after}
static func inject_groups(wave_data, groups: Array, current_wave: int) -> Dictionary
# {ok, reason, injected}
```

`scale_duration()` is applied from a different seam than the other two — `main.gd` reads
`wave_duration` before `EntitySpawner.init()` runs — and leaves each group's `spawn_timing` alone,
because those are absolute seconds and rescaling them would change what a wave is made of rather
than how long it lasts.

### `core/spawn_rate.gd`

```gdscript
static func extra_per_tick(queue_size: int, multiplier: float, enabled: bool) -> int
```

The enemy multiplier's other half, and the one without which the first half is invisible past
about 4×. `wave_scaling.gd` decides how many enemies are *queued*; this decides how many arrive.

Vanilla drains `EntitySpawner.queue_to_spawn` on a fixed budget — `spawn()` pops one entity, at
most two calls, once every three physics frames — which is 40 enemies a second at Godot 3's default
physics rate and does not move when `max_enemies` or the multiplier does. A multiplied plan queues
several hundred a second, the queue grows for the whole wave, and the number alive settles at 40/s
times how long an enemy survives: well under a cap that was correctly lifted to ten times vanilla's.
See [00 — Research](00-research.md#1-enemy-multiplier).

So this returns how many *extra* pops the adapter should add on top of the ones vanilla just did.
`VANILLA_PER_TICK` is subtracted for that reason. 0 for every reason to do nothing — feature off,
dial at 1, queue empty — so the adapter can skip the queue entirely on a 0, and `MAX_PER_TICK`
keeps a hand-edited config from asking one frame to instance a thousand enemies.

`inject_groups()` appends copies, keeping each group's own `min_wave`/`max_wave` filter. It is used
for "horde every wave", and the adapter calls it *before* `scale()` so injected hordes are
multiplied like any other enemy group.

### `core/enemy_stats.gd`

```gdscript
static func scale(value: float, multiplier: float, minimum: int) -> int
```

One multiply and a clamp, applied to what `EntityService` already returned rather than folded into
the factor it caches. The floor is the caller's, because zero means something different per stat:
health and damage floor at 1 — the second because `Player.get_damage_value()` resolves an armoured
hit as `max(1, …)`, so no dial can make enemies harmless — and speed may reach 0, which is standing
still.

### `core/elite_schedule.gd`

```gdscript
static func override_args(base_wave: int, horde_chance: float,
                          first_wave: int, horde_percent: float) -> Dictionary
# {apply, base_wave, horde_chance}
```

`apply` false means "pass the caller's own arguments through". That is the whole module: `main.gd`
tops up elites in endless with an absolute wave number, and rewriting *that* call would schedule
elites into the past. Only a call that used both vanilla defaults — the run-start one — is
rewritten.

### `core/settings_layout.gd`

```gdscript
static func build(properties: Dictionary, settings: Dictionary) -> Array
# [{title, rows: [{key, kind, title, description, parent, value, minimum, maximum, step, text}]}]
static func row_visible(row: Dictionary, settings: Dictionary) -> bool
static func format_value(key: String, value: float) -> String
static func out_of_range(properties: Dictionary, settings: Dictionary) -> Array
# [{key, value, clamped}]
```

The three things a JSON schema cannot say, kept out of the screen that draws them: what order the
settings go in and how they group; which rows are sub-options of which toggle, which is what lets
the screen hide a dial whose feature is off; and how a number reads, because `2.0`, `40` and `11`
render as `2.0x`, `40%` and `11` and Mod Options renders all three as a percentage of 1.

One property worth keeping: a key the schema declares and no section here claims is still drawn, in
a trailing section. A setting added to `manifest.json` and forgotten here stays reachable — only
its placement is lost. `tests/godot/core_test.gd` checks exactly that.

`out_of_range()` is the same schema read for a different reason. ModLoader validates the *whole*
config on every save, so one number left over from a version whose range was wider makes
`update_config()` reject the file and nothing the player changes is ever written again — silently,
because the only sign is a line in ModLoader's own log. `Tweaks` clamps what this reports on load,
once, and says so. `multipleOf` is deliberately not enforced: the validator checks it too, but an
off-step value can only have come from a hand-edited file, where rounding it would throw away a
choice someone made on purpose.

### `core/settings_store.gd`

```gdscript
func mount() -> void                                    # called by Tweaks, once it is in the tree
func get_setting(key: String, default = null)
func set_setting(key: String, value) -> void
func reset_to_defaults() -> bool                        # false = nothing was done
func flush_pending_save() -> void                       # write a debounced save now
func get_schema_properties() -> Dictionary
func schema_description() -> String
var settings: Dictionary
signal changed(settings)                                # a value moved; emitted at once
signal persisted(settings)                              # it reached disk; at most one per debounce
```

A `Node`, mounted as a child of `Tweaks`, because the debounce and the wait for Mod Options are both
timers and a timer needs a tree. `mount()` rather than `_ready()`, so the order of load, config
creation, signal wiring and the Mod Options bridge is written down rather than left to when the
parent happened to add the child.

The two signals are one distinction: `changed` is every edit, which is what a screen follows;
`persisted` is at most one per 0.4 s window, which is why it is the one the summary is logged from.
A slider drag emits a value per step and would otherwise be a line in the log and a file write each.

The window is short but it is not zero, and the change a player makes last is the one they came to
the menu for. `_exit_tree()` flushes a save still owed, so quitting from the pause menu's own
options screen writes it rather than dropping it.

`set_setting()` is the single write path — the mod's own tab and Mod Options both end there — and it
accepts only keys the schema declared. `get_schema_properties()` reads the *default* config's schema
rather than the loaded one, because ModLoader regenerates that from the manifest on every boot: it
is the newer of the two whenever the mod has been updated under an existing `user.json`.

**Settings live in the mod's own named config, and it is created eagerly.** ModLoader regenerates
`default.json` from the manifest schema on effectively every boot, so a player editing that file by
hand loses the edit on the next launch. `_ensure_user_config()` therefore creates `user.json`,
seeded with the schema defaults, on the mod's first run — so there is always a file that survives.

Reading it back cannot rely on `get_current_config()`, which answers entirely from
`mod_user_profiles.json`: a profile written while the mod was not yet valid carries no entry, and
then the file the player has been editing is invisible. So `_load_settings()` tries, in order, the
profile's current config, then `user.json` by name out of `get_configs()` (which ModLoader
populates from disk at boot regardless of the profile), then the schema defaults.

Making the config current is a profile write — `ModData.current_config` has a setter that reaches
into `mod_user_profiles.json` — and that setter dereferences the current profile with no null
check. So it is guarded on a profile existing, and skipping it costs nothing because the read path
above finds the file by name anyway. Every route to it goes through `_make_current()`, saving
included: the branch that saves into a `user.json` the profile does not know about is exactly the
one a player with no profile entry takes.

A config read back is repaired before it is used, on both routes in — `mount()` and
`current_config_changed`. A `user.json` older than the schema is missing keys the schema has since
gained, which is an index error on the Mod Options screen rather than a default, and it can hold a
number a later version narrowed the range on — and ModLoader validates the *whole* config on every
save, so one of those makes every later write fail silently. `_fill_missing_keys()` fills what is
missing, drops what the schema no longer declares, and clamps the numbers back into range, once,
on the way in.

### `core/tweaks_lookup.gd`

```gdscript
static func find(node)                                  # the Tweaks node, or null
static func cached(node, current)                       # the same, reusing one already found
```

Rule 6 of "Rules every adapter follows", in one place instead of thirteen. Nothing found means the
mod is not mounted yet, and every adapter reads that as "do nothing and let vanilla stand".

`cached()` returns what the caller should store, because a static function cannot write to the
caller's field:

```gdscript
func _tweaks():
    _tweaks_node = TweaksLookup.cached(self, _tweaks_node)
    return _tweaks_node
```

Four adapters use that shape, for two different reasons. `singletons/run_data.gd` and
`global/entity_spawner.gd` ask on a hot path, where walking the tree per call is far too much.
`ui/menus/shop/base_shop.gd` asks from `_on_tree_exited()`, where the node has already left the tree
and `find()` cannot answer at all — so it looks `Tweaks` up while the screen is being built and keeps
it for the one call that comes after.

The adapters reach this by `preload()` of an absolute `res://mods-unpacked/…` path, which is the
same shape `ui/options_tab.gd` is loaded by. It is a *mod* path, so rule 5 — never preload a vanilla
path — is untouched. It is also why `tests/run_extensions.sh` stages `core/` back into the
decompiled tree for its second pass: a preload is resolved at parse time, and without the file there
every adapter fails to compile for a reason that has nothing to do with vanilla.

### `core/loadout.gd`

```gdscript
static func free_slots(limit: int, held: int) -> int
static func excess(limit: int, held: int) -> int
static func remaining_bans(allowance: int, spent: int) -> int
static func spent_bans(allowance: int, remaining: int) -> int
static func apply_ban_tokens(players_data: Array, player_count: int, allowance: int) -> int
```

The arithmetic behind the two tweaks that change what a player carries into a run. Nothing here is
negative: over the limit is "no slots free", not "minus two", and an allowance lowered below what
has already been spent is no tokens rather than a negative count.

`apply_ban_tokens()` is the one that writes, because there is nowhere else the count could live —
the game keeps it on `PlayerRunData` and decrements it as bans are spent. It writes three fields by
name on whatever it is handed and skips anything that does not have them, and it sets the allowance
as "allowance minus already spent" so calling it twice is the same as calling it once.

### `core/recycling.gd`

```gdscript
static func price_factor(specific_items_price: Array, item_id: String, id_names: Dictionary) -> float
```

The one part of vanilla's recycle price that is arithmetic rather than a service call: the
`specific_items_price` player effect is a list of `[item id hash, factor]` pairs, and vanilla folds
in the first factor whose *name* is a substring of the item's own id. `id_names` is
`Keys.hash_to_string`, passed in so this names no game singleton.

It is asked twice per recycle — once for the button's label, once for the payout — which is what
makes the number on the button the number you get. `1.0` for an empty effect, a malformed pair or an
id this version of the game does not know.

### `core/item_limits.gd`

```gdscript
static func lifted(max_nb: int, lift_limited: bool, lift_unique: bool) -> bool
```

One integer read four ways. `ItemData.max_nb` is `-1` for no cap, `0` for an item the game never
offers, `1` for a unique and anything higher for a limited item, and the two switches are separate
because three Wheelbarrows and three of a unique are different runs.

`0` is deliberately not liftable — see [00 — Research](00-research.md#3bc-the-item-limits).

### `core/curse.gd`

```gdscript
static func dlc_data()                                  # the DLC resource, or null
static func available() -> bool
static func curse(data, player_index: int)              # never null; the argument when it cannot
static func recurse(data, base, rolled)                 # never null; the argument when it cannot

static func can_curse_enemy(enemy) -> bool
static func enemy_is_cursed(enemy) -> bool
static func curse_enemy(enemy, behavior, curse_value: float) -> bool
```

Calls the DLC's own `curse_item()`, so a cursed item made here is indistinguishable from one the
DLC made — including the curse it charges you. Never curses an already cursed item or a
`CharacterData`. Returns its argument unchanged whenever the DLC is absent, which is the whole of
"this does nothing without Abyssal Terrors".

`recurse()` is the same method used against its own guard. A cursed item can never be handed to
`curse_item()` twice, so a cursed item locked in the shop keeps the roll it was given for the rest
of the run. Re-rolling means putting the **original** back through the game's own offer roll —
`base` is that original and `rolled` is what came back, both supplied by the adapter, so this file
names no item catalogue and holds no chance of its own. **There is deliberately no separate recurse
chance:** the roll the adapter makes is `ItemService.apply_item_effect_modifications()`, the natural
curse chance with All Cursed already on top of it, so a locked item is re-cursed exactly as often as
a new one of its kind arrives cursed.

That leaves this function two rules. A roll that came back cursed replaces the slot; a roll that
missed leaves the curse the slot already had, because an item cannot lose a curse by being offered
one. And `rolled == base` is refused, because a miss hands the original straight back and the slot
would then hold the catalogue resource every later roll of that item duplicates from.

It is pure, unlike the rest of the file — the DLC is on the far side of a roll the adapter already
made — so `tests/run.sh` drives all of it.

The enemy half is the same idea against a method that cannot be extended: `behavior` is the DLC's
`CurseSceneEffectBehavior`, found by the adapter off the spawner's connection list, and
`curse_enemy()` calls the same `_curse_enemy()` the DLC calls on its own roll. Null `behavior`
means the DLC is not active and nothing happens. `enemy_is_cursed()` matches on the script *path*
of the enemy's effect behaviours rather than on the class, because `CurseEnemyEffectBehavior` is a
DLC `class_name` and naming it would make this file fail to parse without the DLC installed.

### `tweaks.gd` — what the adapters actually call

```gdscript
func feature_enabled(feature: String) -> bool
func disable_feature(feature: String, reason: String) -> void

func inject_hordes(wave_data, horde_groups: Array, current_wave: int) -> void
func scale_wave(wave_data, enemy_type: int) -> void
func scale_wave_duration(wave_data) -> void
func scale_enemy_health(value: float) -> int
func scale_enemy_damage(value: float) -> int
func scale_enemy_speed(value: float) -> int
func elite_schedule_args(base_wave: int, horde_chance: float) -> Dictionary
func curse_data(data, player_index: int, is_weapon: bool)
func cursed_enemy_chance() -> float                     # 0 when the tweak is off
func curse_enemy(enemy, behavior, curse_value: float) -> void

func recurse_locked_items() -> bool
func recurse_locked(data, base, rolled)                 # never null
func report_recursed(item_id: String) -> void

func item_limit_lifted(max_nb: int) -> bool

func ban_allowance() -> int                             # -1 when the tweak is off
func apply_ban_tokens(players_data: Array, player_count: int) -> void
func bans_cover_weapons() -> bool
func ban_label_counts(remaining: int) -> Dictionary     # {apply, spent, allowance}

func recycle_items() -> bool
func recycle_price_factor(prices: Array, item_id: String, id_names: Dictionary) -> float
func report_item_recycled(item_id: String, value: int) -> void

func weapon_limit() -> int                              # -1 when the tweak is off
func free_weapon_slots(held: int) -> int                # -1 when the tweak is off
func weapon_overflow(held: int) -> int                  # 0 when the tweak is off

func keep_harvesting() -> bool
func report_harvesting_kept(value: int) -> void
func keep_piggy_bank() -> bool
func report_piggy_bank(player_index: int, value: int) -> void

func get_setting(key: String, default = null)          # these six are core/settings_store.gd
func get_settings() -> Dictionary                      # answering; see below
func set_setting(key: String, value) -> void
func reset_to_defaults() -> void
func get_schema_properties() -> Dictionary
func schema_description() -> String
signal settings_changed(settings)
```

Death Guard has no entry of its own: unlimited restarts mean the adapter needs nothing but
`feature_enabled("death_guard")`. `curse_data()` never returns null, so its result can go
straight into a typed vanilla parameter, and it is called from two seams — the roll and the
pickup — because neither covers the other.

The two `keep_*` answers are bare on/off, and that is deliberate: "is the run past wave 20" is
`RunData.current_wave > RunData.nb_of_waves`, two of RunData's own fields, and both adapters are
already holding them. Asking `Tweaks` would mean naming a game singleton in the one file that
names none. The `report_*` pair is the same shape as `report_bonus_spawns()` — said by the adapter
after it has acted, so there is nothing in `tweaks.gd` to get out of step.

`-1` is the answer for "the tweak is off" wherever the question is a number the game already has
one of. An adapter that gets it calls the vanilla method it was wrapping and leaves the vanilla
value alone, rather than substituting a default of its own — which is what makes turning the weapon
limit off mid-run give the character's real slot count back, untouched.

**The last six are delegated.** `tweaks.gd` answers questions about the game; where a value is kept,
which ModLoader config it came out of and when it reaches disk are `core/settings_store.gd`'s, and
the adapters and the settings screen are not told the difference. What stays here is the part that
needs `feature_enabled()`: the store says *what changed*, and `tweaks.gd` writes the summary line,
because only it knows which features are on and which have switched themselves off.

## Extension points

| Adapter | Vanilla script | What it does |
|---|---|---|
| `global/entity_spawner.gd` | the spawner | Wraps `init()`. Calls vanilla first — it spawns the players and wires their weapons — then injects hordes and hands the wave to `Tweaks.scale_wave()`, in that order. This is the one moment the whole wave is assembled and nothing has spawned. `init()` also connects the adapter to `enemy_respawned` for cursed enemies: it is the same signal the DLC rolls its own curse on, and connecting from here is always *after* the DLC did, so an enemy it already cursed arrives recognisably cursed. Also wraps `_physics_process()` for the spawn queue's drain rate: vanilla runs first and untouched, then the adapter adds `Tweaks.enemy_spawn_extra()` more `spawn()` calls. It recognises the tick vanilla spawned on by `cur_spawn_delay == 0` — vanilla resets it in that branch and nowhere else — so on the two frames in three where nothing spawned this is one integer comparison, and nothing vanilla decides is reimplemented. |
| `singletons/entity_service.gd` | enemy stat resolution | Wraps `get_final_enemy_damage/health/speed()` and scales what they returned. Not the cached factor inside them, which would not take effect until the next `reset_cache()`. |
| `singletons/item_service.gd` | the item roll | Wraps `apply_item_effect_modifications()`, the last thing every rolled item passes through and where vanilla itself rolls the natural curse chance. Cursing here is what makes a shop card show the curse it is selling. Also wraps `get_limited_items()`, which is the whole of the game's per-item cap — two callers, and both of them use its answer to drop items from a pool — and removes the entries whose cap the player lifted. Nothing is added to the answer; one is left out of it. |
| `main.gd` | the run scene's root | The Piggy Bank past wave 20. Wraps `_on_EntitySpawner_players_spawned()`, the one place `gain_pct_gold_start_wave` is paid, and then — only past `nb_of_waves`, and only for a positive rate, which is the Piggy Bank and nothing else — runs the two lines vanilla skipped: the same effect read, the same `add_gold()`, the same tracked value. Vanilla's branch and this one are mutually exclusive by wave, so a wave is never paid twice. The vanilla script carries `class_name Main`, so this binds by path and declares none; both handlers it can reach are resolved by name, one from `main.tscn` and one from `main.gd::_ready()`. Every local is annotated rather than inferred — see the note at the top of the file. |
| `singletons/run_data.gd` | run state | Six tweaks, because RunData holds all six answers. Wraps `add_item()`/`add_weapon()`, cursing the argument on the way past — `add_weapon()`'s return value goes straight back to the caller, which keeps the instance — and `init_elites_spawn()`, rewriting only its two arguments and only on the run-start call. Wraps `reset()` for the ban allowance and `get_player_banned_items()` so a banned weapon is in the list and the count. Answers the three weapon-slot reads with the limit, capping `weapon_slot_upgrades` with it, and trims a loadout that starts over the limit in `add_starting_items_and_weapons()`. Wraps `remove_stat()` for the endless harvesting decay: past `nb_of_waves`, a removal naming `stat_harvesting` is the decay and nothing else in the game, so the call is skipped rather than undone — `FloatingTextManager` listens to `stat_removed` *and* `stat_added`, so undoing it would print the loss and the refund one after the other. Wraps `get_remaining_max_nb_item()` for the item limits' other half — the same cap, read for how many clones a duplicating item may still make. |
| `zones/wave_manager.gd` | the wave's group list | Wraps `init()` and appends one elite group and one boss group to what vanilla just finished assembling — which is what makes them bonus spawns rather than a reschedule. The two groups are built by vanilla's own `init_elite_group()` and `create_boss_wave_unit_data()`, out of the exported `elite_group` resource this node was built with, so the mod names no elite, no boss and no scene. It runs before `EntitySpawner.init()`, so the enemy multiplier sees these groups — and skips them, because they are `is_boss`. |
| `singletons/zone_service.gd` | wave loading | Wraps `get_wave_data()` and sets the duration on the fresh duplicate it returns, before `main.gd` reads it for the wave timer. |
| `ui/menus/ingame/retry_wave.gd` | the wave-failed screen | Wraps `show()`. Makes the retry half of the screen visible while the feature is on, and writes the game's own retry line, which vanilla writes only when its own Options toggle is on. Everything behind the confirm button is vanilla's. |
| `ui/menus/ingame/upgrades_ui_player_container.gd` | the item-box panel | Two methods, both additive. `_ready()` — with no base call — shows the ban button on a save that has not completed the ban challenge. `show_item()` rewrites the one label that prints bans as "spent / allowance", because vanilla builds both halves of it out of `RunData.BAN_MAX_TOKEN`. |
| `ui/menus/run/difficulty_selection/difficulty_selection.gd` | the difficulty screen | Wraps `_on_element_pressed()`, the click that starts a run and the second place vanilla hands out ban tokens. Vanilla's own `difficulty_selected` flag, read either side of the call, is what says the run actually started. |
| `ui/menus/shop/item_popup.gd` | the popup beside a weapon or an item in the shop | Recycle items, the button half. `should_show_buttons()` is *widened* — vanilla decides first and this adds the item case on top — and `buttons_enabled`, an export only the two shop scenes set, keeps it off every other screen the popup appears on. `_update_button_visibilities()` is the one method here that is replaced rather than wrapped, and only on the branch vanilla never reaches: its next line is `RunData.can_combine(_item_data, …)`, typed `WeaponData`, which cannot be asked about an item. `_on_DiscardButton_pressed()` routes an item to the shop by hand, because the vanilla signal lands on a handler typed `WeaponData` and GDScript rejects an override that widens a parameter — see below. |
| `ui/menus/shop/base_shop.gd` | both shop screens | Two tweaks. **Recurse** wraps `_on_tree_exited()` — vanilla's own Fish Hook pass over the locked slots — and runs its own pass first, over exactly the slots vanilla skips: the ones already cursed. For each it finds the catalogue resource that slot's item was made from, puts it back through `ItemService.apply_item_effect_modifications()`, and asks `Tweaks.recurse_locked()` which of the two to keep. That call is the whole chance: it is the same roll every offered item passes through, and this mod's own extension of it is where All Cursed sits, so nothing here reads `curse_locked_items` or the pity beside it. Running first is what keeps an item vanilla curses on this visit from being re-rolled a line later, and vanilla's `has_cursed_an_item`, its miss count and its pity are neither read nor written. **Recycle items**, the shop half: a new method rather than an override, for the typing reason above, and it is reached off the popup's own connection list the way `entity_spawner.gd` reaches the DLC's curse behaviour. The body is vanilla's weapon recycle line for line against the items half of the gear container, with `is_weapon` false and `RunData.add_recycled()` deliberately not called — that is challenge progress, it goes to the save file, and vanilla's own item-box recycle does not call it either. Two empty hooks either side are what the two screens wrap it with. |
| `ui/menus/shop/shop.gd`, `…/coop_shop.gd` | the two shop screens | The lines vanilla wraps all three of the popup's own buttons with: drop the dimmer behind a focused popup and make the card underneath selectable again, and in co-op put the player's focused popup away. They override the hooks rather than calling `.tweaks_recycle_item()`, so each still compiles on its own against pristine vanilla — which is what `tests/run_extensions.sh` does. |
| `ui/menus/shop/shop_item.gd` | one shop card | Wraps `manage_ban_button_visibility()`, then re-runs the tail vanilla skips for a weapon or an unearned challenge. For an ordinary item on an ordinary save that tail is exactly what vanilla just did, so it changes nothing; the fisherman's bait exception is kept. |
| `ui/menus/title_screen/title_screen.gd` | the title screen | Three lines: hands its `Menus/MenuOptions` to `ui/options_tab.gd`. |
| `ui/menus/ingame/pause_menu.gd` | the pause menu | The same three lines against the same path — it is the same scene. This is the one that matters, because a dial is wanted between waves. |

Rules every adapter follows:

1. Call the vanilla method — first for setup-style methods, last for teardown-style ones. Never
   reorder what it does. There is exactly one place the vanilla call is skipped rather than
   wrapped, and it is the whole point of that tweak: `RunData.remove_stat()` is *how* the endless
   harvesting decay happens, so stopping the decay means not making the call. It is guarded down
   to the one stat and the one wave range that can only be the decay, and everything else reaches
   vanilla untouched.
2. Never override `_ready()` *with a base call*. Godot calls every `_ready()` in a script chain,
   base first, so an extension's own `_ready()` is a safe place to add to what vanilla has already
   built — the two menu adapters and `base_shop.gd` do exactly that — and a `._ready()` inside it
   would run vanilla's twice. Where the answer can change after the screen is built, hook the method
   that runs each time instead: `retry_wave.gd` hooks `show()`.

   `base_shop.gd`'s is there for a different reason: it does not add to the screen, it finds the
   `Tweaks` node while there is still a tree to find it in. Recurse acts from `_on_tree_exited()`,
   which runs *after* the node has left the tree — `get_tree()` is null there, and every other
   adapter's group lookup would answer "the mod is not mounted".
3. Guard every lookup: `is_instance_valid(node)`, `"field" in object`, `found.empty()`.
4. Only ever *add* an option. The retry adapter makes a hidden container visible; it never hides
   the vanilla prompt, so a player who turned the vanilla retry on themselves keeps it.
5. No `preload()` of vanilla paths, ever — it silently defeats extensions.
6. Reach `Tweaks` through `core/tweaks_lookup.gd` — the group, never a node path. Nothing found
   means the mod is not mounted yet, and the adapter does nothing. `find()` for most; `cached()`
   for the four that ask on a hot path or after leaving the tree.

## Settings

Declared in `manifest.json` as `extra.godot.config_schema`. That schema is the one place a setting
is declared: the mod's own settings tab builds itself from it, ModLoader validates every save
against it, and [Brotato Mod Options](https://github.com/BrotatoMods/Brotato-Mod-Options) renders
it too if installed.

| Key | Type | Default | Effect |
|---|---|---|---|
| `enemies_enabled` | bool | `false` | Enemy multiplier on |
| `enemies_multiplier` | number | `2` | How many times the vanilla enemy count (1–10) |
| `enemies_raise_cap` | bool | `true` | Scale `WaveData.max_enemies` too, so the extra enemies are not culled |
| `enemies_fast_spawn` | bool | `true` | Drain the spawn queue by the same multiplier, so the extra enemies actually arrive |
| `enemy_stats_enabled` | bool | `false` | Enemy health/damage/speed dials on |
| `enemy_health_multiplier` | number | `1` | 0.1–5. Floors at 1 HP |
| `enemy_damage_multiplier` | number | `1` | 0.1–5. Floors at 1 damage, because the game does |
| `enemy_speed_multiplier` | number | `1` | 0–5. 0 leaves them standing still |
| `horde_every_wave_enabled` | bool | `false` | Add the zone's horde groups to every wave |
| `elites_enabled` | bool | `false` | Reschedule elites and hordes |
| `elites_first_wave` | number | `11` | 1–50. The wave the first elite lands on; 11 matches vanilla |
| `elites_horde_chance` | number | `40` | 0–100 percent |
| `bonus_elites_enabled` | bool | `false` | Add elites to every wave, from wave 1, on top of what it already spawns |
| `bonus_elites_count` | number | `1` | 1–10 per wave |
| `bonus_bosses_enabled` | bool | `false` | The same for the zone's bosses, at full health |
| `bonus_bosses_count` | number | `1` | 1–10 per wave |
| `wave_duration_enabled` | bool | `false` | Change how long waves last |
| `wave_duration_multiplier` | number | `1` | 0.25–3, floored at 10 seconds |
| `death_guard_enabled` | bool | `false` | Offer a wave restart when every player dies; unlimited |
| `cursed_enabled` | bool | `false` | Curse what you pick up. Needs Abyssal Terrors |
| `cursed_items` | bool | `true` | Include items |
| `cursed_weapons` | bool | `true` | Include weapons |
| `cursed_enemy_chance` | number | `0` | 0–100 percent, rolled on top of the one the Curse stat already gets. `0` leaves the game's own rate alone |
| `recurse_enabled` | bool | `false` | Re-roll the curse on a cursed item locked in the shop, when the shop closes, at the chance a newly offered item is cursed at. Needs Abyssal Terrors |
| `unlimited_items_enabled` | bool | `false` | Ignore the cap on items limited to two or more |
| `unlimited_uniques_enabled` | bool | `false` | Ignore the cap on unique items |
| `bans_enabled` | bool | `false` | Set the ban allowance; also turns ban mode on for the run and lifts the challenge in front of it |
| `bans_max` | number | `8` | 0–100 tokens per run; 8 matches vanilla. Applies from the next run |
| `bans_weapons` | bool | `false` | Put the ban button on shop weapons too |
| `recycle_items_enabled` | bool | `false` | Put the shop's Recycle button on the items you already own. One press, one copy |
| `weapon_limit_enabled` | bool | `false` | Pin how many weapons a player may hold |
| `weapon_limit` | number | `6` | 1–12; 6 matches vanilla. A loadout that starts over it is trimmed from the back |
| `endless_harvesting_enabled` | bool | `false` | Skip the 20%-a-wave Harvesting decay past wave 20 |
| `endless_piggy_bank_enabled` | bool | `false` | Keep the Piggy Bank paying past wave 20 |
| `verbose_log` | bool | `false` | Write what the wave tweaks did, once per wave |

Every tweak is off by default. A fresh install changes nothing about the game.

Number properties carry `multipleOf`, not the non-standard `step`. Two things read it and neither
reads `step`: the JSON schema validator ModLoader runs on every save, and Mod Options, which uses
it for the slider's step size — without it the slider falls back to Godot's default step of `1`,
so a dial declared `0.1`–`5` can only be moved in whole numbers.

### The settings tab

The mod adds a fifth tab — **Tweaks** — beside Audio, Visual, Gameplay and Accessibility, in both
the title screen's Options and the pause menu's. It is the mod's own screen and it needs nothing
installed.

The seam is `UIBetterTabContainer`, the `Buttons` node inside `MenuOptions`, and it is unusually
kind: a tab is a button in the strip, its NodePath in `buttons_tab_np`, the button in `buttons_tab`
and a child of `tab_container` at the same index. Adding all four is a pure append — no vanilla
method is replaced and no scene is edited — and the shoulder-button cycling, the exclusive button
group and the game's theme and focus sounds come with it. See
[00 — Research](00-research.md#4-the-settings-tab) for the source it was read from.

Three files, and only one of them knows anything about the game:

| File | Knows about |
|---|---|
| `extensions/ui/menus/title_screen/title_screen.gd`, `…/ingame/pause_menu.gd` | Where their own Options menu is. Three lines each. |
| `ui/options_tab.gd` | The tab container's node paths and its four arrays. Every failure here disables the tab for the session and leaves the Options menu as vanilla built it. |
| `ui/tweaks_tab.gd` | Nothing. It draws the rows it is handed and emits `setting_changed(key, value)`; the mount wires that to `Tweaks.set_setting()`. |

Details worth keeping:

- **The new tab's index is `buttons_tab_np.size()`**, not a count of the strip's children. Mod
  Options derives its index from `get_child_count() - 2`, which is right only because of where the
  strip's two spacers sit; taking the array's own length is right whatever else has added a tab.
- **The button is duplicated without its signals** (`DUPLICATE_GROUPS | DUPLICATE_SCRIPTS`).
  Godot's default flags include `DUPLICATE_SIGNALS`, and a copy carrying the original's `pressed`
  connection would open the tab it was copied from as well as this one.
- **The tab's layout is copied off the tab already there** — anchors, size flags, focus
  neighbours — so a patch that restyles the Options menu restyles this with it.
- **A section heading is larger than the settings under it, not smaller.** The game's theme draws
  every row title at 40, so the 26 this used to use read as a caption on the row below. It is the
  game's own 60 now, upper case, with space above it and a rule under it — the whole page is
  large horizontal widgets, so one of those signals alone does not register as a break.
- **Programmatic writes are wrapped in `set_block_signals()`.** `apply_settings()` is called from
  the very signal these widgets emit, so a widget that reported the value it was just handed would
  never settle. Blocking is also what keeps a silent write from playing `MyHSlider`'s click.
- **`SliderOption`'s children are `onready`**, so a row is put in the tree *before* anything is
  built into it. Assembling a row and mounting it afterwards yields a row of nulls.
- **A rebuild frees the one node this script added, never "every child".** A `ScrollContainer`
  owns `h_scroll` and `v_scroll`, which it created itself and holds raw pointers to; freeing them
  segfaults the engine on the next layout pass. See the note under "What the tests cover".

### Brotato Mod Options

Mod Options is still supported — the schema is one line of manifest and some players already have
it. It is not enough to be the only settings screen: it never renders `description`, prints every
number as a percentage of 1, labels each widget with the raw key in capitals, cannot group or hide
anything, and crashes on a nested schema object. See
[00 — Research](00-research.md#why-not-brotato-mod-options).

And it renders the schema **but it does not save anything.** Its
`ModsConfigInterface.on_setting_changed()` writes the new value into its own in-memory dictionary,
emits `setting_changed(setting_name, value, mod_name)`, and stops — the write-back to ModLoader is
still a `TODO` in its source. Nothing calls `ModLoaderConfig.update_config()`, and
`current_config_changed` is never emitted, so a mod that listens only for that signal sees a
settings screen that appears to work and changes nothing.

So `Tweaks` connects to `setting_changed` itself and does the saving, through the same
`set_setting()` its own tab uses:

- The node lives at `/root/ModLoader/dami-ModOptions/ModsConfigInterface`, mounted from that mod's
  own `mod_main._ready()`. It is a different, optional mod and load order is the player's to
  change, so `Tweaks` looks the path up once and otherwise waits on `SceneTree.node_added`.
- Only keys already in `settings` are accepted; anything else belongs to another mod or to a
  version this one does not know.
- Saving is debounced by 0.4 s, because a slider drag emits a value per step. The timer is
  `PAUSE_MODE_PROCESS`: the options screen is reached from the pause menu, where an inheriting
  timer would never fire.

## Failure policy

- One guard per adapter entry point. GDScript has no exceptions, so this means explicit validity
  checks plus a flag set on the first unexpected result.
- A feature that fails calls `Tweaks.disable_feature(name, reason)`: it logs one warning, stays
  off for the session, and the others keep running.
- **The mod writes nothing to `ProgressData` or a save file, and writes to `RunData` only where the
  game writes the same field itself.** Twelve of the seventeen tweaks write nothing at all: the three wave
  tweaks rewrite a per-wave `WaveData` copy that is thrown away when the wave ends, and the bonus
  elites and bosses append two groups to that same copy, leaving `RunData.elites_spawn` and
  `RunData.bosses_spawn` exactly as vanilla filled them; the enemy dials
  multiply a returned number and store nothing, not even in the game's own factor cache; the elite
  schedule rewrites two arguments and lets vanilla do its own work; Death Guard only reads
  `RunData.retries`, for the line it shows, and lets vanilla's own confirm button do the writing;
  All Cursed hands a cursed duplicate to the vanilla method and lets it store what it would have
  stored anyway; the two item limits leave one entry out of an answer and write nothing anywhere;
  and stopping the harvesting decay skips a write vanilla was about to make, which
  leaves the stat where it already was.

  The five that do write are the five that have to. Bans set `remaining_ban_token` and `uses_ban`, at
  the two moments and on the two fields vanilla sets them itself. The weapon limit *answers* rather
  than writes — the slot effect underneath it is never touched — with one exception: a run that
  starts over the limit has the weapons past it removed, through the game's own
  `remove_weapon_by_index()`. The Piggy Bank past wave 20 adds materials with the game's own
  `add_gold()`, at the moment and by the sum vanilla itself uses up to wave 20, and touches the
  same tracked-value entry vanilla does. Recycling an item is the game's own `remove_item()` and
  `add_gold()`, in the shop, where the player asked for it — the same two calls vanilla makes to
  recycle a weapon on the same screen, and the same tracked values. Its one omission is on purpose:
  `RunData.add_recycled()` is challenge progress, so it is not called. Recurse replaces
  `RunData.locked_shop_items[i][0]` with a freshly cursed copy — the same field, in the same method,
  that vanilla's own Fish Hook pass writes two lines later. Turning every tweak off returns
  the game to vanilla with no residue, and so does removing the mod mid-run.

  The tempting shortcuts were rejected for this reason: `RunData.current_run_accessibility_settings`
  for the enemy dials and a `number_of_enemies` player effect for the multiplier are both serialized
  into the run state, and each would have left the mod's numbers inside the player's save.
- Its only writes are `user://configs/Brotato-Tweaks/*.json`, through ModLoaderConfig.
- Runs made with a tweak on are not comparable to vanilla ones. The mod does not try to hide that:
  Death Guard deliberately raises the game's own retry counter, which the end-run screen shows.

## What the tests cover

| Harness | Catches |
|---|---|
| `tests/run.sh` | Every mod script outside `extensions/` compiles; the pure cores behave, including the shared-resource case; and the settings tab is built for real against a stub of `slider_option.tscn` and read back — which widget each row reached, that a value reads as the mod formats it rather than as vanilla's percentage, that a sub-option hides with its feature, and that being told a value reports nothing back |
| `tests/run_extensions.sh` | The real ModLoader accepts the manifest and installs all seventeen extensions; every adapter compiles against real vanilla source — which is what fails when a vanilla method is renamed or its signature changes, and what caught the un-inferrable `:=` in `extensions/main.gd` |
| `tests/run_menu.sh` | The real title screen is built against real vanilla, the adapter mounts the tab, and the tab is switched to and left on screen for 40 frames — so the engine actually lays it out |
| `tests/run_baseline.sh` | The three kinds of vanilla change that compile perfectly and are wrong anyway: a default argument on an overridden method, a vanilla method whose logic this mod copies, and a signal looked up by name. Recorded in `tests/vanilla_baseline.json` and re-recorded with `--update` |

The fourth is there because the other three are all, in the end, the compiler. A game where
`RunData.init_elites_spawn()` has a new default, where `ItemPopup._update_button_visibilities()` has
gained a line, and where `enemy_respawned` has been renamed passes `run_extensions.sh` at 17/17 with
the loader reporting success — and plays differently in three ways. `run_baseline.sh` is the harness
that fails on that, and it names the copy and the reason rather than only the file.

What is left to the game itself is a moved node, a scene that no longer has the child an adapter
mounts against, and how a wave actually plays. That is why step 6 of "Adding a tweak" in
[02 — Development setup](02-dev-setup.md) ends with a wave played with the tweak on and a wave
played with it off.

`run_menu.sh` exists because of one bug that got past the other two and crashed the game on the
first click:

> `set_sections()` cleared the tab with `for child in get_children(): child.queue_free()`. A
> `ScrollContainer`'s children are not all the caller's — the engine adds `h_scroll` and `v_scroll`
> in its constructor and keeps raw pointers to them — so that freed the scrollbars and left the
> container dereferencing freed memory on the next layout pass. **A segfault, not an error:** no
> GDScript message, nothing in `modloader.log`, and it lands a frame after the tab first becomes
> visible rather than where the mistake is.

`run.sh` could not see it, because it builds the tab under a bare `Node` that is never laid out;
`run_extensions.sh` could not, because it only compiles. Only a frame could. The rule that came out
of it is in `ui/tweaks_tab.gd`: **free the node this script added, never "every child"** — a Godot
container may own children the script never put there.

The wiring behind the tab is covered by all three; the tab strip, the button, gamepad focus and the
shoulder-button cycling are the game's own widgets, checked by opening Options.
