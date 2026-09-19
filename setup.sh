#!/bin/sh
# Fetch Void's C dependencies into deps/ at pinned commits.
#
# The pins are the versions Void is built and tested against. sokol in
# particular moves its API: master after 2026-08 replaced
# sg_buffer_usage.stream_update with write_transient/write_unsealed, which
# void2d/batcher.c still uses. Bump a pin only together with the code change
# it needs, and regenerate the shader headers (scripts/regen-shaders.sh) when
# sokol-tools-bin moves.
#
# Also needed, as a sibling checkout: ../yoga (github.com/metascriptlang/yoga),
# with libyoga.a built for the target (see its scripts/build-yoga.sh).
set -e
cd "$(dirname "$0")"

SOKOL_REV="6c3fa5ac6493f4a157f4a8d9740ef0ede1d69ebb"            # 2026-08-10
SOKOL_TOOLS_REV="11d0cf678105d614d675e6d9bd2aaf3eeff12f8c"
FONTSTASH_REV="b5ddc9741061343740d85d636d782ed3e07cf7be"
STB_REV="2c980bb59875b0d32144a71867fbdebb2f77cd20"

fetch() {
	name="$1"; repo="$2"; rev="$3"
	dest="deps/$name"
	if [ ! -d "$dest/.git" ]; then
		echo "cloning $repo"
		git clone -q "https://github.com/$repo.git" "$dest"
	fi
	if [ "$(git -C "$dest" rev-parse HEAD)" != "$rev" ]; then
		git -C "$dest" fetch -q origin
		git -C "$dest" checkout -q "$rev"
	fi
	echo "$name @ $(git -C "$dest" rev-parse --short HEAD)"
}

mkdir -p deps
fetch sokol           floooh/sokol           "$SOKOL_REV"
fetch sokol-tools-bin floooh/sokol-tools-bin "$SOKOL_TOOLS_REV"
fetch fontstash       memononen/fontstash    "$FONTSTASH_REV"
fetch stb             nothings/stb           "$STB_REV"

# batcher.c includes deps/fontstash/fontstash.h; upstream keeps its headers in src/.
cp deps/fontstash/src/fontstash.h deps/fontstash/src/stb_truetype.h deps/fontstash/

echo "--- Setup complete ---"
