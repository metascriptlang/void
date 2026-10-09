
import {
	uniformBlockBytes as doorUniformBlockBytes,
	textureSlotMask as doorTextureSlotMask,
	samplerSlotMask as doorSamplerSlotMask,
	layoutFloats as doorLayoutFloats,
	layoutPerInstance as doorLayoutPerInstance,
	programLayout as doorProgramLayout,
} from "../gpu/door";
import {
	PipelineCache,
	pipelineFor as pipelineForIds,
} from "../gpu/pipeline";
import { RenderState } from "../gpu/state";
import { TargetLayout } from "../gpu/target";
import {
	gpu3dProgramBase,
	gpu3dLayoutBase,
	gpu3dProgramCount,
	gpu3dProgramKey,
	gpu3dMakeDynamicImage,
	gpu3dMakeStreamBuffer,
	gpu3dDestroyBuffer,
	gpu3dDestroyImage,
	gpu3dApplyPipeline,
	gpu3dDraw,
} from "./gpu3d.h";

// The functions that take arrays are declared here instead: an `extern` Span<T> parameter
// lowers to the (pointer, int64 length) pair gpu3d.h declares. Importing them from the header
// maps the pointer to Borrow<T>, and on msc 0.2.53 `span[0]` passed there is the address of a
// one-element copy (docs/VOID3D.md, Compiler notes).
extern function gpu3dMakeVertexBuffer(data: Readonly<Span<float32>>): uint32;
extern function gpu3dMakeIndexBuffer(data: Readonly<Span<uint16>>): uint32;
extern function gpu3dMakeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32;
extern function gpu3dUpdateImage(image: uint32, rgba: Readonly<Span<uint32>>): void;
extern function gpu3dUpdateBuffer(buffer: uint32, data: Readonly<Span<float32>>): int32;
extern function gpu3dApplyBindings(bindings: Readonly<Span<uint32>>): void;
extern function gpu3dApplyUniforms(slot: int32, data: Readonly<Span<float32>>): void;

let programBase: int32 = gpu3dProgramBase();
let layoutBase: int32 = gpu3dLayoutBase();

// A program's base: what a material names. Its preset and features complete its key.
export enum Program {
	Lit,
	Particle,
	Billboard,
	Copy,
	Post,
	Blit,
	LitTextured,
	UnlitTextured,
	BloomDownsampleFirst,
	BloomDownsample,
	BloomUpsample,
}

// Heaps adds a pass's output shaders to a material's (h3d.pass.Output); sokol-shdc programs
// cannot compose, so a preset is the key's: the pixel-art preset's own source (pixelArt3d.glsl),
// and Shadow, the depth h3d.pass.Shadows writes (dirShadowMap.ms).
export enum Preset {
	Core,
	PixelArt,
	Shadow,
}

// hxsl's constant bits (Shader.hx updateConstantsFinal) and Bevy's MeshPipelineKey: one program
// per value. programKeys.txt declares the values the build ships; regen-shaders.sh compiles them.
export struct ProgramKey {
	program: Program;
	preset: Preset;
	// Texels are premultiplied: unpremultiplied before the decode, the output premultiplied (M27).
	premultiplied: boolean;
	// Discards a pixel whose alpha is below MATERIAL_ALPHA_KILL (M33).
	cutout: boolean;
	shadowed: boolean;
	// Bevy's StandardMaterial.uv_transform, scrolled by Heaps' UVScroll on the frame's time (M36).
	uvTransform: boolean;
	// Back faces sample the texture at view slot BACK_VIEW_SLOT through their own UV transform.
	backTexture: boolean;
	// Discards a pixel whose noise texel (DISSOLVE_VIEW_SLOT) is below the material's threshold,
	// and paints the band just above it in an edge colour.
	dissolve: boolean;
	emissive: boolean;
	normalMap: boolean;
}

const KEY_LIMIT: int32 = 16384;

export function of(this typeof ProgramKey, program: Program): ProgramKey {
	return {
		program: program, preset: Preset.Core, premultiplied: false, cutout: false, shadowed: false,
		uvTransform: false, backTexture: false, dissolve: false, emissive: false, normalMap: false,
	};
}

function stopOnFeature(key: ProgramKey, feature: string): ProgramKey {
	console.log(`void3d: ${key.describe()} has no ${feature} variant`);
	unreachable;
}

export function withPremultiplied(this key: ProgramKey): ProgramKey {
	if (key.program != Program.Billboard) { stopOnUntextured(key, "premultiplied"); }
	return { ...key, premultiplied: true };
}

