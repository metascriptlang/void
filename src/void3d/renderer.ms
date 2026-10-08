// Port of h3d.scene.Renderer: what every renderer does, and no look of its own.
//
// Heaps' base Renderer walks nothing and draws nothing (render() is abstract); it owns the
// named PassLists, sorts them and gives subclasses setTarget/copy. Here the same core owns the
// pass lists (Opaque, Alpha back to front, Additive), the scene's camera and light uniform
// blocks, the frame's time (RenderContext.time, the `global.time` shaders read), the screen
// triangle every ScreenFx draws, and the GPU context bookkeeping. A preset
// (pixelArtRenderer.ms, as fwd.Renderer / pbr.Renderer are in Heaps) owns targets and passes
// and calls beginFrame, drawPassLists (or drawPhase, one list at a time, as Heaps'
// renderPass) and drawScreen in its own order, between openPrepare,
// closePrepare and openScreen, which hold its two halves to one sokol frame.
//
// It takes a Span<DrawItem> and the camera block, never a scene (docs/VOID3D.md, Porting
// rules); the items' meshes and materials live in the DrawContext it was made on. It draws each
// material's program key in its preset: the core's, or the one a preset makes it with.

import {
	Program,
	ProgramKey,
	Preset,
	ProgramError,
	drawnIn,
	VertexLayout,
	vertexLayoutOf,
	drawsQuads,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	SHADOW_UNIFORM_SLOT,
	SHADOW_VIEW_SLOT,
	FRAME_UNIFORM_SLOT,
	FRAME_UNIFORM_LENGTH,
	FRAME_TIME,
	FRAME_EXPOSURE,
	FRAME_LINEAR,
	MOVING_UV_SCROLL,
	movingBase,
	SHADOW_SAMPLER_SLOT,
	uniformBlockLength,
	textureSlotMask,
	samplerSlotMask,
	destroyBuffer,
} from "./gpu3d";
import {
	Material,
	Phase,
	UniformBlock,
	NO_UNIFORMS,
	MATERIAL_TEXTURE_ROLES,
	viewSlotOf,
	samplerSlotOf,
} from "./material";
import { TextureId } from "./texture";
import { TargetLayout } from "../gpu/target";
import {
	PassState,
	passState,
	UNIFORM_SLOTS,
	contextGeneration,
	frameIndex,
} from "../gpu/door";
import {
	DrawContext,
	DrawItem,
	MeshId,
	MaterialId,
	MeshUploadError,
	addMesh,
	releaseMesh,
	HandleError,
	buryDoomed,
	rebuildMeshes,
	rebuildTextures,
	reserveUniforms,
	writeUniforms,
	drawItem,
	MODEL_SLOT,
	SceneTexture,
	NO_SCENE_TEXTURE,
	slotBit,
} from "./draw";
import { UniformError, ownRange, disownRange } from "./uniformPool";
import {
	PassList, collect, filterFrustum, sortBackToFront, sortByLayer, drawPassList,
} from "./passList";
import { screenMesh, screenItem, makeScreenTriangle } from "./screenFx";
import { Mat4 } from "../math/math3d";
import { Frustum3D } from "./frustum";
import { DirShadowMap, castsAll, drawShadows, sceneTexture } from "./dirShadowMap";

