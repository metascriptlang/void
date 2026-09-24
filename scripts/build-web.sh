#!/bin/sh
# Build both web targets (WebGPU + WebGL2) and deploy to web/{wgpu,gl}.
# Pins emscripten to EMSCRIPTEN_VERSION so a stray `emsdk activate` can't
# silently downgrade the emdawnwebgpu port below what vendored sokol needs.
set -e

EMSCRIPTEN_VERSION="$(cat "$(dirname "$0")/../.emscripten-version")"
EMSDK_DIR="${EMSDK_DIR:-$HOME/projects/emsdk}"
MSC="${MSC:-msc}"
ENTRY="${VOID_WEB_ENTRY:-src/examples/mainSokol2d.ms}"
DEST="${VOID_WEB_DEST:-web}"
EXTRA_PASSC="${VOID_WEB_PASSC:-}"
NAME="$(basename "$ENTRY" .ms)"

cd "$(dirname "$0")/.."

case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
	# Windows: emsdk_env.sh exports unix-shaped variables that break the .bat wrappers, and
	# msc cannot spawn a .bat at all. Use the shims instead (scripts/emccShim.c) and point
	# emcc.py at emsdk's own interpreter and config.
	sh "$(dirname "$0")/build-emcc-shim.sh"
	VOID_EMSDK_ROOT="$EMSDK_DIR"
	VOID_EMSDK_PYTHON="$(ls -d "$EMSDK_DIR"/python/*/python.exe 2>/dev/null | head -1)"
	[ -x "$VOID_EMSDK_PYTHON" ] || { echo "no emsdk python under $EMSDK_DIR/python"; exit 1; }
	EM_CONFIG="$EMSDK_DIR/.emscripten"
	export VOID_EMSDK_ROOT VOID_EMSDK_PYTHON EM_CONFIG
	PATH="$(cd "$(dirname "$0")/.." && pwd)/out/emcc-shim:$PATH"
	export PATH
	;;
*)
	. "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
	;;
esac
active="$(cat "$EMSDK_DIR/upstream/emscripten/emscripten-version.txt" 2>/dev/null | tr -d '\"')"
if [ "$active" != "$EMSCRIPTEN_VERSION" ]; then
	echo "emscripten is $active, .emscripten-version pins $EMSCRIPTEN_VERSION"
	exit 1
fi

# msc can flake on the uncached async-emcc path; retry.
build() {
	target="$1"; passc="$2"; passl="$3"; dest="$4"
	rm -f "out/release/$NAME.js" "out/release/$NAME.wasm" "out/release/$NAME.data"
	for i in 1 2 3 4; do
		"$MSC" build "$ENTRY" --os=emcc --passC="$passc $EXTRA_PASSC" --passL="$passl" \
			--output="out/release/$NAME.js" >/tmp/void_web_$target.log 2>&1 || true
		if grep -q "Built" /tmp/void_web_$target.log && [ -f "out/release/$NAME.wasm" ]; then
			mkdir -p "$dest"
			cp "out/release/$NAME.js" "out/release/$NAME.wasm" "out/release/$NAME.data" "$dest/"
			echo "$target → $dest (attempt $i)"
			return 0
		fi
	done
	echo "$target FAILED after retries — see /tmp/void_web_$target.log"; return 1
}

PRELOAD="${VOID_WEB_PRELOAD:---preload-file assets/test.png --preload-file assets/font.ttf}"
BACKENDS="${VOID_WEB_BACKENDS:-wgpu gl}"
case " $BACKENDS " in *" wgpu "*)
	build wgpu "--use-port=emdawnwebgpu -DSOKOL_WGPU" "--use-port=emdawnwebgpu $PRELOAD" "$DEST/wgpu" ;;
esac
case " $BACKENDS " in *" gl "*)
	build gl   "-DSOKOL_GLES3" "-sFULL_ES3=1 -sMAX_WEBGL_VERSION=2 $PRELOAD" "$DEST/gl" ;;
esac
echo "done — serve web/ and open void2d.html"