export function withCutout(this key: ProgramKey): ProgramKey {
	const cuts: boolean = key.program == Program.Lit || key.program == Program.LitTextured ||
		key.program == Program.UnlitTextured || key.program == Program.Billboard;
	if (!cuts) { return stopOnFeature(key, "cutout"); }
	return { ...key, cutout: true };
}

// Heaps' receiveShadows adds its shadow shader to the lit pass.
export function withShadowed(this key: ProgramKey): ProgramKey {
	const lit: boolean = key.program == Program.Lit || key.program == Program.LitTextured;
	if (!lit) { return stopOnFeature(key, "shadowed"); }
	return { ...key, shadowed: true };
}

function stopOnUntextured(key: ProgramKey, feature: string): ProgramKey {
	const textured: boolean =
		key.program == Program.LitTextured || key.program == Program.UnlitTextured;
	if (!textured) { return stopOnFeature(key, feature); }
	return key;
}

export function withUvTransform(this key: ProgramKey): ProgramKey {
	return { ...stopOnUntextured(key, "uv transform"), uvTransform: true };
}

export function withBackTexture(this key: ProgramKey): ProgramKey {
	return { ...stopOnUntextured(key, "back texture"), backTexture: true };
}

export function withDissolve(this key: ProgramKey): ProgramKey {
	return { ...stopOnUntextured(key, "dissolve"), dissolve: true };
}

function stopOnNotLitTextured(key: ProgramKey, feature: string): ProgramKey {
	if (key.program != Program.LitTextured) { return stopOnFeature(key, feature); }
	return key;
}

export function withEmissive(this key: ProgramKey): ProgramKey {
	return { ...stopOnNotLitTextured(key, "emissive"), emissive: true };
}

export function withNormalMap(this key: ProgramKey): ProgramKey {
	return { ...stopOnNotLitTextured(key, "normal map"), normalMap: true };
}

// Any of the three reads the moving material block (MOVING_* below).
export function moves(this key: ProgramKey): boolean {
	return key.uvTransform || key.backTexture || key.dissolve;
}

export function withPreset(this key: ProgramKey, preset: Preset): ProgramKey {
	return { ...key, preset: preset };
}

// GPU3D_PROGRAM_KEY in gpu3d.c packs the same bits.
export function bits(this key: ProgramKey): int32 {
	return (key.program as int32) | ((key.preset as int32) << 4) |
		((key.premultiplied ? 1 : 0) << 6) | ((key.cutout ? 1 : 0) << 7) |
		((key.shadowed ? 1 : 0) << 8) | ((key.uvTransform ? 1 : 0) << 9) |
		((key.backTexture ? 1 : 0) << 10) | ((key.dissolve ? 1 : 0) << 11) |
		((key.emissive ? 1 : 0) << 12) | ((key.normalMap ? 1 : 0) << 13);
}

export function describe(this key: ProgramKey): string {
	const premultiplied: string = key.premultiplied ? " premultiplied" : "";
	const cutout: string = key.cutout ? " cutout" : "";
	const shadowed: string = key.shadowed ? " shadowed" : "";
	const uv: string = key.uvTransform ? " uv-transform" : "";
	const back: string = key.backTexture ? " back-texture" : "";
	const dissolve: string = key.dissolve ? " dissolve" : "";
	const emissive: string = key.emissive ? " emissive" : "";
	const normalMap: string = key.normalMap ? " normal-map" : "";
	const features: string =
		`${premultiplied}${cutout}${shadowed}${uv}${back}${dissolve}${emissive}${normalMap}`;
	return `${key.preset.toString()} ${key.program.toString()}${features}`;
}

function stopOnTable(message: string): Vec<int32> {
	console.log(`void3d: programTable.h ${message}`);
	unreachable;
}

function indexPrograms(): Vec<int32> {
	let index: Vec<int32> = [];
	for (let bits = 0; bits < KEY_LIMIT; bits++) { index.push(-1); }
	for (let i = 0; i < gpu3dProgramCount(); i++) {
		const bits: int32 = gpu3dProgramKey(i);
		if (bits < 0 || bits >= KEY_LIMIT) { return stopOnTable(`declares key ${bits}`); }
		if (index[bits] >= 0) { return stopOnTable(`declares key ${bits} twice`); }
		index[bits] = i;
	}
	return index;
}

let programIndex: Vec<int32> = indexPrograms();

export function declares(key: ProgramKey): boolean {
	return programIndex[key.bits()] >= 0;
}

