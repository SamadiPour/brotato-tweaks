# 00 — Research: the vanilla facts each tweak stands on

Everything here was read out of decompiled game source, not inferred. Line numbers are from the
decompiled tree described in [02 — Development setup](02-dev-setup.md); paths are `res://` paths.

Verified: 2026-09-04, against **Brotato 1.1.15 (GOG, macOS)** with the **Abyssal Terrors** DLC.

This file covers only what these tweaks need. Two constraints of Brotato modding shape every file
in this repository:

- **Script extensions and runtime node injection are the only mechanisms.** ModLoader 6.3.0 in
  this build has `install_script_extension`, and no `add_hook`, no `extend_scene`.
- **Code cannot be inserted mid-function.** Changing behaviour in the middle of a vanilla method
  means replacing the whole method, which breaks every other mod that extends it. So each tweak
  had to be findable at a seam — a method boundary where wrapping the vanilla call is enough.

---

## 1. Enemy multiplier

### Where the numbers come from

`res://global/entity_spawner.gd`, `on_group_spawn_timing_reached()` — the method the wave manager
calls each time a spawn group's timer comes up:

```gdscript
var max_enemies = int(_current_wave_data.max_enemies + ((RunData.get_player_count() - 1) * (_current_wave_data.max_enemies / 8.0)))

if enemies.size() > max_enemies:
    for i in enemies.size() - max_enemies:
        var en = Utils.get_rand_element(array_from)
        en.can_drop_loot = false
        en.die()
        enemies_removed_for_perf += 1

...
for unit_wave_data in units_data:
    var number: float = Utils.randi_range(unit_wave_data.min_number, unit_wave_data.max_number) as float
    number *= DebugService.nb_enemies_mult

    if unit_wave_data.type == EntityType.ENEMY and not group_data.is_loot:
        number += number * coop_factor
        number = max(1.0, number + number * enemy_modifier)
    elif unit_wave_data.type == EntityType.NEUTRAL:
        number += tree_modifier
```

Three things follow.

**The cap is a performance cull, and it is destructive.** Once more than `max_enemies` are alive,
the spawner picks live enemies at random, sets `can_drop_loot = false` and kills them. Spawning
three times as many enemies into an unchanged cap produces the same crowd on screen plus a lot of
silently deleted ones. That is why "bypass the enemy limit" is not a second feature: it is the
half of this one that makes the other half visible. `WaveData.max_enemies` defaults to 100, and
`ZoneService.get_wave_data()` already scales it itself in endless
(`wave.max_enemies *= 1.25 + (wave_index * 0.01)`), so scaling it is a thing the game does too.

**Vanilla already distinguishes enemies from everything else in a group**, with
`type == EntityType.ENEMY and not group_data.is_loot`. Loot aliens are free items and neutrals are
trees — free materials. Any multiplier that ignores that distinction is an economy mod wearing an
enemy multiplier's name. This mod copies the condition rather than inventing one.

**The queue drains on a fixed budget, and that budget — not the cap — is what limits a high
multiplier.** `res://global/entity_spawner.gd`, `_physics_process()`:

```gdscript
const SPAWN_DELAY = 3
const QUEUE_LIMIT = 100

cur_spawn_delay += 1

if cur_spawn_delay >= SPAWN_DELAY:
    ...
    var nb_to_spawn = 1

    if queue_to_spawn.size() >= QUEUE_LIMIT:
        nb_to_spawn = int(clamp((queue_to_spawn.size() - QUEUE_LIMIT) / 10.0, 1, 2))

    for i in nb_to_spawn:
        spawn(queue_to_spawn)

    cur_spawn_delay = 0
```

`spawn()` pops exactly one entity per call, so this is at most two entities every third physics
frame — **40 a second** at Godot 3's default 60 physics ticks, plus a one-second `EntityBirth`
before each becomes a live enemy. It does not move when `max_enemies` moves and it does not move
when the multiplier does.

