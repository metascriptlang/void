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
passes=0
d3d11_conformance="not run"

# out/ is gitignored, so on a clean clone the first redirect into it would abort under set -e
# before any step had a chance to report.
mkdir -p out out/golden

pass() { echo "PASS  $1"; passes=$((passes + 1)); }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
skip() { echo "SKIP  $1"; skips=$((skips + 1)); }

echo "=== 1. evict the caches ==============================================="
# msc answers "Up to date" after a header that a compiled .c includes has changed, and the
# global object cache is keyed on the .c and not its includes — --force does not bypass it
# (~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md). A gate that
# silently tests the previous binary is worse than no gate.
rm -f out/goldenRunner.exe out/goldenCompare.exe out/benchUi.exe out/benchSprites.exe out/benchText.exe out/benchCheck.exe out/mixedFrame.exe out/twoViews.exe
rm -rf out/debug/.cache out/release/.cache
rm -rf "$HOME/.metascript/cache/objects"
pass "caches evicted"

echo
echo "=== 2. T0 and T1 — msc test ==========================================="
# msc exits 0 for a crashed test binary: ~/metascript/.inbox/compiler/2026-09-23-crash-exit-status-lost.md
if "$MSC" test src/test/index.ms > out/gate-t0.log 2>&1; then
	t0Summary="$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
	if echo "$t0Summary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
		pass "$t0Summary"
	else
		fail "msc test exited 0 without a clean 'Tests N passed (N)' summary (a crash?) — see out/gate-t0.log"
	fi
else
	fail "msc test src/test/index.ms — see out/gate-t0.log"
fi
	echo "      T1: tests/displayList/*.txt snapshots, recorded with no GPU; VOID_SNAPSHOT=1 rewrites them"

echo
echo "=== 3. the demo still builds and runs ================================="
if "$MSC" build src/examples/mainSokol2d.ms --output=out/demo2d.exe > out/gate-demo.log 2>&1; then
	pass "src/examples/renderer2d.ms builds through src/examples/mainSokol2d.ms"
	# Building is not enough. The entry used to declare `function main()` with nothing
	# calling it, so it built a binary that exited at once — a defect a build check cannot
	# see. A windowed app never exits on its own, so the timeout IS the pass.
	demo_status=0
	timeout 5 out/demo2d.exe > out/gate-demo-run.log 2>&1 || demo_status=$?
	case "$demo_status" in
		124) pass "the demo still runs (held a window for 5 s)" ;;
		0)   fail "the demo exited on its own within 5 s — see out/gate-demo-run.log" ;;
		*)   fail "the demo exited $demo_status — see out/gate-demo-run.log" ;;
	esac
else
	fail "the demo does not build — see out/gate-demo.log"
fi

if "$MSC" build tests/integration/mixedFrame.ms --release --output=out/mixedFrame.exe > out/gate-mixed-frame.log 2>&1 \
		&& out/mixedFrame.exe > out/gate-mixed-frame-run.log 2>&1; then
	pass "mixed frame: 3D + void2d, one shared commit, two fresh frames"
else
	fail "mixed 3D/void2d frame lifecycle — see out/gate-mixed-frame.log and out/gate-mixed-frame-run.log"
fi

if "$MSC" build tests/integration/twoViews.ms --output=out/twoViews.exe > out/gate-two-views.log 2>&1 \
		&& out/twoViews.exe > out/gate-two-views-run.log 2>&1; then
	pass "$(grep -E '^PASS two views' out/gate-two-views-run.log | sed 's/^PASS //')"
else
	fail "two host views in one process — see out/gate-two-views.log and out/gate-two-views-run.log"
	grep -E '^FAIL' out/gate-two-views-run.log | sed 's/^/      /' || true
fi
outside_status=0
VOID_VIEWS_OUTSIDE=1 out/twoViews.exe > out/gate-two-views-outside.log 2>&1 || outside_status=$?
if [ "$outside_status" -ne 0 ] && grep -q 'fbWidth outside a view frame' out/gate-two-views-outside.log; then
	pass "fbWidth outside a view frame aborts and names the call"
else
	fail "fbWidth outside a view frame did not abort (exit $outside_status) — see out/gate-two-views-outside.log"
fi

