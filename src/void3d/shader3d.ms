// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl for scripts/regen-shaders.sh; the native gate runs them on the CPU.

import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	clamp,
	cross,
	discard,
	dot,
	feature,
	length,
	location,
	mat2x2f,
	max,
	min,
	mix,
	normalize,
	pow,
	sampleType,
	samplerType,
	textureDimensions,
	textureLoad,
	textureSample,
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

export struct TexturedAttributes {
	position: Vec3f;
	normal: Vec3f;
	uv: Vec2f;
	color: Vec4f;
	@feature(NORMAL_MAP) tangent: Vec4f;
}

export struct LitTexturedVaryings {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct LitTexturedFragmentInput {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	@builtin(frontFacing) frontFacing: boolean;
}

export struct UnlitTexturedVaryings {
	@feature(NORMAL_MRT) worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct UnlitTexturedFragmentInput {
	@feature(NORMAL_MRT) worldNormal: Vec3f;
	surfaceUv: Vec2f;
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

export struct ModelTransformParams {
	model: Mat4x4f;
}

export struct MaterialParams {
	material: Vec4f;
}

// gpu3d.ms MOVING_*: materialParams, then what a key with a UV transform, a back texture or a
// dissolve reads; the emissive blocks add the emissive vec4 (gpu3d.ms emissiveBase).
export struct MovingMaterialParams {
	material: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
	backUvMatrix: Vec4f;
	backUvOffset: Vec4f;
	dissolve: Vec4f;
	dissolveEdge: Vec4f;
}

export struct EmissiveMaterialParams {
	material: Vec4f;
	emissive: Vec4f;
}

export struct MovingEmissiveMaterialParams {
	material: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
	backUvMatrix: Vec4f;
	backUvOffset: Vec4f;
	dissolve: Vec4f;
	dissolveEdge: Vec4f;
	emissive: Vec4f;
}

export struct UnlitMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
}

export struct MovingUnlitMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
	backUvMatrix: Vec4f;
	backUvOffset: Vec4f;
	dissolve: Vec4f;
	dissolveEdge: Vec4f;
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

// The blocks at one binding are the layouts a program key chooses between.
export struct VertexBindings {
	@binding(0) vertexParams: VertexParams;
	@binding(4) modelParams: ModelParams;
	@binding(4) modelTransformParams: ModelTransformParams;
}

export struct LitBindings {
	@binding(3) materialParams: MaterialParams;
	@binding(3) movingMaterialParams: MovingMaterialParams;
	@binding(3) emissiveMaterialParams: EmissiveMaterialParams;
	@binding(3) movingEmissiveMaterialParams: MovingEmissiveMaterialParams;
	@binding(1) lightParams: LightParams;
	@binding(6) frameParams: FrameParams;
	@binding(5) shadowParams: ShadowParams;
	@binding(4) @sampleType(unfilterable_float) shadowMap: Texture2d;
	@binding(2) @samplerType(nonfiltering) shadowSampler: Sampler;
	@binding(0) baseTexture: Texture2d;
	@binding(0) baseSampler: Sampler;
	@binding(1) backTexture: Texture2d;
	@binding(2) dissolveTexture: Texture2d;
	@binding(1) dissolveSampler: Sampler;
	@binding(3) emissiveTexture: Texture2d;
	@binding(5) normalTexture: Texture2d;
}

export struct UnlitBindings {
	@binding(3) unlitMaterialParams: UnlitMaterialParams;
	@binding(3) movingUnlitMaterialParams: MovingUnlitMaterialParams;
	@binding(6) frameParams: FrameParams;
	@binding(0) baseTexture: Texture2d;
	@binding(0) baseSampler: Sampler;
	@binding(1) backTexture: Texture2d;
	@binding(2) dissolveTexture: Texture2d;
	@binding(1) dissolveSampler: Sampler;
}

export struct LitKey {
	@feature(CUTOUT) cutout: boolean;
	@feature(SHADOWED) shadowed: boolean;
	@feature(NORMAL_MRT) normalMrt: boolean;
	@feature(PREMULTIPLIED) premultiplied: boolean;
	@feature(UV_TRANSFORM) uvTransform: boolean;
	@feature(BACK_TEXTURE) backTexture: boolean;
	@feature(DISSOLVE) dissolve: boolean;
	@feature(EMISSIVE) emissive: boolean;
	@feature(NORMAL_MAP) normalMap: boolean;
}

export struct LitOutput {
	@location(0) color: Vec4f;
	@location(1) @feature(NORMAL_MRT) normal: Vec4f;
}

export function litVs(input: LitAttributes, b: VertexBindings): LitVaryings {
	const world = b.modelParams.model * vec4f(input.position, 1.0);
	return {
		worldPosition: world.xyz,
		worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
		baseColor: input.color,
		clip: b.vertexParams.viewProj * world,
	};
}

export function litTexturedVs(input: TexturedAttributes, b: VertexBindings): LitTexturedVaryings {
	const world = b.modelParams.model * vec4f(input.position, 1.0);
	return {
		worldPosition: world.xyz,
		worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
		worldTangent: vec4f(upperLeft3x3(b.modelParams.model) * input.tangent.xyz, input.tangent.w),
		surfaceUv: input.uv,
		baseColor: input.color,
		clip: b.vertexParams.viewProj * world,
	};
}

// An unlit draw needs the normal matrix only for the normal target.
function unlitModel(b: VertexBindings, key: LitKey): Mat4x4f {
	if (key.normalMrt) {
		return b.modelParams.model;
	} else {
		return b.modelTransformParams.model;
	}
}

export function unlitTexturedVs(
	input: TexturedAttributes,
	b: VertexBindings,
	key: LitKey,
): UnlitTexturedVaryings {
	return {
		clip: b.vertexParams.viewProj * unlitModel(b, key) * vec4f(input.position, 1.0),
		worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
		surfaceUv: input.uv,
		baseColor: input.color,
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
export function toneMapped(rgb: Vec3f, tone: Vec4f): Vec3f {
	if (tone.z == 1.0) {
		return srgbToLinear(rgb);
	}
	if (tone.y == 1.0 && tone.w == 0.0) {
		return rgb;
	}
	return linearToSrgb(toneCurved(srgbToLinear(rgb) * tone.y, tone.w));
}

export function pointLightAt(position: Vec3f, normal: Vec3f, at: Vec4f, tint: Vec4f): Vec3f {
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
export function facingNormal(normal: Vec3f, doubleSided: float32, frontFacing: boolean): Vec3f {
	return doubleSided > 0.5 && !frontFacing ? -normal : normal;
}

export function faceOf(doubleSided: float32, frontFacing: boolean): float32 {
	return doubleSided > 0.5 && !frontFacing ? -1.0 : 1.0;
}

// Unpremultiply before srgbToLinear, never after: three d4ea9b9 RenderOutputNode.js:115-137.
export function straightTexel(texel: Vec4f): Vec4f {
	return texel.a > 0.0 ? vec4f(texel.rgb / texel.a, texel.a) : vec4f(0.0);
}

// h3d.shader.UVDelta's transform as Bevy's uv_transform (an Affine2), then UVScroll's
// `uvSpeed * global.time`.
export function movedUv(uv: Vec2f, matrix: Vec4f, motion: Vec4f, time: float32): Vec2f {
	return mat2x2f(matrix.xy, matrix.zw) * uv + motion.xy + motion.zw * time;
}

// The back texture is read on back faces through its own transform.
export function backUv(uv: Vec2f, matrix: Vec4f, offset: Vec4f): Vec2f {
	return mat2x2f(matrix.xy, matrix.zw) * uv + offset.xy;
}

// Heaps' AlphaMap read as KillAlpha reads its threshold: a pixel whose noise is below dissolve.x
// is discarded; above it, a band dissolve.y wide takes the edge colour, mixed by its alpha, while
// the threshold is above 0.
export function dissolveEdgeOver(
	color: Vec4f,
	noise: float32,
	dissolve: Vec4f,
	edge: Vec4f,
): Vec4f {
	const onEdge = dissolve.x > 0.0 && noise < dissolve.x + dissolve.y;
	return onEdge ? vec4f(mix(color.rgb, edge.rgb, edge.a), color.a) : color;
}

// three d4ea9b9 meshphong.glsl.js:94 and emissivemap_fragment: the emissive colour times the
// decoded map, added to the lit colour in linear light.
export function emittedOver(color: Vec4f, texel: Vec3f, emissive: Vec4f): Vec4f {
	const emitted = srgbToLinear(emissive.rgb) * srgbToLinear(texel) * emissive.a;
	return vec4f(linearToSrgb(srgbToLinear(color.rgb) + emitted), color.a);
}

// three d4ea9b9 normal_vertex.glsl.js:9 and normal_fragment_begin/maps: glTF's tangent, w the
// bitangent's sign, and on a flipped back face the whole frame turns with the normal.
export function mappedNormal(normal: Vec3f, tangent: Vec4f, face: float32, texel: Vec3f): Vec3f {
	const t = normalize(tangent.xyz);
	const sign: float32 = tangent.w < 0.0 ? -1.0 : 1.0;
	const bitangent = normalize(cross(normal, t)) * sign;
	const mapped = texel * 2.0 - 1.0;
	return normalize(mapped.x * t + mapped.y * bitangent + mapped.z * normal) * face;
}

// What the material block holds, from the layout the key gives it.
function moving(b: LitBindings, key: LitKey): boolean {
	return key.uvTransform || key.backTexture || key.dissolve;
}

// The material block's layout follows the key: the moving layouts when a UV transform, a back
// texture or a dissolve reads them, the emissive ones when the key emits. Each reader below
// picks the member from the block the program declares.
export function materialOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.uvTransform || key.backTexture || key.dissolve) {
		if (key.emissive) {
			return b.movingEmissiveMaterialParams.material;
		} else {
			return b.movingMaterialParams.material;
		}
	} else {
		if (key.emissive) {
			return b.emissiveMaterialParams.material;
		} else {
			return b.materialParams.material;
		}
	}
}

export function emissiveOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.uvTransform || key.backTexture || key.dissolve) {
		return b.movingEmissiveMaterialParams.emissive;
	} else {
		return b.emissiveMaterialParams.emissive;
	}
}

export function uvMatrixOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.uvMatrix;
	} else {
		return b.movingMaterialParams.uvMatrix;
	}
}

