#!/bin/sh
# Build both web targets (WebGPU + WebGL2) and deploy to web/{wgpu,gl}; the --target=js build of the
# same demo goes to web/{js-wgpu,js-gl} (web/void2d.html ?js).
# Pins emscripten to EMSCRIPTEN_VERSION so a stray `emsdk activate` can't
# silently downgrade the emdawnwebgpu port below what vendored sokol needs.
set -e

EMSCRIPTEN_VERSION="$(cat "$(dirname "$0")/../.emscripten-version")"
EMSDK_DIR="${EMSDK_DIR:-$HOME/projects/emsdk}"
MSC="${MSC:-msc}"
ENTRY="${VOID_WEB_ENTRY:-src/examples/main2d.ms}"
DEST="${VOID_WEB_DEST:-web}"
EXTRA_PASSC="${VOID_WEB_PASSC:-}"
MSC_FLAGS="${VOID_WEB_MSCFLAGS:-}"
NAME="$(basename "$ENTRY" .ms)"
LOG_DIR="${VOID_WEB_LOGDIR:-/tmp}"
mkdir -p "$LOG_DIR"

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
	target="$1"; api="$2"; dest="$3"
	rm -f "out/release/$NAME.js" "out/release/$NAME.wasm" "out/release/$NAME.data"
	for i in 1 2 3 4; do
		"$MSC" build $MSC_FLAGS "$ENTRY" --os=emcc "-d:$api" --passC="$EXTRA_PASSC" --passL="$PRELOAD" \
			--output="out/release/$NAME.js" >"$LOG_DIR/void_web_$target.log" 2>&1 || true
		if grep -q "Built" "$LOG_DIR/void_web_$target.log" && [ -f "out/release/$NAME.wasm" ]; then
			mkdir -p "$dest"
			cp "out/release/$NAME.js" "out/release/$NAME.wasm" "out/release/$NAME.data" "$dest/"
			echo "$target → $dest (attempt $i)"
			return 0
		fi
	done
	echo "$target FAILED after retries — see $LOG_DIR/void_web_$target.log"; return 1
}

# The JS build needs no emscripten: msc emits the bundle, scripts/jsMinify.sh ships it, and the files
# the demo reads go beside it for the page to fetch (a browser has no files).
JS_ENTRY="${VOID_WEB_JS_ENTRY:-src/examples/main2dWeb.jms}"
JS_ASSETS="${VOID_WEB_JS_ASSETS:-assets/test.png assets/font.ttf}"
buildJs() {
	target="$1"; api="$2"; dest="$3"
	jsName="$(basename "$JS_ENTRY" .jms)"
	"$MSC" build $MSC_FLAGS "$JS_ENTRY" --target=js "-d:$api" --output="out/release/$jsName-$target.js" \
		>"$LOG_DIR/void_web_$target.log" 2>&1 \
		|| { echo "$target FAILED — see $LOG_DIR/void_web_$target.log"; return 1; }
	mkdir -p "$dest/assets"
	sh scripts/jsMinify.sh "out/release/$jsName-$target.js" "$dest/$jsName.js" >>"$LOG_DIR/void_web_$target.log" 2>&1 \
		|| { echo "$target minify FAILED — see $LOG_DIR/void_web_$target.log"; return 1; }
	for asset in $JS_ASSETS; do cp "$asset" "$dest/assets/"; done
	echo "$target → $dest"
}

PRELOAD="${VOID_WEB_PRELOAD:---preload-file assets/test.png --preload-file assets/font.ttf}"
BACKENDS="${VOID_WEB_BACKENDS:-wgpu gl js-wgpu js-gl}"
case " $BACKENDS " in *" wgpu "*)
	build wgpu webgpu "$DEST/wgpu" ;;
esac
case " $BACKENDS " in *" gl "*)
	build gl webgl2 "$DEST/gl" ;;
esac
case " $BACKENDS " in *" js-wgpu "*)
	buildJs js-wgpu webgpu "$DEST/js-wgpu" ;;
esac
case " $BACKENDS " in *" js-gl "*)
	buildJs js-gl webgl2 "$DEST/js-gl" ;;
esac
echo "done — serve web/ and open void2d.html"