Worked through on wave 80 of zone 1, which is where this was first noticed. `get_wave_data()` takes
`wave_index = (80 - 1) % 20 = 19`, so the plan is `wave_20.tres` with `max_enemies` `100 * (1.25 +
0.19)` = **144**, plus `int((80 / 10.0) * 2)` = 16 endless groups; "horde every wave" adds five more
(zone 1's horde groups are `max_wave = 9999`, so all five pass the filter). At 10× the mod lifts the
cap to 1440 and the plan queues several hundred enemies a second — against a drain of 40. The queue
grows for the whole wave, the number alive settles at 40/s times how long an enemy survives, and the
lifted cap is never reached. Reaching 1440 alive would need 36 seconds of killing nothing.

So the cap and the drain are both halves of the same feature, and `enemies_fast_spawn` is the
second one: extra `spawn()` calls appended after vanilla's, on the tick vanilla spawned on.
`cur_spawn_delay` identifies that tick — vanilla sets it back to 0 in that branch and nowhere else.
Wrapping `_physics_process()` rather than replacing it keeps vanilla's counter, its own budget and
the four other queues (trees, bosses, summons, structures and pets) exactly as they were.

**There is a ready-made global multiplier, and it is the wrong one.** `DebugService.nb_enemies_mult`
is applied one line above that check, so it multiplies loot aliens and trees along with enemies. It
is also never reset (it is absent from `DebugService.reset()`), which makes it tempting — one
assignment, no extension. It was rejected for the first reason.

### Where the plan is assembled, and when it is safe to rewrite

`res://main.gd`, `_ready()`:

```gdscript
var current_wave_data = ZoneService.get_wave_data(RunData.current_zone, RunData.current_wave)
...
_wave_manager.init(_wave_timer, current_zone, current_wave_data)     # line 175
...
_entity_spawner.init(zone_min, zone_max, current_wave_data, _wave_timer)   # line 240
```

Both hold the same `WaveData` instance. `WaveManager.init()` is where `groups_data` is finished —
it pushes in the zone's always-groups, extra loot aliens, the boss and elite groups, the horde, and
the DLC's `groups_in_all_zones`. `EntitySpawner.init()` runs afterwards in the same frame, and
`WaveManager._physics_process()` has not yet had a frame in which to emit a spawn. So
`EntitySpawner.init()` is the one moment the whole wave exists and nothing has spawned.

### Why groups are replaced rather than edited

`ZoneService.get_wave_data()` does `zone.waves_data[index - 1].duplicate()`, so the `WaveData` and
its `groups_data` array are per-wave copies — writing `max_enemies` on it is transient and correct.

The groups *inside* that array are not all copies. `WaveManager.init()` duplicates the
always-groups (`group_data.duplicate()`), but pushes these in by reference:

```gdscript
for group_array in wave_data.conditional_groups_data:
    groups_to_add.push_back(Utils.get_rand_element(group_array))
...
for group_data in zone_data.horde_groups:
    groups_to_add.push_back(group_data)
...
for group_in_all_zones in dlc_data.groups_in_all_zones:
    groups_to_add.push_back(group_in_all_zones)
```

Those come straight from resources that live for the whole session. Editing one in place would
compound the multiplier on every later wave and outlive turning the setting off. So the mod
duplicates each group it touches, duplicates the units inside it, and puts the copy in the array
slot. `tests/godot/core_test.gd` has a check named exactly that.

### Field names relied on

| Class | Fields |
|---|---|
| `WaveData` (`res://zones/wave_data.gd`) | `max_enemies`, `groups_data` |
| `WaveGroupData` (`res://zones/wave_group_data.gd`) | `wave_units_data`, `is_boss`, `is_loot`, `is_neutral` |
| `WaveUnitData` (`res://zones/wave_unit_data.gd`) | `type`, `min_number`, `max_number` |
| `EntityType` (`res://entities/entity_type.gd`) | `enum {PLAYER, ENEMY, NEUTRAL, STRUCTURE, BOSS, PET}` |
| `EntitySpawner` (`res://global/entity_spawner.gd`) | `cur_spawn_delay`, `queue_to_spawn`, `_cleaning_up`, `spawn()` — the drain-rate half only |

Every one of the wave fields is checked with `"field" in object` before it is read, and a wave that
does not match reports why and switches the feature off for the session. The `EntitySpawner`
members are not: they are named from inside a script extension of that same class, so a rename
would be a parse error rather than a silent miss — `tests/run_extensions.sh` compiles the adapters
against real vanilla source and fails on exactly that.

---

## 1b. Enemy stat dials

`res://singletons/entity_service.gd` resolves every enemy stat through three functions, and each
one folds the same list of modifiers into a cached factor:

```gdscript
func get_final_enemy_damage(from_value: float, percent_modifier: int = 0) -> int:
    var factor = factor_cache.get(cache_key)
    if factor == null:
        var effects_factor = ...            # items
        var danger_factor = ...             # danger level
        var coop_factor = ...               # player count
        var accessibility_factor = RunData.current_run_accessibility_settings.damage
        var endless_factor = ...
        factor = danger_factor * accessibility_factor * coop_factor * effects_factor * endless_factor
        factor_cache[cache_key] = factor
    return round(from_value * factor * boost_factor) as int
```

Two things this settles.

**The game already has this feature.** `accessibility_factor` is
`ProgressData.settings.enemy_scaling.{health, damage, speed}` — the three sliders in Options →
Accessibility, defaulting to 1.0. So enemy stats are already a number the game expects players to
move, and everything downstream is built for it.

**The dial goes on the return value, not into the factor.** The combined factor is cached per wave
in `factor_cache` and only cleared by `reset_cache()`. A multiplier folded in would be cached with
it and would not take effect until the next clear. On the way out it applies immediately, and
nothing the game caches is touched.

The obvious alternative — writing `RunData.current_run_accessibility_settings` directly — was
rejected. That dictionary is serialized into the run state (`run_data.gd:1735`, restored at
`:1794`) and reported on the end-run screen, so writing it would leave the mod's numbers inside the
player's save.

Speed is worth a note: `get_final_enemy_speed()` is not the only place `accessibility_settings.speed`
is read. `unit.gd`, `pursuer.gd`, `charging_attack_behavior.gd` and `shooting_attack_behavior.gd`
each apply it to their own bonus speeds. So the mod's speed dial scales base movement, and leaves
charge speeds and projectile speeds where vanilla put them. That is a smaller knob than the name
suggests, and it is the right one — scaling projectile speed by the same number would change what
attacks are dodgeable, not how fast enemies walk.

**Damage cannot be dialled to zero.** `res://entities/units/player/player.gd`, `get_damage_value()`:

```gdscript
result.value = max(1, round(dmg_value * armor_coef)) as int if armor_applied else dmg_value
```

Every armoured hit — which is every ordinary enemy hit — is floored at 1 *after* the multiply, well
downstream of `get_final_enemy_damage()`. So a damage multiplier of 0 produces a 0 here and a 1
there: the setting reads as a mode and behaves as a very small number. There is no seam that fixes
this without replacing `get_damage_value()`, which is a whole vanilla method and the wrong trade.
The dial therefore floors at 1 and the schema's `minimum` is 0.1, so the range is the range that
does something. Speed keeps its 0 because vanilla has its own zero-speed flag
(`DebugService.nullify_enemy_speed`) and the movement behaviours already handle it.

---

## 1c. Horde every wave

`ZoneData` (`res://zones/zone_data.gd`) carries `horde_groups`, and `WaveManager.init()` uses them
on a scheduled horde wave:

```gdscript
elif elite_spawn[1] == EliteType.HORDE:
    for group_data in zone_data.horde_groups:
        if RunData.current_wave >= group_data.min_wave and RunData.current_wave <= group_data.max_wave:
            groups_to_add.push_back(group_data)
```

Three facts came out of reading it.

**They are ordinary enemy groups.** `zones/zone_1/000_hordes/group_1.tres` is `is_boss = false`,
`is_loot = false`, `is_neutral = false`, `is_horde = true`, `spawn_edge_of_map = true`,
`repeating = 999` with a shrinking interval. So they can be appended to any wave, and the enemy
multiplier's own rules already treat them correctly.

**The wave-range filter is the zone author's.** `min_wave` / `max_wave` say which hordes make sense
when, and the mod applies the same filter rather than dumping wave-20 hordes into wave 1.

**Vanilla pushes them in by reference**, straight off the zone resource, which is why the mod
appends `duplicate()`s — the same rule as everywhere else in `wave_scaling.gd`.

One consequence worth knowing. A scheduled horde wave also sets `RunData.elites_spawn`, which makes
`RunData.is_elite_wave(EliteType.HORDE)` true, which makes `WaveManager._physics_process()` skip
every group flagged `prevent_if_horde`. The mod sets nothing, so those groups still spawn: an
injected horde is the normal wave **plus** a horde, not instead of it. On a wave the game already
scheduled as a horde the mod injects nothing, so a double horde cannot happen.

---

## 1d. Wave length

`WaveData.wave_duration` (default 60), read once:

```gdscript
# main.gd
var current_wave_data = ZoneService.get_wave_data(RunData.current_zone, RunData.current_wave)  # 153
_wave_timer.wait_time = 1 if RunData.instant_waves else current_wave_data.wave_duration        # 165
_wave_manager.init(_wave_timer, current_zone, current_wave_data)                               # 175
_entity_spawner.init(..., current_wave_data, _wave_timer)                                      # 240
```

Line 165 is why this one cannot share the `EntitySpawner.init()` seam the other wave tweaks use: by
then the timer is already set. `ZoneService.get_wave_data()` is the seam, and it returns
`zone.waves_data[index - 1].duplicate()` — or, in endless, a wave it assembles itself — so writing
to the result is per-wave and thrown away with it.

Group `spawn_timing` is deliberately not rescaled. It is an absolute number of seconds
(`group_data.spawn_timing <= wave_time_elapsed` in `WaveManager._physics_process()`), so a
shortened wave drops the groups timed to arrive late and a lengthened one is carried by the
repeating groups. Rescaling the timings as well would change which enemies a wave is made of, which
is a different feature.

---

## 2. Death Guard

### The game already restarts waves

`res://ui/menus/ingame/retry_wave.gd` is the whole feature, and it is 51 lines:

```gdscript
func _ready() -> void:
    _ok_button.visible = not ProgressData.settings.retry_wave
    _retry_wave_container.visible = ProgressData.settings.retry_wave

func show() -> void:
    .show()
    if ProgressData.settings.retry_wave:
        _label_number_retry.text = Text.text("RETRY_NUMBER", [str(RunData.retries)])
        _confirm_button.grab_focus()
    else:
        _ok_button.grab_focus()

func _on_ConfirmButton_pressed() -> void:
    RunData.reset_to_start_wave_state()
    RunData.retries += 1
    _change_scene(MenuData.game_scene)
```

`res://main.gd`, `_on_EndWaveTimer_timeout()` shows it whatever the setting says:

```gdscript
if _is_wave_failed and RunData.current_wave > 0:
    _retry_wave.show()
    _pause_menu.enabled = false
    return
```

So the Options toggle "Retry wave" decides only *which half of this screen is visible* — the retry
prompt, or a lone OK button that ends the run. The restart itself is always there, and vanilla
offers it without limit.

Death Guard therefore adds no restart logic at all. It makes the retry half visible while the
feature is on. Everything behind the confirm button is vanilla's.

### Why the state is always there

`res://singletons/run_data.gd`:

```gdscript
func on_wave_start(timer: WaveTimer) -> void:
    _reset_per_wave_properties()
    start_wave_state = get_state()      # unconditional, every wave
```

`start_wave_state` is snapshotted on every wave start regardless of the Options setting, and
`_reset_per_wave_properties()` — which clears it — is reached through `RunData.on_wave_end()`,
which `main.gd` calls *after* the `_retry_wave.show()` early return. So forcing the confirm button
on can never hit an empty state.

### Why no counter of the mod's own

```gdscript
var retries := 0                            # run_data.gd:190
retries = 0                                 # run_data.gd:549, on a new run
"retries": retries,                         # run_data.gd:1743, inside get_state()
retries = state.retries                     # run_data.gd:1799, inside resume_from_state()
```

`retries` is already part of the saved run state, incremented by the vanilla confirm button,
carried across a quit and resume, reset with the run, and shown by the end-run screen and the
difficulty score (`Utils` appends `" - R" + str(retries)`). Restarts are unlimited, so the mod
needs no count of its own — it reads that number for the line it draws and writes nothing.

---

## 2b. Elite schedule

`RunData.init_elites_spawn(base_wave := 10, horde_chance := 0.4)` picks the waves a run's elites
arrive on:

```gdscript
if diff < 2:      return
elif diff < 4:    nb_elites = 1
else:             nb_elites = 3

var wave = Utils.randi_range(base_wave + 1, base_wave + 2)
for i in nb_elites:
    var type = EliteType.HORDE if Utils.get_chance_success(horde_chance) else EliteType.ELITE
    if i == 1:    wave = Utils.randi_range(base_wave + 4, base_wave + 5)
    elif i == 2:  wave = Utils.randi_range(base_wave + 7, base_wave + 8); type = EliteType.ELITE
    ...
    elites_spawn.push_back([wave, type, elite_id])
check_elite_generation.append(base_wave)
```

Everything interesting is already parameterised, so the mod rewrites the two arguments and touches
nothing else. How many elites you get stays a function of difficulty; which elites stays
`ItemService.get_elites_from_zone()`; and two characters override `horde_chance` themselves inside
the function (`character_jack` and `character_gangster` force 0, solo `character_ogre` forces 1),
which the mod does not attempt to fight.

**The trap is the caller list.** There are three, and they are not the same call:

```
run_data.gd:541               init_elites_spawn()                         # run start
difficulty_selection.gd:99    init_elites_spawn()                         # pre-run preview
main.gd:974                   init_elites_spawn(current_wave + 10, 0.0)   # endless top-up
```

The endless one passes an *absolute* wave derived from where the run currently is. Overriding it
with a fixed number would schedule endless elites at a wave already in the past, and they would
never spawn — a bug that first shows up an hour into a run. So the override applies only when the
call used both vanilla defaults, which is exactly the run-start call.

`check_elite_generation.has(base_wave)` is the function's own dedupe, keyed on the argument. Since
the mod substitutes the same value for both default calls, the preview and the run start still
dedupe against each other the way vanilla intends.

---

## 2c. Bonus elites and bonus bosses

The tweak above moves vanilla's timetable. This one ignores it: a fixed number of elites, and a
fixed number of bosses, added to **every** wave from wave 1, on top of whatever that wave already
spawns. No chance, no schedule, no difficulty gate — which is exactly why it cannot go through
`init_elites_spawn()`, whose whole output is a list of `[wave, type, elite_id]` triples that
`WaveManager` then matches one wave against.

### An elite is not a scene, it is a group vanilla builds

`res://zones/wave_manager.gd`, and both builders are already public:

```gdscript
export (Resource) var elite_group          # res://zones/common/elite/group_elite.tres

func init_elite_group(elites_to_spawn: Array = [], add_endless_elites: bool = true) -> WaveGroupData:
    var local_elite_group = elite_group.duplicate()
    if add_endless_elites:
        elites_to_spawn.append_array(RunData.get_additional_elites_endless())
    for elite_to_spawn in elites_to_spawn:
        for elite in ItemService.elites:
            assert (elite_to_spawn is int)
            if elite_to_spawn == elite.my_id_hash:
                var unit = WaveUnitData.new()
                unit.type = EntityType.BOSS
                unit.unit_scene = elite.scene
                local_elite_group.wave_units_data.push_back(unit)
    return local_elite_group

func create_boss_wave_unit_data(boss_id: String) -> WaveUnitData:
    var wave_unit_data = WaveUnitData.new()
    var boss = ItemService.get_element(ItemService.bosses, Keys.generate_hash(boss_id))
    wave_unit_data.type = EntityType.BOSS
    wave_unit_data.unit_scene = boss.scene
    return wave_unit_data
```

So neither an elite nor a boss is something the mod has to describe. It picks ids and hands them
to vanilla. The two id forms differ and the assert is real: `init_elite_group()` wants
`my_id_hash` **ints**, `create_boss_wave_unit_data()` wants a `my_id` **String**.

`add_endless_elites` is passed as `false`. Vanilla passes true so a run past wave 20 gets one more
elite per ten waves; letting that through here would multiply the player's dial by the wave number.

`group_elite.tres` is `is_boss = true`, `spawn_edge_of_map = true`, `spawn_timing = 1`,
`repeating = -1`. Two of those matter:

- `is_boss` puts the group in `_physics_process()`'s `spawn_start_wave` branch, so it spawns at
  the top of the wave rather than at its `spawn_timing` — which is what "there from the start"
  means, and it is vanilla's own behaviour for elites, not something the mod arranges.
- `repeating = -1` fails `if group_data.repeating > 0`, so the group fires once.

Bonus bosses reuse the same resource — `elite_group.duplicate()` with boss units pushed into it —
because it is the only group vanilla ever spawns a `BOSS` unit from other than the wave's own boss
group, and that one is reserved: `WaveManager.init()` overwrites its `wave_units_data` outright,
from `RunData.bosses_spawn`, on the last wave.

### The seam is `WaveManager.init()`, and it has to be

`Main._ready()` calls `_wave_manager.init()` at line 175 and `_entity_spawner.init()` at line 240.
Both hold the same `WaveData`, so either would do for *appending* — but only inside `WaveManager`
are `elite_group`, `init_elite_group()` and `create_boss_wave_unit_data()` reachable at all, and
copying any of them into the mod would be copying vanilla content rather than calling it.

Appending after `.init()` is what makes these bonus spawns: vanilla has by then pushed in the
always-groups, the extra loot aliens, the last wave's boss group, the scheduled elite or horde and
the DLC's `groups_in_all_zones`, and none of it is touched.

The order against the enemy multiplier is settled by the same two line numbers: the multiplier runs
later, sees these groups, and skips them — `wave_scaling.gd` scales only `EntityType.ENEMY` units
and never an `is_boss` group. The dials do not multiply each other.

### Which ones, and how many of each

```gdscript
func get_elites_from_zone(zone_id: int) -> Array   # singletons/item_service.gd:871
func get_bosses_from_zone(zone_id: int) -> Array   # singletons/item_service.gd:881
```

Both build and return a **fresh** array, so consuming it is safe — which is what
`init_elites_spawn()` and `get_bosses_to_spawn()` already do (`possible_elites.erase(elite)`) to
avoid picking the same elite twice. That rule only has to hold up to three there. The mod's dial
goes to ten and no zone has ten elites, so it refills: every distinct member is picked once before
any is picked twice. See `core/bonus_spawns.gd`.

### The one interaction, and it is on the last wave

`res://main.gd`, `_on_enemy_died()`:

```gdscript
if enemy is Boss:
    if _entity_spawner.get_nb_bosses_and_elites_alive() <= 1 and RunData.current_wave == RunData.nb_of_waves:
        ...
        _wave_timer.wait_time = 0.1
        _wave_timer.start()
```

`get_nb_bosses_and_elites_alive()` returns `bosses.size()`, and `EntitySpawner.spawn_entity()`
pushes **every** `EntityType.BOSS` entity into that array — elites included. So bonus spawns on
wave 20 have to be dead before the wave ends early. That is vanilla's rule for its own double
boss, applied to more of them, and it is the reason the setting says so.

Nothing is written. `RunData.bosses_spawn` and `RunData.elites_spawn` are both left exactly as
vanilla filled them; the groups are appended to the per-wave `WaveData` copy that
`ZoneService.get_wave_data()` hands out and that is thrown away when the wave ends.

---

## 3. All Cursed

### The curse is the DLC's, and it is one method

`res://dlcs/dlc_1/dlc_1_data.gd` — the Abyssal Terrors DLC resource:

```gdscript
func curse_item(item_data: ItemParentData, player_index: int,
                turn_randomization_off: bool = false, min_modifier: float = 0.0) -> ItemParentData:
    if item_data.is_cursed:
        return item_data
    ...
    new_item_data.effects = new_effects
    new_item_data.is_cursed = true
    new_item_data.curse_factor = max_effect_modifier
    return new_item_data as ItemParentData
```

It duplicates the item, boosts every effect it has a rule for — 300-odd lines of per-item special
cases — adds the `stat_curse` the item is worth (`curse_per_item_value * item_data.value`, unless
the item already carried a curse effect), and returns the copy. It early-returns on an already
cursed item, and it never mutates its argument.

Vanilla calls it from `BaseShop` (locked items, weapon combining), from `RunData` (cursed starting
gear), from `DebugService`, and from its own `update_item_effects()` — the natural drop roll, whose
chance comes from the player's `stat_curse` through `Utils.get_curse_factor()`. The two-argument
form this mod uses is the one `DebugService` uses.

Without the DLC there is no `curse_item` and no curse system: `ProgressData.is_dlc_available_and_active("abyssal_terrors")`
is the check vanilla itself makes before every call, and the mod makes the same one.

### Why acquisition is not enough on its own

`res://ui/menus/shop/base_shop.gd`, `buy_item()`:

```gdscript
RunData.add_item(item_data, player_index)
...
player_gear_container.items_container._elements.add_element(item_data, true)
```

and `buy_weapon()`:

```gdscript
player_gear_container.weapons_container._elements.add_element(item_data)
...
var _weapon = RunData.add_weapon(item_data, player_index)
```

Both pass the shop's own `item_data` to the gear container, not whatever `add_item()` stored. So a
curse applied *inside* `RunData.add_item()` reaches the run and misses everything the player has
already read: the shop card was drawn from the uncursed resource, so no curse icon, vanilla stat
numbers, and no sign of the `stat_curse` the purchase is about to charge. The curse only appears
once the item is in the inventory — which is exactly the "it curses it after I get it" symptom.

### The roll seam, which is where vanilla curses too

`res://singletons/item_service.gd`:

```gdscript
func apply_item_effect_modifications(item: ItemParentData, player_index: int) -> ItemParentData:
	for dlc_id in RunData.enabled_dlcs:
		var dlc_data = ProgressData.get_dlc_data(dlc_id)
		if dlc_data:
			item = dlc_data.update_item_effects(item, player_index)
	return item
```

and Abyssal Terrors' `update_item_effects()` is a chance check around the same `curse_item()`:

```gdscript
var curse_chance = max(0, Utils.get_max_capped_stat(Keys.stat_curse_hash, player_index)) as int
var drop_chance: float = Utils.get_curse_factor(max(base_item_curse_chance * 100.0, curse_chance), max_curse_item_chance * 100.0) / 100.0
return curse_item(item_data, player_index) if Utils.get_chance_success(drop_chance) else item_data
```

So this is the game's own "should this offer be cursed" decision point, and All Cursed is the same
decision with the chance removed. It is reached from two places, which between them are every item
the game offers:

```
item_service.gd:262   apply_item_effect_modifications(get_element(...))   # a guaranteed shop item
item_service.gd:477   return apply_item_effect_modifications(elt, ...)    # the end of _get_rand_item_for_wave
```

and `_get_rand_item_for_wave()` is what `get_player_shop_items()` (the four shop slots and every
reroll), `process_item_box()` (a crate) and `get_rand_item_for_wave()` (a treasure map's extra
item) all call. Everything they return is drawn from the cursed copy, so the card, the crate popup
and the price the player reads all agree with what is bought.

Two consequences worth knowing:

- **Cursed shop items survive a quit and resume already.** `BaseShop` serializes `_shop_items`
  through `ProgressData.save_run_state()`, and `ItemParentData.serialize()` carries `is_cursed`,
  `curse_factor` and the effect list, restored by `deserialize_and_merge()`. Vanilla needs that for
  its own natural curse roll, so nothing new is asked of it.
- **A locked shop item stays as it is.** `BaseShop`'s own `curse_locked_items` pass checks
  `is_cursed` before touching a locked item, so an item this mod cursed is skipped there. That is
  the gap [3bb — Recurse](#3bb-recurse) fills.

### Why the pickup hook stays

`res://singletons/run_data.gd`:

```gdscript
func add_item(item: ItemData, player_index: int, is_selection: bool = false) -> void
func add_weapon(weapon: WeaponData, player_index: int, is_selection: bool = false) -> WeaponData
```

Every route into a player's inventory converges on these two — the shop (`BaseShop.buy_item`,
`buy_weapon`), a crate (`Main.on_item_box_take_button_pressed`), a consumable, starting gear
(`RunData.add_starting_items_and_weapons`), the pre-run weapon screen, and anything another mod
adds. The roll seam above covers the first two and nothing else, so this one is what is left:
starting gear, the character-selection weapon, a consumable's item, another mod's. An item the roll
already cursed arrives here cursed and `curse_item()` returns it untouched, so nothing is cursed
twice.

Two things the callers make visible:

- **`add_weapon` returns the weapon it added**, and `BaseShop.buy_weapon` keeps the returned
  instance. The hook has to pass the return value straight back.
- **The character is added as an item.** `res://ui/menus/run/character_selection.gd:436` calls
  `RunData.add_item(character, player_index)` with a `CharacterData`. A cursed character is not a
  thing the game has a concept of, so it is excluded by class.

**Level-up upgrades never reach `add_item()`.** `Main.on_upgrade_selected()` calls
`RunData.apply_item_effects(upgrade_data, ...)` directly, so the sixteen stat upgrades are outside
this hook by construction — worth knowing before someone goes looking for the check that excludes
them.

### Extending an autoload's script

`ItemService` is autoload eleven in `project.godot` and `RunData` is fifteen; `ModLoader` is autoload
six, and installs script extensions from its own `_init()`. So both extensions are in place before
their singletons are instanced. `ItemService` and `RunData` are `.tscn` autoloads, which changes
nothing — the extension binds to the `res://singletons/*.gd` the scene root carries.
`Brotato-BalanceMod` extends game singletons the same way. If that ordering ever changes, this
adapter silently stops applying and nothing else breaks.

---

## 3b. Cursed enemies

### The roll is one DLC method, and it cannot be extended

`res://dlcs/dlc_1/effect_behaviors/scene/curse_scene_effect_behavior.gd` — the DLC's
`CurseSceneEffectBehavior`, mounted per wave — is the whole feature:

```gdscript
func _ready() -> void :
    var _err = _entity_spawner_ref.connect("enemy_respawned", self, "_on_EntitySpawner_enemy_respawned")
    ...

func _on_EntitySpawner_enemy_respawned(enemy: Enemy) -> void :
    if enemy is Boss or enemy.stats in _loot_alien_stats:
        return

    var curse = 0
    var curse_chance = 0.0
    var nb_players = RunData.get_player_count()

    for player_index in nb_players:
        var curse_stat = max(0, Utils.get_max_capped_stat(Keys.stat_curse_hash, player_index)) as int
        var player_curse_stat = curse_stat
        curse += player_curse_stat
        var player_curse_chance = min(1.0, (Utils.get_curse_factor(player_curse_stat) / 100.0 / 2.0) * (1.0 + (RunData.get_endless_factor() / 2.0)))
        curse_chance += player_curse_chance

    if (Utils.get_chance_success(curse_chance / nb_players) or DebugService.always_curse or DebugService.curse_enemy_spawn) and enemy.can_be_cursed:
        _curse_enemy(enemy, curse)
```

Two facts follow, and they point in opposite directions.

**It cannot be extended.** The file lives in `BrotatoAbyssalTerrors.pck`, which
`ProgressData.load_dlc_pcks()` mounts at runtime — long after ModLoader has installed every script
extension from its own `_init()`. There is no `res://dlcs/…` path to bind to when it matters. And
the decision is mid-method anyway, which GDScript cannot reach.

**It does not have to be.** The roll hangs off `EntitySpawner.enemy_respawned`, a vanilla signal
this mod's own adapter already extends the emitter of, and what the roll *calls* is a method on a
node that is, by definition, in that signal's connection list. So the tweak is a second listener
that rolls its own chance and calls the DLC's `_curse_enemy(enemy, curse)` — the same method, with
the same two arguments, producing a cursed enemy that is the DLC's own work.

`_curse_enemy()` is what makes that worth doing: it instances the curse effect behaviour, adds it
under `enemy.effect_behaviors`, and boosts the enemy through `Entity.boost()` with
`hp_boost + min(curse, 300) * 2`, `damage_boost` and `speed_boost` from its own exported fields.
None of that is reimplemented here.

### Finding the behaviour, and the order it runs in

`Main._ready()` mounts the scene effect behaviours before it initialises the spawner:

```gdscript
# main.gd
for effect_behavior_data in EffectBehaviorService.scene_effect_behaviors:
    var effect_behavior: SceneEffectBehavior = effect_behavior_data.scene.instance()
    _effect_behaviors.add_child(effect_behavior.init(_entity_spawner, _wave_manager))

_entity_spawner.init(...)
```

`add_child()` runs `_ready()`, which is where the DLC connects. Anything this mod connects from
`EntitySpawner.init()` is therefore connected *after* it, and Godot calls connections in order — so
by the time the mod's listener sees an enemy, the DLC has already had its roll on it. That is what
makes "do not curse it twice" a check the mod can actually make.

`get_signal_connection_list("enemy_respawned")` is how the behaviour is found: it is a child of a
node in `main.tscn`, and the one certainty about it is that it is on this signal. Vanilla's own
`Main._on_EntitySpawner_enemy_respawned` is in the same list and has no `_curse_enemy`.

### What may be cursed

`enemy.can_be_cursed` is an exported bool on `res://entities/units/enemies/enemy.gd`, default true.
`looter.tscn` and `evil_mob.tscn` set it false — which is the same exclusion the DLC writes as
`enemy.stats in _loot_alien_stats`, from the other side. Bosses never arrive at all:
`enemy_respawned` is emitted only in the `EntityType.ENEMY` branch of `spawn_entity()`; bosses take
the `EntityType.BOSS` branch.

Enemies are pooled. `Entity.free_entity()` clears `_outline_colors` and the enemy's effect
behaviours when one goes back in the pool, so "is this one already cursed" has to be asked of the
enemy as it is now — which is what reading `effect_behaviors`' children does.

---

## 3bb. Recurse

### A curse is a roll, and it is rolled once

`curse_item()` boosts every effect by `_get_cursed_item_effect_modifier()`, and that is not a
constant — `res://dlcs/dlc_1/dlc_1_data.gd`:

```gdscript
func _get_cursed_item_effect_modifier(turn_randomization_off: bool = false, min_modifier: float = 0.0) -> float:
    var random_modifier: = 0 if turn_randomization_off else Utils.randi_range( - cursed_item_random_percent_modifier, cursed_item_random_percent_modifier)
    var wave_basis = 0 if turn_randomization_off else RunData.current_wave
    var percent_modifier: = cursed_item_base_percent_modifier + cursed_item_percent_modifier_increase_each_wave * min(20, (wave_basis - 1)) + random_modifier
    return max(min_modifier, percent_modifier / 100.0)
```

A base, a bump per wave capped at wave 21, and a random swing either side of it — rolled *per
effect*, with the largest of them kept as the item's `curse_factor`. So the same item cursed twice
is two different items, and the one you were offered is one sample of a distribution.

The item you got that sample on is stuck with it, because the method opens with:

```gdscript
if item_data.is_cursed:
    return item_data
```

That guard is what makes this a feature rather than a fix. Re-rolling cannot mean handing the
cursed copy back to `curse_item()` — it means putting the **original** through the roll again.
`ItemService.items` and `ItemService.weapons` hold that original, found by
`get_element(pool, my_id_hash)`, which is the same lookup `get_limited_items()` already uses to turn
a cursed item back into the catalogue one.

Two things make that safe. `curse_item()` duplicates its argument and never mutates it, so handing
it a session-lifetime catalogue resource does not damage the catalogue. And it does not touch
`value`, so the shop price — `ItemService.get_value(wave_value, item_data.value, …)` in
`ShopItem.set_data()` — is the price the slot already had.

### The roll is the game's own, so there is no chance to invent

`ItemService.apply_item_effect_modifications()` is the one call every offered item passes through,
and Abyssal Terrors' `update_item_effects()` is a chance check around `curse_item()` — see
[the roll seam](#the-roll-seam-which-is-where-vanilla-curses-too). It is also the method this mod
already extends for All Cursed. So "re-roll at the same chance a new item is cursed at" is not a
number to reproduce; it is that call, made again on the original:

```gdscript
var rolled = ItemService.apply_item_effect_modifications(base, player_index)
```

One line, and it carries the player's `stat_curse`, the DLC's own caps, and All Cursed on top —
which means that with All Cursed on it never misses, and Recurse re-rolls every locked cursed item
every visit. Nothing in the mod has a second chance to keep in step with the first.

The one rule the caller has to add is what a **miss** means. `update_item_effects()` returns its
argument unchanged when the roll fails, and that argument is the uncursed original — so a miss must
leave the slot alone rather than be written into it. An item cannot lose a curse by being offered
one, and writing `base` into the slot would put the catalogue resource itself in the shop.

### Where a locked item is skipped, and where to stand

`BaseShop._on_tree_exited()`, which is connected in its own `_ready()`
(`self.connect("tree_exited", self, "_on_tree_exited")`, base_shop.gd:37) and is not overridden by
`Shop` or `CoopShop`:

```gdscript
for i in randomized_positions:
    if not locked_items[i][0].is_cursed and Utils.get_chance_success((RunData.players_data[player_index].curse_locked_shop_items_pity + curse_locked_items) / 100.0):
        for dlc_id in RunData.enabled_dlcs:
            var dlc_data = ProgressData.get_dlc_data(dlc_id)
            if dlc_data and dlc_data.has_method("curse_item"):
                has_cursed_an_item = true
                RunData.players_data[player_index].curse_locked_shop_items_pity = 0
                RunData.set_tracked_value(player_index, Keys.item_fish_hook_hash, RunData.players_data[player_index].curse_locked_shop_items_pity)
                locked_items[i][0] = dlc_data.curse_item(locked_items[i][0], player_index)
    elif not locked_items[i][0].is_cursed:
        nb_locked_items_that_didnt_get_cursed += 1
```

This is the Fish Hook, and it identifies the exact set of slots the mod wants: a locked item that is
already cursed matches neither branch — it is not re-rolled, and it does not even feed the pity
counter.

So the mod's pass is the same loop over the slots this one skips, and it runs **first**:

- an item vanilla curses on this visit is not re-rolled a line later, when it is a fresh roll
  already;
- vanilla sees the shop it would have seen either way — a cursed slot is still cursed afterwards,
  so nothing moves between its two branches and `has_cursed_an_item`,
  `nb_locked_items_that_didnt_get_cursed` and the pity are all left to vanilla. The mod reads
  neither `curse_locked_items` nor `curse_locked_shop_items_pity`: this is Fish Hook's seam, not
  Fish Hook's chance.

`locked_items` is `RunData.locked_shop_items[player_index]`, and each entry is `[item_data, wave]` —
the wave it was rolled at, which `ShopItem` prices from. Writing `entry[0]` is what vanilla writes
on the line above, so it is the same mutation on the same array.

---

## 3bc. The item limits

### One field, one reader

`ItemData.max_nb` (`items/global/item_data.gd:4`, `export(int) var max_nb = -1`) is the whole of the
per-item cap: `-1` no cap, `0` never offered, `1` unique, anything higher limited to that many. The
shop card's category line is written from it (`ui/menus/shop/item_description.gd:104` for `UNIQUE`,
`:114` for `LIMITED`), but that is text, not enforcement.

Enforcement is `ItemService.get_limited_items()`:

```gdscript
func get_limited_items(from_items: Array) -> Dictionary:
    var limited_items = {}
    for item in from_items:
        if item.max_nb != - 1:
            if limited_items.has(item.my_id_hash):
                limited_items[item.my_id_hash][1] += 1
            else:
                var non_cursed_item = item
                if item.is_cursed:
                    non_cursed_item = get_element(items, item.my_id_hash)
                limited_items[item.my_id_hash] = [non_cursed_item, 1]
    return limited_items
```

and it has exactly two callers in the whole game:

```
singletons/item_service.gd:446   _get_rand_item_for_wave()          # the shop, crates, treasure map
ui/menus/ingame/upgrades_ui.gd:153  _recheck_extra_items()          # the extra crate item
```

The first drops every returned item from the pool it is about to roll from:

```gdscript
var limited_items = get_limited_items(args.owned_and_shop_items)
for key in limited_items:
    if limited_items[key][1] >= limited_items[key][0].max_nb:
        backup_pool = remove_element_by_id_with_item(backup_pool, limited_items[key][0])
        items_to_remove.push_back(limited_items[key][0])
```

and `_get_rand_item_for_wave()` is what `get_player_shop_items()` (the four slots and every
reroll), `process_item_box()` (a crate) and `get_rand_item_for_wave()` (a treasure map) all call.
So leaving an entry out of what `get_limited_items()` answers lifts the cap everywhere it is
enforced, and nothing has to know which of the three routes an item is being rolled for.

### The second question the cap is asked

`RunData.get_remaining_max_nb_item()`:

```gdscript
func get_remaining_max_nb_item(item_data: ItemData, player_index: int) -> int:
    if item_data.max_nb == - 1:
        return Utils.LARGE_NUMBER
    var existing_item_count: = get_nb_item(item_data.my_id_hash, player_index)
    return max(0, item_data.max_nb - existing_item_count) as int
```

Read by `BaseShop.buy_item()` and `ShopItem.set_data()`, and only for the duplicating items — how
many clones an effect may still make, and the icon that says so. It is the same cap, so it is
lifted with it, and `Utils.LARGE_NUMBER` is used because that is vanilla's own answer for an
uncapped item: every caller stays on a path it already had.

### What is deliberately not touched

`max_nb == 0` is a different thing. `init_unlocked_pool()` filters on it:

```gdscript
if ProgressData.items_unlocked.has(item.my_id_hash) and item.max_nb != 0:
```

so those items are not in any tier pool to begin with — they are a character's own item, or one
that only arrives from an effect. Lifting a cap that was never a cap is not this feature, and it
would mean writing into the pools rather than leaving one answer out.

Nothing gates *buying* a capped item you already hold the maximum of. The only gate is the roll, so
there is no second seam to find.

---

## 3c. Bans

`RunData.BAN_MAX_TOKEN` is `8`, and it is a `const`. It is read in exactly three places:

```gdscript
# singletons/run_data.gd, reset()
for player_index in get_player_count():
    players_data[player_index].uses_ban = RunData.is_ban_mode_active
    players_data[player_index].remaining_ban_token = RunData.BAN_MAX_TOKEN

# ui/menus/run/difficulty_selection/difficulty_selection.gd, _on_element_pressed()
for player_index in range(RunData.get_player_count()):
    var player_run_data = RunData.players_data[player_index]
    player_run_data.uses_ban = RunData.is_ban_mode_active
    player_run_data.remaining_ban_token = RunData.BAN_MAX_TOKEN

# ui/menus/ingame/upgrades_ui_player_container.gd, show_item()
_ban_button_label.text = tr("MENU_BAN") + " (" + str(RunData.BAN_MAX_TOKEN - player_run_data.remaining_ban_token) + "/" + str(RunData.BAN_MAX_TOKEN) + ") ..."
```

So the constant is never consulted while a ban is being spent — it is copied into
`PlayerRunData.remaining_ban_token` at the two moments a run begins, and every later question is
asked of that field. Both writes are in methods a script extension can wrap, which is why the
allowance does not need the constant to change. The third read is a label, and it is the only place
that would print a wrong number afterwards.

`difficulty_selection` writes *after* `RunData.reset()`, so overriding only `reset()` would be
overwritten by the constant one screen later. Its own `difficulty_selected` flag — false on entry,
true on the call that starts the run — is the guard that says which call to act on.

### Ban mode, and the challenge in front of it

Bans are gated twice:

```gdscript
func is_ban_active_in_current_run() -> bool:
    var test = players_data[0].uses_ban
    return test
```

`uses_ban` comes from `RunData.is_ban_mode_active`, which is `ProgressData.settings.ban_mode_toggled`
— the toggle on the character screen. And every ban UI adds
`ChallengeService.is_challenge_completed(ChallengeService.chal_banned_items_hash)` on top, a
progression unlock earned by reaching a difficulty.

### Weapons are already bannable, except in the shop

`ShopItem.manage_ban_button_visibility()` opens with:

```gdscript
if not ChallengeService.is_challenge_completed(ChallengeService.chal_banned_items_hash) or not RunData.is_ban_active_in_current_run() or item_data is WeaponData:
    _ban_button.disable()
    _ban_button.hide()
    return
```

That `item_data is WeaponData` is the only thing standing between the shop and a banned weapon.
Everything past it is type-agnostic:

- `ShopItem.ban_item()` pushes `item_data.my_id_hash` and decrements the token, whatever it is;
- `BaseShop.on_shop_item_banned()` removes the card by `my_id_hash`;
- `ItemService._get_rand_item_for_wave()` drops every banned id from the pool it rolls from —
  `remove_element_by_id()` matches `my_id_hash`, and the weapon pools are keyed by it;
- `Main.on_item_box_ban_button_pressed()` already bans whatever an item box was showing, weapon or
  not, and `UpgradesUIPlayerContainer.show_item()` has no `WeaponData` check at all.

Which fixes the semantics of a weapon ban without inventing them: a banned weapon is that weapon at
that tier, exactly like a banned item is that item. The pools are per tier, so a banned tier-2
weapon does not remove the tier-3 one — the same way banning an item does not ban the item it
upgrades into.

One thing does not follow, and has to be added: `RunData.get_player_banned_items()` resolves each
banned id through `ItemService.is_item_id()` / `get_item_from_id()`, which know items only. A banned
weapon is silently absent from the pause menu's banned list and from `get_used_ban_count()`, which
the end-run screen prints. The ids items cannot claim are looked up in `ItemService.weapons` instead.

---

## 3d. The weapon limit

How many weapons fit is not a constant. It is a player effect:

```gdscript
# singletons/player_run_data.gd
Keys.weapon_slot_hash: 6 if not all_null_values else 0,
```

Characters set it, items add to it, and level-up weapon slot upgrades raise it. Overwriting it
would be a fight with all three, every time one of them recalculates. So the tweak answers the
reads instead, and there are exactly four of them worth knowing about:

```gdscript
# singletons/run_data.gd
func get_free_weapon_slots(player_index: int) -> int:
    var effects: = get_player_effects(player_index)
    return effects[Keys.weapon_slot_hash] - get_player_weapons_ref(player_index).size()

func has_weapon_slot_available(shop_weapon: WeaponData, player_index: int) -> bool:
    ...
    return weapons.size() < effects[Keys.weapon_slot_hash] and nb < min(effects[Keys.weapon_slot_hash], max_slots)

func player_has_weapon_slots(player_index: int) -> bool:
    return get_player_effect(Keys.weapon_slot_hash, player_index) > 0
```

The first two read the effects **dictionary** directly, so overriding `get_player_effect()` does not
reach them and each needs its own override. `player_has_weapon_slots()`, the two UI labels
(`player_gear_container.gd`, `ingame_main_menu.gd`) and `ItemService.get_upgrades()` all go through
`get_player_effect()` and are covered by one.

`has_weapon_slot_available()` is the one that is asked *with* the limit rather than answered from
it. Its body carries rules worth keeping — `no_duplicate_weapons`, and the melee and ranged
sub-limits — and reimplementing a dozen lines to change one number is how a mod ends up out of step
with a patch. Setting the effect to the limit for the length of the vanilla call and putting it back
afterwards keeps all of it.

### The trap: level-up upgrades

```gdscript
# singletons/item_service.gd, get_upgrades()
var weapon_slot_upgrades = RunData.get_player_effect(Keys.weapon_slot_upgrades_hash, player_index)
var current_weapon_slots = RunData.get_player_effect(Keys.weapon_slot_hash, player_index)

if weapon_slot_upgrades > 0 and current_weapon_slots < weapon_slot_upgrades:
    return [weapon_slot_upgrade_data]
```

A character with `weapon_slot_upgrades` set is climbing towards that number, and every level-up is
forced to be a weapon slot upgrade until it gets there. Report a limit below it and that condition
is true forever: every level-up offers the same card, taking it raises an effect the limit answers
over, and nothing else is ever offered again. So `weapon_slot_upgrades` is capped to the limit in
the same override. It is the reason that override exists at all rather than being left to the UI.

### Starting over the limit

`WeaponSelection._on_selections_completed()` adds the weapon the player picked and *then* calls
`RunData.add_starting_items_and_weapons()`, which adds what the character brings of its own
(`Keys.starting_weapon_hash`, and the DLC's `cursed_starting_weapon_hash`). `RunData.reset(true)` —
a run restarted from the end-run screen — does the same two in the same order.

That is the one moment a loadout can begin over the limit, and the order is what makes the fix
obvious: trim from the back and the weapon the player chose is the one that survives.
`remove_weapon_by_index()` is the vanilla removal that takes a position; `remove_weapon()` matches by
weapon and would drop the first equivalent one, which is the wrong one when two are the same.

A hard cap inside `add_weapon()` would have been the obvious alternative and is wrong:
`BaseShop.buy_weapon()` deliberately adds a weapon it has no slot for and then calls
`_combine_weapon()`, which removes two and adds one. Blocking the add would break combining.

---

## 3e. Past wave 20

Two unrelated vanilla rules that share one trigger — `RunData.current_wave > RunData.nb_of_waves` —
and so share a section. `nb_of_waves` is `var nb_of_waves: = 20` in `singletons/run_data.gd:170`
and is never assigned anywhere but `load_state()`, so "past wave 20" is literal.

### The harvesting decay is one line, and one caller

```gdscript
# main.gd, _on_HarvestingTimer_timeout()                                          # 1521
for player_index in RunData.get_player_count():
    var harvesting_stat = Utils.get_stat(Keys.stat_harvesting_hash, player_index)
    if harvesting_stat <= 0:
        continue
    if RunData.current_wave > RunData.nb_of_waves:
        var val = ceil(harvesting_stat * (RunData.ENDLESS_HARVESTING_DECREASE / 100.0))
        RunData.remove_stat(Keys.stat_harvesting_hash, val, player_index)          # 1528
    else:
        ... harvesting_growth, and the Crown's tracked value
```

`ENDLESS_HARVESTING_DECREASE` is `const … = 20` (`run_data.gd:18`), and the two branches are the
whole method. Nothing in the endless branch is reachable from anywhere else, and nothing else in
the game removes `stat_harvesting`, so line 1528 *is* the decay.

That makes `RunData.remove_stat()` the seam rather than the method around it, which matters: the
method is a scene-connected handler on `main.gd`, and there is no way to wrap only the branch. The
grep that has to hold for this to stay narrow is the list of `RunData.remove_stat()` callers —
there are three:

| Caller | Stat |
|---|---|
| `main.gd:1528` | `stat_harvesting` — the decay |
| `run_data.gd:1514` | `stat_max_hp` |
| `utils.gd:618` | whatever a stat conversion names, and only when `permanent` |

`Utils.convert_stats()` is the only one that could ever name harvesting, and the two conversion
effects vanilla ships are the Cyborg's (ranged damage → engineering, `convert_stats_half_wave`,
which is not permanent and so goes to `TempStats.remove_stat()`) and the Demon's (materials → max
HP, and materials go through `remove_gold()`). So skipping harvesting removals past wave 20 skips
the decay and nothing else.

