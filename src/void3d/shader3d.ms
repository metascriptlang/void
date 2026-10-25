// void3d's programs written as MetaScript shader functions. tools/genShaders.ms writes their GLSL
// into shader3dGen.glsl for scripts/regen-shaders.sh; the native gate runs them on the CPU.

import {
	Mat4x4f,
	Sampler,
	Texture2d,
	Texture2dArray,
	Texture2dU32,
	TextureCube,
	Vec2f,
	Vec3f,
	Vec4f,
	Vec4i,
	abs,
	atan2,
	binding,
	builtin,
	clamp,
	cos,
	cross,
	determinant,
	discard,
	dot,
	exp2,
	feature,
	length,
	location,
	mat2x2f,
	mat4x4f,
	max,
	min,
	mix,
	normalize,
	pow,
	reflect,
	sampleType,
	samplerType,
	sin,
	textureDimensions,
	textureLoad,
	textureSample,
	textureSampleLevel,
	transpose,
	upperLeft3x3,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
	vec4i,
} from "../shader/std";
import {
	CUBE_PCF_OFFSETS,
	CUBE_PCF_SAMPLES,
	PCF_SAMPLES,
	mapCoord,
	mapLit,
	pcfTexelOf,
	poissonOffset,
	poissonRotation,
} from "./shadowLookup";
import {
	cascadeBlendOf,
	cascadeCountOf,
	cascadeDepthOf,
	cascadeIndexOf,
	cascadeLitOf,
	cascadeTexelOf,
} from "./cascadeShadow";
import {
	dataTexelOf, fragmentClusterOf, indexOfWord, indexTexelOf, recordTexelOf,
} from "./clusterLookup";

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

export const PARTICLE_CORNERS: Vec2f[6] = [
	vec2f(-0.5, -0.5), vec2f(0.5, -0.5), vec2f(0.5, 0.5),
	vec2f(-0.5, -0.5), vec2f(0.5, 0.5), vec2f(-0.5, 0.5),
];

export struct ParticleVisualAttributes {
	root: Vec4f;
	shape: Vec4f;
	tile: Vec4f;
	color: Vec4f;
	velocity: Vec3f;
	look: Vec4f;
	scale: Vec4f;
	pull: Vec3f;
	emitterRight: Vec3f;
	emitterUp: Vec3f;
	@builtin(vertexIndex) index: uint32;
}

export struct ParticleVisualVaryings {
	worldPosition: Vec3f;
	towardCamera: Vec3f;
	uv: Vec2f;
	instanceColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct ParticleVisualPixelArtVaryings {
	uv: Vec2f;
	rootPosition: Vec3f;
	instanceColor: Vec4f;
	depth01: float32;
	@builtin(position) clip: Vec4f;
}

export struct LitAttributes {
	position: Vec3f;
	normal: Vec3f;
	color: Vec4f;
	@feature(SKINNED) skinJoints: Vec4f;
	@feature(SKINNED) skinWeights: Vec4f;
	instanceRow0: Vec4f;
	instanceRow1: Vec4f;
	instanceRow2: Vec4f;
	instanceColor: Vec4f;
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
	@builtin(position) fragCoord: Vec4f;
}

export struct TexturedAttributes {
	position: Vec3f;
	normal: Vec3f;
	uv: Vec2f;
	color: Vec4f;
	@feature(NORMAL_MAP) tangent: Vec4f;
	@feature(OCCLUSION_UV_B) uvB: Vec2f;
	@feature(SKINNED) skinJoints: Vec4f;
	@feature(SKINNED) skinWeights: Vec4f;
	instanceRow0: Vec4f;
	instanceRow1: Vec4f;
	instanceRow2: Vec4f;
	instanceColor: Vec4f;
}

export struct LitTexturedVaryings {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	@feature(OCCLUSION_UV_B) surfaceUvB: Vec2f;
	baseColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct LitTexturedFragmentInput {
	@feature(NORMAL_MAP) worldTangent: Vec4f;
	worldPosition: Vec3f;
	worldNormal: Vec3f;
	surfaceUv: Vec2f;
	@feature(OCCLUSION_UV_B) surfaceUvB: Vec2f;
	baseColor: Vec4f;
	@builtin(frontFacing) frontFacing: boolean;
	@builtin(position) fragCoord: Vec4f;
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
	cameraPosition: Vec4f;
}

export struct MaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
}

// gpu3d.ms MOVING_*: materialParams, then what a key with a UV transform, a back texture or a
// dissolve reads; the emissive blocks add the emissive vec4 (gpu3d.ms emissiveBase).
export struct MovingMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
	backUvMatrix: Vec4f;
	backUvOffset: Vec4f;
	dissolve: Vec4f;
	dissolveEdge: Vec4f;
}

// gpu3d.ms PBR_*: materialParams, then metalness, roughness and occlusion in x, y and z, then the
// UV transform every pbr key reads.
export struct PbrMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
	pbr: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
}

// gpu3d.ms PBR_* then EMISSIVE_*: a pbr key that emits holds the emissive vec4 after the pbr one.
export struct PbrEmissiveMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
	pbr: Vec4f;
	uvMatrix: Vec4f;
	uvMotion: Vec4f;
	emissive: Vec4f;
}

export struct EmissiveMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
	emissive: Vec4f;
}

export struct MovingEmissiveMaterialParams {
	material: Vec4f;
	materialColor: Vec4f;
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
	clusterGrid: Vec4f;
	clusterFactors: Vec4f;
	clusterView: Vec4f;
	clusterScreen: Vec4f;
}

export struct FrameParams {
	frame: Vec4f;
	cameraPosition: Vec4f;
	envParams: Vec4f;
}

export struct ShadowParams {
	cascadeMatrices: Mat4x4f[4];
	cascadeFar: Vec4f;
	cascadeInfo: Vec4f;
	cascadeView: Vec4f;
	cascadeFilter: Vec4f;
	spotMatrix: Mat4x4f;
	spotShadow: Vec4f;
	cubeMatrices: Mat4x4f[6];
	cubeShadow: Vec4f;
	cubeLight: Vec4f;
}

// The blocks at one binding are the layouts a program key chooses between.
export struct SkinParams {
	skinRows: Vec4f[192];
}

export struct VertexBindings {
	@binding(0) vertexParams: VertexParams;
	@binding(7) skinParams: SkinParams;
}

