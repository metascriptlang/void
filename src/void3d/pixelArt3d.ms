// The pixel-art preset's programs as MetaScript shader functions. tools/genShadersPixelArt.ms
// writes their GLSL into pixelArt3dGen.glsl for scripts/regen-shaders.sh. Every scene stage also
// writes the normal target, its alpha the clip depth the post pass outlines and fogs by.

import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec2i,
	Vec3f,
	Vec4f,
	abs,
	binding,
	builtin,
	clamp,
	determinant,
	discard,
	dot,
	feature,
	floor,
	length,
	location,
	max,
	mix,
	normalize,
	sampleType,
	samplerType,
	smoothstep,
	textureDimensions,
	textureLoad,
	textureSample,
	upperLeft3x3,
	vec2f,
	vec2i,
	vec3f,
	vec3i,
	vec4f,
} from "../shader/std";
import {
	BillboardAttributes,
	BillboardBindings,
	BillboardKey,
	LitAttributes,
	LitBindings,
	LitKey,
	PARTICLE_CORNERS,
	ParticleAttributes,
	ParticleBindings,
	ParticleKey,
	ParticleVisualPixelArtVaryings,
	TexturedAttributes,
	UnlitBindings,
	VertexBindings,
	backUv,
	backUvMatrixOf,
	backUvOffsetOf,
	billboardPoint,
	dirShadowAt,
	dissolveEdgeOf,
	dissolveEdgeOver,
	dissolveOf,
	emissiveOf,
	emittedOver,
	faceOf,
	facingNormal,
	linearToSrgb,
	mappedNormal,
	materialColorOf,
	materialOf,
	movedUv,
	saturated,
	skinNormal,
	skinWorld,
	instanceWorld,
	srgbToLinear,
	straightTexel,
	toneMapped,
	unlitShade,
	uvMatrixOf,
	uvMotionOf,
} from "./shader3d";
import { OUTLINE_OFFSETS, PostInput } from "./post3d";

export struct PixelArtLitVaryings {
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(position) clip: Vec4f;
}

export struct PixelArtLitFragmentInput {
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(frontFacing) frontFacing: boolean;
}

export struct PixelArtLitTexturedVaryings {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(position) clip: Vec4f;
}

export struct PixelArtLitTexturedFragmentInput {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(frontFacing) frontFacing: boolean;
}

export struct PixelArtUnlitTexturedVaryings {
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(position) clip: Vec4f;
}

export struct PixelArtUnlitTexturedFragmentInput {
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	baseColor: Vec4f;
	depth01: float32;
	@builtin(frontFacing) frontFacing: boolean;
}

export struct PixelArtBillboardFragmentInput {
	uv: Vec2f;
	rootPosition: Vec3f;
	instanceColor: Vec4f;
	depth01: float32;
}

export struct PixelArtParticleVaryings {
	particleColor: Vec4f;
	depth01: float32;
	@builtin(position) clip: Vec4f;
}

export struct PixelArtParticleFragmentInput {
	particleColor: Vec4f;
	depth01: float32;
}

export struct PixelArtOutput {
	@location(0) color: Vec4f;
	@location(1) normal: Vec4f;
}

export struct PostParams {
	edge: Vec4f;
	fog: Vec4f;
	fogColor: Vec4f;
	features: Vec4f;
	depthUnpack: Vec4f;
	colorAdjust: Vec4f;
}

export struct PostBindings {
	@binding(0) postParams: PostParams;
	@binding(0) colorTexture: Texture2d;
	@binding(1) normalTexture: Texture2d;
	@binding(2) @sampleType(unfilterable_float) depthTexture: Texture2d;
	@binding(3) paletteTexture: Texture2d;
	@binding(0) pointSampler: Sampler;
	@binding(1) @samplerType(nonfiltering) depthSampler: Sampler;
}

export struct BlitParams {
	pixel: Vec4f;
}

export struct BlitBindings {
	@binding(0) blitParams: BlitParams;
	@binding(0) sceneTexture: Texture2d;
	@binding(0) pointSampler: Sampler;
}

// The toon ramp: the point light's energy stepped into `levels` bands. normalWeight 0 lights a
// billboard by distance alone.
export function toonPointLightAt(
	position: Vec3f,
	normal: Vec3f,
	at: Vec4f,
	tint: Vec4f,
	normalWeight: float32,
	levels: float32,
): Vec3f {
	const toLight = at.xyz - position;
	const distance = length(toLight);
	const falloff = clamp(1.0 - distance / tint.a, 0.0, 1.0);
	const facing = mix(1.0, max(dot(normal, toLight / max(distance, 0.0001)), 0.0), normalWeight);
	const energy = falloff * falloff * facing * at.w;
	const level = floor(energy * levels + 0.35) / levels;
	return srgbToLinear(tint.rgb) * level;
}

