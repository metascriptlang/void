#!/bin/bash
# Matched pairs: per round, Void then GPUI back to back for each case, on one Mac in one quiet window.
# usage (tree root, on the Mac): tests/bench/gpuiParity/pairs.sh <rounds> <outDir>; summarise its stdout with tests/bench/gpuiParity/compare.py <savedStdout>
set -e
here=tests/bench/gpuiParity
rounds=$1; out=$2; mkdir -p "$out"
msc build $here/voidEditorTerminal.ms --release --output="$out/voidBench" > "$out/voidBuild.log" 2>&1 || { tail -20 "$out/voidBuild.log"; exit 1; }
$here/buildGpui.sh > "$out/gpuiBuild.log" 2>&1 || { tail -20 "$out/gpuiBuild.log"; exit 1; }
gpui=$HOME/work/gpui-parity/$here/gpui/target/release/current_gpui_bench
echo "msc $(command -v msc) $(grep binary ~/.metascript/BUILD)"; uptime
for r in $(seq 1 "$rounds"); do
	for c in editor terminal; do
		$here/runGui.sh . "$out/void-$c-$r.log" "$out/voidBench" VOID_BENCH_CASE=$c
		BUNDLE_BIN=1 $here/runGui.sh . "$out/gpui-$c-$r.log" "$gpui" GPUI_BENCH_CASE=$c
		echo "round $r $c done $(uptime | sed 's/.*averages: //')"
	done
done
for f in "$out"/void-*.log "$out"/gpui-*.log; do echo "=== $(basename "$f")"; grep -E '^(SAMPLE|CPU_NS_WITH_HARNESS |FRAMEBUFFER|PLATFORM|FAIL|DONE)' "$f" || true; done
