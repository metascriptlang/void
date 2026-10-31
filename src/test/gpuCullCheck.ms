import { Mat4, identity, rotationX, rotationY, scaling, translation } from "../math/math3d";
import { computeModule, programSource } from "../shader/descriptor";
import { glslComputeIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { Bounds3D } from "../void3d/bounds";
import { Frustum3D } from "../void3d/frustum";
import {
	CULL_WORKGROUP, CullBindings, CullRun, CullSlot, CullWork, MeshInput, cullKernel, cullPlanesOf,
	meshInputOf,
} from "../void3d/gpuCull";

function perspective(): Mat4 {
	return {
		m11: 1.0, m12: 0.0, m13: 0.0, m14: 0.0,
		m21: 0.0, m22: 1.0, m23: 0.0, m24: 0.0,
		m31: 0.0, m32: 0.0, m33: -1.125, m34: -1.0,
		m41: 0.0, m42: 0.0, m43: -1.125, m44: 0.0,
	};
}

function cube(): Bounds3D {
	return Bounds3D.fromValues(-0.25, -0.25, -0.25, 0.5, 0.5, 0.5);
}

function sheared(): Mat4 {
	let m = identity();
	m.m21 = -2.0;
	return m;
}

function worlds(): Vec<Mat4> {
	let out: Vec<Mat4> = [];
	for (let i = 0; i < 40; i++) {
		const x = ((i % 8) as float32) * 0.9 - 3.2;
		const z = -1.0 - ((i >> 3) as float32) * 2.5;
		const turn = rotationY((i as float32) * 0.37) * rotationX((i as float32) * 0.21);
		const stretch = scaling(1.0 + ((i % 3) as float32), 1.0, 0.5 + ((i % 2) as float32));
		out.push(stretch * turn * translation(x, ((i % 5) as float32) * 0.6 - 1.2, z));
	}
	out.push(sheared() * translation(1.7, 0.0, -1.0));
	out.push(sheared() * translation(1.8, 0.0, -1.0));
	out.push(translation(0.0, 0.0, -50.0));
	return out;
}

function runKernel(inputs: Vec<MeshInput>, frustum: Frustum3D, batches: int32): CullBindings {
	let work: CullWork[] = [];
	let sizes: Vec<int32> = [];
	for (let n = 0; n < batches; n++) { sizes.push(0); }
	for (let i = 0; i < inputs.length; i++) {
		work.push({ input: i as uint32, batch: (i % batches) as uint32 });
		sizes[i % batches]++;
	}
	let runs: CullRun[] = [];
	let first = 0;
	for (const size of sizes) {
		runs.push({ first: first as uint32, count: { value: 0 } });
		first += size;
	}
	let visible: CullSlot[] = [];
	for (let i = 0; i < inputs.length; i++) { visible.push({ input: 0 }); }
	let b: CullBindings = {
		inputs: [...inputs],
		work,
		planes: cullPlanesOf(frustum),
		view: [{ itemCount: inputs.length as uint32 }],
		runs,
		visible,
	};
	const groups: int32 = ((inputs.length + CULL_WORKGROUP - 1) / CULL_WORKGROUP) as int32;
	for (let i = 0; i < groups * CULL_WORKGROUP; i++) {
		cullKernel({ id: { x: i as uint32, y: 0, z: 0 } }, b);
	}
	return b;
}

test "the cull kernel keeps exactly the meshes the CPU frustum test keeps, batch by batch" {
	const frustum = Frustum3D.fromMatrix(perspective());
	const list = worlds();
	let inputs: Vec<MeshInput> = [];
	for (const world of list) { inputs.push(meshInputOf(world, cube())); }
	const b = runKernel(inputs, frustum, 3);
	let kept = 0;
	for (let batch = 0; batch < 3; batch++) {
		const run = b.runs[batch];
		let expected: Vec<int32> = [];
		for (let i = batch; i < list.length; i += 3) {
			if (frustum.intersectsBounds(cube(), list[i])) { expected.push(i); }
		}
		assert run.count.value == expected.length as uint32;
		for (let n = 0; n < expected.length; n++) {
			assert b.visible[run.first + (n as uint32)].input == expected[n] as uint32;
		}
		kept += expected.length;
	}
	assert kept > 0 && kept < list.length;
}

test "a mesh with empty bounds is never culled" {
	const frustum = Frustum3D.fromMatrix(perspective());
	const far = translation(0.0, 0.0, 400.0);
	const empty = Bounds3D.empty();
	const b = runKernel([meshInputOf(far, empty), meshInputOf(far, cube())], frustum, 1);
	assert b.runs[0].count.value == 1;
	assert b.visible[0].input == 0;
}

test "the cull kernel prints as a compute program for every compute target" {
	const module = computeModule(glslComputeIr(cullKernel, [64, 1, 1]), []);
	if (!module.ok) { console.log(module.error); assert false; return; }
	for (const target of [ShaderTarget.Hlsl5, ShaderTarget.Glsl430, ShaderTarget.Msl, ShaderTarget.Wgsl]) {
		const source = programSource(module.value, target);
		assert source.ok;
		if (source.ok) { assert source.value.refusal == ""; }
	}
}