**Skipping, not undoing.** `FloatingTextManager._ready()` connects to both `stat_added` and
`stat_removed`, so restoring the stat after vanilla took it would print "-12 harvesting" and then
"+12 harvesting" over the player, every wave.

**What is deliberately not done.** Routing the endless case into the `else` branch instead would
give harvesting its +5% growth back and re-arm the Crown, and it would need
`RunData.current_wave` to be lied about for the length of the call. That is a second feature with
a second failure mode; the switch stops the decay and no more.

**One cosmetic mismatch, left alone.** `ItemService.get_stat_description_text()` builds the
Harvesting tooltip out of `RunData.nb_of_waves` and `RunData.ENDLESS_HARVESTING_DECREASE`
(`item_service.gd:838`), so it still describes a decay the tweak is skipping. Rewriting a
localised string with four substitutions to fix a tooltip is a worse trade than the mismatch.

### The Piggy Bank is a rate with a wave clause

```gdscript
# main.gd, _on_EntitySpawner_players_spawned()                                     # 1429
var pct_val = RunData.get_player_effect(Keys.gain_pct_gold_start_wave_hash, i)
var apply_pct_gold_wave = (pct_val > 0 and RunData.current_wave <= RunData.nb_of_waves) or pct_val < 0

if pct_val < 0 and RunData.current_wave > RunData.nb_of_waves:
    pct_val = - 100.0

if apply_pct_gold_wave:
    var val = RunData.get_player_gold(i) * (pct_val / 100.0)
    RunData.add_gold(val, i)
    if pct_val > 0:
        RunData.add_tracked_value(i, Keys.item_piggy_bank_hash, val)
```

