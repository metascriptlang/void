// CPU light clustering for point and spot lights: the view's frustum cut into a grid of tiles by
// depth slices, and each light listed in the clusters it can reach. The grid, the slice maths and
// the Iterative Sphere Refinement are Bevy's (bevy_light/src/cluster/mod.rs, ClusterConfig and
// Clusters::update; cluster/assign.rs, assign_objects_to_clusters), after Persson's Practical
// Clustered Shading and Olsson's logarithmic slicing. Bevy's camera looks down -z with reversed
// clip z; here view space is void3d's: x right, y up, +z forward, and clip z runs 0 at the near
// plane to 1 at the far one, so every depth below is a positive distance along forward.

import { Mat4, Vec3, Vec4, vec3, vec4 } from "../math/math3d";
import { CameraView } from "./camera";
import { Frustum3D } from "./frustum";

const DEFAULT_FAR_DEPTH: float32 = 1000.0;
const MIN_POSITIVE: float32 = 1.17549435e-38;

export enum ClusterError {
	ScreenSize,
	ZSlices,
	Total,
	Dimensions,
	FirstSliceDepth,
	FarDepth,
	Range,
	Position,
	Direction,
	Angle,
}

export enum ClusterLayoutKind {
	FixedZ,
	Xyz,
}

// FixedZ: `total` clusters over `zSlices` depth slices with square tiles; Xyz: the counts as given.
export struct ClusterLayout = match (kind: ClusterLayoutKind) {
	ClusterLayoutKind.FixedZ => { total: int32, zSlices: int32 },
	ClusterLayoutKind.Xyz => { x: int32, y: int32, z: int32 },
};

export enum ClusterFarKind {
	MaxLightRange,
	Constant,
}

// Where the last slice ends: at the farthest light of the previous frame, or at `depth`.
export struct ClusterFar = match (kind: ClusterFarKind) {
	ClusterFarKind.MaxLightRange => {},
	ClusterFarKind.Constant => { depth: float32 },
};

export struct ClusterConfig {
	layout: ClusterLayout;
	firstSliceDepth: float32;
	far: ClusterFar;
}

export struct ClusterGrid {
	x: int32;
	y: int32;
	z: int32;
	tileWidth: int32;
	tileHeight: int32;
}

export enum ClusterLightKind {
	Point,
	Spot,
}

// `direction` is where a spot light shines, and `outerHalfAngle` the cone's angle from that axis;
// a point light ignores both.
export struct ClusterLight {
	kind: ClusterLightKind;
	position: Vec3;
	range: float32;
	direction: Vec3;
	outerHalfAngle: float32;
}

// Cluster (x, y, z) is `(y * grid.x + x) * grid.z + z`. Its lights are
// `lightIndices[offsets[i] .. offsets[i] + counts[i]]`, indices into the input span, the first
// `pointCounts[i]` of them point lights.
export struct ClusterAssignment {
	grid: ClusterGrid;
	near: float32;
	far: float32;
	farthestZ: float32;
	offsets: Vec<int32>;
	counts: Vec<int32>;
	pointCounts: Vec<int32>;
	lightIndices: Vec<int32>;
}

export struct ClusterFactors {
	x: float32;
	y: float32;
}

struct ViewSphere {
	center: Vec3;
	radius: float32;
}

struct ClusterCell {
	x: int32;
	y: int32;
	z: int32;
}

struct ClusterRange {
	min: ClusterCell;
	max: ClusterCell;
}

struct ClusterSetup {
	grid: ClusterGrid;
	screenWidth: int32;
	screenHeight: int32;
	orthographic: boolean;
	projectionNear: float32;
	near: float32;
	far: float32;
	factors: ClusterFactors;
	clipFromView: Mat4;
	viewFromClip: Mat4;
	viewFromWorld: Mat4;
	xPlanes: Vec<Vec4>;
	yPlanes: Vec<Vec4>;
	zDepths: Vec<float32>;
}