// The core's litShade with the point lights on the toon ramp, material.x bands.
export function toonShade(
	n: Vec3f,
	position: Vec3f,
	surfaceColor: Vec4f,
	b: LitBindings,
	key: LitKey,
): Vec4f {
	const params = materialOf(b, key);
	const dir = b.lightParams.dirLight;
	let lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
	if (key.shadowed) {
		lambert = lambert * dirShadowAt(position, b);
	}
	let light = srgbToLinear(b.lightParams.ambient.rgb) +
		srgbToLinear(b.lightParams.dirColor.rgb) * lambert;
	for (let i = 0; i < ((b.lightParams.ambient.a + 0.5) as int32); i++) {
		const at = b.lightParams.pointLight[i];
		light = light + toonPointLightAt(
			position, n, at, b.lightParams.pointColor[i], 1.0, params.x,
		);
	}
	const surface = srgbToLinear(saturated(surfaceColor.rgb, params.y));
	return vec4f(linearToSrgb(surface * light), surfaceColor.a);
}

export function pixelArtLitVs(
	input: LitAttributes,
	b: VertexBindings,
	key: LitKey,
): PixelArtLitVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		const world = matrix * vec4f(input.position, 1.0);
		const clip = b.vertexParams.viewProj * world;
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			baseColor: input.color,
			depth01: clip.z,
			clip: clip,
		};
	} else {
		const world = b.modelParams.model * vec4f(input.position, 1.0);
		const clip = b.vertexParams.viewProj * world;
		return {
			worldPosition: world.xyz,
			worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
			baseColor: input.color,
			// PENDING3D: pixel-art-depth-orthographic
			depth01: clip.z,
			clip: clip,
		};
	}
}

export function pixelArtLitFs(
	input: PixelArtLitFragmentInput,
	b: LitBindings,
	key: LitKey,
): PixelArtOutput {
	const params = materialOf(b, key);
	const n = facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
	const shaded = toonShade(n, input.worldPosition, input.baseColor, b, key);
	if (key.cutout) {
		if (shaded.a < params.w) {
			discard();
		}
	}
	return {
		color: vec4f(toneMapped(shaded.rgb, b.frameParams.frame), shaded.a),
		normal: vec4f(n * 0.5 + 0.5, input.depth01),
	};
}

export function pixelArtLitTexturedVs(
	input: TexturedAttributes,
	b: VertexBindings,
	key: LitKey,
): PixelArtLitTexturedVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		const world = matrix * vec4f(input.position, 1.0);
		const clip = b.vertexParams.viewProj * world;
		const handedness: float32 = determinant(upperLeft3x3(matrix)) < 0.0 ? -1.0 : 1.0;
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			worldTangent: vec4f(
				upperLeft3x3(matrix) * input.tangent.xyz, input.tangent.w * handedness,
			),
			surfaceUv: input.uv,
			baseColor: input.color,
			depth01: clip.z,
			clip: clip,
		};
	} else {
		if (key.instanced) {
			const matrix = instanceWorld(
				input.instanceRow0, input.instanceRow1, input.instanceRow2,
			);
			const world = matrix * vec4f(input.position, 1.0);
			const clip = b.vertexParams.viewProj * world;
			return {
				worldPosition: world.xyz,
				worldNormal: skinNormal(matrix, input.normal),
				worldTangent: vec4f(upperLeft3x3(matrix) * input.tangent.xyz, input.tangent.w),
				surfaceUv: input.uv,
				baseColor: input.color * input.instanceColor,
				depth01: clip.z,
				clip: clip,
			};
		} else {
			const world = b.modelParams.model * vec4f(input.position, 1.0);
			const clip = b.vertexParams.viewProj * world;
			return {
				worldPosition: world.xyz,
				worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
				worldTangent: vec4f(
					upperLeft3x3(b.modelParams.model) * input.tangent.xyz, input.tangent.w,
				),
				surfaceUv: input.uv,
				baseColor: input.color,
				depth01: clip.z,
				clip: clip,
			};
		}
	}
}

export function pixelArtLitTexturedFs(
	input: PixelArtLitTexturedFragmentInput,
	b: LitBindings,
	key: LitKey,
): PixelArtOutput {
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
	let shaded = toonShade(n, input.worldPosition, surfaceColor, b, key);
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
	return { color: color, normal: vec4f(n * 0.5 + 0.5, input.depth01) };
}

