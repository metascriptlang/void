#!/bin/sh
# Interleaved A/B of the bench milliseconds; the protocol and why load is sampled on both sides
# of a run are docs/TESTING.md "T4". AB_LOAD_LIMIT (default 25 %) marks a pair NOISY,
# AB_MIN_CLEAN (default 5) is the fewest clean pairs a verdict is given on.
#
#   sh scripts/bench-ab.sh <tree A> <tree B> [pairs] [scene...]
#
# Each tree must hold out/bench<Scene>.exe already built with --release; each binary runs from
# its own tree so its assets resolve.
set -eu
A="$1"; B="$2"; PAIRS="${3:-6}"
shift 2; [ $# -gt 0 ] && shift
SCENES="${*:-Ui Sprites}"
LIMIT="${AB_LOAD_LIMIT:-25}"
MIN_CLEAN="${AB_MIN_CLEAN:-5}"
ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT

load() {
	powershell.exe -NoProfile -Command \
		"(1..3 | ForEach-Object { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue } | Measure-Object -Average).Average.ToString('F1')" \
		| tr -d '\r'
}

one() {
	tree="$1"; scene="$2"; side="$3"; pair="$4"
	before=$(load)
	ms=$(cd "$tree" && "./out/bench$scene.exe" 2>/dev/null | sed -n 's/^[a-z]*\.present\.ms //p' | tr -d '\r')
	after=$(load)
	echo "AB $scene $side pair $pair present.ms ${ms:-missing} load ${before:-missing} ${after:-missing}" \
		| tee -a "$ROWS"
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

awk -v limit="$LIMIT" -v minClean="$MIN_CLEAN" '
	function number(v) { return v ~ /^[0-9]+(\.[0-9]+)?$/ }
	{
		key = $2 " " $5; seen[key] = $2 " " $5
		if (NF != 10 || !number($7) || !number($9) || !number($10)) {
			broken[key] = 1
			printf "AB %s: pair %s is BROKEN, left out: %s\n", $2, $5, $0
			next
		}
		ms[key, $3] = $7
		if ($9 > limit || $10 > limit) noisy[key] = 1
	}
	END {
		for (key in seen) {
			split(seen[key], part, " ")
			scene = part[1]
			if (key in broken) { brokenCount[scene]++; continue }
			if (key in noisy) { noisyCount[scene]++; continue }
			n = ++clean[scene]
			a[scene, n] = ms[key, "A"]; b[scene, n] = ms[key, "B"]
		}
		for (key in seen) { split(seen[key], part, " "); scenes[part[1]] = 1 }
		for (scene in scenes) {
			n = clean[scene] + 0
			if (n < minClean) {
				printf "AB %s: %d clean pairs of %d (limit %s %%, %d broken), too few for a verdict\n", \
					scene, n, n + noisyCount[scene] + brokenCount[scene], limit, brokenCount[scene]
				continue
			}
			for (side = 0; side < 2; side++) {
				for (i = 1; i <= n; i++) v[i] = side == 0 ? a[scene, i] : b[scene, i]
				for (i = 2; i <= n; i++) { x = v[i]; j = i - 1; while (j >= 1 && v[j] > x) { v[j + 1] = v[j]; j-- } v[j + 1] = x }
				median[side] = n % 2 ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
				low[side] = v[1]; high[side] = v[n]
			}
			printf "AB %s: A %.2f ms (%.2f-%.2f), B %.2f ms (%.2f-%.2f), %d clean pairs, %d noisy (limit %s %%), %d broken\n", \
				scene, median[0], low[0], high[0], median[1], low[1], high[1], n, noisyCount[scene] + 0, limit, \
				brokenCount[scene] + 0
		}
	}' "$ROWS"
