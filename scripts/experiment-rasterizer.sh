#!/bin/sh
# P3's rasterizer experiment (docs/VOID2D.md P3, "The rasterizer"): three arms x three
# samples through tests/experiments/rasterizer.ms, one process each, PNGs and one RASTER
# row per capture under out/experiments/rasterizer/. Needs FreeType: VOID_FREETYPE=1 sh setup.sh.
set -e
cd "$(dirname "$0")/.."
MSC="${MSC:-msc}"
ROOT="$(cygpath -m "$PWD" 2>/dev/null || pwd)"

[ -f deps/freetype/include/ft2build.h ] || { echo "no FreeType: run VOID_FREETYPE=1 sh setup.sh"; exit 1; }
mkdir -p out/experiments/rasterizer
rm -f out/rasterizerExperiment.exe
"$MSC" build tests/experiments/rasterizer.ms \
	--passC="-I$ROOT/deps/freetype/include -I$ROOT/tests/experiments" \
	--output=out/rasterizerExperiment.exe > out/experiments/rasterizer/build.log 2>&1 \
	|| { echo "build failed — see out/experiments/rasterizer/build.log"; exit 1; }

for sample in 0 1 2; do
	for arm in 0 1 2; do
		VOID_RASTERIZER=$arm VOID_SAMPLE=$sample out/rasterizerExperiment.exe 2>&1 | grep -E '^(RASTER|FAIL)'
	done
done

# --wasm: the FreeType delta per web backend, the plain demo against the demo with FreeType
# installed, both built by scripts/build-web.sh with the same flags.
if [ "${1:-}" = "--wasm" ]; then
	VOID_WEB_DEST=out/experiments/web/plain sh scripts/build-web.sh > out/experiments/rasterizer/web-plain.log 2>&1
	VOID_WEB_ENTRY=tests/experiments/rasterizerWeb.ms VOID_WEB_DEST=out/experiments/web/freetype \
		VOID_WEB_PASSC="-I$ROOT/deps/freetype/include -I$ROOT/tests/experiments" \
		sh scripts/build-web.sh > out/experiments/rasterizer/web-freetype.log 2>&1
	for backend in wgpu gl; do
		plain=$(wc -c < out/experiments/web/plain/$backend/mainSokol2d.wasm)
		freetype=$(wc -c < out/experiments/web/freetype/$backend/rasterizerWeb.wasm)
		echo "WASM $backend plain $plain freetype $freetype delta $((freetype - plain))"
	done
fi