export function pixelArtUnlitTexturedVs(
	input: TexturedAttributes,
	b: VertexBindings,
	key: LitKey,
): PixelArtUnlitTexturedVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		const clip = b.vertexParams.viewProj * matrix * vec4f(input.position, 1.0);
		return {
			worldNormal: skinNormal(matrix, input.normal),
			surfaceUv: input.uv,
			baseColor: input.color,
			depth01: clip.z,
			clip: clip,
		};
	} else {
		if (key.instanced) {
			const matrix = instanceWorld(
				input.instanceRow0, input.instanceRow1, input.instanceRow2,
			);
			const clip = b.vertexParams.viewProj * matrix * vec4f(input.position, 1.0);
			return {
				worldNormal: skinNormal(matrix, input.normal),
				surfaceUv: input.uv,
				baseColor: input.color * input.instanceColor,
				depth01: clip.z,
				clip: clip,
			};
		} else {
			const clip =
				b.vertexParams.viewProj * b.modelParams.model * vec4f(input.position, 1.0);
			return {
				worldNormal: upperLeft3x3(b.modelParams.normalModel) * input.normal,
				surfaceUv: input.uv,
				baseColor: input.color,
				depth01: clip.z,
				clip: clip,
			};
		}
	}
}

export function pixelArtUnlitTexturedFs(
	input: PixelArtUnlitTexturedFragmentInput,
	b: UnlitBindings,
	key: LitKey,
): PixelArtOutput {
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
	const n = facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
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
	return { color: color, normal: vec4f(n * 0.5 + 0.5, input.depth01) };
}

export function pixelArtBillboardVs(
	input: BillboardAttributes,
	b: VertexBindings,
): ParticleVisualPixelArtVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const world = billboardPoint(input.position, input.size, input.anchor, corner,
		b.vertexParams.cameraRight.xyz, b.vertexParams.cameraUp.xyz);
	const clip = b.vertexParams.viewProj * vec4f(world, 1.0);
	return {
		uv: vec2f(corner.x > 0.0 ? input.tile.z : input.tile.x,
			corner.y > 0.0 ? input.tile.y : input.tile.w),
		rootPosition: input.position,
		instanceColor: input.color,
		depth01: clip.z,
		clip: clip,
	};
}

// Lit by the point lights at the root raised billboard.z, on billboard.x bands. A cutout pixel
// writes alpha 0, so the post pass outlines it as background.
export function pixelArtBillboardFs(
	input: PixelArtBillboardFragmentInput,
	b: BillboardBindings,
	key: BillboardKey,
): PixelArtOutput {
	let texel = textureSample(b.billboardTexture, b.billboardSampler, input.uv);
	if (key.premultiplied) {
		texel = straightTexel(texel);
	}
	const tint = b.billboardParams.billboardColor;
	const alpha = tint.a * texel.a * input.instanceColor.a;
	if (key.cutout) {
		if (alpha < 0.5) {
			discard();
		}
	}
	let rgb = tint.rgb * texel.rgb * input.instanceColor.rgb;
	const shape = b.billboardParams.billboard;
	if (shape.y != 0.0) {
		const lightPoint = input.rootPosition + vec3f(0.0, shape.z, 0.0);
		let points = vec3f(0.0);
		for (let i = 0; i < ((b.lightParams.ambient.a + 0.5) as int32); i++) {
			const at = b.lightParams.pointLight[i];
			const up = vec3f(0.0, 1.0, 0.0);
			points = points + toonPointLightAt(
				lightPoint, up, at, b.lightParams.pointColor[i], 0.0, shape.x,
			);
		}
		rgb = linearToSrgb(srgbToLinear(rgb) + points);
	}
	rgb = toneMapped(rgb, b.frameParams.frame);
	let color = vec4f(rgb, alpha);
	if (key.cutout) {
		color = vec4f(rgb, 0.0);
	}
	if (key.premultiplied) {
		color = vec4f(rgb * alpha, alpha);
	}
	return { color: color, normal: vec4f(0.5, 1.0, 0.5, input.depth01) };
}

export function pixelArtParticleVs(
	input: ParticleAttributes, b: VertexBindings,
): PixelArtParticleVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const right = b.vertexParams.cameraRight.xyz;
	const up = b.vertexParams.cameraUp.xyz;
	const world = input.root.xyz + right * (corner.x * input.root.w) +
		up * (corner.y * input.root.w);
	const clip = b.vertexParams.viewProj * vec4f(world, 1.0);
	return { particleColor: input.color, depth01: clip.z, clip: clip };
}

