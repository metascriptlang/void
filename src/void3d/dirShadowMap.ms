// Port of h3d.pass.DirShadowMap as h3d.pass.DefaultShadowMap uses it (Dynamic mode, autoShrink,
// SAMPLING_NONE): a depth-only pass from the directional light into a square target the caller
// sizes, which every shadowed lit program samples (shader3dBlocks.glsl dirShadow).

import { Vec3, Mat4, vec3, identity } from "../math/math3d";
import {
	Program,
	ProgramKey,
	ProgramError,
	castIn,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	SHADOW_UNIFORM_SLOT,
	SHADOW_UNIFORM_LENGTH,
	SHADOW_BIAS,
	SHADOW_OPACITY,
} from "./gpu3d";
import {
	PixelFormat,
	LoadAction,
	StoreAction,
	PassState,
	endPass,
	passState,
	originTopLeft,
	depthZeroToOne,
} from "../gpu/door";
import { FilterMode, Wrap, RenderState } from "../gpu/state";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	Sampler,
	beginPass,
} from "../gpu/target";
import { Material, UniformBlock, Phase, ShadowCasting, shadowFace } from "./material";
import {
	DrawContext,
	DrawItem,
	SceneTexture,
	NO_SCENE_TEXTURE,
	reserveUniforms,
	writeUniforms,
	drawItemWith,
} from "./draw";
import { UniformError, ownRange, disownRange } from "./uniformPool";
import { PassList, collectCasters, filterFrustum } from "./passList";
import { Bounds3D, addPos, addBounds } from "./bounds";
import { Frustum3D } from "./frustum";
import { CameraBasis, OrthoBounds } from "./camera";

export interface DirShadowMap {
	context: DrawContext;
	// opacity is Godot's shadow_opacity; Heaps' DefaultShadowMap tints by a colour instead.
	size: int32;
	bias: float32;
	opacity: float32;
	depthTarget: RenderTarget;
	sampler: Sampler;
	casters: PassList;
	cast: Vec<ProgramKey>;
	cameraBlock: UniformBlock;
	shadowBlock: UniformBlock;
	cameraValues: Vec<float32>;
	shadowValues: Vec<float32>;
	globals: Vec<UniformBlock>;
	viewProj: Mat4;
	casterCount: int32;
	closed: boolean;
}

export enum ShadowError {
	UniformPoolFull,
	Size,
}

export const DIR_SHADOW_UNIFORM_LENGTH: int32 = VERTEX_UNIFORM_LENGTH + SHADOW_UNIFORM_LENGTH;

// Heaps' Shadows.bias default, in [0, 1] map depth.
export const DEFAULT_SHADOW_BIAS: float32 = 0.01;

export const SHADOW_LAYOUT: TargetLayout = {
	color0: PixelFormat.None,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.Depth,
	sampleCount: 1,
};

const FAR_DEPTH: float32 = 1.0;
// DirShadowMap.calcShadowBounds widens the box by 1% (bounds.scaleCenter(1.01)).
const BOUNDS_SCALE: float32 = 1.01;
// A flat caster facing the light has no depth extent, and projectionMatrix divides by it.
const MIN_EXTENT: float32 = 0.001;
const NO_COLORS: Vec<ColorAttachment> = [];

function reserveOwned(context: DrawContext, slot: int32, length: int32): UniformBlock {
	const reserved: Result<UniformBlock, UniformError> = reserveUniforms(context, slot, length);
	if (!reserved.ok) { unreachable; }
	if (!ownRange(context.uniforms, reserved.value).ok) { unreachable; }
	return reserved.value;
}