Two items carry `gain_pct_gold_start_wave` and they are the only two:
`items/all/piggy_bank/piggy_bank_effect_1.tres` at `+20`, and
`items/characters/entrepreneur/entrepreneur_effect_3.tres` at `-100`. So a positive rate is the
Piggy Bank and a negative one is the Entrepreneur, and the wave clause applies to the positive rate
only — vanilla keeps charging the Entrepreneur in endless, at a forced -100%.

The seam is the method, because the clause is a comparison in the middle of a hundred-line one. The
adapter calls vanilla and then, past `nb_of_waves` and for a positive rate only, runs the same two
lines vanilla skipped. The two branches cannot both fire for one wave: vanilla's runs at or below
`nb_of_waves`, the adapter's only above it.

`_on_EntitySpawner_players_spawned()` is connected by name from `main.gd:131` and contains no
`yield`, so an override is what the signal reaches and the base call has finished before the
adapter's own work starts.

### Extending `main.gd`

`main.gd` is the run scene's root script and it declares `class_name Main`, so the extension binds
by path (`extends "res://main.gd"`) and declares no class name of its own. Both methods it
overrides are signal handlers resolved by name — one from `main.tscn`'s connection list, one from
`main.gd::_ready()` — so an override is reached either way.

While the loader installs the extension the parser cannot resolve the base script it is replacing,
and every `:=` in the file becomes `Parse Error: The assigned value doesn't have a set type` in
`modloader.log`. Annotating each local (`var x: float = …`) is the fix; `tests/run_extensions.sh`
fails on those lines, which is how it was found.

