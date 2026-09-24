// P3's rasterizer experiment (docs/VOID2D.md P3, "The rasterizer"): the same code sample
// through the same pipeline and the P0 capture path, rasterized by stb_truetype or by
// FreeType, at 13 px / 1x, 13 px / 1.5x and 14 px / 1.25x. scripts/experiment-rasterizer.sh
// builds it with FreeType on the include path and runs every arm and sample.
//
//   VOID_RASTERIZER  0 stb_truetype unhinted, 1 FreeType unhinted, 2 FreeType light hinting
//   VOID_SAMPLE      0 13 px @ 1x, 1 13 px @ 1.5x, 2 14 px @ 1.25x

import { gfxSetup } from "../../src/sokol/gpu";
import { setup2d } from "../../src/void2d/draw";
import { label } from "../../src/void2d/node";
import { Scene, scene, add, presentAt } from "../../src/void2d/scene";
import { rgba } from "../../src/void2d/types";
import {
	voidCaptureGrab,
	voidCapturePixel,
	voidCaptureWidth,
	voidCaptureHeight,
	voidCaptureSlotsDiffer,
	voidCaptureWritePng,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";
import { void2dFreetypeInstall } from "./freetypeRaster.h";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

const LINES: string[] = [
	"fn layout(node: &Node, width: f32) -> Size {",
	"    let mut used = 0.0; // iIl1| 0Oo8 mmwWVA",
	"    for child in node.children() { used += child.measure(width); }",
	"    Size { width: used.min(width), height: LINE_HEIGHT * 1.25 }",
	"}",
];
const ARM_NAMES: string[] = ["stb", "freetype", "freetypeLight"];
const SIZES: float32[] = [13.0, 13.0, 14.0];
const DPIS: float32[] = [1.0, 1.5, 1.25];
const WIDTH_LOGICAL: float32 = 480.0;
const HEIGHT_LOGICAL: float32 = 100.0;
const BACKGROUND: int32 = 0x1E;
const FOREGROUND: int32 = 0xDC;

let arm: int32 = 0;
let sample: int32 = 0;
let current: Scene | null = null;
let stage: int32 = 0;

function init(): void {
	gfxSetup();
	setup2d();
	const s = scene(rgba((BACKGROUND as float32) / 255.0, (BACKGROUND as float32) / 255.0, (BACKGROUND as float32) / 255.0, 1.0));
	const ink = (FOREGROUND as float32) / 255.0;
	for (let i: int32 = 0; i < (LINES.length as int32); i++) {
		s.add(label(LINES[i], SIZES[sample], rgba(ink, ink, ink, 1.0)).at(8.0, 6.0 + (i as float32) * SIZES[sample] * 1.4));
	}
	current = s;
}

function coverageAt(x: int32, y: int32): float64 {
	const pixel: int64 = voidCapturePixel(1, x, y) as int64;
	const green: int32 = ((pixel >> 16) & 0xFF) as int32;
	const c: float64 = ((green - BACKGROUND) as float64) / ((FOREGROUND - BACKGROUND) as float64);
	return c < 0.0 ? 0.0 : (c > 1.0 ? 1.0 : c);
}

function measure(): void {
	let ink: float64 = 0.0;
	let solid: float64 = 0.0;
	let grey: int32 = 0;
	let touched: int32 = 0;
	for (let y: int32 = 0; y < voidCaptureHeight(1); y++) {
		for (let x: int32 = 0; x < voidCaptureWidth(1); x++) {
			const c = coverageAt(x, y);
			if (c <= 0.0) { continue; }
			touched = touched + 1;
			ink = ink + c;
			if (c >= 0.85) { solid = solid + c; }
			if (c > 0.15 && c < 0.85) { grey = grey + 1; }
		}
	}
	const name: string = `${ARM_NAMES[arm]}-${SIZES[sample]}px-${DPIS[sample]}x`;
	console.log(
		`RASTER ${name} ink ${ink} solidShare ${solid / ink} greyShare ${(grey as float64) / (touched as float64)}`
		+ ` touched ${touched}`,
	);
	const path: string = `out/experiments/rasterizer/${name}.png`;
	if (voidCaptureWritePng(1, path) == 0) {
		console.log(`FAIL could not write ${path}`);
		voidCaptureExit(1);
	}
}

function frame(): void {
	const s = current;
	if (s === null) { return; }
	s.presentAt(DPIS[sample]);
	stage = stage + 1;
	if (stage == 2 && voidCaptureGrab(0) == 0) { voidCaptureExit(1); }
	if (stage < 3) { return; }
	if (voidCaptureGrab(1) == 0) { voidCaptureExit(1); }
	if (voidCaptureSlotsDiffer() != 0) {
		console.log("FAIL two draws of the same state differ");
		voidCaptureExit(1);
	}
	measure();
	voidCaptureExit(0);
}

function start(): void {
	arm = voidCaptureEnvInt("VOID_RASTERIZER", -1);
	sample = voidCaptureEnvInt("VOID_SAMPLE", -1);
	if (arm < 0 || arm > 2 || sample < 0 || sample > 2) {
		console.log("FAIL VOID_RASTERIZER must be 0..2 and VOID_SAMPLE 0..2");
		voidCaptureExit(2);
	}
	if (arm > 0 && void2dFreetypeInstall(arm == 2 ? 1 : 0) == 0) { voidCaptureExit(1); }
	const width = Math.round(WIDTH_LOGICAL * DPIS[sample]) as int32;
	const height = Math.round(HEIGHT_LOGICAL * DPIS[sample]) as int32;
	voidRunConfigured(width, height, 1, 0, init, frame);
}

start();
