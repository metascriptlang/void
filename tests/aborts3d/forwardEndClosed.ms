// expect: void3d: endPrepared on a forward preset that was closed
import { Vec4 } from "../../src/math/math3d";
import { DrawContext } from "../../src/void3d/draw";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	closeForward,
	endPrepared,
} from "../../src/void3d/forwardRenderer";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
if (!made.ok) { unreachable; }
let forward: ForwardRenderer = made.value;
closeForward(forward);
endPrepared(forward);
console.log("endPrepared on a closed forward preset returned");
