#!/bin/bash
# Regenerate sokol-shdc shader headers from GLSL sources.
# Run this after editing any .glsl file or src/void3d/programKeys.txt — the .glsl.h headers are
# #included by C bridges, and a stale header produces silent visual bugs (old shader code
# compiled into the binary).
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

guard() {
	guard="#if !defined(VOID_SOKOL_BACKEND_H)\n#error \"include src/sokol/backend.h before $2\"\n#endif"
	awk -v guard="$guard" '{ print } /^#if !defined\(SOKOL_GFX_INCLUDED\)/ { open = 1 } open && /^#endif/ { print guard; open = 0 }' \
		"$1" > "$1.tmp" && mv "$1.tmp" "$1"
	grep -q "include src/sokol/backend.h before" "$1" || { echo "no backend guard in $1"; exit 1; }
}

settle() {
	if [ "$CHECK" = 0 ]; then
		mv "$1" "$2"
		return 0
	fi
	if cmp -s <(grep -v "^        sokol-shdc " "$1" | tr -d "\r") \
		<(grep -v "^        sokol-shdc " "$2" | tr -d "\r"); then
		echo "fresh $2"
	else
		echo "stale $2"
		STALE=1
	fi
}

regen() {
	dest="$2"
	[ "$CHECK" = 1 ] && dest="$SCRATCH/$(basename "$2")"
	"$SHDC" -i "$1" -o "$dest" -l "$3" -f sokol --ifdef >/dev/null
	guard "$dest" "$(basename "$2")"
	[ "$CHECK" = 1 ] || return 0
	settle "$dest" "$2"
}

# ---- void3d: one program per declared key ----

KEYS=src/void3d/programKeys.txt
ROOT=$(pwd -W 2>/dev/null || pwd)

sourceOf() {
	case "$1" in
		CORE)      echo src/void3d/shader3d.glsl ;;
		SHADOW)    echo src/void3d/shader3d.glsl ;;
		PIXEL_ART) echo src/void3d/pixelArt3d.glsl ;;
		*) echo "programKeys.txt: unknown preset $1" >&2; return 1 ;;
	esac
}

attributesOf() {
	case "$1" in
		LIT)          echo "position normal color" ;;
		PARTICLE)     echo "root color" ;;
		BILLBOARD)    echo "position size anchor tile color" ;;
		LIT_TEXTURED) echo "position normal uv color" ;;
		FULLSCREEN)   echo "position" ;;
		*) echo "programKeys.txt: unknown layout $1" >&2; return 1 ;;
	esac
}

# sokol-shdc embeds every stage it is given, used or not: keep the blocks and the key's two stages.
stagesOf() {
	awk -v vs="$2" -v fs="$3" '
		{ sub(/\r$/, "") }
		/^@(vs|fs) / { skip = ($2 != vs && $2 != fs) }
		!skip { print }
		skip && /^@end/ { skip = 0 }
	' "$1"
}

