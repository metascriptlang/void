// The golden runner: one scene per process, selected by the VOID_SCENE environment
// variable, captured to out/golden/<backend>/<name>.png. scripts/golden.sh drives it, and
// tests/golden/compare.ms is what judges the result.
//
// One scene per process isolates GPU-resource and atlas state. A capture cannot inherit pooled
// targets from another row or hide a leak behind resources that row already allocated.
//
// The window is opened with sample_count 1 and high_dpi off. Both are deliberate:
//   - 4x MSAA is on only for the sokol_app entry (bridgeWin.c voidRun) and off on iOS, Android and
//     the embed bridges, so a golden taken with it could never be the single golden set
//     every backend is compared against (guardrail 9, docs/TESTING.md). It is also not
//     reproducible: at sample_count 4 the demo scene's D3D11 resolve differs by one or two
//     pixels between runs of the same binary, and at sample_count 1 it is byte-identical.
//   - high_dpi off makes the framebuffer exactly the size the table asks for and
//     voidDpiScale() 1.0, whatever the host display reports. A scene's DPI comes from the
//     table instead, through Scene.presentAt.
//
// Each scene is drawn three times: once to warm up — the first draw of a Label shapes it and
// rasterizes its glyphs into the atlas — and then twice, into the two capture slots. The two
// captures must be identical before either is written out.

import {
	SceneRow,
	sceneRows,
	sceneCount,
	sceneDrawCounts,
	sceneRenderTargetCounts,
	backendDirectory,
} from "./table";
import { SceneBuilder, sceneBuilders } from "./scenes";
import { Scene, presentAt } from "../../src/void2d/scene";
import { gfxSetup } from "../../src/sokol/gpu";
import { setup2d, drawCallCount } from "../../src/void2d/draw";
import { renderTargetsAlive } from "../../src/void2d/render";
import { init2d, step2d, present2d } from "../../src/examples/renderer2d";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCaptureWidth,
	voidCaptureHeight,
	voidCaptureSlotsDiffer,
	voidCaptureUniform,
	voidCaptureWritePng,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

const EXIT_OK: int32 = 0;
const EXIT_FAILED: int32 = 1;
const EXIT_BAD_USAGE: int32 = 2;
const EXIT_NO_READBACK: int32 = 3;

const rows: SceneRow[] = sceneRows();
const expectedDraws: int32[] = sceneDrawCounts();
const expectedRenderTargets: int32[] = sceneRenderTargetCounts();
const builders: SceneBuilder[] = sceneBuilders();
let index: int32 = 0;
let current: Scene | null = null;
let stage: int32 = 0;

function describeTable(): void {
	for (const row of rows) {
		console.log(`${row.name}\t${row.phase}\t${row.width}\t${row.height}\t${row.dpi}\t${row.steps}`);
	}
}

function initScene(): void {
	const row = rows[index];
	if (row.demo) {
		init2d();
		for (let i: int32 = 0; i < row.steps; i++) {
			step2d(1.0 / 60.0);
		}
		return;
	}
	gfxSetup();
	setup2d();
	current = builders[index].build();
}

function drawOnce(): void {
	const row = rows[index];
	if (row.demo) {
		present2d();
		return;
	}
	const s = current;
	if (s === null) { return; }
	s.presentAt(row.dpi);
}

