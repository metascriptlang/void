import {
	Access,
	ExprKind,
	Intrinsic,
	ResourceKind,
	SamplerType,
	ScalarKind,
	ShaderExpr,
	ShaderModule,
	ShaderResource,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
} from "./ir";
import { TexturePair, readsFrom } from "./specialize";

enum LayoutRule {
	Std140,
	Std430,
}

export enum ShaderTarget {
	Wgsl,
	Glsl300es,
	Glsl430,
	Hlsl5,
	Msl,
	Spirv,
}

export struct StructLayout {
	name: string;
	offsets: int32[];
	size: int32;
	align: int32;
}

const MAX_UNIFORM_SLOTS = 8;
const MAX_VIEW_SLOTS = 32;
const MAX_SAMPLER_SLOTS = 12;

function roundUp(n: int32, to: int32): int32 {
	return (n + to - 1) / to * to;
}

// The bytes a column of this many rows takes in a matrix, and the alignment of a vector of them.
export function columnStride(rows: int32): int32 {
	return rows == 2 ? 8 : 16;
}

function arrayAlign(m: ShaderModule, t: ShaderType, rule: LayoutRule): int32 {
	const [elementAlign, _elementSize] = extentOf(m, t.element[0], rule);
	return rule == LayoutRule.Std140 ? roundUp(elementAlign, 16) : elementAlign;
}

function arrayStride(m: ShaderModule, t: ShaderType, rule: LayoutRule): int32 {
	const [_elementAlign, elementSize] = extentOf(m, t.element[0], rule);
	return roundUp(elementSize, arrayAlign(m, t, rule));
}

export function uniformArrayStride(m: ShaderModule, t: ShaderType): int32 {
	return arrayStride(m, t, LayoutRule.Std140);
}

function extentOf(m: ShaderModule, t: ShaderType, rule: LayoutRule): [int32, int32] {
	match (t.kind) {
		ShaderTypeKind.Scalar | ShaderTypeKind.Atomic => { return [4, 4]; },
		ShaderTypeKind.Vector => { return [columnStride(t.rows), 4 * t.rows]; },
		ShaderTypeKind.Matrix => {
			const column = columnStride(t.rows);
			return [column, column * t.columns];
		},
		ShaderTypeKind.Array => {
			return [arrayAlign(m, t, rule), arrayStride(m, t, rule) * t.length];
		},
		_ => {},
	}
	const s = structLayoutOf(m, t.structIndex, rule);
	return [s.align, s.size];
}

function structLayoutOf(m: ShaderModule, structIndex: int32, rule: LayoutRule): StructLayout {
	const s = m.structs[structIndex];
	let offsets: int32[] = [];
	let align = 1;
	let end = 0;
	for (const f of s.members) {
		const [memberAlign, memberSize] = extentOf(m, f.type, rule);
		const offset = roundUp(end, memberAlign);
		offsets.push(offset);
		end = offset + memberSize;
		align = memberAlign > align ? memberAlign : align;
	}
	if (rule == LayoutRule.Std140) { align = roundUp(align, 16); }
	return { name: s.name, offsets, size: roundUp(end, align), align };
}

function typeName(t: ShaderType): string {
	return match (t.kind) {
		ShaderTypeKind.Scalar => t.scalar.toString(),
		ShaderTypeKind.Vector => t.scalar.toString() + "x" + String(t.rows),
		ShaderTypeKind.Matrix => "mat" + String(t.columns) + "x" + String(t.rows),
		_ => t.kind.toString(),
	};
}

function isVec4OrMat4(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.Vector && t.rows == 4 ||
		t.kind == ShaderTypeKind.Matrix && t.columns == 4 && t.rows == 4;
}

