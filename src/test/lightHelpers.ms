import { Sampler, Texture2d, Texture2dU32, Vec4f, vec4f } from "../shader/std";
import { ClusterAssignment } from "../void3d/clusters";
import { clusterTexture, indexTexture, recordTexture } from "../void3d/clusterTextures";
import { LIGHT_RECORD_LENGTH, LIGHT_RECORD_TEXELS, LIGHT_UNIFORM_LENGTH } from "../void3d/gpu3d";
import { LightParams } from "../void3d/shader3d";

export struct LightRecord {
	at: Vec4f;
	tint: Vec4f;
	shapeA: Vec4f;
	shapeB: Vec4f;
	shapeC: Vec4f;
	shapeD: Vec4f;
}

// The lit bindings' light fields for one cluster that lists every record, as a 1×1×1 grid
// assigns them: every fragment reads that cluster.
export struct SceneLights {
	lightParams: LightParams;
	lightRecords: Texture2d;
	clusterRecords: Texture2dU32;
	clusterIndices: Texture2dU32;
	clusterSampler: Sampler;
}

function zero(): Vec4f {
	return vec4f(0.0, 0.0, 0.0, 0.0);
}

export function pointRecord(at: Vec4f, tint: Vec4f): LightRecord {
	return { at: at, tint: tint, shapeA: zero(), shapeB: zero(), shapeC: zero(), shapeD: zero() };
}

function pushQuad(ref out: Vec<float32>, v: Vec4f): void {
	out.push(v.x);
	out.push(v.y);
	out.push(v.z);
	out.push(v.w);
}

function floatTexels(values: Vec<float32>): float32[] {
	let out: float32[] = [];
	for (const v of values) { out.push(v); }
	return out;
}

function wordTexels(values: Vec<uint32>): uint32[] {
	let out: uint32[] = [];
	for (const v of values) { out.push(v); }
	return out;
}

export function sceneLights(
	ambient: Vec4f,
	dirLight: Vec4f,
	dirColor: Vec4f,
	records: Vec<LightRecord>,
): SceneLights {
	const count: int32 = records.length as int32;
	let floats: Vec<float32> = [];
	for (const r of records) {
		pushQuad(floats, r.at);
		pushQuad(floats, r.tint);
		pushQuad(floats, r.shapeA);
		pushQuad(floats, r.shapeB);
		pushQuad(floats, r.shapeC);
		pushQuad(floats, r.shapeD);
	}
	let indices: Vec<int32> = [];
	for (let i = 0; i < count; i++) { indices.push(i); }
	const one: ClusterAssignment = {
		grid: { x: 1, y: 1, z: 1, tileWidth: 1, tileHeight: 1 },
		near: 0.0,
		far: 0.0,
		farthestZ: 0.0,
		offsets: [0],
		counts: [count],
		pointCounts: [count],
		lightIndices: indices,
	};
	const recordData = recordTexture(floats, 0);
	const clusterData = clusterTexture(one);
	const indexData = indexTexture(one);
	return {
		lightParams: {
			ambient: ambient,
			dirLight: dirLight,
			dirColor: dirColor,
			clusterGrid: vec4f(1.0, 1.0, 1.0, 1.0),
			clusterFactors: zero(),
			clusterView: zero(),
			clusterScreen: vec4f(0.0, 1.0, count as float32, 0.0),
		},
		lightRecords: {
			width: recordData.width,
			height: recordData.height,
			texels: floatTexels(recordData.floats),
		},
		clusterRecords: {
			width: clusterData.width,
			height: clusterData.height,
			texels: wordTexels(clusterData.words),
		},
		clusterIndices: {
			width: indexData.width, height: indexData.height, texels: wordTexels(indexData.words),
		},
		clusterSampler: { nearest: true },
	};
}

function quadAt(values: Vec<float32>, at: int32): Vec4f {
	return vec4f(values[at], values[at + 1], values[at + 2], values[at + 3]);
}

// The records of a collectLights span.
export function recordsOf(values: Vec<float32>): Vec<LightRecord> {
	let out: Vec<LightRecord> = [];
	const count: int32 = ((values.length as int32) - LIGHT_UNIFORM_LENGTH) / LIGHT_RECORD_LENGTH;
	for (let i = 0; i < count; i++) {
		const at: int32 = LIGHT_UNIFORM_LENGTH + i * LIGHT_RECORD_LENGTH;
		out.push({
			at: quadAt(values, at), tint: quadAt(values, at + 4),
			shapeA: quadAt(values, at + 8), shapeB: quadAt(values, at + 12),
			shapeC: quadAt(values, at + 16), shapeD: quadAt(values, at + 20),
		});
	}
	return out;
}

// `records` with texel `texel` of light `light` replaced by `value`.
export function withTexel(records: Texture2d, light: int32, texel: int32, value: Vec4f): Texture2d {
	let texels: float32[] = [];
	for (const v of records.texels) { texels.push(v); }
	const first: int32 = (light * LIGHT_RECORD_TEXELS + texel) * 4;
	texels[first] = value.x;
	texels[first + 1] = value.y;
	texels[first + 2] = value.z;
	texels[first + 3] = value.w;
	return { width: records.width, height: records.height, texels: texels };
}
