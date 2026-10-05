// h3d.scene.fwd.Renderer on the core, then h3d.pass.Copy to the swapchain. The scene gets its own
// colour and depth targets: the Android swapchain has no depth buffer (bridgeAndroid.c).

import { Vec4 } from "../math/math3d";
import { Program } from "./gpu3d";
import {
	PixelFormat,
	LoadAction,
	StoreAction,
	PassState,
	endPass,
	commit,
	passState,
	contextGeneration,
} from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
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
} from "../gpu/target";
import {
	DrawContext,
	DrawItem,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	releaseMaterial,
} from "./draw";
import { screenState } from "./screenFx";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawPassLists,
	drawScreen,
	closePrepare,
	openScreen,
	closeRenderer,
} from "./renderer";

export interface ForwardRenderer {
	core: Renderer;
	background: Vec4;
	colorTarget: RenderTarget;
	depthTarget: RenderTarget;
	sampler: Sampler;
	sceneColors: Vec<ColorAttachment>;
	sceneDepth: DepthAttachment;
	copyMaterial: MaterialId;
	closed: boolean;
}

export enum ForwardError {
	UniformPoolFull,
	CameraBlockLength,
	LightBlockLength,
	ProgramNotDrawn,
	MaterialBlock,
	VertexLayout,
	MaterialTexture,
	QuadMesh,
	UniformsReplaced,
	TextureReplaced,
	StaleMesh,
	StaleMaterial,
	ForeignMesh,
	ForeignMaterial,
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
// first prepareFrame makes them.
export function create(
	this typeof ForwardRenderer,
	context: DrawContext,
	background: Vec4,
): Result<ForwardRenderer, ForwardError> {
	context.requireOpen("ForwardRenderer.create");
	const core: Result<Renderer, RendererError> = Renderer.create(context);
	if (!core.ok) {
		return Result.err(fromCore(core.error));
	}
	const copy: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Copy, screenState(), Phase.Opaque));
	if (!copy.ok) { unreachable; }
	return Result.ok({
		core: core.value,
		background: background,
		colorTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		depthTarget: RenderTarget.unallocated(PixelFormat.Depth, false),
		sampler: { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0 },
		sceneColors: new Array(1),
		sceneDepth: NO_DEPTH,
		copyMaterial: copy.value,
		closed: false,
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
		RendererError.QuadMesh => ForwardError.QuadMesh,
		RendererError.UniformsReplaced => ForwardError.UniformsReplaced,
		RendererError.TextureReplaced => ForwardError.TextureReplaced,
		RendererError.StaleMesh => ForwardError.StaleMesh,
		RendererError.StaleMaterial => ForwardError.StaleMaterial,
		RendererError.ForeignMesh => ForwardError.ForeignMesh,
		RendererError.ForeignMaterial => ForwardError.ForeignMaterial,
	};
}

function adoptContext(renderer: ForwardRenderer): void {
	renderer.sampler = Sampler.create(renderer.sampler.filter, renderer.sampler.wrap);
}

function resizeTargets(renderer: ForwardRenderer, width: int32, height: int32): void {
	const color: RenderTarget = renderer.colorTarget;
	if (color.image != 0 && color.generation == contextGeneration() &&
		color.width == width && color.height == height) {
		return;
	}
	renderer.colorTarget.resize(width, height);
	renderer.depthTarget.resize(width, height);
	renderer.sceneColors[0] = renderer.colorTarget.asColor(LoadAction.Clear, renderer.background);
	renderer.sceneDepth =
		renderer.depthTarget.asDepth(LoadAction.Clear, FAR_DEPTH, StoreAction.DontCare);
}

