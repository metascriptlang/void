#!/bin/sh
# The linked wasm of one entry with each text module off and on, per backend (docs/VOID2D.md P6,
# guardrail 6). The entry links no node.ms, which is what keeps Yoga out of it
# (tests/PENDING.md wasm:budget); a recorded row in tests/bench/wasmBudget.txt is checked when there
# is one:  modulesWeb-<module> <backend> off <bytes> on <bytes>
#
#   sh scripts/experiment-modulesWeb.sh            shaper and sdf
#   sh scripts/experiment-modulesWeb.sh shaper     one module
set -e
cd "$(dirname "$0")/.."
OUT=out/experiments/modulesWeb
mkdir -p "$OUT"
export MSC_NO_GLOBAL_CACHE=1
modules="${*:-shaper sdf}"

build() {
	label="$1"; flags="$2"
	rm -rf "$OUT/$label" out/release/.cache
	VOID_WEB_ENTRY=tests/experiments/modulesWeb.ms VOID_WEB_DEST="$OUT/$label" \
		VOID_WEB_MSCFLAGS="$flags" VOID_WEB_LOGDIR="$OUT/$label.logs" sh scripts/build-web.sh > "$OUT/$label.log" 2>&1 \
		|| { echo "$label build failed, see $OUT/$label.log"; exit 1; }
}

build off ""
status=0
for module in $modules; do
	case "$module" in
		shaper) flag="-d:voidShaper" ;;
		sdf) flag="-d:voidSdfText" ;;
		*) echo "unknown module $module"; exit 2 ;;
	esac
	build "$module" "$flag"
	for backend in wgpu gl; do
		off=$(wc -c < "$OUT/off/$backend/modulesWeb.wasm")
		on=$(wc -c < "$OUT/$module/$backend/modulesWeb.wasm")
		echo "WASM $module $backend off $off on $on delta $((on - off))"
		if [ "$on" -le "$off" ]; then
			echo "FAIL $module $backend: the module on is not larger than off, so the flag or the call path links nothing"
			status=1
		fi
		if [ -f tests/bench/wasmBudget.txt ]; then
			recorded=$(grep -E "^modulesWeb-$module $backend off " tests/bench/wasmBudget.txt | head -1 || true)
			if [ -z "$recorded" ]; then
				echo "BUDGET $module $backend: no modulesWeb-$module row in tests/bench/wasmBudget.txt"
				continue
			fi
			budgetOff=$(echo "$recorded" | awk '{ print $4 }' | tr -d '\r')
			budgetOn=$(echo "$recorded" | awk '{ print $6 }' | tr -d '\r')
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