// PENDING3D: store-serial-writable
export interface Renderer {
	context: DrawContext;
	opaque: PassList;
	alpha: PassList;
	additive: PassList;
	cameraBlock: UniformBlock;
	lightBlock: UniformBlock;
	frameBlock: UniformBlock;
	sceneGlobals: Vec<UniformBlock>;
	// h3d.scene.RenderContext's `time` and `elapsedTime`, in seconds and 64-bit as Haxe's Float:
	// each beginFrame adds the elapsed time to the time, then writes the time into the frame
	// block as a float32. Void keeps no clock, so the elapsed time stays 0 until the caller sets
	// it (setElapsedTime); the time is the caller's to set too.
	time: float64;
	elapsedTime: float64;
	// Bevy's `GlobalsUniform.time` wraps at an hour; Heaps' `global.time` never does, so this is 0,
	// no wrap, until setTimeWrap.
	timeWrap: float64;
	// h3d.scene.pbr.Renderer's `exposure`, in its unit: stops of e, the multiplier exp(exposure),
	// 0 exposing nothing. Its toneMode is Linear, the one curve here (docs/VOID3D.md, M45).
	exposure: float32;
	// The scene passes draw into an HDR target: scene programs write linear colour, and the
	// preset that set this exposes and encodes it in its own pass.
	linearOutput: boolean;
	frameValues: Vec<float32>;
	// The last frame drew a material whose UV transform scrolls.
	readsTime: boolean;
	preset: Preset;
	// Per item of the frame, the key drawn for its material's.
	drawn: Vec<ProgramKey>;
	shadow: DirShadowMap | null;
	screenMesh: MeshId;
	// The GPU context the handles in play belong to; 0 before the first frame.
	generation: int32;
	// Something changed since the last frame (V6: the host skips frames that would draw the
	// same image).
	changed: boolean;
	prepared: boolean;
	preparedFrame: uint32;
	culledCount: int32;
	closed: boolean;
}

export enum RendererError {
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
}

// Floats of the uniform pool the core reserves: camera, lights and the frame block.
export const RENDERER_UNIFORM_LENGTH: int32 =
	VERTEX_UNIFORM_LENGTH + LIGHT_UNIFORM_LENGTH + FRAME_UNIFORM_LENGTH;

const NO_GLOBALS: Vec<UniformBlock> = [];

function meshError(context: DrawContext, id: MeshId): RendererError {
	return context.issuedMesh(id) ? RendererError.StaleMesh : RendererError.ForeignMesh;
}

function materialError(context: DrawContext, id: MaterialId): RendererError {
	return context.issuedMaterial(id) ? RendererError.StaleMaterial : RendererError.ForeignMaterial;
}

// createDrawing checked that the pool fits the block, and the renderer owns it, so nothing but
// the renderer can release it.
function reserveOwned(context: DrawContext, slot: int32, length: int32): UniformBlock {
	const reserved: Result<UniformBlock, UniformError> = reserveUniforms(context, slot, length);
	if (!reserved.ok) { unreachable; }
	if (!ownRange(context.uniforms, reserved.value).ok) { unreachable; }
	return reserved.value;
}

// Reserves the camera, light and frame blocks and adds the screen triangle's mesh to `context`. No
// GPU object is made here: the first beginFrame makes them. It draws the core's programs.
export function create(
	this typeof Renderer,
	context: DrawContext,
): Result<Renderer, RendererError> {
	return Renderer.createDrawing(context, Preset.Core);
}

// The same, drawing its materials' programs in `preset`: a preset's.
export function createDrawing(
	this typeof Renderer,
	context: DrawContext,
	preset: Preset,
): Result<Renderer, RendererError> {
	context.requireOpen("Renderer.createDrawing");
	const blocks: Vec<int32> =
		[VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH, FRAME_UNIFORM_LENGTH];
	if (!context.uniforms.fits(blocks).ok) {
		return Result.err(RendererError.UniformPoolFull);
	}
	const cameraBlock: UniformBlock =
		reserveOwned(context, VERTEX_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH);
	const lightBlock: UniformBlock =
		reserveOwned(context, LIGHT_UNIFORM_SLOT, LIGHT_UNIFORM_LENGTH);
	const frameBlock: UniformBlock =
		reserveOwned(context, FRAME_UNIFORM_SLOT, FRAME_UNIFORM_LENGTH);
	const screen: Result<MeshId, MeshUploadError> = addMesh(context, screenMesh(0));
	if (!screen.ok) { unreachable; }
	return Result.ok({
		context: context,
		opaque: PassList.forPhase(Phase.Opaque),
		alpha: PassList.forPhase(Phase.Alpha),
		additive: PassList.forPhase(Phase.Additive),
		cameraBlock: cameraBlock,
		lightBlock: lightBlock,
		frameBlock: frameBlock,
		sceneGlobals: [cameraBlock, lightBlock, frameBlock],
		time: 0.0,
		elapsedTime: 0.0,
		timeWrap: 0.0,
		exposure: 0.0,
		linearOutput: false,
		frameValues: new Array(FRAME_UNIFORM_LENGTH),
		readsTime: false,
		preset: preset,
		drawn: [],
		shadow: null,
		screenMesh: screen.value,
		generation: 0,
		changed: true,
		prepared: false,
		preparedFrame: 0,
		culledCount: 0,
		closed: false,
	});
}

