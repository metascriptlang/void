import {
	AtlasError,
	GlyphAtlas,
	GlyphTile,
	GlyphPage,
	GlyphPageHandle,
	PageKind,
	GLYPH_PAGE_SIZE,
	quantizeX,
	snapBaseline,
} from "./glyphAtlas";
import {
	Align,
	TextLayout,
	TextStyle,
	TextRun,
	LaidGlyph,
	LineBox,
	LineOptions,
	ShapedText,
	NO_GLYPH,
	NO_RUN,
	PLAIN_LINES,
	shapeText,
	wrapText,
} from "./textLayout";
import {
	ColourGlyph,
	ColourTileBox,
	decorationMetrics,
	hasColourTables,
	colourTileBox,
} from "./face";
import { DEFAULT_FONT, fontFace } from "./font";
import { Transform2D, Color } from "./types";

when (voidSdfText) {
	import { acquireSdf } from "./glyphAtlas";
	import { SDF_EM } from "./textSdf";
}

when (voidColourEmoji) {
	import { acquireColour, colourKey } from "./glyphAtlas";
}

export const NO_LABEL_TEXT: int32 = -1;
const MAX_GLYPH_PAGES: int32 = 16;

export enum TextRegime {
	PixelExact,
	Sdf,
	Bitmap,
}

export struct PlacedGlyph {
	tile: int32;
	page: GlyphPage;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	u0: float32;
	v0: float32;
	u1: float32;
	v1: float32;
	run: int32;
}

struct PlacementKey {
	a: float32;
	b: float32;
	c: float32;
	d: float32;
	scale: float32;
	fracX: float32;
	fracY: float32;
}

const NO_PLACEMENT_KEY: PlacementKey = {
	a: 0.0, b: 0.0, c: 0.0, d: 0.0, scale: 0.0, fracX: 0.0, fracY: 0.0,
};

export enum DecorationKind {
	Background,
	Underline,
	WavyUnderline,
	Strikethrough,
}

export struct Decoration {
	kind: DecorationKind;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	color: Color;
}

export interface LabelText {
	text: string;
	stale: boolean;
	layout: TextLayout;
	style: TextStyle;
	placed: Vec<PlacedGlyph>;
	placedValid: boolean;
	coverageInSdf: boolean;
	colourGlyphs: int32;
	regime: TextRegime;
	key: PlacementKey;
	refused: int32;
	runs: Vec<TextRun>;
	decorations: Vec<Decoration>;
	shaped: ShapedText;
	shapedText: string;
	reshape: boolean;
	options: LineOptions;
	shapingBreaks: Vec<int32>;
	selectionStart: int32;
	selectionLength: int32;
	selectionColor: Color;
	cursorIndex: int32;
	cursorColor: Color;
	cursorBlinkTime: float32;
	blinkClock: float32;
	rowsXMax: float32;
}

export const NO_CURSOR: int32 = -1;
export const CURSOR_WIDTH: float32 = 2.0;
export const CURSOR_BLINK_TIME: float32 = 0.5;

export const glyphAtlas: GlyphAtlas = GlyphAtlas.create(GLYPH_PAGE_SIZE, MAX_GLYPH_PAGES);
export let labelTexts: Vec<LabelText> = [];
let freeLabelTexts: Vec<int32> = [];
let refusedGlyphs: int32 = 0;
let refusalReports: int32 = 0;

export function firstGlyphPageHandle(): GlyphPageHandle {
	return glyphAtlas.ensurePage();
}

export function glyphPageHandle(page: GlyphPage): GlyphPageHandle {
	return glyphAtlas.pageHandle(page);
}

export function glyphPageKind(page: GlyphPage): PageKind {
	return glyphAtlas.pageKind(page);
}

export function beginGlyphFrame(frame: int32): void {
	glyphAtlas.beginFrame(frame);
}

export function markGlyphPageDrawn(page: GlyphPage): void {
	glyphAtlas.markDrawn(page);
}

