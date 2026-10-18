import { Scene2D, NodeRef } from "../../src/void2d/node";
import { add, paint, close, presentAt } from "../../src/void2d/scene";
import { xForIndex, indexAt, textWidth, textHeight } from "../../src/void2d/render";
import { FontId, addFont, fontFace } from "../../src/void2d/font";
import {
	LabelText, TextRegime, labelTexts, glyphAtlas, glyphPageHandle,
	glyphRasterizations, glyphRefusals, setSdfRegime,
} from "../../src/void2d/labelText";
import { PageKind } from "../../src/void2d/glyphAtlas";
import { void2dGlyphPageTexel } from "../../src/void2d/glyph.h";
import { gfxSetup } from "../../src/sokol/gpu";
import { setup2d, frameEnd, setTextGamma } from "../../src/void2d/draw";
import { Color, rgba } from "../../src/void2d/types";
import {
	voidCaptureBackend, voidCaptureRenderer, voidCaptureEnvInt,
	voidCaptureGrab, voidCaptureWidth, voidCaptureHeight, voidCaptureSlotsDiffer,
	voidCaptureUniform, voidCapturePixel, voidCaptureWritePng, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, samples: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const DPI: float32 = (voidCaptureEnvInt("FONT_PANEL_DPI100", 150) as float32) / 100.0;
const WIDTH: int32 = 576;
const HEIGHT: int32 = 224;
const PIXEL_WIDTH: int32 = ((WIDTH as float32) * DPI) as int32;
const PIXEL_HEIGHT: int32 = ((HEIGHT as float32) * DPI) as int32;
const SAMPLE: string = "iIl1| 0Oo8 g@ AV fi ->";
const CARET_INDEX: int32 = 6;
const DARK: Color = rgba(0.05, 0.06, 0.08, 1.0);
const LIGHT: Color = rgba(0.94, 0.95, 0.98, 1.0);

struct PanelLabel {
	node: NodeRef;
	font: int32;
	row: int32;
	column: int32;
	regime: TextRegime;
}

interface Panel {
	scene: Scene2D;
	labels: Vec<PanelLabel>;
}

struct LabelSnapshot {
	width: float32;
	height: float32;
	caretX: float32;
	hit: int32;
	glyphs: int32;
	tileChecksum: uint64;
}

function require(ok: boolean, message: string): void {
	if (!ok) {
		console.log(`FAIL fontPanel: ${message}`);
		unreachable;
	}
}

function loadFont(path: string): FontId {
	const loaded = addFont(path);
	if (loaded.ok) { return loaded.value; }
	console.log(`FAIL fontPanel font ${path}: ${loaded.error.toString()}`);
	unreachable;
}

function buildPanel(): Panel {
	require(DPI > 0.0, "DPI must be positive");
	setSdfRegime(true);
	const fonts: Vec<FontId> = [loadFont("assets/font.ttf"),
		loadFont("tests/fonts/cascadiaSubset.ttf")];
	const s = Scene2D.create(DARK);
	let labels: Vec<PanelLabel> = [];
	for (let font: int32 = 0; font < 2; font++) {
		for (let origin: int32 = 0; origin < 2; origin++) {
			const row: int32 = font * 2 + origin;
			const y: float32 = (row * 48) as float32;
			const background: Color = origin == 0 ? DARK : LIGHT;
			const color: Color = origin == 0 ? LIGHT : DARK;
			s.add(s.rect(WIDTH as float32, 48.0, background).at(0.0, y));
			for (let column: int32 = 0; column < 2; column++) {
				const shift: float32 = (origin == 0 ? 0.0 : 0.5) as float32;
				const x: float32 = 16.0 + ((column * 288) as float32) + shift;
				const n = s.label(SAMPLE, 13.0, color).setFont(fonts[font]).at(x, y + 12.0);
				if (column == 1) { n.setRotation(0.03); }
				s.add(n);
				labels.push({ node: n, font: font, row: row, column: column,
					regime: column == 0 ? TextRegime.PixelExact : TextRegime.Sdf });
			}
		}
	}
	return { scene: s, labels: labels };
}

function entry(n: NodeRef): LabelText { return labelTexts[n.scene.payloads[n.id.index]]; }

function hasMode(text: LabelText, regime: TextRegime): boolean {
	if (!text.placedValid || text.refused != 0 || text.regime != regime ||
		text.coverageInSdf || text.placed.length == 0) { return false; }
	const kind: PageKind = regime == TextRegime.Sdf ? PageKind.Sdf : PageKind.Coverage;
	let visible: int32 = 0;
	for (const p of text.placed) {
		if (p.w <= 0.0 || p.h <= 0.0) { continue; }
		if (glyphAtlas.pageKind(p.page) != kind) { return false; }
		visible = visible + 1;
	}
	return visible > 0;
}

function checksum(text: LabelText): uint64 {
	let sum: uint64 = 0;
	let position: uint64 = 1;
	for (const p of text.placed) {
		const tile = glyphAtlas.tile(p.tile);
		if (tile.width == 0 || tile.height == 0) { continue; }
		const handle: int32 = glyphPageHandle(tile.page) as int32;
		for (let y: int32 = 0; y < tile.height; y++) {
			for (let x: int32 = 0; x < tile.width; x++) {
				const value: uint64 =
					void2dGlyphPageTexel(handle, tile.x + x, tile.y + y) as uint64;
				sum = sum + value * position;
				position = position + 1;
			}
		}
	}
	return sum;
}

function inspect(panel: Panel): Vec<LabelSnapshot> {
	let snapshots: Vec<LabelSnapshot> = [];
	for (const row of panel.labels) {
		const text = entry(row.node);
		require(hasMode(text, row.regime), `font ${row.font} row ${row.row} wrong regime/page`);
		require(text.style.size == 13.0, "logical font size changed");
		for (const glyph of text.layout.glyphs) {
			require(glyph.glyph != 0 && glyph.face == fontFace(text.style.font),
				"sample selected .notdef or an unintended fallback face");
		}
		const tileChecksum: uint64 = checksum(text);
		require(tileChecksum > 0, "real glyph tiles are empty");
		const caretX: float32 = row.node.xForIndex(CARET_INDEX);
		const hit: int32 = row.node.indexAt(caretX, row.node.textHeight() * 0.5);
		require(hit == CARET_INDEX, "UTF-16 caret does not round-trip");
		snapshots.push({ width: row.node.textWidth(), height: row.node.textHeight(),
			caretX: caretX, hit: hit, glyphs: text.placed.length as int32,
			tileChecksum: tileChecksum });
	}
	for (let i: int32 = 0; i < (snapshots.length as int32); i = i + 4) {
		for (let j: int32 = 1; j < 4; j++) {
			require(snapshots[i].width == snapshots[i + j].width &&
				snapshots[i].height == snapshots[i + j].height &&
				snapshots[i].caretX == snapshots[i + j].caretX,
				"origin or SDF transform changed logical metrics");
		}
	}
	return snapshots;
}

function same(a: Readonly<Span<LabelSnapshot>>, b: Readonly<Span<LabelSnapshot>>): boolean {
	if (a.length != b.length) { return false; }
	for (let i: int32 = 0; i < (a.length as int32); i++) {
		if (a[i] != b[i]) { return false; }
	}
	return true;
}

function matchesBackend(expected: int32, actual: int32): boolean {
	return (expected == 1 || expected == 4) && expected == actual;
}

test "font panel refuses missing, generic GL and mismatched native backends" {
	assert matchesBackend(1, 1) && matchesBackend(4, 4);
	assert !matchesBackend(0, 0) && !matchesBackend(2, 2) && !matchesBackend(3, 3);
	assert !matchesBackend(1, 4) && !matchesBackend(4, 1);
}

function cpuFrame(panel: Panel): void {
	panel.scene.paint(WIDTH as float32, HEIGHT as float32, DPI);
	frameEnd();
	panel.scene.clearChanges();
	panel.scene.retryRefused();
}

test "13px real Inter and Cascadia at fractional DPI select coverage and genuine SDF" {
	const panel = buildPanel();
	defer panel.scene.close();
	defer setSdfRegime(false);
	cpuFrame(panel);
	const snapshots = inspect(panel);
	assert snapshots.length == 8;
	for (const row of panel.labels) {
		const other: TextRegime = row.regime == TextRegime.Sdf ?
			TextRegime.PixelExact : TextRegime.Sdf;
		assert !hasMode(entry(row.node), other);
	}
}

test "13px real-font warm replay keeps logical metrics and raw tiles without rasterizing" {
	const panel = buildPanel();
	defer panel.scene.close();
	defer setSdfRegime(false);
	cpuFrame(panel);
	const cold = inspect(panel);
	const rasterized: int32 = glyphRasterizations();
	const generated: int32 = glyphAtlas.generations;
	const refused: int32 = glyphRefusals();
	cpuFrame(panel);
	const warm = inspect(panel);
	assert same(cold, warm);
	assert glyphRasterizations() == rasterized;
	assert glyphAtlas.generations == generated;
	assert glyphRefusals() == refused;
}

let live: Panel | null = null;
let cold: Vec<LabelSnapshot> = [];
let rasterized: int32 = 0;
let generated: int32 = 0;
let stage: int32 = 0;

function init(): void {
	const expected: int32 = voidCaptureEnvInt("FONT_PANEL_BACKEND", 0);
	const actual: int32 = voidCaptureBackend();
	require(matchesBackend(expected, actual), `expected backend ${expected}, actual ${actual}`);
	gfxSetup();
	setup2d();
	setTextGamma(1.8, 1.0);
	live = buildPanel();
}

function frame(): void {
	const panel = live;
	if (panel === null) { require(false, "panel was not initialized"); return; }
	panel.scene.presentAt(DPI);
	const seen = inspect(panel);
	if (stage == 0) {
		cold = seen;
		rasterized = glyphRasterizations();
		generated = glyphAtlas.generations;
	} else {
		require(same(cold, seen), "warm replay changed metrics or raw tiles");
		require(glyphRasterizations() == rasterized && glyphAtlas.generations == generated,
			"warm replay rasterized or generated a glyph");
	}
	if (stage == 1) { voidCaptureGrab(0); }
	if (stage == 2) {
		voidCaptureGrab(1);
		require(voidCaptureWidth(1) == PIXEL_WIDTH && voidCaptureHeight(1) == PIXEL_HEIGHT,
			"framebuffer differs from requested physical size");
		require(voidCaptureUniform(1) == 0 && voidCaptureSlotsDiffer() == 0,
			"warm captures are blank or not byte-identical");
		for (let i: int32 = 0; i < (panel.labels.length as int32); i++) {
			const row = panel.labels[i];
			const background: Color = row.row % 2 == 0 ? DARK : LIGHT;
			let ink: int32 = 0;
			for (let y: int32 = (((row.row * 48 + 4) as float32) * DPI) as int32;
				y < (((row.row * 48 + 44) as float32) * DPI) as int32; y++) {
				for (let x: int32 = (((row.column * 288 + 8) as float32) * DPI) as int32;
					x < (((row.column * 288 + 280) as float32) * DPI) as int32; x++) {
					const pixel: int64 = voidCapturePixel(1, x, y);
					require(pixel >= 0, "pixel read fell outside capture");
					const red: float32 = ((pixel >> 24) & 255) as float32;
					const green: float32 = ((pixel >> 16) & 255) as float32;
					const blue: float32 = ((pixel >> 8) & 255) as float32;
					const delta: float64 = Math.abs(red - background.r * 255.0) +
						Math.abs(green - background.g * 255.0) +
						Math.abs(blue - background.b * 255.0);
					if (delta > 6.0) { ink++; }
				}
			}
			require(ink > 20, `font ${row.font} row ${row.row} has no visible text`);
			const snap = seen[i];
			console.log(`FONT_PANEL ${i} font ${row.font} regime ${row.regime as int32} ` +
				`dpi ${DPI} glyphs ${snap.glyphs} width ${snap.width} caret ${snap.caretX} ` +
				`tileChecksum ${snap.tileChecksum} ink ${ink}`);
		}
		const backend: int32 = voidCaptureBackend();
		const path: string = `out/fontPanel-${backend}-${PIXEL_WIDTH}.png`;
		require(voidCaptureWritePng(1, path) != 0, "PNG write failed");
		console.log(`RENDERER ${voidCaptureRenderer()}`);
		console.log(`PASS fontPanel ${backend} ${PIXEL_WIDTH}x${PIXEL_HEIGHT} dpi ${DPI}`);
		panel.scene.close();
		voidCaptureExit(0);
	}
	stage = stage + 1;
}

when (!testBuild) { voidRunConfigured(PIXEL_WIDTH, PIXEL_HEIGHT, 1, 0, init, frame); }
