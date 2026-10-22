// The lit programs' PBR path run on the CPU: shader3d.ms pbrDirect held to pbrResponse.ms, the
// landed oracle of Heaps' direct BRDF, and litFs under a pbr key held to that oracle plus an
// independent ambient formula.

import { Vec3, vec3 } from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, mat4x4f, vec3f, vec4f } from "../shader/std";
import {
	Program,
	ProgramKey,
	PBR_METALNESS,
	PBR_MATERIAL_UNIFORM_LENGTH,
	PBR_OCCLUSION,
	PBR_ROUGHNESS,
	MATERIAL_UNIFORM_LENGTH,
	MATERIAL_UNIFORM_SLOT,
	declares,
	uniformBlockLength,
} from "../void3d/gpu3d";
import { pbrBlock } from "../void3d/material";
import {
	PbrDirectInput,
	PbrProperties,
	PbrResponseError,
	PbrSurface,
} from "../void3d/pbrResponse";
import {
	LitBindings,
	LitKey,
	linearToSrgb,
	litFs,
	pbrDirect,
	srgbToLinear,
} from "../void3d/shader3d";

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) <= 2e-5 * Math.max(1.0, Math.abs(b));
}

function nearVec(a: Vec3f, b: Vec3): boolean {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z);
}

function toVec3f(v: Vec3): Vec3f {
	return vec3f(v.x, v.y, v.z);
}

const ALBEDO: Vec3 = vec3(0.8, 0.2, 0.05);
const RADIANCE: Vec3 = vec3(2.0, 0.5, 1.5);
const UP: Vec3 = vec3(0.0, 0.0, 1.0);

function oracle(
	metalness: float32, roughness: float32, view: Vec3, light: Vec3,
	shadow: float32, occlusionFactor: float32, occlusion: float32,
	albedo: Vec3 = ALBEDO, radiance: Vec3 = RADIANCE,
): Vec3 {
	const surface: PbrSurface = {
		linearAlbedo: albedo,
		properties: { metalness: metalness, roughness: roughness, occlusion: occlusion },
	};
	const input: PbrDirectInput = {
		normal: UP, view: view, light: light, radiance: radiance,
		shadow: shadow, directOcclusionFactor: occlusionFactor,
	};
	const response = surface.direct(input);
	if (!response.ok) { unreachable; }
	return response.value;
}

function shader(
	metalness: float32, roughness: float32, view: Vec3, light: Vec3,
	shadow: float32, occlusionFactor: float32, occlusion: float32,
): Vec3f {
	return pbrDirect(toVec3f(ALBEDO), metalness, roughness, toVec3f(UP), toVec3f(view),
		toVec3f(light), toVec3f(RADIANCE), shadow, occlusionFactor, occlusion);
}

test "pbrDirect equals the pbrResponse oracle on a rough dielectric" {
	const view: Vec3 = vec3(0.0, 0.0, 1.0);
	const light: Vec3 = vec3(0.6, 0.0, 0.8);
	assert nearVec(shader(0.0, 0.8, view, light, 1.0, 0.0, 1.0),
		oracle(0.0, 0.8, view, light, 1.0, 0.0, 1.0));
}

test "pbrDirect equals the oracle on a smooth metal off axis" {
	const view: Vec3 = vec3(0.8, 0.0, 0.6);
	const light: Vec3 = vec3(0.6, 0.0, 0.8);
	assert nearVec(shader(1.0, 0.15, view, light, 1.0, 0.0, 1.0),
		oracle(1.0, 0.15, view, light, 1.0, 0.0, 1.0));
}

test "pbrDirect equals the oracle at a grazing view and a grazing light" {
	const view: Vec3 = vec3(0.99, 0.0, 0.05);
	const light: Vec3 = vec3(-0.2, 0.3, 0.06);
	const expected: Vec3 = oracle(0.35, 0.5, view, light, 1.0, 0.0, 1.0);
	assert expected.x > 0.0;
	assert nearVec(shader(0.35, 0.5, view, light, 1.0, 0.0, 1.0), expected);
}