function stopOnUndeclared(key: ProgramKey): int32 {
	console.log(`void3d: no program declared for ${key.describe()} (src/void3d/programKeys.txt)`);
	unreachable;
}

// The door id of one of void3d's programs / layouts.
export function doorProgram(key: ProgramKey): int32 {
	if (!declares(key)) { return stopOnUndeclared(key); }
	return programBase + programIndex[key.bits()];
}

export function doorLayout(layout: VertexLayout): int32 {
	return layoutBase + (layout as int32);
}

export enum ProgramError {
	NotDrawn,
	BlockShort,
}

// Drawn only by drawScreen, through its own material, over a whole target.
export function isScreenProgram(program: Program): boolean {
	return match (program) {
		Program.Lit => false,
		Program.Particle => false,
		Program.Billboard => false,
		Program.Copy => true,
		Program.Post => true,
		Program.Blit => true,
		Program.LitTextured => false,
		Program.UnlitTextured => false,
		Program.BloomDownsampleFirst => true,
		Program.BloomDownsample => true,
		Program.BloomUpsample => true,
	};
}

// What a renderer of `preset` draws for a material's key: the same key in its preset, when the
// build declares it. A material names the core's scene programs; a screen program is drawn only
// by drawScreen, through its own material. With no shadow map in the frame a receiver draws
// unshadowed, as DirShadow's `enable` constant compiles the sampling away.
export function drawnIn(
	key: ProgramKey,
	preset: Preset,
	shadowMap: boolean,
): Result<ProgramKey, ProgramError> {
	const screen: boolean = isScreenProgram(key.program);
	if (screen || key.preset != Preset.Core || preset == Preset.Shadow) {
		return Result.err(ProgramError.NotDrawn);
	}
	const drawn: ProgramKey = { ...key.withPreset(preset), shadowed: key.shadowed && shadowMap };
	if (!declares(drawn)) { return Result.err(ProgramError.NotDrawn); }
	return Result.ok(drawn);
}

// Depth output has no colour, so premultiplied input and shadow receiving do not reach it; a
// dissolve cuts depth as it cuts colour. A cut reads its texel at the UV the colour program
// reads it at, so a cutout keeps its UV features; no such caster is declared, so a cutout that
// moves its UV is refused as not cast rather than cut at the wrong texel.
export function castIn(key: ProgramKey): Result<ProgramKey, ProgramError> {
	if (key.preset != Preset.Core) { return Result.err(ProgramError.NotDrawn); }
	const cast: ProgramKey = {
		...key.withPreset(Preset.Shadow), premultiplied: false, shadowed: false,
		uvTransform: key.uvTransform && key.cutout, backTexture: key.backTexture && key.cutout,
		emissive: false,
	};
	if (!declares(cast)) { return Result.err(ProgramError.NotDrawn); }
	return Result.ok(cast);
}

// Vertex buffer layouts gpu3d.c describes (describeLayout).
export enum VertexLayout {
	Lit,
	Particle,
	Billboard,
	Fullscreen,
	LitTextured,
	LitTexturedTangent,
}

export function vertexLayoutOf(program: ProgramKey): VertexLayout {
	return (doorProgramLayout(doorProgram(program)) - layoutBase) as VertexLayout;
}

export function drawsQuads(layout: VertexLayout): boolean {
	return match (layout) {
		VertexLayout.Lit => false,
		VertexLayout.Particle => true,
		VertexLayout.Billboard => true,
		VertexLayout.Fullscreen => false,
		VertexLayout.LitTextured => false,
		VertexLayout.LitTexturedTangent => false,
	};
}

