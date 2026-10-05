// A renderer preset for low-resolution pixel art, built on the core (renderer.ms) the way
// h3d.scene.fwd.Renderer and pbr.Renderer are built on h3d.scene.Renderer. It is the
// "t3ssel8r" pipeline of Hibernal's RENDERER-BRIEF §3.2, but nothing in it is Hibernal's:
// palettes, look and settings come from the caller.
//
//   Scene  low-res MRT: color + normal (depth packed in its alpha) + depth attachment,
//          drawing the core's pass lists with the preset's own programs (pixelArt3d.glsl) in
//          place of the ones materials name: the toon ramp and the normal target are its look
//   Post   ScreenFx: outline from depth + normal edges, fog, palette LUT; one pass, since the
//          palette only reads the pixel it quantizes (docs/VOID3D.md, Open questions)
//   Blit   ScreenFx to the swapchain: integer scale, nearest, centering + sub-pixel offset
//
// Every GPU object it holds is rebuilt from CPU data when the core reports a new context.

import { Vec4 } from "../math/math3d";
import {
	Program,
	BILLBOARD_LIGHT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_LENGTH,
} from "./gpu3d";
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
import { originTopLeft, depthZeroToOne } from "../gpu/door";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "./material";
import { ProgramMap, ProgramError } from "./programMap";
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
	reserveUniforms,
	writeUniforms,
} from "./draw";
import { UniformError } from "./uniformPool";
import { LowResView, ViewError, lowResView } from "./blit";
import {
	PaletteLut,
	PaletteError,
	DEFAULT_PALETTE_LEVELS,
	fill,
	upload,
	closePalette,
} from "./palette";
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

// The preset's own uniform blocks, from the `binding=` blocks in pixelArt3d.glsl. A lit
// material's block (gpu3d.ms MATERIAL_UNIFORM_SLOT) holds the toon ramp's levels at
// RAMP_LEVELS. A billboard's (BILLBOARD_UNIFORM_SLOT) holds them at BILLBOARD_RAMP_LEVELS, and
// at BILLBOARD_LIGHT_HEIGHT how far above its instance's position, the point its anchor puts
// on the quad, it takes the point lights.
export const RAMP_LEVELS: int32 = 0;
export const BILLBOARD_RAMP_LEVELS: int32 = 4;
export const BILLBOARD_LIGHT_HEIGHT: int32 = 6;
export const POST_UNIFORM_SLOT: int32 = 0;
export const POST_UNIFORM_LENGTH: int32 = 24;
export const BLIT_UNIFORM_SLOT: int32 = 0;
export const BLIT_UNIFORM_LENGTH: int32 = 4;

// What the scene pass draws for the programs materials name.
export function pixelArtPrograms(): ProgramMap {
	return ProgramMap.empty()
		.drawing(Program.Lit, Program.PixelArtLit)
		.drawing(Program.Particle, Program.PixelArtParticle)
		.drawing(Program.Billboard, Program.PixelArtBillboard)
		.drawing(Program.LitTextured, Program.PixelArtLitTextured)
		.drawing(Program.UnlitTextured, Program.PixelArtUnlitTextured)
		.drawing(Program.LitTexturedPremultiplied, Program.PixelArtLitTexturedPremultiplied)
		.drawing(Program.UnlitTexturedPremultiplied, Program.PixelArtUnlitTexturedPremultiplied);
}

// The preset's passes, in the order a frame runs them.
export enum Stage {
	Scene,
	Post,
	Blit,
}

// Where the post pass reads depth for edges and fog. NormalAlpha is an 8-bit copy the scene
// programs pack into the normal target; DepthTexture samples the depth attachment (32-bit
// float on every backend), which is finer and frees that alpha. Which one a device should use
// is measured there (docs/VOID3D.md, Open questions).
export enum DepthSource {
	NormalAlpha,
	DepthTexture,
}

