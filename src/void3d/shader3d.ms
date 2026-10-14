// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl for scripts/regen-shaders.sh; the native gate runs them on the CPU.

import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	clamp,
	discard,
	dot,
	feature,
	length,
	location,
	max,
	min,
	mix,
	normalize,
	pow,
	sampleType,
	samplerType,
	textureDimensions,
	textureLoad,
	upperLeft3x3,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
} from "../shader/std";

export struct CopyInput {
	@builtin(position) position: Vec4f;
}

export struct CopyBindings {
	@binding(0) sourceTexture: Texture2d;
	@binding(0) pointSampler: Sampler;
}

// h3d.pass.Copy: the scene target onto the swapchain, one texel per pixel.
export function copyFs(input: CopyInput, b: CopyBindings): Vec4f {
	const size = textureDimensions(b.sourceTexture, b.pointSampler, 0);
	const p = clamp(vec2i(input.position.xy), vec2i(0, 0), size - vec2i(1, 1));
	return textureLoad(b.sourceTexture, b.pointSampler, p, 0);
}

export struct LitAttributes {
	position: Vec3f;
	normal: Vec3f;
	color: Vec4f;
}

export struct LitVaryings {
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	baseColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct LitFragmentInput {
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	baseColor: Vec4f;
	@builtin(frontFacing) frontFacing: boolean;
}

export struct VertexParams {
	viewProj: Mat4x4f;
	cameraRight: Vec4f;
	cameraUp: Vec4f;
}

export struct ModelParams {
	model: Mat4x4f;
	normalModel: Mat4x4f;
}

export struct MaterialParams {
	material: Vec4f;
}

export struct LightParams {
	ambient: Vec4f;
	dirLight: Vec4f;
	dirColor: Vec4f;
	pointLight: Vec4f[4];
	pointColor: Vec4f[4];
}

export struct FrameParams {
	frame: Vec4f;
}

export struct ShadowParams {
	shadowMatrix: Mat4x4f;
	shadow: Vec4f;
}

export struct LitVertexBindings {
	@binding(0) vertexParams: VertexParams;
	@binding(4) modelParams: ModelParams;
}

export struct LitBindings {
	@binding(3) materialParams: MaterialParams;
	@binding(1) lightParams: LightParams;
	@binding(6) frameParams: FrameParams;
	@binding(5) shadowParams: ShadowParams;
	@binding(4) @sampleType(unfilterable_float) shadowMap: Texture2d;
	@binding(2) @samplerType(nonfiltering) shadowSampler: Sampler;
}

export struct LitKey {
	@feature(CUTOUT) cutout: boolean;
	@feature(SHADOWED) shadowed: boolean;
	@feature(NORMAL_MRT) normalMrt: boolean;
}

export struct LitOutput {
	@location(0) color: Vec4f;
	@location(1) @feature(NORMAL_MRT) normal: Vec4f;
}

export function litVs(input: LitAttributes, b: LitVertexBindings): LitVaryings {
	const world = b.modelParams.model * vec4f(input.position, 1.0);
	return {
		worldPosition: world.xyz,
		worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
		baseColor: input.color,
		clip: b.vertexParams.viewProj * world,
	};
}

// h3d.shader.ColorSpaces' exact pair (ColorSpaces.hx:56-76); bevy_color's gamma_function carries
// the same constants. Colour inputs and stored targets stay gamma-encoded. The pow operands clamp
// at 0 only to keep fxc's X3571 out of consumer stdout: output-neutral, the selects route every
// input a matrix can make negative to the linear branch.
export function srgbToLinear(srgb: Vec3f): Vec3f {
	const low = srgb * 0.0773993808;
	const high = pow(max(srgb * 0.9478672986 + vec3f(0.0521327014), vec3f(0.0)), vec3f(2.4));
	return vec3f(
		srgb.x <= 0.04045 ? low.x : high.x,
		srgb.y <= 0.04045 ? low.y : high.y,
		srgb.z <= 0.04045 ? low.z : high.z,
	);
}

export function linearToSrgb(rgb: Vec3f): Vec3f {
	const low = rgb * 12.92;
	const high = vec3f(1.055) * pow(max(rgb, vec3f(0.0)), vec3f(0.41666)) - vec3f(0.055);
	return vec3f(
		rgb.x <= 0.0031308 ? low.x : high.x,
		rgb.y <= 0.0031308 ? low.y : high.y,
		rgb.z <= 0.0031308 ? low.z : high.z,
	);
}

// h3d.shader.pbr.ToneMapping's `mode` switch over an exposed linear colour: 0 linear, 1 Reinhard,
// 2 Filmic at Heaps' default a..e, 3 Khronos PBR Neutral.
export function toneCurved(exposed: Vec3f, mode: float32): Vec3f {
	if (mode == 1.0) {
		return exposed / (exposed + vec3f(1.0));
	}
	if (mode == 2.0) {
		const a = exposed * (2.51 * exposed + 0.03);
		const b = exposed * (2.43 * exposed + 0.59) + 0.14;
		return clamp(a / b, vec3f(0.0), vec3f(1.0));
	}
	if (mode == 3.0) {
		const startCompression: float32 = 0.8 - 0.04;
		const desaturation: float32 = 0.15;
		const x = min(exposed.x, min(exposed.y, exposed.z));
		const offset: float32 = x < 0.08 ? x - 6.25 * x * x : 0.04;
		let color = exposed - offset;
		const peak = max(color.x, max(color.y, color.z));
		if (peak >= startCompression) {
			const d = 1.0 - startCompression;
			const newPeak = 1.0 - d * d / (peak + d - startCompression);
			color = color * (newPeak / peak);
			const g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
			color = mix(color, vec3f(newPeak), g);
		}
		return color;
	}
	return clamp(exposed, vec3f(0.0), vec3f(1.0));
}

// h3d.shader.pbr.ToneMapping per fragment: the decoded colour times frame.y, through the curve
// frame.w names, encoded again. At exposure 0 (frame.y exactly 1) and the linear curve the colour
// is left alone. frame.z is 1 when the pass draws into an HDR target: the colour is decoded and
// left unclamped, and the preset's toneMapFs exposes and curves it after blending, as Heaps' pbr
// Renderer does.
export function toneMapped(rgb: Vec3f, b: LitBindings): Vec3f {
	const tone = b.frameParams.frame;
	if (tone.z == 1.0) {
		return srgbToLinear(rgb);
	}
	if (tone.y == 1.0 && tone.w == 0.0) {
		return rgb;
	}
	return linearToSrgb(toneCurved(srgbToLinear(rgb) * tone.y, tone.w));
}

export function pointLightAt(i: int32, position: Vec3f, normal: Vec3f, b: LitBindings): Vec3f {
	const at = b.lightParams.pointLight[i];
	const tint = b.lightParams.pointColor[i];
	const toLight = at.xyz - position;
	const distance = length(toLight);
	const falloff = clamp(1.0 - distance / tint.a, 0.0, 1.0);
	const facing = max(dot(normal, toLight / max(distance, 0.0001)), 0.0);
	return srgbToLinear(tint.rgb) * (falloff * falloff * facing * at.w);
}

// h3d.Matrix.colorSaturate in scalar form; campfireGreyCpuCapture holds it to colorSaturated.
export function saturated(rgb: Vec3f, amount: float32): Vec3f {
	if (amount == 0.0) {
		return rgb;
	}
	const luma = dot(rgb, vec3f(0.212671, 0.71516, 0.072169));
	const keep = amount + 1.0;
	return rgb * keep + vec3f(luma * (1.0 - keep));
}

// h3d.shader.FlipBackFaceNormal, on when the material says so (glTF doubleSided).
export function facingNormal(normal: Vec3f, doubleSided: float32, input: LitFragmentInput): Vec3f {
	return doubleSided > 0.5 && !input.frontFacing ? -normal : normal;
}

// h3d.shader.ShadowSampling.sampleShadow with SAMPLING_NONE, on the map dirShadowMap.ms draws.
// shadowMatrix takes a world position to the map's texel space and to the depth the backend
// stores, so the compare reads the attachment as written; shadow.x is the bias in that depth,
// shadow.y the opacity (1 a full shadow).
export function dirShadowAt(position: Vec3f, b: LitBindings): float32 {
	const p = (b.shadowParams.shadowMatrix * vec4f(position, 1.0)).xyz;
	if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0) {
		return 1.0;
	}
	const size = textureDimensions(b.shadowMap, b.shadowSampler, 0);
	const texel = clamp(vec2i(p.xy * vec2f(size)), vec2i(0, 0), size - vec2i(1, 1));
	const depth = textureLoad(b.shadowMap, b.shadowSampler, texel, 0).x;
	const lit: float32 = clamp(p.z, 0.0, 1.0) - b.shadowParams.shadow.x > depth ? 0.0 : 1.0;
	return mix(1.0, lit, b.shadowParams.shadow.y);
}