// For whatever the renderer cannot see: the items moved, a material or a light changed.
export function markChanged(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("markChanged"); }
	renderer.changed = true;
}

function stopOnForeignShadow(): void {
	console.log("void3d: attachShadow with a shadow map of another draw context");
	unreachable;
}

function stopOnClosedShadow(call: string): void {
	console.log(`void3d: ${call} with a shadow map that was closed`);
	unreachable;
}

export function attachShadow(renderer: Renderer, shadow: DirShadowMap | null): void {
	if (renderer.closed) { stopOnClosed("attachShadow"); }
	if (shadow !== null && shadow.context !== renderer.context) { stopOnForeignShadow(); }
	if (shadow !== null && shadow.isClosed()) { stopOnClosedShadow("attachShadow"); }
	renderer.shadow = shadow;
	renderer.sceneGlobals = shadow !== null ?
		[renderer.cameraBlock, renderer.lightBlock, renderer.frameBlock, shadow.shadowBlock] :
		[renderer.cameraBlock, renderer.lightBlock, renderer.frameBlock];
	renderer.changed = true;
}

// h3d.scene.Scene.setElapsedTime: what the next beginFrame adds to the time.
export function setElapsedTime(renderer: Renderer, seconds: float64): void {
	if (renderer.closed) { stopOnClosed("setElapsedTime"); }
	renderer.elapsedTime = seconds;
}

// h3d.shader.pbr.ToneMapping.set_exposure: exposureExp = Math.exp(exposure).
export function exposureMultiplier(stops: float32): float32 {
	return Math.exp(stops) as float32;
}

export function setExposure(renderer: Renderer, stops: float32): void {
	if (renderer.closed) { stopOnClosed("setExposure"); }
	if (!Number.isFinite(stops)) {
		console.log(`void3d: setExposure with ${stops} stops; an exposure is a finite number`);
		unreachable;
	}
	renderer.exposure = stops;
}

export function setTimeWrap(renderer: Renderer, seconds: float64): void {
	if (renderer.closed) { stopOnClosed("setTimeWrap"); }
	if (!(seconds >= 0.0)) {
		console.log(`void3d: setTimeWrap with ${seconds} seconds; 0 turns the wrap off`);
		unreachable;
	}
	renderer.timeWrap = seconds;
}

export function frameTime(time: float64, wrap: float64): float32 {
	if (wrap <= 0.0) { return time as float32; }
	return (time - Math.floor(time / wrap) * wrap) as float32;
}

// Whether the next frame could differ from the last one drawn: something was marked changed,
// the GPU context is new, or time passes under a key that reads it. A preset adds its own
// inputs (the view, its settings).
export function needsFrame(this renderer: Renderer): boolean {
	if (renderer.closed) { return false; }
	const moving: boolean = renderer.readsTime && renderer.elapsedTime != 0.0;
	return renderer.changed || moving || renderer.generation != contextGeneration();
}

