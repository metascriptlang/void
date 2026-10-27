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
	SKIN_UNIFORM_SLOT,
	vertexLayoutOf,
	drawsQuads,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_SHAPE,
	LIGHT_CLUSTER_GRID,
	CLUSTER_SCENE_VIEWS,
	CLUSTER_SCENE_SAMPLERS,
	SHADOW_UNIFORM_SLOT,
	SHADOW_VIEW_SLOT,
	FRAME_UNIFORM_SLOT,
	FRAME_UNIFORM_LENGTH,
	FRAME_TIME,
	FRAME_EXPOSURE,
	FRAME_LINEAR,
	FRAME_TONE_MODE,
	FRAME_CAMERA_POSITION,
	FRAME_ENV_POWER,
	FRAME_ENV_LEVELS,
	FRAME_ENV_COS,
	FRAME_ENV_SIN,
	ENV_SCENE_VIEWS,
	ENV_SCENE_SAMPLERS,
	MOVING_UV_SCROLL,
	PBR_UV_SCROLL,
	movingBase,
	SHADOW_SAMPLER_SLOT,
	SHADOW_SCENE_VIEWS,
	SHADOW_SCENE_SAMPLERS,
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
import { Vec3, vec3 } from "../math/math3d";
import { TargetLayout } from "../gpu/target";
import {
	PassState,
	passState,
	UNIFORM_SLOTS,
	contextGeneration,
	frameIndex,
	PixelFormat,
	makeCubeImage,
	makeTextureView,
	makeSampler,
	destroyImage,
	destroyView,
	destroySampler,
	originTopLeft,
} from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import { Environment, compute, isCurrent, specLevels } from "./environment";
import "../gpu/cubeTarget";
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
	uploadDirtyMeshes,
	reserveUniforms,
	writeUniforms,
	drawItem,
	validSkin,
	validRange,
	elementCount,
	SceneTexture,
	NO_SCENE_TEXTURE,
	slotBit,
} from "./draw";
import { UniformError, ownRange, disownRange } from "./uniformPool";
import {
	PassList, collect, filterFrustum, sortBackToFront, sortByLayer, sortByMaterial, drawPassList,
} from "./passList";
import { screenMesh, screenItem, makeScreenTriangle } from "./screenFx";
import { Mat4 } from "../math/math3d";
import { Frustum3D } from "./frustum";
import {
	DirShadowMap, ShadowKind, castsAll, drawShadows, carryShadows, sceneTexture,
} from "./dirShadowMap";
import { SpotShadowError, spotCaster, spotShadowView } from "./spotShadow";
import { CubeShadowError, cubeCaster, cubeShadowViews } from "./cubeShadow";
import {
	CameraView, CAMERA_EYE, CAMERA_NEAR, CAMERA_PROJECTION_X, CAMERA_PROJECTION_Y,
} from "./camera";
import { pickFor } from "./meshLod";
import { ClusterAssignment, ClusterConfig } from "./clusters";
import {
	ClusterFrame,
	ClusterFrameError,
	assignFrame,
	closeClusterFrame,
	clusterSampler,
	clustersView,
	indicesView,
	recordCountOf,
	recordsView,
	uploadFrame,
} from "./clusterFrame";

