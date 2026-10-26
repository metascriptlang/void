// The cluster assignment as the shader's two data textures: the record per cluster and the index
// list four to a texel.

import { ClusterAssignment } from "../void3d/clusters";
import {
	DATA_TEXTURE_WIDTH, DataTexture, clusterTexture, indexTexture,
} from "../void3d/clusterTextures";

function assignment(clusters: int32): ClusterAssignment {
	let offsets: Vec<int32> = [];
	let counts: Vec<int32> = [];
	let pointCounts: Vec<int32> = [];
	let lightIndices: Vec<int32> = [];
	for (let i = 0; i < clusters; i++) {
		offsets.push(lightIndices.length as int32);
		const lights: int32 = i % 3;
		for (let k = 0; k < lights; k++) { lightIndices.push(i * 10 + k); }
		counts.push(lights);
		pointCounts.push(Math.min(lights, 1));
	}
	return {
		grid: { x: clusters, y: 1, z: 1, tileWidth: 1, tileHeight: 1 },
		near: 1.0,
		far: 10.0,
		farthestZ: 10.0,
		offsets: offsets,
		counts: counts,
		pointCounts: pointCounts,
		lightIndices: lightIndices,
	};
}

function texel(texture: DataTexture, at: int32, channel: int32): uint32 {
	const x: int32 = at % texture.width;
	const y: int32 = (at / texture.width) as int32;
	return texture.words[(y * texture.width + x) * 4 + channel];
}

test "each cluster's texel holds its offset, point count and spot count, past the first row" {
	const made: ClusterAssignment = assignment(DATA_TEXTURE_WIDTH + 5);
	const texture: DataTexture = clusterTexture(made);
	assert texture.width == DATA_TEXTURE_WIDTH && texture.height == 2;
	assert texture.words.length == texture.width * texture.height * 4;
	for (const i of [0, 1, 2, DATA_TEXTURE_WIDTH + 1, DATA_TEXTURE_WIDTH + 4]) {
		assert texel(texture, i, 0) == made.offsets[i] as uint32;
		assert texel(texture, i, 1) == made.pointCounts[i] as uint32;
		assert texel(texture, i, 2) == (made.counts[i] - made.pointCounts[i]) as uint32;
		assert texel(texture, i, 3) == 0;
	}
}

test "the index list fills four indices a texel, and an empty list still makes one row" {
	const made: ClusterAssignment = assignment(DATA_TEXTURE_WIDTH * 3);
	const texture: DataTexture = indexTexture(made);
	const indices: int32 = made.lightIndices.length as int32;
	const perRow: float64 = (4 * DATA_TEXTURE_WIDTH) as float64;
	assert texture.height == Math.ceil((indices as float64) / perRow);
	for (let i = 0; i < indices; i++) {
		assert texel(texture, (i / 4) as int32, i % 4) == made.lightIndices[i] as uint32;
	}
	const empty: DataTexture = indexTexture(assignment(1));
	assert empty.height == 1 && empty.words.length == DATA_TEXTURE_WIDTH * 4;
}