// Starts a frame: uploads the camera and lights, adopts a new GPU context if there is one and fills
// the pass lists from `items`. A camera or light span that is not its block's length, an item whose
// material names a program this renderer does not draw, a material whose block is not the one that
// program reads or has been released, or that lacks a texture or sampler it samples, names a
// texture it does not sample or another than it was added with, or a mesh whose vertex layout it
// does not read, or a quad-layout mesh with a vertex buffer or with instances and no instance
// buffer, is refused before anything changes. Answers true when the context is new: every handle
// the caller made before is stale then (it may name an object of the new context), so the caller
// drops its own without destroying them and makes them again before drawing. The core has already
// dropped the pipelines, remade the screen triangle, and remade every mesh and texture that
// carries its CPU data (draw.ms rebuildMeshes, rebuildTextures); what is left is whatever the
// caller uploaded from buffers only it keeps.
export function beginFrame(
	renderer: Renderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
): Result<boolean, RendererError> {
	if (renderer.closed) { stopOnClosed("beginFrame"); }
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) {
		return Result.err(meshError(context, renderer.screenMesh));
	}
	const shadow: DirShadowMap | null = renderer.shadow;
	if (shadow !== null && shadow.isClosed()) { stopOnClosedShadow("beginFrame"); }
	const shadowed: boolean = shadow !== null;
	for (const item of items) {
		if (!context.hasMesh(item.mesh)) { return Result.err(meshError(context, item.mesh)); }
		if (!context.hasMaterial(item.material)) {
			return Result.err(materialError(context, item.material));
		}
		const material: int32 = item.material.index;
		const drawn: Result<ProgramKey, ProgramError> =
			drawnIn(context.materials[material].program, renderer.preset, shadowed);
		if (!drawn.ok) { return Result.err(RendererError.ProgramNotDrawn); }
		if (!context.keepsItsUniforms(item.material)) {
			return Result.err(RendererError.UniformsReplaced);
		}
		if (!context.keepsItsTexture(item.material)) {
			return Result.err(RendererError.TextureReplaced);
		}
		if (!blockFits(drawn.value, context.materials[material].uniforms)) {
			return Result.err(RendererError.MaterialBlock);
		}
		const layout: VertexLayout = context.meshes[item.mesh.index].layout;
		if (layout != vertexLayoutOf(drawn.value)) {
			return Result.err(RendererError.VertexLayout);
		}
		if (drawsQuads(layout) && !context.meshes[item.mesh.index].isQuadShaped()) {
			return Result.err(RendererError.QuadMesh);
		}
		if (!texturesFit(drawn.value, context.materials[material])) {
			return Result.err(RendererError.MaterialTexture);
		}
	}
	if (shadow !== null) {
		const cast: Result<int32, ProgramError> = shadow.castsAll(items);
		if (!cast.ok) {
			return Result.err(cast.error == ProgramError.BlockShort ?
				RendererError.CasterBlock : RendererError.ProgramNotCast);
		}
	}
	if ((camera.length as int32) != renderer.cameraBlock.length) {
		return Result.err(RendererError.CameraBlockLength);
	}
	if ((lights.length as int32) != renderer.lightBlock.length) {
		return Result.err(RendererError.LightBlockLength);
	}
	const cameraWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.cameraBlock, camera);
	if (!cameraWritten.ok) { return Result.err(RendererError.CameraBlockLength); }
	const lightsWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.lightBlock, lights);
	if (!lightsWritten.ok) { return Result.err(RendererError.LightBlockLength); }
	renderer.time = renderer.time + renderer.elapsedTime;
	renderer.frameValues[FRAME_TIME] = frameTime(renderer.time, renderer.timeWrap);
	renderer.frameValues[FRAME_EXPOSURE] = exposureMultiplier(renderer.exposure);
	renderer.frameValues[FRAME_LINEAR] = renderer.linearOutput ? 1.0 : 0.0;
	if (!writeUniforms(context, renderer.frameBlock, renderer.frameValues).ok) { unreachable; }
	while ((renderer.drawn.length as int32) < (items.length as int32)) {
		renderer.drawn.push(ProgramKey.of(Program.Lit));
	}
	let readsTime: boolean = false;
	for (let i = 0; i < (items.length as int32); i++) {
		const resolved: Result<ProgramKey, ProgramError> =
			drawnIn(context.materials[items[i].material.index].program, renderer.preset, shadowed);
		if (!resolved.ok) { unreachable; }
		renderer.drawn[i] = resolved.value;
		readsTime = readsTime || scrolls(context, items[i].material.index, resolved.value);
	}
	renderer.readsTime = readsTime;
	const generation: int32 = contextGeneration();
	const _buried: int32 = buryDoomed(context, generation);
	const fresh: boolean = generation != renderer.generation;
	if (fresh) {
		rebuildMeshes(context);
		rebuildTextures(context);
		context.meshes[renderer.screenMesh.index].vertexBuffer = makeScreenTriangle();
		renderer.generation = generation;
		renderer.changed = true;
	}
	collect(renderer.opaque, items, context.materials);
	collect(renderer.alpha, items, context.materials);
	collect(renderer.additive, items, context.materials);
	let viewProj: Mat4 = {
		m11: camera[0], m12: camera[1], m13: camera[2], m14: camera[3],
		m21: camera[4], m22: camera[5], m23: camera[6], m24: camera[7],
		m31: camera[8], m32: camera[9], m33: camera[10], m34: camera[11],
		m41: camera[12], m42: camera[13], m43: camera[14], m44: camera[15],
	};
	let frustum: Frustum3D = Frustum3D.fromMatrix(viewProj);
	renderer.culledCount =
		filterFrustum(renderer.opaque, items, context.meshData, frustum) +
		filterFrustum(renderer.alpha, items, context.meshData, frustum) +
		filterFrustum(renderer.additive, items, context.meshData, frustum);
	sortByLayer(renderer.opaque);
	sortBackToFront(renderer.alpha, items, camera);
	sortByLayer(renderer.additive);
	return Result.ok(fresh);
}

