import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { RenderTarget, beginScreenPass } from "../../src/gpu/target";
import {
	PixelFormat, endPass, commit, passState, PassState, imageAlive, destroyView,
} from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d, drawCallCount } from "../../src/void2d/draw";
import { rgba, tile, blurFilter, targetTile } from "../../src/void2d/types";
import { fillRect } from "../../src/void2d/graphics";
import { BoxStyle, uniformRadii, uniformBorders } from "../../src/void2d/boxStyle";
import { BlendMode } from "../../src/gpu/state";
import { DrawContext } from "../../src/void3d/draw";
import { Renderer, create, closePrepare, openScreen } from "../../src/void3d/renderer";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 128;
const HEIGHT: int32 = 96;
const DPI: float32 = 2.0;
const subject: Scene2D = Scene2D.create(rgba(0.75, 0.25, 0.5, 0.0));
const source: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
const display: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
const red: NodeRef = subject.rect(16.0, 12.0, rgba(1.0, 0.0, 0.0, 0.5)).at(4.0, 4.0);
let target: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let sourceTarget: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let shown: NodeRef = display.group();
let core: Renderer = null as unknown as Renderer;
let stage: int32 = 0;
let paintedImage: uint32 = 0;
let redraws: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL scene target: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function sameRgba(): boolean {
	for (let y: int32 = 0; y < HEIGHT; y++) {
		for (let x: int32 = 0; x < WIDTH; x++) {
			if (voidCapturePixel(0, x, y) != voidCapturePixel(1, x, y)) { return false; }
		}
	}
	return true;
}

function init(): void {
	gfxSetup();
	setup2d();
	const made = Renderer.create(DrawContext.withUniformCapacity(1024));
	if (!made.ok) { fail("3D renderer could not be created"); }
	if (made.ok) { core = made.value; }
	target = RenderTarget.allocate(WIDTH, HEIGHT, PixelFormat.Rgba8, true);
	sourceTarget = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
	source.add(source.rect(8.0, 8.0, rgba(1.0, 1.0, 0.0, 1.0)));
	subject.add(red);
	const rounded = subject.rect(16.0, 16.0, rgba(0.0, 1.0, 0.0, 0.5)).at(24.0, 4.0);
	rounded.setBoxStyle(BoxStyle.create(uniformRadii(4.0), uniformBorders(0.0),
		rgba(0.0, 0.0, 0.0, 0.0)));
	subject.add(rounded);
	const graphic = subject.graphics().at(4.0, 26.0);
	fillRect(graphic, 0.0, 0.0, 12.0, 8.0, rgba(0.0, 0.0, 1.0, 0.5));
	subject.add(graphic);
	subject.add(subject.sprite(targetTile(sourceTarget, 8.0, 8.0).premultiplied())
		.at(24.0, 26.0));
	const filtered = subject.rect(10.0, 8.0, rgba(1.0, 0.0, 1.0, 0.5)).at(46.0, 26.0);
	filtered.setFilter(blurFilter(1.0));
	subject.add(filtered);
	const clipped = subject.mask(8.0, 12.0).at(46.0, 4.0);
	clipped.addChild(subject.rect(16.0, 12.0, rgba(0.0, 1.0, 1.0, 1.0)));
	subject.add(clipped);
	shown = display.sprite(targetTile(target, WIDTH as float32, HEIGHT as float32)
		.premultiplied()).setBlend(BlendMode.None);
	display.add(shown);
}

