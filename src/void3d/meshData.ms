// CPU-side geometry, in the role of h3d.prim.Polygon: the vertex and index arrays a mesh is
// built from, plus the bounds they span. It owns no GPU object and never touches the driver,
// so it is the thing a lost context is rebuilt from (draw.ms, rebuildMeshes) and the thing
// the headless tests can check.
//
// Heaps keeps points, normals, uvs and colors as four parallel arrays and interleaves them in
// `getCPUBuffer` at upload. Here the interleave is the storage: one `Vec<float32>` in the Lit
// layout gpu3d.c describes (position 3, normal 3, rgba 4). There is one layout, it is the one
// this renderer's content has, and keeping four arrays would only pay off for a format switch
// that the fixed sokol-shdc programs do not have (docs/VOID3D.md, Porting rules).
//
// Bounds are maintained as vertices arrive rather than computed on demand as in Heaps'
// `Polygon.getBounds`: the builders are the only writers, so the bounds cannot go stale, and
// nothing later has to remember to ask.
//
// MeshData is a value struct holding two `Vec`s, so **assigning it to a local copies both
// arrays**. Reach one through its table by index (`context.meshData[i].bounds`) or take it by
// `ref`; never `const data: MeshData = table[i]` (CODE-STYLE §5, the copy trap).

import { Vec3, vec3 } from "../math/math3d";
import { sinf, cosf } from "../math/mat4";
import { Bounds, addPoint } from "./bounds";

// position(3) + normal(3) + rgba(4), the `Lit` vertex layout in gpu3d.c describeLayout.
export const LIT_VERTEX_STRIDE: int32 = 10;

// uint16 indices, so one MeshData holds at most 65536 vertices. The content budget this port
// was sized against is three orders of magnitude under that (RENDERER-BRIEF §4.4); a mesh that
// does not fit is a content constraint, not a reason to widen the format.
export const MAX_MESH_VERTICES: int32 = 65536;

export struct Rgba {
	red: float32;
	green: float32;
	blue: float32;
	alpha: float32;
}

export struct MeshData {
	vertices: Vec<float32>;
	indices: Vec<uint16>;
	bounds: Bounds;
}

export enum MeshError {
	TooManyVertices,
	IndexOutOfRange,
}

export function empty(this typeof MeshData): MeshData {
	return { vertices: [], indices: [], bounds: Bounds.empty() };
}

export function vertexCount(this data: MeshData): int32 {
	return (data.vertices.length as int32) / LIT_VERTEX_STRIDE;
}

export function indexCount(this data: MeshData): int32 {
	return data.indices.length as int32;
}

export function isIndexed(this data: MeshData): boolean {
	return data.indices.length > 0;
}

// h3d.prim.Primitive.triCount: the index count when indexed, the vertex count otherwise.
export function triangleCount(this data: MeshData): int32 {
	if (data.isIndexed()) { return (data.indices.length as int32) / 3; }
	return data.vertexCount() / 3;
}

// Appends one vertex and returns its index, growing the bounds. Fails rather than truncating
// when the mesh would outgrow a uint16 index.
export function addVertex(
	ref data: MeshData,
	position: Vec3,
	normal: Vec3,
	color: Rgba,
): Result<int32, MeshError> {
	const index: int32 = data.vertexCount();
	if (index >= MAX_MESH_VERTICES) { return Result.err(MeshError.TooManyVertices); }
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

// Whether `count` more vertices would still fit a uint16 index. The builders below ask before
// they push anything, because `try` propagates out of a half-written quad: a failure partway
// through would leave loose vertices in `vertices` and in `bounds` that no triangle refers to,
// and every caller reads an `err` as "nothing was added".
export function hasRoomFor(this data: MeshData, count: int32): boolean {
	return data.vertexCount() + count <= MAX_MESH_VERTICES;
}

// Three vertex indices, counter-clockwise as seen from the front (gpu3d.c sets CCW winding).
// Returns the index of the triangle it added, as addVertex returns the index of its vertex.
export function addTriangle(
	ref data: MeshData,
	a: int32,
	b: int32,
	c: int32,
): Result<int32, MeshError> {
	const count: int32 = data.vertexCount();
	if (a < 0 || b < 0 || c < 0 || a >= count || b >= count || c >= count) {
		return Result.err(MeshError.IndexOutOfRange);
	}
	data.indices.push(a as uint16);
	data.indices.push(b as uint16);
	data.indices.push(c as uint16);
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

// Recomputes the bounds from the vertices, h3d.prim.Polygon.getBounds. The builders keep the
// bounds current, so this is for a caller that edited `vertices` itself — a vertex-baked
// animation frame (M9) swapping positions under a mesh that keeps its indices.
export function recomputeBounds(ref data: MeshData): void {
	let box: Bounds = Bounds.empty();
	const count: int32 = data.vertexCount();
	for (let i = 0; i < count; i++) {
		const base: int32 = i * LIT_VERTEX_STRIDE;
		addPoint(box, vec3(data.vertices[base], data.vertices[base + 1], data.vertices[base + 2]));
	}
	data.bounds = box;
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
		data, leftTopBack, rightTopBack, rightTopFront, leftTopFront,
		frame.rotate(vec3(0.0, 1.0, 0.0)), color,
	);
	const _right: int32 = try addQuad(
		data, rightBottomBack, rightBottomFront, rightTopFront, rightTopBack,
		frame.rotate(vec3(1.0, 0.0, 0.0)), color,
	);
	const _left: int32 = try addQuad(
		data, leftBottomFront, leftBottomBack, leftTopBack, leftTopFront,
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
		vec3(halfSize, 0.0, -halfSize),
		vec3(halfSize, 0.0, halfSize),
		vec3(-halfSize, 0.0, halfSize),
		vec3(0.0, 1.0, 0.0),
		color,
	);
}
