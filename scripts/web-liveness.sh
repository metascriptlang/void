#!/bin/sh
# Load the built web demo in headless Chrome, per backend, and screenshot its canvas once it has
# presented frames (scripts/webPresent.mjs).
#
# This is a LIVENESS check, not conformance. It says "the wasm module started, got a device,
# presented frames and they are not one colour"; it does not say the pixels match the D3D11
# goldens, because the WebGPU build has no readback yet (tests/PENDING.md backend:webgpu).
# WebGL2 conformance is scripts/golden-web.sh.
#
# WebGPU skips only when requestAdapter returns null; docs/TESTING.md says why the 2026-09-20
# "no adapter" reading was a screenshot taken before anything presented.
set -e
cd "$(dirname "$0")/.."

PORT="${VOID_WEB_PORT:-8731}"
SHOTS=out/webshot
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"

[ -f web/gl/main2d.wasm ] || { echo "SKIP web liveness: run scripts/build-web.sh first"; exit 0; }
[ -x "$CHROME" ] || { echo "SKIP web liveness: no Chrome at $CHROME"; exit 0; }
command -v python >/dev/null || { echo "SKIP web liveness: no python to serve web/"; exit 0; }
node --test scripts/webPresent.test.mjs > out/webPresent.test.log 2>&1 \
	|| { echo "FAIL  web liveness: scripts/webPresent.test.mjs — see out/webPresent.test.log"; exit 1; }

mkdir -p "$SHOTS"
( cd web && exec python -m http.server "$PORT" >/dev/null 2>&1 ) &
server=$!
# Before the sleep, not after: a Ctrl-C in that window would otherwise leave the server
# bound to the port and the next run would talk to the orphan.
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 2

# node on Windows does not read an MSYS-style path.
chrome=$(cygpath -m "$CHROME" 2>/dev/null || echo "$CHROME")
failed=0
for backend in gl wgpu; do
	CHROME="$chrome" node scripts/webPresent.mjs "web liveness $backend" \
		"http://localhost:$PORT/void2d.html?$backend" "$SHOTS/$backend.png" || failed=1
done
exit "$failed"
