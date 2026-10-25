// Port of h3d.pass.DirShadowMap as h3d.pass.DefaultShadowMap uses it (Dynamic mode, autoShrink,
// SAMPLING_NONE): a depth-only pass from the directional light into a square target the caller
// sizes, which every shadowed lit program samples (shader3d.ms dirShadowAt). The same map, made
// with createSpot, is h3d.pass.SpotShadowMap's: the shadowing spot's own map and shadow block half
// (shader3d.ms spotShadowAt), and with createCube h3d.pass.PointShadowMap's, one layer per cube
// face (shader3d.ms cubeShadowAt).

import { Vec3, Mat4, vec3, identity } from "../math/math3d";
import {
	Program,
	ProgramKey,
	ProgramError,
	castIn,
	uniformBlockLength,
	VERTEX_UNIFORM_SLOT,
	VERTEX_UNIFORM_LENGTH,
	SHADOW_UNIFORM_SLOT,
	SHADOW_UNIFORM_LENGTH,
	SHADOW_CASCADE_FAR,
	SHADOW_CASCADE_INFO,
	SHADOW_CASCADE_VIEW,
	SHADOW_CASCADE_FILTER,
	SHADOW_CASCADE_NORMAL_BIAS,
	SHADOW_CUBE_NORMAL_BIAS,
	SHADOW_SPOT_BASE,
	SHADOW_SPOT_BIAS,
	SHADOW_SPOT_OPACITY,
	SHADOW_SPOT_FILTER,
	SHADOW_SPOT_NORMAL_BIAS,
	SHADOW_SPOT_POSITION,
	SHADOW_CUBE_BASE,
	SHADOW_CUBE_FACES,
	SHADOW_CUBE_BIAS,
	SHADOW_CUBE_OPACITY,
	SHADOW_CUBE_FILTER,
	SHADOW_CUBE_POSITION,
	SHADOW_CUBE_RANGE,
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
	ColorAttachment,
	TargetLayout,
	Sampler,
	beginPass,
} from "../gpu/target";
import { ArrayTarget } from "../gpu/arrayTarget";
import { Material, UniformBlock, Phase, ShadowCasting, shadowFace } from "./material";
import {
	DrawContext,
	DrawItem,
	SceneTexture,
	NO_SCENE_TEXTURE,
	reserveUniforms,
	writeUniforms,
	drawBatchWith,
	drawItemWith,
} from "./draw";
import { UniformError, ownRange, disownRange } from "./uniformPool";
import { PassList, collectCasters, filterFrustum } from "./passList";
import { Bounds3D, addPos, addBounds } from "./bounds";
import { Frustum3D } from "./frustum";
import { CameraBasis, CameraView, OrthoBounds } from "./camera";
import { SpotShadowError, spotCaster, spotShadowView } from "./spotShadow";
import {
	CubeShadowError, cubeCaster, cubeShadowViews, cubePosition, cubeNear, cubeRange,
} from "./cubeShadow";
import {
	Cascade, CascadeConfig, CascadeError, MAX_CASCADES, cascadesOf, viewForward,
} from "./cascades";

export enum ShadowKind {
	Sun,
	Spot,
	Cube,
}

// h3d.pass.Shadows' samplingKind without ESM, which reads a blurred float map this depth map
// is not.
export enum ShadowSamplingKind {
	None,
	Pcf,
}

export interface DirShadowMap {
	context: DrawContext;
	// opacity is Godot's shadow_opacity; Heaps' DefaultShadowMap tints by a colour instead.
	size: int32;
	kind: ShadowKind;
	bias: float32;
	normalBias: float32;
	opacity: float32;
	samplingKind: ShadowSamplingKind;
	// In texels; Heaps' pcfScale is the same number, divided by the map's width in the shader.
	pcfScale: float32;
	// Bevy's CascadeShadowConfig for the sun; null keeps one map fitted to the casters in view.
	cascades: CascadeConfig | null;
	depthTarget: ArrayTarget;
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

const TEXEL_DIAGONAL: float32 = Math.SQRT2 as float32;

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
const NO_MAP: Mat4 = {
	m11: 0.0, m12: 0.0, m13: 0.0, m14: 0.0,
	m21: 0.0, m22: 0.0, m23: 0.0, m24: 0.0,
	m31: 0.0, m32: 0.0, m33: 0.0, m34: 0.0,
	m41: 0.0, m42: 0.0, m43: 0.0, m44: 0.0,
};

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
	return buildMap(context, size, ShadowKind.Sun);
}

