import {
	Access,
	Builtin,
	IoDirection,
	ResourceKind,
	SampleType,
	SamplerType,
	ShaderModule,
	ShaderStage,
	TexelFormat,
	TextureShape,
} from "./ir";
import { ioLocation } from "./irWalk";
import {
	BindingSlot,
	ShaderTarget,
	bindingSlots,
	storageElementLayout,
	uniformBlockLayout,
} from "./layout";
import {
	GPUBufferBindingType,
	GPUSamplerBindingType,
	GPUShaderAttribute,
	GPUShaderBinding,
	GPUShaderBindingKind,
	GPUShaderStage,
	GPUStorageTextureAccess,
	GPUTextureFormat,
	GPUTextureSampleType,
	GPUTextureViewDimension,
} from "../webgpu/types.ms";
import { DUMMY_SAMPLER_BINDING, GPU_MAX_SHADER_BINDINGS, GPU_MAX_VERTEX_ATTRIBUTES } from "../webgpu/types.ms";

export class Reflection {
	bindings: GPUShaderBinding[] = [];
	attributes: GPUShaderAttribute[] = [];
	workgroupSize: int32[] = [0, 0, 0];
	readsVertexIndex: boolean = false;
	readsInstanceIndex: boolean = false;
}

function kindName(kind: ResourceKind): GPUShaderBindingKind {
	return match (kind) {
		ResourceKind.UniformBlock => "uniform" as GPUShaderBindingKind,
		ResourceKind.Texture => "texture" as GPUShaderBindingKind,
		ResourceKind.Sampler => "sampler" as GPUShaderBindingKind,
		ResourceKind.StorageBuffer => "storage-buffer" as GPUShaderBindingKind,
		ResourceKind.StorageTexture => "storage-texture" as GPUShaderBindingKind,
	};
}

function stageBit(stage: ShaderStage): int32 {
	return match (stage) {
		ShaderStage.Vertex => GPUShaderStage.VERTEX as int32,
		ShaderStage.Fragment => GPUShaderStage.FRAGMENT as int32,
		ShaderStage.Compute => GPUShaderStage.COMPUTE as int32,
	};
}

function sampleTypeName(t: SampleType): GPUTextureSampleType {
	return match (t) {
		SampleType.Float => "float" as GPUTextureSampleType,
		SampleType.UnfilterableFloat => "unfilterable-float" as GPUTextureSampleType,
		SampleType.Depth => "depth" as GPUTextureSampleType,
		SampleType.Sint => "sint" as GPUTextureSampleType,
		SampleType.Uint => "uint" as GPUTextureSampleType,
	};
}

function samplerTypeName(t: SamplerType): GPUSamplerBindingType {
	return match (t) {
		SamplerType.Filtering => "filtering" as GPUSamplerBindingType,
		SamplerType.NonFiltering => "non-filtering" as GPUSamplerBindingType,
		SamplerType.Comparison => "comparison" as GPUSamplerBindingType,
	};
}

function storageAccessName(a: Access): GPUStorageTextureAccess {
	return match (a) {
		Access.Read => "read-only" as GPUStorageTextureAccess,
		Access.Write => "write-only" as GPUStorageTextureAccess,
		Access.ReadWrite => "read-write" as GPUStorageTextureAccess,
	};
}

function viewDimensionOf(shape: TextureShape): GPUTextureViewDimension {
	return match (shape) {
		TextureShape.D2Array | TextureShape.Depth2dArray => "2d-array" as GPUTextureViewDimension,
		TextureShape.D3 => "3d" as GPUTextureViewDimension,
		TextureShape.Cube | TextureShape.DepthCube => "cube" as GPUTextureViewDimension,
		TextureShape.CubeArray => "cube-array" as GPUTextureViewDimension,
		TextureShape.D2 | TextureShape.Depth2d | TextureShape.Multisampled2d =>
			"2d" as GPUTextureViewDimension,
	};
}

function storageFormatOf(format: TexelFormat, owner: string): Result<GPUTextureFormat, string> {
	const name: GPUTextureFormat | null = match (format) {
		TexelFormat.Rgba8unorm => "rgba8unorm" as GPUTextureFormat,
		TexelFormat.Rgba8snorm => null,
		TexelFormat.Rgba8uint => "rgba8uint" as GPUTextureFormat,
		TexelFormat.Rgba16float => "rgba16float" as GPUTextureFormat,
		TexelFormat.Rgba32float => "rgba32float" as GPUTextureFormat,
		TexelFormat.R32float => "r32float" as GPUTextureFormat,
		TexelFormat.R32uint => "r32uint" as GPUTextureFormat,
		TexelFormat.Rg32float => "rg32float" as GPUTextureFormat,
	};
	if (name === null) {
		return Result.err(owner + ": " + format.toString() + " is no GPUTextureFormat");
	}
	return Result.ok(name);
}

function dummySamplerOf(s: BindingSlot): GPUShaderBinding {
	return {
		group: s.group,
		binding: DUMMY_SAMPLER_BINDING,
		kind: "sampler",
		visibility: stageBit(s.stage),
		size: 0,
		samplerType: "non-filtering",
		nativeSlot: -1,
		nativeName: s.nativeName,
		textureBinding: s.textureBinding,
	};
}

