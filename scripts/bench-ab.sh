#!/bin/sh
# Interleaved A/B of the bench milliseconds; the protocol and why load is sampled on both sides
# of a run are docs/TESTING.md "T4". AB_LOAD_LIMIT (default 25 %) marks a pair NOISY,
# AB_MIN_CLEAN (default 5) is the fewest clean pairs a verdict is given on.
#
#   sh scripts/bench-ab.sh <tree A> <tree B> [pairs] [scene...]
#
# Each tree must hold out/bench<Scene>.exe already built with --release; each binary runs from
# its own tree so its assets resolve. AB_DIR_A / AB_DIR_B name another directory for that side's
# exes (absolute, or relative to its tree), so one tree can hold one build per backend.
# AB_RAW=<file> also keeps every bench row of every run there and prints the all-row table:
# the median of the clean pairs per row, `.ms` rows RED when B is more than AB_TOL percent
# (default 3) slower than A, a counter that differs DIFF, each row with its flow (scripts/benchFlow.awk).
# AB_LABEL tags the rows (the backend).
# AB_RUN is a command prefix for the exe (a WSL wrapper), so a side can run elsewhere than Windows.
set -eu
A="$1"; B="$2"; PAIRS="${3:-6}"
shift 2; [ $# -gt 0 ] && shift
SCENES="${*:-Ui Sprites}"
LIMIT="${AB_LOAD_LIMIT:-25}"
MIN_CLEAN="${AB_MIN_CLEAN:-5}"
ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT

load() {
	if [ "$(uname -s)" = Darwin ]; then
		top -l 2 -n 0 -s 1 | awk '/CPU usage/ { idle = $7 } END { sub(/%/, "", idle); printf "%.1f\n", 100 - idle }'
		return
	fi
	powershell.exe -NoProfile -Command \
		"(1..3 | ForEach-Object { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue } | Measure-Object -Average).Average.ToString('F1')" \
		| tr -d '\r'
}

one() {
	tree="$1"; scene="$2"; side="$3"; pair="$4"
	if [ "$side" = A ]; then suffix="${AB_SUFFIX_A:-}"; else suffix="${AB_SUFFIX_B:-}"; fi
	if [ "$side" = A ]; then dir="${AB_DIR_A:-out}"; else dir="${AB_DIR_B:-out}"; fi
	before=$(load)
	out=$(cd "$tree" && ${AB_RUN:-} "$dir/bench$scene$suffix.exe" 2>/dev/null | tr -d '\r')
	after=$(load)
	ms=$(printf '%s\n' "$out" | sed -n 's/^[a-z]*\.present\.ms //p')
	if [ -n "${AB_RAW:-}" ]; then
		printf '%s\n' "$out" | awk -v l="${AB_LABEL:-}" -v s="$scene" -v w="$side" -v p="$pair" -v b="${before:-x}" -v a="${after:-x}" \
			'/^[A-Za-z0-9]+\.[A-Za-z0-9.]+ -?[0-9.eE+-]+$/ { print l "\t" s "\t" w "\t" p "\t" b "\t" a "\t" $1 "\t" $2 }' >> "$AB_RAW"
	fi
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

[ -z "${AB_RAW:-}" ] || awk -F'	' -v limit="$LIMIT" -v minClean="$MIN_CLEAN" -v tol="${AB_TOL:-3}" -f "$(dirname "$0")/benchFlow.awk" -e '
	function median(key,   n, i, j, x, v) {
		n = cnt[key]
		for (i = 1; i <= n; i++) v[i] = val[key, i]
		for (i = 2; i <= n; i++) { x = v[i]; j = i - 1; while (j >= 1 && v[j] > x) { v[j + 1] = v[j]; j-- } v[j + 1] = x }
		return n % 2 ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
	}
	function number(v) { return v ~ /^[0-9]+(\.[0-9]+)?$/ }
	{
		pk = $1 SUBSEP $2 SUBSEP $4
		seenSide[pk, $3] = 1
		if (!number($5) || !number($6) || $5 > limit || $6 > limit) noisy[pk] = 1
		rowKey[pk, $3, $7] = $8
		if (!(pk in listed)) { listed[pk] = 1; pairs[++np] = pk }
		rowsOf[pk] = rowsOf[pk] SUBSEP $7 SUBSEP $3
	}
	END {
		for (i = 1; i <= np; i++) {
			pk = pairs[i]; split(pk, p, SUBSEP); sc = p[1] SUBSEP p[2]
			if (noisy[pk] || !seenSide[pk, "A"] || !seenSide[pk, "B"]) continue
			clean[sc]++
			n = split(rowsOf[pk], r, SUBSEP)
			for (j = 2; j <= n; j += 2) {
				m = r[j]; w = r[j + 1]; key = sc SUBSEP m SUBSEP w
				if (!((sc SUBSEP m) in order)) { order[sc SUBSEP m] = 1; keys[++nk] = sc SUBSEP m }
				val[key, ++cnt[key]] = rowKey[pk, w, m]
			}
		}
		printf "%-6s %-8s %-34s %14s %14s %9s  %s\n", "label", "flow", "metric", "A", "B", "delta %", "verdict"
		red = 0; same = 0
		for (i = 1; i <= nk; i++) {
			split(keys[i], q, SUBSEP); sc = q[1] SUBSEP q[2]; m = q[3]
			if (clean[sc] < minClean) { if (!(sc in skipped)) { skipped[sc] = 1; printf "%s %s: %d clean pairs, too few for the table\n", q[1], q[2], clean[sc] } continue }
			ka = keys[i] SUBSEP "A"; kb = keys[i] SUBSEP "B"
			if (!(ka in cnt) || !(kb in cnt)) { printf "%-6s %-8s %-34s %14s %14s %9s  ONLY-%s\n", q[1], flow(m), m, (ka in cnt) ? median(ka) : "-", (kb in cnt) ? median(kb) : "-", "-", (ka in cnt) ? "A" : "B"; continue }
			a = median(ka); b = median(kb)
			d = (a == 0) ? (b == 0 ? 0 : 100) : (b - a) / a * 100
			if (m ~ /\.ms$/) verdict = (d > tol) ? "RED" : "ok"
			else verdict = (a == b) ? "same" : "DIFF"
			if (verdict == "RED") red++
			if (verdict == "same") { same++; continue }
			printf "%-6s %-8s %-34s %14.4g %14.4g %+8.1f%%  %s\n", q[1], flow(m), m, a, b, d, verdict
		}
		printf "(%d counter rows identical on both sides, not listed; tolerance %s %% on .ms rows)\nRED rows: %d\n", same, tol, red
	}' "$AB_RAW"