test "pbrDirect scales by the shadow and by the direct occlusion factor" {
	const view: Vec3 = vec3(0.3, 0.2, 0.9);
	const light: Vec3 = vec3(0.5, -0.1, 0.8);
	const lit: Vec3f = shader(0.2, 0.6, view, light, 1.0, 0.0, 0.3);
	const shadowed: Vec3f = shader(0.2, 0.6, view, light, 0.4, 0.0, 0.3);
	assert nearVec(shadowed, oracle(0.2, 0.6, view, light, 0.4, 0.0, 0.3));
	assert near(shadowed.x, lit.x * 0.4);
	const occluded: Vec3f = shader(0.2, 0.6, view, light, 0.4, 0.5, 0.3);
	assert nearVec(occluded, oracle(0.2, 0.6, view, light, 0.4, 0.5, 0.3));
	assert near(occluded.x, shadowed.x * (1.0 + 0.5 * (0.3 - 1.0)));
}

test "pbrDirect is black behind the surface and under dim radiance" {
	const behind: Vec3f = shader(0.0, 0.5, vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0),
		1.0, 0.0, 1.0);
	assert behind.x == 0.0 && behind.y == 0.0 && behind.z == 0.0;
	const dim: Vec3f = pbrDirect(toVec3f(ALBEDO), 0.0, 0.5, toVec3f(UP), toVec3f(UP),
		toVec3f(UP), vec3f(0.01, 0.0, 0.0), 1.0, 0.0, 1.0);
	assert dim.x == 0.0;
}

test "glTF channel order: roughness is G and metalness is B, and the swap is caught" {
	const texel: Vec3 = vec3(0.0, 0.3, 0.9);
	const properties = PbrProperties.gltfMap(1.0, 1.0, texel, 1.0, 1.0);
	assert properties.ok;
	if (!properties.ok) { unreachable; }
	assert properties.value.metalness == 0.9 && properties.value.roughness == 0.3;
	const view: Vec3 = vec3(0.4, 0.0, 0.9);
	const light: Vec3 = vec3(0.6, 0.0, 0.8);
	const expected: Vec3 = oracle(properties.value.metalness, properties.value.roughness,
		view, light, 1.0, 0.0, 1.0);
	assert nearVec(shader(texel.z, texel.y, view, light, 1.0, 0.0, 1.0), expected);
	assert !nearVec(shader(texel.y, texel.z, view, light, 1.0, 0.0, 1.0), expected);
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

function texture(depth: float32): Texture2d {
	return { width: 1, height: 1, texels: [depth, depth, depth, 1.0] };
}

const POSITION: Vec3 = vec3(0.5, 0.5, 0.5);
const CAMERA: Vec3 = vec3(0.5, 0.0, 2.0);
const SUN: Vec3 = vec3(0.6, 0.0, 0.8);
const SKY: Vec3 = vec3(0.25, 0.3, 0.4);
const BASE: Vec4f = vec4f(0.9, 0.5, 0.25, 1.0);

function bindingsAt(
	camera: Vec3, metalness: float32, roughness: float32, occlusion: float32, depth: float32,
): LitBindings {
	return {
		pbrMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			pbr: vec4f(metalness, roughness, occlusion, 0.0),
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
			cameraPosition: vec4f(camera.x, camera.y, camera.z, 1.0),
		},
		shadowParams: { shadowMatrix: identity(), shadow: vec4f(0.0, 1.0, 0.0, 0.0) },
		shadowMap: texture(depth),
		shadowSampler: { nearest: true },
		baseTexture: texture(1.0),
		baseSampler: { nearest: true },
		backTexture: texture(1.0),
		dissolveTexture: texture(1.0),
		dissolveSampler: { nearest: true },
		emissiveTexture: texture(1.0),
		normalTexture: texture(1.0),
	};
}

// Lighting.hx:78-99 for one channel on float64, written apart from shader3d.ms.
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

function litColor(
	key: LitKey, camera: Vec3, metalness: float32, roughness: float32, occlusion: float32,
	depth: float32,
): Vec3f {
	const out = litFs({
		worldPosition: toVec3f(POSITION),
		worldNormal: toVec3f(UP),
		baseColor: BASE,
		frontFacing: true,
	}, bindingsAt(camera, metalness, roughness, occlusion, depth), key);
	return out.color.rgb;
}

