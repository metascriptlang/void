// The golden runner: one scene per process, selected by the VOID_SCENE environment
// variable, captured to out/golden/<backend>/<name>.png. scripts/golden.sh drives it, and
// tests/golden/compare.ms is what judges the result.
//
// One scene per process is not tidiness. sokol's default resource pools hold 128 objects
// and today every Label and Graphics owns an sg_buffer (VOID2D.md "Known defects", P1), so
// a process that builds several Label-heavy scenes hits the cap partway through and
// captures a scene with nodes missing — which would then become the golden.
//
// The window is opened with sample_count 1 and high_dpi off. Both are deliberate:
//   - 4x MSAA is on only for the sokol_app entry (bridge.c:56) and off on iOS, Android and
//     the embed bridges, so a golden taken with it could never be the single golden set
//     every backend is compared against (guardrail 9, docs/TESTING.md). It is also not
//     reproducible: at sample_count 4 the demo scene's D3D11 resolve differs by one or two
//     pixels between runs of the same binary, and at sample_count 1 it is byte-identical.
//   - high_dpi off makes the framebuffer exactly the size the table asks for and
//     voidDpiScale() 1.0, whatever the host display reports. A scene's DPI comes from the
//     table instead, through Scene.presentAt.
//
// Each scene is drawn three times: once to warm up — the first draw of a Label rasterizes
// its glyphs, and a fontstash atlas resize re-lays out every label — and then twice, into
// the two capture slots. The two captures must be identical before either is written out.

import { SceneRow, sceneRows, sceneCount, backendDirectory } from "./table";
import { sceneBuilders } from "./scenes";
import { Scene, presentAt } from "../../src/void2d/scene";
import { gfxSetup } from "../../src/sokol/gpu";
import { setup2d, drawCallCount } from "../../src/void2d/draw";
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
const builders: (() => Scene)[] = sceneBuilders();
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
	current = builders[index]();
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

	const path: string = `out/golden/${backendDirectory(voidCaptureBackend())}/${row.name}.png`;
	if (voidCaptureWritePng(1, path) == 0) {
		console.log(`FAIL ${row.name} could not write ${path}`);
		voidCaptureExit(EXIT_FAILED);
	}
	console.log(`CAPTURED ${row.name} ${width}x${height} dpi ${row.dpi} draws ${drawCallCount()} -> ${path}`);
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
	if ((builders.length as int32) != sceneCount()) {
		console.log(`FAIL the table has ${sceneCount()} rows and scenes.ms has ${builders.length as int32} builders`);
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
