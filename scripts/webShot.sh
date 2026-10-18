#!/bin/sh
# Sourced by scripts/web-liveness.sh; scripts/webShot.test.sh pins it.

# Headless Chrome can write its --screenshot and then never exit (measured 2026-10-18: the gl
# shot wrote its PNG at 2 s and lived past 120 s), so a shot ends at its PNG, not at Chrome's exit.
children() {
	if [ -r "/proc/$1/winpid" ]; then
		ps | awk -v parent="$1" 'NR > 1 && $2 == parent { print $1 }'
	else
		pgrep -P "$1" || true
	fi
}

killTree() {
	for child in $(children "$1"); do
		killTree "$child"
	done
	winpid=$(cat "/proc/$1/winpid" 2> /dev/null || true)
	if [ -n "$winpid" ]; then
		taskkill //T //F //PID "$winpid" > /dev/null 2>&1 || true
	fi
	kill -KILL "$1" 2> /dev/null || true
}

# waitShot <pid> <png> <seconds>: 0 the shot exited, 1 it wrote the PNG and was stopped,
# 2 it wrote none within the bound and was stopped.
waitShot() {
	elapsed=0
	last=-1
	while kill -0 "$1" 2> /dev/null; do
		if [ -s "$2" ]; then
			size=$(wc -c < "$2")
			if [ "$size" -eq "$last" ]; then
				killTree "$1"
				wait "$1" 2> /dev/null || true
				return 1
			fi
			last=$size
		fi
		if [ "$elapsed" -ge "$3" ]; then
			killTree "$1"
			wait "$1" 2> /dev/null || true
			return 2
		fi
		sleep 1
		elapsed=$((elapsed + 1))
	done
	return 0
}