export function create(
	this typeof DirShadowMap,
	context: DrawContext,
	size: int32,
): Result<DirShadowMap, ShadowError> {
	context.requireOpen("DirShadowMap.create");
	if (size <= 0) { return Result.err(ShadowError.Size); }
	const blocks: Vec<int32> = [VERTEX_UNIFORM_LENGTH, SHADOW_UNIFORM_LENGTH];
	if (!context.uniforms.fits(blocks).ok) { return Result.err(ShadowError.UniformPoolFull); }
	const cameraBlock: UniformBlock =
		reserveOwned(context, VERTEX_UNIFORM_SLOT, VERTEX_UNIFORM_LENGTH);
	const shadowBlock: UniformBlock =
		reserveOwned(context, SHADOW_UNIFORM_SLOT, SHADOW_UNIFORM_LENGTH);
	let cameraValues: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	for (let i = 0; i < VERTEX_UNIFORM_LENGTH; i++) { cameraValues[i] = 0.0; }
	let shadowValues: Vec<float32> = new Array(SHADOW_UNIFORM_LENGTH);
	for (let i = 0; i < SHADOW_UNIFORM_LENGTH; i++) { shadowValues[i] = 0.0; }
	return Result.ok({
		context: context,
		size: size,
		bias: DEFAULT_SHADOW_BIAS,
		opacity: 1.0,
		depthTarget: RenderTarget.unallocated(PixelFormat.Depth, true),
		sampler: { filter: FilterMode.Nearest, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		casters: PassList.forPhase(Phase.Opaque),
		cast: [],
		cameraBlock: cameraBlock,
		shadowBlock: shadowBlock,
		cameraValues: cameraValues,
		shadowValues: shadowValues,
		globals: [cameraBlock],
		viewProj: identity(),
		casterCount: 0,
		closed: false,
	});
}

export function castsAll(
	this shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
): Result<int32, ProgramError> {
	if (shadow.closed) { stopOnClosed("castsAll"); }
	const context: DrawContext = shadow.context;
	while ((shadow.cast.length as int32) < (items.length as int32)) {
		shadow.cast.push(ProgramKey.of(Program.Lit));
	}
	let count: int32 = 0;
	for (let i = 0; i < (items.length as int32); i++) {
		const material: Material = context.materials[items[i].material.index];
		if (material.castShadows == ShadowCasting.Off) { continue; }
		const key: Result<ProgramKey, ProgramError> = castIn(material.program);
		if (!key.ok) { return Result.err(key.error); }
		shadow.cast[i] = key.value;
		count = count + 1;
	}
	return Result.ok(count);
}

// The light block holds the direction toward the light (scene.ms collectLights).
export function lightBasis(toLight: Vec3): CameraBasis {
	const length: float32 = toLight.length();
	const forward: Vec3 =
		length > 0.0 ? vec3(0.0, 0.0, 0.0) - toLight.normalized() : vec3(0.0, -1.0, 0.0);
	const reference: Vec3 = forward.y > 0.99 || forward.y < -0.99 ?
		vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	const right: Vec3 = forward.cross(reference).normalized();
	return { right: right, up: right.cross(forward), forward: forward };
}

struct Extent {
	min: float32;
	max: float32;
}

function widened(min: float32, max: float32, scale: float32): Extent {
	const center: float32 = (min + max) * 0.5;
	let half: float32 = (max - min) * 0.5 * scale;
	if (half < MIN_EXTENT * 0.5) { half = MIN_EXTENT * 0.5; }
	return { min: center - half, max: center + half };
}

// calcShadowBounds, Dynamic mode with autoShrink: the casters' near side is kept so a caster
// outside the view still shades what is in it.
export function shadowBounds(
	basis: CameraBasis,
	casters: Bounds3D,
	cameraInverse: Mat4,
): Bounds3D {
	if (casters.isEmpty()) { return casters; }
	let view: Bounds3D = Bounds3D.empty();
	for (let corner = 0; corner < 8; corner++) {
		const ndc: Vec3 = vec3(
			(corner & 1) == 0 ? -1.0 : 1.0,
			(corner & 2) == 0 ? -1.0 : 1.0,
			(corner & 4) == 0 ? 0.0 : 1.0,
		);
		const world: Vec3 = ndc.project(cameraInverse);
		addPos(view, world.dot(basis.right), world.dot(basis.up), world.dot(basis.forward));
	}
	const minX: float32 = casters.min.x > view.min.x ? casters.min.x : view.min.x;
	const maxX: float32 = casters.max.x < view.max.x ? casters.max.x : view.max.x;
	const minY: float32 = casters.min.y > view.min.y ? casters.min.y : view.min.y;
	const maxY: float32 = casters.max.y < view.max.y ? casters.max.y : view.max.y;
	const maxZ: float32 = casters.max.z < view.max.z ? casters.max.z : view.max.z;
	if (minX > maxX || minY > maxY || casters.min.z > maxZ) { return Bounds3D.empty(); }
	const x: Extent = widened(minX, maxX, BOUNDS_SCALE);
	const y: Extent = widened(minY, maxY, BOUNDS_SCALE);
	const z: Extent = widened(casters.min.z, maxZ, BOUNDS_SCALE);
	return Bounds3D.fromPoints(vec3(x.min, y.min, z.min), vec3(x.max, y.max, z.max));
}

function casterBounds(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	basis: CameraBasis,
): Bounds3D {
	const context: DrawContext = shadow.context;
	const toLight: Mat4 = basis.makeCameraMatrix(vec3(0.0, 0.0, 0.0));
	let bounds: Bounds3D = Bounds3D.empty();
	for (let i = 0; i < shadow.casters.count; i++) {
		const item: DrawItem = items[shadow.casters.indices[i]];
		const local: Bounds3D = context.meshData[item.mesh.index].bounds;
		if (local.isEmpty()) { continue; }
		addBounds(bounds, local.transformed(item.world * toLight));
	}
	return bounds;
}

// NDC to the map: x and y to texel space in the target's row order (row 0 is the top on D3D11
// and Metal, the bottom on GL), z to the depth the backend stores ((z + 1) / 2 on GL).
function mapMatrix(): Mat4 {
	const rows: float32 = originTopLeft() ? -0.5 : 0.5;
	const depth: float32 = depthZeroToOne() ? 1.0 : 0.5;
	return {
		m11: 0.5, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: rows, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: depth, m34: 0.0,
		m41: 0.5, m42: 0.5, m43: 1.0 - depth, m44: 1.0,
	};
}

function stopOnPassOpen(): void {
	console.log("void3d: the shadow pass with a pass already open; it would nest inside it");
	unreachable;
}

// DirShadowMap.draw.
export function drawShadows(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
): int32 {
	if (shadow.closed) { stopOnClosed("drawShadows"); }
	if (passState() != PassState.None) { stopOnPassOpen(); }
	const context: DrawContext = shadow.context;
	const basis: CameraBasis = lightBasis(vec3(lights[4], lights[5], lights[6]));
	const cameraViewProj: Mat4 = {
		m11: camera[0], m12: camera[1], m13: camera[2], m14: camera[3],
		m21: camera[4], m22: camera[5], m23: camera[6], m24: camera[7],
		m31: camera[8], m32: camera[9], m33: camera[10], m34: camera[11],
		m41: camera[12], m42: camera[13], m43: camera[14], m44: camera[15],
	};
	collectCasters(shadow.casters, items, context.materials);
	const bounds: Bounds3D =
		shadowBounds(basis, casterBounds(shadow, items, basis), cameraViewProj.inverse());
	let box: OrthoBounds = { minX: -1.0, maxX: 1.0, minY: -1.0, maxY: 1.0, minZ: 0.0, maxZ: 1.0 };
	if (!bounds.isEmpty()) {
		box = {
			minX: bounds.min.x, maxX: bounds.max.x,
			minY: bounds.min.y, maxY: bounds.max.y,
			minZ: bounds.min.z, maxZ: bounds.max.z,
		};
	} else {
		shadow.casters.count = 0;
	}
	shadow.viewProj = basis.makeCameraMatrix(vec3(0.0, 0.0, 0.0)) * box.projectionMatrix();
	if (shadow.casters.count > 0) {
		const _culled: int32 = filterFrustum(
			shadow.casters, items, context.meshData, Frustum3D.fromMatrix(shadow.viewProj),
		);
	}
	shadow.viewProj.writeTo(shadow.cameraValues[0..16], 0);
	shadow.cameraValues[16] = basis.right.x;
	shadow.cameraValues[17] = basis.right.y;
	shadow.cameraValues[18] = basis.right.z;
	shadow.cameraValues[20] = basis.up.x;
	shadow.cameraValues[21] = basis.up.y;
	shadow.cameraValues[22] = basis.up.z;
	const map: Mat4 = mapMatrix();
	(shadow.viewProj * map).writeTo(shadow.shadowValues[0..16], 0);
	shadow.shadowValues[SHADOW_BIAS] = shadow.bias * map.m33;
	shadow.shadowValues[SHADOW_OPACITY] = shadow.opacity;
	const cameraWritten: Result<int32, UniformError> =
		writeUniforms(context, shadow.cameraBlock, shadow.cameraValues);
	const shadowWritten: Result<int32, UniformError> =
		writeUniforms(context, shadow.shadowBlock, shadow.shadowValues);
	if (!cameraWritten.ok || !shadowWritten.ok) { stopOnLostBlocks(); }

	shadow.depthTarget.resize(shadow.size, shadow.size);
	if (shadow.sampler.handle == 0 || shadow.sampler.generation != shadow.depthTarget.generation) {
		shadow.sampler = Sampler.create(shadow.sampler.filter, shadow.sampler.wrap);
	}
	beginPass(
		NO_COLORS, shadow.depthTarget.asDepth(LoadAction.Clear, FAR_DEPTH, StoreAction.Store),
	);
	for (let i = 0; i < shadow.casters.count; i++) {
		const index: int32 = shadow.casters.indices[i];
		const material: Material = context.materials[items[index].material.index];
		const state: RenderState = RenderState.defaults().withCulling(material.shadowFace());
		drawItemWith(
			context, items[index], shadow.cast[index], state, SHADOW_LAYOUT, shadow.globals,
			NO_SCENE_TEXTURE,
		);
	}
	endPass();
	shadow.casterCount = shadow.casters.count;
	return shadow.casters.count;
}

export function sceneTexture(this shadow: DirShadowMap): SceneTexture {
	if (shadow.closed) { stopOnClosed("sceneTexture"); }
	return { view: shadow.depthTarget.asTexture(), sampler: shadow.sampler.asHandle() };
}

function stopOnLostBlocks(): void {
	console.log("void3d: drawShadows found its uniform blocks given back");
	unreachable;
}

export function closeDirShadow(shadow: DirShadowMap): void {
	if (shadow.closed) { stopOnClosed("closeDirShadow"); }
	if (passState() != PassState.None) {
		console.log("void3d: closeDirShadow with a pass open; endPass ends it");
		unreachable;
	}
	shadow.depthTarget.close();
	shadow.sampler = shadow.sampler.released();
	const camera: Result<int32, UniformError> =
		disownRange(shadow.context.uniforms, shadow.cameraBlock);
	const block: Result<int32, UniformError> =
		disownRange(shadow.context.uniforms, shadow.shadowBlock);
	if (!camera.ok || !block.ok) { stopOnLostBlocks(); }
	shadow.closed = true;
}

export function isClosed(this shadow: DirShadowMap): boolean {
	return shadow.closed;
}

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a shadow map that was closed`);
	unreachable;
}
