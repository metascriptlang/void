// Port of h3d.mat.Material, reduced to what a fixed sokol-shdc program needs: the program,
// its main pass render state and phase, the textures it samples and its own uniform values.
//
// Uniform values live in the DrawContext's pool (draw.ms), a Vec<float32> allocated once;
// a material holds the block's position in it, so materials stay plain values in a table.

import { RenderState, BlendMode, Face } from "../gpu/state";
import {
	Program,
	ProgramKey,
	MOVING_UV_MATRIX,
	MOVING_BACK_UV_MATRIX,
	UNLIT_MATERIAL_COLOR,
	BACK_VIEW_SLOT,
	DISSOLVE_VIEW_SLOT,
	DISSOLVE_SAMPLER_SLOT,
	EMISSIVE_VIEW_SLOT,
	NORMAL_VIEW_SLOT,
	movingBase,
	uniformBlockLength,
	MATERIAL_UNIFORM_SLOT,
} from "./gpu3d";
import { TextureId, NO_TEXTURE } from "./texture";

// Which of the renderer's pass lists draws the material: the passes h3d.scene.fwd.Renderer
// draws, in this order ("default", "alpha" back to front, "additive").
export enum Phase {
	Opaque,
	Alpha,
	Additive,
}

// h3d.mat.Material's DefaultKind without Hidden.
export enum MaterialKind {
	Opaque,
	Alpha,
	AlphaKill,
	Add,
	SoftAdd,
}

// Whether the shadow pass draws the material (h3d.mat.Material.castShadows), and Only for a
// caster the colour passes leave out (Godot's and Unity's shadows-only casting mode).
export enum ShadowCasting {
	Off,
	On,
	Only,
}

// The faces the shadow pass culls for a material. Main is Heaps' rule, `refreshProps` copying the
// main pass's culling into the "shadow" pass (h3d/mat/Material.hx:283); the others are the
// shadow pass's own culling that Heaps leaves to the caller (`getPass("shadow").culling`) and
// three.js names `Material.shadowSide` (WebGLShadowMap.js:486-490).
export enum ShadowCulling {
	Main,
	None,
	Back,
	Front,
}

// Heaps' Defaults.defaultKillAlphaThreshold, and glTF's alphaCutoff default.
export const DEFAULT_ALPHA_KILL: float32 = 0.5;

// set_blendMode sets blend and depth write for every mode; the rest stays the base's.
export function passFor(kind: MaterialKind, base: RenderState): RenderState {
	const written: RenderState = base.withDepth(true, base.depthTest);
	const unwritten: RenderState = base.withDepth(false, base.depthTest);
	return match (kind) {
		MaterialKind.Opaque => written.withBlendMode(BlendMode.None),
		MaterialKind.AlphaKill => written.withBlendMode(BlendMode.None),
		MaterialKind.Alpha => written.withBlendMode(BlendMode.Alpha),
		MaterialKind.Add => unwritten.withBlendMode(BlendMode.Add),
		MaterialKind.SoftAdd => unwritten.withBlendMode(BlendMode.SoftAdd),
	};
}

export function phaseFor(kind: MaterialKind): Phase {
	return match (kind) {
		MaterialKind.Opaque => Phase.Opaque,
		MaterialKind.AlphaKill => Phase.Opaque,
		MaterialKind.Alpha => Phase.Alpha,
		MaterialKind.Add => Phase.Additive,
		MaterialKind.SoftAdd => Phase.Additive,
	};
}

// The value the material's block holds at MATERIAL_ALPHA_KILL; 0 cuts nothing.
export function alphaKillFor(kind: MaterialKind): float32 {
	return kind == MaterialKind.AlphaKill ? DEFAULT_ALPHA_KILL : 0.0;
}

// A uniform block: `length` floats at `offset` in pool `store`, uploaded to shader slot `slot`,
// held while `generation` is the pool's for that range (uniformPool.ms).
export struct UniformBlock {
	store: int32;
	slot: int32;
	offset: int32;
	length: int32;
	generation: int32;
}

