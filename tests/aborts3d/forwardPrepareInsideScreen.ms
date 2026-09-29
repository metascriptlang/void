// expect: void3d: prepareFrame with a pass already open; it would nest inside it
import { DrawContext, DrawItem } from "../../src/void3d/draw";
import { beginScreenPass } from "../../src/gpu/target";
import { Vec4 } from "../../src/math/math3d";
import { gfxSetup } from "../../src/sokol/gpu";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
} from "../../src/void3d/forwardRenderer";
@include("../../src/sokol/bridge.h");

extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
let items: Vec<DrawItem> = [];
let blocks: Vec<float32> = [];
const created: Result<ForwardRenderer, ForwardError> =
	ForwardRenderer.create(context, CLEAR);

function init(): void {
	gfxSetup();
}

function frame(): void {
	beginScreenPass(CLEAR);
	if (created.ok) {
		let forward: ForwardRenderer = created.value;
		const _prepared: Result<int32, ForwardError> =
			prepareFrame(forward, context, items, blocks, blocks, 640, 360);
	}
}

voidRun(1280, 720, init, frame);
