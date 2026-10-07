// expect: void3d: endPrepared with no prepared frame; call prepareFrame first
import { DrawContext } from "../../src/void3d/draw";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	endPrepared,
} from "../../src/void3d/forwardRenderer";

let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
const created: Result<ForwardRenderer, ForwardError> =
	ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
if (created.ok) {
	let forward: ForwardRenderer = created.value;
	endPrepared(forward);
}
console.log("endPrepared with no prepared frame returned");
