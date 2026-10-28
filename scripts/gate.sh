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
#   sh scripts/gate.sh --window   also the macOS window behaviour tests, in a visible focused window
#   sh scripts/gate.sh --ios      also the Metal goldens and view samples on an attached iOS device
set -e
cd "$(dirname "$0")/.."
export VOID_QUIET_WINDOW=1

MSC="${MSC:-msc}"
WEB=0
QUICK=0
WINDOW=0
IOS=0
for arg in "$@"; do
	case "$arg" in
		--web) WEB=1 ;;
		--quick) QUICK=1 ;;
		--window) WINDOW=1 ;;
		--ios) IOS=1 ;;
		*) echo "gate.sh: unknown flag $arg" >&2; exit 2 ;;
	esac
done

fails=0
skips=0
passes=0
d3d11_conformance="not run"
# D3D11 and GL core run on the Windows box; a Mac has neither, and runs Metal instead.
golden_host=d3d11
[ "$(uname -s)" != Darwin ] || golden_host=metal

# out/ is gitignored, so on a clean clone the first redirect into it would abort under set -e
# before any step had a chance to report.
mkdir -p out out/golden

pass() { echo "PASS  $1"; passes=$((passes + 1)); }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
skip() { echo "SKIP  $1"; skips=$((skips + 1)); }
gate_start=$(date +%s)
section() { echo "=== $1 === at $(( $(date +%s) - gate_start )) s"; }

section "0. the compiler under test"
mscPath="$(command -v "$MSC" || true)"
mscVersion="$("$MSC" --version 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -1 || true)"
mscBuild="$(dirname "${mscPath:-.}")/../BUILD"
if [ -n "$mscPath" ] && [ -n "$mscVersion" ] && [ -f "$mscBuild" ]; then
	pass "$mscVersion, $mscPath"
	sed 's/^/      BUILD /' "$mscBuild"
else
	fail "cannot name the compiler: '$MSC' resolves to '${mscPath}', --version printed '${mscVersion}', and $mscBuild is missing or unread"
fi

echo
if sh scripts/oracle.test.sh > out/gate-oracle-ids.log 2>&1; then
	pass "oracle case IDs: invalid and duplicate IDs fail closed"
else
	fail "oracle case ID checks — see out/gate-oracle-ids.log"
fi

echo
section "1. T0 and T1 — msc test"
# msc exits 0 for a crashed test binary: ~/metascript/.inbox/compiler/2026-09-23-crash-exit-status-lost.md
if "$MSC" test src/test/index.ms > out/gate-t0.log 2>&1; then
	t0Summary="$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
	if echo "$t0Summary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
		pass "module stage all-off:$t0Summary"
	else
		fail "module stage all-off exited 0 without a clean 'Tests N passed (N)' summary (a crash?) — see out/gate-t0.log"
	fi
else
	fail "module stage all-off: msc test src/test/index.ms — see out/gate-t0.log"
fi

moduleFlags="voidProfiler voidShaper voidSdfText voidColourEmoji voidSvg voidSprites voidBidi voidTextOutline"
moduleDefines=""
for flag in $moduleFlags; do moduleDefines="$moduleDefines -d:$flag"; done
echo "      module stage all-off: the T0 run above, no -d: flag"
echo "      module stage all-on:  msc test$moduleDefines src/test/index.ms"
# shellcheck disable=SC2086
if "$MSC" test $moduleDefines src/test/index.ms > out/gate-t0-modules.log 2>&1; then
	modSummary="$(sed 's/\[[0-9;]*m//g' out/gate-t0-modules.log | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
	if echo "$modSummary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
		offTotal="$(echo "$t0Summary" | sed -E 's/.*Tests ([0-9]+) passed.*/\1/')"
		onTotal="$(echo "$modSummary" | sed -E 's/.*Tests ([0-9]+) passed.*/\1/')"
		if [ -f src/test/profilerCheck.ms ] && ! [ "${onTotal:-0}" -gt "${offTotal:-0}" ] 2>/dev/null; then
			fail "module stage all-on ran $onTotal tests, not above all-off's $offTotal although src/test/profilerCheck.ms exists: the -d: flags did not reach the code"
		else
			pass "module stage all-on ($moduleFlags):$modSummary (all-off $offTotal)"
		fi
	else
		fail "module stage all-on exited 0 without a clean 'Tests N passed (N)' summary (a crash?) — see out/gate-t0-modules.log"
	fi
else
	fail "module stage all-on: msc test$moduleDefines src/test/index.ms — see out/gate-t0-modules.log"
fi
for jsStage in off on; do
	jsDefines=""
	[ "$jsStage" = off ] || jsDefines="$moduleDefines"
	if "$MSC" test --target=js $jsDefines tests/js/targetCheck.ms > "out/gate-js-$jsStage.log" 2>&1 \
			&& sed 's/\x1b\[[0-9;]*m//g' "out/gate-js-$jsStage.log" | grep -qE '^\s+Tests +[0-9]+ passed \([0-9]+\)$'; then
		pass "JS target, module stage all-$jsStage: Void compiles and refuses C-only work by name"
	else
		fail "JS target, module stage all-$jsStage: msc test --target=js tests/js/targetCheck.ms — see out/gate-js-$jsStage.log"
	fi
done
for jsDriver in views window; do
	for jsBackend in gl gpu; do
		jsBundle="out/tmp/js-$jsDriver-$jsBackend.js"
		jsBackendFlag=""
		[ "$jsBackend" = gl ] && jsBackendFlag="-d:webgl2"
		if "$MSC" build --target=js $jsBackendFlag "src/examples/${jsDriver}JsEntry.jms" --output="$jsBundle" > "out/gate-js-$jsDriver-$jsBackend.log" 2>&1 \
				&& node tests/js/gpuLostHarness.mjs "$jsBundle" "$jsBackend" "$jsDriver" >> "out/gate-js-$jsDriver-$jsBackend.log" 2>&1; then
			pass "JS $jsDriver driver on $jsBackend: the loss harness (tests/js/gpuLostHarness.mjs) passes"
		else
			fail "JS $jsDriver driver on $jsBackend: build or tests/js/gpuLostHarness.mjs — see out/gate-js-$jsDriver-$jsBackend.log"
		fi
	done
done
for jsBackend in gl gpu; do
	if node tests/js/gpuViewsHarness.mjs "out/tmp/js-views-$jsBackend.js" "$jsBackend" > "out/gate-js-views-harness-$jsBackend.log" 2>&1; then
		pass "JS views on $jsBackend: tests/js/gpuViewsHarness.mjs passes"
	else
		fail "JS views on $jsBackend: tests/js/gpuViewsHarness.mjs — see out/gate-js-views-harness-$jsBackend.log"
	fi
done
for jsDriver in views window; do
	for jsBackend in gl gpu; do
		jsMin="out/tmp/js-$jsDriver-$jsBackend.min.js"
		if sh scripts/jsMinify.sh --keep-names "out/tmp/js-$jsDriver-$jsBackend.js" "$jsMin" > "out/gate-js-min-$jsDriver-$jsBackend.log" 2>&1 \
				&& node tests/js/gpuLostHarness.mjs "$jsMin" "$jsBackend" "$jsDriver" >> "out/gate-js-min-$jsDriver-$jsBackend.log" 2>&1; then
			pass "JS $jsDriver driver on $jsBackend, minified with names kept: the loss harness passes"
		else
			fail "JS $jsDriver driver on $jsBackend, minified: scripts/jsMinify.sh or tests/js/gpuLostHarness.mjs — see out/gate-js-min-$jsDriver-$jsBackend.log"
		fi
	done
done
for jsBackend in gl gpu; do
	jsMin="out/tmp/js-views-$jsBackend.min.js"
	if sh scripts/jsMinify.sh --keep-names "out/tmp/js-views-$jsBackend.js" "$jsMin" > "out/gate-js-min-views-harness-$jsBackend.log" 2>&1 \
			&& node tests/js/gpuViewsHarness.mjs "$jsMin" "$jsBackend" >> "out/gate-js-min-views-harness-$jsBackend.log" 2>&1; then
		pass "JS views on $jsBackend, minified with names kept: tests/js/gpuViewsHarness.mjs passes"
	else
		fail "JS views on $jsBackend, minified: scripts/jsMinify.sh or tests/js/gpuViewsHarness.mjs — see out/gate-js-min-views-harness-$jsBackend.log"
	fi
done
for target in "--os=windows" "--os=windows -d:voidGlCore" "--os=linux" "--os=android" "--os=ios" \
		"--os=windows -d:voidVulkan" "--os=linux -d:voidVulkan" "--os=android -d:voidVulkan" \
		"--os=emcc -d:webgpu" "--os=emcc -d:webgl2" "-d:voidDummy"; do
	log="out/gate-backend-check$(echo "$target" | tr -c 'a-zA-Z0-9\n' '-').log"
	if "$MSC" check $target src/examples/main2d.ms > "$log" 2>&1; then
		pass "backend contract, msc check $target: device.ms and its backend type-check"
	else
		fail "backend contract, msc check $target src/examples/main2d.ms — see $log"
	fi
done
if "$MSC" test -d:voidColourEmoji tests/isolated/colourMemory/colourRefusal.ms > out/gate-colour-memory.log 2>&1 \
		&& sed 's/\x1b\[[0-9;]*m//g' out/gate-colour-memory.log | grep -qE '^\s+Tests +[0-9]+ passed \([0-9]+\)$'; then
	pass "a permanently malformed colour PNG stays refused and is not retried as a memory failure"
else
	fail "colour PNG refusal — see out/gate-colour-memory.log"
fi
if MSC="$MSC" "${PYTHON:-python}" tests/isolated/rangeSpan.py > out/gate-range-span.log 2>&1 \
		&& grep -q '^PASS noteRange spans:' out/gate-range-span.log; then
	pass "noteRange rejects truncated current and saved UI spans in debug/release"
else
	fail "noteRange span refusal — see out/gate-range-span.log"
