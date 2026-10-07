import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import {
	setup2d, openBracket, startContext, finishRecording, flushTargets, end2d,
	drawUiInstance, drawSpriteAffine, drawCallCount,
} from "../../src/void2d/draw";
import { DrawContext2D, useContext } from "../../src/void2d/displayList";
import { InstanceMode, uiInstance } from "../../src/void2d/instance";
import { Color, identity2d, rgba } from "../../src/void2d/types";
import { BlendMode } from "../../src/gpu/state";
import {
	frameStats, profilerCollect, lastFrameRecord, frameCommitsWithoutFrame, lastFrameCounters,
} from "../../src/void2d/frameMarks";
import { Scene2D } from "../../src/void2d/node";
import { add, presentAt } from "../../src/void2d/scene";
import { NO_STAMP } from "../../src/void2d/profiler";
import { profilerNow } from "../../src/void2d/frameMarks";
import { OverlayMode, frameProfiler } from "../../src/void2d/profiler";
import {
	PANEL_MARGIN, overlayModel, layoutOverlay, cellPixels, profilerOverlayFeedLive,
	profilerOverlayFeed, profilerOverlaySetMode,
} from "../../src/void2d/profilerOverlay";
import { fixtureProfiler, fixtureCounters } from "../harness/profilerFixture";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const FRAMES: int32 = 120;
const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);
const a: DrawContext2D = DrawContext2D.create();
const b: DrawContext2D = DrawContext2D.create();
let stage: int32 = 0;

function init(): void { gfxSetup(); setup2d(); }

function fail(message: string): void {
	console.log(`FAIL frame profiler: ${message}`);
	voidCaptureExit(1);
}

function card(x: float32): void {
	drawUiInstance(0 as uint32, BlendMode.Alpha,
		uiInstance(InstanceMode.Box, identity2d(), x, 0.0, 8.0, 8.0, WHITE));
}

function recordTwoContexts(): void {
	useContext(a);
	openBracket(120.0, 60.0, 1.0);
	startContext();
	for (let i: int32 = 0; i < 5; i++) { card(10.0 * (i as float32)); }
	drawSpriteAffine(0 as uint32, false, BlendMode.Alpha, identity2d(),
		0.0, 20.0, 8.0, 8.0, 0.0, 0.0, 1.0, 1.0, WHITE);
	useContext(b);
	openBracket(120.0, 60.0, 1.0);
	startContext();
	for (let i: int32 = 0; i < 3; i++) { card(10.0 * (i as float32)); }
	useContext(a);
	finishRecording();
	flushTargets();
	useContext(b);
	finishRecording();
	flushTargets();
}

function presentTwoContexts(): void {
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	useContext(a); end2d();
	useContext(b); end2d();
	endPass();
	commit();
}

function checkMarks(framesBefore: int32): void {
	if (!profilerCollect()) { fail("a committed frame produced no record"); }
	if (frameStats.frames != framesBefore + 1) { fail("one frame did not become one record"); }
	if (lastFrameRecord().serial != frameStats.frames) { fail("record serial is not frame count"); }
	if (lastFrameRecord().drawNs <= 0) { fail("draw time is not above zero"); }
	if (lastFrameRecord().presentNs < 0) { fail("present time is negative"); }
	if (frameCommitsWithoutFrame() != 0) { fail("a steady loop counted a commit with no frame"); }
}

function checkCounters(): void {
	const c = lastFrameCounters();
	if (c.void2dDraws != 3) { fail(`void2d draws ${c.void2dDraws}, expected 3`); }
	if (c.uiInstances != 8) { fail(`ui instances ${c.uiInstances}, expected 8 over two brackets`); }
	if (c.spriteInstances != 1) { fail(`sprite instances ${c.spriteInstances}, expected 1`); }
	if (!c.sokolMeasured) { fail("sokol frame stats were not read"); }
	if (c.sokolDraws < c.void2dDraws) { fail("sokol counted fewer draws than void2d"); }
	if (c.sokolPasses < 1) { fail("sokol counted no pass"); }
	if (c.uploadBytes <= 0) { fail("void2d counted no upload bytes"); }
	if (c.uploadBytes > c.sokolBufferBytes + c.sokolImageBytes) {
		fail("void2d counted more upload bytes than sokol saw");
	}
}

function drawFrame(): void {
	const before: int32 = frameStats.frames;
	recordTwoContexts();
	presentTwoContexts();
	checkMarks(before);
	checkCounters();
}

let scene: Scene2D = null as unknown as Scene2D;
const MIN_DIRTY_WAIT_NS: int64 = 20000000;

