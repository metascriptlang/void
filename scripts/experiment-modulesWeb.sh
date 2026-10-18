#!/bin/sh
#   sh scripts/experiment-modulesWeb.sh            shaper, sdf and bidi
#   sh scripts/experiment-modulesWeb.sh shaper     one module
set -e
cd "$(dirname "$0")/.."
ENTRY="${VOID_WEB_ENTRY:-tests/experiments/modulesWeb.ms}"
NAME="$(basename "$ENTRY" .ms)"
OUT="out/experiments/$NAME"
mkdir -p "$OUT"
sh scripts/wasmBudget.test.sh
export MSC_NO_GLOBAL_CACHE=1
modules="${*:-shaper sdf bidi}"

build() {
	label="$1"; flags="$2"
	rm -rf "$OUT/$label" out/release/.cache
	VOID_WEB_ENTRY="$ENTRY" VOID_WEB_DEST="$OUT/$label" \
		VOID_WEB_MSCFLAGS="$flags" VOID_WEB_LOGDIR="$OUT/$label.logs" sh scripts/build-web.sh > "$OUT/$label.log" 2>&1 \
		|| { echo "$label build failed, see $OUT/$label.log"; exit 1; }
}

build off ""
status=0
for module in $modules; do
	case "$module" in
		shaper) flag="-d:voidShaper" ;;
		sdf) flag="-d:voidSdfText" ;;
		bidi) flag="-d:voidBidi" ;;
		colour) flag="-d:voidColourEmoji" ;;
		sprites) flag="-d:voidSprites" ;;
		outline) flag="-d:voidTextOutline" ;;
		*) echo "unknown module $module"; exit 2 ;;
	esac
	build "$module" "$flag"
	for backend in wgpu gl; do
		off=$(wc -c < "$OUT/off/$backend/$NAME.wasm")
		on=$(wc -c < "$OUT/$module/$backend/$NAME.wasm")
		echo "WASM $module $backend off $off on $on delta $((on - off))"
		if [ "$on" -le "$off" ]; then
			echo "FAIL $module $backend: the module on is not larger than off, so the flag or the call path links nothing"
			status=1
		fi
		if [ -f tests/bench/wasmBudget.txt ]; then
			recorded=$(grep -E "^$NAME-$module $backend off " tests/bench/wasmBudget.txt | head -1 || true)
			if [ -z "$recorded" ]; then
				echo "BUDGET $module $backend: no $NAME-$module row in tests/bench/wasmBudget.txt"
				continue
			fi
			if ! printf '%s\n' "$recorded" | tr -d '\r' | grep -qE "^$NAME-$module $backend off [0-9]+ on [0-9]+$"; then
				echo "FAIL $module $backend: unreadable $NAME budget row"
				status=1
				continue
			fi
			budgetOff=$(echo "$recorded" | awk '{ print $4 }' | tr -d '\r')
			budgetOn=$(echo "$recorded" | awk '{ print $6 }' | tr -d '\r')
			if ! [ "$budgetOff" -ge 0 ] 2>/dev/null || ! [ "$budgetOn" -ge 0 ] 2>/dev/null; then
				echo "FAIL $module $backend: $NAME budget bytes exceed the integer range"
				status=1
				continue
			fi
			if [ "$off" -ne "$budgetOff" ]; then
				echo "BUDGET $module $backend: module off is $off B, recorded $budgetOff B"
				status=1
			elif [ "$on" -gt "$budgetOn" ]; then
				echo "BUDGET $module $backend: module on is $on B, over the recorded $budgetOn B"
				status=1
			else
				echo "BUDGET $module $backend: ok"
			fi
		fi
	done
done
exit $status
