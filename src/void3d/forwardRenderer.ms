// h3d.scene.fwd.Renderer on the core, then h3d.pass.Copy to the swapchain. The scene gets its own
// colour and depth targets: the Android swapchain has no depth buffer (bridgeAndroid.c). An HDR
// preset (createHdr) draws the scene into an Rgba16f target and tone maps it into the colour
// target, as h3d.scene.pbr.Renderer draws into `hdr` and runs its ToneMapping ScreenFx into `ldr`.

import { Vec4 } from "../math/math3d";
import {
	Program,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
	FRAME_UNIFORM_LENGTH,
} from "./gpu3d";
import {
	PixelFormat,
	formatRenderable,
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
import "./uniformPool";
import { screenState } from "./screenFx";
import { ToneMapPass, TONE_MAP_UNIFORM_LENGTH, linearBackground } from "./toneMap";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawPassLists,
	drawScreen,
	closePrepare,
	openScreen,
	releasePrepared,
	closeRenderer,
	drawShadowPass,
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
	// An HDR preset's target and tone map; null for an LDR one.
	toneMap: ToneMapPass | null;
	hdrColors: Vec<ColorAttachment>;
	toneMapColors: Vec<ColorAttachment>;
	// How many times the colour and depth targets were made: the first prepare, a new size or a
	// new GPU context each add one. A caller holding the target's view (a void2d tile of
	// `colorTarget`) renews it when this differs from the value it saw, in place of a poll of
	// the image id (Heaps' `Texture.onContextLost`, which a resize does not fire).
	targetEpoch: int32;
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
	ProgramNotCast,
	CasterBlock,
	TargetSize,
	// The device cannot render into an Rgba16f target (GLES3 and WebGL2 without a
	// color-buffer-float extension); there is no LDR fallback.
	HdrUnsupported,
}

// Floats of the uniform pool the preset needs: the core's blocks, and nothing of its own.
export const FORWARD_UNIFORM_LENGTH: int32 = RENDERER_UNIFORM_LENGTH;

// An HDR preset's floats: the core's blocks and the tone map's.
export const FORWARD_HDR_UNIFORM_LENGTH: int32 = RENDERER_UNIFORM_LENGTH + TONE_MAP_UNIFORM_LENGTH;

// The scene pass's attachments: the target half of its pipeline keys.
export const FORWARD_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.Depth,
	sampleCount: 1,
};

// An HDR preset's scene pass.
export const FORWARD_HDR_LAYOUT: TargetLayout = { ...FORWARD_LAYOUT, color0: PixelFormat.Rgba16f };

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
	return make(context, background, false);
}

// The same, drawing the scene into an Rgba16f target the preset tone maps
// (h3d.shader.pbr.ToneMapping mode 0, at the core's exposure) into `colorTarget`; scene programs
// write linear colour there, unclamped, and blend in linear light. Asks the device whether it
// renders Rgba16f, so the GPU must be set up; `context` needs FORWARD_HDR_UNIFORM_LENGTH floats.
export function createHdr(
	this typeof ForwardRenderer,
	context: DrawContext,
	background: Vec4,
): Result<ForwardRenderer, ForwardError> {
	context.requireOpen("ForwardRenderer.createHdr");
	return ForwardRenderer.createHdrWhere(
		context, background, formatRenderable(PixelFormat.Rgba16f),
	);
}

// createHdr with the device's answer given: a test gives its own.
export function createHdrWhere(
	this typeof ForwardRenderer,
	context: DrawContext,
	background: Vec4,
	rgba16fRenderable: boolean,
): Result<ForwardRenderer, ForwardError> {
	context.requireOpen("ForwardRenderer.createHdrWhere");
	if (!rgba16fRenderable) {
		return Result.err(ForwardError.HdrUnsupported);
	}
	return make(context, background, true);
}

