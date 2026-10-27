#!/bin/sh
# The frame time of a Bevy stress-test log and of a Void bench log alike: both print
# bevy_diagnostic's `frame_time: <ema>ms (avg <mean of 120 frames>ms)` once a second
# (docs/VOID3D.md "Bevy comparison bench"). Skips the first WARM lines (default 5), then prints
# the line count and the median and maximum of the per-second averages.
#
#   sh scripts/frameTime.sh <log> [warm]
set -eu
LOG="$1"; WARM="${2:-5}"
sed -n 's/.*frame_time *: *[0-9.eE+-]*ms (avg \([0-9.eE+-]*\)ms).*/\1/p' "$LOG" |
	tail -n +"$((WARM + 1))" | sort -g |
	awk '{ v[NR] = $1 } END {
		if (NR == 0) { print "frameTime: no frame_time lines after the warm-up" > "/dev/stderr"; exit 1 }
		m = NR % 2 ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
		printf "lines %d median %.6f max %.6f\n", NR, m, v[NR]
	}'
