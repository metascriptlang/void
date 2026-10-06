import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { imageAlive, liveImages } from "../../src/gpu/door";
import { Texture, TextureError } from "../../src/gpu/texture";
import { Scene2D } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d, buffersAlive, glyphPageCount } from "../../src/void2d/draw";
import { renderTargetsAlive } from "../../src/void2d/render";
import { rgba, blurFilter, tile } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureSlotsDiffer, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 160;
const HEIGHT: int32 = 120;
const CHECKER: int32 = 4;
const RELEASES: int32 = 8;
const RED: uint32 = 0xff2020e0 as uint32;
const YELLOW: uint32 = 0xff20e0e0 as uint32;
const CLEAR = rgba(0.05, 0.05, 0.1, 1.0);
const s: Scene2D = Scene2D.create(CLEAR);
let stage: int32 = 0;
let kept: Texture | null = null;
let keptImage: uint32 = 0;
let paintedBuffers: int32 = 0;
let paintedTargets: int32 = 0;
let paintedImages: int32 = 0;
let paintedPages: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL scene occlusion: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function checker(a: uint32, b: uint32): Vec<uint32> {
	let pixels: Vec<uint32> = new Array(0);
	for (let y: int32 = 0; y < CHECKER; y++) {
		for (let x: int32 = 0; x < CHECKER; x++) { pixels.push((x + y) % 2 == 0 ? a : b); }
	}
	return pixels;
}

function made(result: Result<Texture, TextureError>): Texture {
	if (result.ok) { return result.value; }
	console.log(`FAIL scene occlusion: the texture was refused, ${result.error.toString()}`);
	voidCaptureExit(1);
	unreachable;
}

function exerciseMisuse(misuse: string): void {
	if (misuse.equals("prepared")) {
		s.prepare(WIDTH as float32, HEIGHT as float32, 1.0);
		s.releaseGpu();
	}
	if (misuse.equals("closed")) {
		s.close();
		s.releaseGpu();
	}
	console.log(`releaseGpu accepted ${misuse}`);
	voidCaptureExit(0);
}

function init(): void {
	gfxSetup();
	setup2d();
	const pixels: Vec<uint32> = checker(RED, YELLOW);
	const texture: Texture = made(Texture.fromPixels(pixels, CHECKER, CHECKER, false));
	kept = texture;
	keptImage = texture.image;
	s.add(s.rect(24.0, 24.0, rgba(0.9, 0.1, 0.1, 1.0)).at(8.0, 8.0));
	s.add(s.sprite(tile(texture, 32.0, 32.0)).at(40.0, 8.0));
	s.add(s.label("Ag", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(8.0, 56.0));
	s.add(s.rect(24.0, 24.0, rgba(0.2, 0.3, 1.0, 1.0)).at(100.0, 60.0)).setFilter(blurFilter(3.0));
	const misuse: string = env.get("VOID_SCENE_OCCLUSION_MISUSE");
	if (!misuse.equals("")) { exerciseMisuse(misuse); }
}

function release(): void {
	s.releaseGpu();
	s.releaseGpu();
	if (!s.isDirty()) { fail("a released scene does not ask to be painted again"); }
	if (buffersAlive() >= paintedBuffers) {
		fail(`release kept the list buffers: ${buffersAlive()} of ${paintedBuffers}`);
	}
	if (renderTargetsAlive() != 0) {
		fail(`release kept ${renderTargetsAlive()} filter targets`);
	}
	if (!imageAlive(keptImage)) { fail("release destroyed the caller's texture"); }
	if (glyphPageCount() != paintedPages) {
		fail(`release changed the glyph pages: ${glyphPageCount()} of ${paintedPages}`);
	}
}

function repaint(): void {
	s.present();
	if (buffersAlive() != paintedBuffers || renderTargetsAlive() != paintedTargets) {
		fail(
			`the repaint after release did not return to the painted resources: buffers ` +
			`${buffersAlive()} of ${paintedBuffers}, ` +
			`targets ${renderTargetsAlive()} of ${paintedTargets}`,
		);
	}
	if (liveImages() != paintedImages) {
		fail(`the repaint made images again: ${liveImages()} of ${paintedImages}`);
	}
	if (kept === null || kept.image != keptImage) { fail("the texture was made again"); }
	if (voidCaptureGrab(1) == 0) { fail("readback after release failed"); }
	if (voidCaptureSlotsDiffer() != 0) {
		fail(`${voidCaptureSlotsDiffer()} pixels differ after release and repaint`);
	}
}

function frame(): void {
	if (stage == 0) {
		s.present();
		paintedBuffers = buffersAlive();
		paintedTargets = renderTargetsAlive();
		paintedImages = liveImages();
		paintedPages = glyphPageCount();
		if (paintedTargets == 0) { fail("the blurred rect took no filter target"); }
		if (paintedPages == 0) { fail("the label took no glyph page"); }
		if (voidCaptureGrab(0) == 0) { fail("first readback failed"); }
	} else if (stage % 2 == 1) {
		release();
	} else {
		repaint();
	}
	stage = stage + 1;
	if (stage <= RELEASES * 2) { return; }
	console.log(
		`PASS scene occlusion: ${RELEASES} releases freed the scene's list buffers and filter ` +
		"targets, kept its texture and glyph pages, and each repaint was byte-identical",
	);
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