export struct LitBindings {
	@binding(3) materialParams: MaterialParams;
	@binding(3) movingMaterialParams: MovingMaterialParams;
	@binding(3) emissiveMaterialParams: EmissiveMaterialParams;
	@binding(3) movingEmissiveMaterialParams: MovingEmissiveMaterialParams;
	@binding(3) pbrMaterialParams: PbrMaterialParams;
	@binding(3) pbrEmissiveMaterialParams: PbrEmissiveMaterialParams;
	@binding(1) lightParams: LightParams;
	@binding(6) frameParams: FrameParams;
	@binding(5) shadowParams: ShadowParams;
	@binding(4) @sampleType(unfilterable_float) shadowMap: Texture2dArray;
	@binding(2) @samplerType(nonfiltering) shadowSampler: Sampler;
	@binding(6) @sampleType(unfilterable_float) spotShadowMap: Texture2dArray;
	@binding(3) @samplerType(nonfiltering) spotShadowSampler: Sampler;
	@binding(12) @sampleType(unfilterable_float) cubeShadowMap: Texture2dArray;
	@binding(0) baseTexture: Texture2d;
	@binding(0) baseSampler: Sampler;
	@binding(1) backTexture: Texture2d;
	@binding(2) dissolveTexture: Texture2d;
	@binding(1) dissolveSampler: Sampler;
	@binding(3) emissiveTexture: Texture2d;
	@binding(5) normalTexture: Texture2d;
	@binding(1) metalRoughTexture: Texture2d;
	@binding(2) occlusionTexture: Texture2d;
	@binding(7) envDiffuse: TextureCube;
	@binding(8) envSpecular: TextureCube;
	@binding(4) envSampler: Sampler;
	@binding(9) @sampleType(unfilterable_float) lightRecords: Texture2d;
	@binding(10) clusterRecords: Texture2dU32;
	@binding(11) clusterIndices: Texture2dU32;
	@binding(5) @samplerType(nonfiltering) clusterSampler: Sampler;
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
	@feature(SKINNED) skinned: boolean;
	@feature(PREMULTIPLIED) premultiplied: boolean;
	@feature(UV_TRANSFORM) uvTransform: boolean;
	@feature(BACK_TEXTURE) backTexture: boolean;
	@feature(DISSOLVE) dissolve: boolean;
	@feature(EMISSIVE) emissive: boolean;
	@feature(NORMAL_MAP) normalMap: boolean;
	@feature(PBR) pbr: boolean;
	@feature(PBR_MAPS) pbrMaps: boolean;
	@feature(OCCLUSION_UV_B) occlusionUvB: boolean;
	@feature(PARALLAX) parallax: boolean;
}

export struct LitOutput {
	@location(0) color: Vec4f;
	@location(1) @feature(NORMAL_MRT) normal: Vec4f;
}

function skinRow(b: VertexBindings, joints: Vec4f, weights: Vec4f, column: int32): Vec4f {
	return b.skinParams.skinRows[(joints.x as int32) * 3 + column] * weights.x +
		b.skinParams.skinRows[(joints.y as int32) * 3 + column] * weights.y +
		b.skinParams.skinRows[(joints.z as int32) * 3 + column] * weights.z +
		b.skinParams.skinRows[(joints.w as int32) * 3 + column] * weights.w;
}

export function skinWorld(b: VertexBindings, joints: Vec4f, weights: Vec4f): Mat4x4f {
	return transpose(mat4x4f(
		skinRow(b, joints, weights, 0), skinRow(b, joints, weights, 1),
		skinRow(b, joints, weights, 2), vec4f(0.0, 0.0, 0.0, 1.0),
	));
}

export function instanceWorld(row0: Vec4f, row1: Vec4f, row2: Vec4f): Mat4x4f {
	return transpose(mat4x4f(
		row0, row1, row2, vec4f(0.0, 0.0, 0.0, 1.0),
	));
}

export function skinNormal(world: Mat4x4f, normal: Vec3f): Vec3f {
	const linear = upperLeft3x3(world);
	const a = cross(linear.columns[1], linear.columns[2]);
	const b = cross(linear.columns[2], linear.columns[0]);
	const c = cross(linear.columns[0], linear.columns[1]);
	const direction: float32 = dot(linear.columns[0], a) < 0.0 ? -1.0 : 1.0;
	return (a * normal.x + b * normal.y + c * normal.z) * direction;
}

// A ParticleVisual corner in world space. The instance carries its system's render mode: `look`
// is mode (0 Billboard, 1 Stretch, 2 Horizontal, 3 Vertical), alignment (0 View, 1 World,
// 2 Local, 3 Facing, 4 Velocity), pivot.z and the flags (1 allowRoll off, 2 freeform, 4 rotate
// with the stretch direction, summed); `scale` is lengthScale, velocityScale, the smallest and the
// largest size (0 for none), as fractions of the viewport width at the particle; `pull` is the
// camera's velocity times cameraVelocityScale; the emitter's axes serve Local. A zeroed instance
// is the camera-facing billboard. Each rule is Unity's, measured (docs/PARTICLES-RENDER.md A.2).
function particleVisualPoint(
	input: ParticleVisualAttributes, corner: Vec2f, b: VertexBindings,
): Vec3f {
	const root = input.root;
	const shape = input.shape;
	const velocity = input.velocity;
	const pos = root.xyz;
	const eye = b.vertexParams.cameraPosition.xyz;
	const camRight = b.vertexParams.cameraRight.xyz;
	const camUp = b.vertexParams.cameraUp.xyz;
	const camToward = cross(camRight, camUp);
	const kind = input.look;
	const scale = input.scale;
	const emitterRight = input.emitterRight;
	const emitterUp = input.emitterUp;
	let flags: float32 = kind.w;
	const rotateWith = flags >= 3.5;
	if (rotateWith) { flags = flags - 4.0; }
	const freeform = flags >= 1.5;
	if (freeform) { flags = flags - 2.0; }
	const noRoll = flags >= 0.5;
	const stretch = kind.x == 1.0;
	const pivotX = -shape.y;
	const pivotY = -shape.z;
	const pivotZ = kind.z;
	const theta = shape.w;
	const c = cos(theta);
	const s = sin(theta);
	const root2: float32 = 0.70710678;
	let w = root.w;
	let h = shape.x;
	const clipCentre = b.vertexParams.viewProj * vec4f(pos, 1.0);
	const clipRight = b.vertexParams.viewProj * vec4f(pos + camRight, 1.0);
	const viewportWidth = 2.0 * clipCentre.w / (clipRight.x - clipCentre.x);
	const big = max(w, h);
	let fit: float32 = 1.0;
	if (scale.w > 0.0 && big > scale.w * viewportWidth) {
		fit = scale.w * viewportWidth / big;
	}
	if (scale.z > 0.0 && big > 0.0 && big < scale.z * viewportWidth) {
		fit = scale.z * viewportWidth / big;
	}
	const speed = length(velocity);
	const along = velocity / max(speed, 0.000001);
	const toParticle = pos - eye;
	if (stretch) {
		if (freeform) {
			const f = normalize(toParticle);
			const right = normalize(cross(f, camUp));
			const up = cross(right, f);
			let angle = theta;
			if (rotateWith && speed > 0.000001) {
				angle = angle + atan2(dot(along, up), -dot(along, right));
			}
			const ca = cos(angle);
			const sa = sin(angle);
			const fw = w * fit;
			const fh = h * fit;
			let o = (right * ca - up * sa) * ((corner.x + pivotX) * fw)
				+ (up * ca + right * sa) * ((corner.y + pivotY) * fh) + f * (pivotZ * fw);
			const grow = scale.x + speed * scale.y / max(fh, 0.000001) - 1.0;
			o = o + along * (grow * dot(o, along));
			return pos + o;
		}
		if (speed < 0.000001) {
			return pos;
		}
		const pull = along * (h * scale.x) + velocity * scale.y - input.pull;
		const length3 = length(pull);
		const axis = pull / max(length3, 0.000001);
		const forward = -camToward;
		const across = cross(toParticle, axis);
		const flat = across - forward * dot(across, forward);
		const width = flat / max(length(flat), 0.000001);
		const fw = w * fit;
		const head = pos + width * (pivotX * fw) + axis * (2.0 * pivotY * h);
		return head + width * (corner.y * fw) - axis * ((corner.x + 0.5) * length3);
	}
	w = w * fit;
	h = h * fit;
	if (kind.x == 2.0 || kind.x == 3.0) {
		let right = vec3f(1.0, 0.0, 0.0);
		let up = vec3f(0.0, 0.0, -1.0);
		let normal = vec3f(0.0, 1.0, 0.0);
		if (kind.x == 3.0) {
			right = normalize(vec3f(camToward.z, 0.0, camRight.z));
			up = vec3f(0.0, 1.0, 0.0);
			normal = cross(right, up);
		}
		const x = 2.0 * corner.x;
		const y = 2.0 * corner.y;
		const ox = 0.5 * w * (x * c + y * s) * root2 + pivotX * w * (c - s) * root2;
		const oy = 0.5 * h * (y * c - x * s) * root2 + pivotY * h * (c + s) * root2;
		return pos + right * ox + up * oy + normal * (pivotZ * w);
	}
	let right = camRight;
	let up = camUp;
	let normal = camToward;
	if (kind.y == 0.0 && noRoll) {
		right = normalize(cross(-camToward, vec3f(0.0, 1.0, 0.0)));
		up = cross(right, -camToward);
	}
	if (kind.y == 1.0) {
		right = vec3f(1.0, 0.0, 0.0);
		up = vec3f(0.0, 1.0, 0.0);
		normal = vec3f(0.0, 0.0, -1.0);
	}
	if (kind.y == 2.0) {
		right = emitterRight;
		up = emitterUp;
		normal = -cross(right, up);
	}
	if (kind.y == 3.0) {
		normal = normalize(toParticle);
		right = normalize(cross(normal, camUp));
		up = cross(right, normal);
	}
	if (kind.y == 4.0) {
		normal = along;
		right = normalize(cross(vec3f(0.0, 0.0, 1.0), normal));
		up = cross(right, normal);
	}
	const x = (corner.x + pivotX) * w;
	const y = (corner.y + pivotY) * h;
	return pos + (right * c - up * s) * x + (up * c + right * s) * y + normal * (pivotZ * w);
}

