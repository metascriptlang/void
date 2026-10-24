// The CPU light clustering held to Bevy's cluster tiling and to a brute-force oracle that builds
// each cluster's view-space box from the same slice factors: arithmetic only, none of it needs
// a GPU.

import { Vec3, vec3 } from "../math/math3d";
import { Camera3D, CameraView, ProjectionKind } from "../void3d/camera";
import {
	ClusterAssignment,
	ClusterConfig,
	ClusterError,
	ClusterFarKind,
	ClusterLayoutKind,
	ClusterLight,
	ClusterLightKind,
	assignLights,
	clusterFactors,
	depthToZSlice,
	gridFor,
	zSliceToDepth,
} from "../void3d/clusters";
import { approx } from "./helpers";

const WIDTH: int32 = 1920;
const HEIGHT: int32 = 1080;
const FOV: float32 = 0.8;
const WORLD_PER_TEXEL: float32 = 0.02;
// The refinement tests the sphere against tile planes that run on past the cluster's box, so it
// keeps a few cells whose box the sphere just misses: at most 6% of the range in the cases below.
const REFINEMENT_SLACK: float32 = 0.08;

function camera(orthographic: boolean): CameraView {
	const made: Camera3D = {
		position: vec3(0.0, 0.0, 0.0),
		yaw: 0.0,
		pitch: 0.0,
		projection: orthographic
			? { kind: ProjectionKind.Orthographic, worldPerTexel: WORLD_PER_TEXEL, snap: false }
			: { kind: ProjectionKind.Perspective, fovY: FOV },
		nearPlane: 0.1,
		farPlane: 500.0,
	};
	const view = made.resolve(WIDTH, HEIGHT);
	if (!view.ok) { unreachable; }
	return view.value;
}

function pointLight(depth: float32, range: float32): ClusterLight {
	return {
		kind: ClusterLightKind.Point,
		position: vec3(0.0, 0.0, -depth),
		range: range,
		direction: vec3(0.0, 0.0, -1.0),
		outerHalfAngle: 0.0,
	};
}

function spotLight(depth: float32, range: float32, direction: Vec3): ClusterLight {
	return { ...pointLight(depth, range), kind: ClusterLightKind.Spot, direction: direction,
		outerHalfAngle: 0.3 };
}

function assign(
	config: ClusterConfig,
	orthographic: boolean,
	previous: float32 | null,
	lights: Readonly<Span<ClusterLight>>,
): ClusterAssignment {
	const result = assignLights(config, camera(orthographic), WIDTH, HEIGHT, previous, lights);
	if (!result.ok) { unreachable; }
	return result.value;
}

function refusal(
	config: ClusterConfig,
	width: int32,
	height: int32,
	lights: Readonly<Span<ClusterLight>>,
): ClusterError {
	const result = assignLights(config, camera(false), width, height, null, lights);
	if (result.ok) { unreachable; }
	return result.error;
}

function constantFar(depth: float32): ClusterConfig {
	return { ...ClusterConfig.defaults(), far: { kind: ClusterFarKind.Constant, depth: depth } };
}

function fixedZ(total: int32, zSlices: int32): ClusterConfig {
	return {
		...ClusterConfig.defaults(),
		layout: { kind: ClusterLayoutKind.FixedZ, total: total, zSlices: zSlices },
	};
}

function holds(result: ClusterAssignment, cluster: int32, light: int32): boolean {
	for (let i = 0; i < result.counts[cluster]; i++) {
		if (result.lightIndices[result.offsets[cluster] + i] == light) { return true; }
	}
	return false;
}

function clusterAt(result: ClusterAssignment, x: int32, y: int32, z: int32): int32 {
	return (y * result.grid.x + x) * result.grid.z + z;
}

struct Box {
	minX: float32;
	maxX: float32;
	minY: float32;
	maxY: float32;
	minDepth: float32;
	maxDepth: float32;
}