// One frame at the framebuffer's `width` × `height`: `items` index the meshes and materials of
// the context the preset was made on; `camera` and `lights` are the scene programs' uniform
// blocks (shader3dBlocks.glsl vertexParams, lightParams). Answers how many items it was given.
// An item whose material names a program the core does not draw refuses the frame before
// anything changes.
export function prepareFrame(
	renderer: ForwardRenderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
	width: int32,
	height: int32,
): Result<int32, ForwardError> {
	if (renderer.closed) { stopOnClosed("prepareFrame"); }
	renderer.core.openPrepare();
	const context: DrawContext = renderer.core.context;
	if (width <= 0 || height <= 0) {
		return Result.err(ForwardError.TargetSize);
	}
	if (!context.hasMaterial(renderer.copyMaterial)) {
		const issued: boolean = context.issuedMaterial(renderer.copyMaterial);
		return Result.err(issued ? ForwardError.StaleMaterial : ForwardError.ForeignMaterial);
	}
	if (!context.keepsItsTexture(renderer.copyMaterial)) {
		return Result.err(ForwardError.TextureReplaced);
	}
	if (!context.keepsItsUniforms(renderer.copyMaterial)) {
		return Result.err(ForwardError.UniformsReplaced);
	}
	const began: Result<boolean, RendererError> =
		beginFrame(renderer.core, items, camera, lights);
	if (!began.ok) { return Result.err(fromCore(began.error)); }
	if (began.value) {
		adoptContext(renderer);
	}
	resizeTargets(renderer, width, height);
	context.materials[renderer.copyMaterial.index].texture0 = renderer.colorTarget.asTexture();
	context.materials[renderer.copyMaterial.index].sampler0 = renderer.sampler.asHandle();

	beginPass(renderer.sceneColors, renderer.sceneDepth);
	drawPassLists(renderer.core, items, FORWARD_LAYOUT);
	endPass();
	closePrepare(renderer.core);
	return Result.ok((items.length as int32) - renderer.core.culledCount);
}

function stopOnScreenDraw(error: RendererError): void {
	if (error == RendererError.ForeignMesh || error == RendererError.ForeignMaterial) {
		console.log("void3d: drawToScreen with a copy material or screen mesh of another context");
		unreachable;
	}
	console.log(
		"void3d: drawToScreen after the preset's copy material, texture or screen mesh changed",
	);
	unreachable;
}

// Into the screen pass the caller has open: its pipelines are keyed on SWAPCHAIN_LAYOUT.
// PENDING3D: screen-output-swapchain-only
// PENDING3D: copy-opaque
export function drawToScreen(renderer: ForwardRenderer): void {
	if (renderer.closed) { stopOnClosed("drawToScreen"); }
	openScreen(renderer.core);
	const copied: Result<int32, RendererError> =
		drawScreen(renderer.core, renderer.copyMaterial, SWAPCHAIN_LAYOUT);
	if (!copied.ok) { stopOnScreenDraw(copied.error); }
}

export function renderFrame(
	renderer: ForwardRenderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
	width: int32,
	height: int32,
): Result<int32, ForwardError> {
	const drawn: int32 =
		try prepareFrame(renderer, items, camera, lights, width, height);
	beginScreenPass(SCREEN_CLEAR);
	drawToScreen(renderer);
	endPass();
	commit();
	return Result.ok(drawn);
}

export function closeForward(renderer: ForwardRenderer): void {
	if (renderer.closed) { stopOnClosed("closeForward"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeForward with a pass open; endPass ends it");
		unreachable;
	}
	renderer.colorTarget.close();
	renderer.depthTarget.close();
	renderer.sampler = renderer.sampler.released();
	const copy: Result<int32, HandleError> =
		releaseMaterial(renderer.core.context, renderer.copyMaterial);
	if (!copy.ok) {
		console.log(`void3d: closeForward found its copy material ${copy.error.toString()}`);
		unreachable;
	}
	if (!renderer.core.isClosed()) { closeRenderer(renderer.core); }
	renderer.closed = true;
}

export function isClosed(this renderer: ForwardRenderer): boolean {
	return renderer.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a forward preset that was closed`);
	unreachable;
}