export function particleVisualPixelArtVs(
	input: ParticleVisualAttributes, b: VertexBindings,
): ParticleVisualPixelArtVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const world = particleVisualPoint(input, corner, b);
	const clip = b.vertexParams.viewProj * vec4f(world, 1.0);
	return {
		uv: vec2f(corner.x > 0.0 ? input.tile.z : input.tile.x,
			corner.y > 0.0 ? input.tile.y : input.tile.w),
		rootPosition: input.root.xyz,
		instanceColor: input.color,
		depth01: clip.z,
		clip: clip,
	};
}

export function particleVisualVs(
	input: ParticleVisualAttributes, b: VertexBindings,
): ParticleVisualVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const world = particleVisualPoint(input, corner, b);
	return {
		worldPosition: world,
		towardCamera: cross(b.vertexParams.cameraRight.xyz, b.vertexParams.cameraUp.xyz),
		uv: vec2f(corner.x > 0.0 ? input.tile.z : input.tile.x,
			corner.y > 0.0 ? input.tile.y : input.tile.w),
		instanceColor: input.color,
		clip: b.vertexParams.viewProj * vec4f(world, 1.0),
	};
}

export struct ParticleAttributes {
	root: Vec4f;
	color: Vec4f;
	@builtin(vertexIndex) index: uint32;
}

export struct ParticleVaryings {
	particleColor: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct ParticleFragmentInput {
	particleColor: Vec4f;
}

export struct ParticleBindings {
	@binding(6) frameParams: FrameParams;
}

export struct ParticleKey {
	@feature(CUTOUT) cutout: boolean;
}

export function particleVs(input: ParticleAttributes, b: VertexBindings): ParticleVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const right = b.vertexParams.cameraRight.xyz;
	const up = b.vertexParams.cameraUp.xyz;
	const world = input.root.xyz + right * (corner.x * input.root.w) +
		up * (corner.y * input.root.w);
	return { particleColor: input.color, clip: b.vertexParams.viewProj * vec4f(world, 1.0) };
}

export function particleFs(
	input: ParticleFragmentInput, b: ParticleBindings, key: ParticleKey,
): Vec4f {
	const color = input.particleColor;
	if (key.cutout) {
		if (color.a < 0.5) {
			discard();
		}
	}
	return vec4f(toneMapped(color.rgb, b.frameParams.frame), color.a);
}

export struct BillboardAttributes {
	position: Vec3f;
	size: Vec2f;
	anchor: Vec2f;
	tile: Vec4f;
	color: Vec4f;
	@builtin(vertexIndex) index: uint32;
}

export struct BillboardFragmentInput {
	worldPosition: Vec3f;
	towardCamera: Vec3f;
	uv: Vec2f;
	instanceColor: Vec4f;
	@builtin(position) fragCoord: Vec4f;
}

export struct BillboardParams {
	billboardColor: Vec4f;
	billboard: Vec4f;
}

export struct BillboardBindings {
	@binding(2) billboardParams: BillboardParams;
	@binding(1) lightParams: LightParams;
	@binding(6) frameParams: FrameParams;
	@binding(0) billboardTexture: Texture2d;
	@binding(0) billboardSampler: Sampler;
	@binding(9) @sampleType(unfilterable_float) lightRecords: Texture2d;
	@binding(10) clusterRecords: Texture2dU32;
	@binding(11) clusterIndices: Texture2dU32;
	@binding(5) @samplerType(nonfiltering) clusterSampler: Sampler;
}

export struct BillboardKey {
	@feature(CUTOUT) cutout: boolean;
	@feature(PREMULTIPLIED) premultiplied: boolean;
}

export function billboardPoint(
	position: Vec3f, size: Vec2f, anchor: Vec2f, corner: Vec2f, right: Vec3f, up: Vec3f,
): Vec3f {
	const offset = corner - anchor;
	return position + right * (offset.x * size.x) + up * (offset.y * size.y);
}

export function billboardVs(input: BillboardAttributes, b: VertexBindings): ParticleVisualVaryings {
	const corner = PARTICLE_CORNERS[input.index % 6];
	const right = b.vertexParams.cameraRight.xyz;
	const up = b.vertexParams.cameraUp.xyz;
	// PENDING3D: particle-size-world-units
	const world = billboardPoint(input.position, input.size, input.anchor, corner, right, up);
	return {
		worldPosition: world,
		// PENDING3D: billboard-normal-toward-camera
		towardCamera: cross(right, up),
		uv: vec2f(corner.x > 0.0 ? input.tile.z : input.tile.x,
			corner.y > 0.0 ? input.tile.y : input.tile.w),
		instanceColor: input.color,
		clip: b.vertexParams.viewProj * vec4f(world, 1.0),
	};
}