fi
for isolated in tests/isolated/*.ms; do
	log="out/gate-isolated-$(basename "$isolated" .ms).log"
	"$MSC" test "$isolated" > "$log" 2>&1 || true
	summary="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
	if echo "$summary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
		pass "$isolated in a process of its own:$summary"
	else
		fail "$isolated — see $log"
	fi
done
	echo "      T1: tests/displayList/*.txt snapshots, recorded with no GPU; VOID_SNAPSHOT=1 rewrites them"
rm -rf out/instanceLayout && mkdir -p out/instanceLayout
if INSTANCE_LAYOUT_DIR=out/instanceLayout "$MSC" run scripts/instanceLayout.ms \
		> out/gate-instance-layout.log 2>&1 \
	&& diff --strip-trailing-cr out/instanceLayout/instanceLayout.ms src/void2d/instanceLayout.ms \
		>> out/gate-instance-layout.log 2>&1 \
	&& diff --strip-trailing-cr out/instanceLayout/instanceLayout.h src/void2d/instanceLayout.h \
		>> out/gate-instance-layout.log 2>&1; then
	pass "instance layout: src/void2d/instanceLayout.ms and .h are what scripts/instanceLayout.ms generates"
else
	fail "instance layout: the generated files are stale or hand-edited; run 'msc run scripts/instanceLayout.ms' — see out/gate-instance-layout.log"
fi

if sh scripts/checkBridgePass.sh > out/gate-bridge-pass.log 2>&1; then
	pass "public C pass: only the door header offers begin/end/commit"
else
	fail "public C pass surface — see out/gate-bridge-pass.log"
fi

echo
section "2. the demo still builds and runs"
if "$MSC" build src/examples/main2d.ms --output=out/demo2d.exe > out/gate-demo.log 2>&1; then
	pass "src/examples/renderer2d.ms builds through src/examples/main2d.ms"
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

# A 3D preset and void2d in one screen pass and one commit; the same run with the 3D drawn over
# void2d, which must fail; preparing twice and drawing after a commit, which must stop by name;
# and both registration orders of a foreign shader, each with a control that must fail.
mixed_run() {  # mixed_run <log> <environment...>: the exit status in mixed_status
	mixed_log=$1
	shift
	mixed_status=0
	env "$@" out/mixedFrame.exe > "$mixed_log" 2>&1 || mixed_status=$?
}
if "$MSC" build tests/integration/mixedFrame.ms --release --output=out/mixedFrame.exe > out/gate-mixed-frame.log 2>&1; then
	mixed_run out/gate-mixed-frame-run.log
	if [ "$mixed_status" -eq 0 ] && grep -q '^mixed frame:' out/gate-mixed-frame-run.log; then
		pass "mixed frame: $(grep -E '^mixed frame:' out/gate-mixed-frame-run.log | sed 's/^mixed frame: //')"
	else
		fail "mixed 3D/void2d frame lifecycle (exit $mixed_status) — see out/gate-mixed-frame-run.log"
		grep -E '^FAIL' out/gate-mixed-frame-run.log | sed 's/^/      /' || true
	fi
	mixed_run out/gate-mixed-frame-swapped.log VOID_MIXED_3D_OVER_2D=1
	if [ "$mixed_status" -ne 0 ] && grep -q '^FAIL mixed frame: .* inside the quad' out/gate-mixed-frame-swapped.log; then
		pass "mixed frame: the control, the 3D drawn over void2d, fails inside the quad"
	else
		fail "mixed frame: the control, the 3D drawn over void2d, passed (exit $mixed_status) — see out/gate-mixed-frame-swapped.log"
	fi
	mixed_run out/gate-mixed-frame-twice.log VOID_MIXED_PREPARE_TWICE=1
	if [ "$mixed_status" -ne 0 ] && grep -q 'prepareFrame on a frame no drawToScreen or endPrepared ended' out/gate-mixed-frame-twice.log; then
		pass "mixed frame: a second prepareFrame before drawToScreen stops and names the call"
	else
		fail "mixed frame: a second prepareFrame did not stop (exit $mixed_status) — see out/gate-mixed-frame-twice.log"
	fi
	mixed_run out/gate-mixed-frame-next.log VOID_MIXED_SCREEN_NEXT_FRAME=1
	if [ "$mixed_status" -ne 0 ] && grep -q 'drawToScreen in a later sokol frame' out/gate-mixed-frame-next.log; then
		pass "mixed frame: a drawToScreen after a commit stops and names the call"
	else
		fail "mixed frame: a drawToScreen after a commit did not stop (exit $mixed_status) — see out/gate-mixed-frame-next.log"
	fi
	for order in 1 2; do
		mixed_run "out/gate-registration-$order.log" VOID_GPU_REGISTRATION=$order
		if [ "$mixed_status" -eq 0 ] && grep -q '^PASS mixed frame:' "out/gate-registration-$order.log"; then
			pass "registration: order $order, foreign shader draws the same lit frame past the old 16/8 registry widths"
		else
			fail "registration: order $order failed (exit $mixed_status) — see out/gate-registration-$order.log"
		fi
		mixed_run "out/gate-registration-$order-control.log" VOID_GPU_REGISTRATION=$order VOID_GPU_REGISTRATION_ORDER_CONTROL=1
		if [ "$mixed_status" -ne 0 ] \
				&& grep -q '^FAIL mixed frame: the foreign consumer overlaps or misses' "out/gate-registration-$order-control.log"; then
			pass "registration: order $order, reversed range expectation fails at the registry bound"
		else
			fail "registration: order $order, reversed range expectation was not caught — see out/gate-registration-$order-control.log"
		fi
	done
else
	fail "tests/integration/mixedFrame.ms does not build — see out/gate-mixed-frame.log"
fi

if "$MSC" build tests/integration/doorBlendModes.ms --release --output=out/doorBlendModes.exe \
		> out/gate-door-blend-modes.log 2>&1 \
		&& out/doorBlendModes.exe > out/gate-door-blend-modes-run.log 2>&1; then
	pass "door blend modes: every shared BlendMode makes its own pipeline on this backend, and the screen layout keys as the environment's formats"
else
	fail "door blend modes — see out/gate-door-blend-modes.log and out/gate-door-blend-modes-run.log"
fi

rm -f out/gate-pipeline-cache-owner-run.log
if "$MSC" build tests/integration/pipelineCacheOwner.ms --release --output=out/pipelineCacheOwner.exe \
		> out/gate-pipeline-cache-owner.log 2>&1 \
		&& out/pipelineCacheOwner.exe > out/gate-pipeline-cache-owner-run.log 2>&1; then
	pass "pipeline cache owner: two aliases share one cache through release, a stale epoch and close, while an independent cache keeps drawing"
else
	fail "pipeline cache owner — see out/gate-pipeline-cache-owner.log and out/gate-pipeline-cache-owner-run.log"
	grep -E '^FAIL' out/gate-pipeline-cache-owner-run.log | sed 's/^/      /' || true
fi

if "$MSC" build tests/integration/retainedReplay.ms --release --output=out/retainedReplay.exe \
		> out/gate-retained-replay.log 2>&1 \
		&& out/retainedReplay.exe > out/gate-retained-replay-run.log 2>&1; then
	pass "retained replay: vertex, sprite and UI keep the last same-frame write"
else
	fail "retained replay coherence — see out/gate-retained-replay.log and out/gate-retained-replay-run.log"
fi

if "$MSC" build tests/integration/drawContexts.ms --release --output=out/drawContexts.exe \
		> out/gate-draw-contexts.log 2>&1 \
		&& out/drawContexts.exe > out/gate-draw-contexts-run.log 2>&1; then
	pass "draw contexts: interleaved records, native sources, DPI and default append"
else
	fail "draw context isolation — see out/gate-draw-contexts.log and out/gate-draw-contexts-run.log"
fi
context_status=0
VOID_DRAW_CONTEXT_EXPIRED=1 out/drawContexts.exe \
	> out/gate-context-expired.log 2>&1 || context_status=$?
if [ "$context_status" -ne 0 ] \
		&& grep -q 'cannot activate context.*prepared frame.*expired' out/gate-context-expired.log; then
	pass "prepared draw context expires at commit and stops with its id"
else
	fail "expired draw context did not stop with its named error"
fi

if "$MSC" build -d:voidProfiler tests/integration/frameProfiler.ms --release \
		--output=out/frameProfiler.exe > out/gate-frame-profiler.log 2>&1 \
		&& out/frameProfiler.exe > out/gate-frame-profiler-run.log 2>&1; then
	pass "frame profiler: one record per frame on the views and window drivers, counters across brackets, dirty to present, and an overlay that paints and hides without dirtying the scene"
else
	fail "frame profiler — see out/gate-frame-profiler.log and out/gate-frame-profiler-run.log"
	grep -E '^FAIL' out/gate-frame-profiler-run.log | sed 's/^/      /' || true
fi

if "$MSC" build tests/integration/preparedScenes.ms --release --output=out/preparedScenes.exe \
		> out/gate-prepared-scenes.log 2>&1 \
		&& out/preparedScenes.exe > out/gate-prepared-scenes-run.log 2>&1; then
	pass "prepared scenes: filtered snapshots, two DPIs and writes between frame halves"
else
	fail "prepared Scene2D lifecycle — see out/gate-prepared-scenes-run.log"
fi
if "$MSC" build tests/integration/screenOver.ms --release --output=out/screenOver.exe \
		> out/gate-screen-over.log 2>&1; then
	if VOID_SCREEN_OVER_HOLD=3 out/screenOver.exe > out/gate-screen-over-hold.log 2>&1; then
		pass "screen over: two forward presets draw to the screen, the second over the first"
	else
		fail "screen over: the composite did not draw — see out/gate-screen-over-hold.log"
	fi
	status=0
	out/screenOver.exe > out/gate-screen-over-run.log 2>&1 || status=$?
	if [ "$status" -eq 3 ]; then
		skip "screen over: $(grep -E '^SKIP' out/gate-screen-over-run.log | sed 's/^SKIP screen over: //') (this backend has no readback)"
	elif [ "$status" -eq 0 ]; then
		pass "screen over: $(grep -E '^screen over:' out/gate-screen-over-run.log | sed 's/^screen over: //')"
	else
		fail "screen over composite — see out/gate-screen-over-run.log"
	fi
	status=0
	VOID_SCREEN_OVER_REPLACE=1 out/screenOver.exe > out/gate-screen-over-replace.log 2>&1 || status=$?
	if [ "$status" -eq 3 ]; then
		skip "screen over: the drawToScreen control needs the same readback"
	elif [ "$status" -eq 1 ] && grep -q '^FAIL screen over: pixel' out/gate-screen-over-replace.log; then
		pass "screen over: the control, the second preset copied with drawToScreen, erases the first"
	else
		fail "screen over: the control did not fail on a pixel (exit $status) — see out/gate-screen-over-replace.log"
	fi
else
	fail "tests/integration/screenOver.ms does not build — see out/gate-screen-over.log"
fi
if "$MSC" build tests/integration/layerSlot.ms --release --output=out/layerSlot.exe \
		> out/gate-layer-slot.log 2>&1; then
	if VOID_LAYER_SLOT_HOLD=3 out/layerSlot.exe > out/gate-layer-slot-hold.log 2>&1; then
		pass "layer slot: a scene drawn in two segments around another context's layer"
	else
		fail "layer slot: the segmented frame did not draw — see out/gate-layer-slot-hold.log"
	fi
	status=0
	out/layerSlot.exe > out/gate-layer-slot-run.log 2>&1 || status=$?
	if [ "$status" -eq 3 ]; then
		skip "layer slot: this backend has no readback"
	elif [ "$status" -eq 0 ]; then
		pass "layer slot: A under the layer, B and C over it"
	else
		fail "layer slot pixels — see out/gate-layer-slot-run.log"
	fi
	status=0
	VOID_LAYER_SLOT_CONTROL=1 out/layerSlot.exe > out/gate-layer-slot-control.log 2>&1 || status=$?
	if [ "$status" -eq 3 ]; then
		skip "layer slot: the one-drawScreen control needs the same readback"
	elif [ "$status" -eq 1 ] && grep -q '^FAIL layer slot: pixel' out/gate-layer-slot-control.log; then
		pass "layer slot: the control, one drawScreen under the layer, puts B and C under it"
	else
		fail "layer slot: the control did not fail on a pixel (exit $status) — see out/gate-layer-slot-control.log"
	fi
	for misuse in not-slot foreign hidden backwards; do
		case "$misuse" in
			not-slot) expected='which is not a layer slot' ;;
			foreign) expected='of another scene' ;;
			hidden) expected='did not paint on the screen' ;;
			backwards) expected='paints before the part already drawn' ;;
		esac
		status=0
		VOID_LAYER_SLOT_MISUSE="$misuse" out/layerSlot.exe \
			> "out/gate-layer-slot-$misuse.log" 2>&1 || status=$?
		if [ "$status" -ne 0 ] && grep -q "$expected" "out/gate-layer-slot-$misuse.log"; then
			pass "layer slot $misuse stops with its error"
		else
			fail "layer slot $misuse did not name its error"
		fi
	done
else
	fail "tests/integration/layerSlot.ms does not build — see out/gate-layer-slot.log"
fi
if "$MSC" build tests/integration/paintedSlots.ms --release --output=out/paintedSlots.exe \
		> out/gate-painted-slots.log 2>&1; then
	if out/paintedSlots.exe > out/gate-painted-slots-run.log 2>&1; then
		pass "painted slots: paint order, zIndex, hidden and filtered left out, patched frame"
	else
		fail "painted slots — see out/gate-painted-slots-run.log"
	fi
	status=0
	VOID_PAINTED_SLOTS_MISUSE=unprepared out/paintedSlots.exe > out/gate-painted-slots-unprepared.log 2>&1 \
		|| status=$?
	if [ "$status" -ne 0 ] && grep -q 'paintedSlots with no prepared frame' out/gate-painted-slots-unprepared.log; then
		pass "painted slots before prepare stops with its error"
	else
		fail "painted slots before prepare did not name its error"
	fi
else
	fail "tests/integration/paintedSlots.ms does not build — see out/gate-painted-slots.log"
fi
glyph_backends="native"
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) glyph_backends="native gl" ;;
esac
for glyph_backend in $glyph_backends; do
	glyph_flags=""
	[ "$glyph_backend" != gl ] || glyph_flags="-d:voidGlCore --passC=-DVOID_GLCORE"
	glyph_runner="out/glyphClip-$glyph_backend.exe"
	if "$MSC" build -d:voidSvg -d:voidColourEmoji -d:voidSdfText $glyph_flags \
			tests/integration/glyphClip.ms --release --output="$glyph_runner" \
			> "out/gate-glyph-clip-$glyph_backend-build.log" 2>&1; then
		for dpi in 1 2 3; do
			glyph_log="out/gate-glyph-clip-$glyph_backend-dpi$dpi.log"
			if GLYPH_DPI="$dpi" timeout 60 "$glyph_runner" > "$glyph_log" 2>&1; then
				if grep -q "^PASS glyph clip dpi $dpi:" "$glyph_log"; then
					pass "glyph clip $glyph_backend DPI$dpi: UV-independent bitmap/SDF shader coverage and RGBA/rounded controls"
				elif grep -q '^SKIP glyph clip:' "$glyph_log"; then
					skip "glyph clip $glyph_backend DPI$dpi: backend has no readback path"
				else
					fail "glyph clip $glyph_backend DPI$dpi has no verdict — see $glyph_log"
				fi
			else
				fail "glyph clip $glyph_backend DPI$dpi — see $glyph_log"
			fi
		done
	else
		fail "glyph clip $glyph_backend build — see out/gate-glyph-clip-$glyph_backend-build.log"
	fi
	colour_runner="out/colourSampler-$glyph_backend.exe"
	colour_backend=0
	case "$(uname -s):$glyph_backend" in
		*:gl) colour_backend=4 ;;
		MINGW*:native|MSYS*:native|CYGWIN*:native) colour_backend=1 ;;
		Darwin:native) colour_backend=5 ;;
	esac
	if "$MSC" build -d:voidColourEmoji $glyph_flags tests/integration/colourSampler.ms \
			--release --output="$colour_runner" \
			> "out/gate-colour-sampler-$glyph_backend-build.log" 2>&1; then
		colour_supported=0
		for dpi in 1 2; do
			colour_log="out/gate-colour-sampler-$glyph_backend-dpi$dpi.log"
			if COLOUR_SAMPLER_BACKEND="$colour_backend" COLOUR_SAMPLER_DPI="$dpi" \
					COLOUR_SAMPLER_MUTANT=0 timeout 60 "$colour_runner" > "$colour_log" 2>&1; then
				if grep -q '^PASS colourSampler backend ' "$colour_log"; then
					colour_supported=1
					pass "colour sampler $glyph_backend DPI$dpi: zoomed RGBA bilinear pixels, next-node nearest reset and stable warm frames"
				elif grep -q '^SKIP colourSampler:' "$colour_log"; then
					skip "colour sampler $glyph_backend DPI$dpi: backend has no readback path"
				else
					fail "colour sampler $glyph_backend DPI$dpi has no verdict — see $colour_log"
				fi
			else
				fail "colour sampler $glyph_backend DPI$dpi — see $colour_log"
			fi
		done
		if [ "$colour_supported" -eq 1 ]; then
			for colour_mutant in 1 2; do
				case "$colour_mutant" in
					1) colour_reason='bilinear pixel' ;;
					2) colour_reason='nearest reset pixel' ;;
				esac
				colour_log="out/gate-colour-sampler-$glyph_backend-mutant$colour_mutant.log"
				colour_rc=0
				COLOUR_SAMPLER_BACKEND="$colour_backend" COLOUR_SAMPLER_DPI=1 \
					COLOUR_SAMPLER_MUTANT="$colour_mutant" timeout 60 "$colour_runner" \
					> "$colour_log" 2>&1 || colour_rc=$?
				if [ "$colour_rc" -eq 1 ] && \
						grep -q "^FAIL colourSampler: $colour_reason " "$colour_log" && \
						! grep -q '^PASS colourSampler ' "$colour_log"; then
					pass "colour sampler $glyph_backend mutant$colour_mutant: refused by $colour_reason"
				else
					fail "colour sampler $glyph_backend mutant$colour_mutant failed for an incidental reason or passed — see $colour_log"
				fi
			done
		fi
	else
		fail "colour sampler $glyph_backend build — see out/gate-colour-sampler-$glyph_backend-build.log"
	fi
done

for misuse in unprepared twice no-pass nested consumed expired size; do
	case "$misuse" in
		unprepared|consumed) expected='with no prepared frame' ;;
		size) expected='drawScreen 120x60 does not match prepared' ;;
		twice) expected='again before drawScreen' ;;
		no-pass) expected='outside a screen pass' ;;
		nested) expected='with a pass already open' ;;
		expired) expected='prepared frame expired' ;;
	esac
	prepared_status=0
	VOID_PREPARED_MISUSE="$misuse" out/preparedScenes.exe \
		> "out/gate-prepared-$misuse.log" 2>&1 || prepared_status=$?
	if [ "$prepared_status" -ne 0 ] && grep -q "$expected" "out/gate-prepared-$misuse.log"; then
		pass "prepared Scene2D $misuse stops with its lifecycle error"
	else
		fail "prepared Scene2D $misuse did not name its lifecycle error"
	fi
done

if "$MSC" build tests/integration/sceneTarget.ms --release --output=out/sceneTarget.exe \
		> out/gate-scene-target.log 2>&1 \
		&& out/sceneTarget.exe > out/gate-scene-target-run.log 2>&1; then
	pass "scene target: DPI, premultiplied RGBA, idle, recreation and prepared snapshots"
	for misuse in unprepared consumed size closed empty generation format open expired \
		dpi destroyed-view; do
		case "$misuse" in
			unprepared|consumed) expected='with no prepared frame' ;;
			size|dpi) expected='does not match prepared' ;;
			closed) expected='was closed' ;;
			destroyed-view) expected='was released' ;;
			empty|format) expected='allocated Rgba8' ;;
			generation) expected='of GPU context' ;;
			open) expected='with a pass already open' ;;
			expired) expected='prepared frame expired' ;;
		esac
		target_status=0
		VOID_SCENE_TARGET_MISUSE="$misuse" out/sceneTarget.exe \
			> "out/gate-scene-target-$misuse.log" 2>&1 || target_status=$?
		if [ "$target_status" -ne 0 ] && grep -qF "$expected" "out/gate-scene-target-$misuse.log"; then
			pass "Scene2D drawTarget $misuse stops by name"
		else
			fail "Scene2D drawTarget $misuse did not name its lifecycle error"
		fi
	done
else
	fail "Scene2D caller target — see out/gate-scene-target.log and out/gate-scene-target-run.log"
fi

if "$MSC" build tests/integration/targetOwner.ms --release --output=out/tmp/targetOwner.exe \
		> out/gate-target-owner.log 2>&1 \
		&& out/tmp/targetOwner.exe > out/gate-target-owner-run.log 2>&1; then
	pass "target owner: alias resize, same-size reuse, terminal close and independent sampled pixels"
	for misuse in closed-empty color depth begin-closed refused-zero refused-pool; do
		case "$misuse" in
			closed-empty) expected='gpu door: resize on a render target that was closed' ;;
			color) expected='gpu door: asColor on a render target that was closed' ;;
			depth) expected='gpu door: asDepth on a render target that was closed' ;;
			begin-closed) expected='gpu door: beginTarget on a render target that was closed' ;;
			refused-zero) expected='gpu door: resize refused a 0x8 Rgba8 target image' ;;
			refused-pool) case "$(uname -s)" in
				Darwin) expected='webgpu metal: view pool exhausted' ;;
				*) expected='webgpu d3d11: view pool exhausted' ;;
			esac ;;
		esac
		target_status=0
		VOID_TARGET_OWNER_MISUSE="$misuse" out/tmp/targetOwner.exe \
			> "out/gate-target-owner-$misuse.log" 2>&1 || target_status=$?
		if [ "$target_status" -ne 0 ] && grep -qF "$expected" "out/gate-target-owner-$misuse.log"; then
			pass "RenderTarget $misuse stops by name"
		else
			fail "RenderTarget $misuse did not name its owner error"
		fi
	done
else
	fail "target owner — see out/gate-target-owner.log and out/gate-target-owner-run.log"
fi

if "$MSC" build tests/integration/targetPresetEpoch.ms --release --output=out/tmp/targetPresetEpoch.exe \
		> out/gate-target-preset-epoch.log 2>&1 \
		&& out/tmp/targetPresetEpoch.exe > out/gate-target-preset-epoch-run.log 2>&1; then
	pass "target preset epoch: generation-write control rebuilds every same-size target in both presets"
else
	fail "target preset epoch — see out/gate-target-preset-epoch.log and out/gate-target-preset-epoch-run.log"
fi

if "$MSC" build tests/integration/viewPaint.ms --release --output=out/viewPaint.exe \
		> out/gate-view-paint.log 2>&1 \
		&& out/viewPaint.exe > out/gate-view-paint-run.log 2>&1; then
	pass "view paint: in-place promote and demote, transparent and border-only emit no fill"
	paint_status=0
	VOID_VIEW_PAINT_MISUSE=label out/viewPaint.exe > out/gate-view-paint-label.log 2>&1 \
		|| paint_status=$?
	if [ "$paint_status" -ne 0 ] && grep -qF "only a Group or a Rect can take a background" "out/gate-view-paint-label.log"; then
		pass "view paint: a label background stops by name"
	else
		fail "view paint: label background did not name its kind error"
	fi
else
	fail "view paint — see out/gate-view-paint.log and out/gate-view-paint-run.log"
fi

if "$MSC" build tests/integration/sceneLifetime.ms --release --output=out/tmp/sceneLifetime.exe \
		> out/gate-scene-lifetime.log 2>&1 \
		&& out/tmp/sceneLifetime.exe > out/gate-scene-lifetime-run.log 2>&1; then
	pass "scene lifetime: closing a scene releases its list buffers and filter targets; a kept scene is unchanged"
	for misuse in present node construct close; do
		lifetime_status=0
		VOID_SCENE_LIFETIME_MISUSE=$misuse out/tmp/sceneLifetime.exe \
			> "out/gate-scene-lifetime-$misuse.log" 2>&1 || lifetime_status=$?
		if [ "$lifetime_status" -ne 0 ] && grep -qF "closed scene" "out/gate-scene-lifetime-$misuse.log"; then
			pass "scene lifetime: $misuse after close stops by name"
		else
			fail "scene lifetime: $misuse after close did not stop by name"
		fi
	done
else
	fail "scene lifetime — see out/gate-scene-lifetime.log and out/gate-scene-lifetime-run.log"
fi

if "$MSC" build tests/integration/sceneOcclusion.ms --release --output=out/tmp/sceneOcclusion.exe 		> out/gate-scene-occlusion.log 2>&1 		&& out/tmp/sceneOcclusion.exe > out/gate-scene-occlusion-run.log 2>&1; then
	pass "scene occlusion: releaseGpu frees list buffers and filter targets, keeps textures and glyph pages, repaints byte-identical"
	for misuse in prepared closed; do
		case "$misuse" in
			prepared) expected='between prepare and drawScreen' ;;
			closed) expected='releaseGpu on a closed scene' ;;
		esac
		occlusion_status=0
		VOID_SCENE_OCCLUSION_MISUSE=$misuse out/tmp/sceneOcclusion.exe 			> "out/gate-scene-occlusion-$misuse.log" 2>&1 || occlusion_status=$?
		if [ "$occlusion_status" -ne 0 ] && grep -qF "$expected" "out/gate-scene-occlusion-$misuse.log"; then
			pass "scene occlusion: releaseGpu $misuse stops by name"
		else
			fail "scene occlusion: releaseGpu $misuse did not stop by name"
		fi
	done
else
	fail "scene occlusion — see out/gate-scene-occlusion.log and out/gate-scene-occlusion-run.log"
fi

if "$MSC" build -d:voidColourEmoji tests/integration/sceneOcclusion.ms --release --output=out/tmp/sceneOcclusionColour.exe \
		> out/gate-scene-occlusion-colour.log 2>&1 \
		&& out/tmp/sceneOcclusionColour.exe > out/gate-scene-occlusion-colour-run.log 2>&1; then
	pass "scene occlusion with colour: releaseGpu keeps the RGBA page beside the coverage page, repaints byte-identical"
else
	fail "scene occlusion with colour — see out/gate-scene-occlusion-colour.log and out/gate-scene-occlusion-colour-run.log"
fi

device_loss_misuse() {
	loss_status=0
	VOID_DEVICE_LOSS_MISUSE=$1 out/tmp/deviceLoss.exe > "out/gate-device-loss-$1.log" 2>&1 \
		|| loss_status=$?
	if [ "$loss_status" -ne 0 ] && grep -qF "$2" "out/gate-device-loss-$1.log"; then
		pass "device loss: $1 stops by name"
	else
		fail "device loss: $1 did not stop by name"
	fi
}

if "$MSC" build -d:voidSvg tests/integration/deviceLoss.ms --release --output=out/tmp/deviceLoss.exe \
		> out/gate-device-loss.log 2>&1 \
		&& out/tmp/deviceLoss.exe > out/gate-device-loss-run.log 2>&1; then
	pass "device loss: two forced losses, the next frame byte-identical; kept pixels and a realloc hook re-upload"
	device_loss_misuse adopted "adopted image died with it"
	device_loss_misuse reupload "its image is immutable"
else
	fail "device loss — see out/gate-device-loss.log and out/gate-device-loss-run.log"
fi

if "$MSC" build -d:voidColourEmoji tests/integration/deviceLoss.ms --release --output=out/tmp/deviceLossColour.exe \
		> out/gate-device-loss-colour.log 2>&1 \
		&& out/tmp/deviceLossColour.exe > out/gate-device-loss-colour-run.log 2>&1; then
	pass "device loss with colour: two forced losses, the RGBA page re-uploads from its CPU mirror, the next frame byte-identical"
else
	fail "device loss with colour — see out/gate-device-loss-colour.log and out/gate-device-loss-colour-run.log"
fi

if "$MSC" build tests/integration/deviceLoss3d.ms --release --output=out/tmp/deviceLoss3d.exe \
		> out/gate-device-loss-3d.log 2>&1; then
	for preset in forward pixelArt outlined; do
		if VOID_DEVICE_LOSS_PRESET=$preset out/tmp/deviceLoss3d.exe \
				> "out/gate-device-loss-3d-$preset.log" 2>&1; then
			pass "device loss 3d: the $preset textured frame holds its checks across a forced loss"
		else
			fail "device loss 3d: $preset — see out/gate-device-loss-3d-$preset.log"
		fi
	done
else
	fail "device loss 3d — see out/gate-device-loss-3d.log"
fi

if "$MSC" build tests/integration/fbTrap.ms --release --output=out/fbTrap.exe \
		> out/gate-fb-trap.log 2>&1; then
	fb_status=0
	out/fbTrap.exe > out/gate-fb-trap-run.log 2>&1 || fb_status=$?
	if [ "$fb_status" -ne 0 ] && grep -qF "the framebuffer is" out/gate-fb-trap-run.log; then
		pass "fb trap: a window clamped away from its requested size stops before readback"
	else
		fail "fb trap — a clamped window did not name both sizes"
	fi
else
	fail "fb trap — see out/gate-fb-trap.log"
fi

two_views_built=0
"$MSC" build tests/integration/twoViews.ms --output=out/twoViews.exe > out/gate-two-views.log 2>&1 && two_views_built=1
if [ "$two_views_built" -eq 1 ] && out/twoViews.exe > out/gate-two-views-run.log 2> out/gate-two-views-run.err; then
	pass "$(grep -E '^PASS two views' out/gate-two-views-run.log | sed 's/^PASS //')"
else
	fail "two host views in one process — see out/gate-two-views.log, out/gate-two-views-run.log and .err"
	grep -E '^FAIL' out/gate-two-views-run.log | sed 's/^/      /' || true
fi
if [ "$(uname -s)" = Darwin ] && [ "$two_views_built" -eq 1 ]; then
	OBJC_DEBUG_MISSING_POOLS=YES out/twoViews.exe > /dev/null 2> out/gate-two-views-pools.err || true
	if grep -q 'of class CAMetalDrawable autoreleased with no pool' out/gate-two-views-pools.err; then
		fail "a view frame autoreleases its drawable with no pool in place — see out/gate-two-views-pools.err"
	else
		pass "a view frame releases its drawable in its own autorelease pool"
	fi
fi
backend_check() {
	what="$1"; log="out/gate-$2.log"; shift 2
	if "$MSC" test "$@" > "$log" 2>&1; then
		summary="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
		if echo "$summary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
			pass "$what:$summary"
		else
			fail "$what exited 0 without a clean 'Tests N passed (N)' summary — see $log"
		fi
	else
		fail "$what: msc test $* — see $log"
	fi
}
case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*)
		backend_check "d3d11 backend on WARP" webgpu-d3d11 src/test/webgpuD3d11Check.ms
		backend_check "door handle 0 on WARP" door-zero-handle src/test/doorZeroHandleCheck.ms
		backend_check "gl core backend on the system device" webgpu-gl -d:voidGlCore src/test/webgpuGlCheck.ms
		backend_check "vulkan backend on the system device" webgpu-vulkan -d:voidVulkan src/test/webgpuVulkanCheck.ms
		;;
esac
if [ "$(uname -s)" = Darwin ]; then
	backend_check "metal backend on the system device" webgpu-metal src/test/webgpuMetalCheck.ms
	window_tests="framePacing macWindow macWindowEscape macWindowFps"
	if [ "$WINDOW" -eq 1 ]; then
		for test in $window_tests; do
			if "$MSC" build tests/integration/$test.ms --output=out/$test.exe > out/gate-$test.log 2>&1 \
					&& env -u VOID_QUIET_WINDOW out/$test.exe > out/gate-$test-run.log 2>&1; then
				case "$test" in
					framePacing) pass "$(grep -E '^PASS frame pacing' out/gate-$test-run.log | sed 's/^PASS //')" ;;
					*) pass "$test: the macOS window driver delivers AppKit events through the app event API" ;;
				esac
			else
				fail "$test — see out/gate-$test.log and out/gate-$test-run.log"
				grep -E '^FAIL' out/gate-$test-run.log | sed 's/^/      /' || true
			fi
		done
	else
		skip "window behaviour ($window_tests): pass --window when src/platform/macos/*, src/host/bridgeEmbed.m, or tests/capture/capture.c changed; they need a visible focused window, and macWindow toggles full screen"
	fi
	if "$MSC" build tests/integration/metalReadback.ms --output=out/metalReadback.exe > out/gate-metal-readback.log 2>&1; then
		if out/metalReadback.exe > out/gate-metal-readback-run.log 2>&1; then
			pass "$(grep -E '^PASS metal readback' out/gate-metal-readback-run.log | sed 's/^PASS //')"
		else
			fail "metal readback — see out/gate-metal-readback-run.log"
		fi
		if VOID_READBACK_OPEN=1 out/metalReadback.exe > out/gate-metal-readback-open.log 2>&1; then
			pass "$(grep -E '^PASS metal readback: a grab before' out/gate-metal-readback-open.log | sed 's/^PASS //')"
		else
			fail "metal readback before commit — see out/gate-metal-readback-open.log"
		fi
	else
		fail "metal readback does not build — see out/gate-metal-readback.log"
	fi
	if "$MSC" build tests/integration/gpuTimer.ms --output=out/gpuTimer.exe > out/gate-gpu-timer.log 2>&1 \
			&& out/gpuTimer.exe > out/gate-gpu-timer-run.log 2>&1; then
		pass "$(grep -E '^PASS gpu timer' out/gate-gpu-timer-run.log | sed 's/^PASS //')"
	else
		fail "gpu timer — see out/gate-gpu-timer.log and out/gate-gpu-timer-run.log"
	fi
fi
outside_status=0
[ "$two_views_built" -eq 1 ] && { VOID_VIEWS_OUTSIDE=1 out/twoViews.exe > out/gate-two-views-outside.log 2>&1 || outside_status=$?; }
if [ "$two_views_built" -eq 1 ] && [ "$outside_status" -ne 0 ] && grep -q 'fbWidth outside a view frame' out/gate-two-views-outside.log; then
	pass "fbWidth outside a view frame aborts and names the call"
else
	fail "fbWidth outside a view frame did not abort (exit $outside_status) — see out/gate-two-views-outside.log"
fi
if "$MSC" build tests/integration/viewSamples.ms --output=out/viewSamples.exe > out/gate-view-samples.log 2>&1; then
	for samples in 1 2 4 8; do
		if VOID_VIEW_SAMPLES=$samples out/viewSamples.exe > out/gate-view-samples-$samples.log 2>&1; then
			pass "$(grep -o 'view samples: .*' out/gate-view-samples-$samples.log)"
		elif [ "$samples" -eq 8 ] && grep -q "sampleCount '8' is not supported" out/gate-view-samples-$samples.log; then
			pass "a host view at $samples samples stops by name: this GPU does not render them (Apple GPUs stop at 4)"
		else
			fail "a host view at $samples samples — see out/gate-view-samples-$samples.log"
		fi
	done
	late_status=0
	VOID_VIEW_SAMPLES_LATE=1 out/viewSamples.exe > out/gate-view-samples-late.log 2>&1 || late_status=$?
	if [ "$late_status" -ne 0 ] && grep -q 'after the first voidViewCreate' out/gate-view-samples-late.log; then
		pass "a sample count set after the first view aborts and names the call"
	else
		fail "a late sample count did not abort (exit $late_status) — see out/gate-view-samples-late.log"
	fi
	odd_status=0
	VOID_VIEW_SAMPLES=3 out/viewSamples.exe > out/gate-view-samples-odd.log 2>&1 || odd_status=$?
	if [ "$odd_status" -ne 0 ] && grep -q 'takes 1, 2, 4 or 8 samples' out/gate-view-samples-odd.log; then
		pass "a sample count of 3 aborts and names the counts a swapchain takes"
	else
		fail "a sample count of 3 did not abort (exit $odd_status) — see out/gate-view-samples-odd.log"
	fi
else
	fail "tests/integration/viewSamples.ms does not build — see out/gate-view-samples.log"
fi
for program in tests/aborts/cases/*.ms; do
	name=$(basename "$program" .ms)
	flags=$(sed -n 's#^// flags: ##p' "$program" | tr -d '\r')
	cases=$(sed -n 's#^// expect \([A-Za-z0-9_.]*\): .*#\1#p' "$program" | tr -d '\r')
	if [ -z "$cases" ]; then
		fail "aborts: $name names no case"
		continue
	fi
	rm -f "out/abort-$name.exe"
	# shellcheck disable=SC2086
	if ! "$MSC" build $flags "$program" --output="out/abort-$name.exe" > "out/gate-abort-$name.build.log" 2>&1; then
		fail "aborts: $name does not build — see out/gate-abort-$name.build.log"
		continue
	fi
	for case in $cases; do
		expected=$(sed -n "s#^// expect $case: ##p" "$program" | tr -d '\r')
		log="out/gate-abort-$name-$case.log"
		status=0
		"out/abort-$name.exe" "$case" > "$log" 2>&1 || status=$?
		if [ "$status" -ne 0 ] && grep -qF "$expected" "$log"; then
			pass "$case stops and says: $expected"
		else
			fail "$case did not stop with '$expected' (exit $status) — see $log"
		fi
	done
done

root=$(pwd -W 2>/dev/null || pwd)
for program in tests/refusals/*.ms; do
	name=$(basename "$program" .ms)
	expected=$(sed -n '1s#^// expect: ##p' "$program")
	log="out/gate-refusal-$name.log"
	status=0
	"$MSC" check "$program" > "$log" 2>&1 || status=$?
	plain=$(sed 's/\[[0-9;]*m//g' "$log")
	message=$(echo "$plain" | grep -m1 "Macro '" || true)
	at=$(echo "$plain" | grep -m1 -- "-->" | sed 's/.*--> //' || true)
	if [ "$expected" = "ok" ]; then
		if [ "$status" -eq 0 ]; then pass "$name is accepted"
		else fail "$name was refused: $at $message — see $log"; fi
	elif [ "$status" -ne 0 ] && echo "$message" | grep -qF -- "${expected#* }" &&
		[ "$at" = "$root/$program:${expected%% *}" ]; then
		pass "$name is refused at ${expected%% *}: ${expected#* }"
	else
		fail "$name was not refused at '$expected', got $at $message — see $log"
	fi
done

echo
section "3. T2 — golden images"
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
	if [ "$golden_host" = metal ]; then
		d3d11_conformance="not run: this host is $(uname -s), which has no D3D11"
		skip "golden suite on D3D11: this host is $(uname -s), which has no D3D11; Metal is judged in section 6"
	elif sh scripts/golden.sh > out/gate-golden.log 2>&1; then
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
	GOLDEN_DEFINES= sh scripts/golden.sh --backend "$golden_host" > out/gate-golden-bare.log 2>&1 || true
	bare_failing=$(tr -d '\r' < out/gate-golden-bare.log | grep -E '^FAIL' | awk '{ print $2 }' | sort -u)
	module_rows=$(tr -d '\r' < tests/golden/moduleRows.txt | sort -u)
	bare_leaked=""
	for scene in $bare_failing; do
		case " $(echo $module_rows) " in *" $scene "*) ;; *) bare_leaked="$bare_leaked $scene" ;; esac
	done
	bare_stale=""
	for scene in $module_rows; do
		case " $(echo $bare_failing) " in *" $scene "*) ;; *) bare_stale="$bare_stale $scene" ;; esac
	done
	if ! tr -d '\r' < out/gate-golden-bare.log | grep -q "^golden $golden_host"; then
		fail "bare build golden did not run — see out/gate-golden-bare.log"
	elif [ -n "$bare_leaked" ]; then
		fail "bare build: rows that need no module moved:$bare_leaked (tests/golden/moduleRows.txt)"
	elif [ -n "$bare_stale" ]; then
		fail "bare build: rows listed as needing a module match without one:$bare_stale — drop them from tests/golden/moduleRows.txt"
	else
		pass "bare build on $golden_host: every row that needs no module matches; the $(echo $module_rows | wc -w) module rows differ, as listed"
	fi
fi
if "$MSC" build tests/golden/invariants.ms --output=out/goldenInvariants.exe > out/gate-invariants.log 2>&1 \
		&& out/goldenInvariants.exe >> out/gate-invariants.log 2>&1; then
	grep -E '^PASS' out/gate-invariants.log | sed 's/^PASS //' | while read -r held; do
		echo "PASS  $held"
	done
	passes=$((passes + 1))
else
	fail "a committed golden breaks what it must hold within itself — see out/gate-invariants.log"
	grep -E '^FAIL' out/gate-invariants.log | sed 's/^/      /' || true
fi

echo
section "4. T3 — oracles"
t3_pass_before=$passes
t3_skip_before=$skips
pass "coverage oracle: rounded rect, 16x16 supersampled, in T0 (straight edge exact, corner <= 0.06)"
# The T0 oracle judges src/void2d/sdf.ms. The shader is a SECOND copy of that arithmetic in
# GLSL, and until this step existed "the antialiasing is correct" was proven for MetaScript
# and merely unchanged for the thing that draws — the shape of the defect that let a squared
# alpha live through all of P1. This recomputes prim/aaRotatedBox, prim/aaGraphics and
# prim/aaNonUniformBox from geometry and judges the committed goldens.
if "$MSC" build tests/oracle/captureCheck.ms --output=out/coverageCapture.exe > out/gate-oracle.log 2>&1 \
		&& out/coverageCapture.exe > out/gate-oracle-run.log 2>&1; then
	pass "coverage oracle: the captures' AA is true area (prim/aaRotatedBox, prim/aaGraphics, prim/aaNonUniformBox)"
	sed -n 's/^coverage oracle: /      /p' out/gate-oracle-run.log
else
	fail "coverage oracle: the capture's AA disagrees with true area"
	sed -n 's/^/      /p' out/gate-oracle-run.log 2>/dev/null | head -4
fi
pass "coverage oracle: the erf shadow integral, in T0 and judged on the capture (kernel-integral truth, worst 0.0251 of 0.035)"
# The SDF text shader is a third copy of the ramp (textSdf.ms is the T0 one). This recomputes
# the coverage of text/sdfRotated, text/sdfZoom4 and text/sdfScaleDown from the glyph outline at
# the exact device size and judges the committed captures against it.
if "$MSC" build tests/oracle/textSdfCheck.ms --output=out/textSdfCapture.exe > out/gate-oracle-sdf.log 2>&1 \
		&& out/textSdfCapture.exe > out/gate-oracle-sdf-run.log 2>&1; then
	pass "text sdf oracle: the SDF captures read as true coverage (text/sdfRotated, sdfZoom4, sdfScaleDown)"
	sed -n 's/^text sdf oracle: /      /p' out/gate-oracle-sdf-run.log
else
	fail "text sdf oracle: an SDF capture disagrees with true coverage — see out/gate-oracle-sdf-run.log"
	sed -n 's/^/      /p' out/gate-oracle-sdf-run.log 2>/dev/null | head -4
fi
if "$MSC" build$moduleDefines tests/oracle/textOutlineCheck.ms --output=out/textOutlineCapture.exe \
		> out/gate-oracle-outline.log 2>&1 \
		&& out/textOutlineCapture.exe > out/gate-oracle-outline-run.log 2>&1; then
	pass "outline capture oracle: the SDF outline captures read as Pillow strokes (text/outlineSdf*)"
	sed -n 's/^outline capture oracle: /      /p' out/gate-oracle-outline-run.log
else
	fail "outline capture oracle: an outline capture disagrees with Pillow — see out/gate-oracle-outline-run.log"
	sed -n 's/^/      /p' out/gate-oracle-outline-run.log 2>/dev/null | head -4
fi
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
# The full shaping oracle runs in the all-modules T0 stage, because it needs -d:voidShaper. Every
# row that is not an exact agreement must be a PENDING row, so listed == total - agreeing.
shapeLine=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0-modules.log | grep -E '^shape oracle: HarfBuzz full ' | tail -1)
shapeNumbers=$(echo "$shapeLine" | sed -nE 's|^shape oracle: HarfBuzz full ([0-9]+)/([0-9]+) rows agree, [0-9]+/[0-9]+ on glyphs, advances and offsets, ([0-9]+) listed.*|\1 \2 \3|p')
if [ -n "$shapeNumbers" ]; then
	set -- $shapeNumbers
	if [ "$(( $2 - $1 ))" -eq "$3" ]; then
		pass "${shapeLine#shape oracle: }"
	else
		fail "shape oracle: $2 rows, $1 agree, $3 listed in tests/PENDING.md — every other row must be listed — see out/gate-t0-modules.log"
	fi
else
	fail "shape oracle: printed no verdict in the all-modules stage — see out/gate-t0-modules.log"
fi
for oracle in GraphemeBreakTest LineBreakTest; do
	ucd=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E "^ucd oracle: $oracle " | tail -1)
	rows=$(echo "$ucd" | sed -nE 's|^ucd oracle: [A-Za-z]+ ([0-9]+)/([0-9]+) rows.*|\1 \2|p')
	if [ -n "$rows" ] && [ "${rows% *}" = "${rows#* }" ]; then
		pass "UCD 18.0.0 ${ucd#ucd oracle: }"
	else
		fail "UCD oracle $oracle: '${ucd}' — see out/gate-t0.log"
	fi
done
# The BiDi conformance rows are fetched by setup.sh, not vendored, and they run in the all-modules
# stage (they need -d:voidBidi). A missing file or a sha256 that differs from the pin prints a line
# naming it and fails the oracle: it is never a skip.
for oracle in BidiTest BidiCharacterTest; do
	line=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0-modules.log | grep -E "^bidi oracle: $oracle [0-9]+/[0-9]+ (cases|rows) agree" | tail -1)
	counts=$(echo "$line" | sed -nE 's|^bidi oracle: [A-Za-z]+ ([0-9]+)/([0-9]+) .*|\1 \2|p')
	if [ -n "$counts" ] && [ "${counts% *}" = "${counts#* }" ] && [ "${counts#* }" -gt 0 ]; then
		pinned=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0-modules.log | grep -cE '^bidi oracle: 2 conformance files match' || true)
		if [ "$pinned" -ge 1 ]; then
			pass "UCD 18.0.0 ${line#bidi oracle: }, files at their sha256 pins"
		else
			fail "BiDi oracle $oracle: agrees, but the conformance files do not match tests/oracle/ucd/bidiConformance.sha256: run setup.sh — see out/gate-t0-modules.log"
		fi
	else
		fail "BiDi oracle $oracle: '${line}': run setup.sh if a conformance file is missing or differs from its pin — see out/gate-t0-modules.log"
		sed 's/\x1b\[[0-9;]*m//g' out/gate-t0-modules.log | grep -E '^bidi oracle: (deps|[0-9])' | head -3 | sed 's/^/      /'
	fi
done
for oracle in "cases" "scale modes"; do
	line=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E "^h2d oracle: [0-9]+/[0-9]+ $oracle agree" | tail -1)
	if [ -n "$line" ]; then
		pass "h2d semantics against Heaps: ${line#h2d oracle: }"
	else
		fail "h2d oracle: $oracle printed no verdict — see out/gate-t0.log"
	fi
done
# The generated shader modules are printed from the MetaScript stages (docs/SHADER-IR.md), and
# --check also leaves every printed stage in out/irPrograms/ for the validators below.
if bash scripts/regen-shaders.sh --check > out/gate-shaders.log 2>&1; then
	pass "shader modules: the committed modules and DXBC blobs match the printers"
else
	fail "shader modules: stale or unprintable — see out/gate-shaders.log (sh scripts/regen-shaders.sh)"
	grep -E '^(stale|dxbc miss)' out/gate-shaders.log | head -4 | sed 's/^/      /'
fi
for validator in Hlsl Wgsl Msl; do
	status=0
	sh "scripts/validate$validator.sh" out/irPrograms > "out/gate-validate$validator.log" 2>&1 || status=$?
	verdict=$(grep "^validate" "out/gate-validate$validator.log" | tail -1)
	case "$status" in
		0) pass "printed $validator: $verdict" ;;
		2) skip "printed $validator: $verdict" ;;
		*) fail "printed $validator: $verdict — see out/gate-validate$validator.log" ;;
	esac
done
status=0
sh scripts/validateMsl.sh out/mslProbe > out/gate-validateMslProbe.log 2>&1 || status=$?
verdict=$(grep "^validate" out/gate-validateMslProbe.log | tail -1)
case "$status" in
	0) pass "probed MSL: $verdict" ;;
	2) skip "probed MSL: $verdict" ;;
	*) fail "probed MSL: $verdict — see out/gate-validateMslProbe.log" ;;
esac
skip "printed GLSL 430 / ES 3.00: naga reads GL GLSL only after a Vulkan 450 rewrite that is not in this repository"
t3_report="$((passes - t3_pass_before)) wired, $((skips - t3_skip_before)) not"

echo
section "5. T4 — budget"
bench_broken=""
bench_build() {  # bench_build <log> <output> <msc build arguments...>
	log=$1
	output=$2
	shift 2
	"$MSC" build "$@" --release --output="$output" >> "$log" 2>&1 || bench_broken="$bench_broken $output"
}
: > out/gate-bench.log
: > out/gate-bench-profiler.log
for scene in Ui Sprites Text Editor Scroll; do
	bench_build out/gate-bench.log "out/bench$scene.exe" "tests/bench/bench$scene.ms"
	bench_build out/gate-bench-profiler.log "out/bench${scene}Profiler.exe" -d:voidProfiler "tests/bench/bench$scene.ms"
done
for module in ColourEmoji:Emoji TextOutline:Outline SdfText:Sdf; do
	bench_build out/gate-bench.log "out/benchText${module#*:}.exe" "-d:void${module%%:*}" "tests/bench/benchText${module#*:}.ms"
	bench_build out/gate-bench-profiler.log "out/benchText${module#*:}Profiler.exe" -d:voidProfiler \
		"-d:void${module%%:*}" "tests/bench/benchText${module#*:}.ms"
done
if [ -n "$bench_broken" ]; then
	fail "bench: these did not build, so the rows below may read a previous gate's binary:$bench_broken — see out/gate-bench.log and out/gate-bench-profiler.log"
fi
bench_check=0
"$MSC" build tests/bench/check.ms --output=out/benchCheck.exe >> out/gate-bench.log 2>&1 || bench_check=$?
if [ "$bench_check" -eq 0 ] && out/benchCheck.exe > out/gate-bench-rows.log 2>&1; then
	pass "bench counters match tests/bench/baseline.json"
	grep -E '^(REPORT|WARN)' out/gate-bench-rows.log | sed 's/^/      /'
else
	fail "bench — see out/gate-bench.log and out/gate-bench-rows.log"
	grep -E '^FAIL' out/gate-bench-rows.log | sed 's/^/      /' || true
fi
if [ "$bench_check" -eq 0 ] && BENCH_SUFFIX=Profiler out/benchCheck.exe > out/gate-bench-profiler-rows.log 2>&1; then
	pass "bench counters with -d:voidProfiler and the overlay hidden equal tests/bench/baseline.json"
	grep -E '^REPORT [a-z]+\.profile' out/gate-bench-profiler-rows.log | sed 's/^/      /'
else
	fail "bench with the profiler compiled in — see out/gate-bench-profiler-rows.log"
	grep -E '^FAIL' out/gate-bench-profiler-rows.log | sed 's/^/      /' || true
fi
# The counters cannot see an allocation that moves no length, so read the emitted C. It sees
# array copies and fresh arrays; not aliases (`let b = vec` emits no copy on msc 0.2.55, card
# 2026-09-23-vec-param-copy-corrupts-heap), not stream growth, not allocation inside C.
FRAME_PATH="scene:tick scene:present scene:presentAt scene:prepare scene:drawScreen render:drawOrder render:drawRow
	render:drawContent render:drawOwn render:pushMask render:syncOrder node:refreshOrder render:meshBounds render:emitNode render:emitLabel
	render:emitStyledImage render:localBounds render:boxRenderBounds render:animFrame
	render:placedBounds render:cellBounds render:emitImage render:appendTile render:quadTile
	render:rewriteTile render:drawScaleGrid
	render:sharedGlyphView node:clearChanges node:refOf node:liveRow node:imageStyleOf
	render:renderScaleGrid labelText:placementCurrent labelText:placementKey labelText:uvRect
	labelText:markGlyphPageDrawn labelText:beginGlyphFrame labelText:glyphPageHandle
	glyphAtlas:tile glyphAtlas:markDrawn glyphAtlas:beginFrame glyphAtlas:pageHandle
	displayList:resetContext displayList:growTo displayList:pushUiInstance
	displayList:pushSpriteInstance displayList:pushVertex displayList:recordDraw
	displayList:recordUiDraw displayList:recordSpriteDraw displayList:startCommand
	displayList:pushEffect displayList:recordClip draw:openBracket draw:startContext draw:end2d
	draw:flushTargets draw:prepare draw:drawScreen
	draw:drawUiInstance draw:drawSpriteAffine draw:useRun draw:openRun draw:closeRun
	draw:finishRecording draw:applyClip draw:pushClip draw:popClip draw:setEffect
	draw:drawMeshRange snap:snapBoxEdges render:showsEditing render:faded render:segmentBox
	render:emitRunBox render:emitRunLine render:emitDecorations render:neighbourSpan
	render:emitSelection render:emitCaret labelText:cursorShown
	textLayout:lineBoxAt textLayout:lineOfIndex
	render:emitTiles render:cellMatrix render:tileBounds render:drawnEnd render:tileTint
	render:retilable render:queueRetile render:retileRow node:settleTiles draw:beginSprites
	draw:appendSprite draw:rewriteSprite displayList:putSpriteInstance render:lanesFor
	render:laneParent render:openLanes render:closeEnclosure render:closeLanes
	render:remapLaneRows render:checkNoOverlap draw:splitRun draw:closeLaneRun
	draw:restoreLaneRun draw:reopenLast displayList:layLanes displayList:lanesReorderable
	displayList:laneSourceHolding"
REBUILD_PATH="render:shapeIfChanged render:drawFiltered labelText:placeLabel
	labelText:shapeLabel labelText:releasePlacement labelText:runDecorations
	labelText:lineDecorations labelText:refreshSelection labelText:rowSpans labelText:rowEnd
	labelText:xOnRow
	textLayout:layout textLayout:shapeText textLayout:wrapText textLayout:pushLine
	textLayout:pushTruncated textLayout:forceCells textLayout:decodeUtf8
	textLayout:assignFaces textLayout:assignGrapheme textLayout:graphemeFace
	textLayout:breakAfter textLayout:step
	textLayout:tallestFaces grapheme:breaksBefore lineBreak:lineBreaks lineBreak:unitBreak
	glyphAtlas:acquire glyphAtlas:allocate glyphAtlas:placeOnPage
	glyphAtlas:ensurePage glyphAtlas:reclaimPage glyphAtlas:release"
MEASURE_PATH="render:textWidth render:textHeight render:shapedPayload node:labelRow
	node:requireKind"
# A struct that holds no Vec copies only its references. The compiler copies these around a
# call that may run Texture.realloc, a closure that could write the borrowed source.
VEC_FREE_COPIES="types:TextureSource types:Tile node:Content2D"
copied=""
followed=0
allocated=""
unreachable=""
: > out/gate-allocation.log
# $1 bench entry; $2 functions that copy nothing and build no array; $3 that copy nothing and
# call no function named in $4 (textLayout returns the whole layout by value: REVIEWS.md P3 F2).
read_emitted_c() {
	rm -f "out/debug/$(basename "$1" .ms).exe" out/debug/*srcZvoid2dZ*Oms.c
	if ! "$MSC" build "$1" --emit=c -d:voidBidi >> out/gate-allocation.log 2>&1; then
		unreachable="$unreachable (emitting C for $1 failed)"
		return 0
	fi
	awk -v frame="$(echo $2)" -v copyOnly="$(echo $3)" -v forbidden="$4" \
		-v named="$(echo $FRAME_PATH $REBUILD_PATH $MEASURE_PATH)" -v vecFree="$(echo $VEC_FREE_COPIES)" \
		-f scripts/allocation.awk out/debug/*srcZvoid2dZ*Oms.c > out/gate-allocation-rows.log
	cat out/gate-allocation-rows.log >> out/gate-allocation.log
	while read -r kind what; do
		case "$kind" in
			UNREACHABLE) unreachable="$unreachable $what" ;;
			COPIED) copied="$copied $what" ;;
			ALLOCATED) allocated="$allocated $what" ;;
			FOLLOWED) followed=$((followed + what)) ;;
		esac
	done < out/gate-allocation-rows.log
	return 0
}
read_emitted_c tests/bench/benchUi.ms "$FRAME_PATH" "$REBUILD_PATH" ""
read_emitted_c tests/bench/benchText.ms "" "$MEASURE_PATH" "textLayout"
if [ -n "$unreachable" ]; then
	fail "allocation: no body in the emitted C for$unreachable — renamed or unreachable?"
elif [ -n "$copied" ] || [ -n "$allocated" ]; then
	[ -n "$copied" ] && fail "allocation: an array or a struct holding one is copied — in:$copied"
	[ -n "$allocated" ] && fail "allocation: the frame path builds a fresh array — in:$allocated"
	echo "         CODE-STYLE section 5: index the field, take a Span view, or return a tuple"
else
	pass "allocation: the frame path ($(echo $FRAME_PATH | wc -w) functions) copies no array and builds no fresh one; the rebuild ($(echo $REBUILD_PATH | wc -w)) and measure ($(echo $MEASURE_PATH | wc -w)) paths copy none; $followed functions they call are held to the same rules"
fi
# Guardrail 6: a build without the modules pays none of them (C objects: tests/bench/wasm.json).
# srcZvoid2dZcolour and srcZvoid2dZbidi are emitted names of src/void2d/colourEmoji/ and bidi*.ms; moving them turns the check into a skip.
if sh scripts/wasmModuleDelta.sh > out/gate-wasm-delta.log 2>&1; then
	pass "module off: no C unit holds stb_image, the C objects stay inside tests/bench/wasm.json"
	grep -E '^(      default-layer delta|module on)' out/gate-wasm-delta.log | sed 's/^/      /'
else
	fail "module off or wasm delta — see out/gate-wasm-delta.log"
	grep -E '^FAIL' out/gate-wasm-delta.log | sed 's/^/      /' || true
fi
if "$MSC" build src/examples/main2d.ms --release --output=out/tmp/main2dOff.exe > out/gate-module-off.log 2>&1 \
		&& "$MSC" build -d:voidColourEmoji src/examples/main2d.ms --release --output=out/tmp/main2dColour.exe >> out/gate-module-off.log 2>&1; then
	module_off_bytes=$(wc -c < out/tmp/main2dOff.exe)
	module_on_bytes=$(wc -c < out/tmp/main2dColour.exe)
	module_symbols() {
		if [ -f "${1%.exe}.pdb" ]; then
			llvm-pdbutil dump -publics "${1%.exe}.pdb" 2> /dev/null
		else
			llvm-nm "$1" 2> /dev/null
		fi
	}
	named_on=$(module_symbols out/tmp/main2dColour.exe | grep -c 'srcZvoid2dZcolour' || true)
	named_off=$(module_symbols out/tmp/main2dOff.exe | grep -c 'srcZvoid2dZcolour\|void2dGlyphSdf\|kbts_\|void2dShape\|srcZvoid2dZbidi\|srcZvoid2dZsprite\|void2dGlyphFaceSprite' || true)
	named_batcher=$(module_symbols out/tmp/main2dOff.exe | grep -c 'srcZvoid2dZbatcher' || true)
	if [ "$named_on" -eq 0 ] || [ "$named_batcher" -eq 0 ]; then
		skip "module off: the executables name no symbol from src/void2d/colourEmoji or batcher.ms (colour $named_on, batcher $named_batcher), so they get no symbol check"
	elif [ "$named_off" -gt 0 ]; then
		fail "module off: main2d.exe with every module flag off names $named_off colour, SDF, shaper, BiDi or sprite symbols"
	else
		pass "module off: main2d.exe names no colour, SDF, shaper, BiDi or sprite symbol, the colour build names $named_on symbols from src/void2d/colourEmoji"
	fi
	if [ "$module_on_bytes" -gt "$module_off_bytes" ]; then
		pass "module off: main2d.exe is $module_off_bytes B, with the colour module $module_on_bytes B (+$((module_on_bytes - module_off_bytes)) B)"
	else
		fail "module off: main2d.exe is $module_off_bytes B without the colour module and $module_on_bytes B with it, so the flag changed nothing"
	fi
else
	fail "module off: main2d.exe did not build both ways — see out/gate-module-off.log"
fi
if sh scripts/wasmBudget.test.sh --record > out/gate-wasm-budget-record.log 2>&1; then
	pass "linked wasm budgets: 24 measured declarations valid; remeasure with scripts/experiment-modulesWeb.sh (not linked again by this native stage)"
else
	fail "linked wasm budget declarations — see out/gate-wasm-budget-record.log"
fi
if MSC="$MSC" sh scripts/jsBudget.sh > out/gate-js-budget.log 2>&1; then
	pass "JS budgets: both entries, six module flags, raw and gzip stay inside tests/bench/jsBudget.txt"
else
	fail "JS budgets — see out/gate-js-budget.log"
	grep -E '^FAIL' out/gate-js-budget.log | sed 's/^/      /' || true
fi

# The graduation rule for a conformance row: every scene it lists must still fail, and a clean
# run with the row still present fails too. $1 backend, $2 its golden log, $3 the PENDING id.
conformance_rule() {
	row=$(grep -E "^\| $3 " tests/PENDING.md || true)
	listed=$(echo "$row" | grep -oE '`[a-z]+/[A-Za-z0-9]+`' | tr -d '`' | sort -u)
	failing=$(grep -E '^FAIL' "$2" | awk '{ print $2 }' | sort -u)
	unlisted=""
	for scene in $failing; do
		case " $(echo $listed) " in *" $scene "*) ;; *) unlisted="$unlisted $scene" ;; esac
	done
	graduated=""
	for scene in $listed; do
		case " $(echo $failing) " in *" $scene "*) ;; *) graduated="$graduated $scene" ;; esac
	done
	if [ -n "$unlisted" ]; then
		fail "$1 conformance: failures no PENDING row lists:$unlisted (tests/PENDING.md $3)"
	elif [ -n "$row" ] && [ -z "$failing" ]; then
		fail "$1 conformance: 0 fail, and tests/PENDING.md $3 survives the run — delete it"
	elif [ -n "$graduated" ]; then
		fail "$1 conformance: listed scenes now pass:$graduated — delete them from tests/PENDING.md $3"
	elif [ -z "$failing" ]; then
		pass "$1 conformance: every scene identical or within the cross-backend bound"
	else
		skip "$1 conformance: the structural failures are the listed ones — tests/PENDING.md $3"
	fi
	grep -E '^FAIL' "$2" | sed 's/^/      /' || true
}

echo
section "6. guardrail 9 — same pixels on every platform"
echo "      One golden set, authored on D3D11, every backend compared against it."
echo "      Conformance, per backend:"
# Never a fixed number here: the gate may not report a result it did not produce.
echo "      d3d11    $d3d11_conformance      (this box, every gate)"
gl_conformance="not run"
gl_ran=0
if [ "$QUICK" -eq 1 ]; then
	skip "GL core 4.3 desktop (glsl430): --quick skips the golden suites (sh scripts/golden.sh --backend gl)"
elif [ "$golden_host" = metal ]; then
	skip "GL core 4.3 desktop (glsl430): this host is $(uname -s), where the GL core capture does not compile; it runs on Windows (sh scripts/golden.sh --backend gl)"
else
	gl_ran=1
	sh scripts/golden.sh --backend gl > out/gate-golden-gl.log 2>&1 || true
	gl_conformance="$(tr -d '\r' < out/gate-golden-gl.log | grep -E '^golden gl430' || echo 'no conformance line — see out/gate-golden-gl.log')"
	echo "      gl430    $gl_conformance      (this box, every full gate)"
	grep -E '^RENDERER' out/gate-golden-gl.log | sed 's/^/      /' || true
	if ! echo "$gl_conformance" | grep -q '^golden gl430'; then
		fail "GL core 4.3 desktop conformance did not run — see out/gate-golden-gl.log"
	else
		conformance_rule gl430 out/gate-golden-gl.log conformance:gl430-pixel-centre
	fi
fi
if [ "$(uname -s)" != Darwin ]; then
	skip "metal macOS and iOS: run on a Mac only (sh scripts/golden.sh --backend metal; bash scripts/iosDevice.sh golden auto)"
elif [ "$QUICK" -eq 1 ]; then
	skip "metal macOS and iOS: --quick skips the golden suites (sh scripts/golden.sh --backend metal; bash scripts/iosDevice.sh golden auto)"
else
	sh scripts/golden.sh --backend metal > out/gate-golden-metal.log 2>&1 || true
	metal_conformance="$(grep -E '^golden metal' out/gate-golden-metal.log || echo 'no conformance line — see out/gate-golden-metal.log')"
	echo "      metal    $metal_conformance      (this Mac, every full gate)"
	if ! echo "$metal_conformance" | grep -q '^golden metal'; then
		fail "metal macOS conformance did not run — see out/gate-golden-metal.log"
	else
		conformance_rule metal out/gate-golden-metal.log conformance:metal-gpu-rounding
	fi
	if [ "$IOS" -eq 0 ]; then
		skip "metal iOS golden and view samples: pass --ios with an unlocked, paired device attached (bash scripts/iosDevice.sh golden auto)"
	else
		ios_device="${VOID_IOS_DEVICE:-auto}"
		rm -f out/golden-metal-ios-*.log
		ios_status=0
		bash scripts/iosDevice.sh golden "$ios_device" > out/gate-ios-golden.log 2>&1 || ios_status=$?
		ios_model="$(sed -n 's/^iosDevice: \(.*\) (.*), profile .*/\1/p' out/gate-ios-golden.log | head -1)"
		ios_log="out/golden-metal-ios-$ios_model.log"
		if [ -n "$ios_model" ] && grep -q '^golden metal' "$ios_log" 2> /dev/null; then
			echo "      metal    iOS $ios_model: $(grep -E '^golden metal' "$ios_log")      (attached device, every full gate)"
			conformance_rule "metal iOS $ios_model" "$ios_log" conformance:metal-gpu-rounding
		else
			fail "metal iOS golden did not run to a verdict: $(grep '^iosDevice:' out/gate-ios-golden.log | tail -1 | cut -c1-300) (exit $ios_status) — see out/gate-ios-golden.log"
			grep -E '^FAIL scene' out/gate-ios-golden.log | sed 's/^/      /' || true
		fi
		ios_status=0
		bash scripts/iosDevice.sh samples "$ios_device" > out/gate-ios-samples.log 2>&1 || ios_status=$?
		ios_model="$(sed -n 's/^iosDevice: \(.*\) (.*), profile .*/\1/p' out/gate-ios-samples.log | head -1)"
		if [ -z "$ios_model" ] || ! grep -q '^[1248]: ' out/gate-ios-samples.log; then
			fail "metal iOS view samples did not run: $(grep '^iosDevice:' out/gate-ios-samples.log | tail -1 | cut -c1-300) (exit $ios_status) — see out/gate-ios-samples.log"
		else
			for samples in 1 2 4 8; do
				ios_line="$(grep "^$samples: " out/gate-ios-samples.log || true)"
				case "$ios_line" in
					*"PASS view samples"*) pass "iOS $ios_model: ${ios_line#*: }" ;;
					"8: "*"sampleCount '8' is not supported"*) pass "iOS $ios_model: a host view at $samples samples stops by name: this GPU does not render them (Apple GPUs stop at 4)" ;;
					*) fail "iOS $ios_model: a host view at $samples samples: ${ios_line:-no result} — see out/gate-ios-samples.log" ;;
				esac
			done
		fi
	fi