export function litShade(n: Vec3f, input: LitFragmentInput, b: LitBindings, key: LitKey): Vec4f {
	const dir = b.lightParams.dirLight;
	let lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
	if (key.shadowed) {
		lambert = lambert * dirShadowAt(input.worldPosition, b);
	}
	const ambient = srgbToLinear(b.lightParams.ambient.rgb);
	let light = ambient + srgbToLinear(b.lightParams.dirColor.rgb) * lambert;
	for (let i = 0; i < ((b.lightParams.ambient.a + 0.5) as int32); i++) {
		light = light + pointLightAt(i, input.worldPosition, n, b);
	}
	const surface = srgbToLinear(saturated(input.baseColor.rgb, b.materialParams.material.y));
	return vec4f(linearToSrgb(surface * light), input.baseColor.a);
}

// PENDING3D: material-saturation-only
export function litFs(input: LitFragmentInput, b: LitBindings, key: LitKey): LitOutput {
	const params = b.materialParams.material;
	const n = facingNormal(normalize(input.worldNormal), params.z, input);
	const shaded = litShade(n, input, b, key);
	if (key.cutout) {
		if (shaded.a < params.w) {
			discard();
		}
	}
	return {
		color: vec4f(toneMapped(shaded.rgb, b), shaded.a),
		normal: vec4f(n * 0.5 + 0.5, 1.0),
	};
}

export function shadowLitFs(input: LitFragmentInput, b: LitBindings, key: LitKey): void {
	if (key.cutout) {
		if (input.baseColor.a < b.materialParams.material.w) {
			discard();
		}
	}
}