// A uniform block reaches GL as one `vec4 <block>[size / 16]`, so a member that is not float has no
// place in it.
export function uniformBlockLayout(m: ShaderModule, resourceIndex: int32):
	Result<StructLayout, string> {
	const r = m.resources[resourceIndex];
	const owner = "uniform block '" + r.name + "'";
	if (r.kind != ResourceKind.UniformBlock || r.type.kind != ShaderTypeKind.Struct) {
		return Result.err(owner + " is no uniform block of a struct");
	}
	for (const f of m.structs[r.type.structIndex].members) {
		const own = f.type.kind == ShaderTypeKind.Array ? f.type.element[0] : f.type;
		const fits = own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector ||
			own.kind == ShaderTypeKind.Matrix;
		if (!fits) {
			return Result.err(owner + ": member '" + f.name + "' is a " + typeName(own) +
				"; a uniform block member is a scalar, vector or matrix");
		}
		if (own.scalar != ScalarKind.F32) {
			return Result.err(owner + ": member '" + f.name + "' is " + typeName(own) +
				", and GL carries a uniform block as float vec4s only");
		}
		if (f.type.kind == ShaderTypeKind.Array && !isVec4OrMat4(own)) {
			return Result.err(owner + ": member '" + f.name + "' is an array of " +
				typeName(own) + "; an array member holds F32x4 or mat4x4");
		}
	}
	return Result.ok(structLayoutOf(m, r.type.structIndex, LayoutRule.Std140));
}

function storageMemberError(m: ShaderModule, t: ShaderType, path: string): string {
	match (t.kind) {
		ShaderTypeKind.Scalar | ShaderTypeKind.Vector => {
			return t.scalar == ScalarKind.Bool ? path + " is a bool, which has no host layout" : "";
		},
		ShaderTypeKind.Matrix | ShaderTypeKind.Atomic => { return ""; },
		ShaderTypeKind.Array => { return storageMemberError(m, t.element[0], path); },
		ShaderTypeKind.Struct => {
			for (const f of m.structs[t.structIndex].members) {
				const error = storageMemberError(m, f.type, path + "." + f.name);
				if (error != "") { return error; }
			}
			return "";
		},
		_ => {},
	}
	return path + " is a " + t.kind.toString() + ", which a storage buffer cannot hold";
}

export function storageElementLayout(m: ShaderModule, resourceIndex: int32):
	Result<StructLayout, string> {
	const r = m.resources[resourceIndex];
	const owner = "storage buffer '" + r.name + "'";
	if (r.kind != ResourceKind.StorageBuffer || r.type.kind != ShaderTypeKind.RuntimeArray ||
		r.type.element[0].kind != ShaderTypeKind.Struct) {
		return Result.err(owner + " is no runtime array of a struct");
	}
	const element = r.type.element[0];
	const error = storageMemberError(m, element, owner + " element");
	if (error != "") { return Result.err(error); }
	return Result.ok(structLayoutOf(m, element.structIndex, LayoutRule.Std430));
}

export const DUMMY_SAMPLER = "SPIRV_Cross_DummySampler";

export struct BindingSlot {
	resource: int32;
	texture: int32;
	stage: ShaderStage;
	group: int32;
	binding: int32;
	nativeSlot: int32;
	nativeName: string;
	textureBinding: int32;
}

struct Used {
	resource: int32;
	stage: ShaderStage;
}

struct PairUse {
	pair: TexturePair;
	stage: ShaderStage;
}

const UNPLACED = -2;

function highest(next: int32[], stages: int32[]): int32 {
	let slot = 0;
	for (const st of stages) { if (next[st] > slot) { slot = next[st]; } }
	return slot;
}

function stageIndex(s: ShaderStage): int32 {
	return match (s) {
		ShaderStage.Vertex => 0,
		ShaderStage.Fragment => 1,
		ShaderStage.Compute => 2,
	};
}

function isView(kind: ResourceKind): boolean {
	return kind == ResourceKind.Texture || kind == ResourceKind.StorageBuffer ||
		kind == ResourceKind.StorageTexture;
}

function slotLimit(kind: ResourceKind): int32 {
	return match (kind) {
		ResourceKind.UniformBlock => MAX_UNIFORM_SLOTS,
		ResourceKind.Sampler => MAX_SAMPLER_SLOTS,
		_ => MAX_VIEW_SLOTS,
	};
}

