// The receiver's cascade lookup on the CPU, held to Bevy's fetch_directional_shadow: the cascade a
// view depth picks, the blend across the overlap, nothing past the last far bound; and its GLSL
// reading the depth array layer by layer, composed as a lit program composes it.

import { glsl } from "../shader/emit";
import {
	Mat4x4f, Texture2dArray, Vec3f, Vec4f, binding, builtin, mat4x4f, mix, textureLoad,
	vec2i, vec3f, vec4f,
} from "../shader/std";
import {
	CascadeParams, cascadeBlendOf, cascadeCountOf, cascadeDepthOf, cascadeIndexOf, cascadeLitOf,
	cascadeTexelOf,
} from "../void3d/cascadeShadow";

const SIZE: int32 = 4;

struct ProbeInput {
	@builtin(position) position: Vec4f;
}

struct ProbeBindings {
	@binding(5) cascadeParams: CascadeParams;
	@binding(4) cascadeMap: Texture2dArray;
}

function layerLit(position: Vec3f, cascade: int32, b: ProbeBindings): float32 {
	const texel = cascadeTexelOf(position, b.cascadeParams.cascadeMatrices[cascade],
		b.cascadeParams.cascadeView);
	if (texel.w < 0.5) {
		return 1.0;
	}
	const stored = textureLoad(b.cascadeMap, vec2i(texel.xy), cascade, 0).x;
	return cascadeLitOf(texel, stored, b.cascadeParams.cascadeInfo);
}

function cascadedShadowAt(position: Vec3f, eye: Vec3f, b: ProbeBindings): float32 {
	const far = b.cascadeParams.cascadeFar;
	const info = b.cascadeParams.cascadeInfo;
	const depth = cascadeDepthOf(position, eye, b.cascadeParams.cascadeView);
	const cascade = cascadeIndexOf(depth, far, info);
	if (cascade >= cascadeCountOf(info)) {
		return 1.0;
	}
	const shadow = layerLit(position, cascade, b);
	const blend = cascadeBlendOf(depth, cascade, far, info);
	if (blend <= 0.0) {
		return shadow;
	}
	return mix(shadow, layerLit(position, cascade + 1, b), blend);
}

function probeCascadeFs(input: ProbeInput, b: ProbeBindings): float32 {
	return cascadedShadowAt(input.position.xyz, vec3f(0.0, 0.0, 0.0), b);
}

// World x and y in -1..1 to the map's 0..1, every point at depth 0.5.
function onTheMap(): Mat4x4f {
	return mat4x4f(vec4f(0.5, 0.0, 0.0, 0.0), vec4f(0.0, 0.5, 0.0, 0.0), vec4f(0.0, 0.0, 0.0, 0.0),
		vec4f(0.5, 0.5, 0.5, 1.0));
}

function params(count: float32, overlap: float32): CascadeParams {
	return {
		cascadeMatrices: [onTheMap(), onTheMap(), onTheMap(), onTheMap()],
		cascadeFar: vec4f(10.0, 20.0, 60.0, 150.0),
		cascadeInfo: vec4f(count, overlap, 0.001, 1.0),
		cascadeView: vec4f(0.0, 0.0, 1.0, SIZE as float32),
	};
}

// Layer i holds `depths[i]` at every texel.
function bound(p: CascadeParams, depths: float32[]): ProbeBindings {
	let texels: float32[] = [];
	for (const depth of depths) {
		for (let i = 0; i < SIZE * SIZE; i++) {
			texels.push(depth);
			texels.push(0.0);
			texels.push(0.0);
			texels.push(1.0);
		}
	}
	return {
		cascadeParams: p,
		cascadeMap: { width: SIZE, height: SIZE, layers: depths.length as int32, texels },
	};
}

function shadowAt(depth: float32, b: ProbeBindings): float32 {
	return cascadedShadowAt(vec3f(0.0, 0.0, depth), vec3f(0.0, 0.0, 0.0), b);
}

test "a view depth picks the first cascade whose far bound lies beyond it, else the count" {
	const four: CascadeParams = params(4.0, 0.2);
	const far = four.cascadeFar;
	assert cascadeIndexOf(5.0, far, four.cascadeInfo) == 0;
	assert cascadeIndexOf(10.0, far, four.cascadeInfo) == 1;
	assert cascadeIndexOf(30.0, far, four.cascadeInfo) == 2;
	assert cascadeIndexOf(149.0, far, four.cascadeInfo) == 3;
	assert cascadeIndexOf(200.0, far, four.cascadeInfo) == 4;
	assert cascadeIndexOf(100.0, far, params(2.0, 0.2).cascadeInfo) == 2;
}

test "the next cascade blends in across the overlap before a far bound, never past the last" {
	const two: CascadeParams = params(2.0, 0.2);
	const far = two.cascadeFar;
	const info = two.cascadeInfo;
	assert cascadeBlendOf(7.9, 0, far, info) == 0.0 && cascadeBlendOf(8.0, 0, far, info) == 0.0;
	assert Math.abs(cascadeBlendOf(9.0, 0, far, info) - 0.5) < 1e-5;
	assert cascadeBlendOf(19.9, 1, far, info) == 0.0;
}

test "the near cascade shadows, the overlap mixes in the next, and past the last is lit" {
	const b: ProbeBindings = bound(params(2.0, 0.2), [0.0, 1.0]);
	assert shadowAt(5.0, b) == 0.0;
	assert Math.abs(shadowAt(9.0, b) - 0.5) < 1e-5;
	assert shadowAt(15.0, b) == 1.0 && shadowAt(25.0, b) == 1.0;
	const flipped: ProbeBindings = bound(params(2.0, 0.2), [1.0, 0.0]);
	assert shadowAt(5.0, flipped) == 1.0 && shadowAt(15.0, flipped) == 0.0;
}

test "one cascade with no overlap answers as the single sun map does" {
	const b: ProbeBindings = bound(params(1.0, 0.0), [0.0]);
	assert shadowAt(9.99, b) == 0.0 && shadowAt(10.0, b) == 1.0;
}

test "the lookup's GLSL fetches a texel of the cascade's layer of the depth array" {
	const source: string = glsl(probeCascadeFs);
	assert source.includes("uniform texture2DArray cascadeMap;");
	assert source.includes("texelFetch(cascadeMap, ivec3(");
	assert source.includes("mat4 cascadeMatrices[4];");
}