// The cluster's tile in ndc, row 0 at the top, with its two slice depths.
struct Tile {
	left: float32;
	right: float32;
	top: float32;
	bottom: float32;
	nearDepth: float32;
	farDepth: float32;
}

function tileOf(
	result: ClusterAssignment,
	orthographic: boolean,
	x: int32,
	y: int32,
	z: int32,
): Tile {
	const grid = result.grid;
	return {
		left: 2.0 * ((x * grid.tileWidth) as float32) / (WIDTH as float32) - 1.0,
		right: 2.0 * (((x + 1) * grid.tileWidth) as float32) / (WIDTH as float32) - 1.0,
		top: 1.0 - 2.0 * ((y * grid.tileHeight) as float32) / (HEIGHT as float32),
		bottom: 1.0 - 2.0 * (((y + 1) * grid.tileHeight) as float32) / (HEIGHT as float32),
		nearDepth: zSliceToDepth(result.near, result.far, grid.z, z, orthographic),
		farDepth: zSliceToDepth(result.near, result.far, grid.z, z + 1, orthographic),
	};
}

function viewAt(ndcX: float32, ndcY: float32, depth: float32, orthographic: boolean): Vec3 {
	if (orthographic) {
		const half: float32 = 0.5 * WORLD_PER_TEXEL;
		return vec3(ndcX * half * (WIDTH as float32), ndcY * half * (HEIGHT as float32), depth);
	}
	const scaleY: float32 = (1.0 / Math.tan(FOV * 0.5)) as float32;
	const scaleX: float32 = scaleY * (HEIGHT as float32) / (WIDTH as float32);
	return vec3(ndcX * depth / scaleX, ndcY * depth / scaleY, depth);
}

// The tile's frustum cell inside its axis-aligned view-space box, as compute_aabb_for_cluster.
function boxOf(tile: Tile, orthographic: boolean): Box {
	let box: Box = {
		minX: 1e30, maxX: -1e30, minY: 1e30, maxY: -1e30,
		minDepth: tile.nearDepth, maxDepth: tile.farDepth,
	};
	for (const depth of [tile.nearDepth, tile.farDepth]) {
		for (const ndcX of [tile.left, tile.right]) {
			for (const ndcY of [tile.top, tile.bottom]) {
				const corner: Vec3 = viewAt(ndcX, ndcY, depth, orthographic);
				box = {
					...box,
					minX: Math.min(box.minX, corner.x), maxX: Math.max(box.maxX, corner.x),
					minY: Math.min(box.minY, corner.y), maxY: Math.max(box.maxY, corner.y),
				};
			}
		}
	}
	return box;
}

function gap(low: float32, high: float32, at: float32): float32 {
	return Math.max(Math.max(low - at, at - high), 0.0);
}

function touches(box: Box, center: Vec3, radius: float32, grow: float32): boolean {
	const dx: float32 = gap(box.minX - grow, box.maxX + grow, center.x);
	const dy: float32 = gap(box.minY - grow, box.maxY + grow, center.y);
	const dz: float32 = gap(box.minDepth - grow, box.maxDepth + grow, center.z);
	return dx * dx + dy * dy + dz * dz <= radius * radius;
}

function clamped(ndc: float32): float32 { return Math.min(Math.max(ndc, -1.0), 1.0); }

// Whether some point of the cluster's cell, inside the screen, is strictly inside the sphere.
function cellHasPointIn(tile: Tile, orthographic: boolean, center: Vec3, radius: float32): boolean {
	for (let i = 0; i < 6; i++) {
		for (let j = 0; j < 6; j++) {
			for (let k = 0; k < 6; k++) {
				const u: float32 = ((i as float32) + 0.5) / 6.0;
				const v: float32 = ((j as float32) + 0.5) / 6.0;
				const w: float32 = ((k as float32) + 0.5) / 6.0;
				const depth: float32 = tile.nearDepth + w * (tile.farDepth - tile.nearDepth);
				const ndcX: float32 = clamped(tile.left + u * (tile.right - tile.left));
				const ndcY: float32 = clamped(tile.bottom + v * (tile.top - tile.bottom));
				const offset: Vec3 = viewAt(ndcX, ndcY, depth, orthographic) - center;
				if (offset.lengthSquared() < radius * radius * 0.998) { return true; }
			}
		}
	}
	return false;
}

