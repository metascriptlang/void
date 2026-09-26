// h3d.scene.fwd.Renderer on the core, then h3d.pass.Copy to the swapchain. The scene gets its own
// colour and depth targets: the Android swapchain has no depth buffer (bridgeAndroid.c).

import { Vec4 } from "../math/math3d";
import { Program, PixelFormat, LoadAction, Filter, Wrap, endPass } from "./gpu3d";
import { Material, Phase } from "./material";
import {
	RenderTarget,
	ColorAttachment,
	DepthAttachment,
	TargetLayout,
	Sampler,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	beginPass,
	beginScreenPass,
} from "./target";
import { DrawContext, DrawItem, addMaterial } from "./draw";
import { screenState } from "./screenFx";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawPassLists,
	drawScreen,
	endFrame,
} from "./renderer";

export struct ForwardRenderer {
	core: Renderer;
	background: Vec4;
	colorTarget: RenderTarget;
	depthTarget: RenderTarget;
	sampler: Sampler;
	sceneColors: Vec<ColorAttachment>;
	sceneDepth: DepthAttachment;
	copyMaterial: int32;
}

export enum ForwardError {
	UniformPoolFull,
	CameraBlockLength,
	LightBlockLength,
	ProgramNotDrawn,
	MaterialBlock,
	VertexLayout,
	MaterialTexture,
	TargetSize,
}

// Floats of the uniform pool the preset needs: the core's blocks, and nothing of its own.
export const FORWARD_UNIFORM_LENGTH: int32 = RENDERER_UNIFORM_LENGTH;

// The scene pass's attachments: the target half of its pipeline keys.
export const FORWARD_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.Depth,
	sampleCount: 1,
};

const FAR_DEPTH: float32 = 1.0;
const SCREEN_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

// Creates the core and adds the copy material to `context`. No GPU object is made here: the
// first renderFrame makes them.
export function create(
	this typeof ForwardRenderer,
	ref context: DrawContext,
	background: Vec4,
): Result<ForwardRenderer, ForwardError> {
	const core: Result<Renderer, RendererError> = Renderer.create(context);
	if (!core.ok) {
		return Result.err(fromCore(core.error));
	}
	const copy: Material = Material.plain(Program.Copy, screenState(), Phase.Opaque);
	return Result.ok({
		core: core.value,
		background: background,
		colorTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		depthTarget: RenderTarget.unallocated(PixelFormat.Depth, false),
		sampler: { filter: Filter.Nearest, wrap: Wrap.Clamp, handle: 0 },
		sceneColors: new Array(1),
		sceneDepth: NO_DEPTH,
		copyMaterial: addMaterial(context, copy),
	});
}

function fromCore(error: RendererError): ForwardError {
	return match (error) {
		RendererError.UniformPoolFull => ForwardError.UniformPoolFull,
		RendererError.CameraBlockLength => ForwardError.CameraBlockLength,
		RendererError.LightBlockLength => ForwardError.LightBlockLength,
		RendererError.ProgramNotDrawn => ForwardError.ProgramNotDrawn,
		RendererError.MaterialBlock => ForwardError.MaterialBlock,
		RendererError.VertexLayout => ForwardError.VertexLayout,
		RendererError.MaterialTexture => ForwardError.MaterialTexture,
	};
}

// A new GPU context: the handles are dropped, not destroyed; the next resize makes the targets.
function adoptContext(ref renderer: ForwardRenderer): void {
	renderer.colorTarget = renderer.colorTarget.forgotten();
	renderer.depthTarget = renderer.depthTarget.forgotten();
	renderer.sampler = Sampler.create(renderer.sampler.filter, renderer.sampler.wrap);
}

function resizeTargets(ref renderer: ForwardRenderer, width: int32, height: int32): void {
	const color: RenderTarget = renderer.colorTarget;
	if (color.image != 0 && color.width == width && color.height == height) {
		return;
	}
	renderer.colorTarget = renderer.colorTarget.resized(width, height);
	renderer.depthTarget = renderer.depthTarget.resized(width, height);
	renderer.sceneColors[0] = renderer.colorTarget.asColor(LoadAction.Clear, renderer.background);
	renderer.sceneDepth = renderer.depthTarget.asDepth(LoadAction.Clear, FAR_DEPTH);
}

// One frame at the framebuffer's `width` × `height`: `items` index `context`'s meshes and
// materials; `camera` and `lights` are the scene programs' uniform blocks (shader3dBlocks.glsl
// vertexParams, lightParams). Answers how many items it was given. An item whose material names
// a program the core does not draw refuses the frame before anything changes.
export function renderFrame(
	ref renderer: ForwardRenderer,
	ref context: DrawContext,
	items: Span<DrawItem>,
	camera: Span<float32>,
	lights: Span<float32>,
	width: int32,
	height: int32,
): Result<int32, ForwardError> {
	if (width <= 0 || height <= 0) {
		return Result.err(ForwardError.TargetSize);
	}
	const began: Result<boolean, RendererError> =
		beginFrame(renderer.core, context, items, camera, lights);
	if (!began.ok) { return Result.err(fromCore(began.error)); }
	if (began.value) {
		adoptContext(renderer);
	}
	resizeTargets(renderer, width, height);
	context.materials[renderer.copyMaterial].texture0 = renderer.colorTarget.texture;
	context.materials[renderer.copyMaterial].sampler0 = renderer.sampler.handle;

	beginPass(renderer.sceneColors, renderer.sceneDepth);
	drawPassLists(renderer.core, context, items, FORWARD_LAYOUT);
	endPass();
	beginScreenPass(SCREEN_CLEAR);
	drawScreen(renderer.core, context, renderer.copyMaterial, SWAPCHAIN_LAYOUT);
	endPass();
	endFrame(renderer.core);
	return Result.ok(items.length as int32);
}
