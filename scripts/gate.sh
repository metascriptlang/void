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

echo "=== 0. the compiler under test ========================================"
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
echo "=== 1. evict the caches ==============================================="
# msc answers "Up to date" after a header that a compiled .c includes has changed, and the
# global object cache is keyed on the .c and not its includes — --force does not bypass it
# (~/metascript/.inbox/compiler/2026-09-20-object-cache-ignores-headers.md). A gate that
# silently tests the previous binary is worse than no gate. The machine-wide cache stays
# untouched: deleting it raced every other session's msc and wiped their objects.
export MSC_NO_GLOBAL_CACHE=1
rm -f out/goldenRunner.exe out/goldenCompare.exe out/benchUi.exe out/benchSprites.exe out/benchText.exe out/benchEditor.exe out/benchScroll.exe out/benchCheck.exe out/mixedFrame.exe out/doorBlendModes.exe out/pipelineCacheOwner.exe out/twoViews.exe out/viewSamples.exe out/recordCheck.exe out/goldenInvariants.exe
rm -rf out/debug/.cache out/release/.cache
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

moduleFlags="voidProfiler voidShaper voidSdfText voidColourEmoji voidSvg"
moduleDefines=""
for flag in $moduleFlags; do moduleDefines="$moduleDefines -d:$flag"; done
echo "      module stage all-off: the T0 run above, no -d: flag"
echo "      module stage all-on:  msc test$moduleDefines src/test/index.ms"
# shellcheck disable=SC2086
if "$MSC" test $moduleDefines src/test/index.ms > out/gate-t0-modules.log 2>&1; then
	modSummary="$(sed 's/\[[0-9;]*m//g' out/gate-t0-modules.log | grep -E '^\s+Tests ' | tail -1 | tr -s ' ')"
	if echo "$modSummary" | grep -qE 'Tests [0-9]+ passed \([0-9]+\)$'; then
		pass "module stage all-on ($moduleFlags):$modSummary"
	else
		fail "module stage all-on exited 0 without a clean 'Tests N passed (N)' summary (a crash?) — see out/gate-t0-modules.log"
	fi
else
	fail "module stage all-on: msc test$moduleDefines src/test/index.ms — see out/gate-t0-modules.log"
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

if "$MSC" build tests/integration/preparedScenes.ms --release --output=out/preparedScenes.exe \
		> out/gate-prepared-scenes.log 2>&1 \
		&& out/preparedScenes.exe > out/gate-prepared-scenes-run.log 2>&1; then
	pass "prepared scenes: filtered snapshots, two DPIs and writes between frame halves"
else
	fail "prepared Scene2D lifecycle — see out/gate-prepared-scenes-run.log"
fi
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

rm -f out/tmp/targetOwner.exe
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
			refused-pool) expected='gpu door: resize refused a 8x8 Rgba8 target' ;;
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

rm -f out/tmp/targetPresetEpoch.exe
if "$MSC" build tests/integration/targetPresetEpoch.ms --release --output=out/tmp/targetPresetEpoch.exe \
		> out/gate-target-preset-epoch.log 2>&1 \
		&& out/tmp/targetPresetEpoch.exe > out/gate-target-preset-epoch-run.log 2>&1; then
	pass "target preset epoch: generation-write control rebuilds every same-size target in both presets"
else
	fail "target preset epoch — see out/gate-target-preset-epoch.log and out/gate-target-preset-epoch-run.log"
fi

rm -f out/viewPaint.exe
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

rm -f out/tmp/sceneLifetime.exe
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

rm -f out/tmp/sceneOcclusion.exe
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

rm -f out/tmp/deviceLoss.exe
if "$MSC" build tests/integration/deviceLoss.ms --release --output=out/tmp/deviceLoss.exe \
		> out/gate-device-loss.log 2>&1 \
		&& out/tmp/deviceLoss.exe > out/gate-device-loss-run.log 2>&1; then
	pass "device loss: two forced losses, the next frame byte-identical; kept pixels and a realloc hook re-upload"
	device_loss_misuse adopted "adopted image died with it"
	device_loss_misuse reupload "its image is immutable"
else
	fail "device loss — see out/gate-device-loss.log and out/gate-device-loss-run.log"
fi

rm -f out/tmp/deviceLoss3d.exe
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