export function uvMotionOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.uvMotion;
	} else {
		return b.movingMaterialParams.uvMotion;
	}
}

export function backUvMatrixOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.backUvMatrix;
	} else {
		return b.movingMaterialParams.backUvMatrix;
	}
}

export function backUvOffsetOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.backUvOffset;
	} else {
		return b.movingMaterialParams.backUvOffset;
	}
}

export function dissolveOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.dissolve;
	} else {
		return b.movingMaterialParams.dissolve;
	}
}

export function dissolveEdgeOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.movingEmissiveMaterialParams.dissolveEdge;
	} else {
		return b.movingMaterialParams.dissolveEdge;
	}
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

// The lit surface: its colour (the vertex colour, times the texel when textured) under the
// ambient, directional and point lights, saturated as the material says.
export function litShade(
	n: Vec3f,
	position: Vec3f,
	surfaceColor: Vec4f,
	b: LitBindings,
	key: LitKey,
): Vec4f {
	const dir = b.lightParams.dirLight;
	let lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
	if (key.shadowed) {
		lambert = lambert * dirShadowAt(position, b);
	}
	const ambient = srgbToLinear(b.lightParams.ambient.rgb);
	let light = ambient + srgbToLinear(b.lightParams.dirColor.rgb) * lambert;
	for (let i = 0; i < ((b.lightParams.ambient.a + 0.5) as int32); i++) {
		const at = b.lightParams.pointLight[i];
		light = light + pointLightAt(position, n, at, b.lightParams.pointColor[i]);
	}
	const surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf(b, key).y));
	return vec4f(linearToSrgb(surface * light), surfaceColor.a);
}

