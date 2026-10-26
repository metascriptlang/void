// A filter chain and the outline step on the Mac (Metal window); build and run like filterScale.ms.
// The subject is a white square on black. An outline is a ring of taps `size` away, so a single
// outline paints the pixels within `size` of the square; the second outline of a chain reads the
// first one's target, so it reaches `size` past the first. A pixel that only the chain colours
// is the proof that the steps ran in order and that each read the one before.

import { gfxSetup } from "../../src/host/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { presentAt } from "../../src/void2d/scene";
import { Color, Filter, rgba, outlineFilter, withResolutionScale } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureWidth, voidCaptureHeight, voidCapturePixel,
	voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const RED: int32 = 0xFF0000;
const BLUE: int32 = 0x0000FF;
const WHITE: int32 = 0xFFFFFF;
const BLACK: int32 = 0x000000;
const SQUARE_X: float32 = 60.0;
const SQUARE_Y: float32 = 40.0;
const SQUARE: float32 = 40.0;
const TOLERANCE: int32 = 40;

struct Probe {
	dx: float32;
	dy: float32;
	rgb: int32;
}

struct Case {
	name: string;
	dpi: float32;
	scale: float32;
	steps: Filter[];
	probes: Probe[];
}

// Offsets are from the square's left edge, at its vertical middle; negative is outside.
const insideSquare: Probe = { dx: 20.0, dy: 20.0, rgb: WHITE };
const twoOut: Probe = { dx: -2.0, dy: 20.0, rgb: RED };
const sixOut: Probe = { dx: -6.0, dy: 20.0, rgb: BLACK };
const sixOutChained: Probe = { dx: -6.0, dy: 20.0, rgb: BLUE };
const twelveOut: Probe = { dx: -12.0, dy: 20.0, rgb: BLACK };
const aboveSixChained: Probe = { dx: 20.0, dy: -6.0, rgb: BLUE };

const red: Color = rgba(1.0, 0.0, 0.0, 1.0);
const blue: Color = rgba(0.0, 0.0, 1.0, 1.0);

const cases: Case[] = [
	{ name: "one outline", dpi: 1.0, scale: 1.0, steps: [outlineFilter(red, 4.0, 0.3)],
		probes: [insideSquare, twoOut, sixOut, twelveOut] },
	{ name: "outline then outline", dpi: 1.0, scale: 1.0,
		steps: [outlineFilter(red, 4.0, 0.3), outlineFilter(blue, 4.0, 0.3)],
		probes: [insideSquare, twoOut, sixOutChained, aboveSixChained, twelveOut] },
	{ name: "outline then outline at dpi 1.5, scale 0.5", dpi: 1.5, scale: 0.5,
		steps: [outlineFilter(red, 4.0, 0.3), outlineFilter(blue, 4.0, 0.3)],
		probes: [insideSquare, twoOut, sixOutChained, aboveSixChained, twelveOut] },
];

const WIDTH: int32 = 256;
const HEIGHT: int32 = 160;
let index: int32 = 0;
let stage: int32 = 0;
let scene: Scene2D | null = null;

function fail(message: string): void {
	console.log(`FAIL filterChain ${cases[index].name}: ${message}`);
	voidCaptureExit(1);
}

function build(c: Case): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const square = s.rect(SQUARE, SQUARE, rgba(1.0, 1.0, 1.0, 1.0)).at(SQUARE_X, SQUARE_Y);
	let steps: Vec<Filter> = [];
	for (const f of c.steps) { steps.push(f.withResolutionScale(c.scale)); }
	square.setFilters(steps);
	s.add(square);
	return s;
}

function init(): void {
	gfxSetup();
	setup2d();
	if (voidCaptureBackend() == 0) {
		console.log("SKIP this build has no readback path");
		voidCaptureExit(3);
	}
}

function channel(pixel: int64, shift: int32): int32 {
	return ((pixel >> (shift as int64)) & 255) as int32;
}

function check(c: Case): void {
	if (voidCaptureWidth(0) != WIDTH || voidCaptureHeight(0) != HEIGHT) {
		fail("capture size differs from the window");
	}
	for (const p of c.probes) {
		const x: int32 = ((SQUARE_X + p.dx) * c.dpi) as int32;
		const y: int32 = ((SQUARE_Y + p.dy) * c.dpi) as int32;
		const pixel: int64 = voidCapturePixel(0, x, y);
		const want: int32 = p.rgb;
		for (let k: int32 = 0; k < 3; k++) {
			const got: int32 = channel(pixel, 24 - 8 * k);
			const expected: int32 = (want >> (16 - 8 * k)) & 255;
			const d: int32 = got > expected ? got - expected : expected - got;
			if (d > TOLERANCE) {
				fail(`pixel at offset ${p.dx},${p.dy} is ${pixel >> 8}, expected ${want}`);
			}
		}
	}
	console.log(`PASS ${c.name}`);
}

function frame(): void {
	const c = cases[index];
	if (stage == 0) { scene = build(c); }
	const s = scene;
	if (s === null) { return; }
	s.presentAt(c.dpi);
	if (stage == 1) {
		if (voidCaptureGrab(0) == 0) { fail("readback failed"); }
		check(c);
		index++;
		stage = 0;
		if (index == (cases.length as int32)) {
			console.log("PASS filterChain");
			voidCaptureExit(0);
		}
		return;
	}
	stage++;
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
