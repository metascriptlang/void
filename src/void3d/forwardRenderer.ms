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
	depthZeroToOne,
} from "../gpu/door";
import { FilterMode, Wrap, Compare } from "../gpu/state";
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
import { BloomSettings } from "./bloom";
import { screenState } from "./screenFx";
import {
	ForwardOutlineSettings, ForwardOutlinePass, FORWARD_OUTLINE_PASS_UNIFORM_LENGTH,
	FORWARD_OUTLINE_BLOCKS, OUTLINE_SCENE_LAYOUT,
} from "./forwardOutline";
import {
	ToneMapPass,
	TONE_MAP_PASS_BLOCKS,
	TONE_MAP_PASS_UNIFORM_LENGTH,
	linearBackground,
	toneMappedBackground,
} from "./toneMap";
import {
	Renderer,
	RendererError,
	RENDERER_UNIFORM_LENGTH,
	beginFrame,
	drawPassLists,
	drawPhase,
	drawScreen,
	closePrepare,
	openScreen,
	releasePrepared,
	closeRenderer,
	drawShadowPass,
	exposureMultiplier,
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
	outlineBlend: float32;
	outlineSettings: ForwardOutlineSettings;
	outline: ForwardOutlinePass | null;
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
	OutlineBlendedOpaque,
	OutlineOpaqueDepth,
	OutlineTranslucentDepthWrite,
}

// Floats of the uniform pool the preset needs: the core's blocks, and nothing of its own.
export const FORWARD_UNIFORM_LENGTH: int32 = RENDERER_UNIFORM_LENGTH;
// Budget for plain create plus its lazily reserved outline passes.
export const FORWARD_OUTLINE_UNIFORM_LENGTH: int32 =
	FORWARD_UNIFORM_LENGTH + FORWARD_OUTLINE_PASS_UNIFORM_LENGTH;

