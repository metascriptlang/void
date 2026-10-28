// WGSL's assignment into an element, and a field of an element, of a read_write storage buffer:
// the entry runs on the CPU, is pinned as GLSL and printed for every target into out/<target>Probe/
// for scripts/validateWgsl.sh, scripts/validateHlsl.sh and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { computeModule } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import { Access, ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { printedProbe, printedSpirv } from "./shaderProbePrint";
import {
	Vec3u,
	Vec4f,
	access,
	binding,
	builtin,
	vec4f,
} from "../shader/std";

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct Particle {
	position: Vec4f;
	mass: float32;
	count: uint32;
}

export struct Particles {
	@binding(0) @access(read_write) particles: Particle[];
	@binding(1) seeds: Particle[];
}

export function stepCs(input: Ids, b: Particles): void {
	const i = input.id.x;
	b.particles[i].position.x = b.seeds[i].position.y + 1.0;
	b.particles[i].position.w += 2.0;
	b.particles[i].mass *= 3.0;
	b.particles[i].count = b.seeds[i].count + 5;
	b.particles[i].count++;
	b.particles[i + 1] = b.seeds[i];
}

function seed(x: float32, count: uint32): Particle {
	return { position: vec4f(x, x + 1.0, x + 2.0, x + 3.0), mass: x, count };
}

test "an assignment into a storage element and its fields writes the CPU array" {
	const b: Particles = {
		particles: [seed(0.0, 0), seed(10.0, 0), seed(20.0, 0)],
		seeds: [seed(1.0, 7), seed(2.0, 9)],
	};
	stepCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.particles[1].position.x == 4.0 && b.particles[1].position.w == 15.0;
	assert b.particles[1].mass == 30.0 && b.particles[1].count == 15;
	assert b.particles[0].count == 0;
	assert b.particles[2].mass == 2.0 && b.particles[2].count == 9;
}

function computeOf(): ShaderModule {
	const m = computeModule(glslComputeIr(stepCs, [64, 1, 1]), []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

test "GLSL 450 writes the buffer member of the block" {
	const text = glslCompute(stepCs, [64, 1, 1]);
	const _out = mkdir("out");
	const _folder = mkdir("out/glslProbe");
	const _written = writeFile("out/glslProbe/particleStep.450.comp", "#version 450\n" + text);
	assert text ==
		"layout(local_size_x=64, local_size_y=1, local_size_z=1) in;\n" +
		"struct Particle {\n" +
		"    vec4 position;\n" +
		"    float mass;\n" +
		"    uint count;\n" +
		"};\n" +
		"layout(binding=0) buffer particlesBuffer {\n" +
		"    Particle particles[];\n" +
		"};\n" +
		"layout(binding=1) readonly buffer seedsBuffer {\n" +
		"    Particle seeds[];\n" +
		"};\n" +
		"void main() {\n" +
		"    uint i = gl_GlobalInvocationID.x;\n" +
		"    particles[i].position.x = seeds[i].position.y + 1.0;\n" +
		"    particles[i].position.w += 2.0;\n" +
		"    particles[i].mass *= 3.0;\n" +
		"    particles[i].count = seeds[i].count + 5;\n" +
		"    particles[i].count++;\n" +
		"    particles[i + 1] = seeds[i];\n" +
		"}\n";
}

test "every target spells the storage write" {
	const m = computeOf();
	assert irErrors(m).length == 0;
	for (const t of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Msl]) {
		const text = printedProbe(m, 0, t, "particleStep", "comp");
		assert text.length > 0 && !text.startsWith("print");
	}
	
	
	
	assert printedSpirv(m, 0, "particleStep") == "";
}

test "a write to a read-only storage buffer is an error of the module" {
	let m = computeOf();
	m.resources[0].access = Access.Read;
	assert irErrors(m).includes("function 'stepCs': a write to storage buffer 'particles', " +
		"whose access is read, not read_write");
}
