// Port of h3d.mat.Material, reduced to what a fixed sokol-shdc program needs: the program,
// its main pass render state and phase, the textures it samples and its own uniform values.
//
// Uniform values live in the DrawContext's pool (draw.ms), a Vec<float32> allocated once;
// a material holds the block's position in it, so materials stay plain values in a table.

import { RenderState } from "./pass";
import { Program } from "./gpu3d";

// Which of the renderer's pass lists draws the material: the passes h3d.scene.fwd.Renderer
// draws, in this order ("default", "alpha" back to front, "additive").
export enum Phase {
	Opaque,
	Alpha,
	Additive,
}

// A uniform block: `length` floats at `offset` in the pool, uploaded to shader slot `slot`.
export struct UniformBlock {
	slot: int32;
	offset: int32;
	length: int32;
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
	uniforms: UniformBlock;
}

export const NO_UNIFORMS: UniformBlock = { slot: 0, offset: 0, length: 0 };

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
		uniforms: NO_UNIFORMS,
	};
}
