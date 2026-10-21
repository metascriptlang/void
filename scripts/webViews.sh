#!/bin/sh
# Void's web host views (docs/EMBED.md "Web"): src/examples/webViews.ms built for both browser
# backends, then started, stopped and started again on a second canvas in one document by
# scripts/webViews.mjs in headless Chrome.
#
#   sh scripts/webViews.sh          build, then run both backends
#   sh scripts/webViews.sh --run    run what out/webViews already holds
set -e
cd "$(dirname "$0")/.."
PORT="${VOID_WEB_PORT:-8761}"
OUT=out/webViews
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
export CHROME

[ -x "$CHROME" ] || { echo "SKIP webViews: no Chrome at $CHROME"; exit 0; }
command -v python >/dev/null || { echo "SKIP webViews: no python to serve $OUT"; exit 0; }

if [ "${1:-}" != "--run" ]; then
	VOID_WEB_ENTRY=src/examples/webViews.ms VOID_WEB_DEST="$OUT" \
		VOID_WEB_PRELOAD="--preload-file assets/test.png" \
		sh scripts/build-web.sh > "$OUT.build.log" 2>&1 \
		|| { echo "FAIL webViews: the entry does not build — see $OUT.build.log"; exit 1; }
	cp tests/web/views.html "$OUT/wgpu/views.html"
	cp tests/web/views.html "$OUT/gl/views.html"
	root=$(pwd)
	outside=$(mktemp -d)
	if (cd "$outside" && "${MSC:-msc}" build "$root/src/examples/webViews.ms" --os=emcc -d:webgl2 \
		--output="$outside/webViews.js" > "$root/$OUT.outside.log" 2>&1); then
		echo "PASS webViews builds from outside the repo"
	else
		echo "FAIL webViews does not build from outside the repo — see $OUT.outside.log"
	fi
	rm -rf "$outside"
fi

( cd "$OUT" && exec python -m http.server "$PORT" > /dev/null 2>&1 ) &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
sleep 2
node scripts/webViews.mjs "http://127.0.0.1:$PORT" wgpu gl