// PENDING3D: material-saturation-only
export function litFs(input: LitFragmentInput, b: LitBindings, key: LitKey): LitOutput {
	const params = materialOf(b, key);
	const n = facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
	const shaded = litShade(n, input.worldPosition, input.baseColor, b, key);
	if (key.cutout) {
		if (shaded.a < params.w) {
			discard();
		}
	}
	return {
		color: vec4f(toneMapped(shaded.rgb, b.frameParams.frame), shaded.a),
		normal: vec4f(n * 0.5 + 0.5, 1.0),
	};
}

export function shadowLitFs(input: LitFragmentInput, b: LitBindings, key: LitKey): void {
	if (key.cutout) {
		if (input.baseColor.a < materialOf(b, key).w) {
			discard();
		}
	}
}

// PENDING3D: material-saturation-only
export function litTexturedFs(
	input: LitTexturedFragmentInput,
	b: LitBindings,
	key: LitKey,
): LitOutput {
	const params = materialOf(b, key);
	let uv = input.surfaceUv;
	if (key.uvTransform) {
		const time = b.frameParams.frame.x;
		uv = movedUv(input.surfaceUv, uvMatrixOf(b, key), uvMotionOf(b, key), time);
	}
	let texel = textureSample(b.baseTexture, b.baseSampler, uv);
	if (key.backTexture) {
		const backAt = backUv(input.surfaceUv, backUvMatrixOf(b, key), backUvOffsetOf(b, key));
		const backTexel = textureSample(b.backTexture, b.baseSampler, backAt);
		texel = input.frontFacing ? texel : backTexel;
	}
	let noise: float32 = 0.0;
	if (key.dissolve) {
		noise = textureSample(b.dissolveTexture, b.dissolveSampler, input.surfaceUv).x;
		if (noise < dissolveOf(b, key).x) {
			discard();
		}
	}
	if (key.premultiplied) {
		texel = straightTexel(texel);
	}
	let n = facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
	if (key.normalMap) {
		const normalTexel = textureSample(b.normalTexture, b.baseSampler, uv).rgb;
		const face = faceOf(params.z, input.frontFacing);
		n = mappedNormal(normalize(input.worldNormal), input.worldTangent, face, normalTexel);
	}
	const surfaceColor = vec4f(input.baseColor.rgb * texel.rgb, input.baseColor.a * texel.a);
	let shaded = litShade(n, input.worldPosition, surfaceColor, b, key);
	if (key.emissive) {
		const glow = textureSample(b.emissiveTexture, b.baseSampler, uv).rgb;
		shaded = emittedOver(shaded, glow, emissiveOf(b, key));
	}
	if (key.dissolve) {
		shaded = dissolveEdgeOver(shaded, noise, dissolveOf(b, key), dissolveEdgeOf(b, key));
	}
	if (key.cutout) {
		if (shaded.a < params.w) {
			discard();
		}
	}
	let color = vec4f(toneMapped(shaded.rgb, b.frameParams.frame), shaded.a);
	if (key.premultiplied) {
		color = vec4f(color.rgb * color.a, color.a);
	}
	return { color: color, normal: vec4f(n * 0.5 + 0.5, 1.0) };
}

