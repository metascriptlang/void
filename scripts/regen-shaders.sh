#!/bin/bash
# Regenerate sokol-shdc shader headers from GLSL sources.
# Run this after editing any .glsl file — the .glsl.h headers are #included by C bridges,
# and a stale header produces silent visual bugs (old shader code compiled into the binary).
#
# Every header carries every backend and sokol picks one at runtime (sg_query_backend).
# Do not add --ifdef: batcher.c, gpu3d.c, bridge.c and bridgeEmbed.m include these
# headers without defining a SOKOL_<backend> macro, so wrapped code would compile away.
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)-$(uname -m)" in
	Darwin-arm64)            SHDC="deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc" ;;
	Darwin-*)                SHDC="deps/sokol-tools-bin/bin/osx/sokol-shdc" ;;
	Linux-aarch64)           SHDC="deps/sokol-tools-bin/bin/linux_arm64/sokol-shdc" ;;
	Linux-*)                 SHDC="deps/sokol-tools-bin/bin/linux/sokol-shdc" ;;
	MINGW*|MSYS*|CYGWIN*)    SHDC="deps/sokol-tools-bin/bin/win32/sokol-shdc.exe" ;;
	*) echo "no sokol-shdc for $(uname -s)-$(uname -m)"; exit 1 ;;
esac

# The cube and void3d shaders also ship to iOS (device + simulator); void2d does not.
LANGS="metal_macos:glsl300es:wgsl:hlsl5"
LANGS_IOS="metal_macos:metal_ios:metal_sim:glsl300es:wgsl:hlsl5"

echo "Regenerating shader headers..."
"$SHDC" -i src/sokol/shader.glsl     -o src/sokol/shader.glsl.h     -l "$LANGS_IOS" -f sokol
"$SHDC" -i src/void2d/shader2d.glsl  -o src/void2d/shader2d.glsl.h  -l "$LANGS" -f sokol
"$SHDC" -i src/void3d/shader3d.glsl  -o src/void3d/shader3d.glsl.h  -l "$LANGS_IOS" -f sokol

echo "OK: shader headers regenerated"
