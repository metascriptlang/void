import {
	Painter,
	spriteCanvasHeight,
	spriteCanvasWidth,
	spritePadding,
} from "./spriteDraw";
import {
	drawBlock,
	drawBox,
	drawBraille,
	drawGeometric,
	drawLegacyBlock,
	drawOctant,
	drawPowerline,
	drawSextant,
} from "./spriteFamilies";

export const SPRITE_FIRST_CODEPOINT: int32 = 0x2500;

export enum SpriteError {
	NoSuchSprite,
	BadCell,
	Geometry,
}

enum Family {
	Box,
	Block,
	Braille,
	Geometric,
	Powerline,
	Octant,
	Sextant,
	LegacyBlock,
}

struct SpriteRange {
	min: int32;
	max: int32;
	family: Family;
	first: int32;
}

const RANGES: SpriteRange[] = [
	{ min: 0x2500, max: 0x257F, family: Family.Box, first: 0 },
	{ min: 0x2580, max: 0x259F, family: Family.Block, first: 128 },
	{ min: 0x25E2, max: 0x25E5, family: Family.Geometric, first: 160 },
	{ min: 0x25F8, max: 0x25FA, family: Family.Geometric, first: 164 },
	{ min: 0x25FF, max: 0x25FF, family: Family.Geometric, first: 167 },
	{ min: 0x2800, max: 0x28FF, family: Family.Braille, first: 168 },
	{ min: 0xE0B0, max: 0xE0BF, family: Family.Powerline, first: 424 },
	{ min: 0xE0D2, max: 0xE0D2, family: Family.Powerline, first: 440 },
	{ min: 0xE0D4, max: 0xE0D4, family: Family.Powerline, first: 441 },
	{ min: 0x1CD00, max: 0x1CDE5, family: Family.Octant, first: 442 },
	{ min: 0x1FB00, max: 0x1FB3B, family: Family.Sextant, first: 672 },
	{ min: 0x1FB70, max: 0x1FB92, family: Family.LegacyBlock, first: 732 },
	{ min: 0x1FB94, max: 0x1FB97, family: Family.LegacyBlock, first: 767 },
];

export struct SpriteCanvas {
	pixels: uint8[];
	width: int32;
	height: int32;
	padX: int32;
	padY: int32;
}

export struct SpriteInk {
	left: int32;
	top: int32;
	right: int32;
	bottom: int32;
	pixels: uint8[];
	origin: int32;
	stride: int32;
}

class InkCache {
	id: int32 = 0;
	cellWidth: int32 = 0;
	cellHeight: int32 = 0;
	thickness: int32 = 0;
	valid: boolean = false;
	pixels: uint8[] = [];
	left: int32 = 0;
	top: int32 = 0;
	right: int32 = 0;
	bottom: int32 = 0;
}

const inkCache: InkCache = new InkCache();

function rangeOf(codepoint: int32): int32 {
	for (let i: int32 = 0; i < (RANGES.length as int32); i++) {
		if (codepoint >= RANGES[i].min && codepoint <= RANGES[i].max) { return i; }
	}
	return -1;
}

export function spriteCount(): int32 {
	const last: SpriteRange = RANGES[(RANGES.length as int32) - 1];
	return last.first + (last.max - last.min + 1);
}

export function spriteIndex(codepoint: int32): int32 {
	const r: int32 = rangeOf(codepoint);
	if (r < 0) { return 0; }
	return 1 + RANGES[r].first + (codepoint - RANGES[r].min);
}

export function spriteCodepoint(id: int32): int32 {
	if (id < 1 || id > spriteCount()) { return 0; }
	const at: int32 = id - 1;
	for (let i: int32 = (RANGES.length as int32) - 1; i >= 0; i--) {
		if (at >= RANGES[i].first) { return RANGES[i].min + (at - RANGES[i].first); }
	}
	return 0;
}

export function spriteTableFault(): int32 {
	let expectedFirst: int32 = 0;
	for (let i: int32 = 0; i < (RANGES.length as int32); i++) {
		if (RANGES[i].max < RANGES[i].min) { return i + 1; }
		if (i > 0 && RANGES[i].min <= RANGES[i - 1].max) { return i + 1; }
		if (RANGES[i].first != expectedFirst) { return i + 1; }
		expectedFirst += RANGES[i].max - RANGES[i].min + 1;
	}
	return 0;
}

