// A host view under continuous frames never waits for a drawable: a burst of frames in one
// vsync is refused once the layer's drawables are all in flight, the refusal returns at once,
// and the frames after it keep one per vsync without a call that waits for the display. A hidden
// window refuses frames instead of waiting in nextDrawable, and draws again once shown.

@include("macViewsHost.h");
@compile("./macViewsHost.m", "-fobjc-arc");
extern function macHostOpen(width: int32, height: int32): int64;
extern function macHostAwaitVsync(): void;
extern function macHostPump(): void;
extern function macHostHide(): void;
extern function macHostShow(): void;
extern function macHostNowMs(): float64;
extern function macHostClose(): void;
extern function macHostBackingWidth(): int32;
extern function macHostBackingHeight(): int32;
extern function macHostScale(): float32;

import { embedRegister, viewCreate, viewReady, viewFrame, viewDestroy, gfxSetup, fbWidth, fbHeight, dpiScale, ViewId, ViewInvalid } from "../../src/sokol/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { present } from "../../src/void2d/scene";
import { BoardState, boardState, boardScene, layoutBoard } from "../../src/examples/viewScenes";
import { exit } from "std/process";

const WARM_TICKS: int32 = 60 as int32;
const STEADY_TICKS: int32 = 240 as int32;
const BURST_LIMIT: int32 = 8 as int32;
const DRAWABLES: int32 = 3 as int32;
const WAITING_MS: float64 = 4.0;
const REFUSAL_MS: float64 = 1.0;
const HIDDEN_MS: float64 = 1000.0;
const SHOWN_WITHIN_MS: float64 = 1000.0;

let _board: BoardState = boardState(6 as int32, 4 as int32);
let _scene: Scene2D | null = null;
let _failures: int32 = 0 as int32;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL frame pacing: ${what}`);
	_failures = _failures + (1 as int32);
}

function initViews(): void {
	gfxSetup();
	setup2d();
	_scene = boardScene(_board);
}

function frameView(): void {
	if (_scene === null) { return; }
	const scale: float32 = dpiScale();
	layoutBoard(_board, (fbWidth() as float32) / scale, (fbHeight() as float32) / scale);
	_scene.present();
}

interface Tally {
	drawn: int32;
	waited: int32;
	slowestMs: float64;
}

function tick(view: ViewId, tally: Tally): void {
	macHostAwaitVsync();
	if (!viewReady(view)) { return; }
	const started: float64 = macHostNowMs();
	const drawn: boolean = viewFrame(view);
	const took: float64 = macHostNowMs() - started;
	if (drawn) { tally.drawn = tally.drawn + (1 as int32); }
	if (took > WAITING_MS) { tally.waited = tally.waited + (1 as int32); }
	if (took > tally.slowestMs) { tally.slowestMs = took; }
}

function run(): int32 {
	embedRegister(initViews, frameView);
	const host: int64 = macHostOpen(320 as int32, 200 as int32);
	const view: ViewId = viewCreate(host, macHostBackingWidth(), macHostBackingHeight(), macHostScale());
	check(view !== ViewInvalid, "viewCreate on the host NSView returned ViewInvalid");

	const warm: Tally = { drawn: 0 as int32, waited: 0 as int32, slowestMs: 0.0 };
	for (let i: int32 = 0 as int32; i < WARM_TICKS; i++) { tick(view, warm); }

	macHostAwaitVsync();
	let admitted: int32 = 0 as int32;
	let refusalMs: float64 = -1.0;
	for (let i: int32 = 0 as int32; i < BURST_LIMIT; i++) {
		const started: float64 = macHostNowMs();
		const drawn: boolean = viewFrame(view);
		const took: float64 = macHostNowMs() - started;
		if (!drawn) {
			refusalMs = took;
			break;
		}
		admitted = admitted + (1 as int32);
	}
	check(refusalMs >= 0.0, `a burst of ${BURST_LIMIT} frames in one vsync was never refused`);
	check(admitted <= DRAWABLES, `a burst admitted ${admitted} frames, more than the ${DRAWABLES} drawables`);
	check(refusalMs < REFUSAL_MS, `the refused frame took ${refusalMs} ms`);

	const steady: Tally = { drawn: 0 as int32, waited: 0 as int32, slowestMs: 0.0 };
	for (let i: int32 = 0 as int32; i < STEADY_TICKS; i++) { tick(view, steady); }
	check(steady.waited <= (2 as int32), `${steady.waited} of ${steady.drawn} frames after the burst took over ${WAITING_MS} ms (slowest ${steady.slowestMs} ms)`);
	check(steady.drawn * (10 as int32) >= STEADY_TICKS * (9 as int32), `only ${steady.drawn} of ${STEADY_TICKS} vsyncs after the burst drew a frame`);

	macHostHide();
	const hidden: Tally = { drawn: 0 as int32, waited: 0 as int32, slowestMs: 0.0 };
	const hiddenStart: float64 = macHostNowMs();
	while (macHostNowMs() - hiddenStart < HIDDEN_MS) {
		macHostPump();
		if (!viewReady(view)) { continue; }
		const started: float64 = macHostNowMs();
		if (viewFrame(view)) { hidden.drawn = hidden.drawn + (1 as int32); }
		const took: float64 = macHostNowMs() - started;
		if (took > WAITING_MS) { hidden.waited = hidden.waited + (1 as int32); }
	}
	check(hidden.waited <= (2 as int32), `a hidden window waited over ${WAITING_MS} ms in ${hidden.waited} of ${hidden.drawn} frames`);

	macHostShow();
	let shownAfterMs: float64 = -1.0;
	const shownStart: float64 = macHostNowMs();
	while (shownAfterMs < 0.0 && macHostNowMs() - shownStart < SHOWN_WITHIN_MS) {
		macHostPump();
		if (viewReady(view) && viewFrame(view)) { shownAfterMs = macHostNowMs() - shownStart; }
	}
	check(shownAfterMs >= 0.0, `no frame drew within ${SHOWN_WITHIN_MS} ms of showing the window again`);

	viewDestroy(view);
	macHostClose();
	if (_failures === (0 as int32)) {
		console.log(`PASS frame pacing: burst refused after ${admitted} frames in ${refusalMs} ms; ${steady.drawn}/${STEADY_TICKS} vsyncs drawn after it, slowest ${steady.slowestMs} ms; hidden ${hidden.drawn} frames, ${hidden.waited} waited; shown again drew after ${shownAfterMs} ms`);
	}
	return _failures === (0 as int32) ? (0 as int32) : (1 as int32);
}

exit(run());
