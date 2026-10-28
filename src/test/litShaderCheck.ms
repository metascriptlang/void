// The lit family run on the CPU, held to the colour functions the engine already trusts
// (src/math/math3d.ms) and to the identities a lit draw must keep.

import { linearToSrgb as channelToSrgb, srgbToLinear as channelToLinear } from "../math/math3d";
import {
	Mat4x4f,
	Texture2d,
	Vec2f,
	Vec3f,
	Vec4f,
	mat4x4f,
	vec2f,
	vec3f,
	vec4f,
} from "../shader/std";
import {
	LitBindings,
	LitKey,
	TexturedAttributes,
	UnlitBindings,
	VertexBindings,
	linearToSrgb,
	litFs,
	litTexturedFs,
	litTexturedVs,
	distanceFade,
	flipbookBlend,
	flipbookUvs,
	litVs,
	movedUv,
	saturated,
	srgbToLinear,
	straightTexel,
	toneCurved,
	unlitTexturedFs,
	unlitTexturedVs,
} from "../void3d/shader3d";
import { oneCascade, oneLayer } from "./shadowHelpers";
import { SceneLights, sceneLights } from "./lightHelpers";

function within(a: float32, b: float32): boolean {
	return Math.abs(a - b) <= 1e-4;
}

function near(a: Vec3f, b: Vec3f): boolean {
	return within(a.x, b.x) && within(a.y, b.y) && within(a.z, b.z);
}

function identity(): Mat4x4f {
	return mat4x4f(
		vec4f(1.0, 0.0, 0.0, 0.0),
		vec4f(0.0, 1.0, 0.0, 0.0),
		vec4f(0.0, 0.0, 1.0, 0.0),
		vec4f(0.0, 0.0, 0.0, 1.0),
	);
}

function none(): Vec4f {
	return vec4f(0.0, 0.0, 0.0, 0.0);
}

function white(): Texture2d {
	return { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] };
}

function nearUv(a: Vec2f, b: Vec2f): boolean {
	return within(a.x, b.x) && within(a.y, b.y);
}

// White ambient light, no directional or point light, no saturation, exposure 0, linear curve.
function plainBindings(): LitBindings {
	const lights: SceneLights = sceneLights(vec4f(1.0, 1.0, 1.0, 0.0), none(), none(), []);
	return {
		materialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			materialColor: vec4f(1.0, 1.0, 1.0, 1.0),
		},
		lightParams: lights.lightParams,
		lightRecords: lights.lightRecords,
		clusterRecords: lights.clusterRecords,
		clusterIndices: lights.clusterIndices,
		frameParams: { frame: vec4f(0.0, 1.0, 0.0, 0.0) },
		shadowParams: oneCascade(identity(), none(), identity(), none(), 1.0),
		shadowMap: oneLayer(white()),
		spotShadowMap: oneLayer(white()),
		cubeShadowMap: oneLayer(white()),
		cookieTexture: { width: 0, height: 0, texels: [] },
		baseTexture: white(),
		baseSampler: { nearest: true },
		backTexture: white(),
		dissolveTexture: white(),
		dissolveSampler: { nearest: true },
		emissiveTexture: white(),
		normalTexture: white(),
		metalRoughTexture: white(),
		occlusionTexture: white(),
		envDiffuse: { size: 0, texels: [] }, envSpecular: { size: 0, texels: [] },
	};
}

// The unlit counterpart: a white material colour, the same frame.
function plainUnlitBindings(): UnlitBindings {
	return {
		unlitMaterialParams: {
			material: vec4f(0.0, 0.0, 0.0, 0.5),
			materialColor: vec4f(1.0, 1.0, 1.0, 1.0),
		},
		frameParams: { frame: vec4f(0.0, 1.0, 0.0, 0.0) },
		baseTexture: white(),
		baseSampler: { nearest: true },
		backTexture: white(),
		dissolveTexture: white(),
		dissolveSampler: { nearest: true },
	};
}

function plainKey(): LitKey {
	return { cutout: true, shadowed: false, normalMrt: true };
}

test "the colour space pair is the engine's, channel by channel" {
	for (const c of [0.0, 0.02, 0.04045, 0.2, 0.5, 0.9, 1.0]) {
		const v: float32 = c as float32;
		assert within(srgbToLinear(vec3f(v)).x, channelToLinear(v));
		assert within(linearToSrgb(vec3f(v)).y, channelToSrgb(v));
	}
}

test "saturation 0 keeps the colour and -1 leaves its luma" {
	const rgb = vec3f(0.8, 0.4, 0.1);
	assert near(saturated(rgb, 0.0), rgb);
	const luma: float32 = 0.212671 * 0.8 + 0.71516 * 0.4 + 0.072169 * 0.1;
	assert near(saturated(rgb, -1.0), vec3f(luma));
}