rm -f out/fbTrap.exe
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

if "$MSC" build tests/integration/twoViews.ms --output=out/twoViews.exe > out/gate-two-views.log 2>&1 \
		&& out/twoViews.exe > out/gate-two-views-run.log 2> out/gate-two-views-run.err; then
	pass "$(grep -E '^PASS two views' out/gate-two-views-run.log | sed 's/^PASS //')"
else
	fail "two host views in one process — see out/gate-two-views.log, out/gate-two-views-run.log and .err"
	grep -E '^FAIL' out/gate-two-views-run.log | sed 's/^/      /' || true
fi
outside_status=0
VOID_VIEWS_OUTSIDE=1 out/twoViews.exe > out/gate-two-views-outside.log 2>&1 || outside_status=$?
if [ "$outside_status" -ne 0 ] && grep -q 'fbWidth outside a view frame' out/gate-two-views-outside.log; then
	pass "fbWidth outside a view frame aborts and names the call"
else
	fail "fbWidth outside a view frame did not abort (exit $outside_status) — see out/gate-two-views-outside.log"
fi
if "$MSC" build tests/integration/viewSamples.ms --output=out/viewSamples.exe > out/gate-view-samples.log 2>&1; then
	for samples in 1 2 4 8; do
		if VOID_VIEW_SAMPLES=$samples out/viewSamples.exe > out/gate-view-samples-$samples.log 2>&1; then
			pass "$(grep -o 'view samples: .*' out/gate-view-samples-$samples.log)"
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
for program in tests/aborts/*.ms; do
	name=$(basename "$program" .ms)
	expected=$(sed -n '1s#^// expect: ##p' "$program")
	log="out/gate-abort-$name.log"
	status=0
	rm -f "out/abort-$name.exe"
	"$MSC" build "$program" --output="out/abort-$name.exe" > "$log" 2>&1 || true
	"out/abort-$name.exe" >> "$log" 2>&1 || status=$?
	if [ -n "$expected" ] && [ "$status" -ne 0 ] && grep -qF "$expected" "$log"; then
		pass "$name stops and says: $expected"
	else
		fail "$name did not stop with '$expected' (exit $status) — see $log"
	fi
done

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
"$MSC" build tests/golden/invariants.ms --output=out/goldenInvariants.exe > out/gate-invariants.log 2>&1 || true
if [ -x out/goldenInvariants.exe ] && out/goldenInvariants.exe >> out/gate-invariants.log 2>&1; then
	grep -E '^PASS' out/gate-invariants.log | sed 's/^PASS //' | while read -r held; do
		echo "PASS  $held"
	done
	passes=$((passes + 1))
else
	fail "a committed golden breaks what it must hold within itself — see out/gate-invariants.log"
	grep -E '^FAIL' out/gate-invariants.log | sed 's/^/      /' || true
fi

echo
echo "=== 5. T3 — oracles ==================================================="
t3_pass_before=$passes
t3_skip_before=$skips
pass "coverage oracle: rounded rect, 16x16 supersampled, in T0 (straight edge exact, corner <= 0.06)"
# The T0 oracle judges src/void2d/sdf.ms. The shader is a SECOND copy of that arithmetic in
# GLSL, and until this step existed "the antialiasing is correct" was proven for MetaScript
# and merely unchanged for the thing that draws — the shape of the defect that let a squared
# alpha live through all of P1. This recomputes prim/aaRotatedBox and prim/aaGraphics from
# geometry and judges the committed goldens.
"$MSC" build tests/oracle/captureCheck.ms --output=out/coverageCapture.exe > out/gate-oracle.log 2>&1 || true
if [ -x out/coverageCapture.exe ] && out/coverageCapture.exe > out/gate-oracle-run.log 2>&1; then
	pass "coverage oracle: the captures' AA is true area (prim/aaRotatedBox, prim/aaGraphics)"
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
for oracle in GraphemeBreakTest LineBreakTest; do
	ucd=$(sed 's/\x1b\[[0-9;]*m//g' out/gate-t0.log | grep -E "^ucd oracle: $oracle " | tail -1)
	rows=$(echo "$ucd" | sed -nE 's|^ucd oracle: [A-Za-z]+ ([0-9]+)/([0-9]+) rows.*|\1 \2|p')
	if [ -n "$rows" ] && [ "${rows% *}" = "${rows#* }" ]; then
		pass "UCD 18.0.0 ${ucd#ucd oracle: }"
	else
		fail "UCD oracle $oracle: '${ucd}' — see out/gate-t0.log"
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
t3_report="$((passes - t3_pass_before)) wired, $((skips - t3_skip_before)) not"

echo
echo "=== 6. T4 — budget ===================================================="
if [ "$QUICK" -eq 1 ] || [ ! -f out/benchUi.exe ]; then
	"$MSC" build tests/bench/benchUi.ms --release --output=out/benchUi.exe > out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchSprites.ms --release --output=out/benchSprites.exe >> out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchText.ms --release --output=out/benchText.exe >> out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchEditor.ms --release --output=out/benchEditor.exe >> out/gate-bench.log 2>&1 || true
	"$MSC" build tests/bench/benchScroll.ms --release --output=out/benchScroll.exe >> out/gate-bench.log 2>&1 || true
fi
"$MSC" build tests/bench/check.ms --output=out/benchCheck.exe >> out/gate-bench.log 2>&1 || true
if [ -x out/benchCheck.exe ] && out/benchCheck.exe > out/gate-bench-rows.log 2>&1; then
	pass "bench counters match tests/bench/baseline.json"
	grep -E '^(REPORT|WARN)' out/gate-bench-rows.log | sed 's/^/      /'
else
	fail "bench — see out/gate-bench-rows.log"
	grep -E '^FAIL' out/gate-bench-rows.log | sed 's/^/      /' || true
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
	render:renderScaleGrid label84ext:placementCurrent label84ext:placementKey label84ext:uvRect
	label84ext:markGlyphPageDrawn label84ext:beginGlyphFrame label84ext:glyphPageHandle
	glyph65tlas:tile glyph65tlas:markDrawn glyph65tlas:beginFrame glyph65tlas:pageHandle
	display76ist:resetContext display76ist:growTo display76ist:pushUiInstance
	display76ist:pushSpriteInstance display76ist:pushVertex display76ist:recordDraw
	display76ist:recordUiDraw display76ist:recordSpriteDraw display76ist:startCommand
	display76ist:pushEffect display76ist:recordClip draw:openBracket draw:startContext draw:end2d
	draw:flushTargets draw:prepare draw:drawScreen
	draw:drawUiInstance draw:drawSpriteAffine draw:useRun draw:openRun draw:closeRun
	draw:finishRecording draw:applyClip draw:pushClip draw:popClip draw:setEffect
	draw:drawMeshRange snap:snapBoxEdges render:showsEditing render:faded render:segmentBox
	render:emitRunBox render:emitRunLine render:emitDecorations render:rowEnd render:xOnRow
	render:selectedRow render:emitSelection render:emitCaret label84ext:cursorShown
	text76ayout:xForIndex text76ayout:lineBoxAt text76ayout:lineOfIndex text76ayout:clusterEnd
	render:emitTiles render:cellMatrix render:tileBounds render:drawnEnd render:tileTint
	render:retilable render:queueRetile render:retileRow node:settleTiles draw:beginSprites
	draw:appendSprite draw:rewriteSprite display76ist:putSpriteInstance render:lanesFor
	render:laneParent render:openLanes render:closeEnclosure render:closeLanes
	render:remapLaneRows render:checkNoOverlap draw:splitRun draw:closeLaneRun
	draw:restoreLaneRun draw:reopenLast display76ist:layLanes display76ist:lanesReorderable
	display76ist:laneSourceHolding"
REBUILD_PATH="render:shapeIfChanged render:drawFiltered label84ext:placeLabel
	label84ext:shapeLabel label84ext:releasePlacement label84ext:runDecorations
	label84ext:lineDecorations
	text76ayout:layout text76ayout:shapeText text76ayout:wrapText text76ayout:pushLine
	text76ayout:pushTruncated text76ayout:forceCells text76ayout:decodeUtf8
	text76ayout:assignFaces text76ayout:assignGrapheme text76ayout:graphemeFace
	text76ayout:breakAfter text76ayout:step
	text76ayout:tallestFaces grapheme:breaksBefore line66reak:lineBreaks line66reak:unitBreak
	glyph65tlas:acquire glyph65tlas:allocate glyph65tlas:placeOnPage
	glyph65tlas:ensurePage glyph65tlas:reclaimPage glyph65tlas:release"
MEASURE_PATH="render:textWidth render:textHeight render:shapedPayload node:labelRow
	node:requireKind"
copied=""
followed=0
allocated=""
unreachable=""
: > out/gate-allocation.log
# $1 bench entry; $2 functions that copy nothing and build no array; $3 that copy nothing and
# call no function named in $4 (textLayout returns the whole layout by value: REVIEWS.md P3 F2).
read_emitted_c() {
	rm -f "out/debug/$(basename "$1" .ms).exe" out/debug/*ZsrcZvoid2dZ*Oms.c
	if ! "$MSC" build "$1" --emit=c >> out/gate-allocation.log 2>&1; then
		unreachable="$unreachable (emitting C for $1 failed)"
		return 0
	fi
	awk -v frame="$(echo $2)" -v copyOnly="$(echo $3)" -v forbidden="$4" \
		-v named="$(echo $FRAME_PATH $REBUILD_PATH $MEASURE_PATH)" \
		-f scripts/allocation.awk out/debug/*ZsrcZvoid2dZ*Oms.c > out/gate-allocation-rows.log
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
	else
		# The graduation rule for a conformance row: every scene it lists must still fail, and
		# a clean run with the row still present fails too.
		row=$(grep -E '^\| conformance:webgl2-pixel-centre ' tests/PENDING.md || true)
		listed=$(echo "$row" | grep -oE '`[a-z]+/[A-Za-z0-9]+`' | tr -d '`' | sort -u)
		failing=$(grep -E '^FAIL' out/gate-golden-web.log | awk '{ print $2 }' | sort -u)
		unlisted=""
		for scene in $failing; do
			case " $(echo $listed) " in *" $scene "*) ;; *) unlisted="$unlisted $scene" ;; esac
		done
		graduated=""
		for scene in $listed; do
			case " $(echo $failing) " in *" $scene "*) ;; *) graduated="$graduated $scene" ;; esac
		done
		if [ -n "$unlisted" ]; then
			fail "webgl2 conformance: failures no PENDING row lists:$unlisted"
		elif [ -n "$row" ] && [ -z "$failing" ]; then
			fail "webgl2 conformance: 0 fail, and tests/PENDING.md conformance:webgl2-pixel-centre survives the run — delete it"
		elif [ -n "$graduated" ]; then
			fail "webgl2 conformance: listed scenes now pass:$graduated — delete them from tests/PENDING.md conformance:webgl2-pixel-centre"
		elif [ -z "$failing" ]; then
			pass "webgl2 conformance: every scene identical or within the cross-backend bound"
		else
			skip "webgl2 conformance: the structural failures are the listed ones — tests/PENDING.md conformance:webgl2-pixel-centre"
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

echo
echo "=== 8. the record against the code ===================================="
"$MSC" build tests/record/check.ms --output=out/recordCheck.exe > out/gate-record.log 2>&1 || true
if [ -x out/recordCheck.exe ] && out/recordCheck.exe >> out/gate-record.log 2>&1; then
	pass "$(grep -E '^record:' out/gate-record.log)"
else
	fail "the record disagrees with the code — see out/gate-record.log"
	grep -E '^FAIL' out/gate-record.log | sed 's/^/      /' || true
fi
# The conformance rows of docs/TESTING.md against the logs this run wrote; a skipped suite has
# no log from this run, so its row is not judged.
if [ "$QUICK" -eq 0 ]; then
	d3d11=$(tr -d '\r' < out/gate-golden.log | sed -nE 's/^golden d3d11: ([0-9]+) pass, [0-9]+ pending, [0-9]+ fail of ([0-9]+)$/\1 \2/p')
	claim="| D3D11 | **${d3d11% *} / ${d3d11#* } scenes byte-identical**"
	if [ -n "$d3d11" ] && grep -qF "$claim" docs/TESTING.md; then
		pass "docs/TESTING.md's D3D11 row matches this run: ${d3d11% *} / ${d3d11#* }"
	else
		fail "docs/TESTING.md's D3D11 row does not match this run's '$(grep -E '^golden d3d11' out/gate-golden.log)'"
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

echo "=== 9. summary ========================================================"
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
