import { env } from "std/process";
import { gfxSetup } from "../../src/host/gpu";
import { beginScreenPassWith, endPass, commit } from "../../src/gpu/door";
import { Texture } from "../../src/gpu/texture";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { add } from "../../src/void2d/scene";
import { setup2d, droppedFrames } from "../../src/void2d/draw";
import { FontId, addFont, addFallbackFont } from "../../src/void2d/font";
import {
	LabelText, labelTexts, glyphAtlas, glyphRasterizations, glyphRefusals, TextRegime,
} from "../../src/void2d/labelText";
import { PageKind } from "../../src/void2d/glyphAtlas";
import {
	COMMAND_FLOATS, CMD_KIND, CMD_SAMPLER, CommandKind, SOURCE_PREMULTIPLIED,
} from "../../src/void2d/displayList";
import { rgba, tile } from "../../src/void2d/types";
import { void2dGlyphPageTexelRgba } from "../../src/void2d/glyph";
import {
	voidCaptureBackend, voidCaptureRenderer, voidCaptureEnvInt, voidCapturePixel,
	voidCaptureGrab, voidCaptureWidth, voidCaptureHeight, voidCaptureSlotsDiffer,
	voidCaptureWritePng, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 384;
const HEIGHT: int32 = 96;
const DPI: int32 = voidCaptureEnvInt("COLOUR_SAMPLER_DPI", 1);
const MUTANT: int32 = voidCaptureEnvInt("COLOUR_SAMPLER_MUTANT", 0);
const ZOOMS: float32[] = [1.37, 0.63];
const MAX_FILTER_ERROR: float64 = 2.0;

struct SamplerRow {
	node: NodeRef;
	origin: float32;
}

interface SamplerPanel {
	scene: Scene2D;
	texture: Texture;
	rows: Vec<SamplerRow>;
}

function channel(pixel: uint32, index: int32): float64 {
	return ((pixel >> ((index * 8) as uint32)) & 255) as float64;
}

function bilinear(
	a: uint32, b: uint32, c: uint32, d: uint32, x: float64, y: float64, lane: int32,
): float64 {
	const top: float64 = channel(a, lane) * (1.0 - x) + channel(b, lane) * x;
	const bottom: float64 = channel(c, lane) * (1.0 - x) + channel(d, lane) * x;
	return top * (1.0 - y) + bottom * y;
}

test "RGBA mirror lanes are bytes, not capture-order channels" {
	assert channel(0x80402010, 0) == 16.0;
	assert channel(0x80402010, 1) == 32.0;
	assert channel(0x80402010, 2) == 64.0;
	assert channel(0x80402010, 3) == 128.0;
}

test "bilinear colour oracle holds corners and the four-texel midpoint" {
	assert bilinear(0, 255, 255, 0, 0.0, 0.0, 0) == 0.0;
	assert bilinear(0, 255, 255, 0, 1.0, 0.0, 0) == 255.0;
	assert bilinear(0, 255, 255, 0, 0.5, 0.5, 0) == 127.5;
	assert bilinear(0x80402010, 0x80402010, 0x80402010, 0x80402010,
		0.25, 0.75, 3) == 128.0;
}

function fail(message: string): void {
	console.log(`FAIL colourSampler: ${message}`);
	voidCaptureExit(1);
}

function require(ok: boolean, message: string): void {
	if (!ok) { fail(message); }
}

function font(): FontId {
	const loaded = addFont("assets/font.ttf");
	if (loaded.ok) {
		addFallbackFont(loaded.value, "tests/fonts/NotoColorEmoji-subset.ttf");
		return loaded.value;
	}
	fail(`font load ${loaded.error.toString()}`);
	unreachable;
}

function checker(): Texture {
	let pixels: Vec<uint32> = [];
	for (let y: int32 = 0; y < 4; y++) {
		for (let x: int32 = 0; x < 4; x++) {
			pixels.push(((x + y) % 2 == 0 ? 0xFF000000 : 0xFFFFFFFF) as uint32);
		}
	}
	const made = Texture.fromPixels(pixels, 4, 4, false);
	if (made.ok) { return made.value; }
	fail(`checker texture ${made.error.toString()}`);
	unreachable;
}

function buildPanel(): SamplerPanel {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.defaultSmooth = false;
	const face: FontId = font();
	const texture: Texture = checker();
	let rows: Vec<SamplerRow> = [];
	for (let i: int32 = 0; i < 2; i++) {
		const origin: float32 = (8 + i * 192) as float32;
		const node = s.add(s.label("\u{1F600}", 16.0, rgba(1.0, 1.0, 1.0, 1.0))
			.setFont(face).at(origin, 8.0).setScaleX(ZOOMS[i]).setScaleY(ZOOMS[i]));
		s.add(s.sprite(tile(texture, 32.0, 32.0)).at(origin + 64.0, 8.0));
		rows.push({ node: node, origin: origin });
	}
	return { scene: s, texture: texture, rows: rows };
}

function entry(node: NodeRef): LabelText {
	return labelTexts[node.scene.payloads[node.id.index]];
}

function checkEmoji(row: SamplerRow): void {
	const text = entry(row.node);
	require(text.placedValid && text.regime == TextRegime.PixelExact &&
		text.colourGlyphs == 1 && text.placed.length == 1 && text.refused == 0,
		"expected one pixel-exact colour glyph without refusal");
	const p = text.placed[0];
	const t = glyphAtlas.tile(p.tile);
	require(glyphAtlas.pageKind(t.page) == PageKind.Rgba, "glyph is not an RGBA tile");
	const page: int32 = glyphAtlas.pageHandle(t.page) as int32;
	const left: float64 = (row.origin as float64) * (DPI as float64) + (p.x as float64);
	const top: float64 = (8 * DPI) as float64 + (p.y as float64);
	let checked: int32 = 0;
	let distinguished: int32 = 0;
	let worst: float64 = 0.0;
	for (let y: int32 = Math.ceil(top + 1.0) as int32;
		y < (Math.floor(top + (p.h as float64) - 1.0) as int32); y++) {
		for (let x: int32 = Math.ceil(left + 1.0) as int32;
			x < (Math.floor(left + (p.w as float64) - 1.0) as int32); x++) {
			const sx: float64 = ((x as float64) + 0.5 - left) *
				(t.width as float64) / (p.w as float64) - 0.5;
			const sy: float64 = ((y as float64) + 0.5 - top) *
				(t.height as float64) / (p.h as float64) - 0.5;
			const ix: int32 = Math.floor(sx) as int32;
			const iy: int32 = Math.floor(sy) as int32;
			if (ix < 0 || iy < 0 || ix + 1 >= t.width || iy + 1 >= t.height) { continue; }
			const a: uint32 = void2dGlyphPageTexelRgba(page, t.x + ix, t.y + iy);
			const b: uint32 = void2dGlyphPageTexelRgba(page, t.x + ix + 1, t.y + iy);
			const c: uint32 = void2dGlyphPageTexelRgba(page, t.x + ix, t.y + iy + 1);
			const d: uint32 = void2dGlyphPageTexelRgba(page, t.x + ix + 1, t.y + iy + 1);
			const nearest: uint32 = void2dGlyphPageTexelRgba(page,
				t.x + (Math.floor(sx + 0.5) as int32), t.y + (Math.floor(sy + 0.5) as int32));
			const pixel: int64 = voidCapturePixel(1, x, y);
			require(pixel >= 0, "emoji pixel outside capture");
			for (let lane: int32 = 0; lane < 3; lane++) {
				const expected: float64 = bilinear(a, b, c, d,
					sx - (ix as float64), sy - (iy as float64), lane);
				const shift: int64 = (24 - lane * 8) as int64;
				const actual: float64 = ((pixel >> shift) & 255) as float64;
				const delta: float64 = Math.abs(actual - expected);
				worst = Math.max(worst, delta);
				require(delta <= MAX_FILTER_ERROR,
					`bilinear pixel ${x},${y} lane ${lane}: ${actual}, expected ${expected}`);
				if (Math.abs(expected - channel(nearest, lane)) >= 8.0) { distinguished++; }
			}
			checked++;
		}
	}
	require(checked >= 16 && distinguished >= 8, "fixture cannot distinguish linear from nearest");
	console.log(`COLOUR_SAMPLE dpi ${DPI} origin ${row.origin} pixels ${checked} ` +
		`distinguished ${distinguished} maxError ${worst}`);
}

function checkNext(row: SamplerRow): void {
	const left: int32 = ((row.origin + 64.0) * (DPI as float32)) as int32;
	for (let y: int32 = 1; y < 32 * DPI - 1; y++) {
		for (let x: int32 = 1; x < 32 * DPI - 1; x++) {
			const tx: int32 = Math.floor(((x as float64) + 0.5) / ((8 * DPI) as float64)) as int32;
			const ty: int32 = Math.floor(((y as float64) + 0.5) / ((8 * DPI) as float64)) as int32;
			const expected: int64 = (tx + ty) % 2 == 0 ? 0 : 0xFFFFFF;
			const pixel: int64 = voidCapturePixel(1, left + x, 8 * DPI + y);
			require(pixel >= 0 && pixel >> 8 == expected,
				`nearest reset pixel ${left + x},${8 * DPI + y}: ${pixel >> 8}, ` +
				`expected ${expected}`);
		}
	}
}

let live: SamplerPanel | null = null;
let stage: int32 = 0;
let rasterized: int32 = 0;

function init(): void {
	const expected: int32 = voidCaptureEnvInt("COLOUR_SAMPLER_BACKEND", 0);
	const actual: int32 = voidCaptureBackend();
	require((actual == 1 || actual == 4 || actual == 5) && (expected == 0 || actual == expected),
		`expected backend ${expected}, actual ${actual}`);
	gfxSetup();
	setup2d();
	live = buildPanel();
	console.log(`BACKEND ${actual} renderer ${voidCaptureRenderer()}`);
}

function frame(): void {
	const panel = live;
	if (panel === null) { fail("panel not initialized"); return; }
	panel.scene.paint(WIDTH as float32, HEIGHT as float32, DPI as float32);
	const ctx = panel.scene.context;
	if (MUTANT != 0) {
		for (let i: int32 = 0; i < ctx.commandTotal; i++) {
			const at: int32 = i * COMMAND_FLOATS;
			if ((ctx.commands[at + CMD_KIND] as int32) != CommandKind.Draw as int32) { continue; }
			const old: int32 = ctx.commands[at + CMD_SAMPLER] as int32;
			ctx.commands[at + CMD_SAMPLER] =
				(old - old % SOURCE_PREMULTIPLIED + (MUTANT == 1 ? 0 : 2)) as float32;
		}
	}
	ctx.prepare();
	beginScreenPassWith(0.0, 0.0, 0.0, 1.0);
	ctx.drawScreen();
	endPass();
	commit();
	require(droppedFrames() == 0 && glyphRefusals() == 0, "dropped frame or glyph refusal");
	if (stage == 0) { rasterized = glyphRasterizations(); }
	else { require(glyphRasterizations() == rasterized, "warm replay rasterized a glyph"); }
	if (stage == 1) { require(voidCaptureGrab(0) == 1, "first readback failed"); }
	if (stage == 2) {
		require(voidCaptureGrab(1) == 1, "second readback failed");
		require(voidCaptureWidth(1) == WIDTH * DPI && voidCaptureHeight(1) == HEIGHT * DPI &&
			voidCaptureSlotsDiffer() == 0, "framebuffer dimensions or warm pixels changed");
		const path: string = env.get("COLOUR_SAMPLER_OUTPUT");
		if (!path.equals("")) { require(voidCaptureWritePng(1, path) == 1, "PNG write failed"); }
		for (const row of panel.rows) { checkEmoji(row); checkNext(row); }
		console.log(`PASS colourSampler backend ${voidCaptureBackend()} dpi ${DPI}: ` +
			"two zoomed RGBA glyphs match bilinear sampling; " +
			"following sprites reset to nearest");
		panel.scene.close();
		panel.texture.close();
		voidCaptureExit(0);
	}
	stage++;
}

when (!testBuild) {
	require(DPI == 1 || DPI == 2, "DPI must be 1 or 2");
	require(MUTANT >= 0 && MUTANT <= 2, "unknown sampler mutant");
	if (voidCaptureBackend() == 0) {
		console.log("SKIP colourSampler: backend has no readback path");
	} else {
		voidRunConfigured(WIDTH * DPI, HEIGHT * DPI, 1, 0, init, frame);
	}
}
