import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPass } from "../../src/gpu/target";
import { endPass, commit } from "../../src/gpu/door";
import {
	setup2d, openBracket, startContext, finishRecording, fillQuad, flushTargets, end2d, begin2d,
} from "../../src/void2d/draw";
import { DrawContext2D, useContext, currentContext } from "../../src/void2d/displayList";
import { rgba, vec2 } from "../../src/void2d/types";
import { BlendMode } from "../../src/gpu/state";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const a: DrawContext2D = DrawContext2D.create();
const b: DrawContext2D = DrawContext2D.create();
let stage: int32 = 0;
function init(): void { gfxSetup(); setup2d(); }
function box(x: float32, y: float32, color: int32): void {
	const tint = color == 0 ? rgba(1.0, 0.0, 0.0, 1.0) : rgba(0.0, 1.0, 0.0, 1.0);
	fillQuad(vec2(x, y), vec2(x + 20.0, y), vec2(x + 20.0, y + 20.0),
		vec2(x, y + 20.0), tint, BlendMode.Alpha);
}
function fail(message: string): void {
	console.log(`FAIL draw contexts: ${message}`);
	voidCaptureExit(1);
}
function frame(): void {
	useContext(a);
	openBracket(120.0, 60.0, 1.0);
	startContext();
	box(10.0, 10.0, 0);
	useContext(b);
	openBracket(60.0, 30.0, 2.0);
	startContext();
	box(20.0, 5.0, 1);
	finishRecording();
	useContext(a);
	box(80.0, 10.0, 0);
	finishRecording();
	flushTargets();
	useContext(b);
	flushTargets();
	begin2d(120.0, 60.0, 1.0);
	fillQuad(vec2(0.0, 0.0), vec2(8.0, 0.0), vec2(8.0, 8.0), vec2(0.0, 8.0),
		rgba(0.0, 0.0, 1.0, 1.0), BlendMode.Alpha);
	finishRecording();
	flushTargets();
	const immediate: DrawContext2D = currentContext();
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	useContext(a); end2d();
	useContext(b); end2d();
	useContext(immediate); end2d();
	endPass();
	commit();
	if (voidCaptureGrab(0) == 0) { fail("capture failed"); }
	if (voidCapturePixel(0, 15, 15) != 0xFF0000FF ||
		voidCapturePixel(0, 85, 15) != 0xFF0000FF) { fail("A lost its interleaved red records"); }
	if (voidCapturePixel(0, 45, 15) != 0x00FF00FF) { fail("B lost its green records or DPI"); }
	if (voidCapturePixel(0, 5, 5) != 0x0000FFFF) { fail("default append context lost blue"); }
	if (env.get("VOID_DRAW_CONTEXT_EXPIRED").equals("1")) {
		beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
		useContext(a); end2d();
		fail("expired prepared sources were accepted");
	}
	stage = stage + 1;
	if (stage < 2) { return; }
	console.log("PASS draw contexts: interleaved records, native sources, DPI and default append");
	voidCaptureExit(0);
}
if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(120, 60, 1, 0, init, frame);