export interface Renderer {
	readonly context: DrawContext;
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
	toneMode: ToneMode;
	// The scene passes draw into an HDR target: scene programs write linear colour, and the
	// preset that set this exposes and encodes it in its own pass.
	linearOutput: boolean;
	// Forward's enabled outline draws opaque meshes with their normal MRT variants.
	normalMrt: boolean;
	frameValues: Vec<float32>;
	// The eye a pbr key's view vector starts from (setCameraPosition); a frame drawing a pbr key
	// without one is refused.
	cameraPosition: Vec3 | null;
	// The view the camera block was resolved from (setCameraView), which the frame's lights are
	// clustered in; a frame with a positioned light and no view is refused.
	cameraView: CameraView | null;
	clusters: ClusterFrame;
	// The light block as written: the caller's ambient and sun, then the clusters' fields.
	lightValues: Vec<float32>;
	// The last frame drew a material whose UV transform scrolls.
	readsTime: boolean;
	preset: Preset;
	// Per item of the frame, the key drawn for its material's.
	drawn: Vec<ProgramKey>;
	shadow: DirShadowMap | null;
	spotShadow: DirShadowMap | null;
	cubeShadow: DirShadowMap | null;
	// h3d.scene.pbr.Renderer's `env`: the image-based light of every pbr key (attachEnvironment).
	environment: Environment | null;
	// What a pbr key reads with no environment attached, made once per GPU context.
	blackCube: uint32;
	blackCubeView: uint32;
	blackCubeSampler: uint32;
	screenMesh: MeshId;
	// The GPU context the handles in play belong to; 0 before the first frame.
	generation: int32;
	// Something changed since the last frame (V6: the host skips frames that would draw the
	// same image).
	changed: boolean;
	prepared: boolean;
	preparedFrame: uint32;
	culledCount: int32;
	meshLodScale: float64;
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
	SkinPose,
	Instances,
	DrawRange,
	MeshLod,
	CameraPosition,
	MeshWrite,
	// The pixel-art preset's toon lights are points: a spot, rectangle or capsule slot has no
	// toon term there, and drawing it as a point would light the wrong place.
	ShapedLightPreset,
	// The light block's spot caster is no spot record of it, or makes no camera
	// (lightShape.ms perspectiveCamera).
	BadShadowSpot,
	// The light block names a spot caster and no spot map is attached (attachSpotShadow).
	SpotShadowUnattached,
	// The light block's cube caster is no point, rectangle or capsule record of it, or its range
	// does not reach past its near plane (cubeShadow.ms).
	BadCubeShadow,
	// The light block names a cube caster and no cube map is attached (attachCubeShadow).
	CubeShadowUnattached,
	// The frame has a positioned light and no view to cluster it in (setCameraView).
	ClusterViewUnset,
	// The camera block is not the view's viewProj: the lights would be clustered in another view.
	ClusterViewStale,
	// clusters.ms refused the view or a light (a zero-sized target, a light out of range).
	ClusterAssign,
	ClusterUpload,
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
		toneMode: ToneMode.Linear,
		linearOutput: false,
		normalMrt: false,
		frameValues: new Array(FRAME_UNIFORM_LENGTH),
		cameraPosition: null,
		cameraView: null,
		clusters: ClusterFrame.create(ClusterConfig.defaults()),
		lightValues: new Array(LIGHT_UNIFORM_LENGTH),
		readsTime: false,
		preset: preset,
		drawn: [],
		shadow: null,
		spotShadow: null,
		cubeShadow: null,
		environment: null,
		blackCube: 0,
		blackCubeView: 0,
		blackCubeSampler: 0,
		screenMesh: screen.value,
		generation: 0,
		changed: true,
		prepared: false,
		preparedFrame: 0,
		culledCount: 0,
		meshLodScale: 1.0,
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
	if (shadow !== null && shadow.kind != ShadowKind.Sun) {
		stopOnWrongShadow("attachShadow", shadow.kind);
	}
	renderer.shadow = shadow;
	renderer.sceneGlobals = shadowGlobals(renderer);
	renderer.changed = true;
}

export function attachSpotShadow(renderer: Renderer, shadow: DirShadowMap | null): void {
	if (renderer.closed) { stopOnClosed("attachSpotShadow"); }
	if (shadow !== null && shadow.context !== renderer.context) { stopOnForeignShadow(); }
	if (shadow !== null && shadow.isClosed()) { stopOnClosedShadow("attachSpotShadow"); }
	if (shadow !== null && shadow.kind != ShadowKind.Spot) {
		stopOnWrongShadow("attachSpotShadow", shadow.kind);
	}
	renderer.spotShadow = shadow;
	renderer.sceneGlobals = shadowGlobals(renderer);
	renderer.changed = true;
}

export function attachCubeShadow(renderer: Renderer, shadow: DirShadowMap | null): void {
	if (renderer.closed) { stopOnClosed("attachCubeShadow"); }
	if (shadow !== null && shadow.context !== renderer.context) { stopOnForeignShadow(); }
	if (shadow !== null && shadow.isClosed()) { stopOnClosedShadow("attachCubeShadow"); }
	if (shadow !== null && shadow.kind != ShadowKind.Cube) {
		stopOnWrongShadow("attachCubeShadow", shadow.kind);
	}
	renderer.cubeShadow = shadow;
	renderer.sceneGlobals = shadowGlobals(renderer);
	renderer.changed = true;
}

// The renderer bakes an environment that is not baked, or lost its bake to a new GPU context, at
// beginFrame, as Heaps' Environment remakes what was disposed.
export function attachEnvironment(renderer: Renderer, environment: Environment | null): void {
	if (renderer.closed) { stopOnClosed("attachEnvironment"); }
	if (environment !== null && environment.closed) {
		console.log("void3d: attachEnvironment with an environment that was closed");
		unreachable;
	}
	renderer.environment = environment;
	renderer.changed = true;
}