### What the endless item ban is not

`ItemService.banned_items_for_endless` looks like it stops the Piggy Bank being *offered* past wave
20, and does not:

```gdscript
var banned_items_for_endless = ["item_piggy_bank", "item_crown"]                  # 87
...
    for item in pool:
        if banned_items_for_endless.has(item.my_id_hash):                          # 443
            items_to_remove.append(item)
```

The array holds strings and `my_id_hash` is an integer, so `has()` is never true. Those two lines
are its only mentions in the game — nothing rewrites the array into hashes. The Piggy Bank is
therefore still on offer in endless in 1.1.15, and the tweak has nothing to undo there.

---

## 3f. Recycle items

Vanilla has three recycles, not one, and only two of them exist:

| Where | Method | What it takes |
|---|---|---|
| A weapon you own, in the shop | `BaseShop._on_item_discard_button_pressed()` | `weapon_data: WeaponData` |
| An item you are being *offered* | `Main.on_item_box_discard_button_pressed()` | `item_data: ItemParentData` |
| An item you already own | — | — |

The third is missing, and it is missing in one line. Both shop inventories — weapons and items —
are the same `Inventory` scene, wired to the same `PopupManager`, showing the same `ItemPopup`. What
decides whether that popup has buttons on it is:

```gdscript
# ui/menus/shop/item_popup.gd
func should_show_buttons(item_data: ItemParentData, focused: bool) -> bool:
    return buttons_enabled and item_data is WeaponData and (not RunData.is_coop_run or focused)
```

