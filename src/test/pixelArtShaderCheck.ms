// The pixel-art preset's stages run on the CPU: the toon ramp, the depth every scene stage writes
// into the normal target, and the post and blit passes over small textures.

import { linearToSrgb as channelToSrgb, srgbToLinear as channelToLinear } from "../math/math3d";
import { glslLinked } from "../shader/emit";
import { Mat4x4f, Texture2d, Vec4f, mat4x4f, vec2f, vec3f, vec4f } from "../shader/std";
import { BillboardBindings, LitBindings, LitKey, VertexBindings } from "../void3d/shader3d";
import {
	BlitBindings,
	PostBindings,
	PixelArtBillboardFragmentInput,
	blitFs,
	pixelArtBillboardFs,
	pixelArtLitFs,
	pixelArtLitVs,
	pixelArtParticleFs,
	postFs,
	toonPointLightAt,
} from "../void3d/pixelArt3d";

function within(a: float32, b: float32): boolean {
	return Math.abs(a - b) <= 1e-4;
}

function none(): Vec4f {
	return vec4f(0.0, 0.0, 0.0, 0.0);
}

function identity(): Mat4x4f {
	return mat4x4f(vec4f(1, 0, 0, 0), vec4f(0, 1, 0, 0), vec4f(0, 0, 1, 0), vec4f(0, 0, 0, 1));
}

function grid(width: int32, height: int32, fill: Vec4f): Texture2d {
	let texels: float32[] = [];
	for (let i = 0; i < width * height; i++) {
		texels.push(fill.x);
		texels.push(fill.y);
		texels.push(fill.z);
		texels.push(fill.w);
	}
	return { width, height, texels };
}

function put(texture: Texture2d, x: int32, y: int32, value: Vec4f): void {
	const first = (y * texture.width + x) * 4;
	texture.texels[first] = value.x;
	texture.texels[first + 1] = value.y;
	texture.texels[first + 2] = value.z;
	texture.texels[first + 3] = value.w;
}

// White ambient light, no directional or point light, the identity tone.
function plainLit(): LitBindings {
	const white = grid(1, 1, vec4f(1, 1, 1, 1));
	return {
		materialParams: { material: vec4f(4.0, 0.0, 0.0, 0.5) },
		lightParams: {
			ambient: vec4f(1, 1, 1, 0), dirLight: none(), dirColor: none(),
			pointLight: [none(), none(), none(), none()],
			pointColor: [none(), none(), none(), none()],
		},
		frameParams: { frame: vec4f(0, 1, 0, 0) },
		shadowParams: { shadowMatrix: identity(), shadow: none() },
		shadowMap: white, shadowSampler: { nearest: true },
		baseTexture: white, baseSampler: { nearest: true },
		backTexture: white, dissolveTexture: white, dissolveSampler: { nearest: true },
		emissiveTexture: white, normalTexture: white,
		metalRoughTexture: white, occlusionTexture: white,
	};
}

function noKey(): LitKey {
	return {
		cutout: false, shadowed: false, normalMrt: false, skinned: false, premultiplied: false,
		uvTransform: false, backTexture: false, dissolve: false, emissive: false, normalMap: false,
	};
}

// A grey 3x3 frame on a flat floor at depth 0.5, no feature on, fog at no strength.
function plainPost(): PostBindings {
	return {
		postParams: {
			edge: none(), fog: vec4f(0.5, 0.8, 0.0, 0.0), fogColor: none(), features: none(),
			depthUnpack: none(), colorAdjust: none(),
		},
		colorTexture: grid(3, 3, vec4f(0.5, 0.5, 0.5, 1.0)),
		normalTexture: grid(3, 3, vec4f(0.5, 1.0, 0.5, 0.5)),
		depthTexture: grid(3, 3, none()),
		paletteTexture: grid(4, 2, none()),
		pointSampler: { nearest: true },
		depthSampler: { nearest: true },
	};
}

test "the toon ramp steps a point light's energy into bands" {
	const at = vec4f(0, 0, 1, 1);
	const tint = vec4f(1, 1, 1, 4);
	const facing = toonPointLightAt(vec3f(0.0), vec3f(0, 0, 1), at, tint, 1.0, 4.0);
	assert within(facing.x, 0.5) && within(facing.z, 0.5);
	const away = toonPointLightAt(vec3f(0.0), vec3f(0, 0, -1), at, tint, 1.0, 4.0);
	assert away.x == 0.0;
	const unweighted = toonPointLightAt(vec3f(0.0), vec3f(0, 0, -1), at, tint, 0.0, 4.0);
	assert within(unweighted.y, 0.5);
}

test "pixel-art lit stages carry the clip depth into the normal target" {
	let bindings: VertexBindings = {
		vertexParams: {
			viewProj: mat4x4f(vec4f(1, 0, 0, 0), vec4f(0, 1, 0, 0),
				vec4f(0, 0, 0.5, 0), vec4f(0, 0, 0, 1)),
			cameraRight: vec4f(1, 0, 0, 0), cameraUp: vec4f(0, 1, 0, 0),
		},
		modelParams: { model: identity(), normalModel: identity() },
	};
	const point = pixelArtLitVs(
		{ position: vec3f(1, 2, 3), normal: vec3f(0, 0, 1), color: vec4f(1, 1, 1, 1) },
		bindings, noKey(),
	);
	assert point.depth01 == 1.5 && point.clip.z == 1.5 && point.worldNormal.z == 1;
	const shaded = pixelArtLitFs({
		worldPosition: vec3f(0.0), worldNormal: vec3f(0, 0, 2), baseColor: vec4f(0.5, 0.25, 1, 1),
		depth01: 0.25, frontFacing: true,
	}, plainLit(), noKey());
	assert within(shaded.color.x, 0.5) && within(shaded.color.y, 0.25) && shaded.color.w == 1;
	assert shaded.normal.x == 0.5 && shaded.normal.z == 1 && shaded.normal.w == 0.25;
}

