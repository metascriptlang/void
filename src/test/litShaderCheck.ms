// The lit family run on the CPU, held to the colour functions the engine already trusts
// (src/math/math3d.ms) and to the identities a lit draw must keep.

import { linearToSrgb as channelToSrgb, srgbToLinear as channelToLinear } from "../math/math3d";
import { Mat4x4f, Vec3f, Vec4f, mat4x4f, vec3f, vec4f } from "../shader/std";
import {
	LitBindings,
	LitKey,
	linearToSrgb,
	litFs,
	litVs,
	saturated,
	srgbToLinear,
	toneCurved,
} from "../void3d/shader3d";

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

// White ambient light, no directional or point light, no saturation, exposure 0, linear curve.
function plainBindings(): LitBindings {
	return {
		materialParams: { material: vec4f(0.0, 0.0, 0.0, 0.5) },
		lightParams: {
			ambient: vec4f(1.0, 1.0, 1.0, 0.0),
			dirLight: none(),
			dirColor: none(),
			pointLight: [none(), none(), none(), none()],
			pointColor: [none(), none(), none(), none()],
		},
		frameParams: { frame: vec4f(0.0, 1.0, 0.0, 0.0) },
		shadowParams: { shadowMatrix: identity(), shadow: none() },
		shadowMap: { width: 1, height: 1, texels: [1.0, 1.0, 1.0, 1.0] },
		shadowSampler: { nearest: true },
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
		},
		{
			vertexParams: { viewProj: identity(), cameraRight: none(), cameraUp: none() },
			modelParams: { model: identity(), normalModel: identity() },
		},
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
