// h3d.scene.pbr.Renderer's HDR target and its ToneMapping ScreenFx, for a preset that opts in:
// the scene draws into `target` (Rgba16f, linear, unclamped) and `draw` exposes it, puts it
// through the core's curve and encodes it into the preset's Rgba8 colour target.

import { Vec4, srgbToLinear, linearToSrgb } from "../math/math3d";
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
import { BloomPass, BLOOM_UNIFORM_LENGTH, BLOOM_PASS_UNIFORM_LENGTH } from "./bloom";
import { screenState } from "./screenFx";
import { Renderer, RendererError, ToneMode, drawScreen, exposureMultiplier } from "./renderer";

// The tone map's block (shader3d.glsl toneMapFs `toneMapParams`): the exposure multiplier, then
// the curve.
export const TONE_MAP_UNIFORM_SLOT: int32 = 0;
export const TONE_MAP_UNIFORM_LENGTH: int32 = 4;
export const TONE_MAP_EXPOSURE: int32 = 0;
export const TONE_MAP_MODE: int32 = 1;

// The blocks a ToneMapPass reserves, its own and its bloom's, and their floats.
export const TONE_MAP_PASS_BLOCKS: Vec<int32> = [
	TONE_MAP_UNIFORM_LENGTH, BLOOM_UNIFORM_LENGTH, BLOOM_UNIFORM_LENGTH, BLOOM_UNIFORM_LENGTH,
];
export const TONE_MAP_PASS_UNIFORM_LENGTH: int32 =
	TONE_MAP_UNIFORM_LENGTH + BLOOM_PASS_UNIFORM_LENGTH;

// The tone map pass: into an Rgba8 colour target, no depth.
export const TONE_MAP_LAYOUT: TargetLayout = {
	color0: PixelFormat.Rgba8,
	color1: PixelFormat.None,
	color2: PixelFormat.None,
	color3: PixelFormat.None,
	depth: PixelFormat.None,
	sampleCount: 1,
};

// A background is premultiplied by its alpha, as a blend over a transparent clear stores colour
// (M40). As the HDR target holds it: the straight colour decoded, premultiplied again.
export function linearBackground(background: Vec4): Vec4 {
	const alpha: float32 = unit(background.w);
	if (alpha <= 0.0) { return { x: 0.0, y: 0.0, z: 0.0, w: background.w }; }
	return {
		x: srgbToLinear(background.x / alpha) * alpha,
		y: srgbToLinear(background.y / alpha) * alpha,
		z: srgbToLinear(background.z / alpha) * alpha,
		w: background.w,
	};
}

// The background an LDR preset clears to: what toneMapFs makes of the same clear in an HDR
// preset, so both presets show one background. Exposure 0 and the linear curve leave it as it is.
export function toneMappedBackground(background: Vec4, multiplier: float32, mode: ToneMode): Vec4 {
	if (multiplier == 1.0 && mode == ToneMode.Linear) { return background; }
	const alpha: float32 = unit(background.w);
	if (alpha <= 0.0) { return { x: 0.0, y: 0.0, z: 0.0, w: background.w }; }
	const exposed: Vec4 = {
		x: srgbToLinear(background.x / alpha) * multiplier,
		y: srgbToLinear(background.y / alpha) * multiplier,
		z: srgbToLinear(background.z / alpha) * multiplier,
		w: alpha,
	};
	const curved: Vec4 = toneCurved(exposed, mode);
	return {
		x: linearToSrgb(curved.x) * alpha,
		y: linearToSrgb(curved.y) * alpha,
		z: linearToSrgb(curved.z) * alpha,
		w: background.w,
	};
}

// shader3dBlocks.glsl toneCurve on the CPU, line for line: an exposed linear colour through
// h3d.shader.pbr.ToneMapping's `mode`, the alpha untouched.
export function toneCurved(color: Vec4, mode: ToneMode): Vec4 {
	return match (mode) {
		ToneMode.Linear => saturated(color),
		ToneMode.Reinhard => reinhard(color),
		ToneMode.Filmic => filmicColor(color),
		ToneMode.Neutral => neutral(color),
	};
}

function saturated(color: Vec4): Vec4 {
	return { x: unit(color.x), y: unit(color.y), z: unit(color.z), w: color.w };
}

function reinhard(color: Vec4): Vec4 {
	return {
		x: color.x / (color.x + 1.0),
		y: color.y / (color.y + 1.0),
		z: color.z / (color.z + 1.0),
		w: color.w,
	};
}

function filmicColor(color: Vec4): Vec4 {
	return { x: filmic(color.x), y: filmic(color.y), z: filmic(color.z), w: color.w };
}

function unit(value: float32): float32 {
	if (value < 0.0) { return 0.0; }
	if (value > 1.0) { return 1.0; }
	return value;
}

function filmic(c: float32): float32 {
	return unit((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14));
}

function neutral(color: Vec4): Vec4 {
	const startCompression: float32 = 0.8 - 0.04;
	const desaturation: float32 = 0.15;
	const x: float32 = Math.min(color.x, Math.min(color.y, color.z)) as float32;
	const offset: float32 = x < 0.08 ? x - 6.25 * x * x : 0.04;
	let r: float32 = color.x - offset;
	let g: float32 = color.y - offset;
	let b: float32 = color.z - offset;
	const peak: float32 = Math.max(r, Math.max(g, b)) as float32;
	if (peak >= startCompression) {
		const d: float32 = 1.0 - startCompression;
		const newPeak: float32 = 1.0 - d * d / (peak + d - startCompression);
		const scale: float32 = newPeak / peak;
		r = r * scale;
		g = g * scale;
		b = b * scale;
		const mixed: float32 = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
		r = r + (newPeak - r) * mixed;
		g = g + (newPeak - g) * mixed;
		b = b + (newPeak - b) * mixed;
	}
	return { x: r, y: g, z: b, w: color.w };
}

export interface ToneMapPass {
	target: RenderTarget;
	block: UniformBlock;
	material: MaterialId;
	values: Vec<float32>;
	// Off until the preset's setBloom; runs on `target` before the tone map.
	bloom: BloomPass;
}

// Reserves the blocks and adds the materials to `context`, whose pool the caller checked fits
// TONE_MAP_PASS_BLOCKS. No GPU object is made here: `target` is allocated by its owner's resize.
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
		bloom: BloomPass.reserve(context),
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
	pass.bloom.resize(pass.target.width, pass.target.height);
}

// The bloom chain on `target` when it is on, then one pass over `colors`, an Rgba8 target of
// `target`'s size.
export function draw(this pass: ToneMapPass, core: Renderer, colors: Vec<ColorAttachment>): void {
	pass.bloom.draw(core, pass.target);
	beginPass(colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> = drawScreen(core, pass.material, TONE_MAP_LAYOUT);
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: ToneMapPass, context: DrawContext, call: string): void {
	pass.bloom.close(context, call);
	pass.target.close();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found its tone map material ${released.error.toString()}`);
		unreachable;
	}
}
