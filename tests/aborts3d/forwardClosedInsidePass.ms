// expect: void3d: closeForward with a pass open; endPass ends it
import { gfxSetup } from "../../src/sokol/gpu";
import { Vec4 } from "../../src/math/math3d";
import { beginScreenPass } from "../../src/gpu/target";
import { DrawContext } from "../../src/void3d/draw";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	closeForward,
} from "../../src/void3d/forwardRenderer";
@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
let forward: ForwardRenderer = forwardOn(context);

function forwardOn(on: DrawContext): ForwardRenderer {
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(on, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function init(): void { gfxSetup(); }
function frame(): void {
	beginScreenPass(BLACK);
	closeForward(forward);
	console.log("a forward preset closed inside the screen pass");
	process.exit(0);
}
voidRun(64, 64, init, frame);