function makeBlackCube(renderer: Renderer): void {
	const black: uint32[] = [0, 0, 0, 0, 0, 0];
	renderer.blackCube = makeCubeImage(black, 1);
	renderer.blackCubeView = makeTextureView(renderer.blackCube);
	renderer.blackCubeSampler = makeSampler(FilterMode.Linear, Wrap.Clamp);
	if (renderer.blackCube == 0 || renderer.blackCubeView == 0 || renderer.blackCubeSampler == 0) {
		console.log(
			"void3d: the GPU refused the 1x1 black cube a pbr key reads without an environment",
		);
		unreachable;
	}
}

function writeEnvironment(renderer: Renderer): void {
	const environment: Environment | null = renderer.environment;
	if (environment === null) {
		renderer.frameValues[FRAME_ENV_POWER] = 0.0;
		renderer.frameValues[FRAME_ENV_LEVELS] = 0.0;
		renderer.frameValues[FRAME_ENV_COS] = 1.0;
		renderer.frameValues[FRAME_ENV_SIN] = 0.0;
		return;
	}
	renderer.frameValues[FRAME_ENV_POWER] = environment.power * environment.power;
	renderer.frameValues[FRAME_ENV_LEVELS] = environment.specLevels() as float32;
	renderer.frameValues[FRAME_ENV_COS] = Math.cos(environment.rotation as float64) as float32;
	renderer.frameValues[FRAME_ENV_SIN] = Math.sin(environment.rotation as float64) as float32;
}

function castError(error: ProgramError): RendererError {
	return error == ProgramError.BlockShort
		? RendererError.CasterBlock
		: RendererError.ProgramNotCast;
}

function stopOnWrongShadow(call: string, found: ShadowKind): void {
	console.log(`void3d: ${call} with a ${found.toString()} shadow map; DirShadowMap.create ` +
		"makes the sun's, createSpot the spot's and createCube the point's");
	unreachable;
}

// The map whose block reaches the programs: the first of the sun's, the spot's and the point's,
// with the others' parts carried in (dirShadowMap.ms carryShadows).
function shadowOwner(renderer: Renderer): DirShadowMap | null {
	const sun: DirShadowMap | null = renderer.shadow;
	if (sun !== null) { return sun; }
	const spot: DirShadowMap | null = renderer.spotShadow;
	if (spot !== null) { return spot; }
	return renderer.cubeShadow;
}

