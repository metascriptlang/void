import { Vec3, vec3 } from "../math/math3d";

export enum PbrEnvironmentError {
	NonFinite,
	OutOfRange,
	ZeroSamples,
	ZeroDirection,
	Unrepresentable,
}

// Heaps: `_reversebits(i) * 2.3283064365386963e-10` is a signed int, so odd i give a second
// coordinate in [-0.5, 0). Unit is the Hammersley set by definition, in [0, 1).
export enum HammersleyForm {
	Heaps,
	Unit,
}

export struct Point2 {
	x: float32;
	y: float32;
}

export struct SplitSum {
	scale: float32;
	bias: float32;
}

export struct CubeTexel {
	face: int32;
	u: float32;
	v: float32;
}

export struct RadianceSample {
	direction: Vec3;
	radiance: Vec3;
	solidAngle: float32;
}

// Order: L00, L1-1, L10, L11, L2-2, L2-1, L20, L21, L22.
export struct ShCoefficients {
	bands: Vec3[9];
}

// Lighting.hx:85-99 on plain values; diffuseIrradiance is irrDiffuse.get and specularRadiance
// is irrSpecular.textureLod, both already rotated and fetched.
export struct PbrIndirectInput {
	diffuseIrradiance: Vec3;
	specularRadiance: Vec3;
	albedo: Vec3;
	metalness: float32;
	roughness: float32;
	occlusion: float32;
	normalView: float32;
	lut: SplitSum;
	power: float32;
}

struct FaceBasis {
	right: Vec3;
	up: Vec3;
	forward: Vec3;
}

struct Frame {
	tangent: Vec3;
	bitangent: Vec3;
}

const PI: float32 = 3.14159265358979 as float32;

function root(value: float32): float32 { return Math.sqrt(value as float64) as float32; }
function sine(value: float32): float32 { return Math.sin(value as float64) as float32; }
function cosine(value: float32): float32 { return Math.cos(value as float64) as float32; }
function saturate(value: float32): float32 { return Math.max(0.0, Math.min(value, 1.0)); }
function unitInterval(value: float32): boolean { return value >= 0.0 && value <= 1.0; }

