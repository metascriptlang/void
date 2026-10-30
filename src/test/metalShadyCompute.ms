import { computeModule, programSource } from "../shader/descriptor";
import { ShaderTarget } from "../shader/layout";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import {
	AtomicI32,
	AtomicU32,
	Vec3u,
	access,
	atomicStore,
	binding,
	builtin,
	vec2i,
} from "../shader/std";

export const WORKGROUP = 32;

export struct KernelInput {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct FloatCell {
	x: float32;
}

export struct IntCell {
	k: int32;
}

export struct Cell {
	a: AtomicU32;
	b: AtomicI32;
	c: AtomicI32;
}

export struct Params {
	scale: float32;
	bias: float32;
}

export struct PlainBindings {
	@binding(0) @access(read) xs: FloatCell[];
	@binding(1) @access(read) ks: IntCell[];
	@binding(2) @access(read_write) cells: Cell[];
}

export struct ScaledBindings {
	@binding(0) params: Params;
	@binding(0) @access(read) xs: FloatCell[];
	@binding(1) @access(read) ks: IntCell[];
	@binding(2) @access(read_write) cells: Cell[];
}

function mixed(k: int32, n: int32): int32 {
	return (k ^ 5) + (k >> 1) - n;
}

export function plainKernel(input: KernelInput, b: PlainBindings): void {
	const i = input.id.x;
	const n = vec2i(input.id.xy).x;
	atomicStore(b.cells[i].a, i * 7 + 3);
	atomicStore(b.cells[i].b, mixed(b.ks[i].k, n));
	atomicStore(b.cells[i].c, (b.xs[i].x * 2.5 + 0.5) as int32);
}

export function scaledKernel(input: KernelInput, b: ScaledBindings): void {
	const i = input.id.x;
	const n = vec2i(input.id.xy).x;
	atomicStore(b.cells[i].a, i * 7 + 3);
	atomicStore(b.cells[i].b, mixed(b.ks[i].k, n));
	atomicStore(b.cells[i].c, (b.xs[i].x * b.params.scale + b.params.bias) as int32);
}

export function shadyComputeDescriptor(label: string, text: string): GPUShaderModuleDescriptor {
	const module = computeModule(text, []);
	if (!module.ok) { console.log(`${label}: ${module.error}`); unreachable; }
	const source = programSource(module.value, ShaderTarget.Msl);
	if (!source.ok) { console.log(`${label}: ${source.error}`); unreachable; }
	if (source.value.refusal != "") { console.log(`${label}: ${source.value.refusal}`); unreachable; }
	let descriptor: GPUShaderModuleDescriptor = { label: label, computeCode: source.value.computeCode, computeEntryPoint: source.value.entryPoint };
	descriptor.workgroupSize = [source.value.reflection.workgroupSize[0], source.value.reflection.workgroupSize[1], source.value.reflection.workgroupSize[2]];
	for (let i = 0; i < source.value.reflection.bindings.length; i++) {
		descriptor.bindings[i] = source.value.reflection.bindings[i];
	}
	return descriptor;
}
