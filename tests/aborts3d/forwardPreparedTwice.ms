// expect: void3d: prepareFrame again before drawToScreen drew the frame it prepared
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/forwardRenderer";

let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
let items: Vec<DrawItem> = [];
let blocks: Vec<float32> = [];
const created: Result<ForwardRenderer, ForwardError> =
	ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
if (created.ok) {
	let forward: ForwardRenderer = created.value;
	forward.core.prepared = true;
	const _again: Result<int32, ForwardError> =
		prepareFrame(forward, context, items, blocks, blocks, 64, 64);
}
console.log("a second prepareFrame returned");