test "the tone curves: linear clamps, Reinhard is x over x plus one" {
	assert near(toneCurved(vec3f(2.0, 0.5, -1.0), 0.0), vec3f(1.0, 0.5, 0.0));
	assert near(toneCurved(vec3f(1.0, 3.0, 0.0), 1.0), vec3f(0.5, 0.75, 0.0));
}

test "a vertex under identity matrices lands where it is, its normal and colour carried" {
	const out = litVs(
		{
			position: vec3f(0.25, -0.5, 0.75),
			normal: vec3f(0.0, 1.0, 0.0),
			color: vec4f(1.0, 0.5, 0.25, 1.0),
			instanceRow0: vec4f(1.0, 0.0, 0.0, 0.0), instanceRow1: vec4f(0.0, 1.0, 0.0, 0.0),
			instanceRow2: vec4f(0.0, 0.0, 1.0, 0.0), instanceColor: vec4f(1.0),
		},
		{
			vertexParams: { viewProj: identity(), cameraRight: none(), cameraUp: none(), cameraPosition: none() },
		},
		plainKey(),
	);
	assert near(out.worldPosition, vec3f(0.25, -0.5, 0.75));
	assert near(out.worldNormal, vec3f(0.0, 1.0, 0.0));
	assert within(out.clip.w, 1.0) && within(out.baseColor.y, 0.5);
}

test "under white ambient light alone a surface keeps its colour; the normal target is encoded" {
	const out = litFs(
		{
			worldPosition: vec3f(0.0, 0.0, 0.0),
			worldNormal: vec3f(0.0, 0.0, 2.0),
			baseColor: vec4f(0.8, 0.4, 0.1, 0.75),
			frontFacing: true,
		},
		plainBindings(),
		plainKey(),
	);
	assert near(out.color.rgb, vec3f(0.8, 0.4, 0.1)) && within(out.color.a, 0.75);
	assert near(out.normal.xyz, vec3f(0.5, 0.5, 1.0)) && within(out.normal.w, 1.0);
}

test "a white texel leaves the lit and the unlit surface as the vertex colour" {
	const colour = vec4f(0.8, 0.4, 0.1, 0.75);
	const lit = litTexturedFs(
		{
			worldTangent: none(),
			worldPosition: vec3f(0.0, 0.0, 0.0),
			worldNormal: vec3f(0.0, 0.0, 1.0),
			surfaceUv: vec2f(0.5, 0.5),
			baseColor: colour,
			frontFacing: true,
		},
		plainBindings(),
		plainKey(),
	);
	assert near(lit.color.rgb, colour.rgb) && within(lit.color.a, 0.75);
	const unlit = unlitTexturedFs(
		{
			worldNormal: vec3f(0.0, 0.0, 1.0),
			surfaceUv: vec2f(0.5, 0.5),
			baseColor: colour,
			frontFacing: true,
		},
		plainUnlitBindings(),
		plainKey(),
	);
	assert near(unlit.color.rgb, colour.rgb) && within(unlit.color.a, 0.75);
}

test "the material colour multiplies the lit surface, alpha included, textured or not" {
	let tinted: LitBindings = plainBindings();
	tinted.materialParams.materialColor = vec4f(0.5, 1.0, 0.25, 0.8);
	const colour = vec4f(0.8, 0.4, 0.1, 0.75);
	const plain = litFs(
		{
			worldPosition: vec3f(0.0, 0.0, 0.0),
			worldNormal: vec3f(0.0, 0.0, 1.0),
			baseColor: colour,
			frontFacing: true,
		},
		tinted,
		plainKey(),
	);
	assert near(plain.color.rgb, vec3f(0.4, 0.4, 0.025)) && within(plain.color.a, 0.6);
	const textured = litTexturedFs(
		{
			worldTangent: none(),
			worldPosition: vec3f(0.0, 0.0, 0.0),
			worldNormal: vec3f(0.0, 0.0, 1.0),
			surfaceUv: vec2f(0.5, 0.5),
			baseColor: colour,
			frontFacing: true,
		},
		tinted,
		plainKey(),
	);
	assert near(textured.color.rgb, plain.color.rgb) && within(textured.color.a, 0.6);
}

