#!/bin/sh
# What the colour emoji, SDF text, shaper and BiDi modules cost and what a build without them pays
# (docs/VOID2D.md P6, guardrail 6). Object-level, with clang and llvm-nm; no emcc, no Yoga, no GPU.
#
#   sh scripts/wasmModuleDelta.sh           measure, prove, and compare with tests/bench/wasm.json
#   sh scripts/wasmModuleDelta.sh --print   measure and print the json fields, change nothing
#
# The records in tests/bench/wasm.json are the numbers this script printed on a given clang; a run
# fails when a number grows more than ten percent past its record, which is slack for a compiler
# upgrade and not for code.
#
# Two claims, both read from objects, for each module:
#   1. Module off: no object of the default layer refers to a void2dColour symbol, and no
#      translation unit outside the module holds a stb_image implementation. The control is the
#      same glyph.c built with -DVOID2D_COLOUR_EMOJI, which must refer to them.
#   2. Cost: code plus data bytes of each translation unit, x86-64 and wasm32 (clang -O2 against
#      the libc-free headers in scripts/wasmShim). The default-layer delta is the module-off
#      objects now against the same files at the commit before the colour item's first
#      default-layer slice, so it counts the colour item's hooks and nothing else. A wasm32
#      object is not a linked, garbage-collected module: the number the web build gives is owed
#      to scripts/build-web.sh (tests/PENDING.md wasm:budget).
set -e
cd "$(dirname "$0")/.."

OUT=out/wasmDelta
RECORD=tests/bench/wasm.json
BASE_REF="${BASE_REF:-$(sed -n 's/.*"baseRef": *"\([0-9a-f]*\)".*/\1/p' "$RECORD" 2>/dev/null)}"
GROWTH_PERCENT=10
mode=check
[ "${1:-}" = "--print" ] && mode=print
failed=0

for tool in clang llvm-nm llvm-size git tar; do
	command -v "$tool" > /dev/null 2>&1 || { echo "FAIL wasm delta: $tool is not on PATH"; exit 1; }