regenKeys() {
	work="$SCRATCH/keys"
	mkdir -p "$work"
	: > "$work/shader3d.glsl.h"
	: > "$work/pixelArt3d.glsl.h"
	: > "$work/descs"
	: > "$work/layouts"
	: > "$work/keys"
	: > "$work/asserts"
	: > "$work/blocks"
	count=0
	while read -r module program preset features vs fs layout extra; do
		case "$module" in ''|'#'*) continue ;; esac
		if [ -z "$layout" ] || [ -n "$extra" ]; then
			echo "programKeys.txt: row $module does not have seven columns"; exit 1
		fi
		src=$(sourceOf "$preset")
		attributes=$(attributesOf "$layout")
		premultiplied=0
		cutout=0
		shadowed=0
		uvTransform=0
		backTexture=0
		dissolve=0
		defines=""
		if [ "$features" != "-" ]; then
			for feature in $(echo "$features" | tr ':' ' '); do
				case "$feature" in
					PREMULTIPLIED) premultiplied=1 ;;
					CUTOUT)        cutout=1 ;;
					SHADOWED)      shadowed=1 ;;
					UV_TRANSFORM)  uvTransform=1 ;;
					BACK_TEXTURE)  backTexture=1 ;;
					DISSOLVE)      dissolve=1 ;;
					*) echo "programKeys.txt: row $module names unknown feature $feature"; exit 1 ;;
				esac
			done
			defines="--defines=$features"
		fi
		input="$work/$module.glsl"
		{
			echo "@include $ROOT/src/void3d/shader3dBlocks.glsl"
			stagesOf "$src" "$vs" "$fs"
			echo "@program program $vs $fs"
		} > "$input"
		for feature in $(echo "$features" | tr ':' ' '); do
			[ "$feature" = "-" ] && continue
			grep -q "^#ifdef $feature\$" "$input" ||
				{ echo "programKeys.txt: row $module asks for $feature, which $vs and $fs never read"; exit 1; }
		done
		"$SHDC" -i "$input" -o "$work/$module.h" -l "$LANGS_IOS" -f sokol --ifdef --no-log-cmdline \
			-m "$module" $defines >/dev/null
		header=$(basename "$src").h
		guard "$work/$module.h" "$header"
		cat "$work/$module.h" >> "$work/$header"

		printf '\t%s_program_shader_desc,\n' "$module" >> "$work/descs"
		printf '\tLAYOUT_%s,\n' "$layout" >> "$work/layouts"
		key='\tGPU3D_PROGRAM_KEY(GPU3D_PROGRAM_%s, GPU3D_PRESET_%s, %s, %s, %s, %s, %s, %s),\n'
		printf "$key" "$program" "$preset" "$premultiplied" "$cutout" "$shadowed" \
			"$uvTransform" "$backTexture" "$dissolve" >> "$work/keys"
		first=$(tr -d "\r" < "$KEYS" | awk -v l="$layout" '$1 !~ /^#/ && $7 == l { print $1; exit }')
		if [ "$first" != "$module" ]; then
			same=""
			for a in $attributes; do
				same="$same${same:+ && }ATTR_${module}_program_$a == ATTR_${first}_program_$a"
			done
			printf '_Static_assert(%s,\n\t"%s must take the %s layout as %s does");\n' \
				"$same" "$module" "$layout" "$first" >> "$work/asserts"
		fi
		for block in $(grep -oE "typedef struct ${module}_[A-Za-z0-9]+_t" "$work/$module.h" |
			sed "s/typedef struct ${module}_//; s/_t\$//"); do
			owner=$(awk -v b="$block" '$1 == b { print $2; exit }' "$work/blocks")
			if [ -z "$owner" ]; then
				echo "$block $module" >> "$work/blocks"
			else
				printf '_Static_assert(sizeof(%s_%s_t) == sizeof(%s_%s_t) && UB_%s_%s == UB_%s_%s,\n\t"%s must take %s as %s does");\n' \
					"$module" "$block" "$owner" "$block" "$module" "$block" "$owner" "$block" \
					"$module" "$block" "$owner" >> "$work/asserts"
			fi
		done
		count=$((count + 1))
	done < <(tr -d "\r" < "$KEYS")

	{
		echo "// Generated by scripts/regen-shaders.sh from src/void3d/programKeys.txt; do not edit."
		echo "// The programs gpu3d.c registers with the GPU door, in door order, with their keys."
		echo "#define GPU3D_PROGRAM_TABLE_LENGTH $count"
		echo
		echo "static const ShaderDescription PROGRAMS[GPU3D_PROGRAM_TABLE_LENGTH] = {"
		cat "$work/descs"
		echo "};"
		echo
		echo "static const int32_t PROGRAM_LAYOUTS[GPU3D_PROGRAM_TABLE_LENGTH] = {"
		cat "$work/layouts"
		echo "};"
		echo
		echo "static const int32_t PROGRAM_KEYS[GPU3D_PROGRAM_TABLE_LENGTH] = {"
		cat "$work/keys"
		echo "};"
		echo
		cat "$work/asserts"
	} > "$work/programTable.h"

	settle "$work/shader3d.glsl.h" src/void3d/shader3d.glsl.h
	settle "$work/pixelArt3d.glsl.h" src/void3d/pixelArt3d.glsl.h
	settle "$work/programTable.h" src/void3d/programTable.h
}

[ "$CHECK" = 1 ] || echo "Regenerating shader headers..."
regen src/void2d/shader2d.glsl src/void2d/shader2d.glsl.h "$LANGS"
regenKeys
regen tests/integration/gpuCopy.glsl tests/integration/gpuCopy.glsl.h "$LANGS_IOS"

[ "$CHECK" = 1 ] && exit "$STALE"
echo "OK: shader headers regenerated"
