#!/bin/sh
# Fetch Void's C dependencies into deps/ at pinned commits.
#
# The pins are the versions Void is built and tested against. sokol moves its
# API often (its CHANGELOG.md gives a migration recipe per break). Bump a pin
# only together with the code change it needs, and regenerate the shader
# headers (scripts/regen-shaders.sh) when sokol-tools-bin moves.
#
# msc caches C objects globally (~/.metascript/cache/objects) keyed by the .c
# file, not the headers it includes, and --force does not bypass it: after a
# pin bump, delete the cached objects that include deps/sokol, or the build
# silently links code compiled against the old headers.
#
# Also needed, as a sibling checkout: ../yoga (github.com/metascriptlang/yoga),
# with libyoga.a built for the target (see its scripts/build-yoga.sh).
set -e
cd "$(dirname "$0")"

SOKOL_REV="2e75443dbd4940b5aa8d76a8e479f8e4b270b9a3"            # 2026-09-14
SOKOL_TOOLS_REV="11d0cf678105d614d675e6d9bd2aaf3eeff12f8c"
STB_REV="2c980bb59875b0d32144a71867fbdebb2f77cd20"
FREETYPE_REV="42608f77f20749dd6ddc9e0536788eaad70ea4b5"      # VER-2-13-3

# Our sokol fork (docs/SOKOL.md): Void-local patches sit on its `void` branch
# until upstream merges them, so a pin may name a commit floooh/sokol lacks.
SOKOL_FORK="${SOKOL_FORK:-$HOME/projects/sokol}"

fetch() {
	name="$1"; repo="$2"; rev="$3"; fork="$4"
	dest="deps/$name"
	if [ ! -d "$dest/.git" ]; then
		echo "cloning $repo"
		git clone -q "https://github.com/$repo.git" "$dest"
	fi
	if [ "$(git -C "$dest" rev-parse HEAD)" != "$rev" ]; then
		git -C "$dest" fetch -q origin
		if [ -n "$fork" ] && ! git -C "$dest" cat-file -e "$rev^{commit}" 2>/dev/null; then
			[ -d "$fork/.git" ] || { echo "$name: $rev is not upstream and fork $fork is missing"; exit 1; }
			git -C "$dest" fetch -q "$fork" void
		fi
		git -C "$dest" checkout -q "$rev"
	fi
	echo "$name @ $(git -C "$dest" rev-parse --short HEAD)"
}

mkdir -p deps
fetch sokol           floooh/sokol           "$SOKOL_REV" "$SOKOL_FORK"
fetch sokol-tools-bin floooh/sokol-tools-bin "$SOKOL_TOOLS_REV"
fetch stb             nothings/stb           "$STB_REV"
# Only P3's rasterizer experiment compiles FreeType (tests/experiments/, docs/VOID2D.md P3).
if [ "${VOID_FREETYPE:-0}" = 1 ]; then
	fetch freetype    freetype/freetype      "$FREETYPE_REV"
fi

echo "--- Setup complete ---"