export function glyphRasterizations(): int32 {
	return glyphAtlas.rasterizations;
}

export function glyphRefusals(): int32 {
	return refusedGlyphs;
}

export function glyphRefusalReports(): int32 {
	return refusalReports;
}

function emptyLayout(): TextLayout {
	return {
		glyphs: new Array(0),
		lines: new Array(0),
		ascent: 0.0,
		descent: 0.0,
		lineHeight: 0.0,
		width: 0.0,
		height: 0.0,
		decoration: {
			underlineTop: 0.0,
			underlineThickness: 0.0,
			strikethroughTop: 0.0,
			strikethroughThickness: 0.0,
		},
	};
}

export function allocateLabelText(): int32 {
	const style: TextStyle = {
		font: DEFAULT_FONT,
		size: 0.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	};
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const entry: LabelText = {
		text: "",
		stale: true,
		layout: emptyLayout(),
		style: style,
		placed: new Array(0),
		placedValid: false,
		coverageInSdf: false,
		colourGlyphs: 0,
		regime: TextRegime.Bitmap,
		key: NO_PLACEMENT_KEY,
		refused: 0,
		runs: new Array(0),
		decorations: new Array(0),
		shaped: shapeText("", style, noRuns, noBreaks),
		shapedText: "",
		reshape: true,
		options: PLAIN_LINES,
		shapingBreaks: new Array(0),
		selectionStart: 0,
		selectionLength: 0,
		selectionColor: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
		cursorIndex: NO_CURSOR,
		cursorColor: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
		cursorBlinkTime: CURSOR_BLINK_TIME,
		blinkClock: 0.0,
		rowsXMax: 0.0,
	};
	if ((freeLabelTexts.length as int32) > 0) {
		const index: int32 = freeLabelTexts.pop();
		labelTexts[index] = entry;
		return index;
	}
	labelTexts.push(entry);
	return (labelTexts.length as int32) - 1;
}

function releasePlacement(entry: LabelText): void {
	for (const p of entry.placed) { glyphAtlas.release(p.tile); }
	entry.placed = new Array(0);
	entry.placedValid = false;
}

export function releaseLabelGlyphs(index: int32): void {
	releasePlacement(labelTexts[index]);
}

export function releaseLabelText(index: int32): void {
	releasePlacement(labelTexts[index]);
	labelTexts[index].layout = emptyLayout();
	freeLabelTexts.push(index);
}

function shapeStale(entry: LabelText, text: string, style: TextStyle): boolean {
	const shapedWith: TextStyle = entry.shaped.style;
	return entry.reshape || !text.equals(entry.shapedText) || style.font != shapedWith.font ||
		style.size != shapedWith.size || style.letterSpacing != shapedWith.letterSpacing;
}

// A width, alignment or line-option change wraps the shaped text again; only a change to what
// is shaped looks glyphs up (T1 "a width change lays out no glyph again").
export function shapeLabel(index: int32, text: string, style: TextStyle): void {
	const entry: LabelText = labelTexts[index];
	releasePlacement(entry);
	if (shapeStale(entry, text, style)) {
		entry.shaped = shapeText(text, style, entry.runs, entry.shapingBreaks);
		entry.shapedText = text;
		entry.reshape = false;
	}
	entry.style = style;
	entry.layout = wrapText(entry.shaped, style, entry.options);
	entry.decorations = entry.layout.runDecorations(entry.runs, style.size);
}

// GPUI's segments (line.rs:790-937): one per run per line; the backgrounds fill the line box,
// underline and strikethrough sit where the run's face puts them.
function runDecorations(
	this layout: TextLayout,
	runs: Readonly<Span<TextRun>>,
	size: float32,
): Vec<Decoration> {
	let out: Vec<Decoration> = new Array(0);
	if ((runs.length as int32) == 0) { return out; }
	for (let li = 0; li < (layout.lines.length as int32); li++) {
		layout.lineDecorations(runs, size, li, DecorationKind.Background, out);
		layout.lineDecorations(runs, size, li, DecorationKind.Underline, out);
		layout.lineDecorations(runs, size, li, DecorationKind.Strikethrough, out);
	}
	return out;
}

