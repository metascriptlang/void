#!/bin/sh
# Rebuild src/sokol/sokol.o, the Metal implementation unit gpu.ms @links on macOS.
# Run it after every sokol pin bump: msc links the .o as it is and never recompiles it.
set -e
cd "$(dirname "$0")/.."

case "$(uname -s)" in
	Darwin) ;;
	*) echo "sokol.o: only macOS links it, nothing to build on $(uname -s)"; exit 0 ;;
esac

CC="${CC:-clang}"
[ -f deps/sokol/sokol_gfx.h ] || { echo "sokol.o: deps/sokol is missing, run sh setup.sh first"; exit 1; }

"$CC" -c -fobjc-arc -O2 -Ideps/sokol src/sokol/sokol.m -o src/sokol/sokol.o
echo "sokol.o: built from src/sokol/sokol.m against deps/sokol @ $(git -C deps/sokol rev-parse --short HEAD)"
