#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tmp
work=$(mktemp -d out/tmp/oracleIds.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
fails=0

expect_error() {
	name=$1
	body=$2
	expected=$3
	printf '%b' "$body" > "$work/$name.cases"
	status=0
	sh scripts/oracle.sh check "$work/$name.cases" > "$work/$name.log" 2>&1 || status=$?
	if [ "$status" -eq 2 ] && grep -Fxq "$expected" "$work/$name.log"; then
		printf 'PASS oracle IDs: %s\n' "$name"
	else
		printf 'FAIL oracle IDs: %s (exit %s)\n' "$name" "$status" >&2
		head -3 "$work/$name.log" >&2
		fails=$((fails + 1))
	fi
}

expect_error uppercase 'case faceA0 tol=0\n' "oracle: invalid case ID 'faceA0'"
expect_error duplicate 'case same tol=0\ncase same tol=0\n' "oracle: duplicate case ID 'same'"
expect_error valid 'case safe-id-0 tol=0\n' \
	"oracle: no snapshot at $work/valid.snapshot (run regen)"
[ "$fails" -eq 0 ]
