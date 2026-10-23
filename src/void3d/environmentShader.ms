// The fullscreen passes that bake an image-based light (environment.ms): Heaps' PanoramaToCube
// and IrradShader (h3d/scene/pbr/Environment.hx), sampled as Bevy's generate.rs filters its
// cubes (light_probe/environment_filter.wesl): every sample reads the source cube at the mip
// whose texel covers the sample's solid angle, so a few dozen samples stand for Heaps' 4096.
// tools/genShaders.ms writes their GLSL; src/test/environmentShaderCheck.ms runs them on the CPU.

import {
	Sampler,
	Texture2d,
	TextureCube,
	Vec2f,
	Vec3f,
	Vec4f,
	abs,
	asin,
	atan2,
	binding,
	builtin,
	cos,
	cross,
	dot,
	log2,
	max,
	min,
	normalize,
	sin,
	sqrt,
	textureSampleLevel,
	vec2f,
	vec2i,
	vec2u,
	vec3f,
	vec4f,
} from "../shader/std";
import { srgbToLinear } from "./shader3d";

export struct EnvironmentInput {
	@builtin(position) position: Vec4f;
}

// envFaceX..Z: the rows of Heaps' faceMatrix (Environment.hx getCubeMatrix) for the face drawn.
// envBake: x the source mip (resample) or the perceptual roughness (radiance), y the sample count,
// z the source cube's width, w the drawn mip's width. envSource: Heaps' fake-HDR threshold and the
// scale above it, its hdrMax, and at w 1 when the source stores sRGB-encoded colour.
export struct EnvironmentParams {
	envFaceX: Vec4f;
	envFaceY: Vec4f;
	envFaceZ: Vec4f;
	envBake: Vec4f;
	envSource: Vec4f;
}

export struct PanoramaBindings {
	@binding(0) panorama: Texture2d;
	@binding(0) environmentSampler: Sampler;
	@binding(0) environmentParams: EnvironmentParams;
}

export struct CubeBakeBindings {
	@binding(0) sourceCube: TextureCube;
	@binding(0) environmentSampler: Sampler;
	@binding(0) environmentParams: EnvironmentParams;
}

const PI: float32 = 3.14159265358979;

// IrradShader.getNormal: the drawn texel's direction, d = uv * 2 - 1 through the face matrix.
export function faceDirection(
	position: Vec4f,
	size: float32,
	faceX: Vec4f,
	faceY: Vec4f,
	faceZ: Vec4f,
): Vec3f {
	const d = position.xy / size * 2.0 - 1.0;
	return normalize(faceX.xyz * d.x + faceY.xyz * d.y + faceZ.xyz);
}

function panoramaDirection(input: EnvironmentInput, b: PanoramaBindings): Vec3f {
	return faceDirection(input.position, b.environmentParams.envBake.w,
		b.environmentParams.envFaceX, b.environmentParams.envFaceY, b.environmentParams.envFaceZ);
}

function cubeDirection(input: EnvironmentInput, b: CubeBakeBindings): Vec3f {
	return faceDirection(input.position, b.environmentParams.envBake.w,
		b.environmentParams.envFaceX, b.environmentParams.envFaceY, b.environmentParams.envFaceZ);
}

// PanoramaToCube.fragment with this frame's Y up for Heaps' Z: the direction's longitude and
// latitude, the row at v = 0 the sky. Heaps' fake HDR scales a texel brighter than the threshold.
export function environmentPanoramaFs(input: EnvironmentInput, b: PanoramaBindings): Vec4f {
	const n = panoramaDirection(input, b);
	const uv = vec2f(atan2(n.z, n.x), asin(-n.y)) * vec2f(0.1591, 0.3183) + 0.5;
	let texel = textureSampleLevel(b.panorama, b.environmentSampler, uv, 0.0);
	if (max(max(texel.r, texel.g), texel.b) > b.environmentParams.envSource.x) {
		texel = texel * b.environmentParams.envSource.y;
	}
	let color = texel.rgb;
	if (b.environmentParams.envSource.w > 0.5) {
		color = srgbToLinear(color);
	}
	return vec4f(color, 1.0);
}

// One texel of the drawn mip from the source at mip envBake.x, read at the texel's direction:
// at the next finer mip the bilinear tap is the 2x2 average, at the same mip a copy.
export function environmentResampleFs(input: EnvironmentInput, b: CubeBakeBindings): Vec4f {
	const n = cubeDirection(input, b);
	const texel = textureSampleLevel(b.sourceCube, b.environmentSampler, n,
		b.environmentParams.envBake.x);
	return vec4f(texel.rgb, 1.0);
}