export function shadowLitTexturedFs(
	input: LitTexturedFragmentInput,
	b: LitBindings,
	key: LitKey,
): void {
	if (key.dissolve) {
		const noise = textureSample(b.dissolveTexture, b.dissolveSampler, input.surfaceUv).x;
		if (noise < dissolveOf(b, key).x) {
			discard();
		}
	}
	if (key.cutout) {
		const texel = textureSample(b.baseTexture, b.baseSampler, input.surfaceUv);
		if (input.baseColor.a * texel.a < materialOf(b, key).w) {
			discard();
		}
	}
}

export function materialOf(b: UnlitBindings, key: LitKey): Vec4f {
	if (key.uvTransform || key.backTexture || key.dissolve) {
		return b.movingUnlitMaterialParams.material;
	} else {
		return b.unlitMaterialParams.material;
	}
}

export function materialColorOf(b: UnlitBindings, key: LitKey): Vec4f {
	if (key.uvTransform || key.backTexture || key.dissolve) {
		return b.movingUnlitMaterialParams.materialColor;
	} else {
		return b.unlitMaterialParams.materialColor;
	}
}

// The unlit surface: the vertex colour times the material colour times the texel, in linear light.
export function unlitShade(texel: Vec4f, baseColor: Vec4f, materialColor: Vec4f): Vec4f {
	let surface = srgbToLinear(baseColor.rgb) * srgbToLinear(materialColor.rgb);
	surface = surface * srgbToLinear(texel.rgb);
	return vec4f(linearToSrgb(surface), baseColor.a * materialColor.a * texel.a);
}

