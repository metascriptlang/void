// Heaps' h3d.pass.ColorMatrix: post3d.ms colorMatrixFs drawn from a texture into a target of its
// size, optionally weighted by a mask texture. The material ColorMatrix (h3d.shader.ColorMatrix)
// is materialColorMatrixRaw's, which no program draws yet.

import { Program, ProgramKey } from "./gpu3d";
import { LoadAction, endPass } from "../gpu/door";
import { FilterMode, Wrap } from "../gpu/state";
import {
	RenderTarget,
	ColorAttachment,
	Sampler,
	NO_DEPTH,
	beginPass,
	layoutOf,
} from "../gpu/target";
import { Material, Phase, UniformBlock } from "./material";
import { Mat4, Vec3, Vec4, vec4, identity } from "../math/math3d";
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
import { Renderer, RendererError, drawScreen } from "./renderer";

export enum ColorMatrixError {
	NonFinite,
	UndefinedMaskPower,
}

// The colour matrix program's block (post3d.ms ColorMatrixParams) at the screen slot: the matrix,
// the second matrix, the mask's two UV rows with its power in the first's w, the mask's channel
// weights, then useAlpha, useMask, maskInvert and hasSecondMatrix as 0 or 1.
export const COLOR_MATRIX_UNIFORM_SLOT: int32 = 0;
export const COLOR_MATRIX: int32 = 0;
export const COLOR_MATRIX_SECOND: int32 = 16;
export const COLOR_MATRIX_MASK_A: int32 = 32;
export const COLOR_MATRIX_MASK_B: int32 = 36;
export const COLOR_MATRIX_MASK_CHANNEL: int32 = 40;
export const COLOR_MATRIX_FLAGS: int32 = 44;
export const COLOR_MATRIX_UNIFORM_LENGTH: int32 = 48;

// ColorMatrix.apply's mask: its UV rows from `maskMatrix` (identity when none), the shader's
// maskChannel and maskPower, which `new ColorMatrix` sets to red and 1, and maskInvert.
export struct ColorMatrixMask {
	matA: Vec3;
	matB: Vec3;
	channel: Vec4;
	power: float32;
	invert: boolean;
}

export struct ColorMatrixSettings {
	matrix: Mat4;
	useAlpha: boolean;
	secondMatrix: Mat4 | null;
}

export function create(this typeof ColorMatrixSettings): ColorMatrixSettings {
	return { matrix: identity(), useAlpha: false, secondMatrix: null };
}

export function create(this typeof ColorMatrixMask): ColorMatrixMask {
	return {
		matA: { x: 1.0, y: 0.0, z: 0.0 },
		matB: { x: 0.0, y: 1.0, z: 0.0 },
		channel: vec4(1.0, 0.0, 0.0, 0.0),
		power: 1.0,
		invert: false,
	};
}

// h3d.shader.ColorMatrix on one colour: the matrix on the opaque rgb, its alpha from the whole
// colour.
export function materialColorMatrixRaw(
	color: Vec4,
	matrix: Mat4,
	enabled: boolean = true,
): Result<Vec4, ColorMatrixError> {
	if (!finiteColor(color)) { return Result.err(ColorMatrixError.NonFinite); }
	if (!enabled) { return Result.ok(color); }
	if (!finiteMatrix(matrix)) { return Result.err(ColorMatrixError.NonFinite); }
	const rgb: Vec4 = vec4(color.x, color.y, color.z, 1.0) * matrix;
	const rgba: Vec4 = color * matrix;
	return checkedColor(vec4(rgb.x, rgb.y, rgb.z, rgba.w));
}