function expectedColor(
	metalness: float32, roughness: float32, occlusion: float32, shadow: float32,
): Vec3f {
	const albedo: Vec3f = srgbToLinear(BASE.rgb);
	const sky: Vec3f = srgbToLinear(vec3f(SKY.x, SKY.y, SKY.z));
	const toCamera: Vec3 = vec3(CAMERA.x - POSITION.x, CAMERA.y - POSITION.y, CAMERA.z - POSITION.z);
	const direct: Vec3 = oracle(metalness, roughness, toCamera, SUN, shadow, 0.0, occlusion,
		vec3(albedo.x, albedo.y, albedo.z), vec3(1.0, 1.0, 1.0));
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

test "litFs under a pbr key lights with the oracle's direct term and the ambient diffuse" {
	const key: LitKey = { pbr: true };
	assert nearColor(litColor(key, CAMERA, 0.0, 0.7, 1.0, 1.0), expectedColor(0.0, 0.7, 1.0, 1.0));
	assert nearColor(litColor(key, CAMERA, 0.8, 0.3, 0.5, 1.0), expectedColor(0.8, 0.3, 0.5, 1.0));
}

test "a pbr key's occlusion dims the ambient and leaves the sun alone" {
	const key: LitKey = { pbr: true };
	const open: Vec3f = litColor(key, CAMERA, 0.0, 0.7, 1.0, 1.0);
	const closed: Vec3f = litColor(key, CAMERA, 0.0, 0.7, 0.0, 1.0);
	assert nearColor(closed, expectedColor(0.0, 0.7, 0.0, 1.0));
	assert closed.x < open.x;
}

test "a shadowed pbr key takes the shadow map's factor on the sun only" {
	const key: LitKey = { pbr: true, shadowed: true };
	assert nearColor(litColor(key, CAMERA, 0.0, 0.7, 1.0, 1.0), expectedColor(0.0, 0.7, 1.0, 1.0));
	assert nearColor(litColor(key, CAMERA, 0.0, 0.7, 1.0, 0.0), expectedColor(0.0, 0.7, 1.0, 0.0));
}

test "a pbr key reads the camera position: the colour moves with the eye" {
	const key: LitKey = { pbr: true };
	const front: Vec3f = litColor(key, CAMERA, 0.0, 0.2, 1.0, 1.0);
	const side: Vec3f = litColor(key, vec3(-2.0, 0.0, 0.5), 0.0, 0.2, 1.0, 1.0);
	assert !nearColor(front, side);
}

test "ProgramKey.withPbr sets bit 16 and names itself, for the lit programs only" {
	const lit: ProgramKey = ProgramKey.of(Program.Lit);
	const pbr: ProgramKey = lit.withPbr();
	assert pbr.pbr && !lit.pbr;
	assert pbr.bits() == (lit.bits() | 65536);
	assert pbr.describe().includes("pbr");
	assert ProgramKey.of(Program.LitTextured).withPbr().pbr;
}

test "pbrBlock holds the values at PBR_* after the lit block and refuses roughness 0" {
	const key: ProgramKey = ProgramKey.of(Program.Lit).withPbr();
	const block = pbrBlock(key, { metalness: 0.25, roughness: 0.5, occlusion: 0.75 });
	assert block.ok;
	if (!block.ok) { unreachable; }
	assert block.value.length == PBR_MATERIAL_UNIFORM_LENGTH;
	assert PBR_METALNESS == MATERIAL_UNIFORM_LENGTH;
	assert block.value[PBR_METALNESS] == 0.25 && block.value[PBR_ROUGHNESS] == 0.5 &&
		block.value[PBR_OCCLUSION] == 0.75;
	const heaps = PbrProperties.heapsValues();
	assert heaps.ok;
	if (!heaps.ok) { unreachable; }
	const defaults = pbrBlock(key, heaps.value);
	assert defaults.ok;
	if (defaults.ok) {
		assert defaults.value[PBR_METALNESS] == 0.0 && defaults.value[PBR_ROUGHNESS] == 1.0 &&
			defaults.value[PBR_OCCLUSION] == 1.0;
	}
	const smooth = pbrBlock(key, { metalness: 0.0, roughness: 0.0, occlusion: 1.0 });
	assert !smooth.ok;
	if (!smooth.ok) { assert smooth.error == PbrResponseError.ZeroRoughness; }
	assert !pbrBlock(key, { metalness: 1.5, roughness: 0.5, occlusion: 1.0 }).ok;
	if (declares(key)) {
		assert uniformBlockLength(key, MATERIAL_UNIFORM_SLOT) == PBR_MATERIAL_UNIFORM_LENGTH;
	}
}
