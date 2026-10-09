// expect closed.prepareFrame: void3d: prepareFrame on a forward preset that was closed
// expect closed.drawToScreen: void3d: drawToScreen on a forward preset that was closed
// expect bloom.ldr: void3d: setBloom on a forward preset made by create; bloom needs createHdr
// expect bloom.settings: void3d: setBloom with intensity -1
import { argv } from "std/process";
import { Vec4 } from "../../../src/math/math3d";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../src/void3d/gpu3d";
import { DrawContext, DrawItem } from "../../../src/void3d/draw";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	FORWARD_HDR_UNIFORM_LENGTH,
	setBloom,
	prepareFrame,
	drawToScreen,
	closeForward,
} from "../../../src/void3d/forwardRenderer";

import { BloomSettings } from "../../../src/void3d/bloom";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function openForward(hdr: boolean): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_HDR_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = hdr ?
		ForwardRenderer.createHdrWhere(context, BLACK, true) :
		ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	return made.value;
}

function closedForward(): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	let forward: ForwardRenderer = made.value;
	closeForward(forward);
	return forward;
}

function run(name: string): void {
	let items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	if (name == "closed.prepareFrame") {
		const _r: Result<int32, ForwardError> =
			prepareFrame(closedForward(), items, camera, lights, 32, 24);
	} else if (name == "bloom.ldr") {
		setBloom(openForward(false), BloomSettings.natural());
	} else if (name == "bloom.settings") {
		setBloom(openForward(true), { ...BloomSettings.natural(), intensity: -1.0 });
	} else if (name == "closed.drawToScreen") {
		drawToScreen(closedForward());
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
