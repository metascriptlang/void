// A cluster assignment laid out as the two RGBA32UI data textures a lit shader reads with
// textureLoad (docs/VOID3D.md "Clustered lights: how the clusters reach the shader"). The cluster
// texture holds one texel per cluster, Bevy's storage-buffer record (bevy_pbr/src/cluster/mod.rs,
// offsets_and_counts): the offset into the index list, the point light count, the spot light
// count. The index texture holds four light indices a texel. Both are rows of DATA_TEXTURE_WIDTH
// texels, so cluster or index i sits at (i % width, i / width).

import { vec4f } from "../shader/std";
import { ClusterParams } from "./clusterLookup";
import { ClusterAssignment, clusterFactors } from "./clusters";

export const DATA_TEXTURE_WIDTH: int32 = 256;

export struct DataTexture {
	width: int32;
	height: int32;
	words: Vec<uint32>;
}

function rowsFor(texels: int32): int32 {
	return Math.max(1, Math.ceil((texels as float64) / (DATA_TEXTURE_WIDTH as float64)) as int32);
}

function emptyTexture(): DataTexture {
	return { width: DATA_TEXTURE_WIDTH, height: 0, words: [] };
}

// Sizes `texture` to hold `texels` and zeroes it, reusing its words when the size is unchanged.
function reshape(ref texture: DataTexture, texels: int32): void {
	const height: int32 = rowsFor(texels);
	const length: int32 = DATA_TEXTURE_WIDTH * height * 4;
	if ((texture.words.length as int32) != length) {
		texture.words = [];
		for (let i = 0; i < length; i++) { texture.words.push(0); }
	} else {
		for (let i = 0; i < length; i++) { texture.words[i] = 0; }
	}
	texture.width = DATA_TEXTURE_WIDTH;
	texture.height = height;
}

export function fillClusterTexture(ref texture: DataTexture, assignment: ClusterAssignment): void {
	const clusters: int32 = assignment.counts.length as int32;
	reshape(texture, clusters);
	for (let i = 0; i < clusters; i++) {
		const point: int32 = assignment.pointCounts[i];
		texture.words[i * 4] = assignment.offsets[i] as uint32;
		texture.words[i * 4 + 1] = point as uint32;
		texture.words[i * 4 + 2] = (assignment.counts[i] - point) as uint32;
	}
}

export function fillIndexTexture(ref texture: DataTexture, assignment: ClusterAssignment): void {
	const indices: int32 = assignment.lightIndices.length as int32;
	reshape(texture, Math.ceil((indices as float64) / 4.0) as int32);
	for (let i = 0; i < indices; i++) {
		texture.words[i] = assignment.lightIndices[i] as uint32;
	}
}

export function clusterTexture(assignment: ClusterAssignment): DataTexture {
	let texture: DataTexture = emptyTexture();
	fillClusterTexture(texture, assignment);
	return texture;
}

export function indexTexture(assignment: ClusterAssignment): DataTexture {
	let texture: DataTexture = emptyTexture();
	fillIndexTexture(texture, assignment);
	return texture;
}

// The uniforms clusterLookup.ms reads to find a fragment's cluster in this assignment.
export function clusterParamsOf(
	assignment: ClusterAssignment,
	screenWidth: int32,
	screenHeight: int32,
	orthographic: boolean,
): ClusterParams {
	const grid = assignment.grid;
	const factors = clusterFactors(assignment.near, assignment.far, grid.z as float32,
		orthographic);
	return {
		clusterGrid: vec4f(grid.x as float32, grid.y as float32, grid.z as float32,
			(orthographic ? 1.0 : 0.0) as float32),
		clusterFactors: vec4f((grid.x as float32) / (screenWidth as float32),
			(grid.y as float32) / (screenHeight as float32), factors.x, factors.y),
	};
}

export struct RecordTexture {
	width: int32;
	height: int32;
	floats: Vec<float32>;
}

// The light records texture: `lights` from `first` on (gpu3d.ms LIGHT_RECORD_LENGTH floats a
// light) in rows of DATA_TEXTURE_WIDTH texels, so texel t sits at (t % width, t / width) as
// clusterLookup.ms reads. Reuses `texture`'s floats when the size is unchanged.
export function fillRecordTexture(
	ref texture: RecordTexture,
	lights: Readonly<Span<float32>>,
	first: int32,
): void {
	const length: int32 = (lights.length as int32) - first;
	const height: int32 = rowsFor(Math.ceil((length as float64) / 4.0) as int32);
	const size: int32 = DATA_TEXTURE_WIDTH * height * 4;
	if ((texture.floats.length as int32) != size) {
		texture.floats = [];
		for (let i = 0; i < size; i++) { texture.floats.push(0.0); }
	}
	for (let i = 0; i < size; i++) {
		texture.floats[i] = i < length ? lights[first + i] : 0.0;
	}
	texture.width = DATA_TEXTURE_WIDTH;
	texture.height = height;
}

export function recordTexture(lights: Readonly<Span<float32>>, first: int32): RecordTexture {
	let texture: RecordTexture = { width: DATA_TEXTURE_WIDTH, height: 0, floats: [] };
	fillRecordTexture(texture, lights, first);
	return texture;
}
