#!/bin/sh
set -e
cd "$(dirname "$0")/../.."
HEAPS="${HEAPS:-$HOME/projects/heaps}"
mkdir -p out/tmp/h2dOracle
haxe -cp tests/oracle/h2d -cp "$HEAPS" -lib format -main Oracle -js out/tmp/h2dOracle/oracle.js -D js-es=6
node out/tmp/h2dOracle/oracle.js tests/oracle/h2d.json "$(git -C "$HEAPS" rev-parse --short HEAD)"
echo "wrote tests/oracle/h2d.json from Heaps $(git -C "$HEAPS" rev-parse --short HEAD)"