export struct PixelArtSettings {
	// Low-res texels across the framebuffer's short side.
	lowResShortSide: int32;
	// Shrinks the low-res target by this factor; the image covers the same view.
	resolutionDivisor: int32;
	// Texels added on every side of the low-res target, for the sub-pixel shift (M4 sets 1).
	margin: int32;
	// false: the blit reads the scene color, with no outline, fog or palette.
	postPass: boolean;
	outline: boolean;
	palette: boolean;
	depthSource: DepthSource;
}

// Outline from depth and normal edges (postFs). A pixel whose neighbor lies more than
// `depthThreshold` behind it is shaded by `depthShade`; one on a crease (normals closer than
// `normalThreshold` in cosine, same depth) is lit by `normalShade`.
export struct OutlineStyle {
	depthThreshold: float32;
	normalThreshold: float32;
	depthShade: float32;
	normalShade: float32;
}

// Depth fog, `start` to `end` in scene depth (0..1), blended up to `strength` toward `color`.
export struct Fog {
	start: float32;
	end: float32;
	strength: float32;
	color: Vec4;
}

export struct PixelArtLook {
	background: Vec4;
	outline: OutlineStyle;
	fog: Fog;
	// h3d.Matrix.colorSaturate: 0 leaves color alone, -1 is grey. Applied before the palette.
	saturation: float32;
}

export enum PixelArtError {
	UniformPoolFull,
	PaletteLevels,
	CameraBlockLength,
	LightBlockLength,
	ScreenBlockLength,
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
	RampLevels,
}

export interface PixelArtRenderer {
	core: Renderer;
	settings: PixelArtSettings;
	look: PixelArtLook;
	stages: Vec<Stage>;
	colorTarget: RenderTarget;
	normalTarget: RenderTarget;
	depthTarget: RenderTarget;
	postTarget: RenderTarget;
	sampler: Sampler;
	palette: PaletteLut;
	sceneColors: Vec<ColorAttachment>;
	sceneDepth: DepthAttachment;
	postColors: Vec<ColorAttachment>;
	postBlock: UniformBlock;
	blitBlock: UniformBlock;
	postValues: Vec<float32>;
	blitValues: Vec<float32>;
	postMaterial: MaterialId;
	blitMaterial: MaterialId;
	// The view the last frame drew.
	view: LowResView;
	closed: boolean;
}

// Floats of the uniform pool the preset needs, the core's blocks included.
export const PIXEL_ART_UNIFORM_LENGTH: int32 =
	RENDERER_UNIFORM_LENGTH + POST_UNIFORM_LENGTH + BLIT_UNIFORM_LENGTH;

// Attachment formats of the scene and post passes: the target half of their pipeline keys.
export const SCENE_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.Rgba8,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.Depth,
	sampleCount: 1,
};

export const POST_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

// Where nothing is drawn: a normal facing up, at the far plane (1 in the packed alpha).
const NORMAL_CLEAR: Vec4 = { x: 0.5, y: 1.0, z: 0.5, w: 1.0 };
const UNUSED_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
const SCREEN_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
const FAR_DEPTH: float32 = 1.0;
const ON: float32 = 1.0;
const OFF: float32 = 0.0;
const NO_VIEW: LowResView = { width: 0, height: 0, scale: 0, offsetX: 0.0, offsetY: 0.0 };

// postFs `features` and `depthUnpack`, after edge, fog and fogColor.
const POST_FEATURES: int32 = 12;
const POST_DEPTH_UNPACK: int32 = 16;
const POST_COLOR_ADJUST: int32 = 20;

// Hibernal's numbers are the defaults: 360 texels across the short side (360x800 at 3x on
// 1080x2400), outline on, palette off until one is set.
export function full(this typeof PixelArtSettings): PixelArtSettings {
	return {
		lowResShortSide: 360,
		resolutionDivisor: 1,
		margin: 0,
		postPass: true,
		outline: true,
		palette: false,
		depthSource: DepthSource.NormalAlpha,
	};
}