// ClusterConfig::default: 24 slices, square tiles, at most 4096 clusters, the first slice ending
// at 5 and the last at the previous frame's farthest light.
export function defaults(this typeof ClusterConfig): ClusterConfig {
	return {
		layout: { kind: ClusterLayoutKind.FixedZ, total: 4096, zSlices: 24 },
		firstSliceDepth: 5.0,
		far: { kind: ClusterFarKind.MaxLightRange },
	};
}

function lnOf(value: float32): float32 { return Math.log(value as float64) as float32; }

function powOf(base: float32, exponent: float32): float32 {
	return Math.pow(base as float64, exponent as float64) as float32;
}

function sqrtOf(value: float32): float32 { return Math.sqrt(value as float64) as float32; }

// ClusterConfig::dimensions_for_screen_size followed by Clusters::update: the requested counts,
// then the tile size that covers the screen with them and the counts that tile size needs.
export function gridFor(
	config: ClusterConfig,
	screenWidth: int32,
	screenHeight: int32,
): Result<ClusterGrid, ClusterError> {
	if (screenWidth < 1 || screenHeight < 1) { return Result.err(ClusterError.ScreenSize); }
	let requestedX: int32 = 0;
	let requestedY: int32 = 0;
	let requestedZ: int32 = 0;
	const layout: ClusterLayout = config.layout;
	match (layout.kind) {
		ClusterLayoutKind.FixedZ => {
			if (layout.zSlices < 1) { return Result.err(ClusterError.ZSlices); }
			if (layout.total < layout.zSlices) { return Result.err(ClusterError.Total); }
			const aspect: float32 = (screenWidth as float32) / (screenHeight as float32);
			const perLayer: float32 = (layout.total as float32) / (layout.zSlices as float32);
			const rows: float32 = sqrtOf(perLayer / aspect);
			requestedX = (rows * aspect) as int32;
			requestedY = rows as int32;
			if (requestedX == 0) {
				requestedX = 1;
				requestedY = perLayer as int32;
			}
			if (requestedY == 0) {
				requestedX = perLayer as int32;
				requestedY = 1;
			}
			requestedZ = layout.zSlices;
		},
		ClusterLayoutKind.Xyz => {
			if (layout.x < 1 || layout.y < 1 || layout.z < 1) {
				return Result.err(ClusterError.Dimensions);
			}
			requestedX = layout.x;
			requestedY = layout.y;
			requestedZ = layout.z;
		},
	}
	const width: float32 = screenWidth as float32;
	const height: float32 = screenHeight as float32;
	const tileWidth: int32 = Math.max(Math.ceil(width / (requestedX as float32)) as int32, 1);
	const tileHeight: int32 = Math.max(Math.ceil(height / (requestedY as float32)) as int32, 1);
	return Result.ok({
		x: Math.max(Math.ceil(width / (tileWidth as float32)) as int32, 1),
		y: Math.max(Math.ceil(height / (tileHeight as float32)) as int32, 1),
		z: requestedZ,
		tileWidth: tileWidth,
		tileHeight: tileHeight,
	});
}

// calculate_cluster_factors. Orthographic slices are linear in depth, perspective ones
// logarithmic after the first.
export function clusterFactors(
	near: float32,
	far: float32,
	zSlices: float32,
	orthographic: boolean,
): ClusterFactors {
	if (orthographic) {
		return { x: near, y: zSlices / (far - near) };
	}
	const slicesOfLnFarOverNear: float32 = (zSlices - 1.0) / lnOf(far / near);
	return { x: slicesOfLnFarOverNear, y: lnOf(near) * slicesOfLnFarOverNear };
}

// z_slice_to_view_z, as a depth: where slice `zSlice` begins; `zSlices` is the far end.
export function zSliceToDepth(
	near: float32,
	far: float32,
	zSlices: int32,
	zSlice: int32,
	orthographic: boolean,
): float32 {
	if (orthographic) {
		return near + (far - near) * (zSlice as float32) / (zSlices as float32);
	}
	if (zSlice == 0) { return 0.0; }
	if (zSlices == 1) { return far; }
	return near * powOf(far / near, ((zSlice - 1) as float32) / ((zSlices - 1) as float32));
}

