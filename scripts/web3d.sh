#!/bin/sh
# void3d on WebGL2: each readback check built for the browser (build-web.sh, gl backend) and run in
# headless Chrome by scripts/web3d.mjs, judged by its own thresholds as on GL core, not by D3D11
# bytes. WebGPU has no readback in the capture library, so it is not judged here.
#
#   sh scripts/web3d.sh            build, then run every check in both presets
#   sh scripts/web3d.sh --run      run what out/web3d already holds
set -e
cd "$(dirname "$0")/.."
PORT="${VOID_WEB_PORT:-8751}"
OUT=out/web3d
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"

# name:pixel-art setting, or name:- for a check with only the core run. cardTable, worldLabel and
# targetTexture draw void2d text, whose emcc build stops at the bool-span card
# (~/metascript/.inbox/compiler/2026-09-26-interface-array-to-span-void-pointer.md).
WEB_CHECKS="alphaKill:VOID_ALPHA_KILL_PIXEL_ART=1 billboardBlend:VOID_BILLBOARD_BLEND_PIXEL_ART=1
	dirShadow:VOID_DIR_SHADOW_PIXEL_ART=1 mapMaterial:VOID_MAP_PIXEL_ART=1
	movingMaterial:VOID_MOVING_PIXEL_ART=1 mrtBlend:- renderOrder:VOID_RENDER_ORDER_PIXEL_ART=1
	sortLayer:VOID_SORT_LAYER_PIXEL_ART=1 exposure:VOID_EXPOSURE_PIXEL_ART=1"

[ -x "$CHROME" ] || { echo "SKIP web3d: no Chrome at $CHROME"; exit 0; }
command -v python >/dev/null || { echo "SKIP web3d: no python to serve $OUT"; exit 0; }

runs=""
for entry in $WEB_CHECKS; do
	name=${entry%%:*}
	pixel=${entry#*:}
	if [ "${1:-}" != "--run" ]; then
		VOID_WEB_ENTRY=tests/integration/$name.ms VOID_WEB_DEST="$OUT/$name" VOID_WEB_BACKENDS=gl \
			sh scripts/build-web.sh > "$OUT.$name.build.log" 2>&1 \
			|| { echo "FAIL web3d: $name does not build for WebGL2 — see $OUT.$name.build.log"; exit 1; }
		cp tests/integration/web/runner3d.html "$OUT/$name/gl/runner3d.html"
	fi
	runs="$runs $name"
	[ "$pixel" = "-" ] || runs="$runs $name:$pixel"
done

( cd "$OUT" && exec python -m http.server "$PORT" > /dev/null 2>&1 ) &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 2
node scripts/web3d.mjs "http://127.0.0.1:$PORT" $runs | tee "$OUT.log"
total=$(echo $runs | wc -w)
passed=$(grep -c "	PASS " "$OUT.log" || true)
echo "web3d webgl2: $passed of $total runs pass"
[ "$passed" -eq "$total" ]
