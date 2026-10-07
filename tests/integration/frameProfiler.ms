import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import {
	setup2d, openBracket, startContext, finishRecording, flushTargets, end2d,
	drawUiInstance, drawSpriteAffine,
} from "../../src/void2d/draw";
import { DrawContext2D, useContext } from "../../src/void2d/displayList";
import { InstanceMode, uiInstance } from "../../src/void2d/instance";
import { Color, identity2d, rgba } from "../../src/void2d/types";
import { BlendMode } from "../../src/gpu/state";
import {
	frameStats, profilerCollect, lastFrameRecord, frameCommitsWithoutFrame,
} from "../../src/void2d/frameMarks";
import { voidCaptureBackend, voidCaptureExit } from "../capture/capture.h";

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

function drawFrame(): void {
	const before: int32 = frameStats.frames;
	recordTwoContexts();
	presentTwoContexts();
	checkMarks(before);
}

function frame(): void {
	drawFrame();
	stage = stage + 1;
	if (stage < FRAMES) { return; }
	console.log(`PASS frame profiler: ${FRAMES} frames, one record each, marks in order`);
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(120, 60, 1, 0, init, frame);
