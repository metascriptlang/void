import {
	void2dGlyphBox,
	void2dGlyphRasterize,
	void2dGlyphPageCreate,
	void2dGlyphPageClear,
} from "./glyph.h";

export const SUBPIXEL_VARIANTS: int32 = 4;
export const GLYPH_GUTTER: int32 = 1;
export const GLYPH_PAGE_SIZE: int32 = 1024;

export enum AtlasError {
	TooLarge,
	Full,
}

export struct GlyphKey {
	face: int32;
	glyph: int32;
	sizePx: float32;
	variant: int32;
}

export struct GlyphTile {
	page: int32;
	x: int32;
	y: int32;
	width: int32;
	height: int32;
	left: int32;
	top: int32;
	refs: int32;
	key: uint64;
}

export struct PixelPlacement {
	whole: int32;
	variant: int32;
}

struct Shelf {
	page: int32;
	y: int32;
	height: int32;
	cursor: int32;
}

struct AtlasPage {
	handle: int32;
	top: int32;
}

export interface GlyphAtlas {
	pageSize: int32;
	maxPages: int32;
	pages: Vec<AtlasPage>;
	shelves: Vec<Shelf>;
	tiles: Vec<GlyphTile>;
	freeTiles: Vec<int32>;
	index: Map<uint64, int32>;
	rasterizations: int32;
	reclaims: int32;
}

export function create(this typeof GlyphAtlas, pageSize: int32, maxPages: int32): GlyphAtlas {
	return {
		pageSize: pageSize,
		maxPages: maxPages,
		pages: new Array(0),
		shelves: new Array(0),
		tiles: new Array(0),
		freeTiles: new Array(0),
		index: new Map<uint64, int32>(),
		rasterizations: 0,
		reclaims: 0,
	};
}

export function quantizeX(deviceX: float32): PixelPlacement {
	const variants: float32 = SUBPIXEL_VARIANTS as float32;
	const quarters: int32 = Math.floor(deviceX * variants + 0.5) as int32;
	const whole: int32 = Math.floor((quarters as float32) / variants) as int32;
	return { whole: whole, variant: quarters - whole * SUBPIXEL_VARIANTS };
}

export function snapBaseline(deviceY: float32): int32 {
	return Math.floor(deviceY + 0.5) as int32;
}

export function packKey(key: GlyphKey): uint64 {
	const sizeQ: uint64 = (Math.floor(key.sizePx * 64.0 + 0.5) as int32) as uint64;
	return ((key.face as uint64) << 48) |
		((key.glyph as uint64) << 32) |
		(sizeQ << 8) |
		(key.variant as uint64);
}

export function tileSlots(this atlas: GlyphAtlas): int32 {
	return atlas.tiles.length as int32;
}

export function pageCount(this atlas: GlyphAtlas): int32 {
	return atlas.pages.length as int32;
}

export function pageHandle(this atlas: GlyphAtlas, page: int32): int32 {
	return atlas.pages[page].handle;
}

export function residentBytes(this atlas: GlyphAtlas): int32 {
	return (atlas.pages.length as int32) * atlas.pageSize * atlas.pageSize;
}

export function tile(this atlas: GlyphAtlas, index: int32): GlyphTile {
	return atlas.tiles[index];
}

export function release(this atlas: GlyphAtlas, index: int32): void {
	if (atlas.tiles[index].refs > 0) {
		atlas.tiles[index].refs = atlas.tiles[index].refs - 1;
	}
}

function liveTilesOn(atlas: GlyphAtlas, page: int32): int32 {
	let live: int32 = 0;
	for (let i = 0; i < (atlas.tiles.length as int32); i++) {
		if (atlas.tiles[i].page == page && atlas.tiles[i].refs > 0) { live = live + 1; }
	}
	return live;
}

function placeOnPage(
	atlas: GlyphAtlas,
	page: int32,
	width: int32,
	height: int32,
): [int32, int32] {
	const size: int32 = atlas.pageSize;
	for (let s = 0; s < (atlas.shelves.length as int32); s++) {
		const shelf: Shelf = atlas.shelves[s];
		const fits: boolean = shelf.page == page && height <= shelf.height &&
			height * 4 >= shelf.height * 3 && shelf.cursor + width <= size;
		if (fits) {
			atlas.shelves[s].cursor = shelf.cursor + width;
			return [shelf.cursor, shelf.y];
		}
	}
	const top: int32 = atlas.pages[page].top;
	if (top + height > size || width > size) { return [-1, -1]; }
	atlas.shelves.push({ page: page, y: top, height: height, cursor: width });
	atlas.pages[page].top = top + height;
	return [0, top];
}