function shadowGlobals(renderer: Renderer): Vec<UniformBlock> {
	const owner: DirShadowMap | null = shadowOwner(renderer);
	if (owner !== null) {
		return [renderer.cameraBlock, renderer.lightBlock, renderer.frameBlock, owner.shadowBlock];
	}
	return [renderer.cameraBlock, renderer.lightBlock, renderer.frameBlock];
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

// h3d.scene.pbr.Renderer's `toneMode`, in ToneMapping's `mode` order: the curve the exposed
// colour goes through. Heaps defaults to Reinhard; void3d to Linear, which leaves every colour
// below 1 as it was (docs/VOID3D.md, tone curves).
export enum ToneMode {
	Linear,
	Reinhard,
	Filmic,
	Neutral,
}

export function setToneMode(renderer: Renderer, mode: ToneMode): void {
	if (renderer.closed) { stopOnClosed("setToneMode"); }
	renderer.toneMode = mode;
	renderer.changed = true;
}

export function setExposure(renderer: Renderer, stops: float32): void {
	if (renderer.closed) { stopOnClosed("setExposure"); }
	if (!Number.isFinite(stops)) {
		console.log(`void3d: setExposure with ${stops} stops; an exposure is a finite number`);
		unreachable;
	}
	renderer.exposure = stops;
	renderer.changed = true;
}

export function setCameraPosition(renderer: Renderer, eye: Vec3): void {
	if (renderer.closed) { stopOnClosed("setCameraPosition"); }
	if (!Number.isFinite(eye.x) || !Number.isFinite(eye.y) || !Number.isFinite(eye.z)) {
		console.log(
			`void3d: setCameraPosition with ${eye.x}, ${eye.y}, ${eye.z}; an eye is finite`,
		);
		unreachable;
	}
	renderer.cameraPosition = eye;
	renderer.changed = true;
}

export function setCameraView(renderer: Renderer, view: CameraView): void {
	if (renderer.closed) { stopOnClosed("setCameraView"); }
	renderer.cameraView = view;
	renderer.changed = true;
}

function viewMatches(view: CameraView, camera: Readonly<Span<float32>>): boolean {
	const m: Mat4 = view.viewProj;
	const values: Vec<float32> = [
		m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24,
		m.m31, m.m32, m.m33, m.m34, m.m41, m.m42, m.m43, m.m44,
	];
	for (let i = 0; i < 16; i++) {
		if (values[i] != camera[i]) { return false; }
	}
	return true;
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
	const spotShadow: DirShadowMap | null = renderer.spotShadow;
	const cubeShadow: DirShadowMap | null = renderer.cubeShadow;
	if (shadow !== null && shadow.isClosed()) { stopOnClosedShadow("beginFrame"); }
	if (spotShadow !== null && spotShadow.isClosed()) { stopOnClosedShadow("beginFrame"); }
	if (cubeShadow !== null && cubeShadow.isClosed()) { stopOnClosedShadow("beginFrame"); }
	const shadowed: boolean = shadow !== null || spotShadow !== null || cubeShadow !== null;
	for (const item of items) {
		if (!context.hasMesh(item.mesh)) { return Result.err(meshError(context, item.mesh)); }
		if (!item.validRange(context.logicalElementCount(item.mesh.index))) {
			return Result.err(RendererError.DrawRange);
		}
		if (!context.hasMaterial(item.material)) {
			return Result.err(materialError(context, item.material));
		}
		const material: int32 = item.material.index;
		const drawn: Result<ProgramKey, ProgramError> =
			drawnIn(context.materials[material].program, renderer.preset, shadowed,
				renderer.normalMrt && context.materials[material].phase == Phase.Opaque);
		if (!drawn.ok) { return Result.err(RendererError.ProgramNotDrawn); }
		if (drawn.value.pbr && renderer.cameraPosition === null) {
			return Result.err(RendererError.CameraPosition);
		}
		if (!item.validSkin(drawn.value)) { return Result.err(RendererError.SkinPose); }
		if (!item.validInstances(context, drawn.value)) {
			return Result.err(RendererError.Instances);
		}
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
		if (!cast.ok) { return Result.err(castError(cast.error)); }
	}
	if (spotShadow !== null) {
		const cast: Result<int32, ProgramError> = spotShadow.castsAll(items);
		if (!cast.ok) { return Result.err(castError(cast.error)); }
	}
	if (cubeShadow !== null) {
		const cast: Result<int32, ProgramError> = cubeShadow.castsAll(items);
		if (!cast.ok) { return Result.err(castError(cast.error)); }
	}
	if ((camera.length as int32) != renderer.cameraBlock.length) {
		return Result.err(RendererError.CameraBlockLength);
	}
	const lodEye: Vec3 = vec3(camera[CAMERA_EYE], camera[CAMERA_EYE + 1], camera[CAMERA_EYE + 2]);
	for (let i = 0; i < (items.length as int32); i++) {
		const pick = items[i].lod;
		if (pick === null) { continue; }
		if (!pick.pickFor(items[i].world, lodEye, camera[CAMERA_PROJECTION_X],
			camera[CAMERA_PROJECTION_Y], camera[CAMERA_NEAR], renderer.meshLodScale).ok) {
			return Result.err(RendererError.MeshLod);
		}
	}
	const counted: Result<int32, ClusterFrameError> = recordCountOf(lights);
	if (!counted.ok) { return Result.err(RendererError.LightBlockLength); }
	const records: int32 = counted.value;
	if (renderer.preset == Preset.PixelArt) {
		for (let i = 0; i < records; i++) {
			const record: int32 = LIGHT_UNIFORM_LENGTH + i * LIGHT_RECORD_LENGTH;
			const kind: int32 = record + LIGHT_RECORD_SHAPE + 3;
			if (lights[kind] != 0.0) { return Result.err(RendererError.ShapedLightPreset); }
		}
	}
	const spotCast: Result<int32, SpotShadowError> = spotCaster(lights);
	if (!spotCast.ok) { return Result.err(RendererError.BadShadowSpot); }
	const shadowedSpot: int32 = spotCast.value;
	if (shadowedSpot >= 0 && !spotShadowView(lights, shadowedSpot).ok) {
		return Result.err(RendererError.BadShadowSpot);
	}
	if (shadowedSpot >= 0 && spotShadow === null) {
		return Result.err(RendererError.SpotShadowUnattached);
	}
	const cubeCast: Result<int32, CubeShadowError> = cubeCaster(lights);
	if (!cubeCast.ok) { return Result.err(RendererError.BadCubeShadow); }
	const shadowedCube: int32 = cubeCast.value;
	if (shadowedCube >= 0 && !cubeShadowViews(lights, shadowedCube).ok) {
		return Result.err(RendererError.BadCubeShadow);
	}
	if (shadowedCube >= 0 && cubeShadow === null) {
		return Result.err(RendererError.CubeShadowUnattached);
	}
	const view: CameraView | null = renderer.cameraView;
	if (records > 0 && view === null) { return Result.err(RendererError.ClusterViewUnset); }
	if (records > 0 && view !== null && !viewMatches(view, camera)) {
		return Result.err(RendererError.ClusterViewStale);
	}
	const cameraWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.cameraBlock, camera);
	if (!cameraWritten.ok) { return Result.err(RendererError.CameraBlockLength); }
	for (let i = 0; i < LIGHT_CLUSTER_GRID; i++) { renderer.lightValues[i] = lights[i]; }
	const assigned: Result<ClusterAssignment, ClusterFrameError> = renderer.clusters.assignFrame(
		lights, view, !originTopLeft(), renderer.lightValues);
	if (!assigned.ok) { return Result.err(RendererError.ClusterAssign); }
	const lightsWritten: Result<int32, UniformError> =
		writeUniforms(context, renderer.lightBlock, renderer.lightValues);
	if (!lightsWritten.ok) { return Result.err(RendererError.LightBlockLength); }
	renderer.time = renderer.time + renderer.elapsedTime;
	renderer.frameValues[FRAME_TIME] = frameTime(renderer.time, renderer.timeWrap);
	renderer.frameValues[FRAME_EXPOSURE] = exposureMultiplier(renderer.exposure);
	renderer.frameValues[FRAME_LINEAR] = renderer.linearOutput ? 1.0 : 0.0;
	renderer.frameValues[FRAME_TONE_MODE] = renderer.toneMode as float32;
	const eye: Vec3 | null = renderer.cameraPosition;
	if (eye !== null) {
		renderer.frameValues[FRAME_CAMERA_POSITION] = eye.x;
		renderer.frameValues[FRAME_CAMERA_POSITION + 1] = eye.y;
		renderer.frameValues[FRAME_CAMERA_POSITION + 2] = eye.z;
	}
	writeEnvironment(renderer);
	if (!writeUniforms(context, renderer.frameBlock, renderer.frameValues).ok) { unreachable; }
	while ((renderer.drawn.length as int32) < (items.length as int32)) {
		renderer.drawn.push(ProgramKey.of(Program.Lit));
	}
	let readsTime: boolean = false;
	for (let i = 0; i < (items.length as int32); i++) {
		const resolved: Result<ProgramKey, ProgramError> =
			drawnIn(context.materials[items[i].material.index].program, renderer.preset, shadowed,
				renderer.normalMrt &&
					context.materials[items[i].material.index].phase == Phase.Opaque);
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
		makeBlackCube(renderer);
		renderer.generation = generation;
		renderer.changed = true;
	}
	if (!uploadDirtyMeshes(context).ok) { return Result.err(RendererError.MeshWrite); }
	if (!renderer.clusters.uploadFrame(lights, assigned.value).ok) {
		return Result.err(RendererError.ClusterUpload);
	}
	const environment: Environment | null = renderer.environment;
	if (environment !== null && !environment.isCurrent()) { environment.compute(); }
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
	sortByMaterial(renderer.opaque, items, renderer.drawn, context.materials);
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
	const spotShadow: DirShadowMap | null = renderer.spotShadow;
	const cubeShadow: DirShadowMap | null = renderer.cubeShadow;
	let casters: int32 = 0;
	if (shadow !== null) { casters = drawShadows(shadow, items, camera, lights); }
	if (spotShadow !== null) { casters = casters + drawShadows(spotShadow, items, camera, lights); }
	if (cubeShadow !== null) {
		casters = casters + drawShadows(cubeShadow, items, camera, lights);
	}
	const owner: DirShadowMap | null = shadowOwner(renderer);
	if (owner !== null) { carryShadows(owner, spotShadow, cubeShadow); }
	return casters;
}

