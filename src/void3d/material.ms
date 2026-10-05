// Port of h3d.mat.Material, reduced to what a fixed sokol-shdc program needs: the program,
// its main pass render state and phase, the textures it samples and its own uniform values.
//
// Uniform values live in the DrawContext's pool (draw.ms), a Vec<float32> allocated once;
// a material holds the block's position in it, so materials stay plain values in a table.

import { RenderState, BlendMode } from "../gpu/state";
import { Program } from "./gpu3d";
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
	program: Program;
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
	uniforms: UniformBlock;
}

export const NO_UNIFORMS: UniformBlock = { store: 0, slot: 0, offset: 0, length: 0, generation: 0 };

export function cutoutOf(program: Program): Program {
	return match (program) {
		Program.Lit => Program.LitCutout,
		Program.LitTextured => Program.LitTexturedCutout,
		Program.UnlitTextured => Program.UnlitTexturedCutout,
		Program.Billboard => stopOnFixedCut(program),
		Program.Particle => stopOnFixedCut(program),
		Program.LitCutout => Program.LitCutout,
		Program.LitTexturedCutout => Program.LitTexturedCutout,
		Program.UnlitTexturedCutout => Program.UnlitTexturedCutout,
		Program.Copy => stopOnNoCutout(program),
		Program.PixelArtLit => stopOnNoCutout(program),
		Program.PixelArtParticle => stopOnNoCutout(program),
		Program.PixelArtBillboard => stopOnNoCutout(program),
		Program.PixelArtPost => stopOnNoCutout(program),
		Program.PixelArtBlit => stopOnNoCutout(program),
		Program.PixelArtLitTextured => stopOnNoCutout(program),
		Program.PixelArtUnlitTextured => stopOnNoCutout(program),
		Program.LitTexturedPremultiplied => stopOnNoCutout(program),
		Program.PixelArtLitTexturedPremultiplied => stopOnNoCutout(program),
		Program.UnlitTexturedPremultiplied => stopOnNoCutout(program),
		Program.PixelArtUnlitTexturedPremultiplied => stopOnNoCutout(program),
		Program.PixelArtLitCutout => stopOnNoCutout(program),
		Program.PixelArtLitTexturedCutout => stopOnNoCutout(program),
		Program.PixelArtUnlitTexturedCutout => stopOnNoCutout(program),
	};
}

// Their blocks hold colour where a material block holds the threshold.
function stopOnFixedCut(program: Program): Program {
	console.log(`void3d: MaterialKind.AlphaKill for ${program.toString()}, which already cuts at ` +
		"a fixed alpha");
	unreachable;
}

function stopOnNoCutout(program: Program): Program {
	console.log(`void3d: MaterialKind.AlphaKill for ${program.toString()}, which has no cutout`);
	unreachable;
}

// The caller writes alphaKillFor(kind) into the material block, as every other uniform value.
export function ofKind(this typeof Material, program: Program, kind: MaterialKind): Material {
	const drawn: Program = kind == MaterialKind.AlphaKill ? cutoutOf(program) : program;
	return Material.plain(drawn, passFor(kind, RenderState.defaults()), phaseFor(kind));
}

// A material that samples nothing and has no uniforms of its own; add those with spread.
export function plain(
	this typeof Material,
	program: Program,
	pass: RenderState,
	phase: Phase,
): Material {
	return {
		program: program,
		pass: pass,
		phase: phase,
		texture0: 0,
		texture1: 0,
		texture2: 0,
		texture3: 0,
		sampler0: 0,
		sampler1: 0,
		texture: NO_TEXTURE,
		uniforms: NO_UNIFORMS,
	};
}

export function namesTexture(this material: Material): boolean {
	return material.texture.isTexture();
}