function waitNs(ns: int64): void {
	const start: int64 = profilerNow();
	while (profilerNow() - start < ns) {}
}

function mutationStep(step: int32): void {
	if (step == 0) {
		scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		scene.add(scene.rect(8.0, 8.0, WHITE).at(2.0, 2.0));
		scene.presentAt(1.0);
		profilerCollect();
		return;
	}
	if (step == 1) {
		const before: int32 = frameStats.frames;
		scene.add(scene.rect(4.0, 4.0, WHITE).at(30.0, 2.0));
		waitNs(MIN_DIRTY_WAIT_NS);
		scene.presentAt(1.0);
		if (!profilerCollect() || frameStats.frames != before + 1) {
			fail("the mutated frame left no record");
		}
		if (lastFrameRecord().dirtyToPresentNs < MIN_DIRTY_WAIT_NS) {
			fail(`dirty to present ${lastFrameRecord().dirtyToPresentNs} ns is under 20 ms`);
		}
		return;
	}
	const before: int32 = frameStats.frames;
	scene.presentAt(1.0);
	if (!profilerCollect() || frameStats.frames != before + 1) {
		fail("the still frame left no record");
	}
	if (lastFrameRecord().dirtyToPresentNs != NO_STAMP) {
		fail("a still frame recorded a dirty to present sample");
	}
}

const OVERLAY_STEPS: int32 = 3;
const WIDTH: int32 = 320;
const HEIGHT: int32 = 96;

function greenSignature(fromX: int32, toX: int32): int64 {
	if (voidCaptureGrab(0) == 0) { fail("the overlay frame could not be read back"); }
	let signature: int64 = 0;
	for (let y: int32 = 0; y < HEIGHT; y++) {
		for (let x: int32 = fromX; x < toX; x++) {
			const pixel: int64 = voidCapturePixel(0, x, y);
			const r: int64 = (pixel >> 24) & 255;
			const g: int64 = (pixel >> 16) & 255;
			if (g > 200 && r < 100) {
				signature = signature + ((x + 1) as int64) * 997 + ((y + 1) as int64);
			}
		}
	}
	return signature;
}

function panelLeft(): int32 {
	const model = overlayModel(frameStats, lastFrameCounters(), OverlayMode.Minimal);
	const cell: int32 = cellPixels(1.0);
	return WIDTH - (layoutOverlay(model).widthCells + PANEL_MARGIN) * cell;
}

function overlayStep(step: int32): void {
	if (step == 0) {
		profilerOverlayFeedLive();
		profilerOverlaySetMode(OverlayMode.Minimal);
		if (scene.isDirty()) { fail("switching the overlay on dirtied the host scene"); }
		scene.presentAt(1.0);
		if (drawCallCount() != 2) { fail(`overlay on drew ${drawCallCount()} calls, expected 2`); }
		const left: int32 = panelLeft();
		if (left < 0) { fail(`the ${WIDTH} px window is narrower than the minimal panel`); }
		if (greenSignature(left, WIDTH) == 0) { fail("the panel left no text pixel at the right"); }
		if (greenSignature(0, left) != 0) { fail("overlay text reached left of the panel"); }
		return;
	}
	if (step == 1) {
		scene.presentAt(1.0);
		const before: int64 = greenSignature(0, WIDTH);
		profilerOverlayFeed(fixtureProfiler(), fixtureCounters());
		scene.presentAt(1.0);
		const fixture: int64 = greenSignature(0, WIDTH);
		if (fixture == 0 || fixture == before) { fail("a new readout did not reach the screen"); }
		profilerOverlayFeed(frameProfiler(), fixtureCounters());
		scene.presentAt(1.0);
		if (greenSignature(0, WIDTH) == fixture) { fail("an empty readout did not reach it"); }
		return;
	}
	profilerOverlaySetMode(OverlayMode.Hidden);
	scene.presentAt(1.0);
	if (drawCallCount() != 1) { fail(`overlay hidden drew ${drawCallCount()} calls, expected 1`); }
	if (greenSignature(0, WIDTH) != 0) { fail("a hidden overlay still painted text pixels"); }
}

function frame(): void {
	if (stage < FRAMES) {
		drawFrame();
		stage = stage + 1;
		return;
	}
	if (stage < FRAMES + 3) {
		mutationStep(stage - FRAMES);
	} else {
		overlayStep(stage - FRAMES - 3);
	}
	stage = stage + 1;
	if (stage < FRAMES + 3 + OVERLAY_STEPS) { return; }
	console.log(
		`PASS frame profiler: ${FRAMES} frames, counters, dirty to present, still frame, overlay`,
	);
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
