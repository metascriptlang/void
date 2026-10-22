// litTexturedFs under a pbr-maps key run on the CPU: glTF's metallicRoughnessTexture (roughness
// in G, metalness in B, both times the block's factors) and occlusionTexture (R, scaled by
// strength, dimming the ambient only), held to pbrResponse.ms and an ambient formula written
// apart from shader3d.ms.

import { Vec3, vec3 } from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, mat4x4f, vec2f, vec3f, vec4f } from "../shader/std";
import { LitBindings, LitKey, linearToSrgb, litTexturedFs, srgbToLinear } from "../void3d/shader3d";
import { PbrDirectInput, PbrSurface } from "../void3d/pbrResponse";

function toVec3f(v: Vec3): Vec3f {
	return vec3f(v.x, v.y, v.z);
}

function identity() {
	return mat4x4f(
		vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0),
		vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.0, 0.0, 0.0, 1.0),
	);
}

function none(): Vec4f {
	return vec4f(0.0, 0.0, 0.0, 0.0);
}

function texel(r: float32, g: float32, b: float32): Texture2d {
	return { width: 1, height: 1, texels: [r, g, b, 1.0] };
}

const UP: Vec3 = vec3(0.0, 0.0, 1.0);
const POSITION: Vec3 = vec3(0.5, 0.5, 0.5);
const CAMERA: Vec3 = vec3(0.5, 0.0, 2.0);
const SUN: Vec3 = vec3(0.6, 0.0, 0.8);
const SKY: Vec3 = vec3(0.25, 0.3, 0.4);
const BASE: Vec4f = vec4f(0.9, 0.5, 0.25, 1.0);
const MAPS: LitKey = { pbr: true, pbrMaps: true };

struct Factors {
	metalness: float32;
	roughness: float32;
	strength: float32;
}

const FULL: Factors = { metalness: 1.0, roughness: 1.0, strength: 1.0 };

function bindingsOf(factors: Factors, packed: Texture2d, occlusion: Texture2d): LitBindings {
	return {
		pbrMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			pbr: vec4f(factors.metalness, factors.roughness, 1.0, factors.strength),
		},
		lightParams: {
			ambient: vec4f(SKY.x, SKY.y, SKY.z, 0.0),
			dirLight: vec4f(SUN.x, SUN.y, SUN.z, 1.0),
			dirColor: vec4f(1.0, 1.0, 1.0, 1.0),
			pointLight: [none(), none(), none(), none()],
			pointColor: [none(), none(), none(), none()],
		},
		frameParams: {
			frame: vec4f(0.0, 1.0, 0.0, 0.0),
			cameraPosition: vec4f(CAMERA.x, CAMERA.y, CAMERA.z, 1.0),
		},
		shadowParams: { shadowMatrix: identity(), shadow: none() },
		shadowMap: texel(1.0, 1.0, 1.0),
		shadowSampler: { nearest: true },
		baseTexture: texel(1.0, 1.0, 1.0),
		baseSampler: { nearest: true },
		backTexture: texel(1.0, 1.0, 1.0),
		dissolveTexture: texel(1.0, 1.0, 1.0),
		emissiveTexture: texel(1.0, 1.0, 1.0),
		normalTexture: texel(1.0, 1.0, 1.0),
		metalRoughTexture: packed,
		occlusionTexture: occlusion,
	};
}

function colorOf(factors: Factors, packed: Texture2d, occlusion: Texture2d): Vec3f {
	return litTexturedFs({
		worldPosition: toVec3f(POSITION),
		worldNormal: toVec3f(UP),
		surfaceUv: vec2f(0.5, 0.5),
		baseColor: BASE,
		frontFacing: true,
	}, bindingsOf(factors, packed, occlusion), MAPS).color.rgb;
}

// Lighting.hx:78-99 for one channel on float64, as pbrLitCheck.ms writes it.
function ambientChannel(
	albedo: float32, sky: float32, metalness: float32, roughness: float32, occlusion: float32,
): float32 {
	const toCamera: Vec3 = vec3(CAMERA.x - POSITION.x, CAMERA.y - POSITION.y, CAMERA.z - POSITION.z);
	const nv: float64 = toCamera.z / Math.sqrt(toCamera.dot(toCamera));
	const weight: float64 = Math.pow(2.0, (-5.55473 * nv - 6.98316) * nv);
	const f0: float64 = (0.04 * (1.0 - metalness) + albedo * metalness) as float64;
	const gloss: float64 = (1.0 - roughness) as float64;
	const fresnel: float64 = f0 + (Math.max(gloss, f0) - f0) * weight;
	return (sky * albedo * (1.0 - metalness) * (1.0 - fresnel) * occlusion) as float32;
}

