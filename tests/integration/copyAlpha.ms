// Program.Copy is a data-preserving RGBA copy, not an opaque presentation policy.
import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { FilterMode, Wrap } from "../../src/gpu/state";
import { endPass, commit } from "../../src/gpu/door";
import { SWAPCHAIN_LAYOUT, beginScreenPass } from "../../src/gpu/target";
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
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

console.log("FAIL copy alpha diagnostic: entering global context construction");
const context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
const core: Renderer = makeCore();
console.log("FAIL copy alpha diagnostic: completed global context/core construction");
let copy: MaterialId = { store: 0, index: 0, generation: 0 };
let camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
const empty: Vec<DrawItem> = [];

function makeCore(): Renderer {
	const made: Result<Renderer, RendererError> = Renderer.create(context);
	if (!made.ok) { unreachable; }
	return made.value;
}

function fail(message: string): void {
	console.log(`FAIL copy alpha: ${message}`);
	voidCaptureExit(1);
}

function init(): void {
	console.log(`FAIL copy alpha diagnostic: init backend${voidCaptureBackend()} request160x120 fb${fbWidth()}x${fbHeight()}`);
	if (voidCaptureBackend() == 0) { fail("unsupported capture backend"); }
	console.log("FAIL copy alpha diagnostic: entering gfxSetup");
	gfxSetup();
	console.log("FAIL copy alpha diagnostic: gfxSetup complete");
	const data: TextureData = {
		// Opaque, premultiplied half-alpha, transparent black, raw data RGB with zero alpha.
		pixels: [0xFF808080, 0x80404040, 0x00000000, 0x00201008],
		width: 4, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp,
	};
	const uploaded: Result<TextureId, TextureUploadError> = addTexture(context, data);
	if (!uploaded.ok) { fail("source texture refused"); unreachable; }
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(Program.Copy, screenState(), Phase.Opaque), texture: uploaded.value,
	});
	if (!added.ok) { fail("copy material refused"); unreachable; }
	copy = added.value;
	camera[0] = 1.0; camera[5] = 1.0; camera[10] = 1.0; camera[15] = 1.0;
}

function frame(): void {
	console.log(`FAIL copy alpha diagnostic: frame fb${fbWidth()}x${fbHeight()}`);
	core.openPrepare();
	const began = beginFrame(core, empty, camera, lights);
	if (!began.ok) { fail("frame refused"); }
	closePrepare(core);
	beginScreenPass({ x: 1.0, y: 0.0, z: 1.0, w: 1.0 });
	openScreen(core);
	if (!drawScreen(core, copy, SWAPCHAIN_LAYOUT).ok) { fail("copy draw refused"); }
	endPass();
	commit();
	if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
	const expected: Vec<int64> = [0x808080FF, 0x40404080, 0x00000000, 0x08102000];
	for (let x = 0; x < 4; x++) {
		const actual: int64 = voidCapturePixel(0, x, 0);
		if (actual != expected[x]) { fail(`pixel ${x}: ${actual}, expected ${expected[x]}`); }
	}
	// Control: clamped copy still keeps zero alpha; no stale magenta clear leaks through.
	if (voidCapturePixel(0, 31, 0) != expected[3]) { fail("source clamp or clear leakage"); }
	console.log("PASS copy alpha: exact opaque/half/zero/raw-data RGBA, clamped control");
	voidCaptureExit(0);
}

voidRunConfigured(160, 120, 1, 0, init, frame);