// A float that Rust's saturating `as u32` would turn into a cell: NaN and anything below one cell
// is the first, anything past the last is the last.
function cellOf(position: float32, cells: int32): int32 {
	if (!(position > 0.0)) { return 0; }
	if (position >= (cells as float32)) { return cells - 1; }
	return position as int32;
}

// view_z_to_z_slice
export function depthToZSlice(
	factors: ClusterFactors,
	zSlices: int32,
	depth: float32,
	orthographic: boolean,
): int32 {
	const slice: float32 = orthographic
		? Math.floor(((depth - factors.x) * factors.y) as float64) as float32
		: lnOf(depth) * factors.x - factors.y + 1.0;
	return cellOf(slice, zSlices);
}

function minOf(a: Vec3, b: Vec3): Vec3 {
	return vec3(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.min(a.z, b.z));
}

function maxOf(a: Vec3, b: Vec3): Vec3 {
	return vec3(Math.max(a.x, b.x), Math.max(a.y, b.y), Math.max(a.z, b.z));
}

function clipToView(viewFromClip: Mat4, clip: Vec4): Vec3 {
	const view: Vec4 = clip * viewFromClip;
	return vec3(view.x / view.w, view.y / view.w, view.z / view.w);
}

// HalfSpace::new: the normal made a unit, the distance scaled with it.
function halfSpace(normal: Vec3, distance: float32): Vec4 {
	const scale: float32 = 1.0 / normal.length();
	return vec4(normal.x * scale, normal.y * scale, normal.z * scale, distance * scale);
}

// The tile boundaries in view space. Each reflected cross product is Bevy's with its operands
// swapped, because flipping z reverses the handedness and a cross product turns with it.
function xPlanesOf(grid: ClusterGrid, viewFromClip: Mat4, orthographic: boolean): Vec<Vec4> {
	let planes: Vec<Vec4> = [];
	for (let x = 0; x <= grid.x; x++) {
		const position: float32 = (x as float32) / (grid.x as float32) * 2.0 - 1.0;
		if (orthographic) {
			const viewX: float32 = clipToView(viewFromClip, vec4(position, 0.0, 0.0, 1.0)).x;
			planes.push(halfSpace(vec3(1.0, 0.0, 0.0), viewX));
		} else {
			const bottom: Vec3 = clipToView(viewFromClip, vec4(position, -1.0, 0.0, 1.0));
			const top: Vec3 = clipToView(viewFromClip, vec4(position, 1.0, 0.0, 1.0));
			const normal: Vec3 = top.cross(bottom);
			planes.push(halfSpace(normal, bottom.dot(normal)));
		}
	}
	return planes;
}

function yPlanesOf(grid: ClusterGrid, viewFromClip: Mat4, orthographic: boolean): Vec<Vec4> {
	let planes: Vec<Vec4> = [];
	for (let y = 0; y <= grid.y; y++) {
		const position: float32 = (1.0 - (y as float32) / (grid.y as float32)) * 2.0 - 1.0;
		if (orthographic) {
			const viewY: float32 = clipToView(viewFromClip, vec4(0.0, position, 0.0, 1.0)).y;
			planes.push(halfSpace(vec3(0.0, 1.0, 0.0), viewY));
		} else {
			const left: Vec3 = clipToView(viewFromClip, vec4(-1.0, position, 0.0, 1.0));
			const right: Vec3 = clipToView(viewFromClip, vec4(1.0, position, 0.0, 1.0));
			const normal: Vec3 = left.cross(right);
			planes.push(halfSpace(normal, right.dot(normal)));
		}
	}
	return planes;
}

function cellAt(
	setup: ClusterSetup,
	ndcX: float32,
	ndcY: float32,
	depth: float32,
): ClusterCell {
	return {
		x: cellOf((ndcX * 0.5 + 0.5) * (setup.grid.x as float32), setup.grid.x),
		y: cellOf((ndcY * -0.5 + 0.5) * (setup.grid.y as float32), setup.grid.y),
		z: depthToZSlice(setup.factors, setup.grid.z, depth, setup.orthographic),
	};
}