function finiteVector(this value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function direction(this value: Vec3): Result<Vec3, PbrEnvironmentError> {
	if (!value.finiteVector()) { return Result.err(PbrEnvironmentError.NonFinite); }
	const squared: float32 = value.dot(value);
	if (!Number.isFinite(squared)) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	if (squared <= 0.0) { return Result.err(PbrEnvironmentError.ZeroDirection); }
	const result: Vec3 = value.scaled(1.0 / root(squared));
	if (!result.finiteVector()) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	return Result.ok(result);
}

function reverseBits(index: int32): uint32 {
	const m1: uint32 = 0x00ff00ff;
	const m2: uint32 = 0xff00ff00;
	const m3: uint32 = 0x0f0f0f0f;
	const m4: uint32 = 0xf0f0f0f0;
	const m5: uint32 = 0x33333333;
	const m6: uint32 = 0xcccccccc;
	const m7: uint32 = 0x55555555;
	const m8: uint32 = 0xaaaaaaaa;
	let r: uint32 = index as uint32;
	r = (r << 16) | (r >>> 16);
	r = ((r & m1) << 8) | ((r & m2) >>> 8);
	r = ((r & m3) << 4) | ((r & m4) >>> 4);
	r = ((r & m5) << 2) | ((r & m6) >>> 2);
	r = ((r & m7) << 1) | ((r & m8) >>> 1);
	return r;
}

function pointAt(index: int32, count: int32, form: HammersleyForm): Point2 {
	const unit: float64 = (reverseBits(index) as float64) / 4294967296.0;
	const second: float64 = form == HammersleyForm.Heaps && unit >= 0.5 ? unit - 1.0 : unit;
	return { x: ((index as float64) / (count as float64)) as float32, y: second as float32 };
}

// Environment.hx:18-21 (IrradBase.hammersley).
export function hammersley(
	index: int32,
	count: int32,
	form: HammersleyForm = HammersleyForm.Heaps,
): Result<Point2, PbrEnvironmentError> {
	if (count <= 0) { return Result.err(PbrEnvironmentError.ZeroSamples); }
	if (index < 0 || index >= count) { return Result.err(PbrEnvironmentError.OutOfRange); }
	return Result.ok(pointAt(index, count, form));
}

function frameOf(normal: Vec3): Frame {
	const up: Vec3 =
		Math.abs(normal.z as float64) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	const tangent: Vec3 = up.cross(normal).normalized();
	return { tangent: tangent, bitangent: normal.cross(tangent).normalized() };
}

function inFrame(normal: Vec3, local: Vec3): Vec3 {
	const frame: Frame = frameOf(normal);
	return (frame.tangent.scaled(local.x) + frame.bitangent.scaled(local.y) +
		normal.scaled(local.z)).normalized();
}

// Environment.hx:67-77 (IrradShader.cosineWeightedSampling).
export function cosineWeightedSample(
	p: Point2,
	normal: Vec3,
): Result<Vec3, PbrEnvironmentError> {
	if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	if (p.x < 0.0 || p.x > 1.0) { return Result.err(PbrEnvironmentError.OutOfRange); }
	const n: Vec3 = try normal.direction();
	const radius: float32 = root(1.0 - p.x);
	const alpha: float32 = 2.0 * PI * p.y;
	const result: Vec3 = inFrame(n, vec3(radius * cosine(alpha), radius * sine(alpha), root(p.x)));
	if (!result.finiteVector()) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	return Result.ok(result);
}

function ggxHalf(roughness: float32, p: Point2, n: Vec3): Vec3 {
	const a: float32 = roughness * roughness;
	const phi: float32 = 2.0 * PI * p.x;
	const cosT: float32 = Math.min(root((1.0 - p.y) / (1.0 + (a * a - 1.0) * p.y)), 1.0);
	const sinT: float32 = root(1.0 - cosT * cosT);
	return inFrame(n, vec3(sinT * cosine(phi), sinT * sine(phi), cosT));
}

// Environment.hx:23-33 (IrradBase.importanceSampleGGX). Roughness 0 has no guard there: a = 0
// gives cosT = 1, so every sample is the normal.
export function importanceSampleGgx(
	roughness: float32,
	p: Point2,
	normal: Vec3,
): Result<Vec3, PbrEnvironmentError> {
	if (!Number.isFinite(roughness) || !Number.isFinite(p.x) || !Number.isFinite(p.y)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	if (!unitInterval(roughness) || p.y >= 1.0) {
		return Result.err(PbrEnvironmentError.OutOfRange);
	}
	const n: Vec3 = try normal.direction();
	const result: Vec3 = ggxHalf(roughness, p, n);
	if (!result.finiteVector()) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	return Result.ok(result);
}

function faceBasis(face: int32): FaceBasis {
	return match (face) {
		0 => ({
			right: vec3(0.0, 0.0, -1.0), up: vec3(0.0, -1.0, 0.0), forward: vec3(1.0, 0.0, 0.0),
		}),
		1 => ({
			right: vec3(0.0, 0.0, 1.0), up: vec3(0.0, -1.0, 0.0), forward: vec3(-1.0, 0.0, 0.0),
		}),
		2 => ({
			right: vec3(1.0, 0.0, 0.0), up: vec3(0.0, 0.0, 1.0), forward: vec3(0.0, 1.0, 0.0),
		}),
		3 => ({
			right: vec3(1.0, 0.0, 0.0), up: vec3(0.0, 0.0, -1.0), forward: vec3(0.0, -1.0, 0.0),
		}),
		4 => ({
			right: vec3(1.0, 0.0, 0.0), up: vec3(0.0, -1.0, 0.0), forward: vec3(0.0, 0.0, 1.0),
		}),
		_ => ({
			right: vec3(-1.0, 0.0, 0.0), up: vec3(0.0, -1.0, 0.0), forward: vec3(0.0, 0.0, -1.0),
		}),
	};
}

// Faces +X -X +Y -Y +Z -Z, the sokol_gfx.h:3521-3529 order. Basis rows are Environment.hx
// getCubeMatrix :330-351 and the direction is IrradShader.getNormal :79-86 without the specular
// edge fixup: normalize(d.x * right + d.y * up + forward), d = uv * 2 - 1.
export function cubeFaceDirection(
	face: int32,
	u: float32,
	v: float32,
): Result<Vec3, PbrEnvironmentError> {
	if (!Number.isFinite(u) || !Number.isFinite(v)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	if (face < 0 || face > 5 || !unitInterval(u) || !unitInterval(v)) {
		return Result.err(PbrEnvironmentError.OutOfRange);
	}
	const basis: FaceBasis = faceBasis(face);
	return (basis.right.scaled(u * 2.0 - 1.0) + basis.up.scaled(v * 2.0 - 1.0) +
		basis.forward).direction();
}

// The inverse of cubeFaceDirection. Heaps has none (the GPU's cube sampler does it); a tie on
// the major axis goes to the lowest face index.
export function directionToCubeTexel(
	value: Vec3,
): Result<CubeTexel, PbrEnvironmentError> {
	const n: Vec3 = try value.direction();
	let face: int32 = 0;
	let best: float32 = -2.0;
	for (let candidate = 0; candidate < 6; candidate++) {
		const along: float32 = n.dot(faceBasis(candidate).forward);
		if (along > best) {
			best = along;
			face = candidate;
		}
	}
	const basis: FaceBasis = faceBasis(face);
	return Result.ok({
		face: face,
		u: (n.dot(basis.right) / best + 1.0) * 0.5,
		v: (n.dot(basis.up) / best + 1.0) * 0.5,
	});
}

// Environment.hx:116-154 (IrradLut.fragment) at one (roughness, NoV) point: the default sample
// count is Heaps' 4096 (samplesBits 12, :239). Heaps shades texel centres, so NoV = 0 (0/0 in
// gvis) is refused; roughness 0 is accepted because the code has no guard there either.
export function splitSumLut(
	roughness: float32,
	normalView: float32,
	samples: int32 = 4096,
	form: HammersleyForm = HammersleyForm.Heaps,
): Result<SplitSum, PbrEnvironmentError> {
	if (!Number.isFinite(roughness) || !Number.isFinite(normalView)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	if (samples <= 0) { return Result.err(PbrEnvironmentError.ZeroSamples); }
	if (!unitInterval(roughness) || !(normalView > 0.0 && normalView <= 1.0)) {
		return Result.err(PbrEnvironmentError.OutOfRange);
	}
	const view: Vec3 = vec3(root(1.0 - normalView * normalView), 0.0, normalView);
	const normal: Vec3 = vec3(0.0, 0.0, 1.0);
	const k: float32 = roughness * roughness * 0.5;
	let a: float64 = 0.0;
	let b: float64 = 0.0;
	for (let i = 0; i < samples; i++) {
		const half: Vec3 = ggxHalf(roughness, pointAt(i, samples, form), normal);
		const light: Vec3 = view.scaled(-1.0) - half.scaled(-2.0 * view.dot(half));
		const normalLight: float32 = saturate(light.z);
		const normalHalf: float32 = saturate(half.z);
		const viewHalf: float32 = saturate(view.dot(half));
		if (normalLight > 0.0) {
			const geometry: float32 = normalLight / (normalLight * (1.0 - k) + k) *
				(normalView / (normalView * (1.0 - k) + k));
			const visibility: float32 = geometry * viewHalf / (normalHalf * normalView);
			const fresnel: float32 = Math.pow((1.0 - viewHalf) as float64, 5.0) as float32;
			a += ((1.0 - fresnel) * visibility) as float64;
			b += (fresnel * visibility) as float64;
		}
	}
	const result: SplitSum = {
		scale: (a / (samples as float64)) as float32,
		bias: (b / (samples as float64)) as float32,
	};
	if (!Number.isFinite(result.scale) || !Number.isFinite(result.bias)) {
		return Result.err(PbrEnvironmentError.Unrepresentable);
	}
	return Result.ok(result);
}

// Bevy pbr_lighting.wesl:527-538 (the no-DFG_LUT branch, UE mobile polynomial).
export function splitSumAnalytic(
	roughness: float32,
	normalView: float32,
): Result<SplitSum, PbrEnvironmentError> {
	if (!Number.isFinite(roughness) || !Number.isFinite(normalView)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	if (!unitInterval(roughness) || !unitInterval(normalView)) {
		return Result.err(PbrEnvironmentError.OutOfRange);
	}
	const rx: float32 = roughness * -1.0 + 1.0;
	const ry: float32 = roughness * -0.0275 + 0.0425;
	const rz: float32 = roughness * -0.572 + 1.04;
	const rw: float32 = roughness * 0.022 - 0.04;
	const falloff: float32 = Math.pow(2.0, (-9.28 * normalView) as float64) as float32;
	const a004: float32 = Math.min(rx * rx, falloff) * rx + ry;
	const floor: float32 = 0.00005;
	return Result.ok({
		scale: Math.max(-1.04 * a004 + rz, floor),
		bias: Math.max(1.04 * a004 + rw, floor),
	});
}

function indirectChannel(
	diffuseIrradiance: float32,
	specularRadiance: float32,
	albedo: float32,
	metalness: float32,
	roughness: float32,
	fresnelWeight: float32,
	lut: SplitSum,
): float32 {
	const normalReflectance: float32 = 0.04 * (1.0 - metalness) + albedo * metalness;
	const fresnel: float32 = normalReflectance +
		(Math.max(1.0 - roughness, normalReflectance) - normalReflectance) * fresnelWeight;
	const diffuse: float32 = diffuseIrradiance * albedo;
	const specular: float32 = specularRadiance * (fresnel * lut.scale + lut.bias);
	return diffuse * (1.0 - metalness) * (1.0 - fresnel) + specular;
}

// Lighting.hx:85-99 without the sky and emissive terms: `indirect * irrPower * occlusion`.
// The F0 mix is PropsImport.hx:74.
export function pbrIndirect(
	input: PbrIndirectInput,
): Result<Vec3, PbrEnvironmentError> {
	if (!input.diffuseIrradiance.finiteVector() || !input.specularRadiance.finiteVector() ||
		!input.albedo.finiteVector() || !Number.isFinite(input.metalness) ||
		!Number.isFinite(input.roughness) || !Number.isFinite(input.occlusion) ||
		!Number.isFinite(input.normalView) || !Number.isFinite(input.lut.scale) ||
		!Number.isFinite(input.lut.bias) || !Number.isFinite(input.power)) {
		return Result.err(PbrEnvironmentError.NonFinite);
	}
	const radiance: Vec3 = input.diffuseIrradiance;
	const specular: Vec3 = input.specularRadiance;
	const albedo: Vec3 = input.albedo;
	if (radiance.x < 0.0 || radiance.y < 0.0 || radiance.z < 0.0 ||
		specular.x < 0.0 || specular.y < 0.0 || specular.z < 0.0 ||
		!unitInterval(albedo.x) || !unitInterval(albedo.y) || !unitInterval(albedo.z) ||
		!unitInterval(input.metalness) || !unitInterval(input.roughness) ||
		!unitInterval(input.occlusion) || !unitInterval(input.normalView) ||
		input.lut.scale < 0.0 || input.lut.bias < 0.0 || input.power < 0.0) {
		return Result.err(PbrEnvironmentError.OutOfRange);
	}
	const weight: float32 = Math.pow(2.0,
		((-5.55473 * input.normalView - 6.98316) * input.normalView) as float64) as float32;
	const scale: float32 = input.power * input.occlusion;
	const result: Vec3 = vec3(
		indirectChannel(radiance.x, specular.x, albedo.x, input.metalness, input.roughness,
			weight, input.lut) * scale,
		indirectChannel(radiance.y, specular.y, albedo.y, input.metalness, input.roughness,
			weight, input.lut) * scale,
		indirectChannel(radiance.z, specular.z, albedo.z, input.metalness, input.roughness,
			weight, input.lut) * scale,
	);
	if (!result.finiteVector()) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	return Result.ok(result);
}

// Not in Heaps: Heaps bakes a 64x64 cosine-weighted cube (Environment.hx:239, :371-405).
// Real spherical-harmonics basis, Ramamoorthi and Hanrahan 2001 eq. 3 and 12.
function shBasis(index: int32, d: Vec3): float32 {
	return match (index) {
		0 => 0.282095,
		1 => 0.488603 * d.y,
		2 => 0.488603 * d.z,
		3 => 0.488603 * d.x,
		4 => 1.092548 * d.x * d.y,
		5 => 1.092548 * d.y * d.z,
		6 => 0.315392 * (3.0 * d.z * d.z - 1.0),
		7 => 1.092548 * d.x * d.z,
		_ => 0.546274 * (d.x * d.x - d.y * d.y),
	};
}

function shConvolution(index: int32): float32 {
	return index == 0 ? PI : (index < 4 ? 2.0 * PI / 3.0 : PI / 4.0);
}

// Not in Heaps. sum over samples of radiance * basis * solidAngle; the solid angles of a
// quadrature sum to 4 pi.
export function projectSh(
	samples: Readonly<Span<RadianceSample>>,
): Result<ShCoefficients, PbrEnvironmentError> {
	if (samples.length == 0) { return Result.err(PbrEnvironmentError.ZeroSamples); }
	const zero: Vec3 = vec3(0.0, 0.0, 0.0);
	let bands: Vec3[9] = [zero, zero, zero, zero, zero, zero, zero, zero, zero];
	for (const sample of samples) {
		if (!sample.radiance.finiteVector() || !Number.isFinite(sample.solidAngle)) {
			return Result.err(PbrEnvironmentError.NonFinite);
		}
		if (sample.radiance.x < 0.0 || sample.radiance.y < 0.0 || sample.radiance.z < 0.0 ||
			sample.solidAngle <= 0.0) {
			return Result.err(PbrEnvironmentError.OutOfRange);
		}
		const d: Vec3 = try sample.direction.direction();
		for (let k = 0; k < 9; k++) {
			bands[k] = bands[k] + sample.radiance.scaled(shBasis(k, d) * sample.solidAngle);
		}
	}
	return Result.ok({ bands: bands });
}

// Not in Heaps. Cosine-convolved irradiance E(n) (pi * L for a constant radiance L); Heaps'
// irrDiffuse stores the cosine-weighted average E / pi.
export function shIrradiance(
	this coefficients: ShCoefficients,
	normal: Vec3,
): Result<Vec3, PbrEnvironmentError> {
	const n: Vec3 = try normal.direction();
	let sum: Vec3 = vec3(0.0, 0.0, 0.0);
	for (let k = 0; k < 9; k++) {
		sum = sum + coefficients.bands[k].scaled(shConvolution(k) * shBasis(k, n));
	}
	if (!sum.finiteVector()) { return Result.err(PbrEnvironmentError.Unrepresentable); }
	return Result.ok(sum);
}
