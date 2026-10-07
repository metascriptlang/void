#!/bin/sh
set -e
cd "$(dirname "$0")/.."
OUT=out/experiments/profilerWeb
mkdir -p "$OUT"
rm -rf "$OUT/off" "$OUT/on"
export MSC_NO_GLOBAL_CACHE=1
rm -rf out/release/.cache

VOID_WEB_ENTRY=tests/experiments/profilerWeb.ms VOID_WEB_DEST="$OUT/off" \
	sh scripts/build-web.sh > "$OUT/off.log" 2>&1 \
	|| { echo "module-off build failed, see $OUT/off.log"; exit 1; }
rm -rf out/release/.cache
VOID_WEB_ENTRY=tests/experiments/profilerWeb.ms VOID_WEB_DEST="$OUT/on" \
	VOID_WEB_MSCFLAGS="-d:voidProfiler" \
	sh scripts/build-web.sh > "$OUT/on.log" 2>&1 \
	|| { echo "module-on build failed, see $OUT/on.log"; exit 1; }

status=0
for backend in wgpu gl; do
	off=$(wc -c < "$OUT/off/$backend/profilerWeb.wasm")
	on=$(wc -c < "$OUT/on/$backend/profilerWeb.wasm")
	echo "WASM $backend off $off on $on delta $((on - off))"
	if [ -f tests/bench/wasmBudget.txt ]; then
		recorded=$(grep -E "^profilerWeb $backend off " tests/bench/wasmBudget.txt | head -1 || true)
		if [ -z "$recorded" ]; then
			echo "BUDGET $backend: no profilerWeb row in tests/bench/wasmBudget.txt"
			continue
		fi
		budgetOff=$(echo "$recorded" | awk '{ print $4 }')
		budgetOn=$(echo "$recorded" | awk '{ print $6 }')
		if [ "$off" -ne "$budgetOff" ]; then
			echo "BUDGET $backend: module off is $off B, recorded $budgetOff B"
			status=1
		elif [ "$on" -gt "$budgetOn" ]; then
			echo "BUDGET $backend: module on is $on B, over the recorded $budgetOn B"
			status=1
		else
			echo "BUDGET $backend: ok"
		fi
	fi
done
exit $status