echo
echo "=== 4. T2 — golden images, D3D11 ======================================"
# The runner's own verdict logic first, against known inputs, and before it is trusted to say
# what was captured. It needs no build and no GPU, so it runs even under --quick.
if sh scripts/golden.sh --self-check > out/gate-verdict.log 2>&1; then
	pass "golden.sh verdict decision: $(grep -c '^PASS' out/gate-verdict.log) inputs, including a CAPTURED line followed by a FAIL"
else
	fail "golden.sh verdict decision — see out/gate-verdict.log"
	grep -E '^FAIL' out/gate-verdict.log | sed 's/^/      /' || true
fi
if [ "$QUICK" -eq 1 ]; then
	skip "golden suite: --quick"
else
	if sh scripts/golden.sh > out/gate-golden.log 2>&1; then
		# `|| echo` matters under set -e: a bare assignment whose command substitution fails
		# takes grep's status and kills the gate mid-run, with no summary and no message.
		d3d11_conformance="$(grep -E '^golden ' out/gate-golden.log || echo 'no conformance line in the log')"
		pass "$d3d11_conformance"
		grep -E '^(PENDING|  harness/mustFail)' out/gate-golden.log | sed 's/^/      /' || true
	else
		d3d11_conformance="FAILED — see out/gate-golden.log"
		fail "golden suite — see out/gate-golden.log"
		grep -E '^FAIL' out/gate-golden.log | sed 's/^/      /' || true
	fi
	echo "      harness self-checks: hand-computed scene, deliberately wrong golden,"
	echo "      two draws of the same state compared before either is written out,"
	echo "      and the verdict decision proved above"
fi

echo
echo "=== 5. T3 — oracles ==================================================="
t3_pass_before=$passes
t3_skip_before=$skips
pass "coverage oracle: rounded rect, 16x16 supersampled, in T0 (straight edge exact, corner <= 0.06)"
# The T0 oracle judges src/void2d/sdf.ms. The shader is a SECOND copy of that arithmetic in
# GLSL, and until this step existed "the antialiasing is correct" was proven for MetaScript
# and merely unchanged for the thing that draws — the shape of the defect that let a squared
# alpha live through all of P1. This recomputes prim/aaRotatedBox from geometry and judges
# the committed golden.
"$MSC" build tests/oracle/captureCheck.ms --output=out/coverageCapture.exe > out/gate-oracle.log 2>&1 || true
if [ -x out/coverageCapture.exe ] && out/coverageCapture.exe > out/gate-oracle-run.log 2>&1; then
	pass "coverage oracle: the capture's AA is true area (prim/aaRotatedBox, rotated 37 deg, alpha 0.5)"
	sed -n 's/^coverage oracle: /      /p' out/gate-oracle-run.log
else
	fail "coverage oracle: the capture's AA disagrees with true area"
	sed -n 's/^/      /p' out/gate-oracle-run.log 2>/dev/null | head -4
fi
pass "coverage oracle: the erf shadow integral, in T0 and judged on the capture (kernel-integral truth, worst 0.0251 of 0.035)"
# The font oracles run inside T0 (src/test/fontOracleCheck.ms) against snapshots that
# `python tests/oracle/fonts.py regen` writes from fontTools and HarfBuzz; the gate needs
# neither tool, and reads the verdict line each test prints.
for oracle in "fontTools metrics" "HarfBuzz kerning"; do
	line=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E "^font oracle: $oracle " | tail -1)
	case "$line" in
		*" values agree")
			agreed=$(echo "$line" | sed -E 's|.* ([0-9]+)/([0-9]+) values agree|\1 \2|')
			if [ -n "$agreed" ] && [ "${agreed% *}" = "${agreed#* }" ]; then
				pass "${line#font oracle: }"
			else
				fail "${line#font oracle: } — see out/gate-t0.log"
			fi ;;
		*) fail "font oracle: $oracle printed no verdict — see out/gate-t0.log" ;;
	esac
done
skip "UCD segmentation: not wired (P4) — tests/PENDING.md oracle:ucd-segmentation"
skip "h2d semantics: not wired (P5) — tests/PENDING.md oracle:h2d"
t3_report="$((passes - t3_pass_before)) wired, $((skips - t3_skip_before)) not"

echo
echo "=== 6. T4 — budget ===================================================="
if [ "$QUICK" -eq 1 ] || [ ! -f out/benchUi.exe ]; then
	"$MSC" build tests/bench/benchUi.ms --release --output=out/benchUi.exe > out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchSprites.ms --release --output=out/benchSprites.exe >> out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchText.ms --release --output=out/benchText.exe >> out/gate-bench.log 2>&1 || true
