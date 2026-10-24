// CPU-side geometry, in the role of h3d.prim.Polygon: the vertex and index arrays a mesh is
// built from, plus the bounds they span. It owns no GPU object and never touches the driver,
// so it is the thing a lost context is rebuilt from (draw.ms, rebuildMeshes) and the thing
// the headless tests can check.
//
// Heaps keeps points, normals, uvs and colors as four parallel arrays and interleaves them in
// `getCPUBuffer` at upload. Here the interleave is the storage: one `Vec<float32>` in the layout
// gpu3d.c describes for it, `Lit` (position 3, normal 3, rgba 4) or, for a mesh that carries
// uvs, `LitTextured` (position 3, normal 3, uv 2, rgba 4: `getBufferFormat`'s order). The fixed
// sokol-shdc programs read exactly those two, so four arrays would buy nothing.
//
// MeshData is a value struct holding owned `Vec`s, so **assigning it to a local copies its
// arrays**. Reach one through its table by index (`context.meshData[i].bounds`) or take it by
// `ref`; never `const data: MeshData = table[i]` (CODE-STYLE §5, the copy trap).

@include("mikkTangents.h");
@compile("./mikkTangents.c");

extern function void3dMikkTangents(
	vertices: Readonly<Span<float32>>,
	stride: int32,
	indices: Readonly<Span<uint16>>,
	corners: Span<float32>,
): int32;

extern function void3dMikkTangents32(
	vertices: Readonly<Span<float32>>,
	stride: int32,
	indices: Readonly<Span<uint32>>,
	corners: Span<float32>,
): int32;

import { Vec3, vec3 } from "../math/math3d";
import { sinf, cosf } from "../math/mat4";
import { Bounds3D, addPoint } from "./bounds";
import { Ray } from "./ray";
import { Face } from "../gpu/state";
import { MAX_SKIN_PALETTE_JOINTS } from "./skinPalette";

// position(3) + normal(3) + rgba(4), the `Lit` vertex layout in gpu3d.c describeLayout.
export const LIT_VERTEX_STRIDE: int32 = 10;
export const LIT_TEXTURED_VERTEX_STRIDE: int32 = 12;
// LitTextured, then glTF's TANGENT: xyz, and in w the sign the bitangent cross(normal, tangent)
// takes; the `LitTexturedTangent` layout a normal-mapped key reads.
export const LIT_TEXTURED_TANGENT_VERTEX_STRIDE: int32 = 16;

export const MAX_MESH_VERTICES: int32 = 0x7fffffff;

export struct Rgba {
	red: float32;
	green: float32;
	blue: float32;
	alpha: float32;
}

// h3d.prim.UV.
export struct Uv {
	u: float32;
	v: float32;
}

export struct MeshData {
	vertices: Vec<float32>;
	indices: Vec<uint16>;
	wideIndices: Vec<uint32> | null;
	bounds: Bounds3D;
	hasUvs: boolean;
	hasTangents: boolean;
	hasUvB: boolean;
	hasSkin: boolean;
}

export struct MeshRayHit {
	distance: float32;
	uv: Uv | null;
}

export enum MeshError {
	TooManyVertices,
	IndexOutOfRange,
	UvMismatch,
	TangentsAdded,
	TangentCount,
	SkinAdded,
	SkinCount,
	SkinJoint,
	SkinWeight,
	DrawRange,
	IndexStorage,
	SphereParameters,
	UnindexedAppend,
	CylinderParameters,
	DiscParameters,
	CapsuleParameters,
	GridParameters,
	GeoSphereParameters,
	VertexStorage,
	TranslationOffset,
	PositionRange,
	UvScaleParameters,
	UvRange,
	ScaleParameters,
	UvBAdded,
	UvBCount,
}

export function empty(this typeof MeshData): MeshData {
	return {
		vertices: [],
		indices: [],
		bounds: Bounds3D.empty(),
		hasUvs: false,
		hasTangents: false,
		hasUvB: false,
		hasSkin: false,
	};
}

export function withUvs(this typeof MeshData): MeshData {
	return { ...MeshData.empty(), hasUvs: true };
}

export function stride(this data: Readonly<MeshData>): int32 {
	const base: int32 = data.hasTangents ? LIT_TEXTURED_TANGENT_VERTEX_STRIDE :
		(data.hasUvs ? LIT_TEXTURED_VERTEX_STRIDE : LIT_VERTEX_STRIDE);
	return base + (data.hasUvB ? 2 : 0) + (data.hasSkin ? 8 : 0);
}

// Appends a second uv set, two floats per vertex, after the tangent and before the skin: the
// `*UvB` layouts in gpu3d.c, the attribute Bevy calls ATTRIBUTE_UV_1.
export function addUvB(
	ref data: MeshData,
	uvs: Readonly<Span<float32>>,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasUvB) { return Result.err(MeshError.UvBAdded); }
	const count: int32 = data.vertexCount();
	const base: int32 = data.stride();
	if (count > MAX_MESH_VERTICES / (base + 2)) { return Result.err(MeshError.TooManyVertices); }
	if (data.vertices.length != count * base || uvs.length != count * 2) {
		return Result.err(MeshError.UvBCount);
	}
	for (const value of uvs) {
		if (!Number.isFinite(value)) { return Result.err(MeshError.UvRange); }
	}
	let packed: Vec<float32> = [];
	for (let vertex = 0; vertex < count; vertex++) {
		for (let field = 0; field < base; field++) {
			packed.push(data.vertices[vertex * base + field]);
		}
		packed.push(uvs[vertex * 2]);
		packed.push(uvs[vertex * 2 + 1]);
	}
	data.vertices = move packed;
	data.hasUvB = true;
	return Result.ok(count);
}

export function addSkinAttributes(
	ref data: MeshData,
	joints: Readonly<Span<int32>>,
	weights: Readonly<Span<float32>>,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	const count: int32 = data.vertexCount();
	const base: int32 = data.stride();
	if (count > MAX_MESH_VERTICES / (base + 8)) {
		return Result.err(MeshError.TooManyVertices);
	}
	if (count < 1 || data.vertices.length != count * base ||
		joints.length != count * 4 || weights.length != joints.length) {
		return Result.err(MeshError.SkinCount);
	}
	for (let vertex = 0; vertex < count; vertex++) {
		let total: float64 = 0.0;
		for (let slot = 0; slot < 4; slot++) {
			const at: int32 = vertex * 4 + slot;
			if (joints[at] < 0 || joints[at] >= MAX_SKIN_PALETTE_JOINTS) {
				return Result.err(MeshError.SkinJoint);
			}
			if (!Number.isFinite(weights[at]) || weights[at] < 0.0) {
				return Result.err(MeshError.SkinWeight);
			}
			total += weights[at] as float64;
		}
		if (!Number.isFinite(total) || Math.abs(total - 1.0) > 0.00001) {
			return Result.err(MeshError.SkinWeight);
		}
	}
	let packed: Vec<float32> = [];
	for (let vertex = 0; vertex < count; vertex++) {
		for (let field = 0; field < base; field++) {
			packed.push(data.vertices[vertex * base + field]);
		}
		for (let slot = 0; slot < 4; slot++) { packed.push(joints[vertex * 4 + slot] as float32); }
		for (let slot = 0; slot < 4; slot++) { packed.push(weights[vertex * 4 + slot]); }
	}
	data.vertices = move packed;
	data.hasSkin = true;
	return Result.ok(count);
}

