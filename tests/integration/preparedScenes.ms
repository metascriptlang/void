import { env } from "std/process";
import { gfxSetup, commit } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass } from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba, blurFilter } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const a: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const b: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const red: NodeRef = a.rect(30.0, 30.0, rgba(1.0, 0.0, 0.0, 1.0)).at(10.0, 10.0);
const green: NodeRef = b.rect(20.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)).at(30.0, 5.0);
let stage: int32 = 0;
function fail(message: string): void {
	console.log(`FAIL prepared scenes: ${message}`);
	voidCaptureExit(1);
}
function init(): void {
	gfxSetup();
	setup2d();
	a.add(red);
	b.add(green);
	red.setFilter(blurFilter(1.0));
}
function frame(): void {
	const misuse = env.get("VOID_PREPARED_MISUSE");
	if (misuse.equals("unprepared")) { a.drawScreen(); }
	a.prepare(120.0, 60.0, 1.0);
	b.prepare(60.0, 30.0, 2.0);
	if (misuse.equals("twice")) { a.prepare(120.0, 60.0, 1.0); }
	if (misuse.equals("no-pass")) { a.drawScreen(); }
	if (stage == 0) {
		red.setColor(rgba(0.0, 0.0, 1.0, 1.0));
		if (!a.isDirty()) { fail("a write after prepare was lost"); }
	}
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	a.drawScreen();
	if (misuse.equals("nested")) { a.prepare(120.0, 60.0, 1.0); }
	b.drawScreen();
	if (misuse.equals("consumed")) { a.drawScreen(); }
	endPass();
	commit();
	if (misuse.equals("expired")) {
		a.prepare(120.0, 60.0, 1.0);
		commit();
		beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
		a.drawScreen();
	}
	if (voidCaptureGrab(0) == 0) { fail("capture failed"); }
	const expected: uint32 = stage == 0 ? 0xFF0000FF : 0x0000FFFF;
	if (voidCapturePixel(0, 25, 25) != expected) {
		fail("prepared filtered A changed early or did not retain its next-frame write");
	}
	if (voidCapturePixel(0, 70, 20) != 0x00FF00FF) { fail("B lost its own prepared sources or DPI"); }
	if (stage == 0 && !a.isDirty()) { fail("drawScreen cleared a post-prepare write"); }
	stage = stage + 1;
	if (stage < 2) { return; }
	console.log("PASS prepared scenes: filtered snapshots, two DPIs, post-prepare writes and one screen owner");
	voidCaptureExit(0);
}
if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(120, 60, 1, 0, init, frame);