function make(
	context: DrawContext,
	background: Vec4,
	hdr: boolean,
): Result<ForwardRenderer, ForwardError> {
	const blocks: Vec<int32> = [
		VERTEX_UNIFORM_LENGTH,
		LIGHT_UNIFORM_LENGTH,
		FRAME_UNIFORM_LENGTH,
		TONE_MAP_UNIFORM_LENGTH,
	];
	if (hdr && !context.uniforms.fits(blocks).ok) {
		return Result.err(ForwardError.UniformPoolFull);
	}
	const core: Result<Renderer, RendererError> = Renderer.create(context);
	if (!core.ok) {
		return Result.err(fromCore(core.error));
	}
	const copy: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Copy, screenState(), Phase.Opaque));
	if (!copy.ok) { unreachable; }
	const toneMap: ToneMapPass | null = hdr ? ToneMapPass.reserve(context) : null;
	let made: ForwardRenderer = {
		core: core.value,
		background: background,
		colorTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		depthTarget: RenderTarget.unallocated(PixelFormat.Depth, false),
		sampler: { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0 },
		sceneColors: new Array(1),
		sceneDepth: NO_DEPTH,
		copyMaterial: copy.value,
		toneMap: toneMap,
		hdrColors: new Array(1),
		toneMapColors: new Array(1),
		targetEpoch: 0,
		closed: false,
	};
	made.core.linearOutput = hdr;
	return Result.ok(made);
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
		RendererError.ProgramNotCast => ForwardError.ProgramNotCast,
		RendererError.CasterBlock => ForwardError.CasterBlock,
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
	renderer.targetEpoch = renderer.targetEpoch + 1;
	renderer.sceneColors[0] = renderer.colorTarget.asColor(LoadAction.Clear, renderer.background);
	renderer.sceneDepth =
		renderer.depthTarget.asDepth(LoadAction.Clear, FAR_DEPTH, StoreAction.DontCare);
	const toneMap: ToneMapPass | null = renderer.toneMap;
	if (toneMap === null) { return; }
	toneMap.target.resize(width, height);
	renderer.hdrColors[0] =
		toneMap.target.asColor(LoadAction.Clear, linearBackground(renderer.background));
	renderer.toneMapColors[0] = renderer.colorTarget.asColor(LoadAction.DontCare, SCREEN_CLEAR);
}

function screenMaterialError(renderer: ForwardRenderer, material: MaterialId): ForwardError | null {
	const context: DrawContext = renderer.core.context;
	if (!context.hasMaterial(material)) {
		const issued: boolean = context.issuedMaterial(material);
		return issued ? ForwardError.StaleMaterial : ForwardError.ForeignMaterial;
	}
	if (!context.keepsItsTexture(material)) {
		return ForwardError.TextureReplaced;
	}
	if (!context.keepsItsUniforms(material)) {
		return ForwardError.UniformsReplaced;
	}
	return null;
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
	const copyError: ForwardError | null = screenMaterialError(renderer, renderer.copyMaterial);
	if (copyError !== null) { return Result.err(copyError); }
	const toneMap: ToneMapPass | null = renderer.toneMap;
	if (toneMap !== null) {
		const toneMapError: ForwardError | null = screenMaterialError(renderer, toneMap.material);
		if (toneMapError !== null) { return Result.err(toneMapError); }
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
	if (toneMap !== null) {
		toneMap.prepare(renderer.core, renderer.sampler.asHandle());
	}

	const _casters: int32 = drawShadowPass(renderer.core, items, camera, lights);
	if (toneMap !== null) {
		beginPass(renderer.hdrColors, renderer.sceneDepth);
		drawPassLists(renderer.core, items, FORWARD_HDR_LAYOUT);
		endPass();
		toneMap.draw(renderer.core, renderer.toneMapColors);
	} else {
		beginPass(renderer.sceneColors, renderer.sceneDepth);
		drawPassLists(renderer.core, items, FORWARD_LAYOUT);
		endPass();
	}
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
// PENDING3D: copy-opaque
export function drawToScreen(renderer: ForwardRenderer): void {
	if (renderer.closed) { stopOnClosed("drawToScreen"); }
	openScreen(renderer.core);
	const copied: Result<int32, RendererError> =
		drawScreen(renderer.core, renderer.copyMaterial, SWAPCHAIN_LAYOUT);
	if (!copied.ok) { stopOnScreenDraw(copied.error); }
}

// Ends a prepared frame whose `colorTarget` the caller composites itself, in place of
// drawToScreen; the next prepareFrame is then allowed.
export function endPrepared(renderer: ForwardRenderer): void {
	if (renderer.closed) { stopOnClosed("endPrepared"); }
	releasePrepared(renderer.core);
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
	const toneMap: ToneMapPass | null = renderer.toneMap;
	if (toneMap !== null) { toneMap.close(renderer.core.context, "closeForward"); }
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
