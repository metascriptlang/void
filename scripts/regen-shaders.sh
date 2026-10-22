#!/bin/bash
# Regenerate the shader modules and tables from the GLSL sources and src/void3d/programKeys.txt.
# Run this after editing any of them: a stale module compiles the old shader into the binary.
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

# Every shader carries every target, iOS device and simulator included; src/shader/program.ms
# compiles its programs with the same list, so this reads it from there.
LANGS=$(sed -n 's/^const SHDC_LANGUAGES = "\(.*\)";$/\1/p' src/shader/program.ms)
[ -n "$LANGS" ] || { echo "no SHDC_LANGUAGES line in src/shader/program.ms"; exit 1; }

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

# ---- void3d: one program per declared key ----

KEYS=src/void3d/programKeys.txt

sourceOf() {
	case "$1" in
		CORE)      echo "$GENERATED" ;;
		SHADOW)    echo "$GENERATED" ;;
		PIXEL_ART) echo "$GENERATED_PIXEL_ART" ;;
		*) echo "programKeys.txt: unknown preset $1" >&2; return 1 ;;
	esac
}

# sokol-shdc embeds every stage it is given, used or not: keep the key's two stages.
stagesOf() {
	awk -v vs="$2" -v fs="$3" '
		{ sub(/\r$/, "") }
		/^@(vs|fs) / { skip = ($2 != vs && $2 != fs) }
		!skip { print }
		skip && /^@end/ { skip = 0 }
	' "$1"
}

# The position of $2 (programKeys.txt's LIT_TEXTURED) in gpu3d.ms's enum $1 (LitTextured).
ordinal() {
	tr -d "\r" < src/void3d/gpu3d.ms | awk -v head="export enum $1 {" '
		$0 == head { open = 1; next }
		open && /^}/ { exit }
		open { gsub(/[\t ,]/, ""); print }
	' | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr a-z A-Z |
		awk -v name="$2" '$0 == name { print NR - 1; found = 1 } END { exit !found }' ||
		{ echo "src/void3d/gpu3d.ms enum $1 has no $2" >&2; return 1; }
}

# The fields of HLSL cbuffer $2 in $1, with their registers, one per line.
cbufferFields() {
	tr -d "\r" < "$1" | awk -v head="cbuffer $2 " '
		index($0, head) == 1 { open = 1; next }
		open && /^};/ { exit }
		open && /packoffset/ { sub(/^ *float4 _[0-9]+_/, ""); sub(/ : packoffset\(/, "@"); sub(/\);$/, ""); print }
	'
}

regenKeys() {
	work="$SCRATCH/keys"
	mkdir -p "$work"
	: > "$work/dataLayouts"
	: > "$work/dataKeys"
	tables="out/shaderTables/void3d"
	mkdir -p "$tables"
	: > "$tables/rows"
	count=0
	while read -r module program preset features vs fs layout extra; do
		case "$module" in ''|'#'*) continue ;; esac
		if [ -z "$layout" ] || [ -n "$extra" ]; then
			echo "programKeys.txt: row $module does not have seven columns"; exit 1
		fi
		src=$(sourceOf "$preset")
		premultiplied=0
		cutout=0
		shadowed=0
		uvTransform=0
		backTexture=0
		dissolve=0
		emissive=0
		normalMap=0
		skinned=0
		normalMrt=0
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
					EMISSIVE)      emissive=1 ;;
					NORMAL_MAP)    normalMap=1 ;;
					SKINNED)       skinned=1 ;;
					NORMAL_MRT)    normalMrt=1 ;;
					*) echo "programKeys.txt: row $module names unknown feature $feature"; exit 1 ;;
				esac
			done
			defines="--defines=$features"
		fi
		input="$work/$module.glsl"
		{
			stagesOf "$src" "$vs" "$fs"
			echo "@program program $vs $fs"
		} > "$input"
		for feature in $(echo "$features" | tr ':' ' '); do
			[ "$feature" = "-" ] && continue
			grep -q "^#ifdef $feature\$" "$input" ||
				{ echo "programKeys.txt: row $module asks for $feature, which $vs and $fs never read"; exit 1; }
		done
		"$SHDC" -i "$input" -o "$tables/$module" -l "$LANGS" -f bare_yaml -m "$module" $defines >/dev/null
		echo "$module $tables/${module}_${module}_reflection.yaml $layout" >> "$tables/rows"
		layoutOrdinal=$(ordinal VertexLayout "$layout")
		echo "	$layoutOrdinal," >> "$work/dataLayouts"
		programOrdinal=$(ordinal Program "$program")
		presetOrdinal=$(ordinal Preset "$preset")
		echo "	$(( programOrdinal | presetOrdinal << 4 | premultiplied << 6 | cutout << 7 |
			shadowed << 8 | uvTransform << 9 | backTexture << 10 | dissolve << 11 | emissive << 12 |
			normalMap << 13 | skinned << 14 | normalMrt << 15 ))," >> "$work/dataKeys"
		count=$((count + 1))
	done < <(tr -d "\r" < "$KEYS")

	{
		echo "// Generated by scripts/regen-shaders.sh from src/void3d/programKeys.txt; do not edit."
		echo "// The programs gpu3d.ms registers with the GPU door, in door order: layouts and keys."
		echo
		echo "export const GPU3D_PROGRAM_TABLE_LENGTH: int32 = $count;"
		echo
		echo "export const PROGRAM_LAYOUTS: int32[$count] = ["
		cat "$work/dataLayouts"
		echo "];"
		echo
		echo "export const PROGRAM_KEYS: int32[$count] = ["
		cat "$work/dataKeys"
		echo "];"
	} > "$work/programTableData.ms"
	settle "$work/programTableData.ms" src/void3d/programTableData.ms

	"${MSC:-msc}" run tools/shaderTables.ms -- --rows "$tables/rows" "$tables/programModules.ms" \
		../webgpu/types.ms gpu3dShaderModule > "$SCRATCH/tables.log" 2>&1 ||
		{ cat "$SCRATCH/tables.log"; echo "shaderTables src/void3d/programKeys.txt failed"; exit 1; }
	mv "$tables/programModules.ms" "$work/programModules.ms"
	settle "$work/programModules.ms" src/void3d/programModules.ms

	# A dissolve caster writes the head of an emissive dissolve's block (draw.ms applyBlockHead).
	caster=$(cbufferFields "$tables/shadowLitTexturedDissolve_shadowLitTexturedDissolve_program_hlsl5_fragment.hlsl" \
		movingMaterialParams | tr "\n" " ")
	emissive=$(cbufferFields "$tables/litTexturedDissolveEmissive_litTexturedDissolveEmissive_program_hlsl5_fragment.hlsl" \
		movingEmissiveMaterialParams | tr "\n" " ")
	if [ -z "$caster" ] || [ "$emissive" != "${caster}emissive@c$(echo "$caster" | wc -w | tr -d " ") " ]; then
		echo "movingEmissiveMaterialParams ($emissive) must be movingMaterialParams ($caster) and then emissive"
		exit 1
	fi
}