// cluster_space_clusterable_object_aabb and the two ndc_position_to_cluster calls on its corners:
// the clusters the sphere's view-space box covers, with the depth held in front of the eye so a
// box that reaches behind it still projects.
function coveredRange(setup: ClusterSetup, sphere: ViewSphere): ClusterRange {
	const low: Vec3 = sphere.center - vec3(sphere.radius, sphere.radius, sphere.radius);
	const high: Vec3 = sphere.center + vec3(sphere.radius, sphere.radius, sphere.radius);
	const nearDepth: float32 = Math.max(low.z, MIN_POSITIVE);
	const farDepth: float32 = Math.max(high.z, MIN_POSITIVE);
	const corners: Vec<Vec3> = [
		vec3(low.x, low.y, nearDepth),
		vec3(low.x, low.y, farDepth),
		vec3(high.x, high.y, nearDepth),
		vec3(high.x, high.y, farDepth),
	];
	let ndcMin: Vec3 = vec3(1e30, 1e30, 1e30);
	let ndcMax: Vec3 = vec3(-1e30, -1e30, -1e30);
	for (const corner of corners) {
		const clip: Vec4 = vec4(corner.x, corner.y, corner.z, 1.0) * setup.clipFromView;
		const ndc: Vec3 = vec3(clip.x / clip.w, clip.y / clip.w, 0.0);
		ndcMin = minOf(ndcMin, ndc);
		ndcMax = maxOf(ndcMax, ndc);
	}
	const lowCell: ClusterCell = cellAt(setup, ndcMin.x, ndcMin.y, nearDepth);
	const highCell: ClusterCell = cellAt(setup, ndcMax.x, ndcMax.y, farDepth);
	return {
		min: {
			x: Math.min(lowCell.x, highCell.x),
			y: Math.min(lowCell.y, highCell.y),
			z: Math.min(lowCell.z, highCell.z),
		},
		max: {
			x: Math.max(lowCell.x, highCell.x),
			y: Math.max(lowCell.y, highCell.y),
			z: Math.max(lowCell.z, highCell.z),
		},
	};
}

// project_to_plane_z: the circle where the sphere meets the plane at `depth`, as a sphere.
function projectToPlaneZ(sphere: ViewSphere, depth: float32): ViewSphere | null {
	const distance: float32 = depth - sphere.center.z;
	if (Math.abs(distance) > sphere.radius) { return null; }
	return {
		center: vec3(sphere.center.x, sphere.center.y, depth),
		radius: sqrtOf(sphere.radius * sphere.radius - distance * distance),
	};
}

// project_to_plane_y
function projectToPlaneY(
	sphere: ViewSphere,
	plane: Vec4,
	orthographic: boolean,
): ViewSphere | null {
	const distance: float32 = orthographic
		? plane.w - sphere.center.y
		: -(sphere.center.y * plane.y + sphere.center.z * plane.z);
	if (Math.abs(distance) > sphere.radius) { return null; }
	return {
		center: sphere.center + vec3(plane.x, plane.y, plane.z).scaled(distance),
		radius: sqrtOf(sphere.radius * sphere.radius - distance * distance),
	};
}

// get_distance_x: how far the point is to the right of the plane.
function distanceX(plane: Vec4, point: Vec3, orthographic: boolean): float32 {
	if (orthographic) { return point.x - plane.w; }
	return plane.x * point.x + plane.z * point.z;
}

function screenToView(setup: ClusterSetup, pixelX: float32, pixelY: float32, ndcZ: float32): Vec3 {
	const u: float32 = pixelX / (setup.screenWidth as float32);
	const v: float32 = pixelY / (setup.screenHeight as float32);
	return clipToView(setup.viewFromClip, vec4(u * 2.0 - 1.0, (1.0 - v) * 2.0 - 1.0, ndcZ, 1.0));
}

function lineToDepth(point: Vec3, depth: float32): Vec3 {
	return point.scaled(depth / point.z);
}

