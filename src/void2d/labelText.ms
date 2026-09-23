import {
	GlyphAtlas,
	GlyphTile,
	GLYPH_PAGE_SIZE,
	quantizeX,
	snapBaseline,
} from "./glyphAtlas";
import { TextLayout, TextStyle } from "./textLayout";
import { loadFace } from "./face";
import { addFallback } from "./fontFallback";
import { Transform2D } from "./types";

export const NO_LABEL_TEXT: int32 = -1;
const MAX_GLYPH_PAGES: int32 = 16;
const DEFAULT_FONT: string = "assets/font.ttf";

export struct PlacedGlyph {
	tile: int32;
	page: int32;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	u0: float32;
	v0: float32;
	u1: float32;
	v1: float32;
}

export interface LabelText {
	layout: TextLayout;
	style: TextStyle;
	placed: Vec<PlacedGlyph>;
	placedValid: boolean;
	pixelExact: boolean;
	keyA: float32;
	keyB: float32;
	keyC: float32;
	keyD: float32;
	keyScale: float32;
	keyFracX: float32;
	keyFracY: float32;
}

export const glyphAtlas: GlyphAtlas = GlyphAtlas.create(GLYPH_PAGE_SIZE, MAX_GLYPH_PAGES);
export const labelTexts: LabelText[] = [];
const freeLabelTexts: Vec<int32> = [];
const fonts: Vec<int32> = [];
let atlasFullReported: boolean = false;

function ensureDefaultFont(): void {
	if ((fonts.length as int32) == 0) { fonts.push(loadFace(DEFAULT_FONT)); }
}

export function addFont(path: string): int32 {
	ensureDefaultFont();
	const face: int32 = loadFace(path);
	if (face < 0) { return -1; }
	fonts.push(face);
	return (fonts.length as int32) - 1;
}

export function addFallbackFont(fontId: int32, path: string): void {
	addFallback(faceFor(fontId), path);
}

export function faceFor(fontId: int32): int32 {
	ensureDefaultFont();
	if (fontId < 0 || fontId >= (fonts.length as int32)) { return fonts[0]; }
	return fonts[fontId];
}

export function firstGlyphPage(): int32 {
	return glyphAtlas.ensurePage();
}

export function glyphPageHandle(page: int32): int32 {
	return glyphAtlas.pageHandle(page);
}

export function glyphRasterizations(): int32 {
	return glyphAtlas.rasterizations;
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
	const entry: LabelText = {
		layout: emptyLayout(),
		style: { face: -1, size: 0.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0 },
		placed: new Array(0),
		placedValid: false,
		pixelExact: false,
		keyA: 0.0,
		keyB: 0.0,
		keyC: 0.0,
		keyD: 0.0,
		keyScale: 0.0,
		keyFracX: 0.0,
		keyFracY: 0.0,
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

export function shapeLabel(index: int32, text: string, style: TextStyle): TextLayout {
	const entry: LabelText = labelTexts[index];
	releasePlacement(entry);
	entry.style = style;
	entry.layout = TextLayout.layout(text, style);
	return entry.layout;
}

export function isPixelExact(world: Transform2D): boolean {
	return world.b == 0.0 && world.c == 0.0 && world.a == world.d && world.a > 0.0;
}

function fraction(value: float32): float32 {
	return value - (Math.floor(value) as float32);
}

function placementCurrent(entry: LabelText, world: Transform2D, scale: float32): boolean {
	if (!entry.placedValid || entry.keyScale != scale) { return false; }
	if (entry.keyA != world.a || entry.keyB != world.b) { return false; }
	if (entry.keyC != world.c || entry.keyD != world.d) { return false; }
	if (!entry.pixelExact) { return true; }
	return entry.keyFracX == fraction(world.tx * scale) &&
		entry.keyFracY == fraction(world.ty * scale);
}

function acquireOrReport(face: int32, glyph: int32, sizePx: float32, variant: int32): int32 {
	const r = glyphAtlas.acquire({ face: face, glyph: glyph, sizePx: sizePx, variant: variant });
	if (r.ok) { return r.value; }
	if (!atlasFullReported) {
		console.log(`void2d: glyph ${glyph} at ${sizePx} px has no room in the glyph atlas (${r.error.toString()})`);
		atlasFullReported = true;
	}
	return -1;
}

function uvRect(t: GlyphTile): [float32, float32, float32, float32] {
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
	const sizePx: float32 = entry.style.size * devicePerLocal;
	const fracX: float32 = fraction(world.tx * scale);
	const fracY: float32 = fraction(world.ty * scale);
	const placed: Vec<PlacedGlyph> = new Array(0);
	if (devicePerLocal > 0.0) {
		for (const g of entry.layout.glyphs) {
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
			const tileIndex: int32 = acquireOrReport(g.face, g.glyph, sizePx, variant);
			if (tileIndex < 0) { continue; }
			const t: GlyphTile = glyphAtlas.tile(tileIndex);
			const [u0, v0, u1, v1] = uvRect(t);
			const w: float32 = t.width as float32;
			const h: float32 = t.height as float32;
			if (pixelExact) {
				placed.push({
					tile: tileIndex, page: t.page,
					x: (whole + t.left) as float32, y: (baselineDevice + t.top) as float32,
					w: w, h: h, u0: u0, v0: v0, u1: u1, v1: v1,
				});
			} else {
				placed.push({
					tile: tileIndex, page: t.page,
					x: g.x + (t.left as float32) / devicePerLocal,
					y: baseline + (t.top as float32) / devicePerLocal,
					w: w / devicePerLocal, h: h / devicePerLocal,
					u0: u0, v0: v0, u1: u1, v1: v1,
				});
			}
		}
	}
	entry.placed = placed;
	entry.placedValid = true;
	entry.pixelExact = pixelExact;
	entry.keyA = world.a;
	entry.keyB = world.b;
	entry.keyC = world.c;
	entry.keyD = world.d;
	entry.keyScale = scale;
	entry.keyFracX = fracX;
	entry.keyFracY = fracY;
	return entry;
}
