#!/bin/sh
# The two void3d shader headers are generated, not committed (one is near 200 MB): this
# regenerates them when they are missing or their inputs changed since they were made.
set -e
cd "$(dirname "$0")/.."
stamp=out/shaderHeaders.cksum
inputs() {
	cat src/void3d/programKeys.txt src/void3d/shader3dGen.glsl src/void3d/pixelArt3dGen.glsl \
		src/shader/program.ms scripts/regen-shaders.sh deps/sokol-tools-bin/bin/*/sokol-shdc* | cksum
}
if [ -f src/void3d/shader3d.glsl.h ] && [ -f src/void3d/pixelArt3d.glsl.h ] &&
	[ -f "$stamp" ] && [ "$(cat "$stamp")" = "$(inputs)" ]; then
	exit 0
fi
echo "ensureShaders: void3d shader headers missing or stale, running scripts/regen-shaders.sh"
bash scripts/regen-shaders.sh
mkdir -p out
inputs > "$stamp"
