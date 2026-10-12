import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../../src/gpu/door";
import {
	setup2d, begin2d, finishRecording, frameEnd, glyphPageView, setTextGamma,
	drawUiInstance, pushClip, popClip, droppedFrames, setSampler,
} from "../../src/void2d/draw";
import { currentContext, uiInstanceCount, uiInstanceField } from "../../src/void2d/displayList";
import { REC_UI_PARAMS0, REC_UI_UV_RADII } from "../../src/void2d/instanceLayout";
import { InstanceMode, UiInstance, uiInstance } from "../../src/void2d/instance";
import { identity2d, rgba, vec2, Smooth } from "../../src/void2d/types";
import { BlendMode } from "../../src/gpu/state";
import { GlyphPageHandle, PageKind } from "../../src/void2d/glyphAtlas";
import {
	void2dGlyphPageCreate, void2dGlyphPageRelease, void2dGlyphPageKind,
	void2dGlyphPageTexel, void2dGlyphPageTexelRgba,
	void2dGlyphPageBlitMask, void2dGlyphPageBlitRgba,
} from "../../src/void2d/glyph.h";
import {
	voidCaptureBackend, voidCaptureRenderer, voidCaptureEnvInt, voidCapturePixel,
	voidCaptureGrab, voidCaptureWidth, voidCaptureHeight, voidCaptureSlotsDiffer,
	voidCaptureWritePng, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const DPI: int32 = voidCaptureEnvInt("GLYPH_DPI", 1);
const WIDTH: int32 = 224;
const HEIGHT: int32 = 104;
let maskPage: int32 = -1;
let rgbaPage: int32 = -1;
let maskView: uint32 = 0;
let rgbaView: uint32 = 0;
let stage: int32 = 0;

function releasePages(): void {
	if (maskPage >= 0) { void2dGlyphPageRelease(maskPage); maskPage = -1; }
	if (rgbaPage >= 0) { void2dGlyphPageRelease(rgbaPage); rgbaPage = -1; }
}

function fail(message: string): void {
	console.log(`FAIL glyph probe: ${message}`);
	releasePages();
	voidCaptureExit(1);
}

function makePages(): void {
	maskPage = void2dGlyphPageCreate(32, PageKind.Mask as int32);
	rgbaPage = void2dGlyphPageCreate(32, PageKind.Rgba as int32);
	if (maskPage < 0 || rgbaPage < 0) { fail("R8 mask/RGBA page allocation refused"); }
	let alpha: Vec<uint8> = [];
	let pixels: Vec<uint32> = [];
	for (let i: int32 = 0; i < 32 * 32; i++) {
		alpha.push(255);
		pixels.push(0x80204080);
	}
	if (void2dGlyphPageBlitMask(maskPage, 0, 0, 32, 32, alpha[0], 1024, 32) != 0 ||
		void2dGlyphPageBlitRgba(rgbaPage, 0, 0, 32, 32, pixels[0], 32) != 0) {
		fail("page fill refused");
	}
	if (void2dGlyphPageKind(maskPage) != PageKind.Mask as int32 ||
		void2dGlyphPageKind(rgbaPage) != PageKind.Rgba as int32) {
		fail("page kinds differ from requested kinds");
	}
	for (let y: int32 = 0; y < 32; y++) {
		for (let x: int32 = 0; x < 32; x++) {
			if (void2dGlyphPageTexel(maskPage, x, y) != 255 ||
				void2dGlyphPageTexelRgba(rgbaPage, x, y) != 0x80204080) {
				fail("page texels differ from fixture inputs");
			}
		}
	}
}

function glyph(x: float32, y: float32, high: boolean, sdf: boolean): void {
	const base: UiInstance = uiInstance(
		InstanceMode.Glyph, identity2d(), x, y, 16.0, 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	const u0: float32 = high ? 0.875 : 0.03125;
	const u1: float32 = high ? 0.9375 : 0.09375;
	const inst: UiInstance = {
		...base, uvRadii: [u0, u0, u1, u1], params: [sdf ? 1.0 : 0.0, 0.0, 0.0],
	};
	drawUiInstance(maskView, BlendMode.Alpha, inst);
}

function box(x: float32, rounded: boolean): void {
	const base: UiInstance = uiInstance(
		InstanceMode.Box, identity2d(), x, 8.0, 16.0, 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	const r: float32 = rounded ? 4.0 : 0.0;
	drawUiInstance(0, BlendMode.Alpha, { ...base, uvRadii: [r, r, r, r] });
}

function image(x: float32, rounded: boolean, premultiplied: boolean): void {
	const base: UiInstance = uiInstance(
		InstanceMode.Image, identity2d(), x, 40.0, 16.0, 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	const r: float32 = rounded ? 4.0 : 0.0;
	drawUiInstance(rgbaView, BlendMode.Alpha, {
		...base, uvRadii: [0.875, 0.875, 0.9375, 0.9375], borders: [r, r, r, r],
		params1: [0.0, premultiplied ? 1.0 : 0.0, 0.0, 0.0],
	});
}

function recordFixture(): void {
	begin2d(WIDTH as float32, HEIGHT as float32, DPI as float32);
	setSampler(Smooth.Off, false);
	glyph(8.0, 8.0, false, false);
	glyph(40.0, 8.0, true, false);
	glyph(72.0, 8.0, false, true);
	glyph(104.0, 8.0, true, true);
	box(136.0, false);
	box(168.0, true);
	image(8.0, false, false);
	image(40.0, true, false);
	image(72.0, false, true);
	image(104.0, true, true);
	if (!pushClip(vec2(136.0, 40.0), vec2(144.0, 40.0),
		vec2(144.0, 56.0), vec2(136.0, 56.0))) {
		fail("axis-aligned clip refused");
	}
	glyph(136.0, 40.0, true, false);
	popClip();
	const border: UiInstance = uiInstance(
		InstanceMode.Box, identity2d(), 168.0, 40.0, 16.0, 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	drawUiInstance(0, BlendMode.Alpha, {
		...border, uvRadii: [4.0, 4.0, 4.0, 4.0], borders: [2.0, 2.0, 2.0, 2.0],
		border: rgba(1.0, 0.0, 0.0, 1.0),
	});
	finishRecording();
	if (uiInstanceCount() != 12) { fail("instance count differs from fixture"); }
	for (let i: int32 = 0; i < 4; i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) != InstanceMode.Glyph as float32 ||
			uiInstanceField(i, REC_UI_PARAMS0 + 1) != (i < 2 ? 0.0 : 1.0)) {
			fail("glyph mode/SDF flag differs from fixture");
		}
		const start: float32 = i % 2 == 0 ? 0.03125 : 0.875;
		if (uiInstanceField(i, REC_UI_UV_RADII) != start) {
			fail("glyph UV differs from fixture");
		}
	}
}

function init(): void {
	gfxSetup();
	setup2d();
	setTextGamma(1.0, 0.0);
	makePages();
	maskView = glyphPageView(maskPage as GlyphPageHandle);
	rgbaView = glyphPageView(rgbaPage as GlyphPageHandle);
	if (maskView == 0 || rgbaView == 0) { fail("page views refused"); }
	console.log(`BACKEND ${voidCaptureBackend()} renderer ${voidCaptureRenderer()}`);
}

function checkPixel(x: int32, y: int32, rgb: int32): void {
	const pixel: int64 = voidCapturePixel(1, x, y);
	if (pixel < 0 || pixel >> 8 != rgb as int64) {
		fail(`pixel ${x},${y}: RGB ${pixel >> 8}, expected ${rgb}`);
	}
}

function checkRect(x: int32, y: int32, width: int32, rgb: int32): void {
	for (let dy: int32 = -4 * DPI; dy < 20 * DPI; dy++) {
		for (let dx: int32 = -4 * DPI; dx < 20 * DPI; dx++) {
			const expected: int32 = dx >= 0 && dx < width * DPI && dy >= 0 && dy < 16 * DPI
				? rgb : 0;
			checkPixel(x * DPI + dx, y * DPI + dy, expected);
		}
	}
}

function checkRounded(x: int32, y: int32, rgb: int32): void {
	checkPixel(x * DPI, y * DPI, 0);
	checkPixel((x + 8) * DPI, (y + 8) * DPI, rgb);
}

function checkCapture(): void {
	checkRect(8, 8, 16, 0xFFFFFF);
	checkRect(40, 8, 16, 0xFFFFFF);
	checkRect(72, 8, 16, 0xFFFFFF);
	checkRect(104, 8, 16, 0xFFFFFF);
	checkRect(136, 8, 16, 0xFFFFFF);
	checkRect(8, 40, 16, 0x402010);
	checkRect(72, 40, 16, 0x804020);
	checkRect(136, 40, 8, 0xFFFFFF);
	checkRounded(168, 8, 0xFFFFFF);
	checkRounded(40, 40, 0x402010);
	checkRounded(104, 40, 0x804020);
	checkRounded(168, 40, 0xFFFFFF);
}

function frame(): void {
	recordFixture();
	const ctx = currentContext();
	ctx.prepare();
	beginScreenPassWith(0.0, 0.0, 0.0, 1.0);
	ctx.drawScreen();
	endPass();
	commit();
	if (droppedFrames() != 0) { fail("renderer dropped a frame"); }
	stage = stage + 1;
	if (stage == 3 || stage == 4) {
		if (voidCaptureGrab(stage - 3) != 1) { fail("readback failed"); }
	}
	if (stage != 4) { return; }
	if (voidCaptureWidth(1) != WIDTH * DPI || voidCaptureHeight(1) != HEIGHT * DPI ||
		voidCaptureSlotsDiffer() != 0) { fail("framebuffer dimensions/stability differ"); }
	checkCapture();
	const output: string = env.get("GLYPH_OUTPUT");
	if (!output.equals("") && voidCaptureWritePng(1, output) != 1) { fail("PNG write failed"); }
	console.log(`PASS glyph clip dpi ${DPI}: bitmap/SDF shader paths, UV isolation and controls`);
	releasePages();
	voidCaptureExit(0);
}

if (DPI < 1 || DPI > 3) { fail("DPI must be 1, 2 or 3"); }
if (env.get("GLYPH_CPU_ONLY").equals("1")) {
	makePages();
	recordFixture();
	frameEnd();
	releasePages();
	console.log("PASS glyph fixture CPU inputs: R8/RGBA texels and glyph UV/mode/SDF packing");
} else if (voidCaptureBackend() == 0) {
	console.log("SKIP glyph clip: this backend has no readback path");
} else {
	voidRunConfigured(WIDTH * DPI, HEIGHT * DPI, 1, 0, init, frame);
}