export function drawShadowPass(
	renderer: Renderer,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
): int32 {
	if (renderer.closed) { stopOnClosed("drawShadowPass"); }
	const shadow: DirShadowMap | null = renderer.shadow;
	if (shadow === null) { return 0; }
	return drawShadows(shadow, items, camera, lights);
}

function sceneTextureOf(renderer: Renderer): SceneTexture {
	const shadow: DirShadowMap | null = renderer.shadow;
	if (shadow === null) { return NO_SCENE_TEXTURE; }
	return shadow.sceneTexture();
}

// fwd.Renderer's default, alpha and additive passes, into the current pass (`targets` is
// its attachment layout), with the camera and lights applied to every item and each drawn with
// the program beginFrame resolved for it: `items` must be the span that beginFrame accepted.
export function drawPassLists(
	renderer: Renderer,
	items: Readonly<Span<DrawItem>>,
	targets: TargetLayout,
): void {
	if (renderer.closed) { stopOnClosed("drawPassLists"); }
	drawPhase(renderer, Phase.Opaque, items, targets);
	drawPhase(renderer, Phase.Alpha, items, targets);
	drawPhase(renderer, Phase.Additive, items, targets);
}

// fwd.Renderer's renderPass(output, get(name)): one of the lists into the current pass, for a
// preset that sends its lists to different targets.
export function drawPhase(
	renderer: Renderer,
	phase: Phase,
	items: Readonly<Span<DrawItem>>,
	targets: TargetLayout,
): void {
	if (renderer.closed) { stopOnClosed("drawPhase"); }
	const context: DrawContext = renderer.context;
	const scene: SceneTexture = sceneTextureOf(renderer);
	match (phase) {
		Phase.Opaque => {
			drawPassList(
				context, renderer.opaque, items, renderer.drawn, targets, renderer.sceneGlobals,
				scene,
			);
		},
		Phase.Alpha => {
			drawPassList(
				context, renderer.alpha, items, renderer.drawn, targets, renderer.sceneGlobals,
				scene,
			);
		},
		Phase.Additive => {
			drawPassList(
				context, renderer.additive, items, renderer.drawn, targets, renderer.sceneGlobals,
				scene,
			);
		},
	};
}

