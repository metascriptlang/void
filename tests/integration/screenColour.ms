// Heaps' FXAA and ColorMatrix passes on the GPU. A black and white staircase through FXAA: the
// pixels on both sides of each stair blend to the values post3dCheck.ms pins, the rest stay black
// or white. A flat colour through a matrix, then through a matrix with a mask mixing back toward
// the source: each reads back as the CPU's materialColorMatrixRaw gives for the stored texels.

import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { Mat4, Vec4, vec4 } from "../../src/math/math3d";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { PixelFormat, LoadAction, endPass, commit } from "../../src/gpu/door";
import {
	RenderTarget,
	ColorAttachment,
	TargetLayout,
	NO_DEPTH,
	SWAPCHAIN_LAYOUT,
	beginPass,
	beginScreenPass,
} from "../../src/gpu/target";
import { Program, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../src/void3d/gpu3d";
import { Material, Phase } from "../../src/void3d/material";
import { TextureData, TextureId, TextureUploadError } from "../../src/void3d/texture";
import {
	DrawContext, DrawItem, MaterialId, MaterialError, addTexture, addMaterial,
} from "../../src/void3d/draw";
import {
	Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame, closePrepare,
	openScreen, drawScreen,
} from "../../src/void3d/renderer";
import { screenState } from "../../src/void3d/screenFx";
import { FxaaPass } from "../../src/void3d/fxaa";
import {
	ColorMatrixPass,
	ColorMatrixSettings,
	ColorMatrixMask,
	COLOR_MATRIX_UNIFORM_LENGTH,
	materialColorMatrixRaw,
} from "../../src/void3d/colorMatrixPass";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const SIZE: int32 = 64;
// FXAA samples up to its span of 8 texels away; past it a stair sees only the staircase.
const MARGIN: int32 = 10;
const STEP: float32 = 0.813443 * 255.0;
const UNDER: float32 = 0.186557 * 255.0;
const BLEND_TOLERANCE: float32 = 6.0;
const TOLERANCE: float32 = 3.0;
const NO_CLEAR: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
// 0xAABBGGRR, opaque: the source colour, and the mask texel.
const SOURCE_PIXEL: uint32 = 0xFFBF8040;
const MASK_PIXEL: uint32 = 0x80BF4080;

let context: DrawContext =
	DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH + COLOR_MATRIX_UNIFORM_LENGTH);
let core: Renderer = makeCore();
let fxaa: FxaaPass = FxaaPass.reserve(context);
let colorMatrix: ColorMatrixPass = ColorMatrixPass.reserve(context, plainSettings());
let stairsCopy: MaterialId = { store: 0, index: 0, generation: 0 };
let flatCopy: MaterialId = { store: 0, index: 0, generation: 0 };
let maskCopy: MaterialId = { store: 0, index: 0, generation: 0 };
let screenCopy: MaterialId = { store: 0, index: 0, generation: 0 };
let source: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let maskTarget: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let result: RenderTarget = RenderTarget.unallocated(PixelFormat.Rgba8, true);
let colors: Vec<ColorAttachment> = new Array(1);
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
let empty: Vec<DrawItem> = [];
let frames: int32 = 0;

function makeCore(): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (!made.ok) { unreachable; }
	return made.value;
}

function fail(message: string): void {
	console.log(`FAIL screen colour: ${message}`);
	voidCaptureExit(1);
}

function matrixA(): Mat4 {
	return {
		m11: 1.0, m12: 0.5, m13: -0.25, m14: 0.25,
		m21: -0.5, m22: 1.0, m23: 0.5, m24: -0.125,
		m31: 0.25, m32: -0.25, m33: 1.0, m34: 0.5,
		m41: 0.125, m42: 0.25, m43: -0.125, m44: 0.75,
	};
}

function matrixB(): Mat4 {
	return {
		m11: 0.5, m12: -0.25, m13: 0.75, m14: -0.5,
		m21: 0.25, m22: 1.0, m23: -0.5, m24: 0.25,
		m31: -0.5, m32: 0.5, m33: 1.0, m34: 0.125,
		m41: 0.25, m42: -0.125, m43: 0.5, m44: 0.625,
	};
}