// A frame without one of the maps binds another in its slot: the absent light's part of the
// block is zero, so its lookup answers lit before it reads the map.
function sceneTextureOf(renderer: Renderer): SceneTexture {
	const clusters: ClusterFrame = renderer.clusters;
	const shadows: SceneTexture = {
		...shadowTextureOf(renderer),
		lightRecords: clusters.recordsView(),
		clusterRecords: clusters.clustersView(),
		clusterIndices: clusters.indicesView(),
		clusterSampler: clusters.clusterSampler(),
	};
	const environment: Environment | null = renderer.environment;
	if (environment === null) {
		return {
			...shadows,
			envDiffuse: renderer.blackCubeView,
			envSpecular: renderer.blackCubeView,
			envSampler: renderer.blackCubeSampler,
		};
	}
	return {
		...shadows,
		envDiffuse: environment.diffuse.asTexture(),
		envSpecular: environment.specular.asTexture(),
		envSampler: environment.sampler,
	};
}

function shadowTextureOf(renderer: Renderer): SceneTexture {
	const owner: DirShadowMap | null = shadowOwner(renderer);
	if (owner === null) { return NO_SCENE_TEXTURE; }
	const first: SceneTexture = owner.sceneTexture();
	const shadow: DirShadowMap | null = renderer.shadow;
	const spotShadow: DirShadowMap | null = renderer.spotShadow;
	const cubeShadow: DirShadowMap | null = renderer.cubeShadow;
	const sun: SceneTexture = shadow === null ? first : shadow.sceneTexture();
	const spot: SceneTexture = spotShadow === null ? first : spotShadow.sceneTexture();
	const point: SceneTexture = cubeShadow === null ? first : cubeShadow.sceneTexture();
	return {
		view: sun.view, sampler: sun.sampler, spotView: spot.view, spotSampler: spot.sampler,
		cubeView: point.view,
	};
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

// Scene programs write linear colour exactly when the core's linearOutput says so, and only an
// Rgba16f target holds it; any other pairing shows wrong colours with no error.
function stopOnColourSpace(renderer: Renderer, targets: TargetLayout): void {
	const written: string = renderer.linearOutput ? "linear" : "encoded";
	console.log(`void3d: drawPhase writes ${written} colour into a ${targets.color0.toString()} ` +
		"target; linear colour goes into Rgba16f only, through an HDR preset");
	unreachable;
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
	if ((targets.color0 == PixelFormat.Rgba16f) != renderer.linearOutput) {
		stopOnColourSpace(renderer, targets);
	}
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
	if (!key.uvTransform && !key.pbr) { return false; }
	const block: UniformBlock = context.materials[index].uniforms;
	const scroll: int32 = key.pbr ? PBR_UV_SCROLL : movingBase(key) + MOVING_UV_SCROLL;
	const at: int32 = block.offset + scroll;
	return context.uniforms.values[at] != 0.0 || context.uniforms.values[at + 1] != 0.0;
}

// The one block a material brings for `program`: the slot it declares that is neither pass-wide
// nor the skin pose, at the length its shader declares; none when it declares no such slot.
function blockFits(program: ProgramKey, block: UniformBlock): boolean {
	let own: int32 = -1;
	for (let slot = 0; slot < UNIFORM_SLOTS; slot++) {
		const passWide: boolean = slot == VERTEX_UNIFORM_SLOT || slot == LIGHT_UNIFORM_SLOT ||
			slot == SHADOW_UNIFORM_SLOT || slot == FRAME_UNIFORM_SLOT;
		if (passWide || slot == SKIN_UNIFORM_SLOT ||
			uniformBlockLength(program, slot) == 0) {
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
// a shadowed program, and the clustered lights' for every program.
function texturesFit(program: ProgramKey, material: Material): boolean {
	const sceneViews: uint32 = CLUSTER_SCENE_VIEWS |
		(program.shadowed ? SHADOW_SCENE_VIEWS : 0) | (program.pbr ? ENV_SCENE_VIEWS : 0);
	const sceneSamplers: uint32 = CLUSTER_SCENE_SAMPLERS |
		(program.shadowed ? SHADOW_SCENE_SAMPLERS : 0) | (program.pbr ? ENV_SCENE_SAMPLERS : 0);
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
	if (renderer.blackCube != 0 && renderer.generation == contextGeneration()) {
		destroyView(renderer.blackCubeView);
		destroyImage(renderer.blackCube);
		destroySampler(renderer.blackCubeSampler);
	}
	renderer.blackCube = 0;
	renderer.blackCubeView = 0;
	renderer.blackCubeSampler = 0;
	closeClusterFrame(renderer.clusters);
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
