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

# name:pixel-art setting, or name:- for a check with only the core run.
WEB_CHECKS="alphaKill:VOID_ALPHA_KILL_PIXEL_ART=1 billboardBlend:VOID_BILLBOARD_BLEND_PIXEL_ART=1
	cardTable:- dirShadow:VOID_DIR_SHADOW_PIXEL_ART=1 mapMaterial:VOID_MAP_PIXEL_ART=1
	movingMaterial:VOID_MOVING_PIXEL_ART=1 mrtBlend:- renderOrder:VOID_RENDER_ORDER_PIXEL_ART=1
	sortLayer:VOID_SORT_LAYER_PIXEL_ART=1 targetTexture:VOID_TARGET_TEXTURE_PRESET=pixelArt
	worldLabel:VOID_WORLD_LABEL_PRESET=pixelArt exposure:VOID_EXPOSURE_PIXEL_ART=1
	copyAlpha:- forwardOutline:VOID_OUTLINE_FRAMEBUFFER_FACTOR=2
	particleVisual:VOID_PARTICLE_VISUAL_PIXEL_ART=1
	meshLod:VOID_MESH_LOD_INDEX32=1,VOID_MESH_LOD_OUTLINE=1,\
VOID_MESH_LOD_INDEX32=1&VOID_MESH_LOD_OUTLINE=1"

[ -x "$CHROME" ] || { echo "SKIP web3d: no Chrome at $CHROME"; exit 0; }
command -v python >/dev/null || { echo "SKIP web3d: no python to serve $OUT"; exit 0; }
node --test scripts/web3d.test.mjs

runs=""
for entry in $WEB_CHECKS; do
	name=${entry%%:*}
	settingsCsv=${entry#*:}
	if [ "${1:-}" != "--run" ]; then
		VOID_WEB_ENTRY=tests/integration/$name.ms VOID_WEB_DEST="$OUT/$name" VOID_WEB_BACKENDS=gl \
			sh scripts/build-web.sh > "$OUT.$name.build.log" 2>&1 \
			|| { echo "FAIL web3d: $name does not build for WebGL2 — see $OUT.$name.build.log"; exit 1; }
		cp tests/integration/web/runner3d.html "$OUT/$name/gl/runner3d.html"
	fi
	runs="$runs $name"
	if [ "$settingsCsv" != "-" ]; then
		for setting in $(printf '%s' "$settingsCsv" | tr ',' ' '); do
			runs="$runs $name:$setting"
		done
	fi
done

( cd "$OUT" && exec python -m http.server "$PORT" > /dev/null 2>&1 ) &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 2
runnerStatus=0
node scripts/web3d.mjs "http://127.0.0.1:$PORT" $runs > "$OUT.log" 2>&1 || runnerStatus=$?
cat "$OUT.log"
[ "$runnerStatus" -eq 0 ] || exit "$runnerStatus"
total=$(echo $runs | wc -w)
passed=$(grep -c "^RESULT .* PASS$" "$OUT.log" || true)
echo "web3d webgl2: $passed of $total runs pass"
[ "$passed" -eq "$total" ]