function plainSettings(): ColorMatrixSettings {
	return { matrix: matrixA(), useAlpha: false, secondMatrix: null };
}

function weightedMask(): ColorMatrixMask {
	return {
		...ColorMatrixMask.create(),
		channel: vec4(0.25, 0.5, 0.125, 0.125),
		power: 2.0,
	};
}

function texture(pixels: Vec<uint32>, width: int32, height: int32): TextureId {
	const data: TextureData = {
		pixels: pixels, width: width, height: height, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!uploaded.ok) { fail("a source texture was refused"); unreachable; }
	return uploaded.value;
}

function copyOf(id: TextureId): MaterialId {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.Copy, screenState(), Phase.Opaque), texture: id,
	});
	if (!added.ok) { fail("a copy material was refused"); unreachable; }
	return added.value;
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	let stairs: Vec<uint32> = [];
	for (let y = 0; y < SIZE; y++) {
		for (let x = 0; x < SIZE; x++) { stairs.push(x > y ? 0xFFFFFFFF : 0xFF000000); }
	}
	stairsCopy = copyOf(texture(stairs, SIZE, SIZE));
	flatCopy = copyOf(texture([SOURCE_PIXEL], 1, 1));
	maskCopy = copyOf(texture([MASK_PIXEL], 1, 1));
	const added: Result<MaterialId, MaterialError> =
		addMaterial(context, Material.plain(Program.Copy, screenState(), Phase.Opaque));
	if (!added.ok) { fail("the screen copy was refused"); unreachable; }
	screenCopy = added.value;
	camera[0] = 1.0; camera[5] = 1.0; camera[10] = 1.0; camera[15] = 1.0;
}

function layoutOf(): TargetLayout {
	return {
		color0: PixelFormat.Rgba8,
		color1: PixelFormat.None,
		color2: PixelFormat.None,
		color3: PixelFormat.None,
		depth: PixelFormat.None,
		sampleCount: 1,
	};
}

function drawInto(target: RenderTarget, material: MaterialId): void {
	colors[0] = target.asColor(LoadAction.DontCare, NO_CLEAR);
	beginPass(colors, NO_DEPTH);
	if (!drawScreen(core, material, layoutOf()).ok) { fail("a copy into a target was refused"); }
	endPass();
}

function channel(pixel: int64, shift: int64): float32 {
	return ((pixel >> shift) & 255) as float32;
}

function stored(byte: uint32): float32 {
	return (byte as float32) / 255.0;
}

function sourceColor(): Vec4 {
	return vec4(stored(SOURCE_PIXEL & 255), stored((SOURCE_PIXEL >> 8) & 255),
		stored((SOURCE_PIXEL >> 16) & 255), 1.0);
}

function unit(value: float32): float32 {
	return Math.min(Math.max(value, 0.0), 1.0) * 255.0;
}

function expectColor(slot: int32, expected: Vec4, what: string): void {
	const pixel: int64 = voidCapturePixel(slot, SIZE / 2, SIZE / 2);
	const red: float32 = channel(pixel, 24);
	const green: float32 = channel(pixel, 16);
	const blue: float32 = channel(pixel, 8);
	if (Math.abs(red - unit(expected.x)) > TOLERANCE ||
		Math.abs(green - unit(expected.y)) > TOLERANCE ||
		Math.abs(blue - unit(expected.z)) > TOLERANCE) {
		fail(`${what} read ${red}, ${green}, ${blue}; the CPU gives ` +
			`${unit(expected.x)}, ${unit(expected.y)}, ${unit(expected.z)}`);
	}
	console.log(`screen colour: ${what} ${red}, ${green}, ${blue}`);
}