export function billboardFs(
	input: BillboardFragmentInput, b: BillboardBindings, key: BillboardKey,
): Vec4f {
	let texel = textureSample(b.billboardTexture, b.billboardSampler, input.uv);
	if (key.premultiplied) {
		texel = straightTexel(texel);
	}
	let pixel = b.billboardParams.billboardColor * texel * input.instanceColor;
	if (key.cutout) {
		if (pixel.a < 0.5) {
			discard();
		}
	}
	if (b.billboardParams.billboard.y != 0.0) {
		const n = normalize(input.towardCamera);
		const dir = b.lightParams.dirLight;
		const lambert = max(dot(n, dir.xyz), 0.0) * dir.w;
		let light = srgbToLinear(b.lightParams.ambient.rgb) +
			srgbToLinear(b.lightParams.dirColor.rgb) * lambert;
		const cluster = billboardClusterOf(input.fragCoord.xy, input.worldPosition, b);
		for (let k = 0; k < cluster.y + cluster.z; k++) {
			const i = billboardLightOf(b, cluster, k);
			light = light + lightAt(input.worldPosition, n, billboardTexelOf(b, i, 0),
				billboardTexelOf(b, i, 1), billboardTexelOf(b, i, 2), billboardTexelOf(b, i, 3),
				billboardTexelOf(b, i, 4), billboardTexelOf(b, i, 5));
		}
		pixel = vec4f(linearToSrgb(srgbToLinear(pixel.rgb) * light), pixel.a);
	}
	pixel = vec4f(toneMapped(pixel.rgb, b.frameParams.frame), pixel.a);
	if (key.premultiplied) {
		pixel = vec4f(pixel.rgb * pixel.a, pixel.a);
	}
	return pixel;
}

export function litVs(input: LitAttributes, b: VertexBindings, key: LitKey): LitVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		const world = matrix * vec4f(input.position, 1.0);
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			baseColor: input.color,
			clip: b.vertexParams.viewProj * world,
		};
	} else {
		const matrix = instanceWorld(input.instanceRow0, input.instanceRow1, input.instanceRow2);
		const world = matrix * vec4f(input.position, 1.0);
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			baseColor: input.color * input.instanceColor,
			clip: b.vertexParams.viewProj * world,
		};
	}
}

// -1 for a world matrix that mirrors, whose tangent frame flips with it.
export function handednessOf(matrix: Mat4x4f): float32 {
	return determinant(upperLeft3x3(matrix)) < 0.0 ? -1.0 : 1.0;
}

export function litTexturedVs(
	input: TexturedAttributes, b: VertexBindings, key: LitKey,
): LitTexturedVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		const world = matrix * vec4f(input.position, 1.0);
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			worldTangent: vec4f(
				upperLeft3x3(matrix) * input.tangent.xyz, input.tangent.w * handednessOf(matrix),
			),
			surfaceUv: input.uv,
			surfaceUvB: input.uvB,
			baseColor: input.color,
			clip: b.vertexParams.viewProj * world,
		};
	} else {
		const matrix = instanceWorld(input.instanceRow0, input.instanceRow1, input.instanceRow2);
		const world = matrix * vec4f(input.position, 1.0);
		return {
			worldPosition: world.xyz,
			worldNormal: skinNormal(matrix, input.normal),
			worldTangent: vec4f(
				upperLeft3x3(matrix) * input.tangent.xyz, input.tangent.w * handednessOf(matrix),
			),
			surfaceUv: input.uv,
			surfaceUvB: input.uvB,
			baseColor: input.color * input.instanceColor,
			clip: b.vertexParams.viewProj * world,
		};
	}
}

