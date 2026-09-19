#!/bin/sh
# Build the emcc/em++/emar/emranlib shims into out/emcc-shim/ (see scripts/emccShim.c for
# why Windows needs them at all). Idempotent; scripts/build-web.sh calls it.
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) ;;
	*) echo "emcc shim: not needed on $(uname -s)"; exit 0 ;;
esac

CC="${SHIM_CC:-clang}"
command -v "$CC" >/dev/null || { echo "emcc shim: no $CC on PATH"; exit 1; }

mkdir -p out/emcc-shim
"$CC" -O2 -D_CRT_SECURE_NO_WARNINGS -o out/emcc-shim/emcc.exe scripts/emccShim.c
for tool in em++ emar emranlib; do
	cp out/emcc-shim/emcc.exe "out/emcc-shim/$tool.exe"
done
echo "emcc shim: out/emcc-shim/{emcc,em++,emar,emranlib}.exe"