// Uniform block slots and sizes in floats, from the `binding=` blocks in shader3dBlocks.glsl.
export const VERTEX_UNIFORM_SLOT: int32 = 0;
export const VERTEX_UNIFORM_LENGTH: int32 = 24;
export const LIGHT_UNIFORM_SLOT: int32 = 1;
// ambient (rgb + point count), dirLight (direction + power), dirColor, then pointLight[4]
// (position + power) and pointColor[4] (rgb + radius): two vec4 arrays of one vec4 per light,
// packoffset(c3) and packoffset(c7) in the HLSL, so four floats per light in each.
export const MAX_POINT_LIGHTS: int32 = 4;
export const LIGHT_UNIFORM_LENGTH: int32 = 12 + 2 * MAX_POINT_LIGHTS * 4;
// The scene's shadow block (binding=5, shader3dBlocks.glsl dirShadow): the world-to-map
// matrix, then the bias and the opacity.
export const SHADOW_UNIFORM_SLOT: int32 = 5;
export const SHADOW_UNIFORM_LENGTH: int32 = 20;
export const SHADOW_BIAS: int32 = 16;
export const SHADOW_OPACITY: int32 = 17;
// The shadow map's view and sampler slots (dirShadow's `binding=`), past a material's.
export const SHADOW_VIEW_SLOT: int32 = 4;
export const SHADOW_SAMPLER_SLOT: int32 = 2;
// A lit material's own block (binding=3). The core reads the saturation it applies to the
// material's colour before lighting (0 leaves it alone, -1 is grey) and, at 1 in
// MATERIAL_DOUBLE_SIDED, lights a back face through its reversed normal, and discards a pixel
// whose alpha is below MATERIAL_ALPHA_KILL (material.ms MaterialKind.AlphaKill); a preset may
// give the other floats a meaning of its own (pixelArtRenderer.ms RAMP_LEVELS).
export const MATERIAL_UNIFORM_SLOT: int32 = 3;
export const MATERIAL_UNIFORM_LENGTH: int32 = 4;
export const MATERIAL_SATURATION: int32 = 1;
export const MATERIAL_DOUBLE_SIDED: int32 = 2;
export const MATERIAL_ALPHA_KILL: int32 = 3;
export const UNLIT_MATERIAL_UNIFORM_LENGTH: int32 = 8;
export const UNLIT_MATERIAL_COLOR: int32 = 4;
// A moving key's block (movingMaterialParams / movingUnlitMaterialParams in shader3dBlocks.glsl):
// its program's block, then six vec4 at movingBase(key) plus these offsets, whichever of the
// three features the key reads. UV transform: Bevy's Affine2, the 2x2 matrix by columns, then
// the translation and Heaps' UVScroll speed in UV units per second of the frame's time.
export const MOVING_UV_MATRIX: int32 = 0;
export const MOVING_UV_OFFSET: int32 = 4;
export const MOVING_UV_SCROLL: int32 = 6;
// The back face's own UV transform, unscrolled: matrix by columns, then translation.
export const MOVING_BACK_UV_MATRIX: int32 = 8;
export const MOVING_BACK_UV_OFFSET: int32 = 12;
// Dissolve: the threshold (0 dissolves nothing, past 1 everything) and the edge band's width in
// noise units, then the edge colour (gamma-encoded rgb; its alpha mixes it over the shaded colour).
export const MOVING_DISSOLVE_THRESHOLD: int32 = 16;
export const MOVING_DISSOLVE_EDGE_WIDTH: int32 = 17;
export const MOVING_DISSOLVE_EDGE_COLOR: int32 = 20;
export const MOVING_LENGTH: int32 = 24;
export const MOVING_MATERIAL_UNIFORM_LENGTH: int32 = MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH;
export const MOVING_UNLIT_MATERIAL_UNIFORM_LENGTH: int32 =
	UNLIT_MATERIAL_UNIFORM_LENGTH + MOVING_LENGTH;
// The back texture shares the base texture's sampler; the noise has a sampler of its own.
export const BACK_VIEW_SLOT: int32 = 1;
export const DISSOLVE_VIEW_SLOT: int32 = 2;
export const DISSOLVE_SAMPLER_SLOT: int32 = 1;
export const EMISSIVE_VIEW_SLOT: int32 = 3;
export const NORMAL_VIEW_SLOT: int32 = 5;
// An emissive key's block ends in one vec4: the emitted colour, gamma-encoded, and at
// EMISSIVE_STRENGTH the factor it is scaled by in linear light (KHR_materials_emissive_strength).
export const EMISSIVE_COLOR: int32 = 0;
export const EMISSIVE_STRENGTH: int32 = 3;
export const EMISSIVE_LENGTH: int32 = 4;
// The scene's frame block (binding=6, shader3dBlocks.glsl frameUniforms): Heaps' `global.time`
// in seconds at FRAME_TIME, read by a key with a UV transform, and at FRAME_EXPOSURE the linear
// multiplier every scene program's colour is exposed by (toneMap); at FRAME_LINEAR 1 when the pass
// draws into an HDR target, where every scene program writes its colour linear and unexposed; at
// FRAME_TONE_MODE the curve (renderer.ms ToneMode) the exposed colour goes through.
export const FRAME_UNIFORM_SLOT: int32 = 6;
export const FRAME_UNIFORM_LENGTH: int32 = 4;
export const FRAME_TIME: int32 = 0;
export const FRAME_EXPOSURE: int32 = 1;
export const FRAME_LINEAR: int32 = 2;
export const FRAME_TONE_MODE: int32 = 3;