function lineDecorations(
	this layout: TextLayout,
	runs: Readonly<Span<TextRun>>,
	size: float32,
	li: int32,
	slot: DecorationKind,
	ref out: Vec<Decoration>,
): void {
	const line: LineBox = layout.lines[li];
	const end: int32 = line.firstGlyph + line.glyphCount;
	let open: boolean = false;
	let openKind: DecorationKind = slot;
	let openX: float32 = 0.0;
	let openRight: float32 = 0.0;
	let openY: float32 = 0.0;
	let openH: float32 = 0.0;
	let openColor: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	let k: int32 = line.firstGlyph;
	while (k < end) {
		const run: int32 = layout.glyphs[k].run;
		const x0: float32 = layout.glyphs[k].x;
		let last: int32 = k;
		while (last + 1 < end && layout.glyphs[last + 1].run == run) { last = last + 1; }
		const right: float32 = layout.glyphs[last].x + layout.glyphs[last].advance;
		k = last + 1;
		let color: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
		let kind: DecorationKind = slot;
		let y: float32 = line.top;
		let h: float32 = line.height;
		if (run != NO_RUN) {
			const style: TextRun = runs[run];
			const deco = decorationMetrics(fontFace(style.font), size);
			if (slot == DecorationKind.Background) {
				color = style.background;
			} else if (slot == DecorationKind.Underline) {
				color = style.underline;
				kind = style.wavy ? DecorationKind.WavyUnderline : DecorationKind.Underline;
				y = line.baseline + deco.underlineTop;
				h = deco.underlineThickness;
			} else {
				color = style.strikethrough;
				y = line.baseline + deco.strikethroughTop;
				h = deco.strikethroughThickness;
			}
		}
		const same: boolean = open && color.a > 0.0 && kind == openKind && y == openY &&
			h == openH && color.r == openColor.r && color.g == openColor.g &&
			color.b == openColor.b && color.a == openColor.a;
		if (same) {
			openRight = right;
			continue;
		}
		if (open) {
			out.push({
				kind: openKind, x: openX, y: openY, w: openRight - openX, h: openH,
				color: openColor,
			});
		}
		open = color.a > 0.0;
		openKind = kind;
		openX = x0;
		openRight = right;
		openY = y;
		openH = h;
		openColor = color;
	}
	if (open) {
		out.push({
			kind: openKind, x: openX, y: openY, w: openRight - openX, h: openH, color: openColor,
		});
	}
}

export function setLabelRuns(index: int32, runs: Readonly<Span<TextRun>>): void {
	let kept: Vec<TextRun> = new Array(0);
	for (const run of runs) { kept.push(run); }
	labelTexts[index].runs = kept;
	labelTexts[index].reshape = true;
}

export function setLabelShapingBreaks(index: int32, breaks: Readonly<Span<int32>>): void {
	let kept: Vec<int32> = new Array(0);
	for (const at of breaks) { kept.push(at); }
	labelTexts[index].shapingBreaks = kept;
	labelTexts[index].reshape = true;
}

export function setLabelLines(index: int32, options: LineOptions): void {
	labelTexts[index].options = options;
}

export function labelLines(index: int32): LineOptions {
	return labelTexts[index].options;
}

export function setLabelSelection(index: int32, start: int32, length: int32, color: Color): void {
	labelTexts[index].selectionStart = start;
	labelTexts[index].selectionLength = length;
	labelTexts[index].selectionColor = color;
}

export function setLabelCursor(index: int32, at: int32, color: Color): void {
	labelTexts[index].cursorIndex = at;
	labelTexts[index].cursorColor = color;
	labelTexts[index].blinkClock = 0.0;
}