function bindingOf(m: ShaderModule, s: BindingSlot): Result<GPUShaderBinding, string> {
	if (s.resource < 0) { return Result.ok(dummySamplerOf(s)); }
	const r = m.resources[s.resource];
	let b: GPUShaderBinding = {
		group: s.group,
		binding: s.binding,
		kind: kindName(r.kind),
		visibility: stageBit(s.stage),
		size: 0,
		nativeSlot: s.nativeSlot,
		textureBinding: s.textureBinding,
	};
	if (s.nativeName != "") { b.nativeName = s.nativeName; } else { b.nativeName = null; }
	match (r.kind) {
		ResourceKind.UniformBlock => {
			const layout = try uniformBlockLayout(m, s.resource);
			b.size = layout.size;
		},
		ResourceKind.Texture => {
			b.sampleType = sampleTypeName(r.sampleType);
			const dimension = viewDimensionOf(r.type.shape);
			if (dimension != "2d") { b.viewDimension = dimension; }
			b.multisampled = r.type.shape == TextureShape.Multisampled2d;
		},
		ResourceKind.Sampler => { b.samplerType = samplerTypeName(r.samplerType); },
		ResourceKind.StorageBuffer => {
			const layout = try storageElementLayout(m, s.resource);
			b.size = layout.size;
			const bufferType: GPUBufferBindingType = r.access == Access.Read ?
				"read-only-storage" : "storage";
			b.bufferType = bufferType;
		},
		ResourceKind.StorageTexture => {
			const dimension = viewDimensionOf(r.type.shape);
			if (dimension != "2d") { b.viewDimension = dimension; }
			b.storageAccess = storageAccessName(r.type.access);
			const owner = "storage texture '" + r.name + "'";
			b.storageFormat = try storageFormatOf(r.type.format, owner);
		},
	}
	return Result.ok(b);
}

function entryOf(m: ShaderModule, index: int32, stage: ShaderStage): Result<int32, string> {
	if (index < 0 || index >= m.entries.length) {
		return Result.err("entry " + String(index) + " is out of range");
	}
	if (m.entries[index].stage != stage) {
		return Result.err("entry '" + m.entries[index].name + "' is no " + stage.toString() +
			" entry");
	}
	return Result.ok(index);
}

function bindingsOf(m: ShaderModule, entries: int32[], target: ShaderTarget,
	out: Reflection): Result<int32, string> {
	const slots = try bindingSlots(m, entries, target);
	for (const s of slots) {
		const b = try bindingOf(m, s);
		const held = out.bindings.findIndex((h) => h.group == b.group &&
			h.binding == b.binding && h.kind == b.kind &&
			h.textureBinding == b.textureBinding && h.nativeName == b.nativeName);
		if (held < 0) {
			out.bindings.push(b);
		} else if (out.bindings[held].nativeSlot != b.nativeSlot) {
			return Result.err("internal: binding " + String(b.binding) + " sits at native slot " +
				String(out.bindings[held].nativeSlot) + " in one stage and " +
				String(b.nativeSlot) + " in another");
		} else {
			out.bindings[held].visibility = out.bindings[held].visibility | b.visibility;
		}
	}
	if (out.bindings.length > GPU_MAX_SHADER_BINDINGS) {
		return Result.err("the program reads " + String(out.bindings.length) + " bindings, more " +
			"than " + String(GPU_MAX_SHADER_BINDINGS));
	}
	return Result.ok(out.bindings.length as int32);
}

// HLSL reads attribute n at TEXCOORD<n> (sokol-shdc src/shdc/reflection.cc sem_index = slot).
export function reflectProgram(m: ShaderModule, vertex: int32, fragment: int32,
	target: ShaderTarget): Result<Reflection, string> {
	let out = new Reflection();
	const v = try entryOf(m, vertex, ShaderStage.Vertex);
	const f = try entryOf(m, fragment, ShaderStage.Fragment);
	const _count = try bindingsOf(m, [v, f], target, out);
	const gl = target == ShaderTarget.Glsl430 || target == ShaderTarget.Glsl300es;
	out.readsVertexIndex = m.ios.some((io) => io.stage == ShaderStage.Vertex &&
		io.builtin == Builtin.VertexIndex);
	out.readsInstanceIndex = m.ios.some((io) => io.stage == ShaderStage.Vertex &&
		io.builtin == Builtin.InstanceIndex);
	let ordinal = 0;
	for (const io of m.ios) {
		if (io.stage != ShaderStage.Vertex || io.direction != IoDirection.In ||
			io.builtin != Builtin.None) {
			continue;
		}
		const location = ioLocation(io, ordinal);
		ordinal++;
		let a: GPUShaderAttribute = {
			location: location,
			semanticIndex: target == ShaderTarget.Hlsl5 ? location : 0,
		};
		if (gl) { a.nativeName = io.name; } else { a.nativeName = null; }
		out.attributes.push(a);
	}
	if (out.attributes.length > GPU_MAX_VERTEX_ATTRIBUTES) {
		return Result.err("the vertex entry has " + String(out.attributes.length) +
			" attributes, more than " + String(GPU_MAX_VERTEX_ATTRIBUTES));
	}
	return Result.ok(out);
}

export function reflectCompute(m: ShaderModule, compute: int32, target: ShaderTarget):
	Result<Reflection, string> {
	let out = new Reflection();
	const c = try entryOf(m, compute, ShaderStage.Compute);
	const _count = try bindingsOf(m, [c], target, out);
	out.workgroupSize = m.entries[c].workgroupSize.map((n) => n);
	return Result.ok(out);
}