// Where a moving key's own floats start in its material block.
export function movingBase(key: ProgramKey): int32 {
	return key.program == Program.UnlitTextured ?
		UNLIT_MATERIAL_UNIFORM_LENGTH : MATERIAL_UNIFORM_LENGTH;
}
export function emissiveBase(key: ProgramKey): int32 {
	return movingBase(key) + (key.moves() ? MOVING_LENGTH : 0);
}

// A billboard material's block (binding=2): its colour, then at BILLBOARD_LIGHT 0 to leave the
// lights out (Heaps' `particles3D` material has `light: true`). A preset may give the other
// floats a meaning of its own (pixelArtRenderer.ms BILLBOARD_RAMP_LEVELS).
export const BILLBOARD_UNIFORM_SLOT: int32 = 2;
export const BILLBOARD_UNIFORM_LENGTH: int32 = 8;
export const BILLBOARD_COLOR: int32 = 0;
export const BILLBOARD_LIGHT: int32 = 5;

// Floats of the block `program` declares at `slot`, 0 for none, read off its shader desc.
export function uniformBlockLength(program: ProgramKey, slot: int32): int32 {
	return doorUniformBlockBytes(doorProgram(program), slot) / 4;
}

// Bit n set when `program` samples a texture at view slot n (textureSlotMask) or declares
// sampler slot n (samplerSlotMask), read off its shader desc.
export function textureSlotMask(program: ProgramKey): uint32 {
	return doorTextureSlotMask(doorProgram(program));
}

export function samplerSlotMask(program: ProgramKey): uint32 {
	return doorSamplerSlotMask(doorProgram(program));
}

// Floats per element of vertex buffer `buffer` of `layout`, as gpu3d.c registered it.
export function layoutFloats(layout: VertexLayout, buffer: int32): int32 {
	return doorLayoutFloats(doorLayout(layout), buffer);
}

export function layoutPerInstance(layout: VertexLayout): boolean {
	return doorLayoutPerInstance(doorLayout(layout));
}

// PipelineBuilder.lookup, on void3d's own enums: the key and the cache are the door's.
export function pipelineFor(
	cache: PipelineCache,
	program: ProgramKey,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): uint32 {
	return pipelineForIds(
		cache,
		doorProgram(program),
		doorLayout(layout),
		indexed,
		state,
		targets,
	);
}


export function makeVertexBuffer(data: Readonly<Span<float32>>): uint32 {
	return gpu3dMakeVertexBuffer(data);
}

// Three uint16 per triangle. sokol copies the data, so the Vec it came from may move after.
export function makeIndexBuffer(data: Readonly<Span<uint16>>): uint32 {
	return gpu3dMakeIndexBuffer(data);
}

export function makeImage(rgba: Readonly<Span<uint32>>, width: int32, height: int32): uint32 {
	return gpu3dMakeImage(rgba, width, height);
}

// An RGBA8 image the CPU rewrites with updateImage; its pixels start undefined.
export function makeDynamicImage(width: int32, height: int32): uint32 {
	return gpu3dMakeDynamicImage(width, height);
}

// sokol allows one update per image per frame, before any pass samples it.
export function updateImage(image: uint32, rgba: Readonly<Span<uint32>>): void {
	gpu3dUpdateImage(image, rgba);
}

export function makeStreamBuffer(length: int32): uint32 {
	return gpu3dMakeStreamBuffer(length as int64);
}

// sokol takes one update per buffer per frame, before the pass that draws it.
export function updateBuffer(buffer: uint32, data: Readonly<Span<float32>>): boolean {
	return gpu3dUpdateBuffer(buffer, data) != 0;
}


export function destroyBuffer(buffer: uint32): void { gpu3dDestroyBuffer(buffer); }
export function destroyImage(image: uint32): void { gpu3dDestroyImage(image); }

export function applyPipeline(pipeline: uint32): void { gpu3dApplyPipeline(pipeline); }

export function applyBindings(bindings: Readonly<Span<uint32>>): void {
	gpu3dApplyBindings(bindings);
}

export function applyUniforms(slot: int32, data: Readonly<Span<float32>>): void {
	gpu3dApplyUniforms(slot, data);
}

export function draw(base: int32, count: int32, instances: int32): void {
	gpu3dDraw(base, count, instances);
}
