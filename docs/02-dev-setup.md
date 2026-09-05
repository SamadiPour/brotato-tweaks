# 02 — Development setup

## What you need

| Thing | Why | Default the scripts assume |
|---|---|---|
| Godot **3.x** editor binary | Both test harnesses run headless under it. The game is Godot 3.7; Godot 4 will not parse this code. | `/Applications/Godot3.app/Contents/MacOS/Godot`, override with `GODOT=` |
| A decompiled copy of the game | `tests/run_extensions.sh` compiles the adapters against real vanilla source, and every claim in [00 — Research](00-research.md) was read from it | `~/Dev/BrotatoDecompiled`, override with `BROTATO_SRC=` |
| Brotato itself | Only for actually playing the mod | `~/Documents/Brotato`, override with `BROTATO_DIR=` |

Scripts in the game's PCK are compiled `.gdc` bytecode behind `.gd.remap` files, so reading vanilla
source means decompiling. [GDRE Tools](https://github.com/bruvzg/gdsdecomp) does it:

```console
$ "/Applications/Godot RE Tools.app/Contents/MacOS/Godot RE Tools" --headless \
    --recover="$HOME/Documents/Brotato/Brotato.app/Contents/Resources/Brotato.pck" \
    --output="$HOME/Dev/BrotatoDecompiled"
```

The Abyssal Terrors content is a separate pack and has to be recovered separately if you want to
read `curse_item()` for yourself:

```console
$ "/Applications/Godot RE Tools.app/Contents/MacOS/Godot RE Tools" --headless \
    --recover="$HOME/Documents/Brotato/BrotatoAbyssalTerrors.pck" --output=/tmp/dlc1
$ sed -n '49,80p' /tmp/dlc1/dlcs/dlc_1/dlc_1_data.gd
```

Extensions bind against `res://….gd` paths regardless — the decompiled tree is for reading and for
the test harness, never something the mod ships against.

## The loop

```console
$ tests/run.sh                 # parse + core checks, ~10s
$ tests/run_extensions.sh      # real loader + adapters against real vanilla, ~30s
$ tests/run_menu.sh            # the settings tab, laid out on a real title screen, ~20s
$ tests/run_baseline.sh        # what this mod believes about vanilla, ~15s
$ tools/build.sh --install     # zip it and drop it in the game's mods/ folder
```

Run `run_menu.sh` after anything that touches `ui/`. It is the only harness where the engine lays
the tab out, and a UI mistake in Godot 3 is often a segfault rather than an error — no message, no
stack, and a frame away from the line that caused it.

Run `run_baseline.sh` after decompiling a new version of the game. It is the only harness that fails
on a vanilla change the compiler is happy with — see "When the game updates" below.

Then launch the game and read `~/Library/Application Support/Brotato/logs/modloader.log`. A healthy
start looks like this:

```
INFO ModLoader:ScriptExtension: Installing script extension: res://global/entity_spawner.gd <- …
INFO ModLoader:ScriptExtension: Installing script extension: res://singletons/run_data.gd <- …
INFO ModLoader:ScriptExtension: Installing script extension: res://ui/menus/ingame/retry_wave.gd <- …
INFO ModLoader:ScriptExtension: Installing script extension: res://ui/menus/title_screen/title_screen.gd <- …
SUCCESS ModLoader:Loader: DONE: Installed all script extensions
INFO Brotato-Tweaks: mounted - every tweak is off
```

That last line is the mod's own summary and always names what is on, so it is the first thing to
check when a setting does not seem to be taking effect.

## Errors that are always in the loader pass

`tests/run_extensions.sh` prints four `SCRIPT ERROR` lines from vanilla on every run. None of them
is the mod's, none is fixable from here, and the harness's verdict deliberately ignores them — it
fails on `Parse Error` and `TIMED OUT` only.

| Site | Why |
|---|---|
| `singletons/platforms/gog.gd:21` | `load("res://addons/gog_bindings/gog_bindings.gdns").new()`. GDRE recovers scripts, not native libraries, so the GOG GDNative binary is not in the decompiled tree. The `No valid library handle` line under it is the same cause. |
| `singletons/progress_data.gd:1121` | `get_tree().current_scene.name` |
| `singletons/progress_data.gd:1142` | `get_tree().current_scene.name` |
| `singletons/cursor_manager.gd:27` | `current_scene.has_method(…)` |

The last three are one cause: pass 1 boots with `-s res://tweaks_check.gd`, which is a `SceneTree`
script, so there is no main scene and `current_scene` is null. It cannot be fixed by putting a
scene in place first — autoloads run before `_initialize()` does. `tests/run_menu.sh` is the
harness that boots a real scene, and it is 20s rather than instant for that reason.

Each error is printed with the `at: res://…` line under it, so anything from
`res://mods-unpacked/Brotato-Tweaks/` is the mod's and is a real failure.

## Measuring frame time

The enemy multiplier is the one tweak whose cost is frame rate, and a fresh run is no use for
measuring it. `tools/make_run_save.sh` builds a run save from `tools/lag_build.json` — a deep
endless wave with a heavy build — that the game offers as **Continue run**, landing in the shop for
that wave:

```console
$ tools/make_run_save.sh              # write dist/run_v3_0.json and stop
$ tools/make_run_save.sh --install    # ...and put it in the game's save folder
$ tools/make_run_save.sh --restore    # put the backed-up run save back
$ BUILD=other.json tools/make_run_save.sh
```

It needs the decompiled tree, because the save is written by a headless Godot running the game's
own serialisation rather than by a template that would have to be kept in step with it. Only
`run_v3_<profile>.json` is touched; the progress save beside it — unlocks, challenges, statistics —
is never opened, and an existing run save is moved aside rather than overwritten.

## Working without a decompiled copy

`tests/run.sh` needs nothing but Godot 3 — it runs against the stubs in `tests/godot/stubs/`. It
covers the pure cores and compiles everything except `extensions/`, which is the part that needs
the real game to even load. That is enough for changing scaling rules or the settings layout; it is
not enough for changing an adapter, and `run_baseline.sh` needs the real game by definition.

## When the game updates

Decompile the new version over `$BROTATO_SRC`, then run the harnesses in this order:

```console
$ tests/run_extensions.sh      # a renamed method, a changed signature, a member that is gone
$ tests/run_baseline.sh        # everything that still compiles but is no longer true
$ tests/run_menu.sh            # the Options menu is still the shape the tab mounts into
```

The first is the compiler. The second is the one worth having, because three kinds of breakage
compile perfectly and change how the game plays:

| What moved | What it does with nothing watching |
|---|---|
| A **default argument** on an overridden method | GDScript takes defaults from the most-derived method, so the adapter keeps handing out the old number to every caller that omits it. `RunData.init_elites_spawn(10, 0.4)` is the live example. |
| A **vanilla method this mod copies** | Ten of them, listed in `tests/vanilla_baseline.json` with why each copy exists. The copy still runs; it is just no longer what the game does. |
| A **signal name** looked up by string | `enemy_respawned` and `item_discard_button_pressed`. Not a parse error — a feature that stops happening. |

`run_baseline.sh` names the file, the drift and the reason. Read every failure, fix or re-verify the
copy it points at, bump `compatible_game_version` in `manifest.json`, and only then:

```console
$ tests/run_baseline.sh --update
```

That re-records the file. It refuses to write while it cannot read vanilla at all, so an `--update`
against a half-decompiled tree cannot quietly erase what the mod knows. **`--update` is not a way to
make the test pass** — it is what you run after you have read what it said.

## Adding a tweak

1. Find the seam in decompiled source, and write down what you verified in
   [00 — Research](00-research.md). A seam is a method boundary where wrapping the vanilla call is
   enough — GDScript cannot insert code mid-function, and replacing a whole vanilla method breaks
   every other mod that extends it.
2. Put the decision in `core/` as a pure function if it can be one, and give it checks in
   `tests/godot/core_test.gd`.
3. Add the adapter under `extensions/`, mirroring the vanilla path exactly, and list it in
   `mod_main.gd`. Keep it to: call vanilla, ask `Tweaks`, apply.
4. Add the setting to `manifest.json` (default off) and a `feature_enabled` entry in `tweaks.gd`.
5. Place it on the settings screen: a section in `core/settings_layout.gd`, plus a `PARENTS` entry
   if it is a sub-option of a toggle and a `FORMATS` entry if it is a number. Skipping this is not
   fatal — an unclaimed key is drawn in a trailing section — but it is where it will end up.
6. Run all four harnesses, then play a wave with it on and a wave with it off. `tests/run.sh`
   builds the settings tab headless and `tests/run_menu.sh` puts it on a real screen, so a row that
   is wired wrong fails there rather than in the game. A new adapter method means
   `tests/run_baseline.sh --update`, which is also the moment to ask whether the new code *copies*
   any vanilla logic — if it does, add it to the `bodies` list in `tests/vanilla_baseline.json`
   before running `--update`, with a line saying what was copied and why.

Finish on the tab itself: open Options from the title screen *and* from the pause menu, and cycle
to it with the shoulder buttons as well as the mouse.