function checkAgainstOracle(
	config: ClusterConfig,
	orthographic: boolean,
	depth: float32,
	range: float32,
): boolean {
	const result: ClusterAssignment =
		assign(config, orthographic, null, [pointLight(depth, range)]);
	const grid = result.grid;
	const center: Vec3 = vec3(0.0, 0.0, depth);
	let assignedCount: int32 = 0;
	let reachedCount: int32 = 0;
	for (let z = 0; z < grid.z; z++) {
		for (let y = 0; y < grid.y; y++) {
			for (let x = 0; x < grid.x; x++) {
				const tile: Tile = tileOf(result, orthographic, x, y, z);
				const inside: boolean = holds(result, clusterAt(result, x, y, z), 0);
				if (cellHasPointIn(tile, orthographic, center, range)) {
					reachedCount += 1;
					if (!inside) { return false; }
				}
				if (inside) {
					assignedCount += 1;
					const box: Box = boxOf(tile, orthographic);
					if (!touches(box, center, range, REFINEMENT_SLACK * range)) { return false; }
				}
			}
		}
	}
	return reachedCount > 8 && assignedCount >= reachedCount &&
		assignedCount < grid.x * grid.y * grid.z;
}

test "1920x1080 at the default config tiles as Bevy's dimensions_for_screen_size and update" {
	const grid = gridFor(ClusterConfig.defaults(), 1920, 1080);
	assert grid.ok;
	if (!grid.ok) { return; }
	assert grid.value.x == 17 && grid.value.y == 9 && grid.value.z == 24;
	assert grid.value.tileWidth == 113 && grid.value.tileHeight == 120;
	const tall = gridFor(ClusterConfig.defaults(), 3, 4000);
	assert tall.ok;
	if (!tall.ok) { return; }
	assert tall.value.x == 1 && tall.value.y == 167 && tall.value.z == 24;
	assert tall.value.tileWidth == 3 && tall.value.tileHeight == 24;
	const explicit = gridFor({
		...ClusterConfig.defaults(),
		layout: { kind: ClusterLayoutKind.Xyz, x: 16, y: 8, z: 4 },
	}, 1920, 1080);
	assert explicit.ok;
	if (!explicit.ok) { return; }
	assert explicit.value.x == 16 && explicit.value.y == 8 && explicit.value.z == 4;
	assert explicit.value.tileWidth == 120 && explicit.value.tileHeight == 135;
}

test "a slice's depth maps back to the slice, perspective and orthographic" {
	for (const orthographic of [false, true]) {
		const near: float32 = orthographic ? 0.1 : 5.0;
		const far: float32 = 100.0;
		const factors = clusterFactors(near, far, 24.0, orthographic);
		assert approx(zSliceToDepth(near, far, 24, 24, orthographic),
			far);
		for (let slice = 0; slice < 24; slice++) {
			const start: float32 = zSliceToDepth(near, far, 24, slice, orthographic);
			const end: float32 = zSliceToDepth(near, far, 24, slice + 1, orthographic);
			assert depthToZSlice(factors, 24, 0.5 * (start + end), orthographic) == slice;
			assert depthToZSlice(factors, 24, start + 0.001 * (end - start), orthographic) == slice;
		}
		assert depthToZSlice(factors, 24, 1e6, orthographic) == 23;
		assert depthToZSlice(factors, 24, -3.0, orthographic) == 0;
	}
	assert zSliceToDepth(5.0, 100.0, 24, 0, false) == 0.0;
	assert approx(zSliceToDepth(5.0, 100.0, 24, 1, false), 5.0);
	const last: float32 = 5.0 * Math.pow(20.0, 22.0 / 23.0) as float32;
	assert approx(zSliceToDepth(5.0, 100.0, 24, 23, false), last);
}

