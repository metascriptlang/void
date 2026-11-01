// One view's cull on the GPU. A work item names a mesh input and the batch it draws in; an item
// whose bounds meet the view's planes takes the next slot of its batch's run, so the runs hold
// only what the view sees, packed batch by batch. A second pass writes one indexed indirect record
// per batch, drawing its run with the index range the batch's mesh carries.

import { Mat4 } from "../math/math3d";
import {
	AtomicU32, Vec3u, Vec4f, abs, access, atomicAdd, atomicLoad, binding, builtin, dot, vec4f,
} from "../shader/std";
import { Bounds3D } from "./bounds";
import { Frustum3D } from "./frustum";

export const CULL_WORKGROUP: int32 = 64;
export const CULL_PLANES: int32 = 6;

// The world matrix as three rows of the 3x4 affine, the translation in w, with the local bounds
// and the mesh's index range. A mesh with no bounds keeps noCull at 1 and is never culled.
export struct MeshInput {
	axisX: Vec4f;
	axisY: Vec4f;
	axisZ: Vec4f;
	boundsCenter: Vec4f;
	boundsHalf: Vec4f;
	noCull: uint32;
	firstIndex: uint32;
	indexCount: uint32;
	baseVertex: int32;
}

export struct MeshRange {
	firstIndex: uint32;
	indexCount: uint32;
	baseVertex: int32;
}

export struct CullWork {
	input: uint32;
	batch: uint32;
}

// A batch's slots in the visible list start at first; mesh is any input of the batch, read for
// the index range every instance of the batch shares.
export struct CullRun {
	first: uint32;
	mesh: uint32;
	count: AtomicU32;
}

export struct CullView {
	itemCount: uint32;
}

export struct CullPlane {
	plane: Vec4f;
}

export struct CullSlot {
	input: uint32;
}

export struct CullInput {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct CullBindings {
	@binding(0) @access(read) inputs: MeshInput[];
	@binding(1) @access(read) work: CullWork[];
	@binding(2) @access(read) planes: CullPlane[];
	@binding(3) @access(read) view: CullView[];
	@binding(4) @access(read_write) runs: CullRun[];
	@binding(5) @access(read_write) visible: CullSlot[];
}

function planeReach(plane: Vec4f, mesh: MeshInput): float32 {
	const n = vec4f(plane.x, plane.y, plane.z, 0.0);
	return abs(dot(n, mesh.axisX)) * mesh.boundsHalf.x +
		abs(dot(n, mesh.axisY)) * mesh.boundsHalf.y +
		abs(dot(n, mesh.axisZ)) * mesh.boundsHalf.z;
}

function worldCenter(mesh: MeshInput): Vec4f {
	const c = mesh.boundsCenter;
	return vec4f(
		c.x * mesh.axisX.x + c.y * mesh.axisY.x + c.z * mesh.axisZ.x + mesh.axisX.w,
		c.x * mesh.axisX.y + c.y * mesh.axisY.y + c.z * mesh.axisZ.y + mesh.axisY.w,
		c.x * mesh.axisX.z + c.y * mesh.axisY.z + c.z * mesh.axisZ.z + mesh.axisZ.w,
		1.0,
	);
}

export function cullKernel(input: CullInput, b: CullBindings): void {
	const i = input.id.x;
	if (i >= b.view[0].itemCount) { return; }
	const work = b.work[i];
	const mesh = b.inputs[work.input];
	if (mesh.noCull == 0) {
		const center = worldCenter(mesh);
		for (let p = 0; p < 6; p++) {
			const plane = b.planes[p].plane;
			if (dot(plane, center) + planeReach(plane, mesh) < 0.0) { return; }
		}
	}
	const slot = atomicAdd(b.runs[work.batch].count, 1);
	b.visible[b.runs[work.batch].first + slot].input = work.input;
}

export struct DrawIndexedIndirect {
	indexCount: uint32;
	instanceCount: uint32;
	firstIndex: uint32;
	baseVertex: int32;
	firstInstance: uint32;
}

export struct IndirectView {
	runCount: uint32;
}

export struct IndirectBindings {
	@binding(0) @access(read) inputs: MeshInput[];
	@binding(1) @access(read) view: IndirectView[];
	@binding(2) @access(read_write) runs: CullRun[];
	@binding(3) @access(read_write) draws: DrawIndexedIndirect[];
}

export function indirectKernel(input: CullInput, b: IndirectBindings): void {
	const r = input.id.x;
	if (r >= b.view[0].runCount) { return; }
	const mesh = b.inputs[b.runs[r].mesh];
	const visible = atomicLoad(b.runs[r].count);
	b.draws[r].indexCount = mesh.indexCount;
	b.draws[r].instanceCount = visible;
	b.draws[r].firstIndex = mesh.firstIndex;
	b.draws[r].baseVertex = mesh.baseVertex;
	b.draws[r].firstInstance = b.runs[r].first;
}

export function meshInputOf(world: Mat4, bounds: Bounds3D, range: MeshRange): MeshInput {
	const empty = bounds.isEmpty();
	const center = empty ? bounds.min : bounds.center();
	const half = empty ? bounds.min.scaled(0.0) : (bounds.max - bounds.min).scaled(0.5);
	return {
		axisX: vec4f(world.m11, world.m12, world.m13, world.m41),
		axisY: vec4f(world.m21, world.m22, world.m23, world.m42),
		axisZ: vec4f(world.m31, world.m32, world.m33, world.m43),
		boundsCenter: vec4f(center.x, center.y, center.z, 1.0),
		boundsHalf: vec4f(half.x, half.y, half.z, 0.0),
		noCull: empty ? 1 : 0,
		firstIndex: range.firstIndex,
		indexCount: range.indexCount,
		baseVertex: range.baseVertex,
	};
}

export function cullPlanesOf(frustum: Frustum3D): CullPlane[] {
	let out: CullPlane[] = [];
	for (const p of [frustum.left, frustum.right, frustum.bottom, frustum.top, frustum.nearPlane,
		frustum.farPlane]) {
		out.push({ plane: vec4f(p.x, p.y, p.z, p.w) });
	}
	return out;
}