# Every void3d stage is written in MetaScript: the core's in src/void3d/shader3d.ms and
# post3d.ms, the pixel-art preset's in pixelArt3d.ms.
GENERATED=src/void3d/shader3dGen.glsl
GENERATED_PIXEL_ART=src/void3d/pixelArt3dGen.glsl
generate() {
	out="$SCRATCH/$(basename "$2")"
	"${MSC:-msc}" run "$1" > "$out" 2> "$SCRATCH/generate.log" ||
		{ cat "$SCRATCH/generate.log"; echo "$1 failed"; exit 1; }
	settle "$out" "$2"
}

# The same programs as data for src/webgpu: shdc's bare output read by tools/shaderTables.ms
# (docs/GPU.md "Shaders"). Its work directory is relative, because the tool is a native binary
# that cannot open an MSYS /tmp path.
tables() {
	work="out/shaderTables"
	mkdir -p "$work"
	yaml="$work/$(basename "$1" .glsl)"
	"$SHDC" -i "$1" -o "$yaml" -l "$3" -f bare_yaml >/dev/null
	out="$SCRATCH/$(basename "$2")"
	"${MSC:-msc}" run tools/shaderTables.ms -- "${yaml}_reflection.yaml" "$work/$(basename "$2")" "$4" 		> "$SCRATCH/tables.log" 2>&1 || { cat "$SCRATCH/tables.log"; echo "shaderTables $1 failed"; exit 1; }
	mv "$work/$(basename "$2")" "$out"
	settle "$out" "$2"
}

# The C side of a Void-emitted GLSL file (uniform block structs, slot constants) for a C consumer
# that writes the blocks, without sokol_gfx.h.
slots() {
	out="$SCRATCH/$(basename "$2")"
	"${MSC:-msc}" run tools/shaderSlots.ms -- "$1" "$3" > "$out" 2> "$SCRATCH/slots.log" ||
		{ cat "$SCRATCH/slots.log"; echo "shaderSlots $1 failed"; exit 1; }
	settle "$out" "$2"
}

[ "$CHECK" = 1 ] || echo "Regenerating shader headers..."
generate tools/genShaders.ms "$GENERATED"
generate tools/genShadersPixelArt.ms "$GENERATED_PIXEL_ART"
generate tools/genShaders2d.ms src/void2d/shader2dGen.glsl
slots src/void2d/shader2dGen.glsl src/void2d/shader2dSlots.h VOID2D_SHADER2D_SLOTS_H
tables src/void2d/shader2d.glsl src/void2d/shader2dModules.ms "$LANGS" ../webgpu/types.ms
regenKeys
tables tests/integration/gpuCopy.glsl tests/integration/gpuCopyModules.ms "$LANGS" ../../src/webgpu/types.ms

[ "$CHECK" = 1 ] && exit "$STALE"
echo "OK: shader headers regenerated"