`buttons_enabled` is an export, and the only two scenes that set it are `shop.tscn` and
`coop_shop_player_container.tscn` — the two shop screens. So widening that condition to cover an
item is the whole of the feature's visible half, and it cannot leak onto a screen that was never
meant to have the buttons.

### Two things vanilla cannot be asked to do for an item

**`can_combine()` is typed.** The line after the guard above is

```gdscript
_combine_button.visible = RunData.can_combine(_item_data, player_index)
```

and `can_combine(weapon_data: WeaponData, …)` would take the call down with an item in it. So
`_update_button_visibilities()` is the one vanilla method here that is *replaced* rather than
wrapped — for items only, on the branch vanilla never reaches, and with `_combine_button` hidden
because combining is not a thing an item does.

**The signal cannot carry an item.** `item_discard_button_pressed` is connected to
`BaseShop._on_item_discard_button_pressed(weapon_data: WeaponData, …)`, and GDScript will not let a
subclass widen a parameter:

> Parse Error: The function signature doesn't match the parent. Parent signature is:
> `"void _on_item_discard_button_pressed(WeaponData, int)"`.

That is a parse error, not a warning — the extension would fail to compile and ModLoader would
install a broken script. So the shop is reached the way `curse.gd` reaches the DLC's behaviour: off
the popup's own connection list, where the only thing connected to that signal is the shop that
built the popup, and the bind it was connected with is the player index.

