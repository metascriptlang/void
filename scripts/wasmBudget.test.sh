#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
repo="$PWD"
if [ "${1:-}" = --record ]; then
	recordFile="${2:-tests/bench/wasmBudget.txt}"
	awk '
		BEGIN {
			split("modulesWeb main2d", entries)
			split("shaper sdf bidi colour sprites outline", modules)
			split("wgpu gl", backends)
			for (e in entries) for (m in modules) for (b in backends)
				expected[entries[e] "-" modules[m] " " backends[b]] = 1
		}
		{ sub(/\r$/, "") }
		NF == 0 || $1 == "profile" || $1 == "measured" { next }
		{
			key = $1 " " $2
			if (!(key in expected) || ++seen[key] != 1 || NF != 6 ||
				$0 != $1 " " $2 " off " $4 " on " $6 ||
				$4 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ || $4 <= 0 || $6 <= $4) bad = 1
			split($1, parts, "-")
			group = parts[1] " " $2
			if ((group in off) && off[group] != $4) bad = 1
			off[group] = $4
		}
		END {
			for (key in expected) if (seen[key] != 1) bad = 1
			if (bad) { print "FAIL linked wasm budget declarations: malformed, missing, duplicate or mixed off baseline"; exit 1 }
		}
	' "$recordFile"
	while read -r key backend offTag off onTag on rest || [ -n "$key" ]; do
		case "$key" in modulesWeb-*|main2d-*)
			on=$(printf '%s' "$on" | tr -d '\r')
			if ! [ "$off" -ge 0 ] 2>/dev/null || ! [ "$on" -ge 0 ] 2>/dev/null; then
				echo 'FAIL linked wasm budget declarations: byte count exceeds the integer range'
				exit 1
			fi
		;; esac
	done < "$recordFile"
	echo 'PASS linked wasm budget declarations: 24 rows, two entries/six modules/two backends; not rebuilt'
	exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tests/bench"
for backend in wgpu gl; do
	mkdir -p "$tmp/blobs/off/$backend" "$tmp/blobs/shaper/$backend"
	printf 'abcd' > "$tmp/blobs/off/$backend/modulesWeb.wasm"
	printf 'abcdef' > "$tmp/blobs/shaper/$backend/modulesWeb.wasm"
done
{
	printf '%s\n' 'set -eu' 'OUT="$PWD/blobs"' 'NAME=modulesWeb' 'modules=shaper' 'build() { :; }'
	awk '/^status=0$/ { found=1 } found { print } END { if (!found) exit 1 }' \
		"$repo/scripts/experiment-modulesWeb.sh"
} > "$tmp/compare.sh"
check() {
	name=$1; want=$2; row=$3
	printf '%s\n' "$row" 'modulesWeb-shaper gl off 4 on 6' > "$tmp/tests/bench/wasmBudget.txt"
	if (cd "$tmp" && sh compare.sh) > "$tmp/$name.out" 2> "$tmp/$name.err"; then
		got=0
	else
		got=$?
	fi
	if [ "$got" -ne "$want" ]; then
		echo "FAIL wasm budget data $name: exit $got, expected $want"
		return 1
	fi
}
check good 0 'modulesWeb-shaper wgpu off 4 on 6'
check wrongOff 1 'modulesWeb-shaper wgpu off 5 on 6'
check overOn 1 'modulesWeb-shaper wgpu off 4 on 5'
check malformed 1 'modulesWeb-shaper wgpu off nope on 6'
check missingNumber 1 'modulesWeb-shaper wgpu off  on 6'
check extraField 1 'modulesWeb-shaper wgpu off 4 on 6 ignored'
check oversizedOff 1 'modulesWeb-shaper wgpu off 999999999999999999999999999999 on 6'
check oversizedOn 1 'modulesWeb-shaper wgpu off 4 on 999999999999999999999999999999'
cr=$(printf '\r')
check crlf 0 "modulesWeb-shaper wgpu off 4 on 6$cr"
for entry in modulesWeb main2d; do
	for module in shaper sdf bidi colour sprites outline; do
		for backend in wgpu gl; do
			printf '%s-%s %s off 4 on 6\n' "$entry" "$module" "$backend"
		done
	done
done > "$tmp/complete.txt"
checkRecord() {
	name=$1; want=$2
	if sh "$repo/scripts/wasmBudget.test.sh" --record "$tmp/$name.txt" > "$tmp/$name.record"; then
		got=0
	else
		got=$?
	fi
	[ "$got" -eq "$want" ] || { echo "FAIL wasm budget record $name: exit $got, expected $want"; exit 1; }
}
checkRecord complete 0
cp "$tmp/complete.txt" "$tmp/duplicate.txt"
head -1 "$tmp/complete.txt" >> "$tmp/duplicate.txt"
checkRecord duplicate 1
tail -n +2 "$tmp/complete.txt" > "$tmp/missing.txt"
checkRecord missing 1
sed '1s/off 4/off nope/' "$tmp/complete.txt" > "$tmp/malformed.txt"
checkRecord malformed 1
sed '1s/off 4/off 5/' "$tmp/complete.txt" > "$tmp/mixed.txt"
checkRecord mixed 1
sed '1s/on 6/on 999999999999999999999999999999/' "$tmp/complete.txt" > "$tmp/oversized.txt"
checkRecord oversized 1
echo 'PASS wasm budget data: 9 comparison cases and 6 declaration cases; no builds'
