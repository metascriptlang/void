import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit, voidCaptureEnvInt,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 120;
const HEIGHT: int32 = 100;
const content: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const layer: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const a: NodeRef = content.rect(60.0, 60.0, rgba(1.0, 0.0, 0.0, 1.0)).at(10.0, 10.0);
const b: NodeRef = content.rect(60.0, 60.0, rgba(0.0, 1.0, 0.0, 1.0)).at(30.0, 30.0);
const c: NodeRef = content.rect(40.0, 40.0, rgba(0.0, 0.0, 1.0, 1.0)).at(70.0, 55.0);
const quad: NodeRef = layer.rect(80.0, 80.0, rgba(1.0, 1.0, 0.0, 1.0)).at(20.0, 15.0);
let stage: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL layer slot: ${message}`);
	voidCaptureExit(1);
}

function init(): void {
	gfxSetup();
	setup2d();
	content.add(a);
	content.add(b);
	content.add(c);
	layer.add(quad);
	b.setLayerSlot(true);
	const misuse = env.get("VOID_LAYER_SLOT_MISUSE");
	if (misuse.equals("backwards")) { a.setLayerSlot(true); }
	if (misuse.equals("hidden")) { b.setVisible(false); }
}

function frame(): void {
	const misuse = env.get("VOID_LAYER_SLOT_MISUSE");
	const w: float32 = WIDTH as float32;
	const h: float32 = HEIGHT as float32;
	content.prepare(w, h, 1.0);
	layer.prepare(w, h, 1.0);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (misuse.equals("not-slot")) { content.drawScreenUntil(c); }
	if (misuse.equals("foreign")) { content.drawScreenUntil(quad); }
	if (env.get("VOID_LAYER_SLOT_CONTROL").equals("1")) {
		content.drawScreen();
		layer.drawScreen();
	} else {
		content.drawScreenUntil(b);
		if (misuse.equals("backwards")) { content.drawScreenUntil(a); }
		layer.drawScreen();
		content.drawScreen();
	}
	endPass();
	commit();
	const hold: int32 = voidCaptureEnvInt("VOID_LAYER_SLOT_HOLD", 0);
	if (hold > 0) {
		stage = stage + 1;
		if (stage >= hold) { voidCaptureExit(0); }
		return;
	}
	if (voidCaptureGrab(0) == 0) { fail("capture failed"); }
	if (voidCapturePixel(0, 15, 12) != 0xFF0000FF) { fail("pixel 15,12: A lost outside the layer"); }
	if (voidCapturePixel(0, 25, 20) != 0xFFFF00FF) { fail("pixel 25,20: A is not under the layer"); }
	if (voidCapturePixel(0, 40, 40) != 0x00FF00FF) { fail("pixel 40,40: B is not over the layer"); }
	if (voidCapturePixel(0, 85, 80) != 0x0000FFFF) { fail("pixel 85,80: C is not over the layer"); }
	if (voidCapturePixel(0, 95, 20) != 0xFFFF00FF) { fail("pixel 95,20: the layer is missing"); }
	console.log("PASS layer slot: A under the layer, B and C over it");
	voidCaptureExit(0);
}

if (voidCaptureEnvInt("VOID_LAYER_SLOT_HOLD", 0) == 0 &&
	env.get("VOID_LAYER_SLOT_MISUSE").equals("") && voidCaptureBackend() == 0) {
	console.log("SKIP layer slot: this build has no readback path");
	voidCaptureExit(3);
}
voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
