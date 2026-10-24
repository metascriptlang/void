// Cascaded shadow maps for the directional light: the camera's view split by distance into up to
// four slices, each covered by its own orthographic map in one layer of a depth array. The
// split and each cascade's matrix are Bevy's (bevy_light/src/cascade.rs, calculate_cascade_bounds
// and calculate_cascade); Heaps' CascadeShadowMap (h3d/pass/CascadeShadowMap.hx) has the same
// shape: a fitted box per slice, snapped to the map's texels so the shadow does not shimmer.

import { Mat4, Vec3, vec3 } from "../math/math3d";
import { Bounds3D, addPos } from "./bounds";
import { CameraBasis, OrthoBounds } from "./camera";

// Heaps' CascadeShadow MAX_CASCADE_COUNT and Bevy's MAX_CASCADES_PER_LIGHT.
export const MAX_CASCADES: int32 = 4;

// Bevy's CascadeShadowConfig: each cascade's far bound in view depth, nearest first; the share of
// a cascade's far bound the next one starts before it, blended across; where the first starts.
export struct CascadeConfig {
	bounds: Vec<float32>;
	overlap: float32;
	minimumDistance: float32;
}

export enum CascadeError {
	Count,
	Bounds,
	Overlap,
	MinimumDistance,
	MapSize,
}

export struct Cascade {
	clipFromWorld: Mat4;
	farBound: float32;
	texelSize: float32;
}

// calculate_cascade_bounds: from `nearest` to `maximum` in equal ratios, Bevy's builder default
// being 4 cascades, 10 and 150 (cascade.rs CascadeShadowConfigBuilder::default).
export function cascadeBounds(count: int32, nearest: float32, maximum: float32): Vec<float32> {
	if (count == 1) { return [maximum]; }
	const base: float64 = Math.pow((maximum / nearest) as float64, 1.0 / ((count - 1) as float64));
	let bounds: Vec<float32> = [];
	for (let i = 0; i < count; i++) {
		bounds.push((nearest * Math.pow(base, i as float64)) as float32);
	}
	return bounds;
}

// CascadeShadowConfigBuilder::build's checks, with the count capped as the shaders cap it.
export function validate(this config: CascadeConfig): Result<int32, CascadeError> {
	const count: int32 = config.bounds.length as int32;
	if (count < 1 || count > MAX_CASCADES) { return Result.err(CascadeError.Count); }
	if (!Number.isFinite(config.minimumDistance) || config.minimumDistance < 0.0) {
		return Result.err(CascadeError.MinimumDistance);
	}
	if (!Number.isFinite(config.overlap) || config.overlap < 0.0 || config.overlap >= 1.0) {
		return Result.err(CascadeError.Overlap);
	}
	let previous: float32 = config.minimumDistance;
	for (const bound of config.bounds) {
		if (!Number.isFinite(bound) || bound <= previous) {
			return Result.err(CascadeError.Bounds);
		}
		previous = bound;
	}
	return Result.ok(count);
}

// The eight corners of the view between view depths `near` and `far`, measured from `eye` along
// the view's forward axis: each edge of the view frustum cut at the two depths, near plane first,
// each plane bottom-right, top-right, top-left, bottom-left as Bevy's get_frustum_corners.
export function sliceCorners(
	cameraInverse: Mat4,
	eye: Vec3,
	near: float32,
	far: float32,
): Vec<Vec3> {
	let nearPlane: Vec<Vec3> = [];
	let farPlane: Vec<Vec3> = [];
	const xs: Vec<float32> = [1.0, 1.0, -1.0, -1.0];
	const ys: Vec<float32> = [-1.0, 1.0, 1.0, -1.0];
	for (let k = 0; k < 4; k++) {
		nearPlane.push(vec3(xs[k], ys[k], 0.0).project(cameraInverse));
		farPlane.push(vec3(xs[k], ys[k], 1.0).project(cameraInverse));
	}
	const forward: Vec3 = (centerOf(farPlane) - centerOf(nearPlane)).normalized();
	let corners: Vec<Vec3> = [];
	for (const depth of [near, far]) {
		for (let k = 0; k < 4; k++) {
			const from: float32 = (nearPlane[k] - eye).dot(forward);
			const to: float32 = (farPlane[k] - eye).dot(forward);
			const t: float32 = (depth - from) / (to - from);
			corners.push(nearPlane[k] + (farPlane[k] - nearPlane[k]).scaled(t));
		}
	}
	return corners;
}

function centerOf(points: Readonly<Span<Vec3>>): Vec3 {
	let sum: Vec3 = vec3(0.0, 0.0, 0.0);
	for (const point of points) { sum = sum + point; }
	return sum.scaled(1.0 / (points.length as float32));
}

// calculate_cascade, in void3d's light space (lightBasis: +z away from the light, the light's
// origin at the world's). The box's width is the slice's larger diagonal, rounded up, so it does
// not change as the view turns, and its centre sits on a texel multiple, so it moves a whole texel
// at a time. Bevy keeps the slice's near side and draws casters before it with depth clamping;
// sokol has none, so the box reaches back to `casterNear`, the nearest caster's light depth.
export function cascadeOf(
	corners: Readonly<Span<Vec3>>,
	mapSize: int32,
	basis: CameraBasis,
	casterNear: float32,
	farBound: float32,
): Cascade {
	let light: Bounds3D = Bounds3D.empty();
	for (const corner of corners) {
		addPos(light, corner.dot(basis.right), corner.dot(basis.up), corner.dot(basis.forward));
	}
	const min: Vec3 = light.min;
	const max: Vec3 = light.max;
	const body: float32 = (corners[0] - corners[6]).length();
	const farDiagonal: float32 = (corners[4] - corners[6]).length();
	const diameter: float32 = Math.ceil(Math.max(body, farDiagonal)) as float32;
	const texel: float32 = diameter / (mapSize as float32);
	const centerX: float32 = (Math.floor(0.5 * (min.x + max.x) / texel) as float32) * texel;
	const centerY: float32 = (Math.floor(0.5 * (min.y + max.y) / texel) as float32) * texel;
	const box: OrthoBounds = {
		minX: centerX - 0.5 * diameter, maxX: centerX + 0.5 * diameter,
		minY: centerY - 0.5 * diameter, maxY: centerY + 0.5 * diameter,
		minZ: Math.min(min.z, casterNear), maxZ: max.z,
	};
	return {
		clipFromWorld: basis.makeCameraMatrix(vec3(0.0, 0.0, 0.0)) * box.projectionMatrix(),
		farBound: farBound,
		texelSize: texel,
	};
}

// build_directional_light_cascades for one view: cascade i covers view depths from the previous
// far bound times (1 - overlap), or the minimum distance for the first, to its own far bound.
export function cascadesOf(
	config: CascadeConfig,
	cameraInverse: Mat4,
	eye: Vec3,
	basis: CameraBasis,
	mapSize: int32,
	casterNear: float32,
): Result<Vec<Cascade>, CascadeError> {
	const _count: int32 = try config.validate();
	if (mapSize < 1) { return Result.err(CascadeError.MapSize); }
	let cascades: Vec<Cascade> = [];
	let near: float32 = config.minimumDistance;
	for (const far of config.bounds) {
		const corners: Vec<Vec3> = sliceCorners(cameraInverse, eye, near, far);
		cascades.push(cascadeOf(corners, mapSize, basis, casterNear, far));
		near = (1.0 - config.overlap) * far;
	}
	return Result.ok(cascades);
}
