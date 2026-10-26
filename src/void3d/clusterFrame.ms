// A renderer's clustered lights on the GPU (docs/VOID3D.md "Clustered lights: how the clusters
// reach the shader"): each frame assigns collectLights' records to the view's clusters, fills the
// light block's cluster fields and rewrites the three data textures the lit programs read.

import { Mat4, vec3 } from "../math/math3d";
import {
	PixelFormat,
	contextGeneration,
	destroyImage,
	destroySampler,
	destroyView,
	frameIndex,
	makeDataImage,
	makeSampler,
	makeTextureView,
	updateDataFloats,
	updateDataWords,
} from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import { CameraView } from "./camera";
import {
	ClusterAssignment,
	ClusterConfig,
	ClusterError,
	ClusterLight,
	ClusterLightKind,
	assignLights,
} from "./clusters";
import {
	DATA_TEXTURE_WIDTH,
	DataTexture,
	RecordTexture,
	clusterParamsOf,
	clusterTexture,
	indexTexture,
	recordTexture,
} from "./clusterTextures";
import {
	LIGHT_COOKIE,
	LIGHT_CLUSTER_FACTORS,
	LIGHT_CLUSTER_GRID,
	LIGHT_CLUSTER_SCREEN,
	LIGHT_CLUSTER_VIEW,
	LIGHT_KIND_SPOT,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_SHAPE,
	LIGHT_UNIFORM_LENGTH,
} from "./gpu3d";

export enum ClusterFrameError {
	RecordLength,
	NoView,
	Clusters,
	ImageRefused,
}

struct DataImage {
	image: uint32;
	view: uint32;
	height: int32;
}

const NO_IMAGE: DataImage = { image: 0, view: 0, height: 0 };

// With no view the depth is 0, which the perspective slice would take the log of.
const EMPTY_GRID_SLICES_LINEARLY: float32 = 1.0;

export interface ClusterFrame {
	config: ClusterConfig;
	recordImage: DataImage;
	clusterImage: DataImage;
	indexImage: DataImage;
	sampler: uint32;
	generation: int32;
	writtenFrame: uint32;
	farthestZ: float32 | null;
	closed: boolean;
}

export function create(this typeof ClusterFrame, config: ClusterConfig): ClusterFrame {
	return {
		config: config,
		recordImage: NO_IMAGE,
		clusterImage: NO_IMAGE,
		indexImage: NO_IMAGE,
		sampler: 0,
		generation: 0,
		writtenFrame: 0,
		farthestZ: null,
		closed: false,
	};
}

export function recordCountOf(lights: Readonly<Span<float32>>): Result<int32, ClusterFrameError> {
	const extra: int32 = (lights.length as int32) - LIGHT_UNIFORM_LENGTH;
	if (extra < 0 || extra % LIGHT_RECORD_LENGTH != 0) {
		return Result.err(ClusterFrameError.RecordLength);
	}
	return Result.ok(extra / LIGHT_RECORD_LENGTH);
}

// Each record as clusters.ms sees it: a spot by its cone, any other shape by the sphere its range
// reaches, which holds every point it lights. The cookie spot lights its square pyramid, so its
// cone is the one through the pyramid's corners.
export function clusterLightsOf(lights: Readonly<Span<float32>>, count: int32): Vec<ClusterLight> {
	let out: Vec<ClusterLight> = [];
	for (let i = 0; i < count; i++) {
		const cookie: boolean = lights[LIGHT_COOKIE] == (i + 1) as float32;
		const at: int32 = LIGHT_UNIFORM_LENGTH + i * LIGHT_RECORD_LENGTH;
		const shape: int32 = at + LIGHT_RECORD_SHAPE;
		const spot: boolean = lights[shape + 3] == LIGHT_KIND_SPOT;
		out.push({
			kind: spot ? ClusterLightKind.Spot : ClusterLightKind.Point,
			position: vec3(lights[at], lights[at + 1], lights[at + 2]),
			range: lights[at + LIGHT_RECORD_COLOR + 3],
			direction: spot ? vec3(lights[shape], lights[shape + 1], lights[shape + 2])
				: vec3(0.0, 0.0, 1.0),
			outerHalfAngle: !spot ? 0.0 : cookie ? cornerHalfAngle(lights[shape + 7]) :
				lights[shape + 7] * 0.5,
		});
	}
	return out;
}