// A cheaper path for thumbnails and pickers (a live wallpaper's isPreview()): half the
// resolution, no outline, same palette and pipelines. The frame rate is the host's to lower.
export function preview(this typeof PixelArtSettings): PixelArtSettings {
	return { ...PixelArtSettings.full(), resolutionDivisor: 2, outline: false };
}

// The stages a frame runs, in order. Allocates: called when the settings change.
export function planStages(settings: PixelArtSettings): Vec<Stage> {
	const stages: Vec<Stage> = [Stage.Scene];
	if (settings.postPass) { stages.push(Stage.Post); }
	stages.push(Stage.Blit);
	return stages;
}

function flag(on: boolean): float32 {
	return on ? ON : OFF;
}

// The post pass uniform block (shader3d.glsl postParams). `zeroToOne` is gpu3d's
// depthZeroToOne: GL stores clip z as (z + 1) / 2, which the unpack undoes.
export function writePostParams(
	this look: PixelArtLook,
	settings: PixelArtSettings,
	paletteLevels: int32,
	zeroToOne: boolean,
	out: Span<float32>,
): void {
	out[0] = look.outline.depthThreshold;
	out[1] = look.outline.normalThreshold;
	out[2] = look.outline.depthShade;
	out[3] = look.outline.normalShade;
	out[4] = look.fog.start;
	out[5] = look.fog.end;
	out[6] = look.fog.strength;
	out[7] = OFF;
	out[8] = look.fog.color.x;
	out[9] = look.fog.color.y;
	out[10] = look.fog.color.z;
	out[11] = look.fog.color.w;
	out[POST_FEATURES] = flag(settings.outline);
	out[POST_FEATURES + 1] = flag(settings.palette);
	out[POST_FEATURES + 2] = flag(settings.depthSource == DepthSource.DepthTexture);
	out[POST_FEATURES + 3] = paletteLevels as float32;
	const scale: float32 = zeroToOne ? 1.0 : 2.0;
	const bias: float32 = zeroToOne ? 0.0 : -1.0;
	out[POST_DEPTH_UNPACK] = scale;
	out[POST_DEPTH_UNPACK + 1] = bias;
	out[POST_DEPTH_UNPACK + 2] = OFF;
	out[POST_DEPTH_UNPACK + 3] = OFF;
	out[POST_COLOR_ADJUST] = look.saturation;
	out[POST_COLOR_ADJUST + 1] = OFF;
	out[POST_COLOR_ADJUST + 2] = OFF;
	out[POST_COLOR_ADJUST + 3] = OFF;
}


function reserve(context: DrawContext, slot: int32, length: int32): UniformBlock {
	return try reserveUniforms(context, slot, length) catch NO_UNIFORMS;
}