function reclaimPage(atlas: GlyphAtlas): int32 {
	for (let p = 0; p < (atlas.pages.length as int32); p++) {
		if (liveTilesOn(atlas, p) != 0) { continue; }
		for (let i = 0; i < (atlas.tiles.length as int32); i++) {
			if (atlas.tiles[i].page == p) {
				atlas.index.delete(atlas.tiles[i].key);
				atlas.tiles[i].page = -1;
				atlas.tiles[i].refs = -1;
				atlas.freeTiles.push(i);
			}
		}
		const kept: Vec<Shelf> = new Array(0);
		for (const shelf of atlas.shelves) {
			if (shelf.page != p) { kept.push(shelf); }
		}
		atlas.shelves = kept;
		atlas.pages[p].top = 0;
		void2dGlyphPageClear(atlas.pages[p].handle);
		atlas.reclaims = atlas.reclaims + 1;
		return p;
	}
	return -1;
}

function allocate(
	atlas: GlyphAtlas,
	width: int32,
	height: int32,
): Result<[int32, int32, int32], AtlasError> {
	const w: int32 = width + GLYPH_GUTTER;
	const h: int32 = height + GLYPH_GUTTER;
	if (w > atlas.pageSize || h > atlas.pageSize) { return Result.err(AtlasError.TooLarge); }
	for (let p = 0; p < (atlas.pages.length as int32); p++) {
		const [x, y] = placeOnPage(atlas, p, w, h);
		if (x >= 0) { return Result.ok([p, x, y]); }
	}
	let page: int32 = -1;
	if ((atlas.pages.length as int32) < atlas.maxPages) {
		const handle: int32 = void2dGlyphPageCreate(atlas.pageSize);
		if (handle < 0) { return Result.err(AtlasError.Full); }
		atlas.pages.push({ handle: handle, top: 0 });
		page = (atlas.pages.length as int32) - 1;
	} else {
		page = reclaimPage(atlas);
		if (page < 0) { return Result.err(AtlasError.Full); }
	}
	const [x, y] = placeOnPage(atlas, page, w, h);
	return Result.ok([page, x, y]);
}

export function acquire(this atlas: GlyphAtlas, key: GlyphKey): Result<int32, AtlasError> {
	const packed: uint64 = packKey(key);
	const hit = atlas.index.get(packed);
	if (hit.present) {
		atlas.tiles[hit.value].refs = atlas.tiles[hit.value].refs + 1;
		return Result.ok(hit.value);
	}
	const shift: float32 = (key.variant as float32) / (SUBPIXEL_VARIANTS as float32);
	const box: Ptr<int32> = void2dGlyphBox(key.face, key.glyph, key.sizePx, shift);
	const left: int32 = box[0];
	const top: int32 = box[1];
	const width: int32 = box[2] - left;
	const height: int32 = box[3] - top;
	let page: int32 = -1;
	let x: int32 = 0;
	let y: int32 = 0;
	if (width > 0 && height > 0) {
		const placed = try allocate(atlas, width, height);
		page = placed[0];
		x = placed[1];
		y = placed[2];
		void2dGlyphRasterize(key.face, key.glyph, key.sizePx, shift,
			atlas.pages[page].handle, x, y, width, height);
	}
	atlas.rasterizations = atlas.rasterizations + 1;
	const record: GlyphTile = {
		page: page,
		x: x,
		y: y,
		width: width > 0 ? width : 0,
		height: height > 0 ? height : 0,
		left: left,
		top: top,
		refs: 1,
		key: packed,
	};
	let index: int32 = atlas.tiles.length as int32;
	if ((atlas.freeTiles.length as int32) > 0) {
		index = atlas.freeTiles.pop();
		atlas.tiles[index] = record;
	} else {
		atlas.tiles.push(record);
	}
	atlas.index.set(packed, index);
	return Result.ok(index);
}