fi
skip "gles3 Android: shares the glReadPixels path, needs the device — tests/PENDING.md backend:gles3-android"
skip "webgpu: blocked with the other web runs — tests/PENDING.md web:runs"
skip "sample_count on Android: needs the device — tests/PENDING.md backend:sample-count-mobile"
if [ "$WEB" -eq 1 ]; then
	sh scripts/golden-web.sh > out/gate-golden-web.log 2>&1 || true
	webgl2_conformance="$(grep -E '^golden webgl2' out/gate-golden-web.log || echo 'no conformance line — see out/gate-golden-web.log')"
	echo "      webgl2   $webgl2_conformance      (headless Chrome, --web)"
	if ! grep -q '^golden webgl2' out/gate-golden-web.log; then
		fail "webgl2 conformance did not run — see out/gate-golden-web.log"
	else
		conformance_rule webgl2 out/gate-golden-web.log conformance:webgl2-pixel-centre
	fi
else
	skip "webgl2 conformance: runs with --web (sh scripts/golden-web.sh)"
fi
if [ "$WEB" -eq 1 ]; then
	if sh scripts/build-web.sh > out/gate-web.log 2>&1; then
		pass "web build: both backends build ($(wc -c < web/wgpu/main2d.wasm) B wgpu, $(wc -c < web/gl/main2d.wasm) B gl)"
		# Liveness prints its own PASS/SKIP/FAIL per backend, with the reason. Its skips and
		# fails have to reach the counters or the summary undercounts them.
		sh scripts/web-liveness.sh > out/gate-liveness.log 2>&1 || true
		sed 's/^/      /' out/gate-liveness.log
		skips=$((skips + $(grep -c '^SKIP' out/gate-liveness.log || true)))
		fails=$((fails + $(grep -c '^FAIL' out/gate-liveness.log || true)))
		sh scripts/webViews.sh > out/gate-webViews.log 2>&1 || true
		sed 's/^/      /' out/gate-webViews.log
		skips=$((skips + $(grep -c '^SKIP' out/gate-webViews.log || true)))
		fails=$((fails + $(grep -c '^FAIL' out/gate-webViews.log || true)))
		grep -qE '^(PASS|SKIP)' out/gate-webViews.log || fail "web views did not run — see out/gate-webViews.log"
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
grep -oE '^\| [a-z-]+:[a-zA-Z0-9/-]+' tests/PENDING.md | sed 's/^| //' | sort -u > out/pendingIds.txt
dead_refs=$(grep -vE '^[[:space:]]*#' scripts/gate.sh \
	| grep -oE 'tests/PENDING\.md [a-z-]+:[a-zA-Z0-9/-]+' \
	| awk '{ print $2 }' | sort -u \
	| comm -23 - out/pendingIds.txt)
