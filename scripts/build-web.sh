#!/bin/sh
# Build both web targets (WebGPU + WebGL2) and deploy to web/{wgpu,gl}.
# Pins emscripten to EMSCRIPTEN_VERSION so a stray `emsdk activate` can't
# silently downgrade the emdawnwebgpu port below what vendored sokol needs.
set -e

EMSCRIPTEN_VERSION="$(cat "$(dirname "$0")/../.emscripten-version")"
EMSDK_DIR="${EMSDK_DIR:-$HOME/projects/emsdk}"
MSC="${MSC:-msc}"
ENTRY="src/examples/mainSokol2d.ms"

cd "$(dirname "$0")/.."

. "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
active="$(cat "$EMSDK_DIR/upstream/emscripten/emscripten-version.txt" 2>/dev/null | tr -d '\"')"
if [ "$active" != "$EMSCRIPTEN_VERSION" ]; then
	echo "activating emscripten $EMSCRIPTEN_VERSION (was $active)"
	"$EMSDK_DIR/emsdk" activate "$EMSCRIPTEN_VERSION" >/dev/null
	. "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
fi

# msc can flake on the uncached async-emcc path; retry.
build() {
	target="$1"; passc="$2"; passl="$3"; dest="$4"
	rm -f out/release/mainSokol2d.js out/release/mainSokol2d.wasm out/release/mainSokol2d.data
	for i in 1 2 3 4; do
		"$MSC" build "$ENTRY" --os=emcc --passC="$passc" --passL="$passl" \
			--output=out/release/mainSokol2d.js >/tmp/void_web_$target.log 2>&1 || true
		if grep -q "Built" /tmp/void_web_$target.log && [ -f out/release/mainSokol2d.wasm ]; then
			mkdir -p "$dest"
			cp out/release/mainSokol2d.js out/release/mainSokol2d.wasm out/release/mainSokol2d.data "$dest/"
			echo "$target → $dest (attempt $i)"
			return 0
		fi
	done
	echo "$target FAILED after retries — see /tmp/void_web_$target.log"; return 1
}

PRELOAD="--preload-file assets/test.png --preload-file assets/font.ttf"
build wgpu "--use-port=emdawnwebgpu -DSOKOL_WGPU" "--use-port=emdawnwebgpu $PRELOAD" web/wgpu
build gl   "-DSOKOL_GLES3" "-sFULL_ES3=1 -sMAX_WEBGL_VERSION=2 $PRELOAD" web/gl
echo "done — serve web/ and open void2d.html"