// How many items of `phase` the frame beginFrame accepted draws, after culling.
export function phaseCount(this renderer: Renderer, phase: Phase): int32 {
	if (renderer.closed) { stopOnClosed("phaseCount"); }
	return match (phase) {
		Phase.Opaque => renderer.opaque.count,
		Phase.Alpha => renderer.alpha.count,
		Phase.Additive => renderer.additive.count,
	};
}

// ScreenFx.render: `material` (a Fullscreen-layout material of the renderer's context, drawn
// with its own program) over the whole current pass.
export function drawScreen(
	renderer: Renderer,
	material: MaterialId,
	targets: TargetLayout,
): Result<int32, RendererError> {
	if (renderer.closed) { stopOnClosed("drawScreen"); }
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) {
		return Result.err(meshError(context, renderer.screenMesh));
	}
	if (!context.hasMaterial(material)) { return Result.err(materialError(context, material)); }
	if (!context.keepsItsUniforms(material)) {
		return Result.err(RendererError.UniformsReplaced);
	}
	if (!context.keepsItsTexture(material)) { return Result.err(RendererError.TextureReplaced); }
	const program: ProgramKey = context.materials[material.index].program;
	drawItem(context, screenItem(renderer.screenMesh, material), program, targets, NO_GLOBALS);
	return Result.ok(1);
}

// Whether material `index`, drawn as `key`, scrolls its UV with the frame's time.
function scrolls(context: DrawContext, index: int32, key: ProgramKey): boolean {
	if (!key.uvTransform) { return false; }
	const block: UniformBlock = context.materials[index].uniforms;
	const at: int32 = block.offset + movingBase(key) + MOVING_UV_SCROLL;
	return context.uniforms.values[at] != 0.0 || context.uniforms.values[at + 1] != 0.0;
}

// The one block a material brings for `program`: the slot it declares that is neither pass-wide
// nor the model matrix, at the length its shader declares; none when it declares no such slot.
function blockFits(program: ProgramKey, block: UniformBlock): boolean {
	let own: int32 = -1;
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		const passWide: boolean = slot == VERTEX_UNIFORM_SLOT || slot == LIGHT_UNIFORM_SLOT ||
			slot == SHADOW_UNIFORM_SLOT || slot == FRAME_UNIFORM_SLOT;
		if (passWide || slot == MODEL_SLOT || uniformBlockLength(program, slot) == 0) {
			continue;
		}
		if (own >= 0) { return false; }
		own = slot;
	}
	if (own < 0) { return block.length == 0; }
	return block.slot == own && block.length == uniformBlockLength(program, own);
}

// Every texture view and sampler `program` declares is bound on `material`, each by one field: a
// raw view or sampler, or a context texture's role. The shadow map's are the scene's to bind for
// a shadowed program.
function texturesFit(program: ProgramKey, material: Material): boolean {
	const sceneViews: uint32 = program.shadowed ? slotBit(SHADOW_VIEW_SLOT) : 0;
	const sceneSamplers: uint32 = program.shadowed ? slotBit(SHADOW_SAMPLER_SLOT) : 0;
	const views: uint32 = textureSlotMask(program) & ~sceneViews;
	const samplers: uint32 = samplerSlotMask(program) & ~sceneSamplers;
	let boundViews: uint32 = 0;
	let boundSamplers: uint32 = 0;
	for (let slot = 0; slot < 4; slot++) {
		if (material.rawView(slot) != 0) { boundViews = boundViews | slotBit(slot); }
	}
	for (let slot = 0; slot < 2; slot++) {
		if (material.rawSampler(slot) != 0) { boundSamplers = boundSamplers | slotBit(slot); }
	}
	for (let role = 0; role < MATERIAL_TEXTURE_ROLES; role++) {
		if (!material.textureOf(role).isTexture()) { continue; }
		const view: uint32 = slotBit(viewSlotOf(role));
		const sampler: int32 = samplerSlotOf(role);
		const read: uint32 = slotBit(sampler >= 0 ? sampler : 0);
		if ((boundViews & view) != 0 || (views & view) == 0 || (samplers & read) == 0) {
			return false;
		}
		boundViews = boundViews | view;
		if (sampler >= 0) {
			if ((boundSamplers & read) != 0) { return false; }
			boundSamplers = boundSamplers | read;
		}
	}
	return (views & ~boundViews) == 0 && (samplers & ~boundSamplers) == 0;
}