if [ -z "$dead_refs" ]; then
	pass "every PENDING id the skip lines name exists in tests/PENDING.md"
else
	fail "skip lines name PENDING rows that do not exist: $(echo $dead_refs | tr '\n' ' ')"
fi

echo
section "7. the record against the code"
if "$MSC" build tests/record/check.ms --output=out/recordCheck.exe > out/gate-record.log 2>&1 \
		&& out/recordCheck.exe >> out/gate-record.log 2>&1; then
	pass "$(grep -E '^record:' out/gate-record.log)"
else
	fail "the record disagrees with the code — see out/gate-record.log"
	grep -E '^FAIL' out/gate-record.log | sed 's/^/      /' || true
fi
if git ls-files -z 'src/*.ms' 'tests/*.ms' | xargs -0 awk -f scripts/stringLiterals.awk \
		> out/gate-string-literals.log 2>&1; then
	pass "style: every string literal in src and tests closes on its line, with no raw tab or CR"
else
	fail "style: a string literal holds a raw tab, CR or line end — see out/gate-string-literals.log"
	head -8 out/gate-string-literals.log | sed 's/^/      /'
fi
git ls-files -z 'scripts/*.sh' | xargs -0 grep -n -F -f scripts/scriptEscapes.txt \
	> out/gate-script-escapes.log || true
