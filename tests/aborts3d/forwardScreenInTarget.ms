// expect: void3d: drawToScreen outside a screen pass; open one with beginScreenPass
import { gfxSetup } from "../../src/sokol/gpu";
import { beginPass } from "../../src/gpu/target";
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../src/void3d/gpu3d";
import {
	ForwardRenderer, ForwardError, FORWARD_UNIFORM_LENGTH, prepareFrame, drawToScreen,
} from "../../src/void3d/forwardRenderer";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function init(): void { gfxSetup(); }
function frame(): void {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	let made: Result<ForwardRenderer, ForwardError> =
		ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	if (!made.ok) { unreachable; }
	let forward: ForwardRenderer = made.value;
	let items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	for (let i = 0; i < VERTEX_UNIFORM_LENGTH; i++) { camera[i] = 0.0; }
	for (let i = 0; i < LIGHT_UNIFORM_LENGTH; i++) { lights[i] = 0.0; }
	let prepared: Result<int32, ForwardError> =
		prepareFrame(forward, items, camera, lights, 64, 64);
	if (!prepared.ok) { unreachable; }
	beginPass(forward.sceneColors, forward.sceneDepth);
	drawToScreen(forward);
	console.log("drawToScreen into a target returned");
	process.exit(0);
}
voidRun(64, 64, init, frame);
