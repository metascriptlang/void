#!/bin/sh
# The gate (docs/TESTING.md "The gate"). Green before every commit.
#
# Every step prints PASS, FAIL or SKIP with a reason. A SKIP is loud and counted, and
# nothing may report PASS for a backend it did not run — the whole point of this file is
# that the claims in docs/VOID2D.md can be re-run by someone who did not write them.
#
#   sh scripts/gate.sh            T0, the golden suite on D3D11, the bench, the tier report
#   sh scripts/gate.sh --web      also build both web backends (slow; needs emsdk)
#   sh scripts/gate.sh --quick    skip the golden suite (T0 and bench only)
set -e
cd "$(dirname "$0")/.."

MSC="${MSC:-msc}"
WEB=0
QUICK=0
for arg in "$@"; do
	case "$arg" in
		--web) WEB=1 ;;
		--quick) QUICK=1 ;;
		*) echo "gate.sh: unknown flag $arg" >&2; exit 2 ;;
	esac
done

fails=0
skips=0
d3d11_conformance="not run"

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
skip() { echo "SKIP  $1"; skips=$((skips + 1)); }

echo "=== 1. evict the caches ==============================================="
# msc answers "Up to date" after a header that a compiled .c includes has changed, and the
# global object cache is keyed on the .c and not its includes — --force does not bypass it
# (~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md). A gate that
# silently tests the previous binary is worse than no gate.
rm -f out/goldenRunner.exe out/goldenCompare.exe out/benchUi.exe out/benchSprites.exe out/benchCheck.exe
rm -rf out/debug/.cache out/release/.cache
rm -rf "$HOME/.metascript/cache/objects"
pass "caches evicted"

echo
echo "=== 2. T0 and T1 — msc test ==========================================="
if "$MSC" test src/test/index.ms > out/gate-t0.log 2>&1; then
	pass "$(grep -E '^\s+Tests' out/gate-t0.log | tail -1 | tr -s ' ')"
else
	fail "msc test src/test/index.ms — see out/gate-t0.log"
fi
echo "      T1 (display list) does not exist yet: P1 creates it (docs/TESTING.md 'T1')"

echo
echo "=== 3. the demo still builds =========================================="
if "$MSC" build src/examples/mainSokol2d.ms --output=out/demo2d.exe > out/gate-demo.log 2>&1; then
	pass "src/examples/renderer2d.ms builds through src/examples/mainSokol2d.ms"
else
	fail "the demo does not build — see out/gate-demo.log"
fi

echo
echo "=== 4. T2 — golden images, D3D11 ======================================"
if [ "$QUICK" -eq 1 ]; then
	skip "golden suite: --quick"
else
	if sh scripts/golden.sh > out/gate-golden.log 2>&1; then
		d3d11_conformance="$(grep -E '^golden ' out/gate-golden.log)"
		pass "$d3d11_conformance"
		grep -E '^(PENDING|  harness/mustFail)' out/gate-golden.log | sed 's/^/      /' || true
	else
		d3d11_conformance="FAILED — see out/gate-golden.log"
		fail "golden suite — see out/gate-golden.log"
		grep -E '^FAIL' out/gate-golden.log | sed 's/^/      /' || true
	fi
	echo "      harness self-checks: hand-computed scene, deliberately wrong golden,"
	echo "      and two draws of the same state compared before either is written out"
fi

echo
echo "=== 5. T3 — oracles ==================================================="
skip "coverage oracle: not wired (P2) — tests/PENDING.md oracle:coverage"
skip "fontTools metrics: not wired (P3) — tests/PENDING.md oracle:font-metrics"
skip "HarfBuzz kerning subset: not wired (P3) — tests/PENDING.md oracle:harfbuzz-kerning"
skip "UCD segmentation: not wired (P4) — tests/PENDING.md oracle:ucd-segmentation"
skip "h2d semantics: not wired (P5) — tests/PENDING.md oracle:h2d"

echo
echo "=== 6. T4 — budget ===================================================="
if [ "$QUICK" -eq 1 ] || [ ! -f out/benchUi.exe ]; then
	"$MSC" build tests/bench/benchUi.ms --release --output=out/benchUi.exe > out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchSprites.ms --release --output=out/benchSprites.exe >> out/gate-bench.log 2>&1 || true
fi
"$MSC" build tests/bench/check.ms --output=out/benchCheck.exe >> out/gate-bench.log 2>&1 || true
if [ -x out/benchCheck.exe ] && out/benchCheck.exe > out/gate-bench-rows.log 2>&1; then
	pass "bench counters match tests/bench/baseline.json"
	grep -E '^(REPORT|WARN)' out/gate-bench-rows.log | sed 's/^/      /'
else
	fail "bench — see out/gate-bench-rows.log"
	grep -E '^FAIL' out/gate-bench-rows.log | sed 's/^/      /' || true
fi
skip "wasm size budget: no budget committed yet (P6 makes guardrail 6 real)"

echo
echo "=== 7. guardrail 9 — same pixels on every platform ===================="
echo "      One golden set, authored on D3D11, every backend compared against it."
echo "      Conformance, per backend:"
# Never a fixed number here: the gate may not report a result it did not produce.
echo "      d3d11    $d3d11_conformance      (this box, every gate)"
skip "gles3 desktop: capture.c has the glReadPixels path, no GLES3 build has run it"
skip "metal macOS: no readback (~50 lines) — tests/PENDING.md backend:metal-macos"
skip "metal iOS: no readback, and the first device run is T5"
skip "gles3 Android: shares the glReadPixels path, needs the device"
skip "webgpu: needs copyTextureToBuffer + mapAsync and a browser driver"
skip "webgl2: shares the GLES3 path in wasm, needs the same browser driver"
if [ "$WEB" -eq 1 ]; then
	if sh scripts/build-web.sh > out/gate-web.log 2>&1; then
		pass "web liveness: both backends build (this is a build check, NOT conformance)"
	else
		fail "web build — see out/gate-web.log"
	fi
else
	skip "web build: not requested (pass --web)"
fi

echo
echo "=== 8. summary ========================================================"
pending=$(grep -cE '^\| (golden|backend|oracle|debug-abort|walk|text-buffer|upload|cull|idle|h2d|one-node|legacy)' tests/PENDING.md || true)
echo "      tier   what ran"
echo "      T0     msc test src/test/index.ms"
echo "      T1     does not exist until P1"
echo "      T2     $d3d11_conformance"
echo "      T3     nothing wired"
echo "      T4     bench counters gated, milliseconds reported"
echo "      T5     human only (docs/TESTING.md 'T5')"
echo "      tests/PENDING.md entries: $pending"
echo "      SKIP: $skips   FAIL: $fails"

if [ "$fails" -ne 0 ]; then
	echo
	echo "GATE RED"
	exit 1
fi
echo
echo "GATE GREEN (with $skips loud skips)"