function cornerHalfAngle(fullAngle: float32): float32 {
	const half: float64 = (fullAngle * 0.5) as float64;
	return Math.atan(Math.SQRT2 * Math.tan(half)) as float32;
}

function emptyAssignment(): ClusterAssignment {
	return {
		grid: { x: 1, y: 1, z: 1, tileWidth: 1, tileHeight: 1 },
		near: 0.0,
		far: 0.0,
		farthestZ: 0.0,
		offsets: [0],
		counts: [0],
		pointCounts: [0],
		lightIndices: [],
	};
}

function writeQuad(out: Span<float32>, at: int32, x: float32, y: float32, z: float32, w: float32,
): void {
	out[at] = x;
	out[at + 1] = y;
	out[at + 2] = z;
	out[at + 3] = w;
}

// The frame's assignment of `lights` (collectLights' span) to `view`'s clusters, with the light
// block's cluster fields written into `block`. A frame with no positioned light needs no view: its
// one cluster lists nothing. `rowsFromBottom` is the backend's (door.ms originTopLeft negated).
export function assignFrame(
	this frame: ClusterFrame,
	lights: Readonly<Span<float32>>,
	view: CameraView | null,
	rowsFromBottom: boolean,
	block: Span<float32>,
): Result<ClusterAssignment, ClusterFrameError> {
	if (frame.closed) { stopOnClosed("assignFrame"); }
	const counted: Result<int32, ClusterFrameError> = recordCountOf(lights);
	if (!counted.ok) { return Result.err(counted.error); }
	const count: int32 = counted.value;
	const bottom: float32 = rowsFromBottom ? 1.0 : 0.0;
	if (count == 0) {
		writeQuad(block, LIGHT_CLUSTER_GRID, 1.0, 1.0, 1.0, EMPTY_GRID_SLICES_LINEARLY);
		writeQuad(block, LIGHT_CLUSTER_FACTORS, 0.0, 0.0, 0.0, 0.0);
		writeQuad(block, LIGHT_CLUSTER_VIEW, 0.0, 0.0, 0.0, 0.0);
		writeQuad(block, LIGHT_CLUSTER_SCREEN, bottom, 0.0, 0.0, 0.0);
		return Result.ok(emptyAssignment());
	}
	if (view === null) { return Result.err(ClusterFrameError.NoView); }
	const assigned: Result<ClusterAssignment, ClusterError> = assignLights(frame.config, view,
		view.texelWidth, view.texelHeight, frame.farthestZ, clusterLightsOf(lights, count));
	if (!assigned.ok) { return Result.err(ClusterFrameError.Clusters); }
	const assignment: ClusterAssignment = assigned.value;
	frame.farthestZ = assignment.farthestZ;
	const viewFromWorld: Mat4 = view.basis.makeCameraMatrix(view.eye);
	const clipFromView: Mat4 = viewFromWorld.inverseAffine() * view.viewProj;
	const params = clusterParamsOf(assignment, view.texelWidth, view.texelHeight,
		clipFromView.m44 > 0.5);
	const grid = params.clusterGrid;
	const factors = params.clusterFactors;
	const forward = view.basis.forward;
	writeQuad(block, LIGHT_CLUSTER_GRID, grid.x, grid.y, grid.z, grid.w);
	writeQuad(block, LIGHT_CLUSTER_FACTORS, factors.x, factors.y, factors.z, factors.w);
	writeQuad(block, LIGHT_CLUSTER_VIEW, forward.x, forward.y, forward.z, -forward.dot(view.eye));
	writeQuad(block, LIGHT_CLUSTER_SCREEN, bottom, view.texelHeight as float32,
		count as float32, 0.0);
	return Result.ok(assignment);
}

