import { env } from "std/process";
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { endPass, commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d, drawCallCount } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import { BoxStyle, uniformRadii, uniformBorders } from "../../src/void2d/boxStyle";
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
const GREEN_PIXEL: int64 = 0x009900FF;
const BLUE_PIXEL: int64 = 0x0000FFFF;
const CLEAR_PIXEL: int64 = 0x191933FF;
const CLEAR = rgba(0.1, 0.1, 0.2, 1.0);
const GREEN = rgba(0.0, 0.6, 0.0, 1.0);
const BLUE = rgba(0.0, 0.0, 1.0, 1.0);
const subject: Scene2D = Scene2D.create(CLEAR);
const counts: Scene2D = Scene2D.create(CLEAR);
let view: NodeRef = subject.group().at(4.0, 4.0);
let plain: NodeRef = counts.group().at(4.0, 4.0);
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL view paint: stage ${stage}: ${message}`);
	voidCaptureExit(1);
}

function exerciseMisuse(misuse: string): void {
	const s: Scene2D = Scene2D.create(CLEAR);
	const label: NodeRef = s.label("x", 9.0, rgba(1.0, 1.0, 1.0, 1.0));
	label.setBackground(GREEN);
	console.log("a label took a background");
	voidCaptureExit(0);
}

function init(): void {
	gfxSetup();
	setup2d();
	const misuse: string = env.get("VOID_VIEW_PAINT_MISUSE");
	if (!misuse.equals("")) { exerciseMisuse(misuse); }
	if (fbWidth() != WIDTH || fbHeight() != HEIGHT) {
		console.log(`view paint needs a ${WIDTH}x${HEIGHT} framebuffer, the window gave ` +
			`${fbWidth()}x${fbHeight()}; the OS enforces a minimum client width`);
		voidCaptureExit(1);
	}
	subject.add(view);
	view.addChild(subject.rect(8.0, 8.0, BLUE).at(2.0, 2.0));
	counts.add(plain);
	plain.addChild(counts.rect(8.0, 8.0, BLUE).at(2.0, 2.0));
}

function drawToScreen(s: Scene2D): void {
	s.prepare(fbWidth() as float32, fbHeight() as float32, 1.0);
	beginScreenPass({ x: CLEAR.r * CLEAR.a, y: CLEAR.g * CLEAR.a, z: CLEAR.b * CLEAR.a, w: CLEAR.a });
	s.drawScreen();
	endPass();
	commit();
}

function frame(): void {
	if (stage == 0) {
		view.setBackground(GREEN).setSize(16.0, 16.0);
		if (view.kind().toString() != "Rect") { fail("setBackground did not promote the group"); }
		drawToScreen(subject);
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		if (voidCapturePixel(0, 5, 5) != GREEN_PIXEL) { fail("promoted background fill missing"); }
		if (voidCapturePixel(0, 7, 7) != BLUE_PIXEL) { fail("child not drawn over the promoted fill"); }
	} else if (stage == 1) {
		view.clearBackground();
		if (view.kind().toString() != "Group") { fail("clearBackground did not demote the rect"); }
		drawToScreen(subject);
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		if (voidCapturePixel(0, 5, 5) != CLEAR_PIXEL) { fail("demoted background still paints"); }
		if (voidCapturePixel(0, 7, 7) != BLUE_PIXEL) { fail("child lost after demotion"); }
	} else if (stage == 2) {
		const before: int32 = drawCallCount();
		drawToScreen(counts);
		const plainCalls: int32 = drawCallCount() - before;
		plain.setBackground(rgba(0.0, 0.0, 0.0, 0.0)).setSize(16.0, 16.0);
		const second: int32 = drawCallCount();
		drawToScreen(counts);
		const promotedCalls: int32 = drawCallCount() - second;
		if (plainCalls != promotedCalls) {
			fail(`a transparent background emitted draws: ${promotedCalls} vs ${plainCalls}`);
		}
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		if (voidCapturePixel(0, 5, 5) != CLEAR_PIXEL) { fail("transparent background painted"); }
	} else {
		view.setBoxStyle(BoxStyle.create(uniformRadii(0.0), uniformBorders(2.0), BLUE));
		if (view.kind().toString() != "Rect") { fail("setBoxStyle did not promote the group"); }
		if (view.paint().color.a != 0.0) { fail("a border-only promotion kept a fill colour"); }
		drawToScreen(subject);
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		if (voidCapturePixel(0, 5, 5) != BLUE_PIXEL) { fail("border ring missing"); }
		if (voidCapturePixel(0, 16, 16) != CLEAR_PIXEL) {
			fail("border-only interior is not transparent");
		}
	}
	stage = stage + 1;
	if (stage < 4) { return; }
	console.log("PASS view paint: in-place promotion and demotion, child order kept, " +
		"transparent and border-only backgrounds emit no fill");
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
