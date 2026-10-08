// h3d.scene.pbr.Renderer's HDR target and its ToneMapping ScreenFx, for a preset that opts in:
// the scene draws into `target` (Rgba16f, linear, unclamped) and `draw` exposes it, puts it
// through the core's curve and encodes it into the preset's Rgba8 colour target.

import { Vec4, srgbToLinear } from "../math/math3d";
import { Program, ProgramKey } from "./gpu3d";
import { PixelFormat, endPass } from "../gpu/door";
import { Material, Phase, UniformBlock } from "./material";
import { RenderTarget, ColorAttachment, TargetLayout, NO_DEPTH, beginPass } from "../gpu/target";
import {
	DrawContext,
	MaterialId,
	MaterialError,
	HandleError,
	addMaterial,
	releaseMaterial,
	reserveUniforms,
	writeUniforms,
} from "./draw";
import { UniformError } from "./uniformPool";
import { screenState } from "./screenFx";
import { Renderer, RendererError, drawScreen, exposureMultiplier } from "./renderer";

// The tone map's block (shader3d.glsl toneMapFs `toneMapParams`): the exposure multiplier, then
// the curve.
export const TONE_MAP_UNIFORM_SLOT: int32 = 0;
export const TONE_MAP_UNIFORM_LENGTH: int32 = 4;
export const TONE_MAP_EXPOSURE: int32 = 0;
export const TONE_MAP_MODE: int32 = 1;

// The tone map pass: into an Rgba8 colour target, no depth.
export const TONE_MAP_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

// The background as the HDR target holds it: linear, the alpha as is.
export function linearBackground(background: Vec4): Vec4 {
	return {
		x: srgbToLinear(background.x),
		y: srgbToLinear(background.y),
		z: srgbToLinear(background.z),
		w: background.w,
	};
}

export interface ToneMapPass {
	target: RenderTarget;
	block: UniformBlock;
	material: MaterialId;
	values: Vec<float32>;
}

// Reserves the block and adds the material to `context`, whose pool the caller checked fits
// TONE_MAP_UNIFORM_LENGTH. No GPU object is made here: `target` is allocated by its owner's resize.
export function reserve(this typeof ToneMapPass, context: DrawContext): ToneMapPass {
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, TONE_MAP_UNIFORM_SLOT, TONE_MAP_UNIFORM_LENGTH);
	if (!reserved.ok) {
		console.log("void3d: ToneMapPass.reserve found no room for its checked block");
		unreachable;
	}
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(ProgramKey.of(Program.Post), screenState(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (!added.ok) { unreachable; }
	return {
		target: RenderTarget.unallocated(PixelFormat.Rgba16f, true),
		block: reserved.value,
		material: added.value,
		values: new Array(TONE_MAP_UNIFORM_LENGTH),
	};
}

// Binds `target` and `sampler` to the material and writes the core's exposure and curve; the
// caller checked the material still holds its texture and block.
export function prepare(this pass: ToneMapPass, core: Renderer, sampler: uint32): void {
	const context: DrawContext = core.context;
	context.materials[pass.material.index].texture0 = pass.target.asTexture();
	context.materials[pass.material.index].sampler0 = sampler;
	pass.values[TONE_MAP_EXPOSURE] = exposureMultiplier(core.exposure);
	pass.values[TONE_MAP_MODE] = core.toneMode as float32;
	const written: Result<int32, UniformError> = writeUniforms(context, pass.block, pass.values);
	if (!written.ok) { unreachable; }
}

// One pass over `colors`, an Rgba8 target of `target`'s size.
export function draw(this pass: ToneMapPass, core: Renderer, colors: Vec<ColorAttachment>): void {
	beginPass(colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> = drawScreen(core, pass.material, TONE_MAP_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: ToneMapPass, context: DrawContext, call: string): void {
	pass.target.close();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found its tone map material ${released.error.toString()}`);
		unreachable;
	}
}