export function setLabelBlinkTime(index: int32, seconds: float32): void {
	labelTexts[index].cursorBlinkTime = seconds;
	labelTexts[index].blinkClock = 0.0;
}

export function advanceBlink(index: int32, dt: float32): void {
	labelTexts[index].blinkClock = labelTexts[index].blinkClock + dt;
}

// h2d's TextInput blink (h2d/TextInput.hx `cursorBlinkTime`): on for one period, off for the next.
export function cursorShown(entry: LabelText): boolean {
	if (entry.cursorIndex == NO_CURSOR) { return false; }
	if (entry.cursorBlinkTime <= 0.0) { return true; }
	const periods: int32 = Math.floor(entry.blinkClock / entry.cursorBlinkTime) as int32;
	return periods % 2 == 0;
}

export function isPixelExact(world: Transform2D): boolean {
	return world.b == 0.0 && world.c == 0.0 && world.a == world.d && world.a > 0.0;
}

let sdfRegime: boolean = false;
const IDENTITY_NOISE: float32 = 0.00001;

export function setSdfRegime(on: boolean): void {
	when (voidSdfText) {
		sdfRegime = on;
	} else {
		if (on) {
			console.log("void2d: the SDF text regime was asked for without -d:voidSdfText");
			unreachable;
		}
	}
}

export function regimeOf(world: Transform2D): TextRegime {
	when (voidSdfText) {
		if (sdfRegime) {
			const translationOnly: boolean =
				Math.abs(world.a - 1.0) < IDENTITY_NOISE &&
				Math.abs(world.d - 1.0) < IDENTITY_NOISE &&
				Math.abs(world.b) < IDENTITY_NOISE && Math.abs(world.c) < IDENTITY_NOISE;
			return translationOnly ? TextRegime.PixelExact : TextRegime.Sdf;
		}
	}
	return isPixelExact(world) ? TextRegime.PixelExact : TextRegime.Bitmap;
}

function fraction(value: float32): float32 {
	return value - (Math.floor(value) as float32);
}

function placementKey(world: Transform2D, scale: float32, regime: TextRegime): PlacementKey {
	const exact: boolean = regime == TextRegime.PixelExact;
	return {
		a: world.a,
		b: world.b,
		c: world.c,
		d: world.d,
		scale: scale,
		fracX: exact ? fraction(world.tx * scale) : 0.0,
		fracY: exact ? fraction(world.ty * scale) : 0.0,
	};
}

// Early exits, not one struct compare: this runs for every label on every frame.
function placementCurrent(entry: LabelText, world: Transform2D, scale: float32): boolean {
	if (!entry.placedValid) { return false; }
	const regime: TextRegime = regimeOf(world);
	if (entry.regime != regime) { return false; }
	if (regime == TextRegime.Sdf && !entry.coverageInSdf) { return true; }
	if (entry.key.scale != scale) { return false; }
	if (entry.key.a != world.a || entry.key.b != world.b) { return false; }
	if (entry.key.c != world.c || entry.key.d != world.d) { return false; }
	if (regime != TextRegime.PixelExact) { return true; }
	return entry.key.fracX == fraction(world.tx * scale) &&
		entry.key.fracY == fraction(world.ty * scale);
}

export function uvRect(this t: GlyphTile): [float32, float32, float32, float32] {
	const size: float32 = GLYPH_PAGE_SIZE as float32;
	return [
		(t.x as float32) / size,
		(t.y as float32) / size,
		((t.x + t.width) as float32) / size,
		((t.y + t.height) as float32) / size,
	];
}

