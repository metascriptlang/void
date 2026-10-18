#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
repo="$PWD"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tests/bench"
for backend in wgpu gl; do
	mkdir -p "$tmp/blobs/off/$backend" "$tmp/blobs/shaper/$backend"
	printf 'abcd' > "$tmp/blobs/off/$backend/modulesWeb.wasm"
	printf 'abcdef' > "$tmp/blobs/shaper/$backend/modulesWeb.wasm"
done
{
	printf '%s\n' 'set -eu' 'OUT="$PWD/blobs"' 'modules=shaper' 'build() { :; }'
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
cr=$(printf '\r')
check crlf 0 "modulesWeb-shaper wgpu off 4 on 6$cr"
echo 'PASS wasm budget data: valid LF/CRLF, wrong bytes and malformed rows; comparison only, no builds'
