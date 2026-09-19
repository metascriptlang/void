// Port of h3d.mat.Material, reduced to what a fixed sokol-shdc program needs: the program,
// its main pass render state, the textures it samples and its own uniform values.
//
// Uniform values live in the DrawContext's pool (draw.ms), a Vec<float32> allocated once;
// a material holds the block's position in it, so materials stay plain values in a table.

import { RenderState } from "./pass";
import { Program } from "./gpu3d";

// A uniform block: `length` floats at `offset` in the pool, uploaded to shader slot `slot`.
export struct UniformBlock {
	slot: int32;
	offset: int32;
	length: int32;
}

export struct Material {
	program: Program;
	pass: RenderState;
	// Texture views and sampler for view slots 0 and 1 and sampler slot 0 (the `binding=`
	// numbers in shader3d.glsl); 0 when the program samples nothing there.
	texture0: uint32;
	texture1: uint32;
	sampler: uint32;
	uniforms: UniformBlock;
}

export const NO_UNIFORMS: UniformBlock = { slot: 0, offset: 0, length: 0 };
