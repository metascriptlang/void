#!/bin/sh
# The shipped form of a --target=js bundle: node: imports stripped, dead code dropped (msc's JS codegen does not
# yet; inbox card js-bundle-carries-all-std), whitespace and syntax minified, identifiers renamed.
#
#   sh scripts/jsMinify.sh <in.js> <out.js>
set -eu

ESBUILD_VERSION=0.28.2
[ $# -eq 2 ] || { echo "usage: jsMinify.sh <in.js> <out.js>" >&2; exit 2; }
in="$1"; out="$2"
[ -f "$in" ] || { echo "jsMinify: $in does not exist" >&2; exit 2; }

stripped="$out.in.js"
sed -E '/^import .* from "node:[a-z_\/]+";\r?$/d' "$in" > "$stripped"
if grep -q 'from "node:' "$stripped"; then
	echo "jsMinify: $in still has a node: import after stripping" >&2
	exit 1
fi
npx --yes "esbuild@$ESBUILD_VERSION" "$stripped" --bundle --format=iife --target=es2022 \
	--minify-whitespace --minify-syntax --minify-identifiers --log-level=warning --outfile="$out"
rm -f "$stripped"