### One press is one copy, and the game already does that

Identical items are drawn as a single element with a count on it — `Inventory.set_elements()` folds
them with `get_elements_with_count()`, and cursed ones are deliberately left unfolded. Taking one
off is `remove_element()`:

```gdscript
# ui/menus/shop/inventory.gd
if children[i].current_number > 1:
    children[i].remove_from_number()
else:
    order_of_addition.erase(children[i])
    children[i].queue_free()
```

and `RunData.remove_item()` erases the first match and `break`s. Both halves already remove exactly
one, which is what a stack of identical weapons does in vanilla, so "recycle one of them" is the
behaviour of the vanilla calls rather than something the mod arranges.

### The character is in the item list

```gdscript
# singletons/run_data.gd
func add_character(character: CharacterData, player_index: int) -> void:
    players_data[player_index].current_character = character
    add_item(character, player_index)
```

`CharacterData extends ItemData`, so the character is an ordinary entry in `players_data[i].items`
and an ordinary square in the shop's item panel — `Inventory.set_elements()` even sorts it to the
front. Recycling it would call `unapply_item_effects()` on everything the character is. It is
excluded by type, in the popup and again in the shop.

### What the payout is made of

Vanilla prices a weapon recycle in two steps, and the label and the payout each do both:

```gdscript
var base_recycling_value = weapon_data.value
for specific_item_price in RunData.get_player_effect(Keys.specific_items_price_hash, player_index):
    if Keys.hash_to_string[specific_item_price[0]] in weapon_data.my_id:
        specific_recycling_price_factor = specific_item_price[1]
        break
base_recycling_value *= specific_recycling_price_factor

var recycling_value = ItemService.get_recycling_value(RunData.current_wave, base_recycling_value, player_index, true)
```