// compute_aabb_for_cluster, as the sphere around the box.
function clusterSphere(setup: ClusterSetup, x: int32, y: int32, z: int32): ViewSphere {
	const grid: ClusterGrid = setup.grid;
	const lowX: float32 = (x * grid.tileWidth) as float32;
	const lowY: float32 = (y * grid.tileHeight) as float32;
	const highX: float32 = lowX + (grid.tileWidth as float32);
	const highY: float32 = lowY + (grid.tileHeight as float32);
	const a: Vec3 = screenToView(setup, lowX, lowY, 0.0);
	const b: Vec3 = screenToView(setup, highX, highY, 0.0);
	let low: Vec3;
	let high: Vec3;
	if (setup.orthographic) {
		const depthA: float32 = zSliceToDepth(setup.near, setup.far, grid.z, z, true);
		const depthB: float32 = zSliceToDepth(setup.near, setup.far, grid.z, z + 1, true);
		low = minOf(vec3(a.x, a.y, depthA), vec3(b.x, b.y, depthB));
		high = maxOf(vec3(a.x, a.y, depthA), vec3(b.x, b.y, depthB));
	} else {
		const clusterNear: float32 = zSliceToDepth(setup.near, setup.far, grid.z, z, false);
		const clusterFar: float32 = zSliceToDepth(setup.near, setup.far, grid.z, z + 1, false);
		const aNear: Vec3 = lineToDepth(a, clusterNear);
		const aFar: Vec3 = lineToDepth(a, clusterFar);
		const bNear: Vec3 = lineToDepth(b, clusterNear);
		const bFar: Vec3 = lineToDepth(b, clusterFar);
		low = minOf(minOf(aNear, aFar), minOf(bNear, bFar));
		high = maxOf(maxOf(aNear, aFar), maxOf(bNear, bFar));
	}
	const half: Vec3 = (high - low).scaled(0.5);
	return { center: (low + high).scaled(0.5), radius: half.length() };
}

// The spot light's cone against a cluster's bounding sphere, after Wronski's "Cull that cone".
// `back` points from the cone's tip away from where it shines, in view space.
function spotReaches(
	sphere: ViewSphere,
	range: float32,
	back: Vec3,
	angleSin: float32,
	angleCos: float32,
	cluster: ViewSphere,
): boolean {
	const offset: Vec3 = sphere.center - cluster.center;
	const alongAxis: float32 = offset.dot(back);
	const closest: float32 =
		angleCos * sqrtOf(offset.lengthSquared() - alongAxis * alongAxis) - alongAxis * angleSin;
	const angleCull: boolean = closest > cluster.radius;
	const frontCull: boolean = alongAxis > cluster.radius + range;
	const backCull: boolean = alongAxis < -cluster.radius;
	return !angleCull && !frontCull && !backCull;
}

function checkLight(light: ClusterLight): Result<void, ClusterError> {
	if (!Number.isFinite(light.position.x) || !Number.isFinite(light.position.y) ||
		!Number.isFinite(light.position.z)) {
		return Result.err(ClusterError.Position);
	}
	if (!Number.isFinite(light.range) || light.range < 0.0) {
		return Result.err(ClusterError.Range);
	}
	if (light.kind == ClusterLightKind.Spot) {
		const direction: Vec3 = light.direction;
		if (!Number.isFinite(direction.x) || !Number.isFinite(direction.y) ||
			!Number.isFinite(direction.z) || direction.lengthSquared() <= 0.0) {
			return Result.err(ClusterError.Direction);
		}
		if (!Number.isFinite(light.outerHalfAngle)) { return Result.err(ClusterError.Angle); }
	}
	return Result.ok(null);
}

function checkInputs(
	config: ClusterConfig,
	previousFarthestZ: float32 | null,
	lights: Readonly<Span<ClusterLight>>,
): Result<void, ClusterError> {
	if (!Number.isFinite(config.firstSliceDepth) || config.firstSliceDepth <= 0.0) {
		return Result.err(ClusterError.FirstSliceDepth);
	}
	const far: ClusterFar = config.far;
	if (far.kind == ClusterFarKind.Constant && !Number.isFinite(far.depth)) {
		return Result.err(ClusterError.FarDepth);
	}
	if (previousFarthestZ !== null && !Number.isFinite(previousFarthestZ)) {
		return Result.err(ClusterError.FarDepth);
	}
	for (const light of lights) {
		const _checked = try checkLight(light);
	}
	return Result.ok(null);
}

