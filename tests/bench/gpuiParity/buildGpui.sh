#!/bin/bash
# Build the GPUI side on the Mac. Run from a void tree root; needs ~/work/zed-b961 at b961b4950febbc050081554bafe976b5d1b93f39.
# Stages the crate + the two fonts under ~/work/gpui-parity in the tree's own layout, so the include_bytes paths hold.
set -e
src=tests/bench/gpuiParity/gpui
dst=$HOME/work/gpui-parity
mkdir -p "$dst/tests/bench/gpuiParity" "$dst/assets" "$dst/tests/fonts"
rsync -a --delete --exclude target --exclude Cargo.lock "$src" "$dst/tests/bench/gpuiParity/"
cp assets/font.ttf "$dst/assets/"; cp tests/fonts/cascadiaSubset.ttf "$dst/tests/fonts/"
cd "$dst/$src"
[ -f Cargo.lock ] || cp "$HOME/work/zed-b961/Cargo.lock" .
exec "$HOME/.cargo/bin/cargo" build --release