export function vertexCount(this data: Readonly<MeshData>): int32 {
	return (data.vertices.length as int32) / data.stride();
}

export function validIndexStorage(this data: Readonly<MeshData>): boolean {
	return data.indices.length <= 0x7fffffff &&
		(data.wideIndices === null ||
			(data.indices.length == 0 && data.wideIndices.length <= 0x7fffffff));
}

export function indexCount(this data: Readonly<MeshData>): int32 {
	if (!data.validIndexStorage()) {
		console.log("void3d: MeshData has mixed or oversized index storage");
		unreachable;
	}
	if (data.wideIndices !== null) { return data.wideIndices.length as int32; }
	return data.indices.length as int32;
}

export function validIndices(this data: Readonly<MeshData>): boolean {
	if (!data.validIndexStorage() || data.vertices.length > 0x7fffffff ||
		data.vertices.length % data.stride() != 0) { return false; }
	const count: uint32 = data.vertexCount() as uint32;
	for (let i = 0; i < data.indexCount(); i++) {
		const index: uint32 = data.indexAt(i);
		if (index >= count || (data.wideIndices === null && index == 65535)) { return false; }
	}
	return true;
}

export function indexAt(this data: Readonly<MeshData>, index: int32): uint32 {
	if (data.wideIndices !== null) { return data.wideIndices[index]; }
	return data.indices[index] as uint32;
}

export function isIndexed(this data: Readonly<MeshData>): boolean {
	return data.indexCount() > 0;
}

function appendIndex(ref data: MeshData, index: uint32): void {
	if (data.wideIndices === null && index >= 65535) {
		let wide: Vec<uint32> = [];
		for (const previous of data.indices) { wide.push(previous as uint32); }
		data.wideIndices = move wide;
		data.indices = [];
	}
	if (data.wideIndices !== null) { data.wideIndices.push(index); }
	else { data.indices.push(index as uint16); }
}

// h3d.prim.Primitive.triCount: the index count when indexed, the vertex count otherwise.
export function triangleCount(this data: Readonly<MeshData>): int32 {
	if (data.isIndexed()) { return data.indexCount() / 3; }
	return data.vertexCount() / 3;
}

// Appends one vertex and returns its index, growing the bounds.
export function addVertex(
	ref data: MeshData,
	position: Vec3,
	normal: Vec3,
	color: Rgba,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	const index: int32 = data.vertexCount();
	if (!data.hasRoomFor(1)) { return Result.err(MeshError.TooManyVertices); }
	data.vertices.push(position.x);
	data.vertices.push(position.y);
	data.vertices.push(position.z);
	data.vertices.push(normal.x);
	data.vertices.push(normal.y);
	data.vertices.push(normal.z);
	data.vertices.push(color.red);
	data.vertices.push(color.green);
	data.vertices.push(color.blue);
	data.vertices.push(color.alpha);
	addPoint(data.bounds, position);
	return Result.ok(index);
}

export function addTexturedVertex(
	ref data: MeshData,
	position: Vec3,
	normal: Vec3,
	uv: Uv,
	color: Rgba,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (data.hasUvB) { return Result.err(MeshError.UvBAdded); }
	let index: int32 = data.vertexCount();
	if (!data.hasRoomFor(1)) { return Result.err(MeshError.TooManyVertices); }
	data.vertices.push(position.x);
	data.vertices.push(position.y);
	data.vertices.push(position.z);
	data.vertices.push(normal.x);
	data.vertices.push(normal.y);
	data.vertices.push(normal.z);
	data.vertices.push(uv.u);
	data.vertices.push(uv.v);
	data.vertices.push(color.red);
	data.vertices.push(color.green);
	data.vertices.push(color.blue);
	data.vertices.push(color.alpha);
	addPoint(data.bounds, position);
	return Result.ok(index);
}

export function hasRoomFor(this data: MeshData, count: int32): boolean {
	const width: int32 = data.stride();
	return count >= 0 && data.vertices.length <= MAX_MESH_VERTICES &&
		count <= (MAX_MESH_VERTICES - data.vertices.length) / width;
}

// Three vertex indices, counter-clockwise as seen from the front (door.c sets CCW winding).
// Returns the index of the triangle it added, as addVertex returns the index of its vertex.
export function addTriangle(
	ref data: MeshData,
	a: int32,
	b: int32,
	c: int32,
): Result<int32, MeshError> {
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	const count: int32 = data.vertexCount();
	if (a < 0 || b < 0 || c < 0 || a >= count || b >= count || c >= count) {
		return Result.err(MeshError.IndexOutOfRange);
	}
	if (data.indexCount() > 0x7fffffff - 3) { return Result.err(MeshError.DrawRange); }
	appendIndex(data, a as uint32);
	appendIndex(data, b as uint32);
	appendIndex(data, c as uint32);
	return Result.ok(data.triangleCount() - 1);
}

// One flat quad: four vertices sharing a normal and a color, two triangles (a b c, a c d).
// That is the spike's pushQuad with the two shared corners written once instead of twice.
export function addQuad(
	ref data: MeshData,
	a: Vec3,
	b: Vec3,
	c: Vec3,
	d: Vec3,
	normal: Vec3,
	color: Rgba,
): Result<int32, MeshError> {
	if (!data.hasRoomFor(4)) { return Result.err(MeshError.TooManyVertices); }
	const first: int32 = try addVertex(data, a, normal, color);
	const second: int32 = try addVertex(data, b, normal, color);
	const third: int32 = try addVertex(data, c, normal, color);
	const fourth: int32 = try addVertex(data, d, normal, color);
	const _lower: int32 = try addTriangle(data, first, second, third);
	const _upper: int32 = try addTriangle(data, first, third, fourth);
	return Result.ok(first);
}

// addQuad over the whole texture: `a b c d` run counter-clockwise from its bottom left, face on.
export function addTexturedQuad(
	ref data: MeshData,
	a: Vec3,
	b: Vec3,
	c: Vec3,
	d: Vec3,
	normal: Vec3,
	color: Rgba,
): Result<int32, MeshError> {
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (!data.hasRoomFor(4)) { return Result.err(MeshError.TooManyVertices); }
	let first: int32 = try addTexturedVertex(data, a, normal, { u: 0.0, v: 1.0 }, color);
	let second: int32 = try addTexturedVertex(data, b, normal, { u: 1.0, v: 1.0 }, color);
	let third: int32 = try addTexturedVertex(data, c, normal, { u: 1.0, v: 0.0 }, color);
	let fourth: int32 = try addTexturedVertex(data, d, normal, { u: 0.0, v: 0.0 }, color);
	let _lower: int32 = try addTriangle(data, first, second, third);
	let _upper: int32 = try addTriangle(data, first, third, fourth);
	return Result.ok(first);
}