function sameSpace(a: ShaderResource, b: ShaderResource): boolean {
	return a.kind == b.kind || isView(a.kind) && isView(b.kind);
}

function slotOf(m: ShaderModule, u: Used, target: ShaderTarget): BindingSlot {
	const r = m.resources[u.resource];
	const native = target == ShaderTarget.Hlsl5 || target == ShaderTarget.Msl;
	const gl = target == ShaderTarget.Glsl430 || target == ShaderTarget.Glsl300es;
	const uniform = r.kind == ResourceKind.UniformBlock;
	return {
		resource: u.resource,
		texture: -1,
		stage: u.stage,
		group: uniform ? 0 : 1,
		binding: r.kind == ResourceKind.Sampler ? MAX_VIEW_SLOTS + r.binding : r.binding,
		nativeSlot: native && (uniform || r.kind == ResourceKind.Sampler) ? r.binding : -1,
		nativeName: gl && uniform ? r.name : "",
		textureBinding: -1,
	};
}

function samplerlessReads(e: ShaderExpr, out: int32[]): void {
	const fetch = e.kind == ExprKind.Intrinsic && (e.intrinsic == Intrinsic.TextureLoad ||
		e.intrinsic == Intrinsic.TextureDimensions ||
		e.intrinsic == Intrinsic.TextureNumSamples);
	if (fetch && e.operands.length > 0 && e.operands[0].kind == ExprKind.Resource &&
		e.operands[0].type.kind == ShaderTypeKind.Texture &&
		!e.operands.some((o) => o.type.kind == ShaderTypeKind.Sampler) &&
		!out.includes(e.operands[0].index)) {
		out.push(e.operands[0].index);
	}
	for (const o of e.operands) { samplerlessReads(o, out); }
}

function samplerlessStmts(stmts: ShaderStmt[], out: int32[]): void {
	for (const s of stmts) {
		samplerlessReads(s.expr, out);
		samplerlessReads(s.target, out);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { samplerlessStmts(list, out); }
		for (const k of s.cases) { samplerlessStmts(k.body, out); }
	}
}

function fetchesThrough(m: ShaderModule, use: PairUse, texture: int32, stage: ShaderStage):
	boolean {
	return use.stage == stage && use.pair.texture == texture && use.pair.sampler >= 0 &&
		m.resources[use.pair.sampler].samplerType != SamplerType.Comparison;
}

function pairSamplerBinding(m: ShaderModule, pair: TexturePair): int32 {
	return pair.sampler < 0 ? -1 : m.resources[pair.sampler].binding;
}