function setupOf(
	config: ClusterConfig,
	grid: ClusterGrid,
	view: CameraView,
	screenWidth: int32,
	screenHeight: int32,
	previousFarthestZ: float32 | null,
): ClusterSetup {
	const viewFromWorld: Mat4 = view.basis.makeCameraMatrix(view.eye);
	const clipFromView: Mat4 = viewFromWorld.inverseAffine() * view.viewProj;
	const viewFromClip: Mat4 = view.inverseViewProj * viewFromWorld;
	const orthographic: boolean = clipFromView.m44 > 0.5;
	const projectionNear: float32 = -clipFromView.m43 / clipFromView.m33;
	let farDepth: float32 = DEFAULT_FAR_DEPTH;
	const far: ClusterFar = config.far;
	match (far.kind) {
		ClusterFarKind.MaxLightRange => {
			if (previousFarthestZ !== null) { farDepth = previousFarthestZ; }
		},
		ClusterFarKind.Constant => { farDepth = far.depth; },
	}
	let near: float32 = config.firstSliceDepth;
	if (orthographic) {
		near = projectionNear;
	} else if (grid.z == 1) {
		near = Math.max(near, farDepth);
	}
	farDepth = Math.max(farDepth, near);
	let zDepths: Vec<float32> = [];
	for (let z = 0; z <= grid.z; z++) {
		zDepths.push(zSliceToDepth(near, farDepth, grid.z, z, orthographic));
	}
	return {
		grid: grid,
		screenWidth: screenWidth,
		screenHeight: screenHeight,
		orthographic: orthographic,
		projectionNear: projectionNear,
		near: near,
		far: farDepth,
		factors: clusterFactors(near, farDepth, grid.z as float32, orthographic),
		clipFromView: clipFromView,
		viewFromClip: viewFromClip,
		viewFromWorld: viewFromWorld,
		xPlanes: xPlanesOf(grid, viewFromClip, orthographic),
		yPlanes: yPlanesOf(grid, viewFromClip, orthographic),
		zDepths: zDepths,
	};
}

