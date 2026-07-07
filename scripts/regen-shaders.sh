#!/bin/bash
# Regenerate sokol-shdc shader headers from GLSL sources.
# Run this after editing any .glsl file — the .glsl.h headers are #included by C bridges,
# and a stale header produces silent visual bugs (old shader code compiled into the binary).
set -e
cd "$(dirname "$0")/.."

SHDC="deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc"
LANGS="metal_macos:glsl300es:wgsl"

echo "Regenerating shader headers..."
"$SHDC" -i src/sokol/shader.glsl     -o src/sokol/shader.glsl.h     -l "$LANGS" -f sokol
"$SHDC" -i src/void2d/shader2d.glsl  -o src/void2d/shader2d.glsl.h  -l "$LANGS" -f sokol

echo "OK: shader headers regenerated"