function checkFxaa(): void {
	let steps: int32 = 0;
	let unders: int32 = 0;
	for (let y = MARGIN; y < SIZE - MARGIN; y++) {
		for (let x = MARGIN; x < SIZE - MARGIN; x++) {
			const value: float32 = channel(voidCapturePixel(0, x, y), 24);
			if (value <= TOLERANCE || value >= 255.0 - TOLERANCE) { continue; }
			if (Math.abs(value - STEP) <= BLEND_TOLERANCE) { steps = steps + 1; continue; }
			if (Math.abs(value - UNDER) <= BLEND_TOLERANCE) { unders = unders + 1; continue; }
			fail(`FXAA drew ${value} at ${x}, ${y}, neither flat nor a stair's blend`);
		}
	}
	const diagonal: int32 = SIZE - 2 * MARGIN;
	if (steps < diagonal - 1 || unders < diagonal - 1) {
		fail(`FXAA blended ${steps} pixels above the stairs and ${unders} under them, ` +
			`expected one of each per stair, ${diagonal}`);
	}
	console.log(`screen colour: FXAA blended ${steps} pixels to ${STEP} and ${unders} to ${UNDER}`);
}

function checkMatrix(): void {
	const color: Vec4 = sourceColor();
	const plain = materialColorMatrixRaw(color, matrixA());
	if (!plain.ok) { unreachable; }
	expectColor(1, plain.value, "the matrix");
	const first = materialColorMatrixRaw(color, matrixB());
	if (!first.ok) { unreachable; }
	const mask: ColorMatrixMask = weightedMask();
	const texel: Vec4 = vec4(stored(MASK_PIXEL & 255), stored((MASK_PIXEL >> 8) & 255),
		stored((MASK_PIXEL >> 16) & 255), stored((MASK_PIXEL >> 24) & 255));
	const dot: float32 = texel.x * mask.channel.x + texel.y * mask.channel.y +
		texel.z * mask.channel.z + texel.w * mask.channel.w;
	const weight: float32 = Math.pow(dot, mask.power) as float32;
	const mixed: Vec4 = vec4(
		first.value.x + (color.x - first.value.x) * weight,
		first.value.y + (color.y - first.value.y) * weight,
		first.value.z + (color.z - first.value.z) * weight, 1.0);
	expectColor(2, mixed, "the masked matrix");
}

function frame(): void {
	if (fbWidth() != SIZE || fbHeight() != SIZE) { fail("the framebuffer size changed"); }
	core.openPrepare();
	const began: Result<boolean, RendererError> = beginFrame(core, empty, camera, lights);
	if (!began.ok) {
		fail(`beginFrame refused: ${began.error.toString()}`);
		return;
	}
	if (began.value || frames == 0) {
		fxaa.adoptContext();
		colorMatrix.adoptContext();
	}
	closePrepare(core);
	source.resize(SIZE, SIZE);
	maskTarget.resize(SIZE, SIZE);
	result.resize(SIZE, SIZE);
	if (frames == 0) {
		drawInto(source, stairsCopy);
		fxaa.draw(core, source, result);
	} else if (frames == 1) {
		drawInto(source, flatCopy);
		colorMatrix.setSettings(plainSettings());
		colorMatrix.draw(core, source, result, null, null);
	} else {
		drawInto(source, flatCopy);
		drawInto(maskTarget, maskCopy);
		colorMatrix.setSettings({ ...plainSettings(), matrix: matrixB() });
		colorMatrix.draw(core, source, result, maskTarget, weightedMask());
	}
	context.materials[screenCopy.index].texture0 = result.asTexture();
	context.materials[screenCopy.index].sampler0 = fxaa.sampler.asHandle();
	beginScreenPass(NO_CLEAR);
	openScreen(core);
	if (!drawScreen(core, screenCopy, SWAPCHAIN_LAYOUT).ok) { fail("the screen copy was refused"); }
	endPass();
	commit();
	if (voidCaptureGrab(frames) == 0) { fail("readback failed"); }
	frames = frames + 1;
	if (frames < 3) { return; }
	checkFxaa();
	checkMatrix();
	console.log("PASS screen colour: FXAA blends each stair as the CPU does and leaves the flat " +
		"pixels, and the colour matrix, plain and masked, gives the CPU's colour");
	voidCaptureExit(0);
}

voidRunConfigured(SIZE, SIZE, 1, 0, init, frame);