// Hammersley point i of count (Environment.hx IrradBase.hammersley): i / count, then i's bits
// mirrored about the binary point (the radical inverse), one bit per step.
export function hammersley(i: uint32, count: uint32): Vec2f {
	let bits = i;
	let weight: float32 = 0.5;
	let inverse: float32 = 0.0;
	while (bits > (0 as uint32)) {
		inverse = inverse + weight * ((bits % (2 as uint32)) as float32);
		bits = bits / (2 as uint32);
		weight = weight * 0.5;
	}
	return vec2f((i as float32) / (count as float32), inverse);
}

// IrradBase.importanceSampleGGX and IrradShader.cosineWeightedSampling share this frame.
function inFrame(n: Vec3f, local: Vec3f): Vec3f {
	let up = vec3f(1.0, 0.0, 0.0);
	if (abs(n.z) < 0.999) {
		up = vec3f(0.0, 0.0, 1.0);
	}
	const tanX = normalize(cross(up, n));
	const tanY = normalize(cross(n, tanX));
	return normalize(tanX * local.x + tanY * local.y + n * local.z);
}

export function importanceSampleGgx(roughness: float32, p: Vec2f, n: Vec3f): Vec3f {
	const a = roughness * roughness;
	const phi = 2.0 * PI * p.x;
	const cosT = min(sqrt((1.0 - p.y) / (1.0 + (a * a - 1.0) * p.y)), 1.0);
	const sinT = sqrt(1.0 - cosT * cosT);
	return inFrame(n, vec3f(sinT * cos(phi), sinT * sin(phi), cosT));
}

export function cosineWeightedSample(p: Vec2f, n: Vec3f): Vec3f {
	const sq = sqrt(1.0 - p.x);
	const alpha = 2.0 * PI * p.y;
	return inFrame(n, vec3f(sq * cos(alpha), sq * sin(alpha), sqrt(p.x)));
}

// environment_filter.wesl calculate_environment_map_lod: the mip whose texel's solid angle is
// the sample's, 1 / (count * pdf), never finer than mip 0.
export function sampleLod(pdf: float32, sourceWidth: float32, count: float32): float32 {
	const sample = 1.0 / (count * pdf);
	const texel = 4.0 * PI / (6.0 * sourceWidth * sourceWidth);
	return max(0.5 * log2(sample / texel), 0.0);
}

function clampedSource(b: CubeBakeBindings, l: Vec3f, lod: float32): Vec3f {
	const texel = textureSampleLevel(b.sourceCube, b.environmentSampler, l, lod).rgb;
	return min(texel, vec3f(b.environmentParams.envSource.z));
}

function sampleCount(b: CubeBakeBindings): uint32 {
	return vec2u(vec2i((b.environmentParams.envBake.y + 0.5) as int32, 0)).x;
}

// IrradShader.fragment with isSpecular: GGX samples around the normal, the view taken as the
// normal, weighted by N.L. The pdf of a reflected half vector with V = N is D(h) / 4.
export function environmentRadianceFs(input: EnvironmentInput, b: CubeBakeBindings): Vec4f {
	const n = cubeDirection(input, b);
	const roughness = b.environmentParams.envBake.x;
	const count = sampleCount(b);
	const a = roughness * roughness;
	const a2 = a * a;
	let color = vec3f(0.0);
	let total: float32 = 0.0;
	for (let i = 0 as uint32; i < count; i++) {
		const h = importanceSampleGgx(roughness, hammersley(i, count), n);
		const vh = dot(n, h);
		const l = normalize(h * (2.0 * vh) - n);
		const nl = dot(n, l);
		if (nl > 0.0) {
			const denominator = vh * vh * (a2 - 1.0) + 1.0;
			const pdf = a2 / (PI * denominator * denominator) / 4.0;
			const lod = sampleLod(pdf, b.environmentParams.envBake.z, b.environmentParams.envBake.y);
			color = color + clampedSource(b, l, lod) * nl;
			total = total + nl;
		}
	}
	return vec4f(color / max(total, 1e-10), 1.0);
}

// IrradShader.fragment without isSpecular: cosine-weighted samples averaged, each read at the
// mip its pdf, N.L / pi, covers.
export function environmentIrradianceFs(input: EnvironmentInput, b: CubeBakeBindings): Vec4f {
	const n = cubeDirection(input, b);
	const count = sampleCount(b);
	let color = vec3f(0.0);
	let total: float32 = 1e-10;
	for (let i = 0 as uint32; i < count; i++) {
		const l = cosineWeightedSample(hammersley(i, count), n);
		const nl = dot(n, l);
		if (nl > 0.0) {
			const lod = sampleLod(nl / PI, b.environmentParams.envBake.z,
				b.environmentParams.envBake.y);
			color = color + clampedSource(b, l, lod);
			total = total + 1.0;
		}
	}
	return vec4f(color / total, 1.0);
}