// Finite matrices and mask, and a mask power above 0: the shader raises a weight a mask texel
// can make 0, which pow leaves undefined at a power of 0 or below.
export function validate(
	this settings: ColorMatrixSettings,
	mask: ColorMatrixMask | null,
): Result<void, ColorMatrixError> {
	if (!finiteMatrix(settings.matrix)) { return Result.err(ColorMatrixError.NonFinite); }
	const second = settings.secondMatrix;
	if (second !== null && !finiteMatrix(second)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	if (mask === null) { return Result.ok(null); }
	if (!finiteVector(mask.matA) || !finiteVector(mask.matB) || !finiteColor(mask.channel) ||
		!Number.isFinite(mask.power)) {
		return Result.err(ColorMatrixError.NonFinite);
	}
	if (mask.power <= 0.0) { return Result.err(ColorMatrixError.UndefinedMaskPower); }
	return Result.ok(null);
}

function flag(on: boolean): float32 {
	return on ? 1.0 : 0.0;
}

export function writeColorMatrixBlock(
	settings: ColorMatrixSettings,
	mask: ColorMatrixMask | null,
	out: Span<float32>,
): void {
	settings.matrix.writeTo(out, COLOR_MATRIX);
	const second = settings.secondMatrix;
	(second ?? identity()).writeTo(out, COLOR_MATRIX_SECOND);
	const shape: ColorMatrixMask = mask ?? ColorMatrixMask.create();
	out[COLOR_MATRIX_MASK_A] = shape.matA.x;
	out[COLOR_MATRIX_MASK_A + 1] = shape.matA.y;
	out[COLOR_MATRIX_MASK_A + 2] = shape.matA.z;
	out[COLOR_MATRIX_MASK_A + 3] = shape.power;
	out[COLOR_MATRIX_MASK_B] = shape.matB.x;
	out[COLOR_MATRIX_MASK_B + 1] = shape.matB.y;
	out[COLOR_MATRIX_MASK_B + 2] = shape.matB.z;
	out[COLOR_MATRIX_MASK_B + 3] = 0.0;
	out[COLOR_MATRIX_MASK_CHANNEL] = shape.channel.x;
	out[COLOR_MATRIX_MASK_CHANNEL + 1] = shape.channel.y;
	out[COLOR_MATRIX_MASK_CHANNEL + 2] = shape.channel.z;
	out[COLOR_MATRIX_MASK_CHANNEL + 3] = shape.channel.w;
	out[COLOR_MATRIX_FLAGS] = flag(settings.useAlpha);
	out[COLOR_MATRIX_FLAGS + 1] = flag(mask !== null);
	out[COLOR_MATRIX_FLAGS + 2] = flag(mask !== null && mask.invert);
	out[COLOR_MATRIX_FLAGS + 3] = flag(second !== null);
}

const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };

export interface ColorMatrixPass {
	settings: ColorMatrixSettings;
	sampler: Sampler;
	block: UniformBlock;
	material: MaterialId;
	values: Vec<float32>;
	colors: Vec<ColorAttachment>;
}

function stopOnSettings(error: ColorMatrixError): void {
	console.log(`void3d: a colour matrix pass ${error.toString()}: every matrix and mask value ` +
		"is finite and the mask power above 0");
	unreachable;
}

// Reserves the block and adds the material to `context`, whose pool the caller checked fits
// COLOR_MATRIX_UNIFORM_LENGTH; no GPU object is made here.
export function reserve(
	this typeof ColorMatrixPass,
	context: DrawContext,
	settings: ColorMatrixSettings,
): ColorMatrixPass {
	const valid = settings.validate(null);
	if (!valid.ok) { stopOnSettings(valid.error); }
	const reserved: Result<UniformBlock, UniformError> =
		reserveUniforms(context, COLOR_MATRIX_UNIFORM_SLOT, COLOR_MATRIX_UNIFORM_LENGTH);
	if (!reserved.ok) {
		console.log("void3d: ColorMatrixPass.reserve found no room for its checked block");
		unreachable;
	}
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.keyed(ProgramKey.of(Program.ColorMatrix), screenState(), Phase.Opaque),
		uniforms: reserved.value,
	});
	if (!added.ok) { unreachable; }
	return {
		settings: settings,
		sampler: { filter: FilterMode.Linear, wrap: Wrap.Clamp, handle: 0, generation: 0 },
		block: reserved.value,
		material: added.value,
		values: new Array(COLOR_MATRIX_UNIFORM_LENGTH),
		colors: new Array(1),
	};
}

