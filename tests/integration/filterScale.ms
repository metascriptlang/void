// A filter at resolutionScale 0.5 against the same filter at 1: the scene is drawn twice and the
// two captures are compared pixel by pixel. Run by hand on the Mac (Metal):
//   msc build -d:voidSdfText -d:voidShaper -d:voidSvg -d:voidProfiler -d:voidColourEmoji \
//     -d:voidSprites -d:voidBidi -d:voidTextOutline tests/integration/filterScale.ms --release \
//     --output=out/filterScale.exe && out/filterScale.exe
// Each case states its tolerance as (mean per-channel difference, largest per-channel difference),
// both in 0..255. Measured on the Mac Metal window: blur 0.44 and 45, glow 1.04 and 115 (the
// glow's sharp copy is rendered at the reduced scale too, so its edge softens).

import { gfxSetup } from "../../src/host/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { presentAt } from "../../src/void2d/scene";
import { fillRoundedRect, fillEllipse } from "../../src/void2d/graphics";
import {
	Color, Filter, rgba, blurFilter, glowFilter, withResolutionScale,
} from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureWidth, voidCaptureHeight, voidCapturePixel,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

struct Case {
	name: string;
	dpi: float32;
	filter: Filter;
	meanTolerance: float32;
	maxTolerance: int32;
}

const DARK: Color = { r: 0.08, g: 0.09, b: 0.12, a: 1.0 };
const WIDTH: int32 = 256;
const HEIGHT: int32 = 160;

const cases: Case[] = [
	{ name: "blur radius 6, dpi 1", dpi: 1.0, filter: blurFilter(6.0),
		meanTolerance: 1.0, maxTolerance: 64 },
	{ name: "glow radius 8, dpi 1.5", dpi: 1.5,
		filter: glowFilter(rgba(1.0, 0.70, 0.25, 1.0), 8.0, 1.8),
		meanTolerance: 1.5, maxTolerance: 128 },
];

let index: int32 = 0;
let stage: int32 = 0;
let full: Scene2D | null = null;
let half: Scene2D | null = null;

function fail(message: string): void {
	console.log(`FAIL filterScale ${cases[index].name}: ${message}`);
	voidCaptureExit(1);
}

function subject(f: Filter, scale: float32): Scene2D {
	const s = Scene2D.create(DARK);
	const host = s.rect(0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0)).at(40.0, 40.0);
	const g = s.graphics();
	g.fillRoundedRect(0.0, 0.0, 90.0, 60.0, 14.0, rgba(1.0, 0.82, 0.35, 1.0));
	g.fillEllipse(45.0, 30.0, 22.0, 14.0, rgba(0.30, 0.20, 0.55, 1.0));
	host.addChild(g);
	host.setFilter(f.withResolutionScale(scale));
	s.add(host);
	return s;
}

function init(): void {
	gfxSetup();
	setup2d();
	console.log(`BACKEND ${voidCaptureBackend()}`);
	if (voidCaptureBackend() == 0) {
		console.log("SKIP this build has no readback path");
		voidCaptureExit(3);
	}
}

function grab(slot: int32): void {
	if (voidCaptureGrab(slot) == 0) { fail(`readback failed on slot ${slot}`); }
}

function compare(): void {
	if (voidCaptureWidth(0) != WIDTH || voidCaptureHeight(0) != HEIGHT
		|| voidCaptureWidth(1) != WIDTH || voidCaptureHeight(1) != HEIGHT) {
		fail("capture size differs from the window");
	}
	let sum: int64 = 0;
	let largest: int32 = 0;
	let differing: int32 = 0;
	for (let y: int32 = 0; y < HEIGHT; y++) {
		for (let x: int32 = 0; x < WIDTH; x++) {
			const a: int64 = voidCapturePixel(0, x, y);
			const b: int64 = voidCapturePixel(1, x, y);
			for (let shift: int32 = 8; shift <= 24; shift += 8) {
				const ca: int32 = ((a >> (shift as int64)) & 255) as int32;
				const cb: int32 = ((b >> (shift as int64)) & 255) as int32;
				const d: int32 = ca > cb ? ca - cb : cb - ca;
				sum += d as int64;
				if (d > largest) { largest = d; }
				if (d > 0) { differing++; }
			}
		}
	}
	const mean: float32 = (sum as float32) / ((WIDTH * HEIGHT * 3) as float32);
	console.log(`MEASURED ${cases[index].name}: mean ${mean} largest ${largest} channels differing ${differing}`);
	if (differing == 0) { fail("the half-resolution capture is identical to the full one, so the scale did nothing"); }
	if (mean > cases[index].meanTolerance || largest > cases[index].maxTolerance) {
		fail(`outside tolerance mean ${cases[index].meanTolerance} largest ${cases[index].maxTolerance}`);
	}
}

function frame(): void {
	if (stage == 0) {
		full = subject(cases[index].filter, 1.0);
		half = subject(cases[index].filter, 0.5);
	}
	const f = full;
	const h = half;
	if (f === null || h === null) { return; }
	if (stage < 2) { f.presentAt(cases[index].dpi); }
	if (stage == 1) { grab(0); }
	if (stage >= 2) { h.presentAt(cases[index].dpi); }
	if (stage == 3) {
		grab(1);
		compare();
		index++;
		stage = 0;
		if (index == (cases.length as int32)) {
			console.log("PASS filterScale");
			voidCaptureExit(0);
		}
		return;
	}
	stage++;
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