test "a moved uv is the matrix times the uv, then the offset and the motion over time" {
	const swap = vec4f(0.0, 1.0, 1.0, 0.0);
	const offset = vec4f(0.5, 0.0, 0.0, 0.0);
	assert nearUv(movedUv(vec2f(0.25, 0.75), swap, offset, 0.0), vec2f(1.25, 0.25));
	const scroll = vec4f(0.0, 0.0, 0.25, 0.0);
	const identityUv = vec4f(1.0, 0.0, 0.0, 1.0);
	assert nearUv(movedUv(vec2f(0.0, 0.0), identityUv, scroll, 2.0), vec2f(0.5, 0.0));
}

test "a flipbook reads the frame its speed reached, row by row, and mixes in the next one" {
	const grid = vec4f(2.0, 2.0, 4.0, 2.0);
	const uv = vec2f(0.5, 0.5);
	const looping = vec4f(0.0, 0.0, 1.0, 1.0);
	const second = flipbookUvs(uv, grid, looping, 0.75);
	assert nearUv(second.xy, vec2f(0.75, 0.25)) && nearUv(second.zw, vec2f(0.25, 0.75));
	assert within(flipbookBlend(grid, looping, 0.75), 0.5);
	const wrapped = flipbookUvs(uv, grid, looping, 2.25);
	assert nearUv(wrapped.xy, vec2f(0.25, 0.25)) && nearUv(wrapped.zw, vec2f(0.75, 0.25));
}

test "a flipbook that does not loop holds its last frame, and starts at its start frame and time" {
	const grid = vec4f(2.0, 2.0, 4.0, 2.0);
	const uv = vec2f(0.5, 0.5);
	const held = flipbookUvs(uv, grid, vec4f(0.0, 0.0, 0.0, 1.0), 2.25);
	assert nearUv(held.xy, vec2f(0.75, 0.75)) && nearUv(held.zw, vec2f(0.75, 0.75));
	const late = vec4f(1.0, 2.7, 1.0, 0.0);
	assert nearUv(flipbookUvs(uv, grid, late, 1.25).xy, vec2f(0.25, 0.75));
	assert flipbookBlend(grid, late, 1.25) == 0.0;
}

test "a distance fade rises over its near pair, falls over its far pair, and an empty pair is off" {
	const range = vec4f(2.0, 4.0, 10.0, 20.0);
	assert within(distanceFade(1.0, range), 0.0) && within(distanceFade(3.0, range), 0.5);
	assert within(distanceFade(5.0, range), 1.0) && within(distanceFade(15.0, range), 0.5);
	assert within(distanceFade(25.0, range), 0.0);
	assert distanceFade(0.0, vec4f(0.0)) == 1.0 && distanceFade(100.0, vec4f(0.0)) == 1.0;
	assert distanceFade(100.0, vec4f(2.0, 4.0, 0.0, 0.0)) == 1.0;
}

test "a straight texel divides the colour by its alpha, and a clear texel stays clear" {
	const t = straightTexel(vec4f(0.25, 0.5, 0.125, 0.5));
	assert near(t.rgb, vec3f(0.5, 1.0, 0.25)) && within(t.a, 0.5);
	assert near(straightTexel(vec4f(0.3, 0.2, 0.1, 0.0)).rgb, vec3f(0.0));
}

function skinBindings(): VertexBindings {
	let rows: Vec4f[192] = [vec4f(0.0)];
	for (let i = 0; i < 64; i++) {
		rows[i * 3] = vec4f(1.0, 0.0, 0.0, 0.0);
		rows[i * 3 + 1] = vec4f(0.0, 1.0, 0.0, 0.0);
		rows[i * 3 + 2] = vec4f(0.0, 0.0, 1.0, 0.0);
	}
	rows[0] = vec4f(0.0, -1.0, 0.0, 2.0);
	rows[1] = vec4f(1.0, 0.0, 0.0, 3.0);
	rows[2] = vec4f(0.0, 0.0, 1.0, 4.0);
	rows[3] = vec4f(2.0, 0.0, 0.0, -1.0);
	rows[4] = vec4f(0.0, 3.0, 0.0, 1.0);
	rows[5] = vec4f(0.0, 0.0, 4.0, -2.0);
	return {
		vertexParams: { viewProj: identity(), cameraRight: none(), cameraUp: none(), cameraPosition: none() },
		skinParams: { skinRows: rows },
	};
}

