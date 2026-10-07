import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { contextGeneration, loseContext } from "../../src/gpu/door";
import { Texture, TextureError } from "../../src/gpu/texture";
import { Scene2D } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba, blurFilter, tile } from "../../src/void2d/types";
when (voidSvg) {
	import { registerIcon } from "../../src/void2d/icon";
}
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureSlotsDiffer, voidCaptureWritePng,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 160;
const HEIGHT: int32 = 120;
const CHECKER: int32 = 4;
const RED: uint32 = 0xff2020e0 as uint32;
const YELLOW: uint32 = 0xff20e0e0 as uint32;
const GREEN: uint32 = 0xff20e020 as uint32;
const ICON_SOURCE: string = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" ` +
	`viewBox="0 0 24 24"><path d="M12 2 L22 12 L12 22 L2 12 Z" fill="#000"/></svg>`;
const CLEAR = rgba(0.05, 0.05, 0.1, 1.0);
const s: Scene2D = Scene2D.create(CLEAR);
let stage: int32 = 0;
let firstGeneration: int32 = 0;
let hookCalls: int32 = 0;
let decoys: Vec<Texture> = new Array(0);

function fail(message: string): void {
	console.log(`FAIL device loss: stage ${stage}: ${message}`);
	const _written: int32 = voidCaptureWritePng(1, "out/tmp/deviceLossAfter.png");
	voidCaptureExit(1);
}

function checker(a: uint32, b: uint32): Vec<uint32> {
	let pixels: Vec<uint32> = new Array(0);
	for (let y: int32 = 0; y < CHECKER; y++) {
		for (let x: int32 = 0; x < CHECKER; x++) { pixels.push((x + y) % 2 == 0 ? a : b); }
	}
	return pixels;
}

function solid(color: uint32): Vec<uint32> {
	let pixels: Vec<uint32> = new Array(0);
	for (let i: int32 = 0; i < CHECKER * CHECKER; i++) { pixels.push(color); }
	return pixels;
}

function made(result: Result<Texture, TextureError>, what: string): Texture {
	if (result.ok) { return result.value; }
	console.log(`FAIL device loss: the ${what} texture was refused, ${result.error.toString()}`);
	voidCaptureExit(1);
	unreachable;
}

function decodeAgain(texture: Texture): void {
	hookCalls = hookCalls + 1;
	const uploaded: Result<int32, TextureError> = texture.upload(checker(YELLOW, RED));
	if (!uploaded.ok) { fail(`the realloc hook's upload was refused, ${uploaded.error.toString()}`); }
}

function init(): void {
	gfxSetup();
	setup2d();
	const kept: Texture = made(Texture.fromPixels(checker(RED, YELLOW), CHECKER, CHECKER, true), "kept");
	const hooked: Texture = Texture.create(CHECKER, CHECKER, decodeAgain);
	const first: Result<int32, TextureError> = hooked.upload(checker(YELLOW, RED));
	if (!first.ok) { fail(`the hooked texture was refused, ${first.error.toString()}`); }
	s.add(s.rect(24.0, 24.0, rgba(0.9, 0.1, 0.1, 1.0)).at(8.0, 8.0));
	s.add(s.sprite(tile(kept, 32.0, 32.0)).at(40.0, 8.0));
	s.add(s.sprite(tile(hooked, 32.0, 32.0)).at(80.0, 8.0));
	s.add(s.label("Ag", 16.0, rgba(1.0, 1.0, 1.0, 1.0)).at(8.0, 56.0));
	when (voidSvg) {
		const icon = registerIcon(ICON_SOURCE);
		if (!icon.ok) { fail(`the icon was refused, ${icon.error.what}`); }
		if (icon.ok) {
			s.add(s.icon(icon.value, 24.0, 24.0, rgba(0.95, 0.75, 0.2, 1.0)).at(48.0, 52.0));
		}
	}
	s.add(s.rect(24.0, 24.0, rgba(0.2, 0.3, 1.0, 1.0)).at(100.0, 60.0)).setFilter(blurFilter(3.0));
	const misuse: string = env.get("VOID_DEVICE_LOSS_MISUSE");
	if (misuse.equals("adopted")) {
		const adopted: Texture = Texture.adopt(kept.image, kept.view, CHECKER, CHECKER);
		s.add(s.sprite(tile(adopted, 16.0, 16.0)).at(120.0, 8.0));
	}
	if (misuse.equals("reupload")) {
		const _again: Result<int32, TextureError> = kept.upload(checker(YELLOW, RED));
		console.log("a texture with a live image took new pixels");
		voidCaptureExit(0);
	}
}

function claimRecycledIds(): void {
	for (let i: int32 = 0; i < 4; i++) {
		decoys.push(made(Texture.fromPixels(solid(GREEN), CHECKER, CHECKER, false), "decoy"));
	}
}

function compareWithBefore(what: string): void {
	if (voidCaptureGrab(1) == 0) { fail(`readback ${what} failed`); }
	const differ: int32 = voidCaptureSlotsDiffer();
	if (differ != 0) { fail(`${differ} pixels differ ${what}`); }
}

function frame(): void {
	if (stage == 0) {
		firstGeneration = contextGeneration();
		s.present();
		if (voidCaptureGrab(0) == 0) { fail("readback before the loss failed"); }
		const _written: int32 = voidCaptureWritePng(0, "out/tmp/deviceLossBefore.png");
		loseContext();
	} else if (stage == 1) {
		if (contextGeneration() != firstGeneration + 1) {
			fail(`the context generation is ${contextGeneration()}, not ${firstGeneration + 1}`);
		}
		claimRecycledIds();
		s.present();
		compareWithBefore("after the first loss");
		if (hookCalls != 1) { fail(`the realloc hook ran ${hookCalls} times, not once`); }
	} else if (stage == 2) {
		s.present();
		compareWithBefore("on the retained frame after the loss");
	} else if (stage == 3) {
		loseContext();
		s.present();
		compareWithBefore("on the frame that asked for the second loss");
	} else {
		if (contextGeneration() != firstGeneration + 2) {
			fail(`the context generation is ${contextGeneration()}, not ${firstGeneration + 2}`);
		}
		s.present();
		compareWithBefore("after the second loss");
		if (hookCalls != 2) { fail(`the realloc hook ran ${hookCalls} times, not twice`); }
		console.log(
			"PASS device loss: two forced losses, each next frame byte-identical; kept pixels and a " +
			"realloc hook re-uploaded, recycled ids drew nothing of theirs",
		);
		voidCaptureExit(0);
	}
	stage = stage + 1;
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
