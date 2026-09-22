import { initRenderer, drawRendererAt } from "../../src/examples/rendererSokol";
import { fbWidth, fbHeight, beginPass, endPass } from "../../src/sokol/gpu";
import { setup2d, begin2d, flushTargets, end2d, fillQuad, drawCallCount } from "../../src/void2d/draw";
import { BlendMode, vec2, rgba } from "../../src/void2d/types";
import { DrawContext } from "../../src/void3d/draw";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, endFrame } from "../../src/void3d/renderer";
import {
	voidCaptureBackend,
	voidCaptureGrab,
	voidCaptureSlotsDiffer,
	voidCaptureUniform,
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

function createCore(): Renderer {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const created: Result<Renderer, RendererError> = Renderer.create(context);
	if (created.ok) { return created.value; }
	unreachable;
}

let core: Renderer = createCore();
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL mixed frame: ${message}`);
	voidCaptureExit(1);
}

function initMixed(): void {
	initRenderer();
	setup2d();
}

function drawMixed(): void {
	begin2d(fbWidth() as float32, fbHeight() as float32, 1.0);
	fillQuad(
		vec2(16.0, 16.0), vec2(112.0, 16.0), vec2(112.0, 64.0), vec2(16.0, 64.0),
		rgba(0.15, 0.72, 0.92, 0.88), BlendMode.Alpha,
	);
	flushTargets();

	beginPass(0.05, 0.05, 0.15, 1.0);
	drawRendererAt(0.6);
	end2d();
	endPass();

	endFrame(core);
	if (drawCallCount() != 1) {
		fail(`void2d draw counter is ${drawCallCount()}, expected one fresh draw`);
	}
}

function grab(slot: int32): void {
	if (voidCaptureGrab(slot) == 0) {
		fail(`capture slot ${slot} failed`);
	}
}

function frame(): void {
	drawMixed();
	grab(stage);
	stage = stage + 1;
	if (stage < 2) { return; }
	if (voidCaptureUniform(0) != 0 || voidCaptureUniform(1) != 0) {
		fail("a composed frame is uniform");
	}
	const differ: int32 = voidCaptureSlotsDiffer();
	if (differ != 0) {
		fail(`the two fixed-state frames differ in ${differ} pixels`);
	}
	console.log("PASS mixed frame: 3D + void2d, one shared commit, two fresh frames");
	voidCaptureExit(0);
}

function start(): void {
	if (voidCaptureBackend() == 0) {
		console.log("SKIP mixed frame: this build has no readback path");
		voidCaptureExit(3);
	}
	voidRunConfigured(320, 240, 1, 0, initMixed, frame);
}

start();
