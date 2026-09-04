#!/usr/bin/env bash
# Packages the mod into dist/Brotato-Tweaks-<version>.zip, ready to drop into Brotato's mods/
# folder. The version comes from manifest.json, so it is bumped in one place.
#
#   ./tools/build.sh                 # build the zip
#   ./tools/build.sh --install       # build it, then copy it into the game's mods/ folder,
#                                    # replacing any older zip of this mod that is there
#
# The game folder defaults to ~/Documents/Brotato and is overridden with BROTATO_DIR.
set -euo pipefail

readonly MOD_ID="Brotato-Tweaks"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MOD_DIR="$REPO_ROOT/root/mods-unpacked/$MOD_ID"
readonly DIST_DIR="$REPO_ROOT/dist"
BROTATO_DIR="${BROTATO_DIR:-$HOME/Documents/Brotato}"

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
	mods_dir="$BROTATO_DIR/mods"
	if [ ! -d "$mods_dir" ]; then
		echo "no mods folder at $mods_dir - set BROTATO_DIR to your game folder" >&2
		exit 1
	fi
	# Two versions of the same mod id in mods/ confuse the loader, so clear the old one first.
	rm -f "$mods_dir/$MOD_ID"-*.zip
	cp "$zip_path" "$mods_dir/"
	echo "installed to $mods_dir/$zip_name"
fi