// Creates the core, reserves the post and blit blocks and adds their materials to `context`.
// No GPU object is made here: the first prepareFrame makes them.
export function create(
	this typeof PixelArtRenderer,
	context: DrawContext,
	settings: PixelArtSettings,
	look: PixelArtLook,
): Result<PixelArtRenderer, PixelArtError> {
	context.requireOpen("PixelArtRenderer.create");
	const blocks: Vec<int32> = [
		VERTEX_UNIFORM_LENGTH,
		LIGHT_UNIFORM_LENGTH,
		POST_UNIFORM_LENGTH,
		BLIT_UNIFORM_LENGTH,
	];
	if (!context.uniforms.fits(blocks).ok) {
		return Result.err(PixelArtError.UniformPoolFull);
	}
	const palette: Result<PaletteLut, PaletteError> = PaletteLut.withLevels(DEFAULT_PALETTE_LEVELS);
	if (!palette.ok) {
		return Result.err(PixelArtError.PaletteLevels);
	}
	const core: Result<Renderer, RendererError> =
		Renderer.createDrawing(context, pixelArtPrograms());
	if (!core.ok) {
		return Result.err(PixelArtError.UniformPoolFull);
	}
	const postBlock: UniformBlock = reserve(context, POST_UNIFORM_SLOT, POST_UNIFORM_LENGTH);
	const blitBlock: UniformBlock = reserve(context, BLIT_UNIFORM_SLOT, BLIT_UNIFORM_LENGTH);
	const postMaterial: Material = {
		...Material.plain(Program.PixelArtPost, screenState(), Phase.Opaque),
		uniforms: postBlock,
	};
	const blitMaterial: Material = {
		...Material.plain(Program.PixelArtBlit, screenState(), Phase.Opaque),
		uniforms: blitBlock,
	};
	const post: Result<MaterialId, MaterialError> = addMaterial(context, postMaterial);
	const blit: Result<MaterialId, MaterialError> = addMaterial(context, blitMaterial);
	if (!post.ok || !blit.ok) { unreachable; }
	return Result.ok({
		core: core.value,
		settings: settings,
		look: look,
		stages: planStages(settings),
		colorTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		normalTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		depthTarget: RenderTarget.unallocated(PixelFormat.Depth, true),
		postTarget: RenderTarget.unallocated(PixelFormat.Rgba8, true),
		sampler: { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0 },
		palette: palette.value,
		sceneColors: new Array(2),
		sceneDepth: NO_DEPTH,
		postColors: new Array(1),
		postBlock: postBlock,
		blitBlock: blitBlock,
		postValues: new Array(POST_UNIFORM_LENGTH),
		blitValues: new Array(BLIT_UNIFORM_LENGTH),
		postMaterial: post.value,
		blitMaterial: blit.value,
		view: NO_VIEW,
		closed: false,
	});
}

export function setSettings(renderer: PixelArtRenderer, settings: PixelArtSettings): void {
	if (renderer.closed) { stopOnClosed("setSettings"); }
	renderer.settings = settings;
	renderer.stages = planStages(settings);
	renderer.core.changed = true;
}

export function setLook(renderer: PixelArtRenderer, look: PixelArtLook): void {
	if (renderer.closed) { stopOnClosed("setLook"); }
	renderer.look = look;
	renderer.sceneColors[0] = renderer.colorTarget.asColor(LoadAction.Clear, look.background);
	renderer.core.changed = true;
}

// Rebuilds the LUT for `palette` (0xRRGGBB colors); the next frame uploads it. Turning the
// palette on or off is a setting.
export function setPalette(
	renderer: PixelArtRenderer,
	palette: Readonly<Span<uint32>>,
): Result<int32, PaletteError> {
	if (renderer.closed) { stopOnClosed("setPalette"); }
	const written: int32 = try fill(renderer.palette, palette);
	renderer.core.changed = true;
	return Result.ok(written);
}

// Whether a frame with `view` would differ from the last one drawn: the core's inputs, or a
// new view (size or sub-pixel offset). The host may skip the frame when it would not.
export function needsFrame(this renderer: PixelArtRenderer, view: LowResView): boolean {
	if (renderer.closed || renderer.core.isClosed()) { return false; }
	return renderer.core.needsFrame() || !view.sameAs(renderer.view);
}

// The low-res view for this framebuffer, with the camera's sub-pixel remainder (blit.ms).
export function viewFor(
	this renderer: PixelArtRenderer,
	framebufferWidth: int32,
	framebufferHeight: int32,
	remainderX: float32,
	remainderY: float32,
): Result<LowResView, ViewError> {
	if (renderer.closed) { stopOnClosed("viewFor"); }
	const settings: PixelArtSettings = renderer.settings;
	const view: LowResView = try lowResView(
		framebufferWidth,
		framebufferHeight,
		settings.lowResShortSide,
		settings.resolutionDivisor,
		settings.margin,
	);
	return Result.ok(view.withRemainder(remainderX, remainderY, originTopLeft()));
}

function adoptContext(renderer: PixelArtRenderer): void {
	renderer.sampler = Sampler.create(renderer.sampler.filter, renderer.sampler.wrap);
}

