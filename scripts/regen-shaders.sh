#!/bin/bash
# Regenerate sokol-shdc shader headers from GLSL sources.
# Run this after editing any .glsl file — the .glsl.h headers are #included by C bridges,
# and a stale header produces silent visual bugs (old shader code compiled into the binary).
#
# --ifdef keeps only the build's backend in each binary. A wrapped program compiles away
# silently when no SOKOL_<backend> is defined, so every header is made to refuse an
# includer that did not go through src/sokol/backend.h first.
set -e
cd "$(dirname "$0")/.."

# --check regenerates into a scratch directory and compares instead of writing; the gate runs it.
CHECK=0
[ "$1" = "--check" ] && CHECK=1
STALE=0
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

case "$(uname -s)-$(uname -m)" in
	Darwin-arm64)            SHDC="deps/sokol-tools-bin/bin/osx_arm64/sokol-shdc" ;;
	Darwin-*)                SHDC="deps/sokol-tools-bin/bin/osx/sokol-shdc" ;;
	Linux-aarch64)           SHDC="deps/sokol-tools-bin/bin/linux_arm64/sokol-shdc" ;;
	Linux-*)                 SHDC="deps/sokol-tools-bin/bin/linux/sokol-shdc" ;;
	MINGW*|MSYS*|CYGWIN*)    SHDC="deps/sokol-tools-bin/bin/win32/sokol-shdc.exe" ;;
	*) echo "no sokol-shdc for $(uname -s)-$(uname -m)"; exit 1 ;;
esac

# The void3d shaders also ship to iOS (device + simulator); void2d does not.
LANGS="metal_macos:glsl300es:wgsl:hlsl5"
LANGS_IOS="metal_macos:metal_ios:metal_sim:glsl300es:wgsl:hlsl5"

regen() {
	dest="$2"
	[ "$CHECK" = 1 ] && dest="$SCRATCH/$(basename "$2")"
	"$SHDC" -i "$1" -o "$dest" -l "$3" -f sokol --ifdef >/dev/null
	guard="#if !defined(VOID_SOKOL_BACKEND_H)\n#error \"include src/sokol/backend.h before $(basename "$2")\"\n#endif"
	awk -v guard="$guard" '{ print } /^#if !defined\(SOKOL_GFX_INCLUDED\)/ { open = 1 } open && /^#endif/ { print guard; open = 0 }' \
		"$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
	grep -q "include src/sokol/backend.h before" "$dest" || { echo "no backend guard in $2"; exit 1; }
	[ "$CHECK" = 1 ] || return 0
	if cmp -s <(grep -v "^        sokol-shdc " "$dest" | tr -d "\r") \
		<(grep -v "^        sokol-shdc " "$2" | tr -d "\r"); then
		echo "fresh $2"
	else
		echo "stale $2"
		STALE=1
	fi
}

[ "$CHECK" = 1 ] || echo "Regenerating shader headers..."
regen src/void2d/shader2d.glsl src/void2d/shader2d.glsl.h "$LANGS"
regen src/void3d/shader3d.glsl src/void3d/shader3d.glsl.h "$LANGS_IOS"
regen src/void3d/pixelArt3d.glsl src/void3d/pixelArt3d.glsl.h "$LANGS_IOS"
regen tests/integration/gpuCopy.glsl tests/integration/gpuCopy.glsl.h "$LANGS_IOS"

[ "$CHECK" = 1 ] && exit "$STALE"
echo "OK: shader headers regenerated"