export function unlitTexturedVs(
	input: TexturedAttributes,
	b: VertexBindings,
	key: LitKey,
): UnlitTexturedVaryings {
	if (key.skinned) {
		const matrix = skinWorld(b, input.skinJoints, input.skinWeights);
		return {
			clip: b.vertexParams.viewProj * matrix * vec4f(input.position, 1.0),
			worldNormal: skinNormal(matrix, input.normal),
			surfaceUv: input.uv,
			baseColor: input.color,
		};
	} else {
		const matrix = instanceWorld(input.instanceRow0, input.instanceRow1, input.instanceRow2);
		return {
			clip: b.vertexParams.viewProj * matrix * vec4f(input.position, 1.0),
			worldNormal: skinNormal(matrix, input.normal),
			surfaceUv: input.uv,
			baseColor: input.color * input.instanceColor,
		};
	}
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

// One light slot's shape, in shapeA.w: 0 point, 1 spot, 2 rectangle, 3 capsule. A shaped light
// keeps the point light's window, (1 - d / range)^2 with d to the point the shape stands for
// (a spot's position, a rectangle's or capsule's closest point), and multiplies its own angular
// term in; pbr/Light.hx's pointLightIntensity is the 1 / (d^2 + 1) curve the point light here
// already replaces. The sample is xyz toward the light, w the window times the cone, and a ray
// or segment the shape cannot place (a surface seen edge on, a receiver on the light) gives w 0
// where Heaps divides by zero.
export function lightWindow(distance: float32, range: float32): float32 {
	const window = clamp(1.0 - distance / range, 0.0, 1.0);
	return window * window;
}

// pbr/Light.hx spotLightIntensity's angular half (60-62): theta = dot(delta.normalize(),
// -spotDir), clamp((theta - angle) / (fallOff - angle)). a: forward, b: cos(angle / 2), cos(inner),
// then 0 and its full angle (spotShadow.ms).
export function spotSample(position: Vec3f, at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f): Vec4f {
	const delta = at.xyz - position;
	const distance = length(delta);
	if (distance < 0.0001) {
		return vec4f(0.0);
	}
	const toLight = delta / distance;
	const cone = clamp((dot(toLight, -a.xyz) - b.x) / (b.y - b.x), 0.0, 1.0);
	return vec4f(toLight, lightWindow(distance, tint.a) * cone);
}

// pbr/Light.hx rectangleLightIntensity (67-84), one axis: the delta and the inverse light
// direction projected off `excluded`, their cosine against the outer and inner cosines with
// Heaps' 0.00001 widening.
export function rectangleAxisCone(
	delta: Vec3f, forward: Vec3f, excluded: Vec3f, outer: float32, inner: float32,
): float32 {
	const projectedDelta = delta - excluded * dot(delta, excluded);
	const projectedLight = -forward - excluded * dot(-forward, excluded);
	const deltaLength = length(projectedDelta);
	const lightLength = length(projectedLight);
	if (deltaLength < 0.0001 || lightLength < 0.0001) {
		return 0.0;
	}
	const theta = dot(projectedDelta, projectedLight) / (deltaLength * lightLength);
	return clamp((theta - outer) / (inner - outer + 0.00001), 0.0, 1.0);
}

// pbr/Light.hx closestPointOnRectangle (28-32) over tracePlane (23-26): `ray` traced to the
// light's plane, clamped to the half sizes. a: forward, b: right and half width, c: up and half
// height.
export function rectanglePoint(
	position: Vec3f, ray: Vec3f, at: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f,
): Vec3f {
	const along = dot(a.xyz, at.xyz - position) / dot(a.xyz, ray);
	const offset = position + ray * along - at.xyz;
	return at.xyz + b.xyz * clamp(dot(offset, b.xyz), -b.w, b.w) +
		c.xyz * clamp(dot(offset, c.xyz), -c.w, c.w);
}

// pbr/Light.hx rectangleLightDiffuse (101-105), the surface normal as the ray. d: cos outer and
// inner of the horizontal angle, then of the vertical.
export function rectangleSample(
	position: Vec3f, normal: Vec3f, at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f, d: Vec4f,
): Vec4f {
	if (abs(dot(a.xyz, normal)) < 0.000001) {
		return vec4f(0.0);
	}
	const delta = rectanglePoint(position, normal, at, a, b, c) - position;
	const distance = length(delta);
	if (distance < 0.0001) {
		return vec4f(0.0);
	}
	const cone = rectangleAxisCone(delta, a.xyz, c.xyz, d.x, d.y) *
		rectangleAxisCone(delta, a.xyz, b.xyz, d.z, d.w);
	return vec4f(delta / distance, lightWindow(distance, tint.a) * cone);
}

// pbr/Light.hx capsuleLightDiffuse (86-90) over closestPointLineToPoint (8-12). a: axis, b: half
// length.
export function capsuleSample(position: Vec3f, at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f): Vec4f {
	const start = at.xyz - a.xyz * b.x;
	const segment = a.xyz * (2.0 * b.x);
	const along = clamp(dot(position - start, segment) / dot(segment, segment), 0.0, 1.0);
	const delta = start + segment * along - position;
	const distance = length(delta);
	if (distance < 0.0001) {
		return vec4f(0.0);
	}
	return vec4f(delta / distance, lightWindow(distance, tint.a));
}

// pbr/Light.hx rectangleLightSpecularDir (107-109): the plane point along the reflected view
// ray. A ray in the plane keeps the diffuse direction.
export function rectangleSpecularDir(
	position: Vec3f, reflected: Vec3f, diffuse: Vec3f, at: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f,
): Vec3f {
	if (abs(dot(a.xyz, reflected)) < 0.000001) {
		return diffuse;
	}
	return normalize(rectanglePoint(position, reflected, at, a, b, c) - position);
}

// pbr/Light.hx capsuleLightSpecularDir (92-99) over closestPointLineToRay (14-21). b.y is the
// radius, capped at the range (CapsuleLight.hx:68). A ray along the segment, or through it,
// keeps the diffuse direction where Heaps divides by zero.
export function capsuleSpecularDir(
	position: Vec3f, reflected: Vec3f, diffuse: Vec3f, at: Vec4f, a: Vec4f, b: Vec4f,
): Vec3f {
	const l0 = at.xyz - a.xyz * b.x - position;
	const l01 = a.xyz * (2.0 * b.x);
	const squared = dot(l01, l01);
	const alongRay = dot(reflected, l01);
	const denominator = squared - alongRay * alongRay;
	if (denominator <= 0.000001) {
		return diffuse;
	}
	const closest = l0 + l01 * clamp(dot(l0, reflected * alongRay - l01) / denominator, 0.0, 1.0);
	const centerToRay = reflected * dot(closest, reflected) - closest;
	const offset = length(centerToRay);
	if (offset < 0.000001) {
		return normalize(closest);
	}
	return normalize(closest + centerToRay * clamp(b.y / offset, 0.0, 1.0));
}

export function shapedSample(
	position: Vec3f, normal: Vec3f, at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f, d: Vec4f,
): Vec4f {
	if (a.w > 2.5) {
		return capsuleSample(position, at, tint, a, b);
	}
	if (a.w > 1.5) {
		return rectangleSample(position, normal, at, tint, a, b, c, d);
	}
	return spotSample(position, at, tint, a, b);
}

export function shapedSpecularDir(
	position: Vec3f, reflected: Vec3f, diffuse: Vec3f, at: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f,
): Vec3f {
	if (a.w > 2.5) {
		return capsuleSpecularDir(position, reflected, diffuse, at, a, b);
	}
	if (a.w > 1.5) {
		return rectangleSpecularDir(position, reflected, diffuse, at, a, b, c);
	}
	return diffuse;
}

// PENDING3D: light-shape-range-window
// PENDING3D: light-shape-degenerate-black
// pointLightAt for a slot of any shape: a point light is pointLightAt untouched.
export function lightAt(
	position: Vec3f, normal: Vec3f, at: Vec4f, tint: Vec4f, a: Vec4f, b: Vec4f, c: Vec4f, d: Vec4f,
): Vec3f {
	let lit: Vec3f = vec3f(0.0);
	if (a.w < 0.5) {
		lit = pointLightAt(position, normal, at, tint);
	} else {
		const sample = shapedSample(position, normal, at, tint, a, b, c, d);
		lit = srgbToLinear(tint.rgb) * (sample.w * max(dot(normal, sample.xyz), 0.0) * at.w);
	}
	return lit;
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
	if (key.pbr) {
		if (key.emissive) {
			return b.pbrEmissiveMaterialParams.material;
		} else {
			return b.pbrMaterialParams.material;
		}
	} else {
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
}

export function materialColorOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.pbr) {
		if (key.emissive) {
			return b.pbrEmissiveMaterialParams.materialColor;
		} else {
			return b.pbrMaterialParams.materialColor;
		}
	} else {
		if (key.uvTransform || key.backTexture || key.dissolve) {
			if (key.emissive) {
				return b.movingEmissiveMaterialParams.materialColor;
			} else {
				return b.movingMaterialParams.materialColor;
			}
		} else {
			if (key.emissive) {
				return b.emissiveMaterialParams.materialColor;
			} else {
				return b.materialParams.materialColor;
			}
		}
	}
}

// The surface a lit program shades: `color` (the vertex colour, times the texel when textured)
// times the material's colour, as Heaps' BaseMesh multiplies its `color` param in.
export function tintedSurface(b: LitBindings, key: LitKey, color: Vec4f): Vec4f {
	return color * materialColorOf(b, key);
}

export function emissiveOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.pbr) {
		return b.pbrEmissiveMaterialParams.emissive;
	} else {
		if (key.uvTransform || key.backTexture || key.dissolve) {
			return b.movingEmissiveMaterialParams.emissive;
		} else {
			return b.emissiveMaterialParams.emissive;
		}
	}
}

export function pbrOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.emissive) {
		return b.pbrEmissiveMaterialParams.pbr;
	} else {
		return b.pbrMaterialParams.pbr;
	}
}

export function uvMatrixOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.pbr) {
		if (key.emissive) {
			return b.pbrEmissiveMaterialParams.uvMatrix;
		} else {
			return b.pbrMaterialParams.uvMatrix;
		}
	} else {
		if (key.emissive) {
			return b.movingEmissiveMaterialParams.uvMatrix;
		} else {
			return b.movingMaterialParams.uvMatrix;
		}
	}
}