function resizeTargets(renderer: PixelArtRenderer, width: int32, height: int32): void {
	const color: RenderTarget = renderer.colorTarget;
	if (color.image != 0 && color.generation == contextGeneration() &&
		color.width == width && color.height == height) {
		return;
	}
	renderer.colorTarget.resize(width, height);
	renderer.normalTarget.resize(width, height);
	renderer.depthTarget.resize(width, height);
	renderer.postTarget.resize(width, height);
	const background: Vec4 = renderer.look.background;
	renderer.sceneColors[0] = renderer.colorTarget.asColor(LoadAction.Clear, background);
	renderer.sceneColors[1] = renderer.normalTarget.asColor(LoadAction.Clear, NORMAL_CLEAR);
	renderer.sceneDepth =
		renderer.depthTarget.asDepth(LoadAction.Clear, FAR_DEPTH, StoreAction.DontCare);
	renderer.postColors[0] = renderer.postTarget.asColor(LoadAction.DontCare, UNUSED_CLEAR);
}

// The screen materials sample the targets and the LUT, whose views change with a resize, a
// palette upload or a new context; rewriting them each frame costs a few stores.
function bindScreenTextures(renderer: PixelArtRenderer): void {
	const context: DrawContext = renderer.core.context;
	const sampler: uint32 = renderer.sampler.asHandle();
	const packedDepth: boolean = renderer.settings.depthSource == DepthSource.NormalAlpha;
	const post: int32 = renderer.postMaterial.index;
	context.materials[post].texture0 = renderer.colorTarget.asTexture();
	context.materials[post].texture1 = renderer.normalTarget.asTexture();
	context.materials[post].texture2 = packedDepth ?
		renderer.normalTarget.asTexture() :
		renderer.depthTarget.asTexture();
	context.materials[post].texture3 = renderer.palette.texture;
	context.materials[post].sampler0 = sampler;
	context.materials[post].sampler1 = sampler;
	const blit: int32 = renderer.blitMaterial.index;
	context.materials[blit].texture0 = renderer.settings.postPass ?
		renderer.postTarget.asTexture() :
		renderer.colorTarget.asTexture();
	context.materials[blit].sampler0 = sampler;
}

function drawScene(renderer: PixelArtRenderer, items: Readonly<Span<DrawItem>>): void {
	beginPass(renderer.sceneColors, renderer.sceneDepth);
	drawPassLists(renderer.core, items, SCENE_LAYOUT);
	endPass();
}