// The clusters, in z-fastest order, that each light reaches: Bevy visits every point light and
// then every spot light, so a cluster lists its point lights first.
export function assignLights(
	config: ClusterConfig,
	view: CameraView,
	screenWidth: int32,
	screenHeight: int32,
	previousFarthestZ: float32 | null,
	lights: Readonly<Span<ClusterLight>>,
): Result<ClusterAssignment, ClusterError> {
	const grid: ClusterGrid = try gridFor(config, screenWidth, screenHeight);
	const _checked = try checkInputs(config, previousFarthestZ, lights);
	const setup: ClusterSetup =
		setupOf(config, grid, view, screenWidth, screenHeight, previousFarthestZ);
	const frustum: Frustum3D = Frustum3D.fromMatrix(view.viewProj);
	const clusterCount: int32 = grid.x * grid.y * grid.z;
	let known: Vec<boolean> = [];
	let spheres: Vec<ViewSphere> = [];
	let pointCounts: Vec<int32> = [];
	for (let i = 0; i < clusterCount; i++) {
		known.push(false);
		spheres.push({ center: vec3(0.0, 0.0, 0.0), radius: 0.0 });
		pointCounts.push(0);
	}
	let pairClusters: Vec<int32> = [];
	let pairLights: Vec<int32> = [];
	let farthestZ: float32 = 0.0;
	const kinds: Vec<ClusterLightKind> = [ClusterLightKind.Point, ClusterLightKind.Spot];
	for (const kind of kinds) {
		for (let light = 0; light < lights.length; light++) {
			const source: ClusterLight = lights[light];
			if (source.kind != kind) { continue; }
			if (!frustum.intersectsSphere(source.position, source.range)) { continue; }
			const sphere: ViewSphere = {
				center: source.position * setup.viewFromWorld,
				radius: source.range,
			};
			const covered: ClusterRange = coveredRange(setup, sphere);
			farthestZ = Math.max(farthestZ, sphere.center.z + source.range);
			const back: Vec3 = source.direction.scaled(-1.0).transformDirection(setup.viewFromWorld)
				.normalized();
			const angleSin: float32 = Math.sin(source.outerHalfAngle as float64) as float32;
			const angleCos: float32 = Math.cos(source.outerHalfAngle as float64) as float32;
			const centerClip: Vec4 = vec4(sphere.center.x, sphere.center.y, sphere.center.z, 1.0)
				* setup.clipFromView;
			const centerCell: ClusterCell = cellAt(
				setup,
				centerClip.x / centerClip.w,
				centerClip.y / centerClip.w,
				sphere.center.z,
			);
			const centerNdcY: float32 = centerClip.y / centerClip.w;
			const hasZCenter: boolean = setup.orthographic
				? sphere.center.z >= setup.projectionNear
				: sphere.center.z < 0.0 || sphere.center.z >= setup.projectionNear;
			const hasYCenter: boolean = !(centerNdcY > 1.0);
			const yCenter: int32 = centerNdcY < -1.0 ? grid.y + 1 : centerCell.y;
			for (let z = covered.min.z; z <= covered.max.z; z++) {
				let zSphere: ViewSphere = sphere;
				if (!hasZCenter || z != centerCell.z) {
					const plane: float32 = hasZCenter && z < centerCell.z
						? setup.zDepths[z + 1]
						: setup.zDepths[z];
					const projected: ViewSphere | null = projectToPlaneZ(zSphere, plane);
					if (projected === null) { continue; }
					zSphere = projected;
				}
				for (let y = covered.min.y; y <= covered.max.y; y++) {
					let ySphere: ViewSphere = zSphere;
					if (!hasYCenter || y != yCenter) {
						const plane: Vec4 = hasYCenter && y < yCenter
							? setup.yPlanes[y + 1]
							: setup.yPlanes[y];
						const projected: ViewSphere | null =
							projectToPlaneY(ySphere, plane, setup.orthographic);
						if (projected === null) { continue; }
						ySphere = projected;
					}
					let minX: int32 = covered.min.x;
					while (minX < covered.max.x &&
						!(-distanceX(setup.xPlanes[minX + 1], ySphere.center, setup.orthographic)
							+ ySphere.radius > 0.0)) {
						minX += 1;
					}
					let maxX: int32 = covered.max.x;
					while (maxX > minX &&
						!(distanceX(setup.xPlanes[maxX], ySphere.center, setup.orthographic)
							+ ySphere.radius > 0.0)) {
						maxX -= 1;
					}
					for (let x = minX; x <= maxX; x++) {
						const cluster: int32 = (y * grid.x + x) * grid.z + z;
						if (kind == ClusterLightKind.Spot) {
							if (!known[cluster]) {
								spheres[cluster] = clusterSphere(setup, x, y, z);
								known[cluster] = true;
							}
							if (!spotReaches(sphere, source.range, back, angleSin, angleCos,
								spheres[cluster])) {
								continue;
							}
						} else {
							pointCounts[cluster] += 1;
						}
						pairClusters.push(cluster);
						pairLights.push(light as int32);
					}
				}
			}
		}
	}
	let counts: Vec<int32> = [];
	let offsets: Vec<int32> = [];
	let filled: Vec<int32> = [];
	for (let i = 0; i < clusterCount; i++) {
		counts.push(0);
		offsets.push(0);
		filled.push(0);
	}
	for (const cluster of pairClusters) { counts[cluster] += 1; }
	let running: int32 = 0;
	for (let i = 0; i < clusterCount; i++) {
		offsets[i] = running;
		running += counts[i];
	}
	let lightIndices: Vec<int32> = [];
	for (let i = 0; i < pairClusters.length; i++) { lightIndices.push(0); }
	for (let i = 0; i < pairClusters.length; i++) {
		const cluster: int32 = pairClusters[i];
		lightIndices[offsets[cluster] + filled[cluster]] = pairLights[i];
		filled[cluster] += 1;
	}
	return Result.ok({
		grid: grid,
		near: setup.near,
		far: setup.far,
		farthestZ: farthestZ,
		offsets: offsets,
		counts: counts,
		pointCounts: pointCounts,
		lightIndices: lightIndices,
	});
}