export function uvMotionOf(b: LitBindings, key: LitKey): Vec4f {
	if (key.pbr) {
		if (key.emissive) {
			return b.pbrEmissiveMaterialParams.uvMotion;
		} else {
			return b.pbrMaterialParams.uvMotion;
		}
	} else {
		if (key.emissive) {
			return b.movingEmissiveMaterialParams.uvMotion;
		} else {
			return b.movingMaterialParams.uvMotion;
		}
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

// h3d.shader.ShadowSampling.sampleShadow with SAMPLING_NONE, on the maps dirShadowMap.ms draws. A
// spot's matrix is perspective, so the product is divided by w (ShadowSampling.hx:49-53); a
// position behind the spot (w <= 0), like a half of the block nobody wrote, reads lit.
// PENDING3D: spot-shadow-behind-lit
export function dirShadowAt(position: Vec3f, b: LitBindings): float32 {
	const depth = cascadeDepthOf(position, b.frameParams.cameraPosition.xyz,
		b.shadowParams.cascadeView);
	const cascade = cascadeIndexOf(depth, b.shadowParams.cascadeFar, b.shadowParams.cascadeInfo);
	if (cascade >= cascadeCountOf(b.shadowParams.cascadeInfo)) {
		return 1.0;
	}
	const lit = cascadeShadowAt(position, b, cascade);
	const blend = cascadeBlendOf(depth, cascade, b.shadowParams.cascadeFar,
		b.shadowParams.cascadeInfo);
	if (blend > 0.0) {
		return mix(lit, cascadeShadowAt(position, b, cascade + 1), blend);
	}
	return lit;
}

export function cascadeShadowAt(position: Vec3f, b: LitBindings, cascade: int32): float32 {
	const texel = cascadeTexelOf(position, b.shadowParams.cascadeMatrices[cascade],
		b.shadowParams.cascadeView);
	const scale = b.shadowParams.cascadeFilter.x;
	if (texel.w < 0.5 || scale <= 0.0) {
		const stored = textureLoad(b.shadowMap, b.shadowSampler, vec2i(texel.xy), cascade, 0).x;
		return cascadeLitOf(texel, stored, b.shadowParams.cascadeInfo);
	}
	const uv = mapCoord(position, b.shadowParams.cascadeMatrices[cascade]);
	const size = (b.shadowParams.cascadeView.w + 0.5) as int32;
	const rotation = poissonRotation(position);
	let lit: float32 = 0.0;
	for (let tap = 0; tap < PCF_SAMPLES; tap++) {
		const at = pcfTexelOf(uv, size, poissonOffset(tap, rotation, scale));
		const stored = textureLoad(b.shadowMap, b.shadowSampler, at, cascade, 0).x;
		lit = lit + cascadeLitOf(texel, stored, b.shadowParams.cascadeInfo);
	}
	return lit / (PCF_SAMPLES as float32);
}

export function spotShadowAt(position: Vec3f, b: LitBindings): float32 {
	const p = mapCoord(position, b.shadowParams.spotMatrix);
	if (p.w < 0.5) {
		return 1.0;
	}
	const size = (b.shadowParams.spotShadow.z + 0.5) as int32;
	const scale = b.shadowParams.spotShadow.w;
	if (scale <= 0.0) {
		const depth = textureLoad(b.spotShadowMap, b.spotShadowSampler,
			pcfTexelOf(p, size, vec2f(0.0)), 0, 0).x;
		return mapLit(p.z, depth, b.shadowParams.spotShadow.x, b.shadowParams.spotShadow.y);
	}
	const rotation = poissonRotation(position);
	let lit: float32 = 0.0;
	for (let tap = 0; tap < PCF_SAMPLES; tap++) {
		const at = pcfTexelOf(p, size, poissonOffset(tap, rotation, scale));
		const depth = textureLoad(b.spotShadowMap, b.spotShadowSampler, at, 0, 0).x;
		lit = lit + mapLit(p.z, depth, b.shadowParams.spotShadow.x, b.shadowParams.spotShadow.y);
	}
	return lit / (PCF_SAMPLES as float32);
}

export function cubeFaceOf(toPosition: Vec3f): int32 {
	const axes = abs(toPosition);
	if (axes.x >= axes.y && axes.x >= axes.z) {
		return toPosition.x > 0.0 ? 0 : 1;
	}
	if (axes.y >= axes.z) {
		return toPosition.y > 0.0 ? 2 : 3;
	}
	return toPosition.z > 0.0 ? 4 : 5;
}

function cubeTapAt(position: Vec3f, b: LitBindings): float32 {
	const face = cubeFaceOf(position - b.shadowParams.cubeLight.xyz);
	const p = mapCoord(position, b.shadowParams.cubeMatrices[face]);
	if (p.w < 0.5) {
		return 1.0;
	}
	const size = (b.shadowParams.cubeShadow.z + 0.5) as int32;
	const depth = textureLoad(b.cubeShadowMap, b.spotShadowSampler,
		pcfTexelOf(p, size, vec2f(0.0)), face, 0).x;
	return mapLit(p.z, depth, b.shadowParams.cubeShadow.x, b.shadowParams.cubeShadow.y);
}

// cubeShadowPcf's taps turn the light-to-receiver direction and keep its distance, each read
// from the face it then points into.
export function cubeShadowAt(position: Vec3f, b: LitBindings): float32 {
	const scale = b.shadowParams.cubeShadow.w / b.shadowParams.cubeShadow.z;
	const light = b.shadowParams.cubeLight.xyz;
	const toPosition = position - light;
	const distance = length(toPosition);
	if (!(scale > 0.0) || !(distance > 0.0)) {
		return cubeTapAt(position, b);
	}
	const direction = toPosition / distance;
	let lit: float32 = 0.0;
	for (let tap = 0; tap < CUBE_PCF_SAMPLES; tap++) {
		const turned = normalize(direction + CUBE_PCF_OFFSETS[tap] * scale);
		lit = lit + cubeTapAt(light + turned * distance, b);
	}
	return lit / (CUBE_PCF_SAMPLES as float32);
}

// A positioned light's shadow (SpotShadow's sampleShadow, DefaultForward.hx:179-191): 1 unless
// record `i` is the one the light block names as the spot map's or the cube map's caster
// (gpu3d.ms LIGHT_SPOT_CASTER, LIGHT_CUBE_CASTER).
export function recordShadowAt(position: Vec3f, b: LitBindings, key: LitKey, i: int32): float32 {
	if (!key.shadowed) {
		return 1.0;
	}
	const named = (i + 1) as float32;
	if (b.lightParams.ambient.w == named) {
		return spotShadowAt(position, b);
	}
	if (b.lightParams.dirColor.w == named) {
		return cubeShadowAt(position, b);
	}
	return 1.0;
}

// The record of the fragment's cluster: the offset into the index list, the point light count,
// the spot count.
export function litClusterOf(frag: Vec2f, position: Vec3f, b: LitBindings): Vec4i {
	const cluster = fragmentClusterOf(frag, position, b.lightParams.clusterGrid,
		b.lightParams.clusterFactors, b.lightParams.clusterView, b.lightParams.clusterScreen);
	return vec4i(textureLoad(b.clusterRecords, b.clusterSampler, dataTexelOf(cluster), 0));
}

export function litLightOf(b: LitBindings, cluster: Vec4i, k: int32): int32 {
	const j = cluster.x + k;
	return indexOfWord(textureLoad(b.clusterIndices, b.clusterSampler, indexTexelOf(j), 0), j);
}

export function litTexelOf(b: LitBindings, light: int32, texel: int32): Vec4f {
	return textureLoad(b.lightRecords, b.clusterSampler, recordTexelOf(light, texel), 0);
}

export function billboardClusterOf(frag: Vec2f, position: Vec3f, b: BillboardBindings): Vec4i {
	const cluster = fragmentClusterOf(frag, position, b.lightParams.clusterGrid,
		b.lightParams.clusterFactors, b.lightParams.clusterView, b.lightParams.clusterScreen);
	return vec4i(textureLoad(b.clusterRecords, b.clusterSampler, dataTexelOf(cluster), 0));
}

export function billboardLightOf(b: BillboardBindings, cluster: Vec4i, k: int32): int32 {
	const j = cluster.x + k;
	return indexOfWord(textureLoad(b.clusterIndices, b.clusterSampler, indexTexelOf(j), 0), j);
}

export function billboardTexelOf(b: BillboardBindings, light: int32, texel: int32): Vec4f {
	return textureLoad(b.lightRecords, b.clusterSampler, recordTexelOf(light, texel), 0);
}

// h3d.shader.pbr.Direct (Lighting.hx:125-145) for one light, in linear light: Cook-Torrance GGX
// with Schlick-GGX visibility and the exp2 Fresnel (BRDF.hx:40-63), F0 = mix(0.04, albedo,
// metalness) (PropsImport.hx:74). `radiance` excludes N.L and the shadow; `occlusionFactor` is
// pbrOcclusionFactor, whose Heaps default is 0 (Light.hx:10), so glTF's ambient-only occlusion
// holds. pbrResponse.ms is its CPU oracle, minus the validation a shader cannot report: roughness 0
// has no guard in Heaps either, so a material never carries it (material.ms pbrValues).
export function pbrDirect(
	albedo: Vec3f,
	metalness: float32,
	roughness: float32,
	normal: Vec3f,
	view: Vec3f,
	light: Vec3f,
	radiance: Vec3f,
	shadow: float32,
	occlusionFactor: float32,
	occlusion: float32,
): Vec3f {
	return pbrDirectSpecular(albedo, metalness, roughness, normal, view, light, light, radiance,
		shadow, occlusionFactor, occlusion);
}

// pbrDirect with Direct's pbrSpecularLightDirection (Lighting.hx:119-121): `specularLight` only
// feeds the half vector, as a rectangle or capsule light's representative point does, while N.L
// and the geometry term keep the diffuse `light`.
export function pbrDirectSpecular(
	albedo: Vec3f,
	metalness: float32,
	roughness: float32,
	normal: Vec3f,
	view: Vec3f,
	light: Vec3f,
	specularLight: Vec3f,
	radiance: Vec3f,
	shadow: float32,
	occlusionFactor: float32,
	occlusion: float32,
): Vec3f {
	if (dot(radiance, radiance) <= 0.0001) {
		return vec3f(0.0);
	}
	const n = normalize(normal);
	const v = normalize(view);
	const l = normalize(light);
	const nl = clamp(dot(n, l), 0.0, 1.0);
	if (nl <= 0.0) {
		return vec3f(0.0);
	}
	const h = normalize(normalize(specularLight) + v);
	const nh = clamp(dot(n, h), 0.0, 1.0);
	const vh = clamp(dot(v, h), 0.0, 1.0);
	const nv = clamp(dot(n, v), 0.0, 1.0);
	const alpha = roughness * roughness;
	const alpha2 = alpha * alpha;
	const denominator = nh * nh * (alpha2 - 1.0) + 1.0;
	const distribution = alpha2 / (3.14159265358979 * denominator * denominator);
	const remapped = roughness + 1.0;
	const k = remapped * remapped * 0.125;
	const visibility = (1.0 / (nv * (1.0 - k) + k)) * (1.0 / (nl * (1.0 - k) + k)) * 0.25;
	const f0 = mix(vec3f(0.04), albedo, metalness);
	const fresnel = f0 + (1.0 - f0) * exp2((-5.55473 * vh - 6.98316) * vh);
	const specular = max(fresnel * (distribution * visibility), vec3f(0.0));
	const diffuse = albedo * (1.0 / 3.14159265358979) * (1.0 - metalness) * (1.0 - fresnel);
	const reach = nl * shadow * mix(1.0, occlusion, occlusionFactor);
	return (diffuse + specular) * radiance * reach;
}

// h3d.shader.pbr.Indirect's diffuse half with a flat ambient as the irradiance (Lighting.hx:78-99,
// drawIndirectDiffuse): the specular half needs an environment map, which void3d has none of.
export function pbrAmbient(
	albedo: Vec3f,
	metalness: float32,
	roughness: float32,
	normal: Vec3f,
	view: Vec3f,
	ambient: Vec3f,
	occlusion: float32,
): Vec3f {
	const nv = max(dot(normalize(normal), normalize(view)), 0.0);
	const f0 = mix(vec3f(0.04), albedo, metalness);
	const fresnel =
		f0 + (max(vec3f(1.0 - roughness), f0) - f0) * exp2((-5.55473 * nv - 6.98316) * nv);
	return ambient * albedo * (1.0 - metalness) * (1.0 - fresnel) * occlusion;
}

// Bevy pbr_lighting.wesl:527-538, the analytic split sum standing in for Heaps' irrLut: the
// scale and bias of F0 in the specular response.
export function splitSum(roughness: float32, nv: float32): Vec2f {
	const rx = 1.0 - roughness;
	const ry = 0.0425 - 0.0275 * roughness;
	const a004 = min(rx * rx, exp2(-9.28 * nv)) * rx + ry;
	return max(
		vec2f(-1.04 * a004 + 1.04 - 0.572 * roughness, 1.04 * a004 - 0.04 + 0.022 * roughness),
		vec2f(0.00005),
	);
}

// Renderer.hx:716 irrRotation turned about this frame's up axis, Heaps' z.
function envTurned(d: Vec3f, turn: Vec4f): Vec3f {
	return vec3f(d.x * turn.z - d.z * turn.w, d.y, d.x * turn.w + d.z * turn.z);
}

// h3d.shader.pbr.Indirect without the sky and emissive terms (Lighting.hx:85-99): the baked
// irradiance and the specular cube at roughness * irrSpecularLevels, both turned, times irrPower
// and the occlusion. envParams holds irrPower, irrSpecularLevels and the turn's cosine and sine.
export function pbrEnvironmentLight(
	albedo: Vec3f,
	metalness: float32,
	roughness: float32,
	normal: Vec3f,
	view: Vec3f,
	occlusion: float32,
	b: LitBindings,
): Vec3f {
	const n = normalize(normal);
	const v = normalize(view);
	const nv = max(dot(n, v), 0.0);
	const f0 = mix(vec3f(0.04), albedo, metalness);
	const fresnel =
		f0 + (max(vec3f(1.0 - roughness), f0) - f0) * exp2((-5.55473 * nv - 6.98316) * nv);
	const turn = b.frameParams.envParams;
	const irradiance = textureSampleLevel(b.envDiffuse, b.envSampler, envTurned(n, turn), 0.0).rgb;
	const radiance = textureSampleLevel(b.envSpecular, b.envSampler,
		envTurned(reflect(-v, n), turn), roughness * turn.y).rgb;
	const lut = splitSum(roughness, nv);
	const specular = radiance * (fresnel * lut.x + lut.y);
	return (irradiance * albedo * (1.0 - metalness) * (1.0 - fresnel) + specular) *
		(turn.x * occlusion);
}

// Heaps' Parallax (h3d/shader/Parallax.hx) at PbrMaterial's steps, 6 to 24, reading the height
// from the pbr-maps texture's alpha as PbrMaterial hands it its props texture. The tangent basis is
// mappedNormal's, so the steps and the mapped normal agree on the bitangent's sign.
export function parallaxUv(
	b: LitBindings,
	uv: Vec2f,
	view: Vec3f,
	normal: Vec3f,
	tangent: Vec4f,
	amount: float32,
): Vec2f {
	const t = normalize(tangent.xyz);
	const sign: float32 = tangent.w < 0.0 ? -1.0 : 1.0;
	const bitangent = normalize(cross(normal, t)) * sign;
	const viewNs = normalize(vec3f(dot(view, t), dot(view, bitangent), dot(view, normal)));
	const layers = mix(24.0, 6.0, clamp(abs(viewNs.z), 0.0, 1.0));
	const layerDepth = 1.0 / layers;
	const delta = viewNs.xy * (-amount / (viewNs.z * layers));
	let at = uv;
	let depth = 1.0 - textureSampleLevel(b.metalRoughTexture, b.baseSampler, at, 0.0).a;
	let layer: float32 = 0.0;
	while (layer < depth) {
		at = at + delta;
		depth = 1.0 - textureSampleLevel(b.metalRoughTexture, b.baseSampler, at, 0.0).a;
		layer = layer + layerDepth;
	}
	const previous = at - delta;
	const after = depth - layer;
	const before = 1.0 - textureSample(b.metalRoughTexture, b.baseSampler, previous).a - layer +
		layerDepth;
	return mix(at, previous, after / (after - before));
}

// Roughness floors at 0.089 as Bevy's clampedPerceptualRoughness (pbr_lighting.wesl:550): a
// texel of 0 has no BRDF response, and a texture cannot be refused per pixel.
export function pbrMapped(b: LitBindings, key: LitKey, uv: Vec2f, occlusionUv: Vec2f): Vec3f {
	const metalRoughTexel = textureSample(b.metalRoughTexture, b.baseSampler, uv);
	const occluded = textureSample(b.occlusionTexture, b.baseSampler, occlusionUv).r;
	const values = pbrOf(b, key);
	return vec3f(
		values.x * metalRoughTexel.b,
		max(values.y * metalRoughTexel.g, 0.089),
		values.z * (1.0 + values.w * (occluded - 1.0)),
	);
}

// The lit surface under the PBR path: the material's albedo (linear, saturated as the material
// says) under the same ambient, directional and point lights litShade reads, from the camera
// frame.cameraPosition names. The sun is shadowed, as Heaps' `shadow` scales every light of a
// pass; a point light has no shadow here, and one spot may (recordShadowAt).
export function pbrShade(
	n: Vec3f,
	position: Vec3f,
	frag: Vec2f,
	surfaceColor: Vec4f,
	b: LitBindings,
	key: LitKey,
	values: Vec3f,
): Vec4f {
	const albedo = srgbToLinear(saturated(surfaceColor.rgb, materialOf(b, key).y));
	const view = b.frameParams.cameraPosition.xyz - position;
	const dir = b.lightParams.dirLight;
	let shadow: float32 = 1.0;
	if (key.shadowed) {
		shadow = dirShadowAt(position, b);
	}
	const sun = srgbToLinear(b.lightParams.dirColor.rgb) * dir.w;
	let light = vec3f(0.0);
	if (b.frameParams.envParams.x > 0.0) {
		light = pbrEnvironmentLight(albedo, values.x, values.y, n, view, values.z, b);
	} else {
		light = pbrAmbient(albedo, values.x, values.y, n, view,
			srgbToLinear(b.lightParams.ambient.rgb), values.z);
	}
	light = light +
		pbrDirect(albedo, values.x, values.y, n, view, dir.xyz, sun, shadow, 0.0, values.z);
	const eye = normalize(view);
	const reflected = -eye - n * (2.0 * dot(-eye, n));
	const cluster = litClusterOf(frag, position, b);
	for (let k = 0; k < cluster.y + cluster.z; k++) {
		const i = litLightOf(b, cluster, k);
		const at = litTexelOf(b, i, 0);
		const tint = litTexelOf(b, i, 1);
		const a = litTexelOf(b, i, 2);
		const bb = litTexelOf(b, i, 3);
		if (a.w < 0.5) {
			const toLight = at.xyz - position;
			const falloff = clamp(1.0 - length(toLight) / tint.a, 0.0, 1.0);
			const radiance = srgbToLinear(tint.rgb) * (falloff * falloff * at.w);
			light = light + pbrDirect(albedo, values.x, values.y, n, view, toLight, radiance,
				recordShadowAt(position, b, key, i), 0.0, values.z);
		} else {
			const cc = litTexelOf(b, i, 4);
			const sample = shapedSample(position, n, at, tint, a, bb, cc, litTexelOf(b, i, 5));
			const radiance = srgbToLinear(tint.rgb) * (sample.w * at.w);
			const specular = shapedSpecularDir(position, reflected, sample.xyz, at, a, bb, cc);
			light = light + pbrDirectSpecular(albedo, values.x, values.y, n, view, sample.xyz,
				specular, radiance, recordShadowAt(position, b, key, i), 0.0, values.z);
		}
	}
	return vec4f(linearToSrgb(light), surfaceColor.a);
}

// The lit surface: its colour (the vertex colour, times the texel when textured) under the
// ambient, directional and point lights, saturated as the material says.
export function litShade(
	n: Vec3f,
	position: Vec3f,
	frag: Vec2f,
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
	const cluster = litClusterOf(frag, position, b);
	for (let k = 0; k < cluster.y + cluster.z; k++) {
		const i = litLightOf(b, cluster, k);
		light = light + lightAt(position, n, litTexelOf(b, i, 0), litTexelOf(b, i, 1),
			litTexelOf(b, i, 2), litTexelOf(b, i, 3), litTexelOf(b, i, 4), litTexelOf(b, i, 5)) *
			recordShadowAt(position, b, key, i);
	}
	const surface = srgbToLinear(saturated(surfaceColor.rgb, materialOf(b, key).y));
	return vec4f(linearToSrgb(surface * light), surfaceColor.a);
}

// PENDING3D: material-saturation-only
export function litFs(input: LitFragmentInput, b: LitBindings, key: LitKey): LitOutput {
	const params = materialOf(b, key);
	const n = facingNormal(normalize(input.worldNormal), params.z, input.frontFacing);
	const surfaceColor = tintedSurface(b, key, input.baseColor);
	let shaded = vec4f(0.0);
	if (key.pbr) {
		const pbrValues = pbrOf(b, key).xyz;
		shaded = pbrShade(n, input.worldPosition, input.fragCoord.xy, surfaceColor, b, key,
			pbrValues);
	} else {
		shaded = litShade(n, input.worldPosition, input.fragCoord.xy, surfaceColor, b, key);
	}
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
		if (input.baseColor.a * materialColorOf(b, key).a < materialOf(b, key).w) {
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
	if (key.uvTransform || key.pbr) {
		const time = b.frameParams.frame.x;
		uv = movedUv(input.surfaceUv, uvMatrixOf(b, key), uvMotionOf(b, key), time);
	}
	if (key.normalMap && key.parallax) {
		const view = normalize(b.frameParams.cameraPosition.xyz - input.worldPosition);
		uv = parallaxUv(b, uv, view, normalize(input.worldNormal), input.worldTangent,
			materialOf(b, key).x);
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
	const surfaceColor = tintedSurface(
		b, key, vec4f(input.baseColor.rgb * texel.rgb, input.baseColor.a * texel.a),
	);
	let shaded = vec4f(0.0);
	if (key.pbr) {
		let pbrValues = pbrOf(b, key).xyz;
		if (key.pbrMaps) {
			let occlusionUv = uv;
			if (key.occlusionUvB) {
				occlusionUv = movedUv(input.surfaceUvB, uvMatrixOf(b, key), uvMotionOf(b, key),
					b.frameParams.frame.x);
			}
			pbrValues = pbrMapped(b, key, uv, occlusionUv);
		}
		shaded = pbrShade(n, input.worldPosition, input.fragCoord.xy, surfaceColor, b, key,
			pbrValues);
	} else {
		shaded = litShade(n, input.worldPosition, input.fragCoord.xy, surfaceColor, b, key);
	}
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
		const tint = materialColorOf(b, key);
		if (input.baseColor.a * tint.a * texel.a < materialOf(b, key).w) {
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