// Everything that has to hold before a capture may become a golden. A failure here is a
// harness finding, not a renderer finding, and says so.
function finish(): void {
	const row = rows[index];
	const width: int32 = voidCaptureWidth(1);
	const height: int32 = voidCaptureHeight(1);

	if (width != row.width || height != row.height) {
		console.log(`FAIL ${row.name} capture is ${width}x${height}, the table says ${row.width}x${row.height}`);
		voidCaptureExit(EXIT_FAILED);
	}
	if (voidCaptureUniform(1) != 0) {
		console.log(`FAIL ${row.name} every pixel is one colour — captured before the draw, or a constant readback`);
		voidCaptureExit(EXIT_FAILED);
	}
	const differ: int32 = voidCaptureSlotsDiffer();
	if (differ != 0) {
		console.log(`FAIL ${row.name} is not deterministic: two draws of the same state differ in ${differ} pixels`);
		voidCaptureExit(EXIT_FAILED);
	}

	const draws: int32 = drawCallCount();
	const targets: int32 = renderTargetsAlive();
	if (draws != expectedDraws[index] || targets != expectedRenderTargets[index]) {
		console.log(
			`FAIL ${row.name} counters are draws ${draws}, renderTargets ${targets};`
			+ ` expected ${expectedDraws[index]}, ${expectedRenderTargets[index]}`,
		);
		voidCaptureExit(EXIT_FAILED);
	}

	const path: string = `out/golden/${backendDirectory(voidCaptureBackend())}/${row.name}.png`;
	if (voidCaptureWritePng(1, path) == 0) {
		console.log(`FAIL ${row.name} could not write ${path}`);
		voidCaptureExit(EXIT_FAILED);
	}
	console.log(
		`CAPTURED ${row.name} ${width}x${height} dpi ${row.dpi} draws ${draws}`
		+ ` renderTargets ${targets} -> ${path}`,
	);
	voidCaptureExit(EXIT_OK);
}

function grabInto(slot: int32): void {
	if (voidCaptureGrab(slot) != 0) { return; }
	console.log(`FAIL ${rows[index].name} readback failed on slot ${slot}`);
	voidCaptureExit(EXIT_FAILED);
}

const WARMUP_DRAWS: int32 = 1;

function frame(): void {
	if (stage < WARMUP_DRAWS) {
		drawOnce();
		stage = stage + 1;
		return;
	}
	if (stage == WARMUP_DRAWS) {
		drawOnce();
		grabInto(0);
		stage = stage + 1;
		return;
	}
	drawOnce();
	grabInto(1);
	finish();
}

function startRunner(): void {
	// Name by name, not just length. Rexa's cross-check that the command table agrees with
	// the parser is by name, and it has to be: two lists of the same length whose entries
	// are off by one would render a correct image under the wrong row's name, and
	// `golden.sh --update` would commit it as that row's golden.
	if ((builders.length as int32) != sceneCount()) {
		console.log(
			`FAIL the table has ${sceneCount()} rows`
			+ ` and scenes.ms has ${builders.length as int32} builders`,
		);
		voidCaptureExit(EXIT_BAD_USAGE);
	}
	if ((expectedDraws.length as int32) != sceneCount()
		|| (expectedRenderTargets.length as int32) != sceneCount()) {
		console.log("FAIL the golden counter vectors do not cover every scene row");
		voidCaptureExit(EXIT_BAD_USAGE);
	}
	for (let i: int32 = 0; i < sceneCount(); i++) {
		if (rows[i].name.equals(builders[i].name)) { continue; }
		console.log(
			`FAIL row ${i} is '${rows[i].name}' in table.ms`
			+ ` and '${builders[i].name}' in scenes.ms`,
		);
		voidCaptureExit(EXIT_BAD_USAGE);
	}
	if (voidCaptureEnvInt("VOID_SCENE_LIST", 0) != 0) {
		describeTable();
		voidCaptureExit(EXIT_OK);
	}
	if (voidCaptureBackend() == 0) {
		console.log("SKIP this build has no readback path — tests/capture/capture.c covers D3D11 and GLES3 only");
		voidCaptureExit(EXIT_NO_READBACK);
	}
	index = voidCaptureEnvInt("VOID_SCENE", -1);
	if (index < 0 || index >= sceneCount()) {
		console.log(`FAIL VOID_SCENE must be 0..${sceneCount() - 1}, got ${index}`);
		voidCaptureExit(EXIT_BAD_USAGE);
	}
	const row = rows[index];
	voidRunConfigured(row.width, row.height, 1, 0, initScene, frame);
}

startRunner();
