// expect closed.markChanged: void3d: markChanged on a renderer that was closed
// expect closed.beginFrame: void3d: beginFrame on a renderer that was closed
// expect closed.drawPassLists: void3d: drawPassLists on a renderer that was closed
// expect closed.drawPhase: void3d: drawPhase on a renderer that was closed
// expect closed.phaseCount: void3d: phaseCount on a renderer that was closed
// expect closed.drawScreen: void3d: drawScreen on a renderer that was closed
// expect closed.closeRenderer: void3d: closeRenderer on a renderer that was closed
// expect coreClosed.prepareFrame: void3d: prepareFrame on a renderer that was closed
// expect coreClosed.drawToScreen: void3d: drawToScreen on a renderer that was closed
import { argv } from "std/process";
import { Vec4 } from "../../../src/math/math3d";
import { SWAPCHAIN_LAYOUT } from "../../../src/gpu/target";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../src/void3d/gpu3d";
import { DrawContext, DrawItem, NO_MATERIAL } from "../../../src/void3d/draw";
import { Phase } from "../../../src/void3d/material";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	markChanged,
	beginFrame,
	drawPassLists,
	drawPhase,
	drawScreen,
	closeRenderer,
} from "../../../src/void3d/renderer";
import {
	ForwardRenderer,
	ForwardError,
	FORWARD_UNIFORM_LENGTH,
	prepareFrame,
	drawToScreen,
} from "../../../src/void3d/forwardRenderer";

const BLACK: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

function closedCore(): Renderer {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (!made.ok) { unreachable; }
	let core: Renderer = made.value;
	closeRenderer(core);
	return core;
}

function forwardWithClosedCore(): ForwardRenderer {
	let context: DrawContext = DrawContext.withUniformCapacity(FORWARD_UNIFORM_LENGTH);
	const made: Result<ForwardRenderer, ForwardError> = ForwardRenderer.create(context, BLACK);
	if (!made.ok) { unreachable; }
	let forward: ForwardRenderer = made.value;
	let core: Renderer = forward.core;
	closeRenderer(core);
	return forward;
}

function run(name: string): void {
	let items: Vec<DrawItem> = [];
	let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	if (name == "closed.markChanged") {
		markChanged(closedCore());
	} else if (name == "closed.beginFrame") {
		const _r: Result<boolean, RendererError> = beginFrame(closedCore(), items, camera, lights);
	} else if (name == "closed.drawPassLists") {
		drawPassLists(closedCore(), items, SWAPCHAIN_LAYOUT);
	} else if (name == "closed.drawPhase") {
		drawPhase(closedCore(), Phase.Alpha, items, SWAPCHAIN_LAYOUT);
	} else if (name == "closed.phaseCount") {
		const _count: int32 = closedCore().phaseCount(Phase.Alpha);
	} else if (name == "closed.drawScreen") {
		const _r: Result<int32, RendererError> =
			drawScreen(closedCore(), NO_MATERIAL, SWAPCHAIN_LAYOUT);
	} else if (name == "closed.closeRenderer") {
		closeRenderer(closedCore());
	} else if (name == "coreClosed.prepareFrame") {
		const _r: Result<int32, ForwardError> =
			prepareFrame(forwardWithClosedCore(), items, camera, lights, 32, 24);
	} else if (name == "coreClosed.drawToScreen") {
		drawToScreen(forwardWithClosedCore());
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
