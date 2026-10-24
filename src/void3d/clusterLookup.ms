// The lit fragment's side of clustered lights: Bevy's fragment_cluster_index and
// view_z_to_z_slice (bevy_pbr/src/render/clustered_forward.wgsl), with the cluster record and the
// light index list read from clusterTextures.ms's data textures rather than storage buffers. The
// fragment coordinate counts pixels from the top-left, as the clusters' tile rows do.

import { Vec2f, Vec2i, Vec4f, Vec4u, floor, log, vec2i, vec2u, vec4i } from "../shader/std";

// Texels a row in both data textures: clusterTextures.ms's DATA_TEXTURE_WIDTH.
const DATA_ROW: uint32 = 256;

// clusterGrid holds the grid's x, y and z counts and 1 for an orthographic view;
// clusterFactors the grid's x and y over the screen's, then the depth slicing's two factors.
export struct ClusterParams {
	clusterGrid: Vec4f;
	clusterFactors: Vec4f;
}

function cellOf(position: float32, cells: int32): int32 {
	if (!(position > 0.0)) {
		return 0;
	}
	if (position >= (cells as float32)) {
		return cells - 1;
	}
	return position as int32;
}

// view_z_to_z_slice, with void3d's positive depth.
export function clusterSliceOf(depth: float32, grid: Vec4f, factors: Vec4f): int32 {
	const slices = (grid.z + 0.5) as int32;
	if (grid.w > 0.5) {
		return cellOf(floor((depth - factors.z) * factors.w), slices);
	}
	return cellOf(log(depth) * factors.z - factors.w + 1.0, slices);
}

// fragment_cluster_index: the cluster a fragment at `frag` pixels and `depth` lies in.
export function clusterIndexOf(frag: Vec2f, depth: float32, grid: Vec4f, factors: Vec4f): int32 {
	const columns = (grid.x + 0.5) as int32;
	const x = cellOf(frag.x * factors.x, columns);
	const y = cellOf(frag.y * factors.y, (grid.y + 0.5) as int32);
	return (y * columns + x) * ((grid.z + 0.5) as int32) + clusterSliceOf(depth, grid, factors);
}

// The texel holding record `i` of a data texture.
export function dataTexelOf(i: int32): Vec2i {
	const at = vec2u(vec2i(i, 0)).x;
	return vec2i(vec2u(at % DATA_ROW, at / DATA_ROW));
}

// The texel of the index list holding light index `j`.
export function indexTexelOf(j: int32): Vec2i {
	return dataTexelOf(vec2i(vec2u(vec2u(vec2i(j, 0)).x / 4, 0)).x);
}

// Light index `j` of the list sits in channel j % 4 of texel j / 4.
export function indexOfWord(texel: Vec4u, j: int32): int32 {
	const words = vec4i(texel);
	const channel = vec2u(vec2i(j, 0)).x % 4;
	if (channel == 0) {
		return words.x;
	}
	if (channel == 1) {
		return words.y;
	}
	if (channel == 2) {
		return words.z;
	}
	return words.w;
}