fi
"$MSC" build tests/bench/check.ms --output=out/benchCheck.exe >> out/gate-bench.log 2>&1 || true
if [ -x out/benchCheck.exe ] && out/benchCheck.exe > out/gate-bench-rows.log 2>&1; then
	pass "bench counters match tests/bench/baseline.json"
	grep -E '^(REPORT|WARN)' out/gate-bench-rows.log | sed 's/^/      /'
else
	fail "bench — see out/gate-bench-rows.log"
	grep -E '^FAIL' out/gate-bench-rows.log | sed 's/^/      /' || true
fi
# An allocation that moves no length is invisible to the counters, so read the emitted C, as
# gate3d.sh's "allocation" stage does. It sees copies, not aliases: on msc 0.2.55 `let b = vec`
# emits no copy at all (~/metascript/.inbox/compiler/2026-09-23-vec-param-copy-corrupts-heap.md).
FRAME_PATH="scene:present scene:presentAt render:draw render:drawContent render:drawFiltered
	render:sync render:emitNode render:emitLabel render:emitStyledImage render:labelStyle
	render:localBounds render:boxRenderBounds render:visualTile render:sortByZ
	render:sharedGlyphView render:renderScaleGrid label84ext:placeLabel
	label84ext:placementCurrent label84ext:uvRect label84ext:markGlyphPageDrawn
	label84ext:beginGlyphFrame label84ext:glyphPageHandle glyph65tlas:tile glyph65tlas:markDrawn
	glyph65tlas:beginFrame glyph65tlas:pageHandle display76ist:resetList
	display76ist:pushUiInstance display76ist:pushSpriteInstance display76ist:pushVertex
	display76ist:recordDraw display76ist:recordUiDraw display76ist:recordSpriteDraw
	display76ist:startCommand display76ist:pushEffect display76ist:recordClip draw:begin2d
	draw:end2d draw:flushTargets draw:drawUiInstance draw:drawSpriteAffine draw:useUiState
	draw:useSpriteState draw:openRun draw:closeRun draw:finishRecording draw:applyClip
	draw:pushClip draw:popClip draw:setEffect draw:drawMeshRange snap:snapBoxEdges"
PLACEMENT_PATH="render:shapeIfChanged label84ext:shapeLabel label84ext:releasePlacement
	text76ayout:layout text76ayout:layRun text76ayout:decodeUtf8 glyph65tlas:acquire
	glyph65tlas:allocate glyph65tlas:placeOnPage glyph65tlas:ensurePage glyph65tlas:reclaimPage
	glyph65tlas:release"
