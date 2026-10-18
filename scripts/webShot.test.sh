#!/bin/sh
set -e
cd "$(dirname "$0")/.."
. scripts/webShot.sh

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
broken=0

stub() {
	sh -c "$1" &
	pid=$!
}

check() {
	if [ "$2" != "$3" ]; then
		echo "FAIL  webShot: $1: $2, expected $3"
		broken=1
	fi
}

alive() {
	if [ -s "$1" ] && kill -0 "$(cat "$1")" 2> /dev/null; then echo alive; else echo gone; fi
}

stub "sleep 300 & echo \$! > '$dir/child1'; wait"
start=$(date +%s)
status=0
waitShot "$pid" "$dir/never.png" 2 || status=$?
check "a shot that writes nothing returns" "$status" 2
check "it is stopped after the bound, seconds" "$(( $(date +%s) - start <= 5 ))" 1
check "its child process is" "$(alive "$dir/child1")" gone

stub "printf png > '$dir/hangs.png'; sleep 300 & echo \$! > '$dir/child2'; wait"
status=0
waitShot "$pid" "$dir/hangs.png" 30 || status=$?
check "a shot that writes its PNG and hangs returns" "$status" 1
check "its child process is" "$(alive "$dir/child2")" gone

stub "printf png > '$dir/exits.png'"
status=0
waitShot "$pid" "$dir/exits.png" 30 || status=$?
check "a shot that exits returns" "$status" 0

[ "$broken" -eq 0 ] || exit 1
echo "PASS  webShot: a hung shot is stopped at its PNG or its bound, with its process tree"