export function createSpot(
	this typeof DirShadowMap,
	context: DrawContext,
	size: int32,
): Result<DirShadowMap, ShadowError> {
	return buildMap(context, size, ShadowKind.Spot);
}

export function createCube(
	this typeof DirShadowMap,
	context: DrawContext,
	size: int32,
): Result<DirShadowMap, ShadowError> {
	return buildMap(context, size, ShadowKind.Cube);
}

function buildMap(
	context: DrawContext, size: int32, kind: ShadowKind,
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
		kind: kind,
		bias: DEFAULT_SHADOW_BIAS,
		normalBias: 0.0,
		opacity: 1.0,
		samplingKind: ShadowSamplingKind.None,
		pcfScale: 1.0,
		cascades: null,
		depthTarget: ArrayTarget.unallocated(size, 1, PixelFormat.Depth),
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
		const block: UniformBlock = material.uniforms;
		if (block.length > 0 && block.length < uniformBlockLength(key.value, block.slot)) {
			return Result.err(ProgramError.BlockShort);
		}
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
		const item: Readonly<DrawItem> = items[shadow.casters.indices[i]];
		const geometry = item.skinGeometry;
		if (geometry !== null) {
			if (!geometry.mesh.bounds.isEmpty()) {
				addBounds(bounds, geometry.mesh.bounds.transformed(toLight));
			}
		} else {
			const local: Bounds3D = context.meshData[item.mesh.index].bounds;
			if (local.isEmpty()) { continue; }
			addBounds(bounds, local.transformed(item.world * toLight));
		}
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

// The sun's cascades: each layer's clip-from-world and far bound in view depth.
export struct SunLayers {
	clips: Vec<Mat4>;
	far: Vec<float32>;
}

// Past every view depth, so one map covers the whole view.
const ALL_DEPTHS: float32 = 3.0e38;

// Uses Bevy's cascades (setCascades) on the sun, each its own layer; the spot draws one layer and
// the point one per face.
export function setCascades(
	this shadow: DirShadowMap,
	config: CascadeConfig | null,
): Result<int32, CascadeError> {
	if (shadow.closed) { stopOnClosed("setCascades"); }
	if (shadow.kind != ShadowKind.Sun && config !== null) {
		console.log(`void3d: setCascades on a ${shadow.kind.toString()} map: no cascades`);
		unreachable;
	}
	if (config === null) {
		shadow.cascades = null;
		return Result.ok(1);
	}
	const count: int32 = try config.validate();
	shadow.cascades = config;
	return Result.ok(count);
}

// DirShadowMap.draw, or SpotShadowMap.draw (SpotShadowMap.hx:107-171) for a map made with
// createSpot: the shadowing spot's perspective view-projection, or a cleared map with no shadow
// when no spot of the light block casts.
export function drawShadows(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	camera: Readonly<Span<float32>>,
	lights: Readonly<Span<float32>>,
): int32 {
	if (shadow.closed) { stopOnClosed("drawShadows"); }
	if (passState() != PassState.None) { stopOnPassOpen(); }
	if (shadow.kind == ShadowKind.Spot) { return drawSpotShadows(shadow, items, lights); }
	if (shadow.kind == ShadowKind.Cube) { return drawCubeShadows(shadow, items, lights); }
	const context: DrawContext = shadow.context;
	const basis: CameraBasis = lightBasis(vec3(lights[4], lights[5], lights[6]));
	const cameraViewProj: Mat4 = {
		m11: camera[0], m12: camera[1], m13: camera[2], m14: camera[3],
		m21: camera[4], m22: camera[5], m23: camera[6], m24: camera[7],
		m31: camera[8], m32: camera[9], m33: camera[10], m34: camera[11],
		m41: camera[12], m42: camera[13], m43: camera[14], m44: camera[15],
	};
	const cameraInverse: Mat4 = cameraViewProj.inverse();
	collectCasters(shadow.casters, items, context.materials);
	const casters: Bounds3D = casterBounds(shadow, items, basis);
	const layers: SunLayers = sunLayers(shadow, casters, basis, cameraInverse,
		vec3(camera[24], camera[25], camera[26]));
	shadow.viewProj = layers.clips[0];
	shadow.packSun(layers, mapMatrix(), viewForward(cameraInverse));
	let bases: Vec<CameraBasis> = [];
	for (const _clip of layers.clips) { bases.push(basis); }
	return drawLayers(shadow, items, bases, layers.clips);
}

// The sun's part of the block: each layer's clip taken on to the map by `map`, its far bound,
// the count, the overlap, the bias in map depth, the opacity, the view's forward axis, the size.
export function packSun(
	this shadow: DirShadowMap,
	layers: SunLayers,
	map: Mat4,
	forward: Vec3,
): void {
	if (shadow.closed) { stopOnClosed("packSun"); }
	const count: int32 = layers.clips.length as int32;
	if (count < 1 || count > MAX_CASCADES || (layers.far.length as int32) != count) {
		console.log(`void3d: packSun with ${count} clips and ${layers.far.length} far bounds`);
		unreachable;
	}
	for (let i = 0; i < MAX_CASCADES; i++) {
		const clip: Mat4 = i < count ? layers.clips[i] * map : NO_MAP;
		clip.writeTo(shadow.shadowValues[i * 16..i * 16 + 16], 0);
		shadow.shadowValues[SHADOW_CASCADE_FAR + i] = i < count ? layers.far[i] : 0.0;
	}
	const config: CascadeConfig | null = shadow.cascades;
	shadow.shadowValues[SHADOW_CASCADE_INFO] = count as float32;
	shadow.shadowValues[SHADOW_CASCADE_INFO + 1] = config === null ? 0.0 : config.overlap;
	shadow.shadowValues[SHADOW_CASCADE_INFO + 2] = shadow.bias * map.m33;
	shadow.shadowValues[SHADOW_CASCADE_INFO + 3] = shadow.opacity;
	shadow.shadowValues[SHADOW_CASCADE_VIEW] = forward.x;
	shadow.shadowValues[SHADOW_CASCADE_VIEW + 1] = forward.y;
	shadow.shadowValues[SHADOW_CASCADE_VIEW + 2] = forward.z;
	shadow.shadowValues[SHADOW_CASCADE_VIEW + 3] = shadow.size as float32;
	shadow.shadowValues[SHADOW_CASCADE_FILTER] = filterScaleOf(shadow);
	shadow.shadowValues[SHADOW_CASCADE_NORMAL_BIAS] = shadow.normalBias * TEXEL_DIAGONAL;
}

// The PCF scale a part of the block carries: 0 reads one texel.
function filterScaleOf(shadow: DirShadowMap): float32 {
	if (shadow.samplingKind == ShadowSamplingKind.None) { return 0.0; }
	if (!(shadow.pcfScale > 0.0) || !Number.isFinite(shadow.pcfScale)) {
		console.log(`void3d: a Pcf shadow map with pcfScale ${shadow.pcfScale}; it must be ` +
			"a positive number of texels");
		unreachable;
	}
	return shadow.pcfScale;
}

// One layer fitted to the casters in view (calcShadowBounds), or one per cascade.
function sunLayers(
	shadow: DirShadowMap,
	casters: Bounds3D,
	basis: CameraBasis,
	cameraInverse: Mat4,
	eye: Vec3,
): SunLayers {
	const config: CascadeConfig | null = shadow.cascades;
	if (config === null) {
		const bounds: Bounds3D = shadowBounds(basis, casters, cameraInverse);
		let box: OrthoBounds =
			{ minX: -1.0, maxX: 1.0, minY: -1.0, maxY: 1.0, minZ: 0.0, maxZ: 1.0 };
		if (!bounds.isEmpty()) {
			box = {
				minX: bounds.min.x, maxX: bounds.max.x,
				minY: bounds.min.y, maxY: bounds.max.y,
				minZ: bounds.min.z, maxZ: bounds.max.z,
			};
		} else {
			shadow.casters.count = 0;
		}
		return {
			clips: [basis.makeCameraMatrix(vec3(0.0, 0.0, 0.0)) * box.projectionMatrix()],
			far: [ALL_DEPTHS],
		};
	}
	const casterNear: float32 = casters.isEmpty() ? 0.0 : casters.min.z;
	const made: Result<Vec<Cascade>, CascadeError> =
		cascadesOf(config, cameraInverse, eye, basis, shadow.size, casterNear);
	if (!made.ok) {
		console.log(`void3d: drawShadows found its cascades refused (${made.error.toString()})`);
		unreachable;
	}
	let layers: SunLayers = { clips: [], far: [] };
	for (const cascade of made.value) {
		layers.clips.push(cascade.clipFromWorld);
		layers.far.push(cascade.farBound);
	}
	return layers;
}

function drawSpotShadows(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	lights: Readonly<Span<float32>>,
): int32 {
	const caster: Result<int32, SpotShadowError> = spotCaster(lights);
	if (!caster.ok) {
		console.log(`void3d: drawShadows found the spot caster bad (${caster.error.toString()})`);
		unreachable;
	}
	const slot: int32 = caster.value;
	let opacity: float32 = shadow.opacity;
	let basis: CameraBasis = lightBasis(vec3(0.0, 0.0, 0.0));
	let eye: Vec3 = vec3(0.0, 0.0, 0.0);
	let texel: float32 = 0.0;
	if (slot < 0) {
		shadow.casters.count = 0;
		shadow.viewProj = identity();
		opacity = 0.0;
	} else {
		const view: Result<CameraView, SpotShadowError> = spotShadowView(lights, slot);
		if (!view.ok) {
			console.log(
				"void3d: drawShadows found the shadowing spot unplaceable (" +
					view.error.toString() + ")",
			);
			unreachable;
		}
		collectCasters(shadow.casters, items, shadow.context.materials);
		shadow.viewProj = view.value.viewProj;
		basis = view.value.basis;
		eye = view.value.eye;
		texel = 2.0 / (view.value.projectionY * (shadow.size as float32));
	}
	const map: Mat4 = mapMatrix();
	const spotPart: Span<float32> = shadow.shadowValues[SHADOW_SPOT_BASE..SHADOW_SPOT_BASE + 16];
	(shadow.viewProj * map).writeTo(spotPart, 0);
	shadow.shadowValues[SHADOW_SPOT_BIAS] = shadow.bias * map.m33;
	shadow.shadowValues[SHADOW_SPOT_OPACITY] = opacity;
	shadow.shadowValues[SHADOW_SPOT_OPACITY + 1] = shadow.size as float32;
	shadow.shadowValues[SHADOW_SPOT_FILTER] = filterScaleOf(shadow);
	shadow.shadowValues[SHADOW_SPOT_NORMAL_BIAS] = shadow.normalBias * texel * TEXEL_DIAGONAL;
	shadow.shadowValues[SHADOW_SPOT_POSITION] = eye.x;
	shadow.shadowValues[SHADOW_SPOT_POSITION + 1] = eye.y;
	shadow.shadowValues[SHADOW_SPOT_POSITION + 2] = eye.z;
	return drawLayers(shadow, items, [basis], [shadow.viewProj]);
}

// CubeShadowMap.draw: the casting light's six faces, each a layer, or cleared layers with no
// shadow when no light of the light block casts the cube map.
function drawCubeShadows(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	lights: Readonly<Span<float32>>,
): int32 {
	const caster: Result<int32, CubeShadowError> = cubeCaster(lights);
	if (!caster.ok) {
		console.log(`void3d: drawShadows found the cube caster bad (${caster.error.toString()})`);
		unreachable;
	}
	const slot: int32 = caster.value;
	let opacity: float32 = shadow.opacity;
	let clips: Vec<Mat4> = [];
	let bases: Vec<CameraBasis> = [];
	let position: Vec3 = vec3(0.0, 0.0, 0.0);
	let near: float32 = 0.0;
	let far: float32 = 0.0;
	if (slot < 0) {
		shadow.casters.count = 0;
		opacity = 0.0;
		for (let face = 0; face < SHADOW_CUBE_FACES; face++) {
			clips.push(identity());
			bases.push(lightBasis(vec3(0.0, 0.0, 0.0)));
		}
	} else {
		const views: Result<Vec<CameraView>, CubeShadowError> = cubeShadowViews(lights, slot);
		if (!views.ok) {
			console.log(
				"void3d: drawShadows found the cube caster unplaceable (" +
					views.error.toString() + ")",
			);
			unreachable;
		}
		collectCasters(shadow.casters, items, shadow.context.materials);
		for (const view of views.value) {
			clips.push(view.viewProj);
			bases.push(view.basis);
		}
		position = cubePosition(lights, slot);
		near = cubeNear(lights, slot);
		far = cubeRange(lights, slot);
	}
	shadow.viewProj = clips[0];
	shadow.packCube(clips, mapMatrix(), position, opacity, near, far);
	return drawLayers(shadow, items, bases, clips);
}

// The point's part of the block: each face's clip taken on to the map by `map`, the bias in world
// units, the opacity, the size, the light's position, which picks the face, and the faces' near
// and far planes.
export function packCube(
	this shadow: DirShadowMap,
	clips: Readonly<Span<Mat4>>,
	map: Mat4,
	position: Vec3,
	opacity: float32,
	near: float32,
	far: float32,
): void {
	if (shadow.closed) { stopOnClosed("packCube"); }
	if ((clips.length as int32) != SHADOW_CUBE_FACES) {
		console.log(`void3d: packCube with ${clips.length} clips for six faces`);
		unreachable;
	}
	for (let face = 0; face < SHADOW_CUBE_FACES; face++) {
		const at: int32 = SHADOW_CUBE_BASE + face * 16;
		(clips[face] * map).writeTo(shadow.shadowValues[at..at + 16], 0);
	}
	shadow.shadowValues[SHADOW_CUBE_BIAS] = shadow.bias;
	shadow.shadowValues[SHADOW_CUBE_OPACITY] = opacity;
	shadow.shadowValues[SHADOW_CUBE_OPACITY + 1] = shadow.size as float32;
	shadow.shadowValues[SHADOW_CUBE_FILTER] = filterScaleOf(shadow);
	shadow.shadowValues[SHADOW_CUBE_POSITION] = position.x;
	shadow.shadowValues[SHADOW_CUBE_POSITION + 1] = position.y;
	shadow.shadowValues[SHADOW_CUBE_POSITION + 2] = position.z;
	shadow.shadowValues[SHADOW_CUBE_RANGE] = near;
	shadow.shadowValues[SHADOW_CUBE_RANGE + 1] = far;
	shadow.shadowValues[SHADOW_CUBE_NORMAL_BIAS] =
		shadow.normalBias * 2.0 / (shadow.size as float32) * TEXEL_DIAGONAL;
}

// The frame applies one shadow block, the first of the sun's, the spot's and the point's maps:
// it takes the spot's and the point's parts from their maps, or zeros them, so a map detached
// since the last frame shades nothing.
export function carryShadows(
	owner: DirShadowMap,
	spot: DirShadowMap | null,
	point: DirShadowMap | null,
): void {
	if (owner.closed) { stopOnClosed("carryShadows"); }
	for (let i = SHADOW_SPOT_BASE; i < SHADOW_UNIFORM_LENGTH; i++) {
		const from: DirShadowMap | null = i < SHADOW_CUBE_BASE ? spot : point;
		let value: float32 = 0.0;
		if (from !== null) { value = from.shadowValues[i]; }
		owner.shadowValues[i] = value;
	}
	const written: Result<int32, UniformError> =
		writeUniforms(owner.context, owner.shadowBlock, owner.shadowValues);
	if (!written.ok) { stopOnLostBlocks(); }
}

// The array with one layer per clip, made again when the size or the layer count changed or its
// context was lost.
function targetFor(shadow: DirShadowMap, layers: int32): void {
	const target: ArrayTarget = shadow.depthTarget;
	if (target.isCurrent() && target.size == shadow.size && target.layers == layers) { return; }
	target.close();
	shadow.depthTarget = ArrayTarget.unallocated(shadow.size, layers, PixelFormat.Depth);
	shadow.depthTarget.allocate();
}

// The pass every layer takes in turn, depth only: the casters in that layer's frustum, drawn from
// its clip. The camera block holds one layer's clip at a time; a draw applies it as it is drawn.
function drawLayers(
	shadow: DirShadowMap,
	items: Readonly<Span<DrawItem>>,
	bases: Readonly<Span<CameraBasis>>,
	clips: Readonly<Span<Mat4>>,
): int32 {
	const context: DrawContext = shadow.context;
	const shadowWritten: Result<int32, UniformError> =
		writeUniforms(context, shadow.shadowBlock, shadow.shadowValues);
	if (!shadowWritten.ok) { stopOnLostBlocks(); }
	targetFor(shadow, clips.length as int32);
	if (shadow.sampler.handle == 0 || shadow.sampler.generation != shadow.depthTarget.generation) {
		shadow.sampler = Sampler.create(shadow.sampler.filter, shadow.sampler.wrap);
	}
	const anyCasters: boolean = shadow.casters.count > 0;
	let drawn: int32 = 0;
	for (let layer = 0; layer < (clips.length as int32); layer++) {
		if (anyCasters) {
			collectCasters(shadow.casters, items, context.materials);
			const _culled: int32 = filterFrustum(
				shadow.casters, items, context.meshData, Frustum3D.fromMatrix(clips[layer]),
			);
		}
		clips[layer].writeTo(shadow.cameraValues[0..16], 0);
		shadow.cameraValues[16] = bases[layer].right.x;
		shadow.cameraValues[17] = bases[layer].right.y;
		shadow.cameraValues[18] = bases[layer].right.z;
		shadow.cameraValues[20] = bases[layer].up.x;
		shadow.cameraValues[21] = bases[layer].up.y;
		shadow.cameraValues[22] = bases[layer].up.z;
		const cameraWritten: Result<int32, UniformError> =
			writeUniforms(context, shadow.cameraBlock, shadow.cameraValues);
		if (!cameraWritten.ok) { stopOnLostBlocks(); }
		beginPass(NO_COLORS, shadow.depthTarget.asDepth(
			layer, LoadAction.Clear, FAR_DEPTH, StoreAction.Store,
		));
		drawCasters(shadow, items);
		endPass();
		drawn = drawn + shadow.casters.count;
	}
	shadow.casterCount = drawn;
	return drawn;
}

// The collected casters into the open pass, neighbours that differ only in world as one draw.
function drawCasters(shadow: DirShadowMap, items: Readonly<Span<DrawItem>>): void {
	const context: DrawContext = shadow.context;
	let i: int32 = 0;
	while (i < shadow.casters.count) {
		const index: int32 = shadow.casters.indices[i];
		const material: Material = context.materials[items[index].material.index];
		const state: RenderState = RenderState.defaults().withCulling(material.shadowFace());
		let end: int32 = i + 1;
		while (end < shadow.casters.count &&
			items[index].sameBatch(items[shadow.casters.indices[end]])) {
			end = end + 1;
		}
		if (end - i == 1) {
			drawItemWith(context, items[index], shadow.cast[index], state, SHADOW_LAYOUT,
				shadow.globals, NO_SCENE_TEXTURE);
		} else {
			drawBatchWith(
				context, items, shadow.casters.indices[i..end], shadow.cast[index], state,
				SHADOW_LAYOUT, shadow.globals, NO_SCENE_TEXTURE,
			);
		}
		i = end;
	}
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
