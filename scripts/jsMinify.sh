#!/bin/sh
# The shipped form of a --target=js bundle: node: imports stripped, dead code dropped (msc's JS codegen does not
# yet; inbox card js-bundle-carries-all-std), whitespace and syntax minified, identifiers renamed.
#
#   sh scripts/jsMinify.sh [--keep-names] <in.js> <out.js>
#
# --keep-names leaves top-level names alone, because tests/js/*.mjs stub door functions by name.
set -eu

ESBUILD_VERSION=0.28.2
names=--minify-identifiers
if [ "${1:-}" = --keep-names ]; then
	names=
	shift
fi
[ $# -eq 2 ] || { echo "usage: jsMinify.sh [--keep-names] <in.js> <out.js>" >&2; exit 2; }
in="$1"; out="$2"
[ -f "$in" ] || { echo "jsMinify: $in does not exist" >&2; exit 2; }

stripped="$out.in.js"
sed -E '/^import .* from "node:[a-z_\/]+";\r?$/d' "$in" > "$stripped"
if grep -q 'from "node:' "$stripped"; then
	echo "jsMinify: $in still has a node: import after stripping" >&2
	exit 1
fi
npx --yes "esbuild@$ESBUILD_VERSION" "$stripped" --bundle --format=iife --target=es2022 \
	--minify-whitespace --minify-syntax $names --log-level=warning --outfile="$out"
rm -f "$stripped"
