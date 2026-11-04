#!/bin/bash
# Run a GUI benchmark with a window session from a non-GUI shell (ssh): wraps it in a throwaway .app
# and starts that with `open -W -n`, so the window server connection exists.
# usage: tests/bench/gpuiParity/runGui.sh <treeRoot> <logFile> <binary> [VAR=value ...]
# <binary> is run with <treeRoot> as cwd (BUNDLE_BIN=1: copied into the bundle instead, cwd /); stdout and stderr go to <logFile>.
set -e
root=$(cd "$1" && pwd); log=$2; bin=$(cd "$(dirname "$3")" && pwd)/$(basename "$3"); shift 3
app=/tmp/gpuiParityRun.app
rm -rf "$app" "$log"; mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>run</string>
<key>CFBundleIdentifier</key><string>gpuiParity.run</string><key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><false/></dict></plist>
PL
if [ "$BUNDLE_BIN" = 1 ]; then
	# the binary itself is the bundle executable, so NSHighResolutionCapable=false applies (window scale 1, as GPUI's DPI-1 check needs);
	# cwd is then "/", so this mode is for binaries that need no relative paths
	cp "$bin" "$app/Contents/MacOS/run"
else
	printf '#!/bin/bash\ncd "%s" && exec "%s"\n' "$root" "$bin" > "$app/Contents/MacOS/run"
fi
chmod +x "$app/Contents/MacOS/run"
envs=(); for kv in "$@"; do envs+=(--env "$kv"); done
open -W -n --stdout "$log" --stderr "$log" "${envs[@]}" "$app"
