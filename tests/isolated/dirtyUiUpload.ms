// Run in a process of its own (tests/isolated): it sets the door's device up.
//
// A retained scene that edits some UI instances uploads those instances' bytes and no others, in
// ascending order with touching ranges merged, and a grown buffer is written whole.

import { doorSetup, doorSubmitFrame, doorReadTexture } from "../../src/gpu/doorGpu";
import { RenderTarget } from "../../src/gpu/target";
import { PixelFormat } from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create, add, prepare, drawTarget, close } from "../../src/void2d/scene";
import { setup2d, frameEnd, uploadBytes, uploadCount } from "../../src/void2d/draw";
import { rgba, Color } from "../../src/void2d/types";
import { UI_STRIDE } from "../../src/void2d/instanceLayout";

when (voidDummy) {
} else when (windows) {
	import { warpDevice, warpContext } from "../../src/test/d3d11Warp.h";
	@passL("-ld3d11");
} else when (macos) {
	import { metalSystemDevice } from "../../src/test/metalDevice.h";
	@compile("../../src/test/metalDevice.m");
}

const W: int32 = 128;
const H: int32 = 96;
const COLUMNS: int32 = 16;
const COUNT: int32 = 48;
const BOX: float32 = 6.0;
const STEP: int32 = 8;
const OLD: Color = rgba(0.2, 0.7, 0.4, 1.0);
const NEW: Color = rgba(1.0, 0.0, 0.0, 1.0);

function setupDevice(): void {
	when (voidDummy) {
		doorSetup(null, null, 2, PixelFormat.Depth as int32, 1);
	} else when (windows) {
		doorSetup(warpDevice(), warpContext(), 2, 0, 1);
	} else when (macos) {
		doorSetup(metalSystemDevice(), null, 2, 0, 1);
	}
}

function frame(s: Scene2D, target: RenderTarget): void {
	s.prepare(W as float32, H as float32, 1.0);
	s.drawTarget(target);
	doorSubmitFrame();
}

function boxes(s: Scene2D): NodeRef[] {
	const out: NodeRef[] = [];
	for (let i: int32 = 0; i < COUNT; i++) {
		const r = s.rect(BOX, BOX, OLD).at(((i % COLUMNS) * STEP) as float32, ((i / COLUMNS) * STEP) as float32);
		s.add(r);
		out.push(r);
	}
	return out;
}

function pixelOf(target: RenderTarget, index: int32): uint32 {
	let out: Vec<uint8> = new Array(W * H * 4);
	doorReadTexture(target.image, 0, 0, W, H, out);
	const x: int32 = (index % COLUMNS) * STEP + 3;
	const y: int32 = (index / COLUMNS) * STEP + 3;
	const at: int32 = (y * W + x) * 4;
	return (out[at] as uint32) | ((out[at + 1] as uint32) << 8) | ((out[at + 2] as uint32) << 16) | ((out[at + 3] as uint32) << 24);
}

test "an edited UI instance uploads its own bytes, and touching edits merge into one write" {
	setupDevice();
	setup2d();
	const target = RenderTarget.allocate(W, H, PixelFormat.Rgba8, true);
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const nodes = boxes(s);

	frame(s, target);
	frameEnd();
	const whole: int32 = uploadBytes();
	assert whole >= COUNT * UI_STRIDE;

	frame(s, target);
	frameEnd();
	assert uploadBytes() == 0;
	let untouched: uint32 = 0;
	when (!voidDummy) { untouched = pixelOf(target, 6); }

	nodes[7].setColor(NEW);
	frame(s, target);
	const one: int32 = uploadBytes();
	const oneWrites: int32 = uploadCount();
	frameEnd();
	assert one == UI_STRIDE && oneWrites == 1;
	when (!voidDummy) {
		assert pixelOf(target, 7) == 0xFF0000FF;
		assert pixelOf(target, 6) == untouched;
		assert pixelOf(target, 8) == untouched;
	}

	nodes[20].setColor(NEW);
	nodes[3].setColor(NEW);
	nodes[4].setColor(NEW);
	frame(s, target);
	const merged: int32 = uploadBytes();
	const mergedWrites: int32 = uploadCount();
	frameEnd();
	assert merged == 3 * UI_STRIDE && mergedWrites == 2;
	when (!voidDummy) {
		assert pixelOf(target, 3) == 0xFF0000FF && pixelOf(target, 4) == 0xFF0000FF && pixelOf(target, 20) == 0xFF0000FF;
		assert pixelOf(target, 7) == 0xFF0000FF && pixelOf(target, 5) == untouched;
	}
	s.close();
}