export function bindingSlots(m: ShaderModule, entries: int32[], target: ShaderTarget):
	Result<BindingSlot[], string> {
	let used: Used[] = [];
	let pairs: PairUse[] = [];
	for (const entryIndex of entries) {
		const entry = m.entries[entryIndex];
		const reads = try readsFrom(m, entry.functionIndex);
		for (const index of reads.resources) {
			const r = m.resources[index];
			const owner = "resource '" + r.name + "'";
			const seen = used.filter((u) => u.resource == index);
			if (seen.some((u) => u.stage == entry.stage)) { continue; }
			if (seen.length > 0) {
				used.push({ resource: index, stage: entry.stage });
				continue;
			}
			if (r.binding < 0 || r.binding >= slotLimit(r.kind)) {
				return Result.err(owner + ": @binding(" + String(r.binding) + ") is outside 0.." +
					String(slotLimit(r.kind) - 1));
			}
			for (const u of used) {
				const other = m.resources[u.resource];
				if (other.binding == r.binding && sameSpace(other, r)) {
					return Result.err(owner + ": @binding(" + String(r.binding) + ") is also '" +
						other.name + "', and this program reads both");
				}
			}
			if (target == ShaderTarget.Glsl300es && (r.kind == ResourceKind.StorageBuffer ||
				r.kind == ResourceKind.StorageTexture)) {
				return Result.err(owner + ": GLSL ES 3.0 has no storage resources");
			}
			used.push({ resource: index, stage: entry.stage });
		}
		for (const p of reads.pairs) { pairs.push({ pair: p, stage: entry.stage }); }
		let samplerless: int32[] = [];
		for (const f of reads.functions) { samplerlessStmts(m.functions[f].body, samplerless); }
		for (const texture of samplerless) {
			if (pairs.some((u) => fetchesThrough(m, u, texture, entry.stage))) { continue; }
			pairs.push({ pair: { texture, sampler: -1 }, stage: entry.stage });
		}
	}
	used.sort((a, b) => m.resources[a.resource].binding - m.resources[b.resource].binding);

	let slots: BindingSlot[] = [];
	for (const u of used) {
		if (m.resources[u.resource].kind == ResourceKind.UniformBlock) {
			slots.push(slotOf(m, u, target));
		}
	}
	let viewT = [0, 0, 0];
	let viewU = [0, 0, 0];
	let mslTexture = [0, 0, 0];
	let mslBuffer = [MAX_UNIFORM_SLOTS, MAX_UNIFORM_SLOTS, MAX_UNIFORM_SLOTS];
	let glImage = [0, 0, 0];
	let placed: int32[] = [];
	for (let i = 0; i < m.resources.length; i++) { placed.push(UNPLACED); }
	for (const u of used) {
		const r = m.resources[u.resource];
		if (!isView(r.kind)) { continue; }
		let s = slotOf(m, u, target);
		if (placed[u.resource] != UNPLACED) {
			s.nativeSlot = placed[u.resource];
			slots.push(s);
			continue;
		}
		const stages = used.filter((v) => v.resource == u.resource).map((v) => stageIndex(v.stage));
		const writable = r.kind == ResourceKind.StorageTexture ||
			r.kind == ResourceKind.StorageBuffer && r.access != Access.Read;
		const hlsl = highest(writable ? viewU : viewT, stages);
		const msl = highest(r.kind == ResourceKind.StorageBuffer ? mslBuffer : mslTexture, stages);
		const image = highest(glImage, stages);
		s.nativeSlot = match (target) {
			ShaderTarget.Hlsl5 => hlsl,
			ShaderTarget.Msl => msl,
			ShaderTarget.Glsl430 => match (r.kind) {
				ResourceKind.StorageBuffer => r.binding,
				ResourceKind.StorageTexture => image,
				_ => -1,
			},
			_ => -1,
		};
		for (const st of stages) {
			if (writable) { viewU[st] = hlsl + 1; } else { viewT[st] = hlsl + 1; }
			if (r.kind == ResourceKind.StorageBuffer) {
				mslBuffer[st] = msl + 1;
			} else {
				mslTexture[st] = msl + 1;
			}
			if (r.kind == ResourceKind.StorageTexture) { glImage[st] = image + 1; }
		}
		placed[u.resource] = s.nativeSlot;
		slots.push(s);
	}
	if (target != ShaderTarget.Glsl430 && target != ShaderTarget.Glsl300es) {
		for (const u of used) {
			if (m.resources[u.resource].kind == ResourceKind.Sampler) {
				slots.push(slotOf(m, u, target));
			}
		}
		return Result.ok(slots);
	}
	pairs.sort((a, b) => {
		const byTexture = m.resources[a.pair.texture].binding - m.resources[b.pair.texture].binding;
		return byTexture != 0 ? byTexture :
			pairSamplerBinding(m, a.pair) - pairSamplerBinding(m, b.pair);
	});
	for (const p of pairs) {
		const texture = m.resources[p.pair.texture];
		let s: BindingSlot = {
			resource: -1,
			texture: -1,
			stage: p.stage,
			group: 1,
			binding: -1,
			nativeSlot: -1,
			nativeName: "",
			textureBinding: -1,
		};
		if (p.pair.sampler >= 0) { s = slotOf(m, { resource: p.pair.sampler, stage: p.stage }, target); }
		s.texture = p.pair.texture;
		s.nativeName = texture.name + "_" +
			(p.pair.sampler >= 0 ? m.resources[p.pair.sampler].name : DUMMY_SAMPLER);
		s.textureBinding = texture.binding;
		slots.push(s);
	}
	return Result.ok(slots);
}