export struct Material {
	program: ProgramKey;
	pass: RenderState;
	phase: Phase;
	// Texture views for view slots 0 to 3 and samplers for sampler slots 0 and 1 (the
	// `binding=` numbers in shader3d.glsl); 0 where the program samples nothing.
	texture0: uint32;
	texture1: uint32;
	texture2: uint32;
	texture3: uint32;
	sampler0: uint32;
	sampler1: uint32;
	// Heaps' `Material.texture`: a context texture, bound at view and sampler 0 in their place.
	texture: TextureId;
	// Context textures of the moving features (M36), as Bevy's StandardMaterial names each map
	// by handle: the back faces' texture at BACK_VIEW_SLOT, read with the base texture's sampler,
	// and the dissolve's noise at DISSOLVE_VIEW_SLOT with its own sampler.
	backTexture: TextureId;
	dissolveTexture: TextureId;
	// M37's maps, read with the base texture's sampler at EMISSIVE_VIEW_SLOT and NORMAL_VIEW_SLOT.
	emissiveTexture: TextureId;
	normalTexture: TextureId;
	uniforms: UniformBlock;
	// h3d.mat.Pass.layer: a list draws lower layers first, before any other order it has.
	layer: int32;
	castShadows: ShadowCasting;
	shadowCulling: ShadowCulling;
}

export const NO_UNIFORMS: UniformBlock = { store: 0, slot: 0, offset: 0, length: 0, generation: 0 };

function cutoutOf(program: Program): ProgramKey {
	return match (program) {
		Program.Lit => ProgramKey.of(program).withCutout(),
		Program.LitTextured => ProgramKey.of(program).withCutout(),
		Program.UnlitTextured => ProgramKey.of(program).withCutout(),
		Program.Billboard => stopOnFixedCut(program),
		Program.Particle => stopOnFixedCut(program),
		Program.Copy => stopOnNoCutout(program),
		Program.Post => stopOnNoCutout(program),
		Program.Blit => stopOnNoCutout(program),
	};
}

// Their blocks hold colour where a material block holds the threshold.
function stopOnFixedCut(program: Program): ProgramKey {
	console.log(`void3d: MaterialKind.AlphaKill for ${program.toString()}, which already cuts at ` +
		"a fixed alpha");
	unreachable;
}

function stopOnNoCutout(program: Program): ProgramKey {
	console.log(`void3d: MaterialKind.AlphaKill for ${program.toString()}, which has no cutout`);
	unreachable;
}

// Material.create's default props cast and receive shadows (`shadows: true`), except
// particles3D's; here every program with a shadow-pass output casts and every lit one receives.
function castsByDefault(program: Program): boolean {
	return program == Program.Lit || program == Program.LitTextured ||
		program == Program.UnlitTextured;
}

// Material.getDefaultProps("particles3D") has `culling: false` beside `shadows: false`
// (h3d/mat/Material.hx:240-246): the quads of a particle or a billboard are seen from either side.
function culledByDefault(program: Program): boolean {
	return program != Program.Billboard && program != Program.Particle;
}

// The caller writes alphaKillFor(kind) into the material block, as every other uniform value.
export function ofKind(this typeof Material, program: Program, kind: MaterialKind): Material {
	const key: ProgramKey =
		kind == MaterialKind.AlphaKill ? cutoutOf(program) : ProgramKey.of(program);
	const lit: boolean = program == Program.Lit || program == Program.LitTextured;
	const faces: RenderState = culledByDefault(program) ?
		RenderState.defaults() : RenderState.defaults().withCulling(Face.None);
	const material: Material = Material.keyed(key, passFor(kind, faces), phaseFor(kind));
	const cast: ShadowCasting = castsByDefault(program) ? ShadowCasting.On : ShadowCasting.Off;
	return material.withShadows(cast, lit);
}

// h3d.mat.Material's castShadows and receiveShadows setters.
export function withShadows(
	this material: Material,
	cast: ShadowCasting,
	receive: boolean,
): Material {
	const key: ProgramKey =
		receive ? material.program.withShadowed() : { ...material.program, shadowed: false };
	return { ...material, program: key, castShadows: cast };
}

export function withShadowCulling(this material: Material, culling: ShadowCulling): Material {
	return { ...material, shadowCulling: culling };
}

