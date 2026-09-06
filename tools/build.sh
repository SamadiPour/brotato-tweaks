#!/usr/bin/env bash
# Packages the mod into dist/Brotato-Tweaks-<version>.zip, ready to drop into Brotato's mods/
# folder. The version comes from manifest.json, so it is bumped in one place.
#
#   ./tools/build.sh                 # build the zip
#   ./tools/build.sh --install       # build it, then copy it where this copy of the game reads
#                                    # mods from, replacing any older zip of this mod there
#
# The game folder is the one holding Brotato.app or Brotato.exe — not the .app itself. It is
# looked for in the usual places and overridden with BROTATO_DIR.
set -euo pipefail

readonly MOD_ID="Brotato-Tweaks"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MOD_DIR="$REPO_ROOT/root/mods-unpacked/$MOD_ID"
readonly DIST_DIR="$REPO_ROOT/dist"
readonly STEAM_APP_ID="1942280"
BROTATO_DIR="${BROTATO_DIR:-}"

# Where the game folders usually are, tried in this order when BROTATO_DIR is unset.
readonly GAME_DIR_CANDIDATES=(
	"$HOME/Documents/Brotato"
	"$HOME/Library/Application Support/Steam/steamapps/common/Brotato"
	"$HOME/.steam/steam/steamapps/common/Brotato"
	"$HOME/.local/share/Steam/steamapps/common/Brotato"
	"$HOME/Games/Brotato"
)

# The game itself, rather than a folder that happens to be named after it. macOS ships a bundle,
# the other platforms an executable beside Brotato.pck.
is_game_dir() {
	[ -d "$1/Brotato.app" ] || [ -f "$1/Brotato.exe" ] || [ -f "$1/Brotato.pck" ] || [ -x "$1/Brotato" ]
}

# ModLoader reads mods from beside the executable — internal/path.gd's get_local_folder_dir("mods"),
# which on macOS climbs out of the .app first. Steam builds are the exception: options.tres
# overrides steam_workshop_enabled to true under the `steam` feature tag, and _load_mod_zips() then
# reads *only* steamapps/workshop/content/<app id>, one folder per mod, never mods/.
mods_target_for() {
	local game_dir="${1%/}"
	case "$game_dir" in
		*/steamapps/common/*)
			echo "${game_dir%/steamapps/common/*}/steamapps/workshop/content/$STEAM_APP_ID/$MOD_ID"
			;;
		*)
			echo "$game_dir/mods"
			;;
	esac
}

install_after_build=false
for arg in "$@"; do
	case "$arg" in
		--install) install_after_build=true ;;
		*) echo "usage: $0 [--install]" >&2; exit 2 ;;
	esac
done

# The version is whatever manifest.json says, read without a JSON dependency.
version="$(sed -n 's/.*"version_number"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
	"$MOD_DIR/manifest.json" | head -1)"
if [ -z "$version" ]; then
	echo "could not read version_number from $MOD_DIR/manifest.json" >&2
	exit 1
fi

readonly zip_name="$MOD_ID-$version.zip"
readonly zip_path="$DIST_DIR/$zip_name"

mkdir -p "$DIST_DIR"
rm -f "$zip_path"

# The zip's root must be mods-unpacked/, not the mod folder itself, or ModLoader ignores it.
# The mod ships no assets of its own, so there is no .import/ to carry.
cd "$REPO_ROOT/root"
zip -r -q "$zip_path" mods-unpacked -x '*.DS_Store' '__MACOSX/*'

echo "built dist/$zip_name"
unzip -l "$zip_path" | tail -1

if [ "$install_after_build" = true ]; then
	game_dir="$BROTATO_DIR"
	if [ -n "$game_dir" ]; then
		if ! is_game_dir "$game_dir"; then
			echo "no Brotato.app, Brotato.exe or Brotato.pck in BROTATO_DIR ($game_dir)" >&2
			echo "point BROTATO_DIR at the folder holding the game, not at the .app" >&2
			exit 1
		fi
	else
		for candidate in "${GAME_DIR_CANDIDATES[@]}"; do
			if is_game_dir "$candidate"; then
				game_dir="$candidate"
				break
			fi
		done
		if [ -z "$game_dir" ]; then
			echo "could not find the game - set BROTATO_DIR to the folder holding Brotato.app" >&2
			printf '  looked in: %s\n' "${GAME_DIR_CANDIDATES[@]}" >&2
			exit 1
		fi
	fi

	mods_dir="$(mods_target_for "$game_dir")"
	case "$mods_dir" in
		*/workshop/content/*)
			echo "$game_dir is a Steam copy, which loads mods from the workshop folder only"
			;;
	esac

	# The folder is the game's to read, not to create, so it may well not be there yet - a copy
	# that has never had a mod has no mods/, and a Steam copy with no subscriptions has no
	# workshop folder for the app id.
	mkdir -p "$mods_dir"
	# Two versions of the same mod id confuse the loader, so clear the old one first.
	rm -f "$mods_dir/$MOD_ID"-*.zip
	cp "$zip_path" "$mods_dir/"
	echo "installed to $mods_dir/$zip_name"
fi
