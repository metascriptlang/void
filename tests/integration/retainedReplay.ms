import { gfxSetup } from "../../src/sokol/gpu";
import { endPass, commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
import { setup2d, flushTargets, end2d } from "../../src/void2d/draw";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { add, paint } from "../../src/void2d/scene";
import { refreshScopes } from "../../src/void2d/render";
import { fillRect } from "../../src/void2d/graphics";
import { rgba, tile, whiteTile } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const red = rgba(1.0, 0.0, 0.0, 1.0);
const blue = rgba(0.0, 0.0, 1.0, 1.0);
const box: NodeRef = s.add(s.rect(20.0, 20.0, red).at(10.0, 10.0));
const sprite: NodeRef = s.add(s.sprite(whiteTile(20.0, 20.0)).at(40.0, 10.0).setColor(red));
const mesh: NodeRef = s.add(s.graphics().fillRect(70.0, 10.0, 20.0, 20.0, red));
let stage: int32 = 0;

function init(): void { gfxSetup(); setup2d(); }
function drawScene(): void {
	s.paint(120.0, 60.0, 1.0);
	s.refreshScopes();
	flushTargets();
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	end2d();
	endPass();
	s.clearChanges();
}
function checkBlue(where: string): void {
	if (voidCaptureGrab(0) == 0) {
		console.log(`FAIL retained replay: capture at ${where}`);
		voidCaptureExit(1);
	}
	for (let stream: int32 = 0; stream < 3; stream++) {
		const pixel: int64 = voidCapturePixel(0, 15 + stream * 30, 15);
		if (pixel != 0x0000FFFF) {
			console.log(`FAIL retained replay: ${where} stream ${stream} pixel ${pixel}, expected blue`);
			voidCaptureExit(1);
		}
	}
}
function frame(): void {
	if (stage == 0) {
		drawScene();
		box.setColor(blue);
		sprite.setColor(blue);
		mesh.clear().fillRect(70.0, 10.0, 20.0, 20.0, blue);
		drawScene();
		checkBlue("second dirty bracket");
		drawScene();
		checkBlue("third clean bracket");
		commit();
		stage = 1;
		return;
	}
	drawScene();
	commit();
	checkBlue("next clean frame");
	console.log("PASS retained replay: vertex, sprite and UI retain the last same-frame write");
	voidCaptureExit(0);
}
if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(120, 60, 1, 0, init, frame);