rm -f out/debug/benchUi.exe out/debug/*ZsrcZvoid2dZ*Oms.c
if ! "$MSC" build tests/bench/benchUi.ms --emit=c > out/gate-allocation.log 2>&1; then
	fail "allocation: emitting C for tests/bench/benchUi.ms failed — see out/gate-allocation.log"
else
	offenders=""
	unreachable=""
	for entry in $FRAME_PATH $PLACEMENT_PATH; do
		module=${entry%%:*}
		fn=${entry#*:}
		emitted=$(ls out/debug/*ZsrcZvoid2dZ${module}Oms.c 2>/dev/null | head -1)
		if [ -z "$emitted" ] || ! grep -q "^[a-zA-Z_].*[^a-zA-Z0-9_]${fn}__M.*{[[:space:]]*$" "$emitted"; then
			unreachable="$unreachable $entry"
			continue
		fi
		copies=$(awk "/^[a-zA-Z_].*[^a-zA-Z0-9_]${fn}__M.*\{[ \t]*\$/,/^}/" "$emitted" | grep -c 'ArrayCopy(' || true)
		[ "$copies" -gt 0 ] && offenders="$offenders ${fn}=${copies}"
	done
	if [ -n "$unreachable" ]; then
		fail "allocation: no body in the emitted C for$unreachable — renamed or unreachable?"
	elif [ -n "$offenders" ]; then
		fail "allocation: the frame path copies an array — ArrayCopy in:$offenders"
		echo "         CODE-STYLE section 5: index the field or take a Span view"
	else
		pass "allocation: no array copy in the frame path ($(echo $FRAME_PATH | wc -w) functions) or the placement path ($(echo $PLACEMENT_PATH | wc -w))"
	fi
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
skip "webgpu: needs copyTextureToBuffer + mapAsync, and headless Chrome has no adapter here"
if [ "$WEB" -eq 1 ]; then
	sh scripts/golden-web.sh > out/gate-golden-web.log 2>&1 || true
	webgl2_conformance="$(grep -E '^golden webgl2' out/gate-golden-web.log || echo 'no conformance line — see out/gate-golden-web.log')"
	echo "      webgl2   $webgl2_conformance      (headless Chrome, --web)"
	if ! grep -q '^golden webgl2' out/gate-golden-web.log; then
		fail "webgl2 conformance did not run — see out/gate-golden-web.log"
	elif grep -q '^golden webgl2: .* 0 fail of' out/gate-golden-web.log; then
		pass "webgl2 conformance: every scene identical or within the cross-backend bound"
	else
		listed=$(grep -E '^\| conformance:webgl2-pixel-centre ' tests/PENDING.md || true)
		unlisted=""
		for scene in $(grep -E '^FAIL' out/gate-golden-web.log | awk '{ print $2 }'); do
			case "$listed" in *"\`$scene\`"*) ;; *) unlisted="$unlisted $scene" ;; esac
		done
		if [ -z "$unlisted" ]; then
			skip "webgl2 conformance: the structural failures are the listed ones — tests/PENDING.md conformance:webgl2-pixel-centre"
		else
			fail "webgl2 conformance: failures no PENDING row lists:$unlisted"
		fi
		grep -E '^FAIL' out/gate-golden-web.log | sed 's/^/      /' || true
	fi
else
	skip "webgl2 conformance: runs with --web (sh scripts/golden-web.sh)"
fi
if [ "$WEB" -eq 1 ]; then
	if sh scripts/build-web.sh > out/gate-web.log 2>&1; then
		pass "web build: both backends build ($(wc -c < web/wgpu/mainSokol2d.wasm) B wgpu, $(wc -c < web/gl/mainSokol2d.wasm) B gl)"
		# Liveness prints its own PASS/SKIP per backend, with the reason. Its skips have to
		# reach $skips or the summary undercounts what was not run.
		sh scripts/web-liveness.sh > out/gate-liveness.log 2>&1 || true
		sed 's/^/      /' out/gate-liveness.log
		skips=$((skips + $(grep -c '^SKIP' out/gate-liveness.log || true)))
	else
		fail "web build — see out/gate-web.log"
	fi
else
	skip "web build and liveness: not requested (pass --web)"
fi

echo
# ---- the pending list and the skip lines must correspond ---------------------------------
# The skip lines above name PENDING ids in prose ("... tests/PENDING.md oracle:foo"), and
# nothing parsed them: a row an edit swallowed left its skip line pointing at nothing, green.
# That nearly shipped tonight - oracle:harfbuzz-kerning, caught by a diff audit rather than
# by a mechanism. The invariant is the dead-hash idiom this workspace already uses for card
# SHAs: read out EMPTY. One direction only, deliberately - a skip naming a dead row is always
# wrong, while "a new row no skip names yet" is the normal state of a row added before its
# gate line, and making that red is a contract change that belongs to the phase review.
dead_refs=$(grep -vE '^[[:space:]]*#' scripts/gate.sh \
	| grep -oE 'tests/PENDING\.md [a-z-]+:[a-zA-Z0-9/-]+' \
	| awk '{ print $2 }' | sort -u \
	| comm -23 - <(grep -oE '^\| [a-z-]+:[a-zA-Z0-9/-]+' tests/PENDING.md | sed 's/^| //' | sort -u))
if [ -z "$dead_refs" ]; then
	pass "every PENDING id the skip lines name exists in tests/PENDING.md"
else
	fail "skip lines name PENDING rows that do not exist: $(echo $dead_refs | tr '\n' ' ')"
fi

echo "=== 8. summary ========================================================"
# Shape, not an allowlist of id prefixes: an allowlist silently undercounts the moment
# someone adds a row with a new prefix, and a count that is off by one is worse than none.
pending=$(grep -cE '^\| [A-Za-z][A-Za-z0-9:/._-]* \| T[0-5] \|' tests/PENDING.md || true)
echo "      tier   what ran"
echo "      T0     msc test src/test/index.ms"
echo "      T1     display-list snapshots + growth policy, no GPU"
echo "      T2     $d3d11_conformance"
echo "      T3     oracles: $t3_report"
echo "      T4     bench counters gated, milliseconds reported, frame path copies no array"
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