function stopOnRefusedImage(): void {
	console.log("void3d: the GPU refused a clustered-light data texture or its sampler");
	unreachable;
}

function release(image: DataImage): void {
	if (image.view != 0) { destroyView(image.view); }
	if (image.image != 0) { destroyImage(image.image); }
}

// The image to hold `height` rows: kept when it is current, the same size and not yet written
// this frame, as sokol updates an image once a frame.
function imageFor(frame: ClusterFrame, image: DataImage, height: int32, format: PixelFormat,
	rewrite: boolean,
): DataImage {
	const current: boolean = frame.generation == contextGeneration();
	if (image.image != 0 && current && !rewrite && image.height == height) { return image; }
	if (current) { release(image); }
	const made: uint32 = makeDataImage(DATA_TEXTURE_WIDTH, height, format);
	if (made == 0) { stopOnRefusedImage(); }
	const view: uint32 = makeTextureView(made);
	if (view == 0) { stopOnRefusedImage(); }
	return { image: made, view: view, height: height };
}

// Rewrites the three data textures from `lights` and its assignment. A second write in one frame
// goes to new images, so the draws recorded before it keep reading the first.
export function uploadFrame(
	this frame: ClusterFrame,
	lights: Readonly<Span<float32>>,
	assignment: ClusterAssignment,
): Result<int32, ClusterFrameError> {
	if (frame.closed) { stopOnClosed("uploadFrame"); }
	const now: uint32 = frameIndex();
	const rewrite: boolean = frame.writtenFrame == now;
	const records: RecordTexture = recordTexture(lights, LIGHT_UNIFORM_LENGTH);
	const clusters: DataTexture = clusterTexture(assignment);
	const indices: DataTexture = indexTexture(assignment);
	if (frame.generation != contextGeneration()) { frame.sampler = 0; }
	frame.recordImage =
		imageFor(frame, frame.recordImage, records.height, PixelFormat.Rgba32f, rewrite);
	frame.clusterImage =
		imageFor(frame, frame.clusterImage, clusters.height, PixelFormat.Rgba32ui, rewrite);
	frame.indexImage =
		imageFor(frame, frame.indexImage, indices.height, PixelFormat.Rgba32ui, rewrite);
	if (frame.sampler == 0) {
		frame.sampler = makeSampler(FilterMode.Nearest, Wrap.Clamp);
		if (frame.sampler == 0) { stopOnRefusedImage(); }
	}
	frame.generation = contextGeneration();
	if (!updateDataFloats(frame.recordImage.image, records.floats) ||
		!updateDataWords(frame.clusterImage.image, clusters.words) ||
		!updateDataWords(frame.indexImage.image, indices.words)) {
		return Result.err(ClusterFrameError.ImageRefused);
	}
	frame.writtenFrame = now;
	return Result.ok(assignment.lightIndices.length as int32);
}

export function recordsView(this frame: ClusterFrame): uint32 { return frame.recordImage.view; }
export function clustersView(this frame: ClusterFrame): uint32 { return frame.clusterImage.view; }
export function indicesView(this frame: ClusterFrame): uint32 { return frame.indexImage.view; }
export function clusterSampler(this frame: ClusterFrame): uint32 { return frame.sampler; }

function stopOnClosed(call: string): void {
	console.log(`void3d: ${call} on a closed cluster frame`);
	unreachable;
}

export function closeClusterFrame(frame: ClusterFrame): void {
	if (frame.closed) { stopOnClosed("closeClusterFrame"); }
	if (frame.generation == contextGeneration()) {
		release(frame.recordImage);
		release(frame.clusterImage);
		release(frame.indexImage);
		if (frame.sampler != 0) { destroySampler(frame.sampler); }
	}
	frame.recordImage = NO_IMAGE;
	frame.clusterImage = NO_IMAGE;
	frame.indexImage = NO_IMAGE;
	frame.sampler = 0;
	frame.closed = true;
}