export function setSettings(this pass: ColorMatrixPass, settings: ColorMatrixSettings): void {
	const valid = settings.validate(null);
	if (!valid.ok) { stopOnSettings(valid.error); }
	pass.settings = settings;
}

export function adoptContext(this pass: ColorMatrixPass): void {
	pass.sampler = Sampler.create(pass.sampler.filter, pass.sampler.wrap);
}

function stopOnSize(source: RenderTarget, target: RenderTarget): void {
	console.log(`void3d: a colour matrix from ${source.width}x${source.height} into ` +
		`${target.width}x${target.height}; the source is the target's size`);
	unreachable;
}

// ColorMatrix.apply: `source` through the matrix into `target`, which must not be it. With a
// mask, its texel under the mapped UV weights the second matrix (or the source) against the first.
export function draw(
	this pass: ColorMatrixPass,
	core: Renderer,
	source: RenderTarget,
	target: RenderTarget,
	maskTexture: RenderTarget | null,
	mask: ColorMatrixMask | null,
): void {
	if (source.width != target.width || source.height != target.height) {
		stopOnSize(source, target);
	}
	if ((maskTexture === null) != (mask === null)) {
		console.log("void3d: a colour matrix mask needs both its texture and its settings");
		unreachable;
	}
	const valid = pass.settings.validate(mask);
	if (!valid.ok) { stopOnSettings(valid.error); }
	const context: DrawContext = core.context;
	const index: int32 = pass.material.index;
	context.materials[index].texture0 = source.asTexture();
	context.materials[index].texture1 =
		maskTexture !== null ? maskTexture.asTexture() : source.asTexture();
	context.materials[index].sampler0 = pass.sampler.asHandle();
	context.materials[index].sampler1 = pass.sampler.asHandle();
	writeColorMatrixBlock(pass.settings, mask, pass.values);
	const written: Result<int32, UniformError> = writeUniforms(context, pass.block, pass.values);
	if (!written.ok) { unreachable; }
	pass.colors[0] = target.asColor(LoadAction.DontCare, NO_CLEAR);
	beginPass(pass.colors, NO_DEPTH);
	const drawn: Result<int32, RendererError> =
		drawScreen(core, pass.material, layoutOf(pass.colors, NO_DEPTH));
	if (!drawn.ok) { unreachable; }
	endPass();
}

export function close(this pass: ColorMatrixPass, context: DrawContext, call: string): void {
	pass.sampler = pass.sampler.released();
	const released: Result<int32, HandleError> = releaseMaterial(context, pass.material);
	if (!released.ok) {
		console.log(`void3d: ${call} found the colour matrix material ` +
			released.error.toString());
		unreachable;
	}
}

function checkedColor(color: Vec4): Result<Vec4, ColorMatrixError> {
	if (!finiteColor(color)) { return Result.err(ColorMatrixError.NonFinite); }
	return Result.ok(color);
}

function finiteColor(color: Vec4): boolean {
	return Number.isFinite(color.x) && Number.isFinite(color.y) &&
		Number.isFinite(color.z) && Number.isFinite(color.w);
}

function finiteVector(value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function finiteMatrix(matrix: Mat4): boolean {
	return Number.isFinite(matrix.m11) && Number.isFinite(matrix.m12) &&
		Number.isFinite(matrix.m13) && Number.isFinite(matrix.m14) &&
		Number.isFinite(matrix.m21) && Number.isFinite(matrix.m22) &&
		Number.isFinite(matrix.m23) && Number.isFinite(matrix.m24) &&
		Number.isFinite(matrix.m31) && Number.isFinite(matrix.m32) &&
		Number.isFinite(matrix.m33) && Number.isFinite(matrix.m34) &&
		Number.isFinite(matrix.m41) && Number.isFinite(matrix.m42) &&
		Number.isFinite(matrix.m43) && Number.isFinite(matrix.m44);
}