function paint(painter: Painter, codepoint: int32, family: Family): boolean {
	let fits: boolean = true;
	match (family) {
		Family.Box => { drawBox(codepoint, painter); },
		Family.Block => { drawBlock(codepoint, painter); },
		Family.Braille => { fits = drawBraille(codepoint, painter); },
		Family.Geometric => { drawGeometric(codepoint, painter); },
		Family.Powerline => { drawPowerline(codepoint, painter); },
		Family.Octant => { drawOctant(codepoint, painter); },
		Family.Sextant => { drawSextant(codepoint, painter); },
		Family.LegacyBlock => { drawLegacyBlock(codepoint, painter); },
	}
	return fits && !painter.failed;
}

function drawId(
	id: int32, cellWidth: int32, cellHeight: int32, thickness: int32,
): Result<SpriteCanvas, SpriteError> {
	const codepoint: int32 = spriteCodepoint(id);
	if (codepoint == 0) { return Result.err(SpriteError.NoSuchSprite); }
	if (cellWidth < 1 || cellHeight < 1 || thickness < 1) {
		return Result.err(SpriteError.BadCell);
	}
	const painter: Painter = new Painter(cellWidth, cellHeight, thickness);
	if (!paint(painter, codepoint, RANGES[rangeOf(codepoint)].family)) {
		return Result.err(SpriteError.Geometry);
	}
	return Result.ok({
		pixels: painter.pixels,
		width: painter.width,
		height: painter.height,
		padX: spritePadding(cellWidth),
		padY: spritePadding(cellHeight),
	});
}

export function drawSprite(
	codepoint: int32, cellWidth: int32, cellHeight: int32, thickness: int32,
): Result<SpriteCanvas, SpriteError> {
	const id: int32 = spriteIndex(codepoint);
	if (id == 0) { return Result.err(SpriteError.NoSuchSprite); }
	return drawId(id, cellWidth, cellHeight, thickness);
}

function measureInk(cache: InkCache, canvasWidth: int32, canvasHeight: int32): void {
	let left: int32 = canvasWidth;
	let top: int32 = canvasHeight;
	let right: int32 = 0;
	let bottom: int32 = 0;
	for (let y: int32 = 0; y < canvasHeight; y++) {
		for (let x: int32 = 0; x < canvasWidth; x++) {
			if (cache.pixels[y * canvasWidth + x] == 0) { continue; }
			if (x < left) { left = x; }
			if (x + 1 > right) { right = x + 1; }
			if (y < top) { top = y; }
			if (y + 1 > bottom) { bottom = y + 1; }
		}
	}
	if (right <= left || bottom <= top) {
		left = 0;
		top = 0;
		right = 0;
		bottom = 0;
	}
	cache.left = left;
	cache.top = top;
	cache.right = right;
	cache.bottom = bottom;
}

// The ink box of a drawn sprite in cell coordinates and the rows that hold it. The last drawing is
// kept, so the rasterizer's per-glyph box and fill calls draw each sprite once.
export function spriteCanvasInk(
	id: int32, cellWidth: int32, cellHeight: int32, thickness: int32,
): Result<SpriteInk, SpriteError> {
	if (cellWidth < 1 || cellHeight < 1 || thickness < 1) {
		return Result.err(SpriteError.BadCell);
	}
	const canvasWidth: int32 = spriteCanvasWidth(cellWidth);
	const canvasHeight: int32 = spriteCanvasHeight(cellHeight);
	const cache: InkCache = inkCache;
	if (!(cache.valid && cache.id == id && cache.cellWidth == cellWidth &&
		cache.cellHeight == cellHeight && cache.thickness == thickness)) {
		cache.valid = false;
		const drawn: Result<SpriteCanvas, SpriteError> = drawId(id, cellWidth, cellHeight, thickness);
		if (!drawn.ok) { return Result.err(drawn.error); }
		cache.pixels = drawn.value.pixels;
		measureInk(cache, canvasWidth, canvasHeight);
		cache.id = id;
		cache.cellWidth = cellWidth;
		cache.cellHeight = cellHeight;
		cache.thickness = thickness;
		cache.valid = true;
	}
	if (cache.right <= cache.left) {
		return Result.ok({
			left: 0,
			top: 0,
			right: 0,
			bottom: 0,
			pixels: [],
			origin: 0,
			stride: 0,
		});
	}
	const padX: int32 = spritePadding(cellWidth);
	const padY: int32 = spritePadding(cellHeight);
	return Result.ok({
		left: cache.left - padX,
		top: cache.top - padY,
		right: cache.right - padX,
		bottom: cache.bottom - padY,
		pixels: cache.pixels,
		origin: cache.top * canvasWidth + cache.left,
		stride: canvasWidth,
	});
}