export function openPrepare(this renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("prepareFrame"); }
	if (renderer.prepared) {
		console.log("void3d: prepareFrame on a frame no drawToScreen or endPrepared ended");
		unreachable;
	}
	// sokol cannot nest passes, and the prepare opens its own (the door tracks which pass is
	// open, M18's screen-pass-unchecked).
	if (passState() != PassState.None) {
		console.log("void3d: prepareFrame with a pass already open; it would nest inside it");
		unreachable;
	}
}

// The frame's inputs are taken here, so a change made before the screen half is kept.
export function closePrepare(renderer: Renderer): void {
	renderer.prepared = true;
	renderer.preparedFrame = frameIndex();
	renderer.changed = false;
}

export function openScreen(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("drawToScreen"); }
	if (!renderer.prepared) {
		console.log("void3d: drawToScreen with no prepared frame; call prepareFrame first");
		unreachable;
	}
	if (passState() != PassState.Screen) {
		console.log("void3d: drawToScreen outside a screen pass; open one with beginScreenPass");
		unreachable;
	}
	// frameIndex counts sokol frames, so it is read only once a screen pass proves one is
	// being recorded; a headless caller stops above before touching it.
	if (renderer.preparedFrame != frameIndex()) {
		console.log("void3d: drawToScreen in a later sokol frame than the prepareFrame it draws");
		unreachable;
	}
	renderer.prepared = false;
}

// The end of a prepared frame the caller composites itself: Scene.setOutputTarget has no screen
// half (heaps h3d/scene/Scene.hx:586), so the target the prepare drew is the frame's whole product.
export function releasePrepared(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("endPrepared"); }
	if (!renderer.prepared) {
		console.log("void3d: endPrepared with no prepared frame; call prepareFrame first");
		unreachable;
	}
	renderer.prepared = false;
}

export function closeRenderer(renderer: Renderer): void {
	if (renderer.closed) { stopOnClosed("closeRenderer"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeRenderer with a pass open; endPass ends it");
		unreachable;
	}
	const context: DrawContext = renderer.context;
	if (!context.hasMesh(renderer.screenMesh)) { stopOnLostScreenMesh(context, renderer); }
	const screen: int32 = renderer.screenMesh.index;
	const buffer: uint32 = context.meshes[screen].vertexBuffer;
	if (buffer != 0 && renderer.generation == contextGeneration()) { destroyBuffer(buffer); }
	context.meshes[screen].vertexBuffer = 0;
	const released: Result<int32, HandleError> = releaseMesh(context, renderer.screenMesh);
	if (!released.ok) { stopOnLostScreenMesh(context, renderer); }
	const camera: Result<int32, UniformError> = disownRange(context.uniforms, renderer.cameraBlock);
	const light: Result<int32, UniformError> = disownRange(context.uniforms, renderer.lightBlock);
	const frame: Result<int32, UniformError> = disownRange(context.uniforms, renderer.frameBlock);
	if (!camera.ok || !light.ok || !frame.ok) {
		console.log("void3d: closeRenderer found a block of its own already given back");
		unreachable;
	}
	renderer.closed = true;
}

export function isClosed(this renderer: Renderer): boolean {
	return renderer.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a renderer that was closed`);
	unreachable;
}

function stopOnLostScreenMesh(context: DrawContext, renderer: Renderer): void {
	const holders: int32 = context.meshHolders[renderer.screenMesh.index];
	console.log(`void3d: closeRenderer found its screen mesh released (${holders} holders)`);
	unreachable;
}
