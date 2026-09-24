#!/bin/sh
# Guardrail 9 for WebGL2 (docs/TESTING.md): the golden runner built for the browser, every scene
# captured in headless Chrome through scripts/webGolden.mjs, judged against the D3D11 goldens
# under the cross-backend bound.
#
#   sh scripts/golden-web.sh            build, capture, compare
#   sh scripts/golden-web.sh --compare  compare what is already in out/golden/webgl2/
set -e
cd "$(dirname "$0")/.."
MSC="${MSC:-msc}"
PORT="${VOID_WEB_PORT:-8741}"
OUT=out/web-golden

if [ "${1:-}" != "--compare" ]; then
	rm -rf "$OUT" out/golden/webgl2
	VOID_WEB_ENTRY=tests/golden/runner.ms VOID_WEB_DEST="$OUT" VOID_WEB_BACKENDS=gl \
		VOID_WEB_PRELOAD="--preload-file assets --preload-file tests/fonts" \
		sh scripts/build-web.sh > out/golden-web-build.log 2>&1 \
		|| { echo "FAIL the web runner does not build — see out/golden-web-build.log"; exit 1; }
	cp tests/golden/web/runner.html "$OUT/gl/runner.html"

	[ -x out/goldenRunner.exe ] || "$MSC" build tests/golden/runner.ms --output=out/goldenRunner.exe > /dev/null 2>&1
	VOID_SCENE_LIST=1 out/goldenRunner.exe > out/web-golden/scenes.tsv

	( cd "$OUT/gl" && exec python -m http.server "$PORT" > /dev/null 2>&1 ) &
	server=$!
	trap 'kill "$server" 2>/dev/null || true' EXIT
	sleep 2
	node scripts/webGolden.mjs "http://127.0.0.1:$PORT/runner.html" out/web-golden/scenes.tsv webgl2 \
		| tee out/golden-web-capture.log | grep -E '^(FAIL|SKIP|EXCEPTION)' || true
	echo "captured $(grep -c '^CAPTURED' out/golden-web-capture.log) of $(wc -l < out/web-golden/scenes.tsv) scenes"
fi

rm -f out/goldenCompare.exe
"$MSC" build tests/golden/compare.ms --output=out/goldenCompare.exe > out/golden-web-compare-build.log 2>&1 \
	|| { echo "FAIL the comparator does not build — see out/golden-web-compare-build.log"; exit 1; }
VOID_CONFORM=webgl2 out/goldenCompare.exe > out/golden-web-compare.log 2>&1 || true
grep -E '^(FAIL|golden webgl2|pass rate)' out/golden-web-compare.log