export function pixelArtParticleFs(
	input: PixelArtParticleFragmentInput,
	b: ParticleBindings,
	key: ParticleKey,
): PixelArtOutput {
	let color = input.particleColor;
	if (key.cutout) {
		if (color.a < 0.5) {
			discard();
		}
		color = vec4f(color.rgb, 0.0);
	}
	return {
		color: vec4f(toneMapped(color.rgb, b.frameParams.frame), color.a),
		normal: vec4f(0.5, 1.0, 0.5, input.depth01),
	};
}

function postNormalAt(b: PostBindings, p: Vec2i, size: Vec2i): Vec4f {
	return textureLoad(
		b.normalTexture, b.pointSampler, clamp(p, vec2i(0, 0), size - vec2i(1, 1)), 0,
	);
}

// features.z picks the depth: the scene's depth attachment, unpacked to the depth the scene
// shaders write, or the 8-bit copy they pack into the normal target's alpha.
function postDepthAt(b: PostBindings, normal: Vec4f, p: Vec2i, size: Vec2i): float32 {
	let depth = normal.w;
	if (b.postParams.features.z > 0.5) {
		const q = clamp(p, vec2i(0, 0), size - vec2i(1, 1));
		const stored = textureLoad(b.depthTexture, b.depthSampler, q, 0).x;
		depth = stored * b.postParams.depthUnpack.x + b.postParams.depthUnpack.y;
	}
	return depth;
}

// features.w levels per channel; the LUT is levels * levels wide, red + blue * levels across,
// green down (palette.ms).
function paletteColor(b: PostBindings, rgb: Vec3f): Vec3f {
	const levels = b.postParams.features.w as int32;
	const q = vec3i(clamp(rgb, vec3f(0.0), vec3f(1.0)) * ((levels - 1) as float32) + 0.5);
	return textureLoad(b.paletteTexture, b.pointSampler, vec2i(q.x + q.z * levels, q.y), 0).rgb;
}

// Outline from depth and normal edges, fog by depth, then palette quantization through a LUT:
// one pass, because the palette only needs this pixel's outlined colour (docs/VOID3D.md, M3).
export function postFs(input: PostInput, b: PostBindings): Vec4f {
	const size = textureDimensions(b.colorTexture, b.pointSampler, 0);
	const p = vec2i(input.position.xy);
	const color = textureLoad(b.colorTexture, b.pointSampler, p, 0);
	const center = postNormalAt(b, p, size);
	const centerDepth = postDepthAt(b, center, p, size);
	const edge = b.postParams.edge;
	let rgb = color.rgb;
	if (b.postParams.features.x > 0.5) {
		const n = center.xyz * 2.0 - 1.0;
		let depthEdge: float32 = 0.0;
		let normalEdge: float32 = 0.0;
		for (let i = 0; i < 4; i++) {
			const neighbor = postNormalAt(b, p + OUTLINE_OFFSETS[i], size);
			const depthDelta = postDepthAt(b, neighbor, p + OUTLINE_OFFSETS[i], size) - centerDepth;
			if (depthDelta > edge.x) {
				depthEdge = 1.0;
			}
			const nq = neighbor.xyz * 2.0 - 1.0;
			if (abs(depthDelta) < edge.x && dot(n, nq) < edge.y && n.y > nq.y + 0.1) {
				normalEdge = 1.0;
			}
		}
		rgb = mix(rgb, rgb * edge.z, depthEdge * color.a);
		rgb = mix(rgb, rgb * edge.w + vec3f(0.02), normalEdge * color.a * (1.0 - depthEdge));
	}
	const fog = b.postParams.fog;
	const haze = smoothstep(fog.x, fog.y, centerDepth) * fog.z;
	rgb = mix(rgb, b.postParams.fogColor.rgb, haze);
	rgb = saturated(rgb, b.postParams.colorAdjust.x);
	if (b.postParams.features.y > 0.5) {
		rgb = paletteColor(b, rgb);
	}
	return vec4f(rgb, 1.0);
}

// pixel = (scale, scale, offset x, offset y) in framebuffer pixels (blit.ms). Alpha is 1 so that
// blitting the scene colour directly (no post stage) never shows through the surface.
export function blitFs(input: PostInput, b: BlitBindings): Vec4f {
	const size = textureDimensions(b.sceneTexture, b.pointSampler, 0);
	const p = vec2i(floor((input.position.xy + b.blitParams.pixel.zw) / b.blitParams.pixel.x));
	const texel = textureLoad(b.sceneTexture, b.pointSampler,
		clamp(p, vec2i(0, 0), size - vec2i(1, 1)), 0);
	return vec4f(texel.rgb, 1.0);
}