function expectedColor(metalness: float32, roughness: float32, occlusion: float32): Vec3f {
	const albedo: Vec3f = srgbToLinear(BASE.rgb);
	const sky: Vec3f = srgbToLinear(vec3f(SKY.x, SKY.y, SKY.z));
	const toCamera: Vec3 = vec3(CAMERA.x - POSITION.x, CAMERA.y - POSITION.y, CAMERA.z - POSITION.z);
	const surface: PbrSurface = {
		linearAlbedo: vec3(albedo.x, albedo.y, albedo.z),
		properties: { metalness: metalness, roughness: roughness, occlusion: occlusion },
	};
	const input: PbrDirectInput = {
		normal: UP, view: toCamera, light: SUN, radiance: vec3(1.0, 1.0, 1.0),
		shadow: 1.0, directOcclusionFactor: 0.0,
	};
	const response = surface.direct(input);
	if (!response.ok) { unreachable; }
	const direct: Vec3 = response.value;
	return linearToSrgb(vec3f(
		ambientChannel(albedo.x, sky.x, metalness, roughness, occlusion) + direct.x,
		ambientChannel(albedo.y, sky.y, metalness, roughness, occlusion) + direct.y,
		ambientChannel(albedo.z, sky.z, metalness, roughness, occlusion) + direct.z,
	));
}

function nearColor(a: Vec3f, b: Vec3f): boolean {
	return Math.abs(a.x - b.x) <= 1e-4 && Math.abs(a.y - b.y) <= 1e-4 &&
		Math.abs(a.z - b.z) <= 1e-4;
}

test "the packed texel is read as roughness G and metalness B, and swapping them is caught" {
	const packed: Texture2d = texel(0.7, 0.3, 0.9);
	const color: Vec3f = colorOf(FULL, packed, texel(1.0, 1.0, 1.0));
	assert nearColor(color, expectedColor(0.9, 0.3, 1.0));
	assert !nearColor(color, expectedColor(0.3, 0.9, 1.0));
	assert !nearColor(color, expectedColor(0.7, 0.3, 1.0));
}

test "the block's factors multiply the texel: 0.5 of 0.5 is a quarter" {
	const factors: Factors = { metalness: 0.5, roughness: 0.8, strength: 1.0 };
	const color: Vec3f = colorOf(factors, texel(0.0, 0.5, 0.5), texel(1.0, 1.0, 1.0));
	assert nearColor(color, expectedColor(0.25, 0.4, 1.0));
	assert !nearColor(color, expectedColor(0.5, 0.8, 1.0));
}

test "a white texel leaves the factors alone, so a missing map costs nothing" {
	const factors: Factors = { metalness: 0.25, roughness: 0.75, strength: 1.0 };
	const color: Vec3f = colorOf(factors, texel(1.0, 1.0, 1.0), texel(1.0, 1.0, 1.0));
	assert nearColor(color, expectedColor(0.25, 0.75, 1.0));
}

test "occlusion is 1 plus strength times (R minus 1), dims the ambient and leaves the sun" {
	const half: Factors = { metalness: 0.0, roughness: 0.7, strength: 0.5 };
	const dark: Texture2d = texel(0.2, 0.0, 0.0);
	const white: Texture2d = texel(1.0, 1.0, 1.0);
	const color: Vec3f = colorOf(half, white, dark);
	assert nearColor(color, expectedColor(0.0, 0.7, 1.0 + 0.5 * (0.2 - 1.0)));
	const open: Vec3f = colorOf(half, white, white);
	assert color.x < open.x && !nearColor(color, expectedColor(0.0, 0.7, 0.2));
	const none: Factors = { metalness: 0.0, roughness: 0.7, strength: 0.0 };
	assert nearColor(colorOf(none, white, dark), open);
	const full: Factors = { metalness: 0.0, roughness: 0.7, strength: 1.0 };
	assert nearColor(colorOf(full, white, dark), expectedColor(0.0, 0.7, 0.2));
}

test "only the named channels are read: R and A of the packed texel, G and B of occlusion, are free" {
	const a: Vec3f = colorOf(FULL, texel(0.0, 0.4, 0.6), texel(0.5, 0.0, 0.0));
	const b: Vec3f = colorOf(FULL, texel(1.0, 0.4, 0.6), texel(0.5, 1.0, 1.0));
	assert nearColor(a, b);
}

test "a roughness texel of 0 floors at 0.089 instead of leaving the BRDF undefined" {
	const color: Vec3f = colorOf(FULL, texel(1.0, 0.0, 0.0), texel(1.0, 1.0, 1.0));
	assert Number.isFinite(color.x) && Number.isFinite(color.y) && Number.isFinite(color.z);
	assert nearColor(color, expectedColor(0.0, 0.089, 1.0));
	assert nearColor(colorOf(FULL, texel(1.0, 0.05, 0.0), texel(1.0, 1.0, 1.0)),
		expectedColor(0.0, 0.089, 1.0));
	assert !nearColor(colorOf(FULL, texel(1.0, 0.2, 0.0), texel(1.0, 1.0, 1.0)),
		expectedColor(0.0, 0.089, 1.0));
}