// Read only for the normal target, the one place an unlit program has a normal.
function unlitNormal(input: UnlitTexturedFragmentInput, params: Vec4f): Vec3f {
	return facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
}

export function unlitTexturedFs(
	input: UnlitTexturedFragmentInput,
	b: UnlitBindings,
	key: LitKey,
): LitOutput {
	const params = materialOf(b, key);
	let uv = input.surfaceUv;
	if (key.uvTransform) {
		const matrix = b.movingUnlitMaterialParams.uvMatrix;
		const motion = b.movingUnlitMaterialParams.uvMotion;
		uv = movedUv(input.surfaceUv, matrix, motion, b.frameParams.frame.x);
	}
	let texel = textureSample(b.baseTexture, b.baseSampler, uv);
	if (key.backTexture) {
		const backMatrix = b.movingUnlitMaterialParams.backUvMatrix;
		const backOffset = b.movingUnlitMaterialParams.backUvOffset;
		const backAt = backUv(input.surfaceUv, backMatrix, backOffset);
		const backTexel = textureSample(b.backTexture, b.baseSampler, backAt);
		texel = input.frontFacing ? texel : backTexel;
	}
	let noise: float32 = 0.0;
	if (key.dissolve) {
		noise = textureSample(b.dissolveTexture, b.dissolveSampler, input.surfaceUv).x;
		if (noise < b.movingUnlitMaterialParams.dissolve.x) {
			discard();
		}
	}
	if (key.premultiplied) {
		texel = straightTexel(texel);
	}
	let shaded = unlitShade(texel, input.baseColor, materialColorOf(b, key));
	if (key.dissolve) {
		const edge = b.movingUnlitMaterialParams.dissolveEdge;
		shaded = dissolveEdgeOver(shaded, noise, b.movingUnlitMaterialParams.dissolve, edge);
	}
	if (key.cutout) {
		if (shaded.a < params.w) {
			discard();
		}
	}
	let color = vec4f(toneMapped(shaded.rgb, b.frameParams.frame), shaded.a);
	if (key.premultiplied) {
		color = vec4f(color.rgb * color.a, color.a);
	}
	return {
		color: color,
		normal: vec4f(unlitNormal(input, params) * 0.5 + 0.5, 1.0),
	};
}

export function shadowUnlitTexturedFs(
	input: UnlitTexturedFragmentInput,
	b: UnlitBindings,
	key: LitKey,
): void {
	if (key.dissolve) {
		const noise = textureSample(b.dissolveTexture, b.dissolveSampler, input.surfaceUv).x;
		if (noise < b.movingUnlitMaterialParams.dissolve.x) {
			discard();
		}
	}
	if (key.cutout) {
		const texel = textureSample(b.baseTexture, b.baseSampler, input.surfaceUv);
		const tint = materialColorOf(b, key);
		if (input.baseColor.a * tint.a * texel.a < materialOf(b, key).w) {
			discard();
		}
	}
}
