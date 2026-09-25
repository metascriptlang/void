import {
	GlyphAtlas,
	GlyphTile,
	GlyphPage,
	GlyphPageHandle,
	GLYPH_PAGE_SIZE,
	quantizeX,
	snapBaseline,
} from "./glyphAtlas";
import { TextLayout, TextStyle } from "./textLayout";
import { Transform2D } from "./types";

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

export interface LabelText {
	layout: TextLayout;
	style: TextStyle;
	placed: Vec<PlacedGlyph>;
	placedValid: boolean;
	pixelExact: boolean;
	key: PlacementKey;
}

export const glyphAtlas: GlyphAtlas = GlyphAtlas.create(GLYPH_PAGE_SIZE, MAX_GLYPH_PAGES);
export const labelTexts: Vec<LabelText> = [];
const freeLabelTexts: Vec<int32> = [];

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
		style: {
			font: -1,
			size: 0.0,
			letterSpacing: 0.0,
			lineSpacing: 0.0,
			maxWidth: 0.0,
			align: 0.0,
		},
		placed: new Array(0),
		placedValid: false,
		pixelExact: false,
		key: NO_PLACEMENT_KEY,
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

export function shapeLabel(index: int32, text: string, style: TextStyle): void {
	const entry: LabelText = labelTexts[index];
	releasePlacement(entry);
	entry.style = style;
	entry.layout = TextLayout.layout(text, style);
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
	if (refused > 0) {
		console.log(
			`void2d: ${refused} of ${entry.layout.glyphs.length} glyphs of a label are not drawn, ` +
			`the glyph atlas refused them (${refusal})`,
		);
	}
	entry.placed = placed;
	entry.placedValid = true;
	entry.pixelExact = pixelExact;
	entry.key = placementKey(world, scale);
	return entry;
}