// An HDR preset's floats: the core's blocks and the tone map's.
export const FORWARD_HDR_UNIFORM_LENGTH: int32 =
	RENDERER_UNIFORM_LENGTH + TONE_MAP_PASS_UNIFORM_LENGTH;

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
	let blocks: Vec<int32> = [VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH, FRAME_UNIFORM_LENGTH];
	for (const length of TONE_MAP_PASS_BLOCKS) { blocks.push(length); }
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
		outlineBlend: 0.0,
		outlineSettings: ForwardOutlineSettings.defaults(),
		outline: null,
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
	const toneMap: ToneMapPass | null = renderer.toneMap;
	if (toneMap !== null) { toneMap.bloom.adoptContext(); }
	const outline: ForwardOutlinePass | null = renderer.outline;
	if (outline !== null) { outline.adoptContext(); }
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
	if (!Number.isFinite(renderer.outlineBlend) ||
		renderer.outlineBlend < 0.0 || renderer.outlineBlend > 1.0) {
		console.log("void3d: prepareFrame needs a finite outlineBlend in [0,1]; " +
			"setOutlineBlend validates it");
		unreachable;
	}
	if (renderer.outlineBlend > 0.0 &&
		(renderer.outline === null || !renderer.outlineSettings.valid())) {
		console.log("void3d: prepareFrame needs outline holders and valid outlineSettings; " +
			"setOutlineBlend and setOutlineSettings validate them");
		unreachable;
	}
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
		const first: ForwardError | null = screenMaterialError(renderer, toneMap.bloom.first);
		if (first !== null) { return Result.err(first); }
		const down: ForwardError | null = screenMaterialError(renderer, toneMap.bloom.down);
		if (down !== null) { return Result.err(down); }
		const up: ForwardError | null = screenMaterialError(renderer, toneMap.bloom.up);
		if (up !== null) { return Result.err(up); }
	}
	const outline: ForwardOutlinePass | null = renderer.outline;
	const outlined: boolean = renderer.outlineBlend > 0.0 && outline !== null;
	if (outlined && outline !== null) {
		const maskError: ForwardError | null = screenMaterialError(renderer, outline.maskMaterial);
		if (maskError !== null) { return Result.err(maskError); }
		const mixError: ForwardError | null = screenMaterialError(renderer, outline.mixMaterial);
		if (mixError !== null) { return Result.err(mixError); }
		const widthError: ForwardError | null =
			screenMaterialError(renderer, outline.widthMaterial);
		if (widthError !== null) { return Result.err(widthError); }
		const phases: ForwardError | null = outlinePhases(renderer.core.context, items);
		if (phases !== null) { return Result.err(phases); }
	}
	renderer.core.normalMrt = outlined;
	const began: Result<boolean, RendererError> =
		beginFrame(renderer.core, items, camera, lights);
	if (!began.ok) { return Result.err(fromCore(began.error)); }
	if (began.value) {
		adoptContext(renderer);
	}
	resizeTargets(renderer, width, height);
	if (renderer.toneMap === null) {
		const core: Renderer = renderer.core;
		renderer.sceneColors[0].clear = toneMappedBackground(
			renderer.background, exposureMultiplier(core.exposure), core.toneMode,
		);
	}
	context.materials[renderer.copyMaterial.index].texture0 = renderer.colorTarget.asTexture();
	context.materials[renderer.copyMaterial.index].sampler0 = renderer.sampler.asHandle();
	if (toneMap !== null) {
		toneMap.prepare(renderer.core, renderer.sampler.asHandle());
	}

	const _casters: int32 = drawShadowPass(renderer.core, items, camera, lights);
	if (outlined && outline !== null) {
		drawOutlined(renderer, outline, items, width, height);
	} else if (toneMap !== null) {
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
// Copy preserves the final premultiplied RGBA, including an outlined transparent clear.
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
	const outline: ForwardOutlinePass | null = renderer.outline;
	if (outline !== null) { outline.close(renderer.core.context); }
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

// Bevy's Bloom on an HDR preset's target, before the tone map; null turns it off and releases its
// mips. An LDR preset has no HDR target to bloom.
export function setBloom(renderer: ForwardRenderer, settings: BloomSettings | null): void {
	if (renderer.closed) { stopOnClosed("setBloom"); }
	const toneMap: ToneMapPass | null = renderer.toneMap;
	if (toneMap !== null) {
		toneMap.bloom.setSettings(renderer.core.context, settings);
		renderer.core.changed = true;
		return;
	}
	console.log("void3d: setBloom on a forward preset made by create; bloom needs createHdr");
	unreachable;
}

export function isClosed(this renderer: ForwardRenderer): boolean {
	return renderer.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a forward preset that was closed`);
	unreachable;
}

// Per-frame scalar, like setExposure. Zero uses the original pass and program keys exactly.
// Enabling reserves CPU holders only; first prepare allocates full-frame GPU targets.
export function setOutlineBlend(renderer: ForwardRenderer, blend: float32): void {
	if (renderer.closed) { stopOnClosed("setOutlineBlend"); }
	if (!Number.isFinite(blend) || blend < 0.0 || blend > 1.0) {
		console.log("void3d: setOutlineBlend needs a finite blend in [0,1]");
		unreachable;
	}
	if (blend > 0.0 && renderer.outline === null) {
		const context: DrawContext = renderer.core.context;
		context.requireOpen("setOutlineBlend");
		if (!context.uniforms.fits(FORWARD_OUTLINE_BLOCKS).ok) {
			console.log("void3d: setOutlineBlend needs FORWARD_OUTLINE_PASS_UNIFORM_LENGTH " +
				"additional uniform floats; FORWARD_OUTLINE_UNIFORM_LENGTH budgets plain create");
			unreachable;
		}
		renderer.outline = ForwardOutlinePass.reserve(context);
	}
	renderer.outlineBlend = blend;
	renderer.core.changed = true;
}

export function setOutlineSettings(
	renderer: ForwardRenderer,
	settings: ForwardOutlineSettings,
): void {
	if (renderer.closed) { stopOnClosed("setOutlineSettings"); }
	if (!settings.valid()) {
		console.log("void3d: setOutlineSettings needs finite straight RGBA [0,1], " +
			"pixelWidth [1,16], depthThreshold (0,1], normalThreshold [-1,1]");
		unreachable;
	}
	renderer.outlineSettings = settings;
	renderer.core.changed = true;
}

function outlinePhases(
	context: DrawContext,
	items: Readonly<Span<DrawItem>>,
): ForwardError | null {
	for (const item of items) {
		if (!context.hasMaterial(item.material)) { continue; }
		const material: Material = context.materials[item.material.index];
		if (material.phase == Phase.Opaque) {
			if (material.pass.blends()) { return ForwardError.OutlineBlendedOpaque; }
			if (!material.pass.depthWrite ||
				(material.pass.depthTest != Compare.Less &&
					material.pass.depthTest != Compare.LessEqual)) {
				return ForwardError.OutlineOpaqueDepth;
			}
		} else if (material.pass.depthWrite) {
			return ForwardError.OutlineTranslucentDepthWrite;
		}
	}
	return null;
}

function drawOutlined(
	renderer: ForwardRenderer,
	outline: ForwardOutlinePass,
	items: Readonly<Span<DrawItem>>,
	width: int32,
	height: int32,
): void {
	const core: Renderer = renderer.core;
	if (outline.linearSampler.handle == 0) { outline.adoptContext(); }
	outline.resize(width, height, renderer.outlineSettings.pixelWidth != 2.0);
	const toneMap: ToneMapPass | null = renderer.toneMap;
	const hdr: boolean = toneMap !== null;
	const opaqueLayout: TargetLayout = hdr ?
		{ ...OUTLINE_SCENE_LAYOUT, color0: PixelFormat.Rgba16f } : OUTLINE_SCENE_LAYOUT;
	if (toneMap !== null) {
		outline.sceneColors[0] = toneMap.target.asColor(LoadAction.Clear,
			linearBackground(renderer.background));
		outline.translucentColors[0] = toneMap.target.asColor(LoadAction.Load, SCREEN_CLEAR);
	} else {
		outline.sceneColors[0].clear = renderer.sceneColors[0].clear;
	}
	beginPass(outline.sceneColors, outline.sceneDepth);
	drawPhase(core, Phase.Opaque, items, opaqueLayout);
	endPass();
	if (core.phaseCount(Phase.Alpha) + core.phaseCount(Phase.Additive) > 0) {
		beginPass(outline.translucentColors, outline.translucentDepth);
		const layout: TargetLayout = hdr ? FORWARD_HDR_LAYOUT : FORWARD_LAYOUT;
		drawPhase(core, Phase.Alpha, items, layout);
		drawPhase(core, Phase.Additive, items, layout);
		endPass();
	}
	if (toneMap !== null) {
		outline.translucentColors[0] = outline.lit.asColor(LoadAction.DontCare, SCREEN_CLEAR);
		toneMap.draw(core, outline.translucentColors);
	}
	outline.prepare(core.context, renderer.outlineSettings, renderer.outlineBlend,
		depthZeroToOne(), renderer.sampler.asHandle());
	outline.drawMask(core);
	if (renderer.outlineSettings.pixelWidth != 2.0) { outline.drawWidth(core); }
	outline.drawMix(core, renderer.sceneColors);
}
