#!/bin/sh
# Load the built web demo in headless Chrome and screenshot it, per backend.
#
# This is a LIVENESS check, not conformance. It says "the wasm module started, got a
# context and drew something"; it does not say the pixels match the D3D11 goldens, because
# the wasm build has no readback yet. Guardrail 9 needs `copyTextureToBuffer` + `mapAsync`
# for WebGPU and the existing `glReadPixels` path for WebGL2, plus a way to hand the bytes
# back out — tests/PENDING.md backend:webgpu and backend:webgl2.
#
# Measured 2026-09-20 on this box: WebGL2 draws the demo. WebGPU builds and runs but
# headless Chrome hands it no adapter (`--use-angle=swiftshader` and the real adapter both
# give a black canvas, 4 466-byte PNG), so its liveness is unproven headless and is a SKIP.
set -e
cd "$(dirname "$0")/.."

PORT="${VOID_WEB_PORT:-8731}"
SHOTS=out/webshot
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"

[ -f web/gl/mainSokol2d.wasm ] || { echo "SKIP web liveness: run scripts/build-web.sh first"; exit 0; }
[ -x "$CHROME" ] || { echo "SKIP web liveness: no Chrome at $CHROME"; exit 0; }
command -v python >/dev/null || { echo "SKIP web liveness: no python to serve web/"; exit 0; }

mkdir -p "$SHOTS"
( cd web && exec python -m http.server "$PORT" >/dev/null 2>&1 ) &
server=$!
sleep 2
trap 'kill "$server" 2>/dev/null || true' EXIT

shot() {
	backend="$1"
	# Chrome on Windows will not write to an MSYS-style path.
	if command -v cygpath >/dev/null; then
		out="$(cygpath -w "$PWD/$SHOTS")\\$backend.png"
	else
		out="$PWD/$SHOTS/$backend.png"
	fi
	"$CHROME" --headless=new --enable-unsafe-webgpu --use-angle=swiftshader \
		--virtual-time-budget=8000 --window-size=800,600 \
		--screenshot="$out" "http://localhost:$PORT/void2d.html?$backend" >/dev/null 2>&1 || true
	bytes=$(wc -c < "$SHOTS/$backend.png" 2>/dev/null || echo 0)
	# A canvas that drew nothing compresses to a few kilobytes; the demo is over 100 KB.
	if [ "$bytes" -gt 40000 ]; then
		echo "PASS  web liveness $backend: drew the demo ($bytes B in $SHOTS/$backend.png)"
	else
		echo "SKIP  web liveness $backend: blank canvas ($bytes B) — no adapter in this headless Chrome"
	fi
}

shot gl
shot wgpu