if [ -s out/gate-script-escapes.log ]; then
	fail "style: a script has a literal backslash-n where a line continuation belongs — see out/gate-script-escapes.log"
	head -8 out/gate-script-escapes.log | sed 's/^/      /'
else
	pass "style: no script carries a literal backslash-n where a line continuation belongs"
fi
# The conformance rows of docs/TESTING.md against the logs this run wrote; a skipped suite has
# no log from this run, so its row is not judged.
if [ "$QUICK" -eq 0 ] && [ "$golden_host" = metal ]; then
	skip "docs/TESTING.md's D3D11 row: this host is $(uname -s), which ran no D3D11 golden to judge it by"
elif [ "$QUICK" -eq 0 ]; then
	d3d11=$(tr -d '\r' < out/gate-golden.log | sed -nE 's/^golden d3d11: ([0-9]+) pass, [0-9]+ pending, [0-9]+ fail of ([0-9]+)$/\1 \2/p')
	claim="| D3D11 | **${d3d11% *} / ${d3d11#* } scenes byte-identical**"
	if [ -n "$d3d11" ] && grep -qF "$claim" docs/TESTING.md; then
		pass "docs/TESTING.md's D3D11 row matches this run: ${d3d11% *} / ${d3d11#* }"
	else
		fail "docs/TESTING.md's D3D11 row does not match this run's '$(grep -E '^golden d3d11' out/gate-golden.log)'"
	fi
