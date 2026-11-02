import { Vec3, vec3, srgbToLinear } from "../math/math3d";

export enum PbrResponseError {
	NonFinite,
	OutOfRange,
	ZeroDirection,
	ZeroRoughness,
	Unrepresentable,
}

export struct PbrProperties {
	metalness: float32;
	roughness: float32;
	occlusion: float32;
}

export struct PbrSurface {
	linearAlbedo: Vec3;
	properties: PbrProperties;
}

// View/light point from surface toward camera/light; radiance excludes NdL and shadow.
export struct PbrDirectInput {
	normal: Vec3;
	view: Vec3;
	light: Vec3;
	radiance: Vec3;
	shadow: float32;
	directOcclusionFactor: float32;
}

function finiteVector(this value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function unitInterval(value: float32): boolean {
	return value >= 0.0 && value <= 1.0;
}

function unitColor(this value: Vec3): boolean {
	return unitInterval(value.x) && unitInterval(value.y) && unitInterval(value.z);
}

export function heapsValues(
	this typeof PbrProperties,
	metalness: float32 = 0.0,
	roughness: float32 = 1.0,
	occlusion: float32 = 1.0,
): Result<PbrProperties, PbrResponseError> {
	if (!Number.isFinite(metalness) || !Number.isFinite(roughness) || !Number.isFinite(occlusion)) {
		return Result.err(PbrResponseError.NonFinite);
	}
	if (!unitInterval(metalness) || !unitInterval(roughness) || !unitInterval(occlusion)) {
		return Result.err(PbrResponseError.OutOfRange);
	}
	return Result.ok({ metalness: metalness, roughness: roughness, occlusion: occlusion });
}

export function heapsMap(
	this typeof PbrProperties,
	sample: Vec3,
): Result<PbrProperties, PbrResponseError> {
	if (!sample.finiteVector()) { return Result.err(PbrResponseError.NonFinite); }
	if (!sample.unitColor()) { return Result.err(PbrResponseError.OutOfRange); }
	return Result.ok({
		metalness: sample.x,
		roughness: 1.0 - sample.y * sample.y,
		occlusion: sample.z,
	});
}

// glTF b43260ee material.pbrMetallicRoughness / material.occlusionTextureInfo schemas:
// missing factors and MR texture G/B are 1; an absent AO map is identity. R/A are ignored.
export function gltfMap(
	this typeof PbrProperties,
	metallicFactor: float32 = 1.0,
	roughnessFactor: float32 = 1.0,
	metallicRoughnessSample: Vec3 = vec3(1.0, 1.0, 1.0),
	occlusionStrength: float32 = 1.0,
	occlusionRed: float32 = 1.0,
): Result<PbrProperties, PbrResponseError> {
	if (!Number.isFinite(metallicFactor) || !Number.isFinite(roughnessFactor) ||
		!Number.isFinite(metallicRoughnessSample.y) ||
		!Number.isFinite(metallicRoughnessSample.z) ||
		!Number.isFinite(occlusionStrength) || !Number.isFinite(occlusionRed)) {
		return Result.err(PbrResponseError.NonFinite);
	}
	if (!unitInterval(metallicFactor) || !unitInterval(roughnessFactor) ||
		!unitInterval(metallicRoughnessSample.y) || !unitInterval(metallicRoughnessSample.z) ||
		!unitInterval(occlusionStrength) || !unitInterval(occlusionRed)) {
		return Result.err(PbrResponseError.OutOfRange);
	}
	return Result.ok({
		metalness: metallicFactor * metallicRoughnessSample.z,
		roughness: roughnessFactor * metallicRoughnessSample.y,
		occlusion: 1.0 + occlusionStrength * (occlusionRed - 1.0),
	});
}

export function gltfLinearAlbedo(
	encodedTexture: Vec3 = vec3(1.0, 1.0, 1.0),
	linearFactor: Vec3 = vec3(1.0, 1.0, 1.0),
	linearVertexColor: Vec3 = vec3(1.0, 1.0, 1.0),
): Result<Vec3, PbrResponseError> {
	if (!encodedTexture.finiteVector() || !linearFactor.finiteVector() ||
		!linearVertexColor.finiteVector()) {
		return Result.err(PbrResponseError.NonFinite);
	}
	if (!encodedTexture.unitColor() || !linearFactor.unitColor() ||
		!linearVertexColor.unitColor()) {
		return Result.err(PbrResponseError.OutOfRange);
	}
	return Result.ok(vec3(
		srgbToLinear(encodedTexture.x) * linearFactor.x * linearVertexColor.x,
		srgbToLinear(encodedTexture.y) * linearFactor.y * linearVertexColor.y,
		srgbToLinear(encodedTexture.z) * linearFactor.z * linearVertexColor.z,
	));
}

function direction(this value: Vec3): Result<Vec3, PbrResponseError> {
	if (!value.finiteVector()) { return Result.err(PbrResponseError.NonFinite); }
	const squared: float32 = value.dot(value);
	if (!Number.isFinite(squared)) { return Result.err(PbrResponseError.Unrepresentable); }
	if (squared <= 0.0) { return Result.err(PbrResponseError.ZeroDirection); }
	const result: Vec3 = value.scaled(1.0 / (Math.sqrt(squared) as float32));
	if (!result.finiteVector()) { return Result.err(PbrResponseError.Unrepresentable); }
	return Result.ok(result);
}

function facing(value: float32): float32 {
	return Math.max(0.0, Math.min(value, 1.0));
}

function channelResponse(
	albedo: float32,
	metalness: float32,
	distribution: float32,
	visibility: float32,
	fresnelWeight: float32,
): float32 {
	const normalReflectance: float32 = 0.04 * (1.0 - metalness) + albedo * metalness;
	const fresnel: float32 = normalReflectance + (1.0 - normalReflectance) * fresnelWeight;
	const diffuse: float32 = albedo / (Math.PI as float32);
	return diffuse * (1.0 - metalness) * (1.0 - fresnel) +
		Math.max(distribution * fresnel * visibility, 0.0);
}

// Heaps BRDF.hx:40-63 has no isotropic endpoint guard. Report unsupported evaluation;
// preserve canonical roughness, never substitute a floor or a mirror response.
export function direct(
	this surface: PbrSurface,
	input: PbrDirectInput,
): Result<Vec3, PbrResponseError> {
	const properties: PbrProperties = surface.properties;
	if (!surface.linearAlbedo.finiteVector() || !input.radiance.finiteVector() ||
		!Number.isFinite(properties.metalness) || !Number.isFinite(properties.roughness) ||
		!Number.isFinite(properties.occlusion) || !Number.isFinite(input.shadow) ||
		!Number.isFinite(input.directOcclusionFactor)) {
		return Result.err(PbrResponseError.NonFinite);
	}
	if (!surface.linearAlbedo.unitColor() || !unitInterval(properties.metalness) ||
		!unitInterval(properties.roughness) || !unitInterval(properties.occlusion) ||
		!unitInterval(input.shadow) || !unitInterval(input.directOcclusionFactor) ||
		input.radiance.x < 0.0 || input.radiance.y < 0.0 || input.radiance.z < 0.0) {
		return Result.err(PbrResponseError.OutOfRange);
	}
	if (properties.roughness == 0.0) { return Result.err(PbrResponseError.ZeroRoughness); }
	const normal: Vec3 = try input.normal.direction();
	const view: Vec3 = try input.view.direction();
	const light: Vec3 = try input.light.direction();
	const normalLight: float32 = facing(normal.dot(light));
	const energySquared: float32 = input.radiance.dot(input.radiance);
	if (!Number.isFinite(energySquared)) {
		return Result.err(PbrResponseError.Unrepresentable);
	}
	if (normalLight <= 0.0 || energySquared <= 0.0001) {
		return Result.ok(vec3(0.0, 0.0, 0.0));
	}
	const half: Vec3 = try (light + view).direction();
	const normalHalf: float32 = facing(normal.dot(half));
	const viewHalf: float32 = facing(view.dot(half));
	const normalView: float32 = facing(normal.dot(view));
	const alpha: float32 = properties.roughness * properties.roughness;
	const alphaSquared: float32 = alpha * alpha;
	const denominator: float32 = normalHalf * normalHalf * (alphaSquared - 1.0) + 1.0;
	const distributionDenominator: float32 =
		(Math.PI as float32) * denominator * denominator;
	if (alphaSquared <= 0.0 || denominator <= 0.0 || distributionDenominator <= 0.0) {
		return Result.err(PbrResponseError.Unrepresentable);
	}
	const distribution: float32 = alphaSquared / distributionDenominator;
	const remapping: float32 = properties.roughness + 1.0;
	const k: float32 = remapping * remapping * 0.125;
	const visibility: float32 = (1.0 / (normalView * (1.0 - k) + k)) *
		(1.0 / (normalLight * (1.0 - k) + k)) * 0.25;
	const exponent: float32 = (-5.55473 * viewHalf - 6.98316) * viewHalf;
	const fresnelWeight: float32 = Math.pow(2.0, exponent as float64) as float32;
	const occlusion: float32 = 1.0 + input.directOcclusionFactor * (properties.occlusion - 1.0);
	const attenuation: float32 = normalLight * input.shadow * occlusion;
	const albedo: Vec3 = surface.linearAlbedo;
	const result: Vec3 = vec3(
		channelResponse(albedo.x, properties.metalness, distribution, visibility, fresnelWeight) *
			input.radiance.x * attenuation,
		channelResponse(albedo.y, properties.metalness, distribution, visibility, fresnelWeight) *
			input.radiance.y * attenuation,
		channelResponse(albedo.z, properties.metalness, distribution, visibility, fresnelWeight) *
			input.radiance.z * attenuation,
	);
	if (!Number.isFinite(distribution) || !Number.isFinite(visibility) || !result.finiteVector()) {
		return Result.err(PbrResponseError.Unrepresentable);
	}
	return Result.ok(result);
}

export function gltfDirect(
	this surface: PbrSurface,
	input: PbrDirectInput,
): Result<Vec3, PbrResponseError> {
	return surface.direct({ ...input, directOcclusionFactor: 0.0 });
}