// prepareFrame refused the frame before any pass if either screen material, its texture, its block
// or the screen mesh were gone.
function drawPost(renderer: PixelArtRenderer): void {
	beginPass(renderer.postColors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(renderer.core, renderer.postMaterial, POST_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

function drawBlit(renderer: PixelArtRenderer): void {
	const drawn: Result<int32, RendererError> =
		drawScreen(renderer.core, renderer.blitMaterial, SWAPCHAIN_LAYOUT);
	if (!drawn.ok) { stopOnScreenDraw(drawn.error); }
}

function fromCore(error: RendererError): PixelArtError {
	return match (error) {
		RendererError.UniformPoolFull => PixelArtError.UniformPoolFull,
		RendererError.CameraBlockLength => PixelArtError.CameraBlockLength,
		RendererError.LightBlockLength => PixelArtError.LightBlockLength,
		RendererError.ProgramNotDrawn => PixelArtError.ProgramNotDrawn,
		RendererError.MaterialBlock => PixelArtError.MaterialBlock,
		RendererError.VertexLayout => PixelArtError.VertexLayout,
		RendererError.MaterialTexture => PixelArtError.MaterialTexture,
		RendererError.QuadMesh => PixelArtError.QuadMesh,
		RendererError.UniformsReplaced => PixelArtError.UniformsReplaced,
		RendererError.TextureReplaced => PixelArtError.TextureReplaced,
		RendererError.StaleMesh => PixelArtError.StaleMesh,
		RendererError.StaleMaterial => PixelArtError.StaleMaterial,
		RendererError.ForeignMesh => PixelArtError.ForeignMesh,
		RendererError.ForeignMaterial => PixelArtError.ForeignMaterial,
	};
}

// The toon ramp divides by its levels, so the block of a program that steps its lights needs at
// least one; 0 draws NaN, and NaN fails the comparison too. A block too short to hold them is
// the core's to refuse (RendererError.MaterialBlock).
function levelsAt(context: DrawContext, block: UniformBlock, at: int32): boolean {
	if (block.length <= at) { return true; }
	return context.uniforms.values[block.offset + at] >= 1.0;
}

function billboardLevels(context: DrawContext, block: UniformBlock): boolean {
	if (block.length <= BILLBOARD_LIGHT) { return true; }
	if (context.uniforms.values[block.offset + BILLBOARD_LIGHT] == 0.0) { return true; }
	return levelsAt(context, block, BILLBOARD_RAMP_LEVELS);
}

function rampsHaveLevels(
	programs: ProgramMap,
	context: DrawContext,
	items: Readonly<Span<DrawItem>>,
): boolean {
	for (const item of items) {
		if (!context.hasMaterial(item.material)) { continue; }
		const material: Material = context.materials[item.material.index];
		if (!context.keepsItsUniforms(item.material)) { continue; }
		const drawn: Result<Program, ProgramError> = programs.drawnFor(material.program);
		if (!drawn.ok) { continue; }
		const held: boolean = match (drawn.value) {
			Program.PixelArtLit => levelsAt(context, material.uniforms, RAMP_LEVELS),
			Program.PixelArtLitTextured => levelsAt(context, material.uniforms, RAMP_LEVELS),
			Program.PixelArtLitTexturedPremultiplied =>
				levelsAt(context, material.uniforms, RAMP_LEVELS),
			Program.PixelArtBillboard => billboardLevels(context, material.uniforms),
			Program.Lit => true,
			Program.Particle => true,
			Program.Billboard => true,
			Program.Copy => true,
			Program.PixelArtParticle => true,
			Program.PixelArtPost => true,
			Program.PixelArtBlit => true,
			Program.LitTextured => true,
			Program.UnlitTextured => true,
			Program.PixelArtUnlitTextured => true,
			Program.LitTexturedPremultiplied => true,
			Program.UnlitTexturedPremultiplied => true,
			Program.PixelArtUnlitTexturedPremultiplied => true,
		};
		if (!held) { return false; }
	}
	return true;
}

// One frame: `items` index the meshes and materials of the context the preset was made on;
// `camera` and `lights` are the scene programs' uniform blocks (shader3dBlocks.glsl
// vertexParams, lightParams); `view` comes from viewFor. Answers how many items it was given.
// Allocates nothing unless the item count grew. An item the preset cannot draw, or whose ramp
// has no levels, refuses the frame before anything changes.
export function prepareFrame(
	renderer: PixelArtRenderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
	view: LowResView,
): Result<int32, PixelArtError> {
	if (renderer.closed) { stopOnClosed("prepareFrame"); }
	renderer.core.openPrepare();
	const context: DrawContext = renderer.core.context;
	const screens: boolean =
		context.hasMaterial(renderer.postMaterial) && context.hasMaterial(renderer.blitMaterial);
	if (!screens) {
		const issued: boolean = context.issuedMaterial(renderer.postMaterial) &&
			context.issuedMaterial(renderer.blitMaterial);
		return Result.err(issued ? PixelArtError.StaleMaterial : PixelArtError.ForeignMaterial);
	}
	let kept: boolean = context.keepsItsTexture(renderer.postMaterial) &&
		context.keepsItsTexture(renderer.blitMaterial);
	if (!kept) { return Result.err(PixelArtError.TextureReplaced); }
	const blocksKept: boolean = context.keepsItsUniforms(renderer.postMaterial) &&
		context.keepsItsUniforms(renderer.blitMaterial);
	if (!blocksKept) { return Result.err(PixelArtError.UniformsReplaced); }
	if (!rampsHaveLevels(renderer.core.programs, context, items)) {
		return Result.err(PixelArtError.RampLevels);
	}
	const began: Result<boolean, RendererError> =
		beginFrame(renderer.core, items, camera, lights);
	if (!began.ok) { return Result.err(fromCore(began.error)); }
	if (began.value) {
		adoptContext(renderer);
	}
	resizeTargets(renderer, view.width, view.height);
	upload(renderer.palette);
	bindScreenTextures(renderer);
	renderer.look.writePostParams(
		renderer.settings,
		renderer.palette.levels,
		depthZeroToOne(),
		renderer.postValues,
	);
	view.writeBlitParams(renderer.blitValues);
	const post: Result<int32, UniformError> =
		writeUniforms(context, renderer.postBlock, renderer.postValues);
	const blit: Result<int32, UniformError> =
		writeUniforms(context, renderer.blitBlock, renderer.blitValues);
	if (!post.ok || !blit.ok) { return Result.err(PixelArtError.ScreenBlockLength); }

	for (const stage of renderer.stages) {
		match (stage) {
			Stage.Scene => { drawScene(renderer, items); },
			Stage.Post => { drawPost(renderer); },
			Stage.Blit => {},
		};
	}
	renderer.view = view;
	closePrepare(renderer.core);
	return Result.ok((items.length as int32) - renderer.core.culledCount);
}

function stopOnScreenDraw(error: RendererError): void {
	if (error == RendererError.ForeignMesh || error == RendererError.ForeignMaterial) {
		console.log("void3d: drawToScreen with a blit material or screen mesh of another context");
		unreachable;
	}
	console.log(
		"void3d: drawToScreen after the preset's blit material, texture or screen mesh changed",
	);
	unreachable;
}

// Into the screen pass the caller has open: its pipelines are keyed on SWAPCHAIN_LAYOUT.
// PENDING3D: screen-output-swapchain-only
// PENDING3D: copy-opaque
export function drawToScreen(renderer: PixelArtRenderer): void {
	if (renderer.closed) { stopOnClosed("drawToScreen"); }
	openScreen(renderer.core);
	drawBlit(renderer);
}

export function renderFrame(
	renderer: PixelArtRenderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
	view: LowResView,
): Result<int32, PixelArtError> {
	const drawn: int32 = try prepareFrame(renderer, items, camera, lights, view);
	beginScreenPass(SCREEN_CLEAR);
	drawToScreen(renderer);
	endPass();
	commit();
	return Result.ok(drawn);
}

export function closePixelArt(renderer: PixelArtRenderer): void {
	if (renderer.closed) { stopOnClosed("closePixelArt"); }
	if (passState() != PassState.None) {
		console.log("void3d: closePixelArt with a pass open; endPass ends it");
		unreachable;
	}
	renderer.colorTarget.close();
	renderer.normalTarget.close();
	renderer.depthTarget.close();
	renderer.postTarget.close();
	renderer.sampler = renderer.sampler.released();
	const context: DrawContext = renderer.core.context;
	const post: Result<int32, HandleError> = releaseMaterial(context, renderer.postMaterial);
	const blit: Result<int32, HandleError> = releaseMaterial(context, renderer.blitMaterial);
	if (!post.ok || !blit.ok) {
		console.log("void3d: closePixelArt found its post or blit material already released");
		unreachable;
	}
	if (!renderer.palette.isClosed()) { closePalette(renderer.palette); }
	if (!renderer.core.isClosed()) { closeRenderer(renderer.core); }
	renderer.closed = true;
}

export function isClosed(this renderer: PixelArtRenderer): boolean {
	return renderer.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a pixel-art preset that was closed`);
	unreachable;
}