fi
if [ "$gl_ran" -eq 1 ] && grep -q '^golden gl430' out/gate-golden-gl.log; then
	claim=$(tr -d '\r' < out/gate-golden-gl.log | awk '
		/^golden gl430: [0-9]+ pass, [0-9]+ pending, [0-9]+ fail of [0-9]+( \([0-9]+ excluded\))?$/ {
			p = $3; q = $5; f = $7; n = $10; e = 0
			if ($11 != "") { e = substr($11, 2) + 0 }
			printf "| GL core 4.3 desktop (glsl430) | **%d / %d**: %d byte-identical, %d within the cross-backend bound, %d structural failures, %d void3d scenes excluded by name", p + q, n, p, q, f, e
		}')
	if [ -z "$claim" ]; then
		fail "the golden gl430 line is not in the form the record check reads — see out/gate-golden-gl.log"
	elif grep -qF "$claim" docs/TESTING.md; then
		pass "docs/TESTING.md's GL core 4.3 row matches this run: $(echo "$claim" | sed -E 's/.*\*\*(.*)\*\*.*/\1/')"
	else
		fail "docs/TESTING.md's GL core 4.3 row does not match this run; the row has to start with: $claim"
	fi
fi
if [ "$WEB" -eq 1 ] && grep -q '^golden webgl2' out/gate-golden-web.log; then
	claim=$(tr -d '\r' < out/gate-golden-web.log | awk '
		/^golden webgl2: [0-9]+ pass, [0-9]+ pending, [0-9]+ fail of [0-9]+$/ {
			p = $3; q = $5; f = $7; n = $10
			printf "| WebGL2 | **%d / %d**: %d byte-identical, %d within the cross-backend bound, %d structural failures", p + q, n, p, q, f
		}')
	if [ -z "$claim" ]; then
		fail "the golden webgl2 line is not in the form the record check reads — see out/gate-golden-web.log"
	elif grep -qF "$claim" docs/TESTING.md; then
		pass "docs/TESTING.md's WebGL2 row matches this run: $(echo "$claim" | sed -E 's/.*\*\*(.*)\*\*.*/\1/')"
	else
		fail "docs/TESTING.md's WebGL2 row does not match this run's '$(grep -E '^golden webgl2' out/gate-golden-web.log)'"
	fi
fi

section "8. summary"
# Shape, not an allowlist of id prefixes: an allowlist silently undercounts the moment
# someone adds a row with a new prefix, and a count that is off by one is worse than none.
pending=$(grep -cE '^\| [A-Za-z][A-Za-z0-9:/._-]* \| T[0-5] \|' tests/PENDING.md || true)
echo "      tier   what ran"
echo "      T0     msc test src/test/index.ms, stages all-off and all-on ($moduleFlags)"
echo "      T1     display-list snapshots + growth policy, no GPU"
echo "      T2     $d3d11_conformance"
echo "      T3     oracles: $t3_report"
echo "      T4     bench counters gated, milliseconds reported, frame path copies and builds no array"
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
