import {
	GlyphAtlas,
	GlyphTile,
	GlyphPage,
	GlyphPageHandle,
	GLYPH_PAGE_SIZE,
	quantizeX,
	snapBaseline,
} from "./glyphAtlas";
import {
	Align,
	TextLayout,
	TextStyle,
	TextRun,
	LineBox,
	LineOptions,
	ShapedText,
	NO_GLYPH,
	NO_RUN,
	PLAIN_LINES,
	shapeText,
	wrapText,
} from "./textLayout";
import { decorationMetrics } from "./face";
import { DEFAULT_FONT, fontFace } from "./font";
import { Transform2D, Color } from "./types";

export const NO_LABEL_TEXT: int32 = -1;
const MAX_GLYPH_PAGES: int32 = 16;

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
	layout: TextLayout;
	style: TextStyle;
	placed: Vec<PlacedGlyph>;
	placedValid: boolean;
	pixelExact: boolean;
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
export const labelTexts: Vec<LabelText> = [];
const freeLabelTexts: Vec<int32> = [];
let refusedGlyphs: int32 = 0;
let refusalReports: int32 = 0;

export function firstGlyphPageHandle(): GlyphPageHandle {
	return glyphAtlas.ensurePage();
}

export function glyphPageHandle(page: GlyphPage): GlyphPageHandle {
	return glyphAtlas.pageHandle(page);
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
		layout: emptyLayout(),
		style: style,
		placed: new Array(0),
		placedValid: false,
		pixelExact: false,
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
	runs: Span<TextRun>,
	size: float32,
): Vec<Decoration> {
	const out: Vec<Decoration> = new Array(0);
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
	runs: Span<TextRun>,
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

export function setLabelRuns(index: int32, runs: Span<TextRun>): void {
	const kept: Vec<TextRun> = new Array(0);
	for (const run of runs) { kept.push(run); }
	labelTexts[index].runs = kept;
	labelTexts[index].reshape = true;
}

export function setLabelShapingBreaks(index: int32, breaks: Span<int32>): void {
	const kept: Vec<int32> = new Array(0);
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

function fraction(value: float32): float32 {
	return value - (Math.floor(value) as float32);
}

function placementKey(world: Transform2D, scale: float32): PlacementKey {
	const exact: boolean = isPixelExact(world);
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
	if (!entry.placedValid || entry.key.scale != scale) { return false; }
	if (entry.key.a != world.a || entry.key.b != world.b) { return false; }
	if (entry.key.c != world.c || entry.key.d != world.d) { return false; }
	if (!entry.pixelExact) { return true; }
	return entry.key.fracX == fraction(world.tx * scale) &&
		entry.key.fracY == fraction(world.ty * scale);
}

function uvRect(this t: GlyphTile): [float32, float32, float32, float32] {
	const size: float32 = GLYPH_PAGE_SIZE as float32;
	return [
		(t.x as float32) / size,
		(t.y as float32) / size,
		((t.x + t.width) as float32) / size,
		((t.y + t.height) as float32) / size,
	];
}

export function placeLabel(index: int32, world: Transform2D, scale: float32): LabelText {
	const entry: LabelText = labelTexts[index];
	if (placementCurrent(entry, world, scale)) { return entry; }
	releasePlacement(entry);
	const pixelExact: boolean = isPixelExact(world);
	const linear: float32 = pixelExact
		? world.a
		: Math.sqrt(Math.abs(world.a * world.d - world.b * world.c)) as float32;
	const devicePerLocal: float32 = linear * scale;
	const fracX: float32 = fraction(world.tx * scale);
	const fracY: float32 = fraction(world.ty * scale);
	const placed: Vec<PlacedGlyph> = new Array(0);
	let refused: int32 = 0;
	let refusal: string = "";
	if (devicePerLocal > 0.0) {
		for (const g of entry.layout.glyphs) {
			if (g.glyph == NO_GLYPH) { continue; }
			const baseline: float32 = entry.layout.lines[g.line].baseline;
			let variant: int32 = 0;
			let whole: int32 = 0;
			let baselineDevice: int32 = 0;
			if (pixelExact) {
				const q = quantizeX(fracX + g.x * devicePerLocal);
				variant = q.variant;
				whole = q.whole;
				baselineDevice = snapBaseline(fracY + baseline * devicePerLocal);
			}
			const acquired = glyphAtlas.acquire({
				face: g.face, glyph: g.glyph, sizePx: g.size * devicePerLocal, variant: variant,
			});
			if (!acquired.ok) {
				refused = refused + 1;
				refusal = acquired.error.toString();
				continue;
			}
			const tileIndex: int32 = acquired.value;
			const t: GlyphTile = glyphAtlas.tile(tileIndex);
			const [u0, v0, u1, v1] = t.uvRect();
			const w: float32 = t.width as float32;
			const h: float32 = t.height as float32;
			if (pixelExact) {
				placed.push({
					tile: tileIndex, page: t.page,
					x: (whole + t.left) as float32, y: (baselineDevice + t.top) as float32,
					w: w, h: h, u0: u0, v0: v0, u1: u1, v1: v1, run: g.run,
				});
			} else {
				placed.push({
					tile: tileIndex, page: t.page,
					x: g.x + (t.left as float32) / devicePerLocal,
					y: baseline + (t.top as float32) / devicePerLocal,
					w: w / devicePerLocal, h: h / devicePerLocal,
					u0: u0, v0: v0, u1: u1, v1: v1, run: g.run,
				});
			}
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
	entry.pixelExact = pixelExact;
	entry.key = placementKey(world, scale);
	return entry;
}