test "a vertex takes its world from the instance row and its colour times the row's colour" {
	const out = litTexturedVs({
		position: vec3f(1.0, 2.0, 3.0), normal: vec3f(1.0, 0.0, 0.0), uv: vec2f(0.0),
		color: vec4f(1.0, 0.5, 0.25, 1.0), tangent: vec4f(0.0, 1.0, 0.0, 1.0),
		instanceRow0: vec4f(-1.0, 0.0, 0.0, 10.0), instanceRow1: vec4f(0.0, 2.0, 0.0, 20.0),
		instanceRow2: vec4f(0.0, 0.0, 1.0, 30.0), instanceColor: vec4f(0.5, 1.0, 1.0, 0.5),
	}, {
		vertexParams: {
			viewProj: identity(), cameraRight: none(), cameraUp: none(), cameraPosition: none(),
		},
	}, { ...plainKey(), normalMap: true });
	assert near(out.worldPosition, vec3f(9.0, 24.0, 33.0)) && near(out.clip.xyz, out.worldPosition);
	assert within(out.worldNormal.y, 0.0) && within(out.worldNormal.z, 0.0);
	assert near(out.worldTangent.xyz, vec3f(0.0, 2.0, 0.0)) && within(out.worldTangent.w, -1.0);
	assert near(out.baseColor.rgb, vec3f(0.5, 0.5, 0.25)) && within(out.baseColor.a, 0.5);
}

test "generated skin vertices share weighted rows, cofactor normals and no instance row" {
	const b = skinBindings();
	const key: LitKey = { ...plainKey(), skinned: true, normalMap: true };
	const input: TexturedAttributes = {
		position: vec3f(2.0, -1.0, 0.5), normal: vec3f(1.0, 2.0, 3.0),
		color: vec4f(0.2, 0.4, 0.6, 0.8), uv: vec2f(0.25, 0.75),
		tangent: vec4f(1.0, 0.0, 0.0, -1.0),
		skinJoints: vec4f(0.0, 1.0, 0.0, 0.0), skinWeights: vec4f(0.25, 0.75, 0.0, 0.0),
	};
	const lit = litVs({
		position: input.position, normal: input.normal, color: input.color,
		skinJoints: input.skinJoints, skinWeights: input.skinWeights,
	}, b, key);
	const textured = litTexturedVs(input, b, key);
	for (const normalMrt of [false, true]) {
		const unlit = unlitTexturedVs(input, b, { ...key, normalMrt: normalMrt });
		assert near(unlit.clip.xyz, vec3f(3.0, -0.25, 1.125)) && within(unlit.clip.w, 1.0);
		assert near(unlit.worldNormal, vec3f(5.6875, 10.5625, 10.3125));
		assert nearUv(unlit.surfaceUv, input.uv) && near(unlit.baseColor.rgb, input.color.rgb);
	}
	assert near(lit.worldPosition, vec3f(3.0, -0.25, 1.125));
	assert near(textured.worldPosition, lit.worldPosition) && near(textured.clip.xyz, lit.clip.xyz);
	assert near(lit.worldNormal, vec3f(5.6875, 10.5625, 10.3125));
	assert near(textured.worldNormal, lit.worldNormal);
	assert near(textured.worldTangent.xyz, vec3f(1.5, 0.25, 0.0));
	assert within(textured.worldTangent.w, -1.0) && nearUv(textured.surfaceUv, input.uv);
	assert near(lit.baseColor.rgb, input.color.rgb) && within(lit.baseColor.a, input.color.a);
}

test "generated skin normals keep the determinant sign for a mirrored palette" {
	let b = skinBindings();
	b.skinParams.skinRows[0] = vec4f(-1.0, 0.0, 0.0, 0.0);
	b.skinParams.skinRows[1] = vec4f(0.0, 2.0, 0.0, 0.0);
	b.skinParams.skinRows[2] = vec4f(0.0, 0.0, 3.0, 0.0);
	const out = litVs({
		position: vec3f(2.0, -1.0, 0.5), normal: vec3f(1.0, 0.0, 0.0),
		color: vec4f(1.0), skinJoints: vec4f(0.0), skinWeights: vec4f(1.0, 0.0, 0.0, 0.0),
	}, b, { ...plainKey(), skinned: true });
	assert near(out.worldPosition, vec3f(-2.0, -2.0, 1.5));
	assert near(out.worldNormal, vec3f(-6.0, 0.0, 0.0));
	const textured = litTexturedVs({
		position: vec3f(2.0, -1.0, 0.5), normal: vec3f(1.0, 0.0, 0.0),
		uv: vec2f(0.0), color: vec4f(1.0), tangent: vec4f(0.0, 1.0, 0.0, 1.0),
		skinJoints: vec4f(0.0), skinWeights: vec4f(1.0, 0.0, 0.0, 0.0),
	}, b, { ...plainKey(), skinned: true, normalMap: true });
	assert near(textured.worldNormal, out.worldNormal);
	assert near(textured.worldTangent.xyz, vec3f(0.0, 2.0, 0.0));
	assert within(textured.worldTangent.w, -1.0);
}