test "a point light on the axis is in the clusters its sphere reaches and in no others" {
	assert checkAgainstOracle(ClusterConfig.defaults(), false, 20.0, 6.0);
	assert checkAgainstOracle(ClusterConfig.defaults(), false, 8.0, 3.0);
	assert checkAgainstOracle(ClusterConfig.defaults(), false, 60.0, 25.0);
	assert checkAgainstOracle(ClusterConfig.defaults(), false, 3.0, 2.0);
	assert checkAgainstOracle(constantFar(40.0), true, 20.0, 6.0);
	assert checkAgainstOracle(constantFar(40.0), true, 12.0, 4.0);
	const ortho: ClusterAssignment = assign(constantFar(40.0), true, null, []);
	assert approx(ortho.near, 0.1) && ortho.far == 40.0;
}

test "a light behind the camera or outside the frustum is in no cluster" {
	const behind: ClusterLight = { ...pointLight(0.0, 5.0), position: vec3(0.0, 0.0, 30.0) };
	const beside: ClusterLight = { ...pointLight(20.0, 5.0), position: vec3(500.0, 0.0, -20.0) };
	const beyond: ClusterLight = pointLight(2000.0, 10.0);
	const above: ClusterLight = { ...pointLight(20.0, 5.0), position: vec3(0.0, 90.0, -20.0) };
	const lights: Vec<ClusterLight> = [behind, beside, beyond, above];
	for (const orthographic of [false, true]) {
		const result: ClusterAssignment =
			assign(ClusterConfig.defaults(), orthographic, null, lights);
		assert result.lightIndices.length == 0;
		for (const count of result.counts) { assert count == 0; }
		assert result.farthestZ == 0.0;
	}
	const near: ClusterAssignment =
		assign(ClusterConfig.defaults(), false, null, [pointLight(20.0, 5.0)]);
	assert near.lightIndices.length > 0;
}

test "a spot light is culled from the clusters behind it that a point light would fill" {
	const range: float32 = 12.0;
	const point: ClusterAssignment =
		assign(ClusterConfig.defaults(), false, null, [pointLight(20.0, range)]);
	const away: ClusterAssignment = assign(ClusterConfig.defaults(), false, null,
		[spotLight(20.0, range, vec3(1.0, 0.0, 0.0))]);
	const ahead: ClusterAssignment = assign(ClusterConfig.defaults(), false, null,
		[spotLight(20.0, range, vec3(0.0, 0.0, -1.0))]);
	let behindCount: int32 = 0;
	for (let z = 0; z < point.grid.z; z++) {
		for (let y = 0; y < point.grid.y; y++) {
			for (let x = 0; x < point.grid.x; x++) {
				const cluster: int32 = clusterAt(point, x, y, z);
				const tile: Tile = tileOf(point, false, x, y, z);
				const box: Box = boxOf(tile, false);
				const half: Vec3 = vec3(box.maxX - box.minX, box.maxY - box.minY,
					box.maxDepth - box.minDepth).scaled(0.5);
				const centerX: float32 = 0.5 * (box.minX + box.maxX);
				assert !holds(away, cluster, 0) || holds(point, cluster, 0);
				assert !holds(ahead, cluster, 0) || holds(point, cluster, 0);
				if (holds(point, cluster, 0) && centerX < -half.length() - 0.01) {
					behindCount += 1;
					assert !holds(away, cluster, 0);
				}
			}
		}
	}
	assert behindCount > 4;
	assert away.lightIndices.length > 0 && away.lightIndices.length < point.lightIndices.length;
	assert ahead.lightIndices.length > 0 && ahead.lightIndices.length < point.lightIndices.length;
	const mixed: ClusterAssignment = assign(ClusterConfig.defaults(), false, null,
		[spotLight(20.0, range, vec3(0.0, 0.0, -1.0)), pointLight(20.0, range)]);
	for (let cluster = 0; cluster < mixed.counts.length; cluster++) {
		assert mixed.pointCounts[cluster] <= mixed.counts[cluster];
		if (mixed.counts[cluster] == 2) {
			assert mixed.pointCounts[cluster] == 1;
			assert mixed.lightIndices[mixed.offsets[cluster]] == 1;
			assert mixed.lightIndices[mixed.offsets[cluster] + 1] == 0;
		}
	}
}

