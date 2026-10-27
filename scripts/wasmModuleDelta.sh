#!/bin/sh
# What the C units that remain under src/void2d cost as objects, and what the default layer pays for
# the modules (docs/VOID2D.md P6, guardrail 6). Object-level, with clang and llvm-nm; no emcc, no
# Yoga, no GPU. The modules written in MetaScript (colour emoji, SDF text, text outline, BiDi, sprites) have no
# object of their own: their linked cost is tests/bench/wasmBudget.txt, their off-build symbol check
# is guardrail 6 in scripts/gate.sh on the executables.
#
#   sh scripts/wasmModuleDelta.sh           measure, prove, and compare with tests/bench/wasm.json
#   sh scripts/wasmModuleDelta.sh --print   measure and print the json fields, change nothing
#
# The records in tests/bench/wasm.json are the numbers this script printed on a given clang; a run
# fails when a number grows more than ten percent past its record, which is slack for a compiler
# upgrade and not for code.
#
# Claims, all read from objects:
#   1. Default layer (batcher.c, the one C unit every build holds): it names no symbol of a module
#      (shaper, sprite, SDF, outline), and no C unit in src/void2d holds a stb_image
#      implementation.
#   2. Control: shaper.c names kbts_, so claim 1 would see a module symbol if there were one. The
#      sprite module has no C unit and so no control here; its off-build symbol check is on the
#      executables, srcZvoid2dZsprite in guardrail 6 of scripts/gate.sh.
set -e
cd "$(dirname "$0")/.."

OUT=out/wasmDelta
RECORD=tests/bench/wasm.json
GROWTH_PERCENT=10
mode=check
[ "${1:-}" = "--print" ] && mode=print
failed=0

for tool in clang llvm-nm llvm-size; do
	command -v "$tool" > /dev/null 2>&1 || { echo "FAIL wasm delta: $tool is not on PATH"; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT"

WASM="clang --target=wasm32 -O2 -ffreestanding -nostdinc -isystem scripts/wasmShim"
NATIVE="clang -O2 -D_CRT_SECURE_NO_WARNINGS -Wno-deprecated-declarations"

bytes() { llvm-size "$1" | awk 'NR == 2 { print $1 + $2 }'; }

compile() {
	file="$1"; label="$2"
	$WASM -I src/void2d -DVOID_GLES3 -DSOKOL_GLES3 -c "src/void2d/$file" \
		-o "$OUT/$label.wasm.o" 2> "$OUT/$label.wasm.log" \
		|| { echo "FAIL wasm delta: $file did not compile for wasm32 — see $OUT/$label.wasm.log"; failed=1; return; }
	$NATIVE -DVOID_D3D11 -DSOKOL_D3D11 -I src/void2d -c "src/void2d/$file" \
		-o "$OUT/$label.o" 2> "$OUT/$label.log" \
		|| { echo "FAIL wasm delta: $file did not compile natively — see $OUT/$label.log"; failed=1; }
}

compile "batcher.c" "head.batcher"
compile "shaper.c" "on.shaper"
[ "$failed" -eq 0 ] || exit 1

echo "module off: symbols"
MODULE_SYMBOLS='srcZvoid2dZsprite\|void2dGlyphFaceSprite\|void2dGlyphFaceIsSprite\|void2dGlyphSpriteCell\|void2dGlyphSdf\|void2dGlyphOutline\|void2dShape\|kbts_'
for object in "$OUT/head.batcher.o" "$OUT/head.batcher.wasm.o"; do
	if llvm-nm "$object" | grep -q "$MODULE_SYMBOLS"; then
		echo "FAIL wasm delta: the module-off $object names a module symbol"
		failed=1
	fi
done
for object in "$OUT/on.shaper.o" "$OUT/on.shaper.wasm.o"; do
	if ! llvm-nm "$object" | grep -q 'kbts_'; then
		echo "FAIL wasm delta: shaper.c names no kbts_ symbol in $object, so the check above sees nothing"
		failed=1
	fi
done
holders=$(grep -l 'STB_IMAGE_IMPLEMENTATION' src/void2d/*.c src/void2d/*/*.c 2> /dev/null | tr '\n' ' ')
echo "      stb_image implementations under src/void2d: ${holders:-none}"
[ -z "$holders" ] || { echo "FAIL wasm delta: a C unit under src/void2d holds a stb_image implementation: $holders"; failed=1; }

batcher_native=$(bytes "$OUT/head.batcher.o")
batcher_wasm=$(bytes "$OUT/head.batcher.wasm.o")
shaper_native=$(bytes "$OUT/on.shaper.o")
shaper_wasm=$(bytes "$OUT/on.shaper.wasm.o")
echo "default layer: batcher.c $batcher_native B native, $batcher_wasm B wasm32"
echo "module on: shaper.c $shaper_native B native, $shaper_wasm B wasm32"

if [ "$mode" = print ]; then
	printf '  "batcher": { "native": %s, "wasm32": %s },\n' "$batcher_native" "$batcher_wasm"
	printf '  "shaper": { "native": %s, "wasm32": %s }\n' "$shaper_native" "$shaper_wasm"
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
within "batcher.c, wasm32 objects" "$batcher_wasm" "$(recorded batcher wasm32)"
within "batcher.c, native objects" "$batcher_native" "$(recorded batcher native)"
within "shaper, wasm32 objects" "$shaper_wasm" "$(recorded shaper wasm32)"
within "shaper, native objects" "$shaper_native" "$(recorded shaper native)"
exit "$failed"