// The culling the shadow pass draws the material with.
export function shadowFace(this material: Material): Face {
	return match (material.shadowCulling) {
		ShadowCulling.Main => material.pass.culling,
		ShadowCulling.None => Face.None,
		ShadowCulling.Back => Face.Back,
		ShadowCulling.Front => Face.Front,
	};
}

// A material of the core's `program` with no feature; it samples nothing and has no uniforms of
// its own: add those with spread.
export function plain(
	this typeof Material,
	program: Program,
	pass: RenderState,
	phase: Phase,
): Material {
	return Material.keyed(ProgramKey.of(program), pass, phase);
}

// The same, for any key: a preset's program or one with features.
export function keyed(
	this typeof Material,
	key: ProgramKey,
	pass: RenderState,
	phase: Phase,
): Material {
	return {
		program: key,
		pass: pass,
		phase: phase,
		texture0: 0,
		texture1: 0,
		texture2: 0,
		texture3: 0,
		sampler0: 0,
		sampler1: 0,
		texture: NO_TEXTURE,
		backTexture: NO_TEXTURE,
		dissolveTexture: NO_TEXTURE,
		emissiveTexture: NO_TEXTURE,
		normalTexture: NO_TEXTURE,
		uniforms: NO_UNIFORMS,
		layer: 0,
		castShadows: ShadowCasting.Off,
		shadowCulling: ShadowCulling.Main,
	};
}

export function namesTexture(this material: Material): boolean {
	return material.texture.isTexture();
}

// A material's context textures by role: 0 `texture`, 1 `backTexture`, 2 `dissolveTexture`,
// 3 `emissiveTexture`, 4 `normalTexture`.
export const MATERIAL_TEXTURE_ROLES: int32 = 5;

export function textureOf(this material: Material, role: int32): TextureId {
	if (role == 0) { return material.texture; }
	if (role == 1) { return material.backTexture; }
	if (role == 2) { return material.dissolveTexture; }
	return role == 3 ? material.emissiveTexture : material.normalTexture;
}

export function viewSlotOf(role: int32): int32 {
	if (role == 0) { return 0; }
	if (role == 1) { return BACK_VIEW_SLOT; }
	if (role == 2) { return DISSOLVE_VIEW_SLOT; }
	return role == 3 ? EMISSIVE_VIEW_SLOT : NORMAL_VIEW_SLOT;
}

// The sampler slot a role binds its texture's sampler at; -1 for a role that reads with the base
// texture's.
export function samplerSlotOf(role: int32): int32 {
	if (role == 0) { return 0; }
	return role == 2 ? DISSOLVE_SAMPLER_SLOT : -1;
}

// The roles whose texels are colour, so their alpha must match the program's (M27); the noise
// and the normal map are data.
export function colorRole(role: int32): boolean {
	return role != 2 && role != 4;
}

// The raw view a material binds at `slot` (texture0 to texture3, 0 past them), and its raw
// sampler.
export function rawView(this material: Material, slot: int32): uint32 {
	if (slot > 3) { return 0; }
	if (slot == 0) { return material.texture0; }
	if (slot == 1) { return material.texture1; }
	return slot == 2 ? material.texture2 : material.texture3;
}

export function rawSampler(this material: Material, slot: int32): uint32 {
	return slot == 0 ? material.sampler0 : material.sampler1;
}

// The block of a moving key (gpu3d.ms MOVING_*) with both UV transforms the identity, no scroll,
// no dissolve, an unlit key's colour white, and every other float 0; the caller sets its own
// values over it.
export function movingDefaults(key: ProgramKey): Vec<float32> {
	if (!key.moves()) {
		console.log(`void3d: movingDefaults for ${key.describe()}, which does not move`);
		unreachable;
	}
	let values: Vec<float32> = new Array(uniformBlockLength(key, MATERIAL_UNIFORM_SLOT));
	const base: int32 = movingBase(key);
	if (key.program == Program.UnlitTextured) {
		for (let i = 0; i < 4; i++) { values[UNLIT_MATERIAL_COLOR + i] = 1.0; }
	}
	for (const matrix of [base + MOVING_UV_MATRIX, base + MOVING_BACK_UV_MATRIX]) {
		values[matrix] = 1.0;
		values[matrix + 3] = 1.0;
	}
	return values;
}