function placedGlyph(
	g: LaidGlyph,
	tileIndex: int32,
	t: GlyphTile,
	baseline: float32,
	devicePerLocal: float32,
	pixelExact: boolean,
	whole: int32,
	baselineDevice: int32,
): PlacedGlyph {
	const [u0, v0, u1, v1] = t.uvRect();
	const w: float32 = t.width as float32;
	const h: float32 = t.height as float32;
	if (pixelExact) {
		return {
			tile: tileIndex, page: t.page,
			x: (whole + t.left) as float32, y: (baselineDevice + t.top) as float32,
			w: w, h: h, u0: u0, v0: v0, u1: u1, v1: v1, run: g.run,
		};
	}
	return {
		tile: tileIndex, page: t.page,
		x: g.x + g.offsetX + (t.left as float32) / devicePerLocal,
		y: baseline + g.offsetY + (t.top as float32) / devicePerLocal,
		w: w / devicePerLocal, h: h / devicePerLocal,
		u0: u0, v0: v0, u1: u1, v1: v1, run: g.run,
	};
}

when (voidSdfText) {
	function sdfPlacedGlyph(g: LaidGlyph, baseline: float32): Result<PlacedGlyph, AtlasError> {
		const acquired = glyphAtlas.acquireSdf(g.face, g.glyph);
		if (!acquired.ok) { return Result.err(acquired.error); }
		const t: GlyphTile = glyphAtlas.tile(acquired.value);
		const [u0, v0, u1, v1] = t.uvRect();
		const k: float32 = g.size / SDF_EM;
		return Result.ok({
			tile: acquired.value, page: t.page,
			x: g.x + g.offsetX + (t.left as float32) * k,
			y: baseline + g.offsetY + (t.top as float32) * k,
			w: (t.width as float32) * k, h: (t.height as float32) * k,
			u0: u0, v0: v0, u1: u1, v1: v1, run: g.run,
		});
	}
} else {
	function sdfPlacedGlyph(g: LaidGlyph, baseline: float32): Result<PlacedGlyph, AtlasError> {
		console.log("void2d: a label chose the SDF text regime in a build without -d:voidSdfText");
		unreachable;
	}
}

const NO_COLOUR_BOX: ColourTileBox = {
	left: 0, top: 0, right: 0, bottom: 0, glyph: ColourGlyph.Absent, ppem: 0,
};

when (voidColourEmoji) {
	function colourBoxOf(g: LaidGlyph, sizePx: float32): ColourTileBox {
		if (!hasColourTables(g.face)) { return NO_COLOUR_BOX; }
		return colourTileBox(g.face, g.glyph, sizePx);
	}

	function colourPlacedGlyph(
		g: LaidGlyph,
		box: ColourTileBox,
		sizePx: float32,
		baseline: float32,
		devicePerLocal: float32,
		pixelExact: boolean,
		fracX: float32,
		fracY: float32,
	): Result<PlacedGlyph, AtlasError> {
		const acquired = glyphAtlas.acquireColour(
			colourKey(g.face, g.glyph, sizePx),
			box.right - box.left, box.bottom - box.top, box.left, box.top,
		);
		if (!acquired.ok) { return Result.err(acquired.error); }
		let whole: int32 = 0;
		let baselineDevice: int32 = 0;
		if (pixelExact) {
			whole = snapBaseline(fracX + (g.x + g.offsetX) * devicePerLocal);
			baselineDevice = snapBaseline(fracY + (baseline + g.offsetY) * devicePerLocal);
		}
		return Result.ok(placedGlyph(
			g, acquired.value, glyphAtlas.tile(acquired.value), baseline, devicePerLocal,
			pixelExact, whole, baselineDevice,
		));
	}
} else {
	function colourBoxOf(g: LaidGlyph, sizePx: float32): ColourTileBox {
		return NO_COLOUR_BOX;
	}

	function colourPlacedGlyph(
		g: LaidGlyph,
		box: ColourTileBox,
		sizePx: float32,
		baseline: float32,
		devicePerLocal: float32,
		pixelExact: boolean,
		fracX: float32,
		fracY: float32,
	): Result<PlacedGlyph, AtlasError> {
		console.log("void2d: a label placed a colour glyph in a build without -d:voidColourEmoji");
		unreachable;
	}
}