done
[ -n "$BASE_REF" ] || { echo "FAIL wasm delta: no baseRef in $RECORD and no BASE_REF"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/base"
git archive "$BASE_REF" src | tar -x -C "$OUT/base"
mkdir -p "$OUT/base/deps/stb" "$OUT/base/deps/sokol"
cp deps/stb/stb_truetype.h "$OUT/base/deps/stb/"
cp deps/sokol/sokol_gfx.h "$OUT/base/deps/sokol/"

WASM="clang --target=wasm32 -O2 -ffreestanding -nostdinc -isystem scripts/wasmShim"
NATIVE="clang -O2 -D_CRT_SECURE_NO_WARNINGS -Wno-deprecated-declarations"

bytes() { llvm-size "$1" | awk 'NR == 2 { print $1 + $2 }'; }

compile() {
	root="$1"; file="$2"; label="$3"; extra="$4"
	$WASM $extra -I "$root/src/void2d" -DSOKOL_GLES3 -c "$root/src/void2d/$file" \
		-o "$OUT/$label.wasm.o" 2> "$OUT/$label.wasm.log" \
		|| { echo "FAIL wasm delta: $file did not compile for wasm32 — see $OUT/$label.wasm.log"; failed=1; return; }
	$NATIVE $extra -DSOKOL_D3D11 -I "$root/src/void2d" -c "$root/src/void2d/$file" \
		-o "$OUT/$label.o" 2> "$OUT/$label.log" \
		|| { echo "FAIL wasm delta: $file did not compile natively — see $OUT/$label.log"; failed=1; }
}

for unit in glyph grapheme batcher sfnt; do
	compile "$OUT/base" "$unit.c" "base.$unit" ""
done
for unit in glyph grapheme batcher sfnt; do
	compile "." "$unit.c" "head.$unit" ""
done
compile "." "glyph.c" "on.sprite.glyph" "-DVOID2D_SPRITES"
compile "." "spriteGlyph.c" "on.sprite" ""
compile "." "glyph.c" "on.glyph" "-DVOID2D_COLOUR_EMOJI"
compile "." "colourEmoji/colourFace.c" "on.colourFace" ""
compile "." "glyph.c" "on.sdf.glyph" "-DVOID2D_SDF_TEXT"
compile "." "shaper.c" "on.shaper" ""
compile "." "bidiClass.c" "on.bidi" ""
[ "$failed" -eq 0 ] || exit 1

echo "module off: symbols"
for unit in glyph grapheme batcher sfnt; do
	if llvm-nm "$OUT/head.$unit.o" | grep -q 'void2dColour'; then
		echo "FAIL wasm delta: the module-off $unit.c object names a void2dColour symbol"
		failed=1
	fi
done
SPRITE_SYMBOLS='void2dSprite\(Count\|Index\|Codepoint\|TableFault\|Padding\|Canvas\|Draw\|Ink\)\|void2dGlyphFaceSprite\|void2dGlyphFaceIsSprite\|void2dGlyphSpriteCell\|void2dGlyphPolygonCoverage'
for unit in glyph grapheme batcher sfnt; do
	for object in "$OUT/head.$unit.o" "$OUT/head.$unit.wasm.o"; do
		if llvm-nm "$object" | grep -q "$SPRITE_SYMBOLS"; then
			echo "FAIL wasm delta: the module-off $object names a sprite symbol"
			failed=1
		fi
	done
done
for object in "$OUT/on.sprite.glyph.o" "$OUT/on.sprite.glyph.wasm.o"; do
	if ! llvm-nm "$object" | grep -q 'void2dGlyphFaceSprite'; then
		echo "FAIL wasm delta: glyph.c built with the sprite module names no void2dGlyphFaceSprite in $object, so the check above sees nothing"
		failed=1
	fi
done
if ! llvm-nm "$OUT/on.sprite.o" | grep -q 'void2dSpriteDraw'; then
	echo "FAIL wasm delta: spriteGlyph.c names no void2dSpriteDraw symbol, so the check above sees nothing"
	failed=1
fi
if ! llvm-nm "$OUT/on.glyph.o" | grep -q 'void2dColour'; then
	echo "FAIL wasm delta: glyph.c built with the module names no void2dColour symbol, so the check above sees nothing"
	failed=1
fi
for unit in glyph grapheme batcher sfnt; do
	if llvm-nm "$OUT/head.$unit.o" | grep -q 'void2dGlyphSdf\|void2dShape\|void2dBidi\|kbts_'; then
		echo "FAIL wasm delta: the module-off $unit.c object names an SDF, shaper or BiDi symbol"
		failed=1
	fi
done
if ! llvm-nm "$OUT/on.sdf.glyph.o" | grep -q 'void2dGlyphSdf'; then
	echo "FAIL wasm delta: glyph.c built with the SDF module names no void2dGlyphSdf symbol, so the check above sees nothing"
	failed=1
fi
if ! llvm-nm "$OUT/on.bidi.o" | grep -q 'void2dBidiClass'; then
	echo "FAIL wasm delta: bidiClass.c names no void2dBidiClass symbol, so the check above sees nothing"
	failed=1
fi
if ! llvm-nm "$OUT/on.shaper.o" | grep -q 'kbts_'; then
	echo "FAIL wasm delta: shaper.c names no kbts_ symbol, so the check above sees nothing"
	failed=1
fi
holders=$(grep -l 'STB_IMAGE_IMPLEMENTATION' src/void2d/*.c src/void2d/*/*.c src/assets/*.c 2> /dev/null | tr '\n' ' ')
echo "      stb_image implementations: $holders"
case "$holders" in
	*src/void2d/colourEmoji/colourFace.c*) ;;
	*) echo "FAIL wasm delta: the module no longer holds its own PNG decoder"; failed=1 ;;
esac
for unit in glyph grapheme batcher sfnt; do
	case "$holders" in
		*"src/void2d/$unit.c"*) echo "FAIL wasm delta: $unit.c holds a stb_image implementation"; failed=1 ;;
	esac
done

delta_native=0
delta_wasm=0
echo "default layer, module off: code plus data bytes (base $BASE_REF)"
echo "      unit        native base   native head   wasm32 base   wasm32 head"
for unit in glyph grapheme batcher sfnt; do
	nb=$(bytes "$OUT/base.$unit.o"); wb=$(bytes "$OUT/base.$unit.wasm.o")
	nh=$(bytes "$OUT/head.$unit.o"); wh=$(bytes "$OUT/head.$unit.wasm.o")
	printf '      %-10s %12s %13s %13s %13s\n' "$unit.c" "$nb" "$nh" "$wb" "$wh"
	delta_native=$((delta_native + nh - nb))
	delta_wasm=$((delta_wasm + wh - wb))
done
module_native=$(bytes "$OUT/on.colourFace.o")
module_wasm=$(bytes "$OUT/on.colourFace.wasm.o")
seam_native=$(( $(bytes "$OUT/on.glyph.o") - $(bytes "$OUT/head.glyph.o") ))
seam_wasm=$(( $(bytes "$OUT/on.glyph.wasm.o") - $(bytes "$OUT/head.glyph.wasm.o") ))
echo "      default-layer delta since the base: +$delta_native B native, +$delta_wasm B wasm32"
echo "module on: colourFace.c $module_native B native, $module_wasm B wasm32; glyph.c seam +$seam_native B native, +$seam_wasm B wasm32"
sdf_native=$(( $(bytes "$OUT/on.sdf.glyph.o") - $(bytes "$OUT/head.glyph.o") ))
sdf_wasm=$(( $(bytes "$OUT/on.sdf.glyph.wasm.o") - $(bytes "$OUT/head.glyph.wasm.o") ))
shaper_native=$(bytes "$OUT/on.shaper.o")
shaper_wasm=$(bytes "$OUT/on.shaper.wasm.o")
echo "module on: SDF text, glyph.c with VOID2D_SDF_TEXT +$sdf_native B native, +$sdf_wasm B wasm32; shaper.c $shaper_native B native, $shaper_wasm B wasm32"
bidi_native=$(bytes "$OUT/on.bidi.o")
bidi_wasm=$(bytes "$OUT/on.bidi.wasm.o")
echo "module on: BiDi, bidiClass.c $bidi_native B native, $bidi_wasm B wasm32"
sprite_native=$(bytes "$OUT/on.sprite.o")
sprite_wasm=$(bytes "$OUT/on.sprite.wasm.o")
spriteSeam_native=$(( $(bytes "$OUT/on.sprite.glyph.o") - $(bytes "$OUT/head.glyph.o") ))
spriteSeam_wasm=$(( $(bytes "$OUT/on.sprite.glyph.wasm.o") - $(bytes "$OUT/head.glyph.wasm.o") ))
echo "module on: sprites, spriteGlyph.c $sprite_native B native, $sprite_wasm B wasm32; glyph.c seam +$spriteSeam_native B native, +$spriteSeam_wasm B wasm32"

if [ "$mode" = print ]; then
	printf '  "delta": { "native": %s, "wasm32": %s },\n' "$delta_native" "$delta_wasm"
	printf '  "module": { "native": %s, "wasm32": %s },\n' "$module_native" "$module_wasm"
	printf '  "seam": { "native": %s, "wasm32": %s },\n' "$seam_native" "$seam_wasm"
	printf '  "sdf": { "native": %s, "wasm32": %s },\n' "$sdf_native" "$sdf_wasm"
	printf '  "shaper": { "native": %s, "wasm32": %s },\n' "$shaper_native" "$shaper_wasm"
	printf '  "bidi": { "native": %s, "wasm32": %s },\n' "$bidi_native" "$bidi_wasm"
	printf '  "sprite": { "native": %s, "wasm32": %s },\n' "$sprite_native" "$sprite_wasm"
	printf '  "spriteSeam": { "native": %s, "wasm32": %s }\n' "$spriteSeam_native" "$spriteSeam_wasm"
	exit "$failed"
fi

# a recorded number is "key": value on one line, so sh can read it
recorded() { sed -n "s/.*\"$1\": *{.*\"$2\": *\([0-9]*\).*/\1/p" "$RECORD" | head -n 1; }
within() {
	label="$1"; now="$2"; was="$3"
	if [ -z "$was" ]; then echo "FAIL wasm delta: $RECORD has no $label"; failed=1; return; fi
	limit=$((was + was * GROWTH_PERCENT / 100))
	if [ "$now" -gt "$limit" ]; then
		echo "FAIL wasm delta: $label is $now B, the record says $was B (limit $limit B)"
		failed=1
	else
		echo "PASS wasm delta: $label $now B (record $was B, limit $limit B)"
	fi
}
within "default-layer delta, wasm32 objects" "$delta_wasm" "$(recorded delta wasm32)"
within "default-layer delta, native objects" "$delta_native" "$(recorded delta native)"
within "module, wasm32 objects" "$module_wasm" "$(recorded module wasm32)"
within "module, native objects" "$module_native" "$(recorded module native)"
within "SDF text, wasm32 objects" "$sdf_wasm" "$(recorded sdf wasm32)"
within "SDF text, native objects" "$sdf_native" "$(recorded sdf native)"
within "shaper, wasm32 objects" "$shaper_wasm" "$(recorded shaper wasm32)"
within "shaper, native objects" "$shaper_native" "$(recorded shaper native)"
within "BiDi tables, wasm32 objects" "$bidi_wasm" "$(recorded bidi wasm32)"
within "BiDi tables, native objects" "$bidi_native" "$(recorded bidi native)"
within "sprites, wasm32 objects" "$sprite_wasm" "$(recorded sprite wasm32)"
within "sprites, native objects" "$sprite_native" "$(recorded sprite native)"
within "sprite seam, wasm32 objects" "$spriteSeam_wasm" "$(recorded spriteSeam wasm32)"
within "sprite seam, native objects" "$spriteSeam_native" "$(recorded spriteSeam native)"
exit "$failed"