test "the farthest z is the deepest light's view depth plus its range" {
	const one: ClusterAssignment = assign(ClusterConfig.defaults(), false, null,
		[pointLight(20.0, 6.0)]);
	assert approx(one.farthestZ, 26.0);
	const two: ClusterAssignment = assign(ClusterConfig.defaults(), false, null,
		[pointLight(20.0, 6.0), spotLight(30.0, 4.0, vec3(0.0, 0.0, -1.0)), pointLight(5.0, 2.0)]);
	assert approx(two.farthestZ, 34.0);
	const next: ClusterAssignment = assign(ClusterConfig.defaults(), false, two.farthestZ,
		[pointLight(20.0, 6.0)]);
	assert approx(next.far, 34.0) && approx(next.near, 5.0);
	assert approx(one.far, 1000.0);
}

test "input Bevy would clamp or turn into NaN is refused by name" {
	const light: ClusterLight = pointLight(20.0, 5.0);
	const zero: float32 = 0.0;
	const defaults: ClusterConfig = ClusterConfig.defaults();
	assert refusal(defaults, 0, 1080, [light]) == ClusterError.ScreenSize;
	assert refusal(defaults, 1920, 0, [light]) == ClusterError.ScreenSize;
	assert refusal(fixedZ(4096, 0), WIDTH, HEIGHT, [light]) == ClusterError.ZSlices;
	assert refusal(fixedZ(0, 24), WIDTH, HEIGHT, [light]) == ClusterError.Total;
	assert refusal(fixedZ(10, 24), WIDTH, HEIGHT, [light]) == ClusterError.Total;
	assert refusal({ ...defaults, layout: { kind: ClusterLayoutKind.Xyz, x: 4, y: 0, z: 4 } },
		WIDTH, HEIGHT, [light]) == ClusterError.Dimensions;
	assert refusal({ ...defaults, firstSliceDepth: 0.0 }, WIDTH, HEIGHT, [light])
		== ClusterError.FirstSliceDepth;
	assert refusal(constantFar(1.0 / zero), WIDTH, HEIGHT, [light]) == ClusterError.FarDepth;
	assert refusal(defaults, WIDTH, HEIGHT, [{ ...light, range: -1.0 }]) == ClusterError.Range;
	assert refusal(defaults, WIDTH, HEIGHT, [{ ...light, range: zero / zero }])
		== ClusterError.Range;
	assert refusal(defaults, WIDTH, HEIGHT, [{ ...light, position: vec3(1.0 / zero, 0.0, -5.0) }])
		== ClusterError.Position;
	assert refusal(defaults, WIDTH, HEIGHT, [{ ...light, position: vec3(0.0, zero / zero, -5.0) }])
		== ClusterError.Position;
	assert refusal(defaults, WIDTH, HEIGHT, [spotLight(20.0, 5.0, vec3(0.0, 0.0, 0.0))])
		== ClusterError.Direction;
	assert refusal(defaults, WIDTH, HEIGHT,
		[{ ...spotLight(20.0, 5.0, vec3(0.0, 0.0, -1.0)), outerHalfAngle: zero / zero }])
		== ClusterError.Angle;
	const nan: float32 = zero / zero;
	const stale = assignLights(defaults, camera(false), WIDTH, HEIGHT, nan, [light]);
	assert !stale.ok && stale.error == ClusterError.FarDepth;
}
