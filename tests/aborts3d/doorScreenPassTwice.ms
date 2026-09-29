// expect: gpu door: beginScreenPass with a pass already open; endPass ends it
import { beginScreenPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
import { gfxSetup } from "../../src/sokol/gpu";
@include("../../src/sokol/bridge.h");

extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function init(): void {
	gfxSetup();
}

function frame(): void {
	beginScreenPass(CLEAR);
	beginScreenPass(CLEAR);
}

voidRun(1280, 720, init, frame);