export function placeLabel(index: int32, world: Transform2D, scale: float32): LabelText {
	const entry: LabelText = labelTexts[index];
	if (placementCurrent(entry, world, scale)) { return entry; }
	releasePlacement(entry);
	const regime: TextRegime = regimeOf(world);
	const pixelExact: boolean = regime == TextRegime.PixelExact;
	const linear: float32 = pixelExact
		? world.a
		: Math.sqrt(Math.abs(world.a * world.d - world.b * world.c)) as float32;
	const devicePerLocal: float32 = linear * scale;
	const fracX: float32 = fraction(world.tx * scale);
	const fracY: float32 = fraction(world.ty * scale);
	let placed: Vec<PlacedGlyph> = new Array(0);
	let refused: int32 = 0;
	let refusal: string = "";
	let coverageInSdf: boolean = false;
	let colourGlyphs: int32 = 0;
	if (devicePerLocal > 0.0 || regime == TextRegime.Sdf) {
		for (const g of entry.layout.glyphs) {
			if (g.glyph == NO_GLYPH) { continue; }
			const baseline: float32 = entry.layout.lines[g.line].baseline;
			if (devicePerLocal > 0.0) {
				const sizePx: float32 = g.size * devicePerLocal;
				const colourBox: ColourTileBox = colourBoxOf(g, sizePx);
				if (colourBox.glyph == ColourGlyph.Refused) {
					refused = refused + 1;
					refusal = AtlasError.ColourRefused.toString();
					continue;
				}
				if (colourBox.glyph == ColourGlyph.Present) {
					const coloured = colourPlacedGlyph(
						g, colourBox, sizePx, baseline, devicePerLocal, pixelExact, fracX, fracY,
					);
					if (!coloured.ok) {
						refused = refused + 1;
						refusal = coloured.error.toString();
						continue;
					}
					placed.push(coloured.value);
					colourGlyphs = colourGlyphs + 1;
					coverageInSdf = coverageInSdf || regime == TextRegime.Sdf;
					continue;
				}
			}
			if (regime == TextRegime.Sdf) {
				const sdf = sdfPlacedGlyph(g, baseline);
				if (sdf.ok) {
					placed.push(sdf.value);
					continue;
				}
				if (sdf.error != AtlasError.SdfCubicOutline || devicePerLocal <= 0.0) {
					refused = refused + 1;
					refusal = sdf.error.toString();
					continue;
				}
				coverageInSdf = true;
			}
			let variant: int32 = 0;
			let whole: int32 = 0;
			let baselineDevice: int32 = 0;
			if (pixelExact) {
				const q = quantizeX(fracX + (g.x + g.offsetX) * devicePerLocal);
				variant = q.variant;
				whole = q.whole;
				baselineDevice = snapBaseline(fracY + (baseline + g.offsetY) * devicePerLocal);
			}
			const acquired = glyphAtlas.acquire({
				kind: PageKind.Coverage,
				face: g.face, glyph: g.glyph, sizePx: g.size * devicePerLocal, variant: variant,
			});
			if (!acquired.ok) {
				refused = refused + 1;
				refusal = acquired.error.toString();
				continue;
			}
			const tileIndex: int32 = acquired.value;
			const t: GlyphTile = glyphAtlas.tile(tileIndex);
			placed.push(placedGlyph(
				g, tileIndex, t, baseline, devicePerLocal, pixelExact, whole, baselineDevice,
			));
		}
	}
	refusedGlyphs = refusedGlyphs + refused;
	if (refused > 0 && refused != entry.refused) {
		refusalReports = refusalReports + 1;
		console.log(
			`void2d: ${refused} of ${entry.layout.glyphs.length} glyphs of a label are not ` +
			`drawn, the glyph atlas refused them (${refusal})`,
		);
	}
	entry.refused = refused;
	entry.placed = placed;
	entry.placedValid = refused == 0;
	entry.coverageInSdf = coverageInSdf;
	entry.colourGlyphs = colourGlyphs;
	entry.regime = regime;
	entry.key = placementKey(world, scale, regime);
	return entry;
}