`get_recycling_value()` is where Recycling Gains, the items-price stat and the endless factor are
applied, and `is_weapon` is the last thing that changes between a weapon and an item. The substring
loop is the only part that is arithmetic rather than a service call, so it is the part that became
`core/recycling.gd`.

Two pieces of bookkeeping sit either side of it, and only one of them is copied:

- `RunData.update_recycling_tracking_value()` — the Recycling Machine's tracked value. Vanilla runs
  it for the item box recycle too, so an item recycle running it is the existing behaviour.
- `RunData.add_recycled()` — challenge progress, through
  `ChallengeService.try_complete_challenge()`, which is written to the save file. Vanilla's own
  item-box recycle does **not** call it, and this mod writes nothing to `ProgressData`, so it is
  deliberately not called.

---

## 4. The settings tab

Not a tweak — the screen the other tweaks are set from. It is here for the same reason as the rest:
every claim below was read out of vanilla source, and the whole thing stands on them.

### The Options menu is a list of tabs, and the list is a variable

`res://ui/hud/ui_better_tab_container.gd` is the `Buttons` node inside `MenuOptions`, and it is 60
lines:

```gdscript
class_name UIBetterTabContainer
extends Container

export (Array, NodePath) var buttons_tab_np
export (NodePath) var tab_container_np
onready var tab_container: TabContainer = get_node(tab_container_np)
var buttons_tab: Array

func _ready():
    var buttonGroup: ButtonGroup = ButtonGroup.new()
    for i in buttons_tab_np.size():
        var button: Button = get_node(buttons_tab_np[i])
        buttons_tab.append(button)
        button.toggle_mode = true
        button.group = buttonGroup
        button.connect("pressed", self, "_change_tab", [i])
    buttons_tab[0].pressed = true
    _change_tab(0)

func _change_tab(actual_tab: int):
    var button: Button = get_node(buttons_tab_np[actual_tab])
    if button.disabled and not button.pressed: return
    tab_container.current_tab = actual_tab
    if not button.pressed: button.pressed = true
```

A tab is therefore four things, all of them writable at runtime: a `Button` in the strip, its
NodePath appended to `buttons_tab_np`, the button appended to `buttons_tab`, and a child of
`tab_container` at the same index. `_input()` reads the same two arrays for the shoulder-button
cycling, so a tab added this way is cycled to like any other. **No vanilla method is replaced and
no scene is edited** — this is the rare UI change that is pure addition.

`menu_options.tscn` declares the four vanilla tabs:

```
buttons_tab_np = [ NodePath("HBoxContainer2/Audio_but"), NodePath("HBoxContainer2/Visual_but"),
                   NodePath("HBoxContainer2/Gameplay_but"), NodePath("HBoxContainer2/Accessibility_but") ]
tab_container_np = NodePath("HBoxContainer3/TabContainer")
```

and the `TabContainer` sets `tabs_visible = false`, so the child's node name is never drawn — the
strip of buttons above it *is* the tab bar.

### The same scene is reached from two places

```
res://ui/menus/title_screen/title_screen.gd     $Menus/MenuOptions
res://ui/menus/ingame/pause_menu.gd             $Menus/MenuOptions
```

Identical paths into the same scene, which is why one mount function serves both adapters. It is
also why the tab is a tab and not a page of its own on the title screen: **every tweak reads its
setting at the moment it acts**, so the pause menu is where a player actually wants the dials, and
only a tab in `MenuOptions` is reachable from there.

`_ready()` ordering makes the append safe. Godot readies children before parents and calls every
`_ready()` in a script chain base-first, and the `Buttons` node is a descendant of the screen the
adapter extends — so `UIBetterTabContainer._ready()` has already built `buttons_tab` and selected
tab 0 by the time the adapter runs.

### What the tab is built out of

`res://ui/menus/global/slider_option.tscn` is the game's own labelled slider — `Label`, `HSlider`,
`Value`, reached through `onready` vars, so they are null until it is in the tree. Its script is
five lines and one of them is the reason the mod cannot use it as-is:

```gdscript
func _on_HSlider_value_changed(value: float) -> void :
    _value.text = str(value * 100) + "%"
    emit_signal("value_changed", value)
```

That is right for the three audio sliders it was written for and wrong for every dial in this mod:
it renders `2.0` as `200%` and `11` as `1100%`. The connection is made in the `.tscn`
(`HSlider.value_changed -> SliderOption._on_HSlider_value_changed`), so it is disconnected at build
time and the label is written by the mod instead. `MyHSlider`'s own connection to the same signal —
which only plays a click — is left alone.

### Why not Brotato Mod Options

It renders the schema and it is one line of manifest to support, so it stays supported. It is not
enough to be the only answer:

- `flatten_properties()` reads `tooltip` and never `description`, so every description in
  `manifest.json` is invisible on that screen.
- Numbers have no formatting unless the schema carries a `format`, and the fallback is vanilla's
  percentage — see above.
- Widget labels are `config_key.to_upper()`, printed next to the title, so a row reads
  "First elite wave / ELITES_FIRST_WAVE".
- There is no grouping and no conditional visibility: one flat list per mod, in one scroll shared
  with every other mod, with `enemies_multiplier` live while `enemies_enabled` is off.
- Nested schema objects are worse than unsupported. `flatten_properties()` recurses with
  `flatten_properties(value.properties)` — a `Dictionary` into a parameter typed `ModConfig`,
  which is a runtime error.
- It still never saves; see [01 — Architecture](01-architecture.md#brotato-mod-options).

## Surviving a game patch

Everything above is read from one version of the source, and a patch may rename a method, change a
signature or move a node. Three mechanisms carry the mod across that:

1. `tests/run_extensions.sh` compiles every adapter against the real decompiled source, which
   catches a renamed method or a changed signature before the game ever runs it.
2. Every vanilla field is checked with `"field" in object` and every node with
   `is_instance_valid()` before it is touched.
3. A feature that finds something it does not recognise switches *itself* off for the session,
   logs one warning, and leaves the others running. See the failure policy in
   [01 — Architecture](01-architecture.md).
