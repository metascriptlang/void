// The lit programs' PBR path run on the CPU: shader3d.ms pbrDirect held to pbrResponse.ms, the
// landed oracle of Heaps' direct BRDF, and litFs under a pbr key held to that oracle plus an
// independent ambient formula.

import { Vec3, vec3 } from "../math/math3d";
import { Texture2d, Vec3f, Vec4f, mat4x4f, vec2f, vec3f, vec4f } from "../shader/std";
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
	VertexBindings,
	linearToSrgb,
	litFs,
	litTexturedFs,
	litVs,
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
		shadowParams: {
			shadowMatrix: identity(), shadow: vec4f(0.0, 1.0, 0.0, 0.0),
			spotMatrix: identity(), spotShadow: none(),
		},
		shadowMap: texture(depth),
		shadowSampler: { nearest: true },
		spotShadowMap: texture(depth),
		spotShadowSampler: { nearest: true },
		baseTexture: texture(1.0),
		baseSampler: { nearest: true },
		backTexture: texture(1.0),
		dissolveTexture: texture(1.0),
		dissolveSampler: { nearest: true },
		emissiveTexture: texture(1.0),
		normalTexture: texture(1.0),
		metalRoughTexture: texture(1.0),
		occlusionTexture: texture(1.0),
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

// A pbr key that emits reads the emissive layout, and nothing else; the pbr-only block holds
// values no right reading can reach.
function emittingBindings(
	metalness: float32, roughness: float32, emitted: Vec4f, glow: Texture2d,
): LitBindings {
	let b: LitBindings = bindingsAt(CAMERA, 0.9, 0.1, 0.0, 1.0);
	b.pbrEmissiveMaterialParams = {
		material: vec4f(0.0, 0.0, 0.0, 0.5),
		pbr: vec4f(metalness, roughness, 1.0, 0.0),
		emissive: emitted,
	};
	b.emissiveTexture = glow;
	return b;
}

function emittingColor(b: LitBindings): Vec3f {
	return litTexturedFs({
		worldPosition: toVec3f(POSITION),
		worldNormal: toVec3f(UP),
		surfaceUv: vec2f(0.5, 0.5),
		baseColor: BASE,
		frontFacing: true,
	}, b, { pbr: true, emissive: true }).color.rgb;
}

test "an emitting pbr key adds colour times texel times strength after the lighting, in linear light" {
	const glow: Texture2d = { width: 1, height: 1, texels: [0.5, 0.25, 1.0, 1.0] };
	const emitted: Vec4f = vec4f(0.6, 0.3, 0.1, 2.0);
	const lit: Vec3f = expectedColor(0.0, 0.7, 1.0, 1.0);
	const added: Vec3f = linearToSrgb(srgbToLinear(lit) + srgbToLinear(emitted.rgb) *
		srgbToLinear(vec3f(0.5, 0.25, 1.0)) * 2.0);
	const color: Vec3f = emittingColor(emittingBindings(0.0, 0.7, emitted, glow));
	assert nearColor(color, added) && color.x > lit.x;
	assert nearColor(emittingColor(emittingBindings(0.0, 0.7, vec4f(0.0, 0.0, 0.0, 1.0), glow)), lit);
	assert !nearColor(color, linearToSrgb(srgbToLinear(lit) + emitted.rgb * 0.5 * 2.0));
}

test "an emitting pbr key still glows with no light on it" {
	const glow: Texture2d = { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] };
	let b: LitBindings = emittingBindings(0.0, 0.7, vec4f(0.5, 0.2, 0.1, 1.0), glow);
	b.lightParams.ambient = none();
	b.lightParams.dirLight = none();
	const dark: Vec3f = emittingColor(b);
	assert nearColor(dark, linearToSrgb(srgbToLinear(vec3f(0.5, 0.2, 0.1))));
}

function skinnedPosition(x: float32, y: float32, z: float32): Vec3f {
	let rows: Vec4f[192] = [vec4f(0.0)];
	rows[0] = vec4f(1.0, 0.0, 0.0, x);
	rows[1] = vec4f(0.0, 1.0, 0.0, y);
	rows[2] = vec4f(0.0, 0.0, 1.0, z);
	let model = identity();
	model.columns[3] = vec4f(1000.0, 2000.0, 3000.0, 1.0);
	const b: VertexBindings = {
		vertexParams: { viewProj: identity(), cameraRight: none(), cameraUp: none() },
		modelParams: { model: model, normalModel: model },
		modelTransformParams: { model: model },
		skinParams: { skinRows: rows },
	};
	return litVs({
		position: vec3f(0.0, 0.0, 0.0), normal: toVec3f(UP), color: BASE,
		skinJoints: vec4f(0.0), skinWeights: vec4f(1.0, 0.0, 0.0, 0.0),
	}, b, { pbr: true, skinned: true }).worldPosition;
}

function colorAt(position: Vec3f): Vec3f {
	return litFs({
		worldPosition: position, worldNormal: toVec3f(UP), baseColor: BASE, frontFacing: true,
	}, bindingsAt(CAMERA, 0.0, 0.7, 1.0, 1.0), { pbr: true }).color.rgb;
}

test "a skinned pbr vertex is lit from its skinned world position, not from the mesh's model" {
	const home: Vec3f = skinnedPosition(POSITION.x, POSITION.y, POSITION.z);
	assert nearVec(home, POSITION);
	assert nearColor(colorAt(home), expectedColor(0.0, 0.7, 1.0, 1.0));
	assert !nearColor(colorAt(skinnedPosition(-2.0, 0.0, 0.1)), expectedColor(0.0, 0.7, 1.0, 1.0));
}