// h3d.prim.Polygon.addTangents' place, deriving the tangents glTF asks a loader to generate when
// a file has none (2.0 section 3.7.2.1): MikkTSpace per triangle corner, then welded back. Its
// header forbids averaging corners through the existing index list, so a vertex whose corners
// disagree is split, the copy appended and those corners re-pointed: three.js' de-indexed result
// with its duplicates shared. w is glTF's, the negated MikkTSpace sign (three.js negateSign, Bevy).
export function addTangents(ref data: MeshData): Result<int32, MeshError> {
	let sources: Vec<int32> = [];
	return addTangentsWithSources(data, sources);
}

export function addTangentsWithSources(
	ref data: MeshData,
	ref appendedSources: Vec<int32>,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (data.hasUvB) { return Result.err(MeshError.UvBAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	const count: int32 = data.vertexCount();
	const cornerCount: int32 = data.triangleCount() * 3;
	if (cornerCount > 0x7fffffff / 4) { return Result.err(MeshError.TooManyVertices); }
	for (let i = 0; i < data.indexCount(); i++) {
		if (data.indexAt(i) >= (count as uint32)) {
			return Result.err(MeshError.IndexOutOfRange);
		}
	}
	let corners: Vec<float32> = new Array(cornerCount * 4);
	if (data.mikkCorners(corners) == 0) {
		console.log("void3d: addTangents: MikkTSpace could not allocate its working arrays");
		unreachable;
	}
	const indexed: boolean = data.isIndexed();
	let tangents: Vec<float32> = new Array(count * 4);
	let filled: Vec<uint8> = new Array(count);
	let nextSplit: Vec<int32> = new Array(count);
	let sources: Vec<int32> = [];
	let remapped = MeshData.empty();
	if (data.wideIndices !== null) { remapped.wideIndices = []; }
	for (let corner = 0; corner < cornerCount; corner++) {
		const vertex: int32 = indexed ? (data.indexAt(corner) as int32) : corner;
		let at: int32 = vertex;
		if (filled[vertex] == 0) {
			filled[vertex] = 1;
			for (let k = 0; k < 4; k++) { tangents[vertex * 4 + k] = corners[corner * 4 + k]; }
		} else {
			while (!sameTangent(tangents, at, corners, corner) && nextSplit[at] != 0) {
				at = nextSplit[at] - 1;
			}
			if (!sameTangent(tangents, at, corners, corner)) {
				const split: int32 = count + (sources.length as int32);
				if (split >= MAX_MESH_VERTICES / LIT_TEXTURED_TANGENT_VERTEX_STRIDE) {
					return Result.err(MeshError.TooManyVertices);
				}
				nextSplit[at] = split + 1;
				nextSplit.push(0);
				sources.push(vertex);
				for (let k = 0; k < 4; k++) { tangents.push(corners[corner * 4 + k]); }
				at = split;
			}
		}
		if (indexed) { appendIndex(remapped, at as uint32); }
	}
	for (let i = 0; i < count; i++) {
		if (filled[i] != 0) { continue; }
		const base: int32 = i * LIT_TEXTURED_VERTEX_STRIDE;
		const normal: Vec3 =
			vec3(data.vertices[base + 3], data.vertices[base + 4], data.vertices[base + 5]);
		const along: Vec3 = orthogonalTangent(normal, vec3(0.0, 0.0, 0.0));
		tangents[i * 4] = along.x;
		tangents[i * 4 + 1] = along.y;
		tangents[i * 4 + 2] = along.z;
		tangents[i * 4 + 3] = 1.0;
	}
	if (indexed) {
		for (let i = cornerCount; i < data.indexCount(); i++) {
			appendIndex(remapped, data.indexAt(i));
		}
	}
	const total: int32 = try interleaveTangents(data, tangents, sources);
	if (indexed) {
		data.indices = move remapped.indices;
		data.wideIndices = move remapped.wideIndices;
	}
	appendedSources = move sources;
	return Result.ok(total);
}

function mikkCorners(this data: Readonly<MeshData>, corners: Span<float32>): int32 {
	if (data.wideIndices !== null) {
		return void3dMikkTangents32(
			data.vertices, LIT_TEXTURED_VERTEX_STRIDE, data.wideIndices, corners,
		);
	}
	return void3dMikkTangents(data.vertices, LIT_TEXTURED_VERTEX_STRIDE, data.indices, corners);
}

function sameTangent(
	tangents: Readonly<Span<float32>>,
	vertex: int32,
	corners: Readonly<Span<float32>>,
	corner: int32,
): boolean {
	for (let k = 0; k < 4; k++) {
		if (tangents[vertex * 4 + k] != corners[corner * 4 + k]) { return false; }
	}
	return true;
}

// The same closing step with the tangents a file carries (glTF's TANGENT: xyz and w, four floats
// per vertex, in vertex order) instead of the ones addTangents derives.
export function addGivenTangents(
	ref data: MeshData,
	tangents: Readonly<Span<float32>>,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (data.hasUvB) { return Result.err(MeshError.UvBAdded); }
	if ((tangents.length as int32) != data.vertexCount() * 4) {
		return Result.err(MeshError.TangentCount);
	}
	return interleaveTangents(data, tangents, []);
}

// Each vertex followed by its tangent; a vertex past the original count is a copy of its source.
function interleaveTangents(
	ref data: MeshData,
	tangents: Readonly<Span<float32>>,
	sources: Readonly<Span<int32>>,
): Result<int32, MeshError> {
	const count: int32 = data.vertexCount();
	const total: int32 = count + (sources.length as int32);
	if (total > MAX_MESH_VERTICES / LIT_TEXTURED_TANGENT_VERTEX_STRIDE) {
		return Result.err(MeshError.TooManyVertices);
	}
	let vertices: Vec<float32> = [];
	for (let i = 0; i < total; i++) {
		const source: int32 = i < count ? i : sources[i - count];
		const base: int32 = source * LIT_TEXTURED_VERTEX_STRIDE;
		for (let k = 0; k < LIT_TEXTURED_VERTEX_STRIDE; k++) {
			vertices.push(data.vertices[base + k]);
		}
		for (let k = 0; k < 4; k++) { vertices.push(tangents[i * 4 + k]); }
	}
	data.vertices = vertices;
	data.hasTangents = true;
	return Result.ok(total);
}

// Gram-Schmidt against the normal; a vertex no triangle gave a direction takes any unit vector
// perpendicular to its normal.
function orthogonalTangent(normal: Vec3, tangent: Vec3): Vec3 {
	const along: Vec3 = tangent - normal.scaled(normal.dot(tangent));
	if (along.lengthSquared() > 1e-12) { return along.normalized(); }
	const axis: Vec3 = normal.x * normal.x < 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	return (axis - normal.scaled(normal.dot(axis))).normalized();
}

const FLOAT32_MAX: float64 = 3.4028234663852886e38;

function coordinateInRange(value: float64): boolean {
	return value >= -FLOAT32_MAX && value <= FLOAT32_MAX;
}

// Gives every triangle corner a vertex of its own and drops the indices, Bevy's
// `Mesh::duplicate_vertices`; `sources` receives the vertex each new one copies.
export function duplicateVertices(
	ref data: MeshData,
	ref sources: Vec<int32>,
): Result<void, MeshError> {
	if (!data.validIndices()) { return Result.err(MeshError.IndexOutOfRange); }
	const width: int32 = data.stride();
	const corners: int32 = data.triangleCount() * 3;
	if (corners > MAX_MESH_VERTICES / width) { return Result.err(MeshError.TooManyVertices); }
	const indexed: boolean = data.isIndexed();
	let vertices: Vec<float32> = [];
	for (let corner = 0; corner < corners; corner++) {
		const vertex: int32 = indexed ? data.indexAt(corner) as int32 : corner;
		sources.push(vertex);
		for (let k = 0; k < width; k++) { vertices.push(data.vertices[vertex * width + k]); }
	}
	data.vertices = move vertices;
	data.indices = [];
	data.wideIndices = null;
	recomputeBounds(data);
	return Result.ok(null);
}

export function recomputeNormals(ref data: MeshData): Result<void, MeshError> {
	const width: int32 = data.stride();
	if (data.vertices.length > MAX_MESH_VERTICES || data.vertices.length % width != 0) {
		return Result.err(MeshError.VertexStorage);
	}
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (!data.validIndices()) { return Result.err(MeshError.IndexOutOfRange); }
	for (let at = 0; at < data.vertices.length; at += width) {
		if (!Number.isFinite(data.vertices[at]) || !Number.isFinite(data.vertices[at + 1])
			|| !Number.isFinite(data.vertices[at + 2])) {
			return Result.err(MeshError.PositionRange);
		}
	}
	const count: int32 = data.vertexCount();
	let normals: Vec<float64> = new Array(count * 3);
	const indexed: boolean = data.isIndexed();
	const faces: int32 = data.triangleCount();
	for (let face = 0; face < faces; face++) {
		const corner: int32 = face * 3;
		const a: int32 = indexed ? data.indexAt(corner) as int32 : corner;
		const b: int32 = indexed ? data.indexAt(corner + 1) as int32 : corner + 1;
		const c: int32 = indexed ? data.indexAt(corner + 2) as int32 : corner + 2;
		const at: int32 = a * width;
		const bt: int32 = b * width;
		const ct: int32 = c * width;
		const ux: float64 = (data.vertices[bt] as float64) - (data.vertices[at] as float64);
		const uy: float64 = (data.vertices[bt + 1] as float64) - (data.vertices[at + 1] as float64);
		const uz: float64 = (data.vertices[bt + 2] as float64) - (data.vertices[at + 2] as float64);
		const vx: float64 = (data.vertices[ct] as float64) - (data.vertices[at] as float64);
		const vy: float64 = (data.vertices[ct + 1] as float64) - (data.vertices[at + 1] as float64);
		const vz: float64 = (data.vertices[ct + 2] as float64) - (data.vertices[at + 2] as float64);
		const nx: float64 = uy * vz - uz * vy;
		const ny: float64 = uz * vx - ux * vz;
		const nz: float64 = ux * vy - uy * vx;
		for (let vertex = 0; vertex < 3; vertex++) {
			const normalAt: int32 = (vertex == 0 ? a : (vertex == 1 ? b : c)) * 3;
			normals[normalAt] += nx;
			normals[normalAt + 1] += ny;
			normals[normalAt + 2] += nz;
		}
	}
	for (let vertex = 0; vertex < count; vertex++) {
		const normalAt: int32 = vertex * 3;
		const nx: float64 = normals[normalAt];
		const ny: float64 = normals[normalAt + 1];
		const nz: float64 = normals[normalAt + 2];
		const squared: float64 = nx * nx + ny * ny + nz * nz;
		const inverse: float64 = squared < 1.0e-20 ? 0.0 : 1.0 / Math.sqrt(squared);
		const at: int32 = vertex * width;
		data.vertices[at + 3] = (nx * inverse) as float32;
		data.vertices[at + 4] = (ny * inverse) as float32;
		data.vertices[at + 5] = (nz * inverse) as float32;
	}
	return Result.ok(null);
}

export function translate(ref data: MeshData, offset: Vec3): Result<void, MeshError> {
	const width: int32 = data.stride();
	if (data.vertices.length > MAX_MESH_VERTICES || data.vertices.length % width != 0) {
		return Result.err(MeshError.VertexStorage);
	}
	if (!Number.isFinite(offset.x) || !Number.isFinite(offset.y) || !Number.isFinite(offset.z)) {
		return Result.err(MeshError.TranslationOffset);
	}
	for (let at = 0; at < data.vertices.length; at += width) {
		const x: float64 = (data.vertices[at] as float64) + (offset.x as float64);
		const y: float64 = (data.vertices[at + 1] as float64) + (offset.y as float64);
		const z: float64 = (data.vertices[at + 2] as float64) + (offset.z as float64);
		if (!coordinateInRange(x) || !coordinateInRange(y) || !coordinateInRange(z)) {
			return Result.err(MeshError.PositionRange);
		}
	}
	for (let at = 0; at < data.vertices.length; at += width) {
		data.vertices[at] = ((data.vertices[at] as float64) + (offset.x as float64)) as float32;
		data.vertices[at + 1] =
			((data.vertices[at + 1] as float64) + (offset.y as float64)) as float32;
		data.vertices[at + 2] =
			((data.vertices[at + 2] as float64) + (offset.z as float64)) as float32;
	}
	recomputeBounds(data);
	return Result.ok(null);
}

export function scaleUniform(ref data: MeshData, factor: float32): Result<void, MeshError> {
	const width: int32 = data.stride();
	if (data.vertices.length > MAX_MESH_VERTICES || data.vertices.length % width != 0) {
		return Result.err(MeshError.VertexStorage);
	}
	if (!Number.isFinite(factor)) { return Result.err(MeshError.ScaleParameters); }
	for (let at = 0; at < data.vertices.length; at += width) {
		const x: float64 = (data.vertices[at] as float64) * (factor as float64);
		const y: float64 = (data.vertices[at + 1] as float64) * (factor as float64);
		const z: float64 = (data.vertices[at + 2] as float64) * (factor as float64);
		if (!coordinateInRange(x) || !coordinateInRange(y) || !coordinateInRange(z)) {
			return Result.err(MeshError.PositionRange);
		}
	}
	for (let at = 0; at < data.vertices.length; at += width) {
		data.vertices[at] = ((data.vertices[at] as float64) * (factor as float64)) as float32;
		data.vertices[at + 1] =
			((data.vertices[at + 1] as float64) * (factor as float64)) as float32;
		data.vertices[at + 2] =
			((data.vertices[at + 2] as float64) * (factor as float64)) as float32;
	}
	recomputeBounds(data);
	return Result.ok(null);
}

export function scaleUvs(ref data: MeshData, su: float32, sv: float32): Result<void, MeshError> {
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	const width: int32 = data.stride();
	if (data.vertices.length > MAX_MESH_VERTICES || data.vertices.length % width != 0) {
		return Result.err(MeshError.VertexStorage);
	}
	if (!Number.isFinite(su) || !Number.isFinite(sv)) {
		return Result.err(MeshError.UvScaleParameters);
	}
	for (let at = 0; at < data.vertices.length; at += width) {
		const u: float64 = (data.vertices[at + 6] as float64) * (su as float64);
		const v: float64 = (data.vertices[at + 7] as float64) * (sv as float64);
		if (!coordinateInRange(u) || !coordinateInRange(v)) {
			return Result.err(MeshError.UvRange);
		}
	}
	for (let at = 0; at < data.vertices.length; at += width) {
		data.vertices[at + 6] = ((data.vertices[at + 6] as float64) * (su as float64)) as float32;
		data.vertices[at + 7] = ((data.vertices[at + 7] as float64) * (sv as float64)) as float32;
	}
	return Result.ok(null);
}

// Recomputes the bounds from the vertices, h3d.prim.Polygon.getBounds. The builders keep the
// bounds current, so this is for a caller that edited `vertices` itself — a vertex-baked
// animation frame (M9) swapping positions under a mesh that keeps its indices.
export function recomputeBounds(ref data: MeshData): void {
	let box: Bounds3D = Bounds3D.empty();
	const count: int32 = data.vertexCount();
	for (let i = 0; i < count; i++) {
		const base: int32 = i * data.stride();
		addPoint(box, vec3(data.vertices[base], data.vertices[base + 1], data.vertices[base + 2]));
	}
	data.bounds = box;
}

// PENDING3D: pick-culling-follows-material
export function rayIntersection(
	this data: Readonly<MeshData>, ray: Ray, culling: Face,
): MeshRayHit {
	return intersectTriangles(data, ray, culling, 0, data.triangleCount());
}

export function rayIntersectionElements(
	this data: Readonly<MeshData>, ray: Ray, culling: Face, base: int32, count: int32,
): Result<MeshRayHit, MeshError> {
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.indices.length > 0x7fffffff || data.vertices.length > 0x7fffffff ||
		(data.wideIndices !== null && data.wideIndices.length > 0x7fffffff)) {
		return Result.err(MeshError.DrawRange);
	}
	const total: int32 = data.isIndexed() ? data.indexCount() : data.vertexCount();
	if (base < 0 || count < 0 || base % 3 != 0 || count % 3 != 0 ||
		base > total || count > total - base) {
		return Result.err(MeshError.DrawRange);
	}
	return Result.ok(intersectTriangles(data, ray, culling, base / 3, count / 3));
}

function intersectTriangles(
	data: Readonly<MeshData>, ray: Ray, culling: Face, first: int32, count: int32,
): MeshRayHit {
	let best: float32 = -1.0;
	let hitTriangle: int32 = -1;
	let hitU: float32 = 0.0;
	let hitV: float32 = 0.0;
	for (let triangle = first; triangle < first + count; triangle++) {
		const p0: Vec3 = data.cornerOf(triangle, 0);
		const edge1: Vec3 = data.cornerOf(triangle, 1) - p0;
		const edge2: Vec3 = data.cornerOf(triangle, 2) - p0;
		const p: Vec3 = ray.direction.cross(edge2);
		const det: float32 = edge1.dot(p);
		if (!facesKept(det, culling)) { continue; }
		const inverseDet: float32 = 1.0 / det;
		const fromCorner: Vec3 = ray.origin - p0;
		const u: float32 = fromCorner.dot(p) * inverseDet;
		if (u < 0.0 || u > 1.0) { continue; }
		const q: Vec3 = fromCorner.cross(edge1);
		const v: float32 = ray.direction.dot(q) * inverseDet;
		if (v < 0.0 || u + v > 1.0) { continue; }
		const distance: float32 = edge2.dot(q) * inverseDet;
		if (distance < RAY_EPSILON) { continue; }
		if (best < 0.0 || distance < best) {
			best = distance;
			hitTriangle = triangle;
			hitU = u;
			hitV = v;
		}
	}
	return {
		distance: best,
		uv: hitTriangle >= 0 && data.hasUvs ? data.interpolateUv(hitTriangle, hitU, hitV) : null,
	};
}

function interpolateUv(this data: Readonly<MeshData>, triangle: int32, u: float32, v: float32): Uv {
	const at: int32 = triangle * 3;
	const stride: int32 = data.stride();
	const indexed: boolean = data.isIndexed();
	const a: int32 = (indexed ? (data.indexAt(at) as int32) : at) * stride + 6;
	const b: int32 = (indexed ? (data.indexAt(at + 1) as int32) : at + 1) * stride + 6;
	const c: int32 = (indexed ? (data.indexAt(at + 2) as int32) : at + 2) * stride + 6;
	const w: float32 = 1.0 - u - v;
	return {
		u: data.vertices[a] * w + data.vertices[b] * u + data.vertices[c] * v,
		v: data.vertices[a + 1] * w + data.vertices[b + 1] * u + data.vertices[c + 1] * v,
	};
}

// hxd.Math.EPSILON.
const RAY_EPSILON: float32 = 1e-10;

function facesKept(det: float32, culling: Face): boolean {
	return match (culling) {
		Face.Back => det >= RAY_EPSILON,
		Face.Front => det <= -RAY_EPSILON,
		Face.None => det >= RAY_EPSILON || det <= -RAY_EPSILON,
	};
}

function cornerOf(this data: Readonly<MeshData>, triangle: int32, corner: int32): Vec3 {
	const at: int32 = triangle * 3 + corner;
	const vertex: int32 = data.isIndexed() ? (data.indexAt(at) as int32) : at;
	const base: int32 = vertex * data.stride();
	return vec3(data.vertices[base], data.vertices[base + 1], data.vertices[base + 2]);
}

// ---- builders --------------------------------------------------------------------------
//
// A box standing on its base, turned by `yaw` about Y and leaned by `tilt` about X, in the
// role of h3d.prim.Cube. Heaps builds a cube at the origin and moves it with `translate` /
// `scale`; here the placement is baked into the vertices, because until M6 gives every mesh
// an Object3D the programs take world-space positions and there is no model matrix to put it
// in (draw.ms, DrawItem.world). The arithmetic is the spike's, moved rather than rewritten —
// the same term order, and the same `sinf`/`cosf` — so the vertex floats are bit-identical to
// the pre-M5 images and `meshDataCheck.ms` pins a few of them to literals. M6 is where the
// placement becomes a node transform and this becomes a plain unit box.
// Five quads of four vertices: what addBox appends when it succeeds.
export const BOX_VERTICES: int32 = 20;

export struct Box {
	base: Vec3;
	size: Vec3;
	yaw: float32;
	tilt: float32;
	color: Rgba;
}

struct BoxFrame {
	base: Vec3;
	yawSin: float32;
	yawCos: float32;
	tiltSin: float32;
	tiltCos: float32;
}

function toWorld(this frame: BoxFrame, local: Vec3): Vec3 {
	const tiltedY: float32 = local.y * frame.tiltCos - local.z * frame.tiltSin;
	const tiltedZ: float32 = local.y * frame.tiltSin + local.z * frame.tiltCos;
	return {
		x: frame.base.x + local.x * frame.yawCos + tiltedZ * frame.yawSin,
		y: frame.base.y + tiltedY,
		z: frame.base.z - local.x * frame.yawSin + tiltedZ * frame.yawCos,
	};
}

function rotate(this frame: BoxFrame, direction: Vec3): Vec3 {
	const origin: Vec3 = vec3(0.0, 0.0, 0.0);
	const unplaced: BoxFrame = { ...frame, base: origin };
	return unplaced.toWorld(direction);
}

// Five quads: the top and the four sides. The underside is never seen from above the ground
// plane, and leaving it out is what the spike did — 20 vertices and 30 indices per box.
export function addBox(ref data: MeshData, box: Box): Result<int32, MeshError> {
	if (!data.hasRoomFor(BOX_VERTICES)) { return Result.err(MeshError.TooManyVertices); }
	const frame: BoxFrame = {
		base: box.base,
		yawSin: sinf(box.yaw),
		yawCos: cosf(box.yaw),
		tiltSin: sinf(box.tilt),
		tiltCos: cosf(box.tilt),
	};
	const half: float32 = 0.5;
	const halfX: float32 = box.size.x * half;
	const halfZ: float32 = box.size.z * half;
	const top: float32 = box.size.y;
	const leftBottomBack: Vec3 = frame.toWorld(vec3(-halfX, 0.0, -halfZ));
	const rightBottomBack: Vec3 = frame.toWorld(vec3(halfX, 0.0, -halfZ));
	const leftBottomFront: Vec3 = frame.toWorld(vec3(-halfX, 0.0, halfZ));
	const rightBottomFront: Vec3 = frame.toWorld(vec3(halfX, 0.0, halfZ));
	const leftTopBack: Vec3 = frame.toWorld(vec3(-halfX, top, -halfZ));
	const rightTopBack: Vec3 = frame.toWorld(vec3(halfX, top, -halfZ));
	const leftTopFront: Vec3 = frame.toWorld(vec3(-halfX, top, halfZ));
	const rightTopFront: Vec3 = frame.toWorld(vec3(halfX, top, halfZ));
	const color: Rgba = box.color;

	const first: int32 = try addQuad(
		data, leftTopBack, leftTopFront, rightTopFront, rightTopBack,
		frame.rotate(vec3(0.0, 1.0, 0.0)), color,
	);
	const _right: int32 = try addQuad(
		data, rightBottomBack, rightTopBack, rightTopFront, rightBottomFront,
		frame.rotate(vec3(1.0, 0.0, 0.0)), color,
	);
	const _left: int32 = try addQuad(
		data, leftBottomFront, leftTopFront, leftTopBack, leftBottomBack,
		frame.rotate(vec3(-1.0, 0.0, 0.0)), color,
	);
	const _front: int32 = try addQuad(
		data, leftBottomFront, rightBottomFront, rightTopFront, leftTopFront,
		frame.rotate(vec3(0.0, 0.0, 1.0)), color,
	);
	const _back: int32 = try addQuad(
		data, rightBottomBack, leftBottomBack, leftTopBack, rightTopBack,
		frame.rotate(vec3(0.0, 0.0, -1.0)), color,
	);
	return Result.ok(first);
}

// One quad in the XZ plane at y = 0, facing up: h3d.prim.Plane2D turned into the ground plane
// this renderer's Y-up world wants. `halfSize` is half its edge, so the plane spans
// [-halfSize, halfSize] on both axes.
export function addPlane(
	ref data: MeshData,
	halfSize: float32,
	color: Rgba,
): Result<int32, MeshError> {
	return addQuad(
		data,
		vec3(-halfSize, 0.0, -halfSize),
		vec3(-halfSize, 0.0, halfSize),
		vec3(halfSize, 0.0, halfSize),
		vec3(halfSize, 0.0, -halfSize),
		vec3(0.0, 1.0, 0.0),
		color,
	);
}

export function addSphere(
	ref data: MeshData,
	radius: float32,
	color: Rgba,
	sectors: int32,
	stacks: int32,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	if (radius <= 0.0 || radius - radius != 0.0 || sectors < 3 || stacks < 2) {
		return Result.err(MeshError.SphereParameters);
	}
	const vertices: int64 = ((sectors as int64) + 1) * ((stacks as int64) + 1);
	if (vertices > (MAX_MESH_VERTICES as int64) || !data.hasRoomFor(vertices as int32)) {
		return Result.err(MeshError.TooManyVertices);
	}
	const corners: int64 = (sectors as int64) * ((stacks as int64) - 1) * 6;
	if (corners > (0x7fffffff as int64) - (data.indexCount() as int64)) {
		return Result.err(MeshError.DrawRange);
	}
	const first: int32 = data.vertexCount();
	const pi: float32 = 3.141592653589793;
	for (let y = 0; y <= stacks; y++) {
		const latitude: float32 = pi * (y as float32) / (stacks as float32);
		const radial: float32 = y == 0 || y == stacks ? 0.0 : sinf(latitude);
		const vertical: float32 = y == 0 ? 1.0 : (y == stacks ? -1.0 : cosf(latitude));
		for (let x = 0; x <= sectors; x++) {
			const longitude: float32 = x == sectors ? 0.0
				: 2.0 * pi * (x as float32) / (sectors as float32);
			const normal: Vec3 = vec3(radial * cosf(longitude), vertical, radial * sinf(longitude));
			const added = data.hasUvs ? addTexturedVertex(data, normal.scaled(radius), normal,
				{ u: 1.0 - (x as float32) / (sectors as float32),
					v: (y as float32) / (stacks as float32) }, color)
				: addVertex(data, normal.scaled(radius), normal, color);
			if (!added.ok) { return Result.err(added.error); }
		}
	}
	for (let y = 0; y < stacks; y++) {
		for (let x = 0; x < sectors; x++) {
			const v2: int32 = first + x + y * (sectors + 1);
			const v1: int32 = v2 + 1;
			const v3: int32 = v2 + sectors + 1;
			const v4: int32 = v3 + 1;
			if (y != 0) { const _top = try addTriangle(data, v1, v4, v2); }
			if (y != stacks - 1) { const _bottom = try addTriangle(data, v2, v4, v3); }
		}
	}
	return Result.ok(first);
}

export function addCylinderSides(
	ref data: MeshData,
	radius: float32,
	height: float32,
	centered: boolean,
	color: Rgba,
	sectors: int32,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	if (radius <= 0.0 || radius - radius != 0.0 || height <= 0.0
		|| height - height != 0.0 || sectors < 3) {
		return Result.err(MeshError.CylinderParameters);
	}
	const vertices: int64 = (sectors as int64) * 4;
	if (vertices > (MAX_MESH_VERTICES as int64) || !data.hasRoomFor(vertices as int32)) {
		return Result.err(MeshError.TooManyVertices);
	}
	if ((sectors as int64) * 6 > (0x7fffffff as int64) - (data.indexCount() as int64)) {
		return Result.err(MeshError.DrawRange);
	}
	const first: int32 = data.vertexCount();
	const low: float32 = centered ? -height * 0.5 : 0.0;
	const high: float32 = centered ? height * 0.5 : height;
	const turn: float32 = 6.283185307179586;
	for (let s = 0; s < sectors; s++) {
		for (let corner = 0; corner < 4; corner++) {
			const segment: int32 = s + corner % 2;
			const angle: float32 = segment == sectors ? 0.0
				: turn * (segment as float32) / (sectors as float32);
			const normal: Vec3 = vec3(cosf(angle), 0.0, sinf(angle));
			const point: Vec3 = vec3(normal.x * radius, corner < 2 ? low : high, normal.z * radius);
			const added = data.hasUvs ? addTexturedVertex(data, point, normal,
				{ u: 1.0 - (segment as float32) / (sectors as float32),
					v: corner < 2 ? 1.0 : 0.0 }, color)
				: addVertex(data, point, normal, color);
			if (!added.ok) { return Result.err(added.error); }
		}
		const base: int32 = first + s * 4;
		const _first = try addTriangle(data, base, base + 2, base + 1);
		const _second = try addTriangle(data, base + 2, base + 3, base + 1);
	}
	return Result.ok(first);
}

export function addDisc(
	ref data: MeshData,
	radius: float32,
	color: Rgba,
	segments: int32,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	if (radius <= 0.0 || radius - radius != 0.0 || segments < 3) {
		return Result.err(MeshError.DiscParameters);
	}
	const vertices: int64 = (segments as int64) + 1;
	if (vertices > (MAX_MESH_VERTICES as int64) || !data.hasRoomFor(vertices as int32)) {
		return Result.err(MeshError.TooManyVertices);
	}
	if ((segments as int64) * 3 > (0x7fffffff as int64) - (data.indexCount() as int64)) {
		return Result.err(MeshError.DrawRange);
	}
	const first: int32 = data.vertexCount();
	const turn: float32 = 6.283185307179586;
	const normal: Vec3 = vec3(0.0, 1.0, 0.0);
	for (let i = 0; i <= segments; i++) {
		const angle: float32 = turn * (i as float32) / (segments as float32);
		const radial: float32 = i == segments ? 0.0 : radius;
		const point: Vec3 = vec3(radial * cosf(angle), 0.0, radial * sinf(angle));
		const added = data.hasUvs ? addTexturedVertex(data, point, normal,
			{ u: (point.x / radius + 1.0) * 0.5, v: (point.z / radius + 1.0) * 0.5 }, color)
			: addVertex(data, point, normal, color);
		if (!added.ok) { return Result.err(added.error); }
	}
	for (let i = 0; i < segments; i++) {
		const _triangle = try addTriangle(data, first + i, first + segments,
			first + (i + 1) % segments);
	}
	return Result.ok(first);
}

export function addCapsuleY(
	ref data: MeshData,
	radius: float32,
	length: float32,
	color: Rgba,
	segments: int32,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	const extent: float32 = radius + length * 0.5;
	if (radius <= 0.0 || radius - radius != 0.0 || length < 0.0 || length - length != 0.0
		|| extent - extent != 0.0 || segments < 3) {
		return Result.err(MeshError.CapsuleParameters);
	}
	const ring: int64 = (segments as int64) + 1;
	const square: int64 = ring * ring;
	if (square > (MAX_MESH_VERTICES as int64) / 2) {
		return Result.err(MeshError.TooManyVertices);
	}
	const vertices: int64 = 2 * square + (segments as int64) * 4 + 2;
	if (vertices > (MAX_MESH_VERTICES as int64) || !data.hasRoomFor(vertices as int32)) {
		return Result.err(MeshError.TooManyVertices);
	}
	if ((segments as int64) * (segments as int64) * 12
		> (0x7fffffff as int64) - (data.indexCount() as int64)) {
		return Result.err(MeshError.DrawRange);
	}
	const first: int32 = data.vertexCount();
	const pi: float32 = 3.141592653589793;
	const halfLength: float32 = length * 0.5;
	for (let half = 0; half < 2; half++) {
		const offset: float32 = half == 0 ? halfLength : -halfLength;
		const phase: float32 = half == 0 ? pi * 0.5 : -pi * 0.5;
		const base: int32 = data.vertexCount();
		for (let y = 0; y <= segments; y++) {
			const latitude: float32 = pi * (y as float32) / (segments as float32);
			const radial: float32 = y == 0 || y == segments ? 0.0 : sinf(latitude);
			const vertical: float32 = y == 0 ? 1.0 : (y == segments ? -1.0 : cosf(latitude));
			for (let x = 0; x <= segments; x++) {
				const longitude: float32 = phase + pi * (x as float32) / (segments as float32);
				const edge: boolean = x == 0 || x == segments;
				const c: float32 = edge ? 0.0 : cosf(longitude);
				const s: float32 = edge ? ((x == 0) == (half == 0) ? 1.0 : -1.0)
					: sinf(longitude);
				const normal: Vec3 = vec3(vertical, -radial * c, radial * s);
				const _vertex = try addVertex(data,
					normal.scaled(radius) + vec3(0.0, offset, 0.0), normal, color);
			}
		}
		for (let y = 0; y < segments; y++) {
			for (let x = 0; x < segments; x++) {
				const v2: int32 = base + x + y * (segments + 1);
				const v1: int32 = v2 + 1;
				const v3: int32 = v2 + segments + 1;
				const v4: int32 = v3 + 1;
				if (y != 0) { const _a = try addTriangle(data, v1, v4, v2); }
				if (y != segments - 1) { const _b = try addTriangle(data, v2, v4, v3); }
			}
		}
	}
	const base: int32 = data.vertexCount();
	for (let y = 0; y <= segments * 2; y++) {
		const angle: float32 = y == segments * 2 ? 0.0
			: pi * (y as float32) / (segments as float32);
		const normal: Vec3 = vec3(cosf(angle), 0.0, sinf(angle));
		const _a = try addVertex(data,
			vec3(normal.x * radius, halfLength, normal.z * radius), normal, color);
		const _b = try addVertex(data,
			vec3(normal.x * radius, -halfLength, normal.z * radius), normal, color);
	}
	for (let y = 0; y < segments * 2; y++) {
		const v0: int32 = base + y * 2;
		const _a = try addTriangle(data, v0, v0 + 2, v0 + 1);
		const _b = try addTriangle(data, v0 + 1, v0 + 2, v0 + 3);
	}
	return Result.ok(first);
}

export function addGrid(
	ref data: MeshData,
	columns: int32,
	rows: int32,
	cellWidth: float32,
	cellDepth: float32,
	color: Rgba,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	const extentX: float32 = cellWidth * (columns as float32);
	const extentZ: float32 = cellDepth * (rows as float32);
	if (columns < 1 || rows < 1 || cellWidth <= 0.0 || cellDepth <= 0.0
		|| extentX - extentX != 0.0 || extentZ - extentZ != 0.0) {
		return Result.err(MeshError.GridParameters);
	}
	const vertices: int64 = ((columns as int64) + 1) * ((rows as int64) + 1);
	if (vertices > (MAX_MESH_VERTICES as int64) || !data.hasRoomFor(vertices as int32)) {
		return Result.err(MeshError.TooManyVertices);
	}
	if ((columns as int64) * (rows as int64) * 6
		> (0x7fffffff as int64) - (data.indexCount() as int64)) {
		return Result.err(MeshError.DrawRange);
	}
	const first: int32 = data.vertexCount();
	const normal: Vec3 = vec3(0.0, 1.0, 0.0);
	for (let y = 0; y <= rows; y++) {
		for (let x = 0; x <= columns; x++) {
			const point: Vec3 = vec3((x as float32) * cellWidth, 0.0, (y as float32) * cellDepth);
			const added = data.hasUvs ? addTexturedVertex(data, point, normal,
				{ u: (x as float32) / (columns as float32),
					v: (y as float32) / (rows as float32) }, color)
				: addVertex(data, point, normal, color);
			if (!added.ok) { return Result.err(added.error); }
		}
	}
	for (let y = 0; y < rows; y++) {
		for (let x = 0; x < columns; x++) {
			const a: int32 = first + x + y * (columns + 1);
			const b: int32 = a + 1;
			const c: int32 = a + columns + 1;
			const _first = try addTriangle(data, a, c, b);
			const _second = try addTriangle(data, b, c, c + 1);
		}
	}
	return Result.ok(first);
}

export function addGeoSphere(
	ref data: MeshData,
	radius: float32,
	color: Rgba,
	subdivisions: int32,
): Result<int32, MeshError> {
	if (data.hasSkin) { return Result.err(MeshError.SkinAdded); }
	if (data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (data.hasTangents) { return Result.err(MeshError.TangentsAdded); }
	if (!data.validIndexStorage()) { return Result.err(MeshError.IndexStorage); }
	if (data.vertexCount() > 0 && !data.isIndexed()) {
		return Result.err(MeshError.UnindexedAppend);
	}
	if (radius <= 0.0 || radius - radius != 0.0 || subdivisions < 0) {
		return Result.err(MeshError.GeoSphereParameters);
	}
	let plannedVertices: int64 = 6;
	let plannedTriangles: int64 = 8;
	for (let level = 0; level <= subdivisions; level++) {
		if (plannedVertices > (MAX_MESH_VERTICES as int64)
			|| !data.hasRoomFor(plannedVertices as int32)) {
			return Result.err(MeshError.TooManyVertices);
		}
		if (plannedTriangles * 3 > (0x7fffffff as int64) - (data.indexCount() as int64)) {
			return Result.err(MeshError.DrawRange);
		}
		if (level != subdivisions) {
			plannedVertices += plannedTriangles * 3;
			plannedTriangles *= 4;
		}
	}
	const diagonal: float32 = 0.7071067811865476;
	let points: Vec<Vec3> = [
		vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0),
		vec3(-diagonal, 0.0, -diagonal), vec3(diagonal, 0.0, -diagonal),
		vec3(diagonal, 0.0, diagonal), vec3(-diagonal, 0.0, diagonal),
	];
	let faces: Vec<int32> = [
		0, 3, 4, 0, 4, 5, 0, 5, 2, 0, 2, 3,
		1, 4, 3, 1, 5, 4, 1, 2, 5, 1, 3, 2,
	];
	for (let level = 0; level < subdivisions; level++) {
		let next: Vec<int32> = [];
		for (let i = 0; i < faces.length; i += 3) {
			const a: int32 = faces[i];
			const b: int32 = faces[i + 1];
			const c: int32 = faces[i + 2];
			const start: int32 = points.length as int32;
			points.push((points[a] + points[b]).normalized());
			points.push((points[b] + points[c]).normalized());
			points.push((points[c] + points[a]).normalized());
			next.push(start);
			next.push(start + 1);
			next.push(start + 2);
			next.push(a);
			next.push(start);
			next.push(start + 2);
			next.push(start);
			next.push(b);
			next.push(start + 1);
			next.push(start + 1);
			next.push(c);
			next.push(start + 2);
		}
		faces = move next;
	}
	let normals: Vec<Vec3> = [];
	for (let i = 0; i < points.length; i++) { normals.push(vec3(0.0, 0.0, 0.0)); }
	for (let i = 0; i < faces.length; i += 3) {
		const a: int32 = faces[i];
		const b: int32 = faces[i + 2];
		const c: int32 = faces[i + 1];
		const normal: Vec3 = (points[b] - points[a]).cross(points[c] - points[a]);
		normals[a] = normals[a] + normal;
		normals[b] = normals[b] + normal;
		normals[c] = normals[c] + normal;
	}
	const first: int32 = data.vertexCount();
	for (let i = 0; i < points.length; i++) {
		const _vertex = try addVertex(data,
			points[i].scaled(radius), normals[i].normalized(), color);
	}
	for (let i = 0; i < faces.length; i += 3) {
		const _triangle = try addTriangle(data,
			first + faces[i], first + faces[i + 2], first + faces[i + 1]);
	}
	return Result.ok(first);
}

export const CUBE_VERTICES: int32 = 24;

// h3d.prim.Cube with `addUVs`: every face takes the whole texture. Heaps' faces are upright in
// its Z-up frame; here the sides stand along +y and the top and bottom read from the front.
export function addTexturedCube(
	ref data: MeshData,
	size: Vec3,
	centered: boolean,
	color: Rgba,
): Result<int32, MeshError> {
	if (!data.hasUvs) { return Result.err(MeshError.UvMismatch); }
	if (!data.hasRoomFor(CUBE_VERTICES)) { return Result.err(MeshError.TooManyVertices); }
	let low: Vec3 = centered ? size.scaled(-0.5) : vec3(0.0, 0.0, 0.0);
	let high: Vec3 = low + size;
	let leftBottomBack: Vec3 = vec3(low.x, low.y, low.z);
	let rightBottomBack: Vec3 = vec3(high.x, low.y, low.z);
	let leftTopBack: Vec3 = vec3(low.x, high.y, low.z);
	let rightTopBack: Vec3 = vec3(high.x, high.y, low.z);
	let leftBottomFront: Vec3 = vec3(low.x, low.y, high.z);
	let rightBottomFront: Vec3 = vec3(high.x, low.y, high.z);
	let leftTopFront: Vec3 = vec3(low.x, high.y, high.z);
	let rightTopFront: Vec3 = vec3(high.x, high.y, high.z);
	let first: int32 = try addTexturedQuad(
		data, leftBottomFront, rightBottomFront, rightTopFront, leftTopFront,
		vec3(0.0, 0.0, 1.0), color,
	);
	let _right: int32 = try addTexturedQuad(
		data, rightBottomFront, rightBottomBack, rightTopBack, rightTopFront,
		vec3(1.0, 0.0, 0.0), color,
	);
	let _back: int32 = try addTexturedQuad(
		data, rightBottomBack, leftBottomBack, leftTopBack, rightTopBack,
		vec3(0.0, 0.0, -1.0), color,
	);
	let _left: int32 = try addTexturedQuad(
		data, leftBottomBack, leftBottomFront, leftTopFront, leftTopBack,
		vec3(-1.0, 0.0, 0.0), color,
	);
	let _top: int32 = try addTexturedQuad(
		data, leftTopFront, rightTopFront, rightTopBack, leftTopBack,
		vec3(0.0, 1.0, 0.0), color,
	);
	let _bottom: int32 = try addTexturedQuad(
		data, leftBottomBack, rightBottomBack, rightBottomFront, leftBottomFront,
		vec3(0.0, -1.0, 0.0), color,
	);
	return Result.ok(first);
}