test "pixel-art billboard lights by distance and writes cutout alpha 0" {
	const input: PixelArtBillboardFragmentInput = {
		uv: vec2f(0.5, 0.5), rootPosition: vec3f(0.0), instanceColor: vec4f(0.5, 0.25, 1, 0.75),
		depth01: 0.5,
	};
	let b: BillboardBindings = {
		billboardParams: { billboardColor: vec4f(1, 1, 1, 1), billboard: none() },
		lightParams: {
			ambient: vec4f(0, 0, 0, 1), dirLight: none(), dirColor: none(),
			pointLight: [vec4f(0, 0, 1, 1), none(), none(), none()],
			pointColor: [vec4f(1, 1, 1, 4), none(), none(), none()],
		},
		frameParams: { frame: vec4f(0, 1, 0, 0) },
		billboardTexture: grid(1, 1, vec4f(1, 1, 1, 1)),
		billboardSampler: { nearest: true },
	};
	const plain = pixelArtBillboardFs(input, b, { cutout: false, premultiplied: false });
	assert plain.color.x == 0.5 && plain.color.w == 0.75;
	assert plain.normal.y == 1 && plain.normal.w == 0.5;
	const cutout = pixelArtBillboardFs(input, b, { cutout: true, premultiplied: false });
	assert cutout.color.x == 0.5 && cutout.color.w == 0.0;
	const premultiplied = pixelArtBillboardFs(input, b, { cutout: false, premultiplied: true });
	assert within(premultiplied.color.x, 0.375) && premultiplied.color.w == 0.75;
	b.billboardParams.billboard = vec4f(4, 1, 0, 0);
	const lit = pixelArtBillboardFs(input, b, { cutout: false, premultiplied: false });
	assert within(lit.color.x, channelToSrgb(channelToLinear(0.5) + 0.5));
}

test "pixel-art particle writes cutout alpha 0 and a flat normal" {
	const shaded = pixelArtParticleFs({ particleColor: vec4f(0.5, 0.25, 1, 0.75), depth01: 0.125 },
		{ frameParams: { frame: vec4f(0, 1, 0, 0) } }, { cutout: true });
	assert shaded.color.x == 0.5 && shaded.color.w == 0.0;
	assert shaded.normal.x == 0.5 && shaded.normal.y == 1 && shaded.normal.w == 0.125;
}

test "post darkens a depth edge, fogs by the unpacked depth and reads the palette" {
	const centre = { position: vec4f(1.5, 1.5, 0.5, 1.0) };
	let b = plainPost();
	const plain = postFs(centre, b);
	assert plain.x == 0.5 && plain.w == 1.0;
	put(b.normalTexture, 1, 1, vec4f(0.5, 1.0, 0.5, 0.2));
	b.postParams.features = vec4f(1, 0, 0, 0);
	b.postParams.edge = vec4f(0.1, 0.5, 0.5, 1.0);
	const outlined = postFs(centre, b);
	assert within(outlined.x, 0.25) && within(outlined.z, 0.25);
	b = plainPost();
	b.postParams.features = vec4f(0, 0, 1, 0);
	b.depthTexture = grid(3, 3, vec4f(0.25, 0, 0, 0));
	b.postParams.depthUnpack = vec4f(2, 0, 0, 0);
	b.postParams.fog = vec4f(0, 1, 1, 0);
	b.postParams.fogColor = vec4f(1, 0, 0, 0);
	const fogged = postFs(centre, b);
	assert within(fogged.x, 0.75) && within(fogged.y, 0.25);
	b = plainPost();
	b.postParams.features = vec4f(0, 1, 0, 2);
	put(b.paletteTexture, 3, 1, vec4f(0, 1, 0, 1));
	const quantized = postFs(centre, b);
	assert quantized.x == 0 && quantized.y == 1 && quantized.w == 1;
}

test "blit reads the scene texel under the scaled fragment, clamped, alpha 1" {
	let scene = grid(4, 4, none());
	for (let y = 0; y < 4; y++) {
		for (let x = 0; x < 4; x++) {
			put(scene, x, y, vec4f((x as float32) / 4.0, (y as float32) / 4.0, 0.0, 0.5));
		}
	}
	let b: BlitBindings = {
		blitParams: { pixel: vec4f(2, 2, 0, 0) }, sceneTexture: scene,
		pointSampler: { nearest: true },
	};
	const texel = blitFs({ position: vec4f(5.5, 3.5, 0.5, 1.0) }, b);
	assert texel.x == 0.5 && texel.y == 0.25 && texel.w == 1.0;
	b.blitParams.pixel = vec4f(2, 2, 1, 0);
	assert blitFs({ position: vec4f(5.5, 3.5, 0.5, 1.0) }, b).x == 0.75;
	assert blitFs({ position: vec4f(100.5, 0.5, 0.5, 1.0) }, b).x == 0.75;
}

test "every pixel-art scene stage writes the normal target unconditionally" {
	const lit: string = glslLinked(pixelArtLitFs, pixelArtLitVs);
	assert lit.includes("layout(location=1) out vec4 normal;");
	assert !lit.includes("NORMAL_MRT") && lit.includes("in float depth01;");
}
