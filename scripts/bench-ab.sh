#!/bin/sh
# Interleaved A/B of the bench milliseconds (docs/TESTING.md "T4"): the bench binaries of two
# trees run alternately, pair by pair, so load drift lands on both sides. CPU load is sampled
# before every run and printed with it, because a millisecond row means nothing without it.
#
#   sh scripts/bench-ab.sh <tree A> <tree B> [pairs] [scene...]
#
# Each tree must hold out/bench<Scene>.exe already built with --release; each binary runs from
# its own tree so its assets resolve.
set -eu
A="$1"; B="$2"; PAIRS="${3:-6}"
shift 2; [ $# -gt 0 ] && shift
SCENES="${*:-Ui Sprites}"

load() {
	powershell.exe -NoProfile -Command \
		"(1..3 | ForEach-Object { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue } | Measure-Object -Average).Average.ToString('F1')" \
		| tr -d '\r'
}

one() {
	tree="$1"; scene="$2"; side="$3"; pair="$4"
	cpu=$(load)
	ms=$(cd "$tree" && "./out/bench$scene.exe" 2>/dev/null | sed -n 's/^[a-z]*\.present\.ms //p' | tr -d '\r')
	echo "AB $scene $side pair $pair present.ms $ms load $cpu"
}

for scene in $SCENES; do
	pair=1
	while [ "$pair" -le "$PAIRS" ]; do
		if [ $((pair % 2)) -eq 1 ]; then
			one "$A" "$scene" A "$pair"; one "$B" "$scene" B "$pair"
		else
			one "$B" "$scene" B "$pair"; one "$A" "$scene" A "$pair"
		fi
		pair=$((pair + 1))
	done
done