function frame(): void {
	const misuse = env.get("VOID_SCENE_TARGET_MISUSE");
	if (misuse.equals("unprepared")) { subject.drawTarget(target); }
	const dpi: float32 = stage == 8 ? 1.5 : DPI;
	core.openPrepare();
	if (stage == 0) {
		source.prepare(8.0, 8.0, 1.0);
		source.drawTarget(sourceTarget);
	}
	if (stage == 2 || stage == 7 || stage == 8) {
		if (subject.isDirty()) { fail("a clean scene became dirty before target recreation"); }
		const old: uint32 = target.image;
		if (stage == 2) {
			target.close();
			target = RenderTarget.allocate(WIDTH, HEIGHT, PixelFormat.Rgba8, true);
		} else {
			const held: RenderTarget = target;
			target.resize(stage == 8 ? 96 : 192, stage == 8 ? 72 : 144);
			if (held != target || held.image != target.image) {
				fail("resize replaced the target owner instead of updating its alias");
			}
		}
		if (target.image == old || target.image == paintedImage) {
			fail("target identity did not change");
		}
		shown.setTile(targetTile(target, target.width as float32, target.height as float32)
			.premultiplied());
		shown.setSize(target.width as float32, target.height as float32);
	}
	if (stage == 3) { red.setColor(rgba(0.0, 0.0, 1.0, 0.5)); }
	const before: int32 = drawCallCount();
	if (stage == 4) {
		subject.prepare(64.0, 48.0, DPI);
	} else if (subject.isDirty() || target.image != paintedImage || stage == 5) {
		subject.prepare((target.width as float32) / dpi, (target.height as float32) / dpi, dpi);
		if (misuse.equals("size")) { target.resize(144, 108); }
		if (misuse.equals("closed")) { target.close(); }
		if (misuse.equals("empty")) { target = RenderTarget.unallocated(PixelFormat.Rgba8, true); }
		if (misuse.equals("generation")) {
			target.generation = target.generation + 7;
		}
		if (misuse.equals("format")) {
			target = RenderTarget.allocate(WIDTH, HEIGHT, PixelFormat.Depth, false);
		}
		if (misuse.equals("open")) { beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 0.0 }); }
		if (misuse.equals("expired")) { commit(); }
		if (misuse.equals("dpi")) { subject.context.frameDpi = 0.0; }
		if (misuse.equals("destroyed-view")) { destroyView(target.attachment); }
		if (stage == 5) { red.setColor(rgba(1.0, 0.0, 0.0, 0.5)); }
		subject.drawTarget(target);
		if (misuse.equals("consumed")) { subject.drawTarget(target); }
		if (passState() != PassState.None) { fail("drawTarget left a pass open"); }
		if (!imageAlive(target.image)) { fail("drawTarget released the caller's target"); }
		paintedImage = target.image;
		redraws = redraws + 1;
	}
	if (stage == 1 && drawCallCount() != before) { fail("a clean target was drawn again"); }
	if (stage != 4) { display.prepare(WIDTH as float32, HEIGHT as float32, 1.0); }
	closePrepare(core);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 0.0 });
	openScreen(core);
	if (stage == 4) { subject.drawScreen(); } else { display.drawScreen(); }
	endPass();
	commit();
	const slot: int32 = stage == 0 || stage == 3 ? 0 : 1;
	if (voidCaptureGrab(slot) == 0) { fail("readback failed"); }
	if (voidCapturePixel(slot, 0, 0) != 0) { fail("transparent clear did not leave RGBA zero"); }
	const expected: int64 = stage >= 3 && stage <= 5 ? 0x00008080 : 0x80000080;
	if (voidCapturePixel(slot, 12, 12) != expected) {
		fail("DPI, snapshot or premultiplied colour changed");
	}
	const greenX: int32 = stage == 8 ? 48 : 64;
	const greenY: int32 = stage == 8 ? 18 : 24;
	if (voidCapturePixel(slot, greenX, greenY) != 0x00800080) {
		fail("rounded UI fill did not reach the target");
	}
	const spritePixel: int64 = voidCapturePixel(slot, stage == 8 ? 42 : 56, stage == 8 ? 45 : 60);
	if (spritePixel != 0xFFFF00FF) {
		fail(`sprite pixel ${spritePixel} at stage ${stage}, expected 4294902015`);
	}
	const vertexPixel: int64 = voidCapturePixel(slot, stage == 8 ? 12 : 16, stage == 8 ? 45 : 60);
	const blue: int32 = ((vertexPixel >> 8) & 255) as int32;
	const alpha: int32 = (vertexPixel & 255) as int32;
	if ((vertexPixel >> 16) != 0 || blue < 127 || blue > 128 || alpha < 127 || alpha > 128) {
		fail(`vertex premultiplication ${vertexPixel} is not half-blue at half-coverage`);
	}
	if (voidCapturePixel(slot, stage == 8 ? 71 : 94, stage == 8 ? 9 : 12) != 0x00FFFFFF ||
		voidCapturePixel(slot, stage == 8 ? 83 : 110, stage == 8 ? 9 : 12) != 0) {
		fail("target DPI scissor did not clip the mask");
	}
	if (stage == 1 || stage == 2 || stage == 4) {
		if (!sameRgba()) {
			fail("retained/recreated target differs from the direct scene");
		}
	}
	if (stage == 5 && !subject.isDirty()) { fail("drawTarget lost a post-prepare write"); }
	if (stage == 8 && redraws != 7) {
		fail("the caller's dirty/recreate gate drew the wrong frames");
	}
	stage = stage + 1;
	if (stage < 9) { return; }
	console.log("PASS scene target: prepare phase, DPI, every pipeline, transparent RGBA, " +
		"idle, recreate and snapshots");
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
